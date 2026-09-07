#!/usr/bin/env bash
# test-init-template.sh — tests for init-template.sh.
#
# Read-only with respect to this repository. Each test copies the working tree
# into a throwaway git repo and rebrands that, so nothing here can rewrite the
# real README or manifests — which is the one mistake this script could make
# that would be tedious to undo.
#
# Offline. No network, no gh, no upstreams.
#
# Usage:
#   test-init-template.sh              run everything
#   test-init-template.sh <name>...    run only tests whose name contains one of these
#
# Exit: 0 all passed, 1 one or more failed.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-}" in -h|--help) sed -n '2,17p' "$0"; exit 0 ;; esac

PASS=0
FAIL=0
FILTER=("$@")

ok()  { printf '  ok    %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL  %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

wanted_test() {
  [ ${#FILTER[@]} -eq 0 ] && return 0
  local f
  for f in "${FILTER[@]}"; do case "$1" in *"$f"*) return 0 ;; esac; done
  return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A throwaway copy of this repo, tracked by git so `git ls-files` sees everything.
# Copies the working tree rather than HEAD so the tests exercise the script as it
# is right now, not as it was last committed.
make_copy() {
  local dir="$1"
  mkdir -p "$dir"
  # Tracked files plus anything new that is not ignored, so the suite exercises
  # the script as it stands in the working tree — including before it is added.
  (cd "$REPO_ROOT" && git ls-files -z --cached --others --exclude-standard \
    | tar -cf - --null -T -) | tar -xf - -C "$dir"
  [ -x "$dir/scripts/init-template.sh" ] || {
    echo "copy is missing an executable scripts/init-template.sh" >&2; exit 1; }
  git init -q -b main "$dir"
  git -C "$dir" add -A
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm "copy"
  git -C "$dir" remote add origin "git@github.com:ada/my-harbor.git"
}

init() { local d="$1"; shift; (cd "$d" && ./scripts/init-template.sh "$@") 2>&1; }

# Every mention of the source repo, outside the two places that keep it on purpose.
leftovers() {
  local d="$1"
  (cd "$d" && git ls-files \
    | grep -v '^skills/mirrored/' | grep -v '^LICENSE$' \
    | xargs grep -lF 'sachith-gunasekara/agent-harbor' 2>/dev/null \
    | grep -v '^README.md$')
}

# ------------------------------------------------------------------ tests
t="rebrands slug, plugin name and owner"
if wanted_test "$t"; then
  D="$TMP/t1"; make_copy "$D"
  out="$(init "$D" --repo ada/my-harbor --owner-name "Ada Lovelace" --email ada@example.com --yes)"
  left="$(leftovers "$D")"
  if [ -z "$left" ] \
    && [ "$(jq -r '.name' "$D/.claude-plugin/marketplace.json")" = "my-harbor" ] \
    && [ "$(jq -r '.owner.name' "$D/.claude-plugin/marketplace.json")" = "Ada Lovelace" ] \
    && [ "$(jq -r '.owner.email' "$D/.claude-plugin/marketplace.json")" = "ada@example.com" ] \
    && [ "$(jq -r '.plugins[0].homepage' "$D/.claude-plugin/marketplace.json")" = "https://github.com/ada/my-harbor" ] \
    && [ "$(jq -r '.homepage' "$D/.claude-plugin/plugin.json")" = "https://github.com/ada/my-harbor" ] \
    && grep -q 'npx skills add ada/my-harbor' "$D/README.md" \
    && ! grep -q 'Sachith' "$D/docs/skill-library.md"; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
    [ -n "$left" ] && printf '        leftovers: %s\n' "$left" >&2
  fi
fi

t="leaves LICENSE and skills/mirrored untouched"
if wanted_test "$t"; then
  D="$TMP/t2"; make_copy "$D"
  init "$D" --repo ada/my-harbor --owner-name "Ada Lovelace" --yes >/dev/null
  # The copy was committed clean, so anything the script touched shows up here.
  dirty="$(cd "$D" && git status --porcelain -- skills/mirrored LICENSE)"
  if [ -z "$dirty" ] && grep -q 'Sachith Gunasekara' "$D/LICENSE"; then
    ok "$t"
  else
    bad "$t"; printf '        touched: %s\n' "$dirty" >&2
  fi
fi

t="the rebranded repo still passes its own checks"
if wanted_test "$t"; then
  D="$TMP/t3"; make_copy "$D"
  init "$D" --repo ada/my-harbor --owner-name "Ada Lovelace" --yes >/dev/null
  cat_out="$(cd "$D" && ./scripts/gen-catalog.sh --check 2>&1)"; cat_rc=$?
  ver_out="$(cd "$D" && ./scripts/sync-mirrors.sh --verify 2>&1)"; ver_rc=$?
  val_out="$(cd "$D" && ./scripts/validate-skills.sh 2>&1)"; val_rc=$?
  if [ "$cat_rc" -eq 0 ] && [ "$ver_rc" -eq 0 ] && [ "$val_rc" -eq 0 ]; then
    ok "$t"
  else
    bad "$t (gen-catalog $cat_rc, verify $ver_rc, validate $val_rc)"
    printf '%s\n%s\n%s\n' "$cat_out" "$ver_out" "$val_out" | sed 's/^/        /' >&2
  fi
fi

t="credits the source repo in the README"
if wanted_test "$t"; then
  D="$TMP/t4"; make_copy "$D"
  init "$D" --repo ada/my-harbor --owner-name "Ada Lovelace" --yes >/dev/null
  D2="$TMP/t4b"; make_copy "$D2"
  init "$D2" --repo ada/my-harbor --owner-name "Ada Lovelace" --no-attribution --yes >/dev/null
  if grep -qF 'github.com/sachith-gunasekara/agent-harbor' "$D/README.md" \
    && ! grep -qF 'sachith-gunasekara' "$D2/README.md"; then
    ok "$t"
  else
    bad "$t"
  fi
fi

t="--dry-run writes nothing"
if wanted_test "$t"; then
  D="$TMP/t5"; make_copy "$D"
  out="$(init "$D" --repo ada/my-harbor --owner-name "Ada Lovelace" --dry-run)"
  if [ -z "$(cd "$D" && git status --porcelain)" ] \
    && printf '%s' "$out" | grep -q 'nothing written'; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

t="refuses to rewrite unattended without --yes"
if wanted_test "$t"; then
  D="$TMP/t6"; make_copy "$D"
  out="$(init "$D" --repo ada/my-harbor --owner-name "Ada Lovelace" < /dev/null)"
  if [ -z "$(cd "$D" && git status --porcelain)" ] \
    && printf '%s' "$out" | grep -q 'Refusing'; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

t="is a no-op when the slug already matches"
if wanted_test "$t"; then
  D="$TMP/t7"; make_copy "$D"
  out="$(init "$D" --repo sachith-gunasekara/agent-harbor --yes)"
  if [ -z "$(cd "$D" && git status --porcelain)" ] \
    && printf '%s' "$out" | grep -q 'nothing to rebrand'; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

t="--fresh empties the skills and the lockfile"
if wanted_test "$t"; then
  D="$TMP/t8"; make_copy "$D"
  init "$D" --repo ada/my-harbor --owner-name "Ada Lovelace" --fresh --yes >/dev/null
  cat_out="$(cd "$D" && ./scripts/gen-catalog.sh --check 2>&1)"; cat_rc=$?
  ver_out="$(cd "$D" && ./scripts/sync-mirrors.sh --verify 2>&1)"; ver_rc=$?
  if [ -z "$(find "$D/skills/own" -mindepth 1 -maxdepth 1 -type d)" ] \
    && [ -z "$(find "$D/skills/mirrored" -mindepth 1 -maxdepth 1 -type d)" ] \
    && [ "$(jq -r '.mirrors | length' "$D/mirrors.lock.json")" = "0" ] \
    && grep -q 'None yet' "$D/README.md" \
    && [ "$cat_rc" -eq 0 ] && [ "$ver_rc" -eq 0 ]; then
    ok "$t"
  else
    bad "$t"; printf '%s\n%s\n' "$cat_out" "$ver_out" | sed 's/^/        /' >&2
  fi
fi

t="guesses the repo from the origin remote"
if wanted_test "$t"; then
  D="$TMP/t9"; make_copy "$D"
  out="$(init "$D" --owner-name "Ada Lovelace" --dry-run)"
  if printf '%s' "$out" | grep -q 'ada/my-harbor'; then
    ok "$t"
  else
    bad "$t"; printf '%s\n' "$out" | sed 's/^/        /' >&2
  fi
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
