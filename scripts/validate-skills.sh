#!/usr/bin/env bash
# validate-skills.sh — check every skill in this repo is well-formed and installable.
#
# Read-only. Runs over skills/own/ and skills/mirrored/ alike, because a mirrored
# skill that fails these checks would break discovery for the whole repo just as
# badly as one written here — better to catch it while reviewing the mirror PR.
#
# Checks, per skill:
#   - SKILL.md exists and has a --- delimited frontmatter block
#   - frontmatter parses and carries `name` and `description`
#   - `name` matches the directory name and is lowercase/digits/hyphens
#   - `description` is non-empty and under 1024 characters
#   - `name` is unique across the whole repo
#   - every scripts/ or references/ path mentioned in SKILL.md exists
#   - every scripts/*.sh passes `bash -n` and has its executable bit set
#
# Usage:
#   validate-skills.sh              check everything
#   validate-skills.sh <dir>...     check only the given skill directories
#
# Exit: 0 clean, 1 one or more problems found.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || { echo "cannot cd to $REPO_ROOT" >&2; exit 1; }

MAX_DESC=1024
ERRORS=0
CHECKED=0

case "${1:-}" in
  -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
esac

fail() { printf 'FAIL  %s\n' "$*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { printf 'WARN  %s\n' "$*" >&2; }

# Print the frontmatter block (between the first two --- lines) of a SKILL.md.
frontmatter() {
  awk 'NR==1 && $0 != "---" { exit 1 }
       NR==1 { next }
       /^---[[:space:]]*$/ { exit 0 }
       { print }' "$1"
}

# Read one scalar key out of a frontmatter block. Prefers yq; falls back to a
# narrow awk reader so the script still works without yq installed.
fm_get() {
  local file="$1" key="$2" fm
  fm="$(frontmatter "$file")" || return 1
  if command -v yq >/dev/null 2>&1; then
    printf '%s\n' "$fm" | yq -r ".$key // \"\"" 2>/dev/null
  else
    printf '%s\n' "$fm" | awk -v k="$key" '
      $0 ~ "^" k ":" { sub("^" k ":[[:space:]]*", ""); val=$0; found=1; next }
      found && /^[[:space:]]+/ { sub("^[[:space:]]+", " "); val = val $0; next }
      found && /^[^[:space:]]/ { exit }
      END { if (found) print val }'
  fi
}

if [ $# -gt 0 ]; then
  SKILL_DIRS=("$@")
else
  SKILL_DIRS=()
  while IFS= read -r f; do
    SKILL_DIRS+=("$(dirname "$f")")
  done < <(find skills -name SKILL.md -type f 2>/dev/null | sort)
fi

if [ ${#SKILL_DIRS[@]} -eq 0 ]; then
  echo "no skills found under skills/" >&2
  exit 1
fi

NAMES_SEEN=""

for dir in "${SKILL_DIRS[@]}"; do
  dir="${dir%/}"
  skill_md="$dir/SKILL.md"
  base="$(basename "$dir")"
  CHECKED=$((CHECKED + 1))

  if [ ! -f "$skill_md" ]; then
    fail "$dir: no SKILL.md"
    continue
  fi

  if ! frontmatter "$skill_md" >/dev/null 2>&1; then
    fail "$dir: SKILL.md does not start with a '---' frontmatter block"
    continue
  fi

  name="$(fm_get "$skill_md" name)"
  desc="$(fm_get "$skill_md" description)"

  if [ -z "$name" ]; then
    fail "$dir: frontmatter has no 'name'"
  else
    if [ "$name" != "$base" ]; then
      fail "$dir: frontmatter name '$name' does not match directory name '$base'"
    fi
    if ! printf '%s' "$name" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
      fail "$dir: name '$name' must be lowercase letters, digits and hyphens"
    fi
    case " $NAMES_SEEN " in
      *" $name "*)
        fail "$dir: duplicate skill name '$name' — names must be unique across skills/own/ and skills/mirrored/, since that is what an installer resolves"
        ;;
      *) NAMES_SEEN="$NAMES_SEEN $name" ;;
    esac
  fi

  if [ -z "$desc" ]; then
    fail "$dir: frontmatter has no 'description'"
  else
    len=${#desc}
    if [ "$len" -gt "$MAX_DESC" ]; then
      fail "$dir: description is $len characters, over the $MAX_DESC limit"
    fi
  fi

  # Referenced paths must exist. Only flag paths that look like real file
  # references (they have an extension) to avoid tripping on prose like
  # "scripts/ directory".
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ ! -e "$dir/$p" ]; then
      fail "$dir: SKILL.md references '$p' which does not exist"
    fi
  done < <(grep -oE '(scripts|references|assets)/[A-Za-z0-9._/-]+\.[A-Za-z0-9]+' "$skill_md" 2>/dev/null | sort -u)

  # Shell scripts must parse and be executable.
  while IFS= read -r sh; do
    [ -n "$sh" ] || continue
    if ! bash -n "$sh" 2>/dev/null; then
      fail "$sh: bash syntax error"
    fi
    if [ ! -x "$sh" ]; then
      if [[ "$dir" == skills/mirrored/* ]]; then
        warn "$sh: not executable (upstream's choice — mirrored verbatim, not fixed here)"
      else
        fail "$sh: not executable — run 'chmod +x $sh', the bit is tracked by git"
      fi
    fi
  done < <(find "$dir" -name '*.sh' -type f 2>/dev/null | sort)
done

echo "checked $CHECKED skill(s)"
if [ "$ERRORS" -ne 0 ]; then
  echo "$ERRORS problem(s) found" >&2
  exit 1
fi
echo "all skills valid"
