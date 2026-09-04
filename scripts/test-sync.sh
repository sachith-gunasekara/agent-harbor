#!/usr/bin/env bash
# test-sync.sh — tests for sync-mirrors.sh against local fixture repositories.
#
# Read-only with respect to this repository: every test runs in its own temporary
# directory with its own mirrors.yaml, lockfile and upstreams. Nothing here
# touches skills/ or mirrors.lock.json.
#
# Offline. MIRROR_GIT_BASE points sync-mirrors.sh at file:// fixtures instead of
# github.com, so the suite is fast and cannot fail because a real upstream moved.
#
# Usage:
#   test-sync.sh              run everything
#   test-sync.sh <name>...    run only tests whose name contains one of these
#
# Exit: 0 all passed, 1 one or more failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-}" in -h|--help) sed -n '2,17p' "$0"; exit 0 ;; esac

PASS=0
FAIL=0
FILTER=("$@")

ok()   { printf '  ok    %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

wanted_test() {
  [ ${#FILTER[@]} -eq 0 ] && return 0
  local f
  for f in "${FILTER[@]}"; do case "$1" in *"$f"*) return 0 ;; esac; done
  return 1
}

# --------------------------------------------------------------- fixtures
# A fake upstream repo containing one or more skills.
make_upstream() {
  local dir="$1"; shift
  mkdir -p "$dir"
  git init -q -b main "$dir"
  printf 'MIT License\n\nPermission is hereby granted, free of charge\n' > "$dir/LICENSE"
  local skill
  for skill in "$@"; do
    mkdir -p "$dir/skills/$skill"
    printf -- '---\nname: %s\ndescription: Fixture skill %s.\n---\n\n# %s\n' \
      "$skill" "$skill" "$skill" > "$dir/skills/$skill/SKILL.md"
  done
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm "fixture"
}

# A throwaway harbor: a git repo with the real scripts and a generated mirrors.yaml.
make_harbor() {
  local dir="$1"; shift
  mkdir -p "$dir/scripts" "$dir/skills/own" "$dir/skills/mirrored"
  cp "$REPO_ROOT/scripts/sync-mirrors.sh" "$dir/scripts/"
  git init -q -b main "$dir"
  {
    echo "version: 1"
    echo "defaults:"
    echo "  ref: main"
    echo "mirrors:"
    local entry
    for entry in "$@"; do
      echo "  - repo: ${entry%%:*}"
      echo "    skill: ${entry##*:}"
      echo "    license: MIT"
    done
  } > "$dir/mirrors.yaml"
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm "init"
}

# Rewrite the mirrors list of an existing harbor.
set_mirrors() {
  local dir="$1"; shift
  {
    echo "version: 1"
    echo "defaults:"
    echo "  ref: main"
    echo "mirrors:"
    if [ $# -eq 0 ]; then
      echo "  []"
    else
      local entry
      for entry in "$@"; do
        echo "  - repo: ${entry%%:*}"
        echo "    skill: ${entry##*:}"
        echo "    license: MIT"
      done
    fi
  } > "$dir/mirrors.yaml"
}

# Run the harbor's own copy of the script. sync-mirrors.sh resolves the repository
# from its own location, not from the working directory, so invoking the real one
# would operate on this repository no matter where we cd to.
sync() { local h="$1"; shift; MIRROR_GIT_BASE="$BASE" "$h/scripts/sync-mirrors.sh" "$@"; }

# ------------------------------------------------------------------ setup
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BASE="$TMP/upstreams"
mkdir -p "$BASE/acme"
make_upstream "$BASE/acme/tools.git" alpha beta

# ------------------------------------------------------------------ tests
t="vendors a newly declared skill"
if wanted_test "$t"; then
  H="$TMP/h1"; make_harbor "$H" "acme/tools:alpha"
  out="$(sync "$H" 2>&1)"
  if [ -f "$H/skills/mirrored/alpha/SKILL.md" ] && printf '%s' "$out" | grep -q '^new'; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

t="is idempotent when nothing changed"
if wanted_test "$t"; then
  H="$TMP/h2"; make_harbor "$H" "acme/tools:alpha"
  sync "$H" >/dev/null 2>&1
  git -C "$H" add -A && git -C "$H" -c user.email=t@t -c user.name=t commit -qm sync
  out="$(sync "$H" 2>&1)"
  if printf '%s' "$out" | grep -q 'unchanged' && [ -z "$(git -C "$H" status --porcelain)" ]; then
    ok "$t"
  else
    bad "$t (produced a diff or did not report unchanged)"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

# The behaviour this suite exists for.
t="removing a record deletes the vendored skill"
if wanted_test "$t"; then
  H="$TMP/h3"; make_harbor "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  if [ ! -d "$H/skills/mirrored/beta" ]; then
    bad "$t (setup: beta was never vendored)"
  else
    set_mirrors "$H" "acme/tools:alpha"
    out="$(sync "$H" 2>&1)"
    dir_gone=1; [ -d "$H/skills/mirrored/beta" ] && dir_gone=0
    lock_gone=1
    jq -e '.mirrors.beta' "$H/mirrors.lock.json" >/dev/null 2>&1 && lock_gone=0
    kept=0; [ -d "$H/skills/mirrored/alpha" ] && kept=1
    if [ "$dir_gone" -eq 1 ] && [ "$lock_gone" -eq 1 ] && [ "$kept" -eq 1 ] \
       && printf '%s' "$out" | grep -q '^removed .*beta'; then
      ok "$t"
    else
      bad "$t (dir_gone=$dir_gone lock_gone=$lock_gone alpha_kept=$kept)"
      printf '%s\n' "$out" | sed 's/^/        /' >&2
    fi
  fi
fi

t="removal is reported to the workflow as state=removed"
if wanted_test "$t"; then
  H="$TMP/h4"; make_harbor "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  set_mirrors "$H" "acme/tools:alpha"
  plan="$(sync "$H" --dry-run --json 2>/dev/null)"
  if printf '%s' "$plan" | jq -e '.[]|select(.name=="beta" and .state=="removed")' >/dev/null 2>&1; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$plan" | sed 's/^/        /' >&2
  fi
fi

t="removal of a single skill works under --skill"
if wanted_test "$t"; then
  H="$TMP/h5"; make_harbor "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  set_mirrors "$H" "acme/tools:alpha"
  sync "$H" --skill beta >/dev/null 2>&1
  if [ ! -d "$H/skills/mirrored/beta" ] && [ -d "$H/skills/mirrored/alpha" ]; then
    ok "$t"
  else
    bad "$t (the workflow opens one PR per skill, so --skill must handle removals)"
  fi
fi

t="a dry-run removal deletes nothing"
if wanted_test "$t"; then
  H="$TMP/h6"; make_harbor "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  set_mirrors "$H" "acme/tools:alpha"
  sync "$H" --dry-run >/dev/null 2>&1
  if [ -d "$H/skills/mirrored/beta" ] && jq -e '.mirrors.beta' "$H/mirrors.lock.json" >/dev/null 2>&1; then
    ok "$t"
  else
    bad "$t (--dry-run destroyed data)"
  fi
fi

t="a malformed entry never causes a removal"
if wanted_test "$t"; then
  H="$TMP/h7"; make_harbor "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  # beta loses its required license: it must be reported as an error, not pruned.
  {
    echo "version: 1"; echo "defaults:"; echo "  ref: main"; echo "mirrors:"
    echo "  - repo: acme/tools"; echo "    skill: alpha"; echo "    license: MIT"
    echo "  - repo: acme/tools"; echo "    skill: beta"
  } > "$H/mirrors.yaml"
  sync "$H" >/dev/null 2>&1
  if [ -d "$H/skills/mirrored/beta" ]; then
    ok "$t"
  else
    bad "$t (a typo deleted a mirror)"
  fi
fi

t="removing every record empties the mirror directory"
if wanted_test "$t"; then
  H="$TMP/h8"; make_harbor "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  set_mirrors "$H"
  sync "$H" >/dev/null 2>&1
  remaining="$(find "$H/skills/mirrored" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  locked="$(jq -r '.mirrors|length' "$H/mirrors.lock.json" 2>/dev/null || echo 0)"
  [ -n "$locked" ] || locked=0
  if [ "$remaining" = "0" ] && [ "$locked" = "0" ]; then
    ok "$t"
  else
    bad "$t (dirs=$remaining locked=$locked)"
  fi
fi

t="a re-added skill comes back"
if wanted_test "$t"; then
  H="$TMP/h9"; make_harbor "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  set_mirrors "$H" "acme/tools:alpha"
  sync "$H" >/dev/null 2>&1
  set_mirrors "$H" "acme/tools:alpha" "acme/tools:beta"
  sync "$H" >/dev/null 2>&1
  if [ -f "$H/skills/mirrored/beta/SKILL.md" ]; then ok "$t"; else bad "$t"; fi
fi

t="--verify fails after a hand-edit"
if wanted_test "$t"; then
  H="$TMP/h10"; make_harbor "$H" "acme/tools:alpha"
  sync "$H" >/dev/null 2>&1
  git -C "$H" add -A && git -C "$H" -c user.email=t@t -c user.name=t commit -qm sync
  echo "local edit" >> "$H/skills/mirrored/alpha/SKILL.md"
  if ! sync "$H" --verify >/dev/null 2>&1; then ok "$t"; else bad "$t (drift went undetected)"; fi
fi

t="--verify fails on an undeclared mirrored directory"
if wanted_test "$t"; then
  H="$TMP/h11"; make_harbor "$H" "acme/tools:alpha"
  sync "$H" >/dev/null 2>&1
  mkdir -p "$H/skills/mirrored/stowaway"
  printf -- '---\nname: stowaway\ndescription: x.\n---\n' > "$H/skills/mirrored/stowaway/SKILL.md"
  if ! sync "$H" --verify >/dev/null 2>&1; then ok "$t"; else bad "$t"; fi
fi

t="an unknown skill name is refused with the available list"
if wanted_test "$t"; then
  H="$TMP/h12"; make_harbor "$H" "acme/tools:nope"
  out="$(sync "$H" 2>&1)"
  if printf '%s' "$out" | grep -q 'no directory named' && printf '%s' "$out" | grep -q 'alpha'; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

t="an upstream change is detected"
if wanted_test "$t"; then
  H="$TMP/h13"; make_harbor "$H" "acme/tools:alpha"
  sync "$H" >/dev/null 2>&1
  printf '\nnew upstream line\n' >> "$BASE/acme/tools.git/skills/alpha/SKILL.md"
  git -C "$BASE/acme/tools.git" add -A
  git -C "$BASE/acme/tools.git" -c user.email=t@t -c user.name=t commit -qm "upstream change"
  out="$(sync "$H" 2>&1)"
  if printf '%s' "$out" | grep -q '^changed' && grep -q 'new upstream line' "$H/skills/mirrored/alpha/SKILL.md"; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

# ----------------------------------------------------------------- report
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
