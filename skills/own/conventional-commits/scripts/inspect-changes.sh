#!/usr/bin/env bash
# inspect-changes.sh — survey the repo before writing a commit message.
# Read-only. Safe to run at any time.
#
# Usage:
#   inspect-changes.sh                 staged changes only (default)
#   inspect-changes.sh --all           staged + unstaged + untracked
#   inspect-changes.sh --diff          include bounded patch text
#   inspect-changes.sh --log 20        number of recent commits to show (default 12)
#   inspect-changes.sh --max-diff 800  max diff lines to print (default 400)

set -uo pipefail

SCOPE="staged"
SHOW_DIFF=0
LOG_N=12
MAX_DIFF=400

while [ $# -gt 0 ]; do
  case "$1" in
    --all)      SCOPE="all" ;;
    --staged)   SCOPE="staged" ;;
    --diff)     SHOW_DIFF=1 ;;
    --log)      LOG_N="${2:-12}"; shift ;;
    --max-diff) MAX_DIFF="${2:-400}"; shift ;;
    -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 1; }

hr() { printf '\n=== %s ===\n' "$1"; }

hr "BRANCH"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '(detached)')"
echo "branch:   $BRANCH"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -n "$UPSTREAM" ]; then
  echo "upstream: $UPSTREAM"
  echo "ahead/behind: $(git rev-list --left-right --count "${UPSTREAM}...HEAD" 2>/dev/null | awk '{print "behind "$1", ahead "$2}')"
else
  echo "upstream: (none)"
fi
if [ -n "$(git rev-parse -q --verify MERGE_HEAD 2>/dev/null)" ]; then
  echo "state:    MERGE IN PROGRESS"
fi
if [ -d "$(git rev-parse --git-path rebase-merge 2>/dev/null)" ] || [ -d "$(git rev-parse --git-path rebase-apply 2>/dev/null)" ]; then
  echo "state:    REBASE IN PROGRESS"
fi

hr "STATUS (porcelain)"
STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [ -z "$STATUS" ]; then
  echo "(clean working tree — nothing to commit)"
else
  echo "$STATUS"
fi

hr "STAGED FILES"
if git diff --cached --quiet 2>/dev/null; then
  echo "(nothing staged)"
else
  git diff --cached --stat
  echo
  git diff --cached --name-status
fi

if [ "$SCOPE" = "all" ]; then
  hr "UNSTAGED FILES"
  if git diff --quiet 2>/dev/null; then
    echo "(no unstaged modifications)"
  else
    git diff --stat
  fi

  hr "UNTRACKED FILES"
  UNTRACKED="$(git ls-files --others --exclude-standard)"
  [ -n "$UNTRACKED" ] && echo "$UNTRACKED" || echo "(none)"
fi

if [ "$SHOW_DIFF" -eq 1 ]; then
  hr "PATCH (truncated to ${MAX_DIFF} lines)"
  if [ "$SCOPE" = "all" ]; then
    DIFF_CMD=(git diff HEAD --no-color)
  else
    DIFF_CMD=(git diff --cached --no-color)
  fi
  "${DIFF_CMD[@]}" | head -n "$MAX_DIFF"
  TOTAL=$("${DIFF_CMD[@]}" | wc -l | tr -d ' ')
  if [ "$TOTAL" -gt "$MAX_DIFF" ]; then
    echo "... [truncated: ${TOTAL} diff lines total; re-run with --max-diff or diff specific paths]"
  fi
fi

hr "RECENT COMMITS (style reference)"
git log --no-color --pretty=format:'%h %s' -n "$LOG_N" 2>/dev/null || echo "(no commits yet)"
echo

hr "COMMITS ON THIS BRANCH vs UPSTREAM"
if [ -n "$UPSTREAM" ]; then
  git log --no-color --pretty=format:'%h %s' "${UPSTREAM}..HEAD" 2>/dev/null | head -n 20
  echo
else
  echo "(no upstream to compare against)"
fi
