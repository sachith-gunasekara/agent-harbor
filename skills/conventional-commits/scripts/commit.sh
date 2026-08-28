#!/usr/bin/env bash
# commit.sh — assemble a Conventional Commit message and create the commit.
# The only script here that writes. Use --dry-run first for anything non-trivial.
#
# Usage:
#   commit.sh --type <type> --desc "<description>" [options]
#
# Options:
#   --type   <t>      feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert
#                     (override the allowed set with CC_TYPES="a b c")
#   --scope  <s>      optional noun for the area touched, e.g. auth, parser
#   --desc   <d>      imperative, lowercase, no trailing period
#   --body   <b>      why the change was made; repeat the flag for extra paragraphs
#   --breaking <b>    adds `!` to the header and a BREAKING CHANGE footer
#   --jira   <KEY>    issue key -> emitted as a trailer (default token: Refs)
#   --trailer-key <t> footer token for the Jira key (Refs, Ticket, Jira, Issue...)
#   --footer "K: V"   any extra trailer; repeatable
#   --smart-commit "<cmds>"  appends "KEY #cmds" as its own line (needs --jira)
#   --wrap   <n>      wrap body paragraphs at n columns (default 72, 0 disables)
#   --no-wrap         leave body paragraphs exactly as given
#   --amend           amend the previous commit instead of creating one
#   --all             stage tracked modifications first (never touches untracked)
#   --signoff         add Signed-off-by
#   --no-verify       skip hooks (avoid; hooks usually run the repo's commitlint)
#   --dry-run         print the message and exit without committing
#   --type-list       print the allowed types and exit

set -uo pipefail

DEFAULT_TYPES="feat fix docs style refactor perf test build ci chore revert"
TYPES="${CC_TYPES:-$DEFAULT_TYPES}"
MAX_HEADER="${CC_MAX_HEADER:-72}"
WRAP="${CC_WRAP:-72}"

TYPE=""; SCOPE=""; DESC=""; BREAKING=""; JIRA=""; SMART=""
TRAILER_KEY="${CC_TRAILER_KEY:-Refs}"
AMEND=0; STAGE_ALL=0; DRY=0; SIGNOFF=0; NO_VERIFY=0
BODY_PARTS=(); FOOTERS=()

die() { echo "error: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --type)          TYPE="${2:-}"; shift ;;
    --scope)         SCOPE="${2:-}"; shift ;;
    --desc|--subject) DESC="${2:-}"; shift ;;
    --body)          BODY_PARTS+=("${2:-}"); shift ;;
    --breaking)      BREAKING="${2:-}"; shift ;;
    --jira|--issue)  JIRA="${2:-}"; shift ;;
    --trailer-key)   TRAILER_KEY="${2:-}"; shift ;;
    --footer)        FOOTERS+=("${2:-}"); shift ;;
    --smart-commit)  SMART="${2:-}"; shift ;;
    --wrap)          WRAP="${2:-72}"; shift ;;
    --no-wrap)       WRAP=0 ;;
    --amend)         AMEND=1 ;;
    --all|-a)        STAGE_ALL=1 ;;
    --signoff|-s)    SIGNOFF=1 ;;
    --no-verify)     NO_VERIFY=1 ;;
    --dry-run|-n)    DRY=1 ;;
    --type-list)     echo "$TYPES" | tr ' ' '\n'; exit 0 ;;
    -h|--help)       sed -n '2,26p' "$0"; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# ---------- validation ----------
[ -n "$TYPE" ] || die "--type is required (see --type-list)"
[ -n "$DESC" ] || die "--desc is required"

TYPE_LC="$(printf '%s' "$TYPE" | tr '[:upper:]' '[:lower:]')"
case " $TYPES " in
  *" $TYPE_LC "*) ;;
  *) die "type '$TYPE' is not in the allowed set: $TYPES
       (if this repo genuinely uses it, re-run with CC_TYPES=\"$TYPES $TYPE_LC\")" ;;
esac
TYPE="$TYPE_LC"

case "$DESC" in
  *.) die "description must not end with a period" ;;
esac
printf '%s' "$DESC" | grep -qE '^[A-Z][a-z]' && \
  echo "warning: description starts with a capital — most repos keep it lowercase" >&2

if [ -n "$SCOPE" ]; then
  printf '%s' "$SCOPE" | grep -qE '^[A-Za-z0-9_./-]+$' || \
    die "scope '$SCOPE' should be a single noun without spaces or parentheses"
fi

if [ -n "$JIRA" ]; then
  printf '%s' "$JIRA" | grep -qE '^[A-Z][A-Z0-9]+-[0-9]+$' || \
    die "Jira key '$JIRA' is malformed — Jira only matches 2+ UPPERCASE letters, hyphen, digits (PROJ-123)"
fi
printf '%s' "$TRAILER_KEY" | grep -qE '^[A-Za-z][A-Za-z0-9-]*$' || \
  die "trailer token '$TRAILER_KEY' must be one word using '-' instead of spaces"
[ -n "$SMART" ] && [ -z "$JIRA" ] && die "--smart-commit needs --jira"

printf '%s' "$WRAP" | grep -qE '^[0-9]+$' || \
  die "--wrap takes a column count (0 disables wrapping)"
[ "$WRAP" -ne 0 ] && [ "$WRAP" -lt 40 ] && die "--wrap $WRAP is too narrow to be readable"

# ---------- header ----------
BANG=""
[ -n "$BREAKING" ] && BANG="!"
SCOPE_PART=""
[ -n "$SCOPE" ] && SCOPE_PART="($SCOPE)"
HEADER="${TYPE}${SCOPE_PART}${BANG}: ${DESC}"

