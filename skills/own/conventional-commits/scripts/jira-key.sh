#!/usr/bin/env bash
# jira-key.sh — resolve the Jira issue key for the current work.
# Read-only. Prints the key on stdout (or nothing) and the reasoning on stderr.
#
# Resolution order: branch name -> commits on this branch -> $JIRA_ISSUE_KEY
#
# Usage:
#   jira-key.sh                 print the best key, or exit 1 if none found
#   jira-key.sh --explain       show every candidate and where it came from
#   jira-key.sh --validate KEY  check that KEY matches Jira's required format
#
# Jira's key format is strict: two or more UPPERCASE letters, a hyphen, digits.

set -uo pipefail

KEY_RE='[A-Z][A-Z0-9]+-[0-9]+'
EXPLAIN=0

case "${1:-}" in
  --validate)
    CAND="${2:-}"
    if printf '%s' "$CAND" | grep -qE "^${KEY_RE}$"; then
      echo "valid: $CAND"; exit 0
    else
      echo "INVALID: '$CAND' — Jira needs 2+ uppercase letters, a hyphen, then digits (e.g. PROJ-123)." >&2
      exit 1
    fi
    ;;
  --explain) EXPLAIN=1 ;;
  -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
  "") ;;
  *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 1; }

note() { [ "$EXPLAIN" -eq 1 ] && echo "$*" >&2 || true; }

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

# 1. Branch name. Uppercase first so feature/proj-123-foo still matches, but
#    report it as a normalisation so the user can confirm the casing.
FROM_BRANCH="$(printf '%s' "$BRANCH" | grep -oE "$KEY_RE" | head -n1)"
if [ -z "$FROM_BRANCH" ]; then
  UPPER="$(printf '%s' "$BRANCH" | tr '[:lower:]' '[:upper:]')"
  CAND="$(printf '%s' "$UPPER" | grep -oE "$KEY_RE" | head -n1)"
  if [ -n "$CAND" ]; then
    FROM_BRANCH="$CAND"
    note "branch:  $CAND  (branch was lowercase '$BRANCH' — uppercased; confirm before use)"
  fi
else
  note "branch:  $FROM_BRANCH  (from '$BRANCH')"
fi
[ -z "$FROM_BRANCH" ] && note "branch:  (no key in '$BRANCH')"

# 2. Commits already on this branch but not on its upstream / default base.
FROM_LOG=""
BASE="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$BASE" ]; then
  for b in origin/main origin/master main master develop; do
    git rev-parse --verify -q "$b" >/dev/null 2>&1 && { BASE="$b"; break; }
  done
fi
if [ -n "$BASE" ]; then
  FROM_LOG="$(git log --no-color --pretty=format:'%B' "${BASE}..HEAD" 2>/dev/null | grep -oE "$KEY_RE" | sort | uniq -c | sort -rn | head -n1 | awk '{print $2}')"
fi
[ -z "$FROM_LOG" ] && FROM_LOG="$(git log --no-color --pretty=format:'%B' -n 10 2>/dev/null | grep -oE "$KEY_RE" | head -n1)"
[ -n "$FROM_LOG" ] && note "history: $FROM_LOG  (from commits on this branch)" || note "history: (no key on recent commits)"

# 3. Environment.
FROM_ENV="$(printf '%s' "${JIRA_ISSUE_KEY:-}" | grep -oE "^${KEY_RE}$" || true)"
[ -n "$FROM_ENV" ] && note "env:     $FROM_ENV  (\$JIRA_ISSUE_KEY)" || note "env:     (JIRA_ISSUE_KEY unset or malformed)"

for K in "$FROM_BRANCH" "$FROM_LOG" "$FROM_ENV"; do
  if [ -n "$K" ]; then
    echo "$K"
    exit 0
  fi
done

echo "No Jira key found. Ask the user for it, or commit without one." >&2
exit 1
