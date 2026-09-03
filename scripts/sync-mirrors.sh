#!/usr/bin/env bash
# sync-mirrors.sh — vendor the upstream skills declared in mirrors.yaml into
# skills/mirrored/, and record their provenance in mirrors.lock.json.
#
# Writes to the working tree (skills/mirrored/ and mirrors.lock.json). It never
# commits, branches, or pushes — the workflow does that. Use --dry-run to preview.
#
# Change detection is a git tree hash, not a diff: `git rev-parse <commit>:<path>`
# is the content hash of a directory, and git tree hashes are path-independent, so
# the upstream subtree and our copy hash identically exactly when their contents
# match. Unchanged skills are skipped and produce no output to commit.
#
# Because of that, a mirrored directory must stay byte-identical to upstream.
# Nothing is injected into it — provenance lives in mirrors.lock.json instead.
#
# Entries name a repo and a skill, not a path. The skill is located the way an
# installer locates it: the directory called <skill> that contains a SKILL.md.
# An explicit 'path:' is only needed to break a tie in a repo that has more than
# one directory by that name.
#
# Usage:
#   sync-mirrors.sh                  sync every entry in mirrors.yaml
#   sync-mirrors.sh --dry-run        report what would change, write nothing
#   sync-mirrors.sh --skill NAME     limit to one mirror (repeatable)
#   sync-mirrors.sh --force          re-materialise even when already up to date
#   sync-mirrors.sh --verify         read-only: mirrored dirs still match the lock
#   sync-mirrors.sh --json           machine-readable summary on stdout
#
# Exit: 0 all good, 1 a mirror failed (or --verify found drift), 2 bad usage.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO_ROOT/mirrors.yaml"
LOCK="$REPO_ROOT/mirrors.lock.json"
MIRROR_DIR="skills/mirrored"

DRY_RUN=0
FORCE=0
VERIFY=0
JSON=0
ONLY=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --verify) VERIFY=1 ;;
    --json) JSON=1 ;;
    --skill) shift; [ $# -gt 0 ] || { echo "--skill needs a name" >&2; exit 2; }; ONLY+=("$1") ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { [ "$JSON" -eq 1 ] && return 0; printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() { printf '%s\n' "$*" >&2; exit 1; }

command -v git >/dev/null || die "git is required"
command -v yq >/dev/null || die "yq is required to read mirrors.yaml — install it with 'brew install yq' (see https://github.com/mikefarah/yq)"
[ -f "$CONFIG" ] || die "no mirrors.yaml at $CONFIG"

cd "$REPO_ROOT" || die "cannot cd to $REPO_ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# Content hash of a directory as it exists in the working tree. Uses a scratch
# index and --force so that .gitignore can never quietly drop a mirrored file and
# make an out-of-date copy look identical to upstream.
dir_tree_oid() {
  local dir="$1" tmpd idx oid
  [ -d "$dir" ] || return 1
  # git refuses a zero-byte index, so point GIT_INDEX_FILE at a path that does
  # not exist yet rather than at a file mktemp already created.
  tmpd="$(mktemp -d)" || return 1
  idx="$tmpd/index"
  GIT_INDEX_FILE="$idx" git add --force -A -- "$dir" >/dev/null 2>&1 || { rm -rf "$tmpd"; return 1; }
  oid="$(GIT_INDEX_FILE="$idx" git write-tree --prefix="$dir" 2>/dev/null)"
  rm -rf "$tmpd"
  [ -n "$oid" ] || return 1
  printf '%s' "$oid"
}

# Resolve a branch / tag / SHA to a concrete commit without cloning.
resolve_commit() {
  local repo="$1" ref="$2" url out
  if printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$'; then printf '%s' "$ref"; return 0; fi
  url="https://github.com/${repo}.git"
  if [ "$ref" = "HEAD" ]; then
    out="$(git ls-remote "$url" HEAD 2>/dev/null | head -n1 | cut -f1)"
  else
    # Prefer the dereferenced tag (^{}) so annotated tags resolve to their commit.
    out="$(git ls-remote "$url" "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}" 2>/dev/null \
      | awk '/\^\{\}$/ {deref=$1} !/\^\{\}$/ && !first {first=$1} END {print (deref ? deref : first)}')"
  fi
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# Shallow, blobless fetch with no checkout. Trees come down but blobs do not, so
# the repository layout can be inspected before deciding what to materialise.
fetch_repo() {
  local repo="$1" commit="$2" dest="$3"
  git init -q "$dest" >/dev/null 2>&1 || return 1
  git -C "$dest" remote add origin "https://github.com/${repo}.git" >/dev/null 2>&1 || return 1
  git -C "$dest" fetch -q --depth 1 --filter=blob:none origin "$commit" >/dev/null 2>&1 || return 1
  return 0
}

# Locate a skill by name, the way an installer does: find the directory called
# <skill> that contains a SKILL.md. Prints every match, one per line, so the
# caller can distinguish "not found" from "ambiguous".
find_skill_paths() {
  local dest="$1" commit="$2" skill="$3"
  git -C "$dest" ls-tree -r --name-only "$commit" 2>/dev/null \
    | grep -E "(^|/)${skill}/SKILL\.md$" \
    | sed 's|/SKILL\.md$||'
}

# Materialise one directory out of an already-fetched repo.
checkout_path() {
  local dest="$1" commit="$2" path="$3"
  git -C "$dest" sparse-checkout init --cone >/dev/null 2>&1
  git -C "$dest" sparse-checkout set "$path" >/dev/null 2>&1
  git -C "$dest" checkout -q "$commit" >/dev/null 2>&1 || return 1
  return 0
}

# Best-effort SPDX guess from an upstream LICENSE file, used only to flag a
# mismatch with what mirrors.yaml claims. Never authoritative.
detect_license() {
  local root="$1" f body
  for f in LICENSE LICENSE.md LICENSE.txt COPYING; do
    [ -f "$root/$f" ] || continue
    body="$(head -c 4000 "$root/$f" 2>/dev/null)"
    case "$body" in
      *"Apache License"*) printf 'Apache-2.0'; return 0 ;;
      *"MIT License"*|*"Permission is hereby granted, free of charge"*) printf 'MIT'; return 0 ;;
      *"GNU GENERAL PUBLIC LICENSE"*) printf 'GPL'; return 0 ;;
      *"BSD"*) printf 'BSD'; return 0 ;;
      *) printf 'UNKNOWN'; return 0 ;;
    esac
  done
  return 1
}