HLEN=${#HEADER}
if [ "$HLEN" -gt "$MAX_HEADER" ]; then
  echo "warning: header is ${HLEN} chars (target <= ${MAX_HEADER}). Move detail into the body." >&2
fi

# ---------- body wrapping ----------
# Git tooling assumes a wrapped body: `git log` indents the message by four spaces,
# and an unwrapped paragraph forces horizontal scrolling in most viewers and diffs
# badly when the message is later edited. Wrapping is greedy at word boundaries.
# Passed through untouched: blank lines, fenced code blocks, indented lines, list
# items, quotes, and any single word longer than the limit — URLs, paths and SHAs
# are never broken. A second argument indents every line after the first, which is
# what a multi-line footer value needs.
wrap_paragraph() {
  local width="$1" indent="${2:-}"
  awk -v width="$width" -v indent="$indent" '
    function emit(s) { if (started) print indent s; else { print s; started = 1 } }
    function flush() { if (buf != "") { emit(buf); buf = "" } }
    {
      if ($0 ~ /^[ \t]*```/)                     { flush(); fence = !fence; emit($0); next }
      if (fence)                                 { emit($0); next }
      if ($0 ~ /^[ \t]*$/)                       { flush(); print ""; next }
      if ($0 ~ /^([ \t]{2,}|\t)/)                { flush(); emit($0); next }
      if ($0 ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) { flush(); emit($0); next }
      if ($0 ~ /^[ \t]*>/)                       { flush(); emit($0); next }
      for (i = 1; i <= NF; i++) {
        lim = width - (started ? length(indent) : 0)
        if (buf == "")                           buf = $i
        else if (length(buf) + 1 + length($i) <= lim) buf = buf " " $i
        else                                     { emit(buf); buf = $i }
      }
    }
    END { flush() }
  '
}

# ---------- assemble ----------
MSG="$(mktemp)"
trap 'rm -f "$MSG" "$MSG.new"' EXIT

printf '%s\n' "$HEADER" > "$MSG"
for p in "${BODY_PARTS[@]:-}"; do
  [ -n "$p" ] || continue
  printf '\n' >> "$MSG"
  if [ "$WRAP" -gt 0 ]; then
    printf '%s\n' "$p" | wrap_paragraph "$WRAP" >> "$MSG"
  else
    printf '%s\n' "$p" >> "$MSG"
  fi
done

# The footer block is written directly rather than through git-interpret-trailers.
# That tool refuses tokens containing whitespace, and mangles "BREAKING CHANGE:"
# into "BREAKING CHANGE: <value>: " — but the spec requires that exact spaced,
# uppercase token. BREAKING CHANGE leads the block, then any extra footers, then
# the issue reference last so it is easy to spot at the bottom of the message.
FOOTER_LINES=()
# BREAKING CHANGE is the one footer whose value may span lines, and the only one
# worth wrapping: its spaced token already stops git parsing the block as trailers,
# so continuation lines cost nothing that was not lost already. They are indented
# so changelog parsers read them as part of the same note.
if [ -n "$BREAKING" ]; then
  if [ "$WRAP" -gt 0 ]; then
    while IFS= read -r bcline; do FOOTER_LINES+=("$bcline"); done < <(
      printf 'BREAKING CHANGE: %s\n' "$BREAKING" | wrap_paragraph "$WRAP" "  "
    )
  else
    FOOTER_LINES+=("BREAKING CHANGE: ${BREAKING}")
  fi
fi
for f in "${FOOTERS[@]:-}"; do
  if [ -n "$f" ]; then
    printf '%s' "$f" | grep -qE '^[A-Za-z][A-Za-z0-9-]*(: | #)' || \
      die "footer '$f' is not a valid trailer — use 'Token: value' or 'Token #value', with '-' instead of spaces in the token"
    [ "$WRAP" -gt 0 ] && [ "${#f}" -gt "$WRAP" ] && \
      echo "warning: footer is ${#f} chars and cannot be wrapped — a trailer must stay on one line" >&2
    FOOTER_LINES+=("$f")
  fi
done
[ -n "$JIRA" ] && FOOTER_LINES+=("${TRAILER_KEY}: ${JIRA}")

if [ "${#FOOTER_LINES[@]}" -gt 0 ]; then
  printf '\n' >> "$MSG"
  for line in "${FOOTER_LINES[@]}"; do
    printf '%s\n' "$line" >> "$MSG"
  done
fi

# A Smart Commit command must be one unwrapped line containing the key, so it is
# appended raw rather than as a trailer.
if [ -n "$SMART" ]; then
  printf '\n%s %s\n' "$JIRA" "$SMART" >> "$MSG"
fi

echo "--- commit message ---"
cat "$MSG"
echo "--- end ---"

if [ "$DRY" -eq 1 ]; then
  echo
  echo "(dry run — nothing committed)"
  exit 0
fi

# ---------- commit ----------
[ "$STAGE_ALL" -eq 1 ] && git add -u

if [ "$AMEND" -eq 0 ] && git diff --cached --quiet 2>/dev/null; then
  die "nothing staged. Stage the specific files for this logical change first."
fi

ARGS=(commit -F "$MSG")
[ "$AMEND" -eq 1 ] && ARGS+=(--amend)
[ "$SIGNOFF" -eq 1 ] && ARGS+=(--signoff)
[ "$NO_VERIFY" -eq 1 ] && ARGS+=(--no-verify)

git "${ARGS[@]}" || die "git commit failed (a hook may have rejected the message)"

echo
git --no-pager log -1 --stat --pretty=format:'%h %s%n'
