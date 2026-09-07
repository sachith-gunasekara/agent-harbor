#!/usr/bin/env bash
# init-template.sh — make a copy of this repo belong to whoever copied it.
#
# GitHub's "Use this template" gives you the files and none of the identity: the
# README still installs from the original slug, the plugin manifests still name
# the original author, and gen-catalog.sh would regenerate both on your next
# commit. This rewrites all of it in one pass, then regenerates and validates.
#
# What it changes:
#   .claude-plugin/*.json    name, owner/author, homepage — the identity source
#   README.md, docs/, .github/, mirrors.yaml
#                            every mention of the old slug, plugin name and owner
#   README.md                a one-line "scaffolding came from" credit at the end
#
# What it never touches:
#   LICENSE                  you are keeping MIT-licensed code, so the original
#                            copyright notice stays. Add your own line to it.
#   skills/mirrored/         byte-identical to upstream by design — rewriting a
#                            word in there would read as upstream drift and fail
#                            sync-mirrors.sh --verify
#
# Usage:
#   init-template.sh [options]
#     --repo OWNER/NAME    your repository  (default: guessed from git remote)
#     --owner-name NAME    display name     (default: gh api, else the owner login)
#     --email EMAIL        manifest contact (default: git config user.email)
#     --fresh              also empty skills/own, the mirrors list and the lockfile,
#                          so you start with no skills instead of inheriting these
#     --no-attribution     skip the credit line in the README
#     --dry-run            print the plan, write nothing
#     --yes                do not prompt for confirmation
#
# Exit: 0 done / nothing to do, 1 failed, 2 bad usage.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || { echo "cannot cd to $REPO_ROOT" >&2; exit 1; }

NEW_SLUG=""; NEW_OWNER=""; NEW_EMAIL=""
FRESH=0; ATTRIB=1; DRY=0; ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) NEW_SLUG="${2:-}"; shift 2 ;;
    --owner-name) NEW_OWNER="${2:-}"; shift 2 ;;
    --email) NEW_EMAIL="${2:-}"; shift 2 ;;
    --fresh) FRESH=1; shift ;;
    --no-attribution) ATTRIB=0; shift ;;
    --dry-run) DRY=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v perl >/dev/null || { echo "perl is required" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 1; }

MANIFEST=".claude-plugin/marketplace.json"
[ -f "$MANIFEST" ] || { echo "missing $MANIFEST — nothing to rebrand from" >&2; exit 1; }

# ------------------------------------------------------- who this repo is now
OLD_SLUG="$(jq -r '.plugins[0].homepage // ""' "$MANIFEST" | sed 's#^https://github.com/##; s#/$##')"
OLD_NAME="$(jq -r '.name // ""' "$MANIFEST")"
OLD_OWNER="$(jq -r '.owner.name // ""' "$MANIFEST")"
OLD_OWNER_URL="$(jq -r '.owner.url // ""' "$MANIFEST")"

[ -n "$OLD_SLUG" ] || { echo "$MANIFEST has no plugins[0].homepage to rebrand from" >&2; exit 1; }

# ------------------------------------------------------- who it should become
if [ -z "$NEW_SLUG" ]; then
  remote="$(git remote get-url origin 2>/dev/null)"
  # Both forms git hands back: git@github.com:owner/name.git and https://…/owner/name.git
  NEW_SLUG="$(printf '%s' "$remote" | sed -E 's#^git@github\.com:##; s#^https?://[^/]+/##; s#\.git$##')"
fi
case "$NEW_SLUG" in
  */*) ;;
  *) echo "could not work out your repository. Pass --repo OWNER/NAME." >&2; exit 2 ;;
esac

NEW_OWNER_LOGIN="${NEW_SLUG%%/*}"
NEW_NAME="${NEW_SLUG##*/}"

if [ -z "$NEW_OWNER" ]; then
  if command -v gh >/dev/null 2>&1; then
    NEW_OWNER="$(gh api "users/$NEW_OWNER_LOGIN" --jq '.name // ""' 2>/dev/null)"
  fi
  [ -n "$NEW_OWNER" ] || NEW_OWNER="$NEW_OWNER_LOGIN"
fi
[ -n "$NEW_EMAIL" ] || NEW_EMAIL="$(git config user.email 2>/dev/null || true)"

if [ "$NEW_SLUG" = "$OLD_SLUG" ]; then
  echo "This repo is already $OLD_SLUG — nothing to rebrand."
  echo "If you copied it, point the origin remote at your own repo first, or pass --repo."
  exit 0
fi

# ---------------------------------------------------------------- what we edit
# Tracked text files only. skills/mirrored/ is excluded because the sync detects
# upstream change by hashing those directories: one substituted word in there
# would look like drift and fail sync-mirrors.sh --verify. LICENSE is excluded
# because you are redistributing MIT code and the notice has to stay.
files() {
  local f
  git ls-files | grep -v '^skills/mirrored/' | grep -v '^LICENSE$' | while IFS= read -r f; do
    [ -f "$f" ] && grep -Iq '' "$f" 2>/dev/null && printf '%s\n' "$f"
  done
}

hits() {
  local needle="$1" f
  while IFS= read -r f; do
    grep -qF -- "$needle" "$f" 2>/dev/null && printf '%s\n' "$f"
  done < <(files)
}

subst() {
  local needle="$1" repl="$2" boundary="${3:-0}" f
  [ -n "$needle" ] || return 0
  [ "$needle" = "$repl" ] && return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$boundary" -eq 1 ]; then
      NEEDLE="$needle" REPL="$repl" perl -pi -e 's/\b\Q$ENV{NEEDLE}\E\b/$ENV{REPL}/g' "$f"
    else
      NEEDLE="$needle" REPL="$repl" perl -pi -e 's/\Q$ENV{NEEDLE}\E/$ENV{REPL}/g' "$f"
    fi
  done < <(files)
}

