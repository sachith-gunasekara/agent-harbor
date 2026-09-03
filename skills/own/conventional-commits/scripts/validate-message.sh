#!/usr/bin/env bash
# validate-message.sh — lint a commit message against Conventional Commits v1.0.0
# plus the Jira-key rule. Read-only.
#
# Usage:
#   validate-message.sh HEAD            check the last commit
#   validate-message.sh HEAD~3..HEAD    check a range
#   validate-message.sh path/to/msg.txt check a message file
#   cat msg.txt | validate-message.sh - check stdin
#
#   --require-jira    fail (not warn) when no Jira key is present
#   --max-header N    header length limit (default 72)
#   --max-body N      body line length limit (default 100)
#
# Exit 0 = clean, 1 = errors found.

set -uo pipefail

TYPES="${CC_TYPES:-feat fix docs style refactor perf test build ci chore revert}"
MAX_HEADER="${CC_MAX_HEADER:-72}"
MAX_BODY="${CC_BODY_WRAP:-100}"
REQUIRE_JIRA=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --require-jira) REQUIRE_JIRA=1 ;;
    --max-header)   MAX_HEADER="${2:-72}"; shift ;;
    --max-body)     MAX_BODY="${2:-100}"; shift ;;
    -h|--help)      sed -n '2,15p' "$0"; exit 0 ;;
    *)              TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || TARGET="HEAD"

ERRORS=0
WARNS=0
err()  { echo "  ERROR: $*"; ERRORS=$((ERRORS+1)); }
warn() { echo "  warn:  $*"; WARNS=$((WARNS+1)); }
ok()   { echo "  ok:    $*"; }