lock_get() {
  local name="$1" field="$2"
  [ -f "$LOCK" ] || return 1
  jq -r --arg n "$name" --arg f "$field" '.mirrors[$n][$f] // empty' "$LOCK" 2>/dev/null
}

wanted() {
  local name="$1" n
  [ ${#ONLY[@]} -eq 0 ] && return 0
  for n in "${ONLY[@]}"; do [ "$n" = "$name" ] && return 0; done
  return 1
}

COUNT="$(yq '.mirrors | length' "$CONFIG" 2>/dev/null)"
[ -n "$COUNT" ] && [ "$COUNT" != "null" ] || COUNT=0

DEFAULT_REF="$(yq -r '.defaults.ref // "HEAD"' "$CONFIG" 2>/dev/null)"
[ -n "$DEFAULT_REF" ] && [ "$DEFAULT_REF" != "null" ] || DEFAULT_REF="HEAD"

STATUS=0
RESULTS=()          # name<TAB>state<TAB>repo<TAB>path<TAB>old_commit<TAB>new_commit
CHANGED_NAMES=()
declare -a SEEN_NAMES=()

record() { RESULTS+=("$1	$2	$3	$4	$5	$6"); }

# ---------------------------------------------------------------- verify mode
if [ "$VERIFY" -eq 1 ]; then
  if [ ! -f "$LOCK" ]; then
    if [ -d "$MIRROR_DIR" ] && [ -n "$(find "$MIRROR_DIR" -name SKILL.md -print -quit 2>/dev/null)" ]; then
      die "mirrored skills exist but there is no mirrors.lock.json"
    fi
    say "no mirrors locked; nothing to verify"
    exit 0
  fi
  DRIFT=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    wanted "$name" || continue
    want="$(lock_get "$name" tree)"
    dir="$MIRROR_DIR/$name"
    if [ ! -d "$dir" ]; then
      warn "MISSING  $name — locked but $dir does not exist"
      DRIFT=1; continue
    fi
    have="$(dir_tree_oid "$dir")"
    if [ "$have" != "$want" ]; then
      warn "DRIFT    $name — $dir does not match the lockfile"
      warn "         locked $want"
      warn "         actual ${have:-<unreadable>}"
      DRIFT=1
    else
      say "ok       $name"
    fi
  done < <(jq -r '.mirrors | keys[]' "$LOCK" 2>/dev/null)

  # A mirrored directory nobody declared is also drift.
  if [ -d "$MIRROR_DIR" ]; then
    while IFS= read -r dir; do
      name="$(basename "$dir")"
      if [ -z "$(lock_get "$name" tree)" ]; then
        warn "UNTRACKED $name — $MIRROR_DIR/$name is not in mirrors.lock.json"
        DRIFT=1
      fi
    done < <(find "$MIRROR_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  fi

  if [ "$DRIFT" -ne 0 ]; then
    warn ""
    warn "Mirrored skills are copies of upstream and must not be edited here."
    warn "To diverge, fork the skill into skills/own/ and remove its mirrors.yaml entry."
    warn "To adopt an intentional upstream change, run: ./scripts/sync-mirrors.sh"
    exit 1
  fi
  say "all mirrored skills match mirrors.lock.json"
  exit 0
fi

# ------------------------------------------------------------------ sync mode
[ "$COUNT" -eq 0 ] && say "mirrors.yaml declares no mirrors"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

i=0
while [ "$i" -lt "$COUNT" ]; do
  idx=$i; i=$((i + 1))

  repo="$(yq -r ".mirrors[$idx].repo // \"\"" "$CONFIG")"
  skill="$(yq -r ".mirrors[$idx].skill // \"\"" "$CONFIG")"
  path="$(yq -r ".mirrors[$idx].path // \"\"" "$CONFIG")"
  name="$(yq -r ".mirrors[$idx].name // \"\"" "$CONFIG")"
  ref="$(yq -r ".mirrors[$idx].ref // \"\"" "$CONFIG")"
  license="$(yq -r ".mirrors[$idx].license // \"\"" "$CONFIG")"

  path="${path%/}"
  [ -n "$name" ] || name="$skill"
  [ -n "$ref" ] || ref="$DEFAULT_REF"

  # ---- preflight ---------------------------------------------------------
  if [ -z "$repo" ] || [ -z "$skill" ]; then
    warn "ERROR    mirrors[$idx]: 'repo' and 'skill' are required"; STATUS=1; continue
  fi
  if ! printf '%s' "$skill" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    warn "ERROR    $skill: skill name must be lowercase letters, digits and hyphens"
    STATUS=1; continue
  fi
  if ! printf '%s' "$repo" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; then
    warn "ERROR    $repo: not a valid owner/name"; STATUS=1; continue
  fi
  if ! printf '%s' "$name" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    warn "ERROR    $name: mirror name must be lowercase, digits and hyphens"; STATUS=1; continue
  fi
  if [ -z "$license" ]; then
    warn "ERROR    $name: 'license' is required — you are redistributing $repo, so the"
    warn "         upstream license has to be declared and reproduced in NOTICE.md"
    STATUS=1; continue
  fi
  if [ -d "skills/own/$name" ]; then
    warn "ERROR    $name: collides with skills/own/$name — rename the mirror with 'name:'"
    STATUS=1; continue
  fi
  for s in ${SEEN_NAMES[@]+"${SEEN_NAMES[@]}"}; do
    if [ "$s" = "$name" ]; then
      warn "ERROR    $name: declared twice in mirrors.yaml — set a distinct 'name:'"
      STATUS=1; continue 2
    fi
  done
  SEEN_NAMES+=("$name")

  wanted "$name" || continue

  # ---- resolve + fetch ---------------------------------------------------
  commit="$(resolve_commit "$repo" "$ref")"
  if [ -z "$commit" ]; then
    warn "ERROR    $name: cannot resolve ref '$ref' in $repo"; STATUS=1; continue
  fi

  old_commit="$(lock_get "$name" commit)"
  dest="$MIRROR_DIR/$name"
  local_tree="$(dir_tree_oid "$dest" 2>/dev/null || true)"

  work="$TMP_ROOT/$name"
  if ! fetch_repo "$repo" "$commit" "$work"; then
    warn "ERROR    $name: failed to fetch $repo@${commit:0:7}"; STATUS=1; continue
  fi

  # Find the skill by name, the way an installer does. An explicit 'path:' is
  # only needed to break a tie when a repo has several directories by that name.
  if [ -z "$path" ]; then
    matches="$(find_skill_paths "$work" "$commit" "$skill")"
    count="$(printf '%s' "$matches" | grep -c . || true)"
    if [ "$count" -eq 0 ]; then
      warn "ERROR    $skill: no directory named '$skill' with a SKILL.md in $repo@${commit:0:7}"
      warn "         available skills:"
      git -C "$work" ls-tree -r --name-only "$commit" 2>/dev/null \
        | grep -E '(^|/)SKILL\.md$' | sed 's|/SKILL\.md$||' | sed 's|.*/||' \
        | sort -u | head -30 | sed 's/^/           /' >&2
      STATUS=1; continue
    fi
    if [ "$count" -gt 1 ]; then
      warn "ERROR    $skill: ambiguous — $repo@${commit:0:7} has $count directories named '$skill':"
      printf '%s\n' "$matches" | sed 's/^/           /' >&2
      warn "         disambiguate with an explicit 'path:' on this entry"
      STATUS=1; continue
    fi
    path="$matches"
  fi

  upstream_tree="$(git -C "$work" rev-parse "$commit:$path" 2>/dev/null)"
  if [ -z "$upstream_tree" ]; then
    warn "ERROR    $name: '$path' does not exist in $repo@${commit:0:7}"; STATUS=1; continue
  fi

  if ! checkout_path "$work" "$commit" "$path"; then
    warn "ERROR    $name: failed to check out '$path' from $repo@${commit:0:7}"; STATUS=1; continue
  fi
  if [ ! -f "$work/$path/SKILL.md" ]; then
    warn "ERROR    $name: $repo/$path has no SKILL.md — that is not a skill directory"
    STATUS=1; continue
  fi

  detected="$(detect_license "$work" || true)"
  if [ -z "$detected" ]; then
    warn "WARNING  $name: no LICENSE file found in $repo — mirrors.yaml claims $license."
    warn "         Confirm you actually have the right to redistribute this."
  elif [ "$detected" != "UNKNOWN" ] && [ "${license%%-*}" != "${detected%%-*}" ]; then
    warn "WARNING  $name: mirrors.yaml says $license but $repo's LICENSE looks like $detected"
  fi

  # ---- compare -----------------------------------------------------------
  if [ "$upstream_tree" = "$local_tree" ] && [ "$FORCE" -eq 0 ]; then
    # Contents already match; refresh the lock only if its metadata drifted.
    if [ "$(lock_get "$name" commit)" = "$commit" ] && [ "$(lock_get "$name" tree)" = "$upstream_tree" ]; then
      say "unchanged $name  ($repo@${commit:0:7})"
      record "$name" unchanged "$repo" "$path" "$old_commit" "$commit"
      continue
    fi
    say "relock   $name  ($repo@${commit:0:7}) — contents identical, lock metadata refreshed"
    state=relock
  elif [ -z "$local_tree" ]; then
    say "new      $name  <- $repo/$path @ ${commit:0:7}"
    state=new
  else
    say "changed  $name  <- $repo/$path @ ${commit:0:7}${old_commit:+ (was ${old_commit:0:7})}"
    state=changed
  fi

  record "$name" "$state" "$repo" "$path" "$old_commit" "$commit"
  CHANGED_NAMES+=("$name")

  [ "$DRY_RUN" -eq 1 ] && continue

  # ---- materialise -------------------------------------------------------
  # Replace wholesale so upstream deletions propagate instead of lingering.
  rm -rf "$dest"
  mkdir -p "$dest"
  if ! (cd "$work/$path" && tar cf - .) | (cd "$dest" && tar xf -); then
    warn "ERROR    $name: failed to copy $path into $dest"; STATUS=1; continue
  fi

  written_tree="$(dir_tree_oid "$dest")"
  if [ "$written_tree" != "$upstream_tree" ]; then
    warn "ERROR    $name: copy does not hash to the upstream tree"
    warn "         upstream $upstream_tree"
    warn "         written  ${written_tree:-<unreadable>}"
    STATUS=1; continue
  fi

  homepage="$(yq -r ".mirrors[$idx].homepage // \"\"" "$CONFIG")"
  notes="$(yq -r ".mirrors[$idx].notes // \"\"" "$CONFIG")"
  [ -n "$homepage" ] || homepage="https://github.com/$repo"

  [ -f "$LOCK" ] || printf '{\n  "version": 1,\n  "mirrors": {}\n}\n' > "$LOCK"
  tmp_lock="$(mktemp)"
  # `path` is recorded even though it is no longer declared: it is where the skill
  # was actually found upstream, which is what the catalog links to and what makes
  # a later move visible in the diff.
  jq --sort-keys \
     --arg n "$name" --arg repo "$repo" --arg skill "$skill" --arg path "$path" \
     --arg ref "$ref" \
     --arg commit "$commit" --arg tree "$upstream_tree" --arg license "$license" \
     --arg homepage "$homepage" --arg notes "$notes" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.version = 1
      | .mirrors[$n] = {
          repo: $repo, skill: $skill, path: $path, ref: $ref,
          commit: $commit, tree: $tree,
          license: $license, homepage: $homepage, notes: $notes, synced_at: $at
        }' "$LOCK" > "$tmp_lock" && mv "$tmp_lock" "$LOCK"
done

# ------------------------------------------------- prune undeclared mirrors
# Only safe when every entry parsed cleanly: an entry that failed preflight never
# made it into SEEN_NAMES, and pruning on that basis would delete a mirror because
# of a typo rather than because someone asked for its removal.
if [ "$STATUS" -ne 0 ]; then
  warn ""
  warn "skipping removal of undeclared mirrors — some entries in mirrors.yaml failed"
  warn "to parse, and treating them as 'removed' would delete a mirror by accident."
elif [ -f "$LOCK" ]; then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # Honour --skill here too, so the workflow can raise a removal PR for a single
    # dropped mirror the same way it raises an update PR for a changed one.
    wanted "$name" || continue
    declared=0
    for s in ${SEEN_NAMES[@]+"${SEEN_NAMES[@]}"}; do [ "$s" = "$name" ] && declared=1 && break; done
    [ "$declared" -eq 1 ] && continue

    say "removed  $name  — no longer declared in mirrors.yaml"
    record "$name" removed "$(lock_get "$name" repo)" "$(lock_get "$name" path)" "$(lock_get "$name" commit)" ""
    CHANGED_NAMES+=("$name")
    [ "$DRY_RUN" -eq 1 ] && continue

    rm -rf "${MIRROR_DIR:?}/$name"
    tmp_lock="$(mktemp)"
    jq --sort-keys --arg n "$name" 'del(.mirrors[$n])' "$LOCK" > "$tmp_lock" && mv "$tmp_lock" "$LOCK"
  done < <(jq -r '.mirrors | keys[]' "$LOCK" 2>/dev/null)
fi

# ------------------------------------------------------------------- report
if [ "$JSON" -eq 1 ]; then
  printf '%s\n' "${RESULTS[@]:-}" | jq -R -s -c '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({name: .[0], state: .[1], repo: .[2], path: .[3],
         old_commit: .[4], new_commit: .[5]})'
else
  if [ ${#CHANGED_NAMES[@]} -eq 0 ]; then
    say ""
    say "everything up to date"
  elif [ "$DRY_RUN" -eq 1 ]; then
    say ""
    say "${#CHANGED_NAMES[@]} mirror(s) would change: ${CHANGED_NAMES[*]}"
    say "re-run without --dry-run to apply"
  else
    say ""
    say "${#CHANGED_NAMES[@]} mirror(s) updated: ${CHANGED_NAMES[*]}"
    say "run ./scripts/gen-catalog.sh to refresh the README, catalog and NOTICE"
  fi
fi

exit "$STATUS"