# ------------------------------------------------------------------- the plan
printf 'Rebranding this copy:\n\n'
printf '  repository   %s  ->  %s\n' "$OLD_SLUG" "$NEW_SLUG"
printf '  plugin name  %s  ->  %s\n' "$OLD_NAME" "$NEW_NAME"
printf '  owner        %s  ->  %s\n' "${OLD_OWNER:-—}" "$NEW_OWNER"
printf '  contact      %s\n' "${NEW_EMAIL:-— (none; pass --email)}"
[ "$FRESH" -eq 1 ] && printf '  skills       removing every skill and mirror (--fresh)\n'
[ "$ATTRIB" -eq 1 ] && printf '  attribution  crediting %s at the end of the README\n' "$OLD_SLUG"
printf '\n'

n_files="$(hits "$OLD_SLUG" | wc -l | tr -d ' ')"
printf 'Files mentioning the old slug: %s\n' "$n_files"
hits "$OLD_SLUG" | sed 's/^/  /'
printf '\nLICENSE and skills/mirrored/ are left alone.\n'

if [ "$DRY" -eq 1 ]; then
  printf '\n--dry-run: nothing written.\n'
  exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  if [ -t 0 ]; then
    printf '\nRewrite these files? [y/N] '
    read -r reply
    case "$reply" in y|Y|yes|YES) ;; *) echo "aborted"; exit 0 ;; esac
  else
    echo "" >&2
    echo "Refusing to rewrite without confirmation. Re-run with --yes (or --dry-run)." >&2
    exit 2
  fi
fi

# ------------------------------------------------------------------ manifests
# Set the identity fields explicitly rather than relying on the text pass, so a
# copy whose manifest was already half-edited still ends up consistent.
tmp="$(mktemp)"
jq --arg name "$NEW_NAME" --arg owner "$NEW_OWNER" --arg email "$NEW_EMAIL" \
   --arg login "$NEW_OWNER_LOGIN" --arg url "https://github.com/$NEW_SLUG" '
     .name = $name
     | .owner.name = $owner
     | .owner.email = $email
     | .owner.url = "https://github.com/" + $login
     | .plugins[0].name = $name
     | .plugins[0].homepage = $url
     | .plugins[0].author.name = $owner
   ' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"

if [ -f .claude-plugin/plugin.json ]; then
  tmp="$(mktemp)"
  jq --arg name "$NEW_NAME" --arg owner "$NEW_OWNER" --arg url "https://github.com/$NEW_SLUG" '
       .name = $name | .author.name = $owner | .homepage = $url
     ' .claude-plugin/plugin.json > "$tmp" && mv "$tmp" .claude-plugin/plugin.json
fi

# ----------------------------------------------------------------- everything else
# Slug before bare name: the slug contains the name, and replacing the name first
# would turn owner/agent-harbor into owner/<new> and leave the owner behind.
subst "$OLD_SLUG" "$NEW_SLUG"
subst "$OLD_OWNER_URL" "https://github.com/$NEW_OWNER_LOGIN"
[ -n "$OLD_OWNER" ] && subst "$OLD_OWNER" "$NEW_OWNER"
subst "$OLD_NAME" "$NEW_NAME" 1

# -------------------------------------------------------------------- --fresh
if [ "$FRESH" -eq 1 ]; then
  find skills/own -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null
  find skills/mirrored -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null
  # Keep the commented header and defaults; drop only the entries.
  if [ -f mirrors.yaml ]; then
    tmp="$(mktemp)"
    awk '/^mirrors:/ { print "mirrors:"; print "  []"; exit } { print }' mirrors.yaml > "$tmp"
    mv "$tmp" mirrors.yaml
  fi
  printf '{\n  "mirrors": {},\n  "version": 1\n}\n' > mirrors.lock.json
  # The keyword list names skills that are no longer here.
  tmp="$(mktemp)"
  jq '.plugins[0].keywords = ["skills", "agent-skills", "claude-code", "skill-mirror"]' \
    "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"
  if [ -f .claude-plugin/plugin.json ]; then
    tmp="$(mktemp)"
    jq '.keywords = ["skills", "agent-skills", "claude-code", "skill-mirror"]' \
      .claude-plugin/plugin.json > "$tmp" && mv "$tmp" .claude-plugin/plugin.json
  fi
fi

# --------------------------------------------------------------- attribution
CREDIT="The scaffolding — mirroring, catalog generation, CI — came from"
if [ "$ATTRIB" -eq 1 ] && [ -f README.md ] && ! grep -qF "$CREDIT" README.md; then
  printf '\n%s\n[%s](https://github.com/%s), MIT.\n' \
    "$CREDIT" "$OLD_SLUG" "$OLD_SLUG" >> README.md
fi

# ------------------------------------------------------------------ regenerate
./scripts/gen-catalog.sh || { echo "gen-catalog.sh failed" >&2; exit 1; }
./scripts/validate-skills.sh || { echo "validate-skills.sh failed" >&2; exit 1; }

cat <<EOF

Done. This repo is now $NEW_SLUG.

Still yours to do:
  - LICENSE keeps the original copyright, as MIT requires. Add your own line.
  - Review the diff, then commit: git add -A && git commit -m "chore: make this repo mine"
  - For mirror syncing, set up the MIRROR_PAT secret and the mirror/automated
    labels — see docs/mirroring.md.
EOF