check_message() {
  local msg="$1" label="$2"
  echo "--- $label"

  local header rest
  header="$(printf '%s\n' "$msg" | head -n1)"
  rest="$(printf '%s\n' "$msg" | tail -n +2)"

  # 1. Header structure.
  if printf '%s' "$header" | grep -qE '^[a-zA-Z]+(\([^)]+\))?!?: .+'; then
    ok "header structure"
  else
    err "header does not match '<type>[(scope)][!]: <description>' -> $header"
    return
  fi

  local type
  type="$(printf '%s' "$header" | sed -E 's/^([a-zA-Z]+).*/\1/')"
  printf '%s' "$type" | grep -qE '^[a-z]+$' || warn "type '$type' is not lowercase"
  case " $TYPES " in
    *" $(printf '%s' "$type" | tr '[:upper:]' '[:lower:]') "*) ok "type '$type'" ;;
    *) err "type '$type' is not one of: $TYPES" ;;
  esac

  local desc
  desc="$(printf '%s' "$header" | sed -E 's/^[a-zA-Z]+(\([^)]+\))?!?: //')"
  [ -n "$desc" ] || err "empty description"
  case "$desc" in *.) err "description ends with a period" ;; esac
  printf '%s' "$desc" | grep -qE '^[A-Z][a-z]' && warn "description starts with a capital letter"
  printf '%s' "$desc" | grep -qiE '^(added|fixed|updated|changed|removed) ' && \
    warn "description is past tense — use the imperative ('add', not 'added')"

  local hlen=${#header}
  if [ "$hlen" -le "$MAX_HEADER" ]; then ok "header length ${hlen}"
  else warn "header is ${hlen} chars (target <= ${MAX_HEADER})"; fi

  # 2. Blank line before the body.
  if [ -n "$(printf '%s' "$rest" | tr -d '[:space:]')" ]; then
    local second
    second="$(printf '%s\n' "$msg" | sed -n '2p')"
    [ -z "$second" ] && ok "blank line after header" || err "body/footer must be separated from the header by a blank line"
  fi

  # 3. Body line length.
  # Skipped: fenced code, indented lines, footers, and any line of a single word,
  # since a bare URL or path is longer than the limit and must not be broken.
  if [ -n "$(printf '%s' "$rest" | tr -d '[:space:]')" ]; then
    local nlong=0 longest=0 fence=0 line len
    while IFS= read -r line; do
      case "$line" in '```'*) fence=$((1-fence)); continue ;; esac
      [ "$fence" -eq 1 ] && continue
      case "$line" in '    '*|'	'*) continue ;; esac
      printf '%s' "$line" | grep -qE '^(BREAKING[ -]CHANGE|[A-Za-z][A-Za-z0-9-]*)(: | #)' && continue
      [ "$(printf '%s' "$line" | wc -w)" -le 1 ] && continue
      len=${#line}
      if [ "$len" -gt "$MAX_BODY" ]; then
        nlong=$((nlong+1))
        [ "$len" -gt "$longest" ] && longest="$len"
      fi
    done <<< "$rest"
    if [ "$nlong" -eq 0 ]; then
      ok "body line length"
    else
      warn "${nlong} body line(s) over ${MAX_BODY} columns (longest ${longest}) — wrap the body"
    fi
  fi

  # 4. Breaking change consistency.
  local has_bang=0 has_bc=0
  printf '%s' "$header" | grep -qE '^[a-zA-Z]+(\([^)]+\))?!:' && has_bang=1
  printf '%s\n' "$msg" | grep -qE '^BREAKING[ -]CHANGE: .+' && has_bc=1
  if printf '%s\n' "$msg" | grep -qiE '^breaking[ -]change:' && [ "$has_bc" -eq 0 ]; then
    err "BREAKING CHANGE token must be uppercase"
  fi
  if [ "$has_bang" -eq 1 ] && [ "$has_bc" -eq 0 ]; then
    ok "breaking flagged with '!' (footer optional when the description explains it)"
  elif [ "$has_bc" -eq 1 ]; then
    ok "BREAKING CHANGE footer present"
  fi

  # 5. Footer / trailer form.
  local footers
  footers="$(printf '%s\n' "$msg" | git interpret-trailers --parse --no-divider 2>/dev/null)"
  if [ -n "$footers" ]; then
    ok "trailers parsed:"
    printf '%s\n' "$footers" | sed 's/^/         /'
  elif [ "$has_bc" -eq 1 ]; then
    ok "BREAKING CHANGE is the footer block (git cannot parse its spaced token — expected)"
  else
    warn "no trailers found"
  fi
  # A spaced token other than BREAKING CHANGE will silently not be a trailer.
  printf '%s\n' "$msg" | tail -n +3 | grep -qE '^[A-Za-z][A-Za-z0-9-]*[[:space:]]+[A-Za-z][A-Za-z0-9-]*: ' \
    && ! printf '%s\n' "$msg" | grep -qE '^BREAKING[ -]CHANGE: ' \
    && warn "a footer token appears to contain a space — git will not treat it as a trailer; use '-' instead"

  # 6. Jira key.
  local key
  key="$(printf '%s\n' "$msg" | grep -oE '\b[A-Z][A-Z0-9]+-[0-9]+\b' | head -n1)"
  if [ -n "$key" ]; then
    ok "Jira key '$key' present — the integration will link this commit"
    printf '%s\n' "$msg" | head -n1 | grep -qE '\b[A-Z][A-Z0-9]+-[0-9]+\b' && \
      warn "key is in the subject line; a footer keeps changelogs cleaner"
  else
    local lower
    lower="$(printf '%s\n' "$msg" | grep -oiE '\b[a-z][a-z0-9]+-[0-9]+\b' | head -n1)"
    if [ -n "$lower" ]; then
      err "found '$lower' — Jira only matches UPPERCASE keys, so this will not link"
    elif [ "$REQUIRE_JIRA" -eq 1 ]; then
      err "no Jira issue key found"
    else
      warn "no Jira issue key found — this commit will not link to a ticket"
    fi
  fi
}

if [ "$TARGET" = "-" ]; then
  check_message "$(cat)" "stdin"
elif [ -f "$TARGET" ]; then
  check_message "$(cat "$TARGET")" "$TARGET"
else
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 1; }
  if printf '%s' "$TARGET" | grep -q '\.\.'; then
    RANGE_REFS="$(git rev-list "$TARGET" 2>/dev/null)" || { echo "cannot resolve range '$TARGET'" >&2; exit 1; }
  else
    RANGE_REFS="$(git rev-parse "$TARGET" 2>/dev/null)" || { echo "cannot resolve '$TARGET'" >&2; exit 1; }
  fi
  for sha in $RANGE_REFS; do
    check_message "$(git log -1 --pretty=format:'%B' "$sha")" "$(git log -1 --pretty=format:'%h %s' "$sha")"
    echo
  done
fi

echo
echo "errors: $ERRORS   warnings: $WARNS"
[ "$ERRORS" -eq 0 ] || exit 1
