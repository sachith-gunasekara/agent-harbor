#!/usr/bin/env bash
# repo-conventions.sh — mine the repo for the conventions it already follows.
# Read-only.
#
# Usage:
#   repo-conventions.sh            sample the last 100 commits
#   repo-conventions.sh -n 300     widen the sample

set -uo pipefail

N=100
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--number) N="${2:-100}"; shift ;;
    -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 1; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

hr() { printf '\n=== %s ===\n' "$1"; }

SUBJECTS="$(git log --no-color --no-merges --pretty=format:'%s' -n "$N" 2>/dev/null)"
BODIES="$(git log --no-color --no-merges --pretty=format:'%B%n---COMMIT---' -n "$N" 2>/dev/null)"
# Body only (%b) — excludes the subject, so subject prefixes like "chore:" are
# not mistaken for footer trailer tokens.
BODY_ONLY="$(git log --no-color --no-merges --pretty=format:'%b%n---COMMIT---' -n "$N" 2>/dev/null)"

hr "CONVENTIONAL ADHERENCE (last $N non-merge commits)"
TOTAL=$(printf '%s\n' "$SUBJECTS" | grep -c . || true)
CONV=$(printf '%s\n' "$SUBJECTS" | grep -cE '^[a-zA-Z]+(\([^)]+\))?!?: .+' || true)
echo "conventional: ${CONV}/${TOTAL}"
if [ "$TOTAL" -gt 0 ] && [ "$CONV" -lt $((TOTAL / 2)) ]; then
  echo "NOTE: this repo mostly does NOT use conventional commits."
  echo "      Confirm with the user before introducing the format."
fi

hr "TYPES IN USE"
printf '%s\n' "$SUBJECTS" \
  | grep -oE '^[a-zA-Z]+(\([^)]+\))?!?:' \
  | sed -E 's/\(.*//; s/!?:$//' \
  | sort | uniq -c | sort -rn || echo "(none found)"

hr "SCOPES IN USE"
SCOPES="$(printf '%s\n' "$SUBJECTS" | grep -oE '^[a-zA-Z]+\([^)]+\)' | sed -E 's/^[a-zA-Z]+\(//; s/\)$//' | sort | uniq -c | sort -rn)"
[ -n "$SCOPES" ] && echo "$SCOPES" || echo "(no scopes used — plain 'type: description' is the house style)"

hr "HEADER LENGTH"
printf '%s\n' "$SUBJECTS" | awk '{ n=length($0); if(n>max) max=n; sum+=n; c++ } END { if(c) printf "count %d, mean %.0f, max %d\n", c, sum/c, max }'

hr "FOOTER TOKENS IN USE"
FOOTERS="$(printf '%s\n' "$BODY_ONLY" | grep -oE '^[A-Za-z][A-Za-z0-9-]*(: | #)' | sed -E 's/(: | #)$//' | sort | uniq -c | sort -rn | head -n 15)"
[ -n "$FOOTERS" ] && echo "$FOOTERS" || echo "(no trailers found in recent history)"

hr "JIRA KEYS SEEN IN HISTORY"
KEYS="$(printf '%s\n' "$BODIES" | grep -oE '\b[A-Z][A-Z0-9]+-[0-9]+\b' | sed -E 's/-[0-9]+$//' | sort | uniq -c | sort -rn | head -n 10)"
if [ -n "$KEYS" ]; then
  echo "project keys (count, key):"
  echo "$KEYS"
  echo
  echo "where the key usually sits:"
  IN_SUBJ=$(printf '%s\n' "$SUBJECTS" | grep -cE '\b[A-Z][A-Z0-9]+-[0-9]+\b' || true)
  echo "  in subject line: ${IN_SUBJ}/${TOTAL}"
  printf '%s\n' "$BODY_ONLY" | grep -oE '^[A-Za-z][A-Za-z0-9-]*(: | #)[[:space:]]*[A-Z][A-Z0-9]+-[0-9]+' \
    | sed -E 's/(: | #).*//' | sort | uniq -c | sort -rn \
    | awk '{ printf "  in trailer %-16s %s commit(s)\n", $2":", $1 }' || true
else
  echo "(no Jira-style keys found — repo may not be Jira-linked)"
fi

hr "TOOLING CONFIG"
found=0
for f in commitlint.config.js commitlint.config.cjs commitlint.config.mjs commitlint.config.ts \
         .commitlintrc .commitlintrc.json .commitlintrc.yml .commitlintrc.yaml .commitlintrc.js \
         .czrc .cz.json .versionrc .versionrc.json release.config.js .releaserc .releaserc.json \
         .releaserc.yml .gitmessage .gitmessage.txt CONTRIBUTING.md CONTRIBUTING.rst; do
  if [ -f "$ROOT/$f" ]; then echo "found: $f"; found=1; fi
done
[ -d "$ROOT/.husky" ] && { echo "found: .husky/ (git hooks)"; found=1; }
[ -d "$ROOT/.changeset" ] && { echo "found: .changeset/"; found=1; }
if [ -f "$ROOT/package.json" ]; then
  grep -qE '"(commitlint|commitizen|semantic-release|standard-version|@commitlint/[a-z-]+)"' "$ROOT/package.json" 2>/dev/null \
    && { echo "found: commit tooling declared in package.json"; found=1; }
fi
TEMPLATE="$(git config --get commit.template 2>/dev/null || true)"
[ -n "$TEMPLATE" ] && { echo "found: commit.template -> $TEMPLATE"; found=1; }
[ "$found" -eq 0 ] && echo "(no commit tooling config detected)"

if [ -f "$ROOT/CONTRIBUTING.md" ]; then
  hr "CONTRIBUTING.md — commit-related lines"
  grep -inE 'commit|conventional|jira|ticket|issue key' "$ROOT/CONTRIBUTING.md" | head -n 20 || echo "(nothing relevant)"
fi

hr "SUMMARY"
echo "Match the dominant type/scope vocabulary and footer token above."
echo "If commitlint is configured, read its config — its type-enum is authoritative."
