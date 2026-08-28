---
name: conventional-commits
description: Write Conventional Commits v1.0.0 messages and stamp the Jira issue key into a git trailer footer so the Jira–GitHub integration links the commit to the ticket. Use this whenever the user is about to commit, asks to "commit this", "commit my changes", "write a commit message", "make a conventional commit", wants a message amended, reworded, or split into several commits, or mentions commitlint, semantic-release, changelog generation from history, SemVer bumps from commits, or Jira ticket references in git. Also use when reviewing or fixing existing commit messages, and when setting up commit conventions for a repo — even if the user never says the words "conventional commits".
---

# Conventional Commits (+ Jira linking)

Turn a working tree full of changes into commits whose messages a human can skim,
a changelog generator can parse, and Jira can link to the right ticket.

Never guess at the diff. Run the scripts, read the actual changes, then write.

## Workflow

Run the scripts from the skill's `scripts/` directory. All are read-only except `commit.sh`.

### 1. See what actually changed

```bash
scripts/inspect-changes.sh            # staged changes (default)
scripts/inspect-changes.sh --all      # staged + unstaged + untracked
scripts/inspect-changes.sh --diff     # add the bounded patch text
```

Prints branch/upstream state, a file-level stat, porcelain status, and recent
history. Read it before deciding anything. If nothing is staged, say so and ask
what to stage rather than running `git add -A` on the user's behalf — unrelated
changes swept into one commit is the most common failure here.

### 2. Learn the repo's existing conventions

```bash
scripts/repo-conventions.sh           # add -n 200 to widen the history sample
```

Reports the type and scope vocabulary already in use, whether commitlint /
semantic-release / a commit template is configured, which footer token the repo
uses for Jira, and any Jira project keys seen in history. **Match what's there.**
A repo that has used `Ticket:` for 400 commits does not want your `Refs:`.

### 3. Resolve the Jira issue key

```bash
scripts/jira-key.sh                   # branch name → history → JIRA_ISSUE_KEY env
```

Order of trust: an explicit key from the user, then the branch name
(`feature/PROJ-123-refresh-tokens`), then keys on recent commits of this branch,
then `$JIRA_ISSUE_KEY`. If none resolves, ask once. If the user says there isn't
one (personal repo, chore branch), commit without it — a wrong key is worse than
no key, because it silently attaches work to a stranger's ticket.

### 4. Decide the commit split

One logical change per commit. If the diff contains a feature *and* an unrelated
fix, that is two commits — the spec's own FAQ says to go back and split rather
than pick a winner. Propose the split to the user before staging anything.

### 5. Compose and commit

```bash
scripts/commit.sh --type feat --scope auth \
  --desc "add refresh token rotation" \
  --body "Tokens now rotate on every refresh; the old token is revoked server-side." \
  --jira PROJ-123
```

Add `--dry-run` to print the message without committing — do this first when the
message is non-trivial, show the user, then run for real. Other flags:
`--breaking "<description>"`, `--footer "Reviewed-by: Ana"`, `--trailer-key Ticket`,
`--amend`, `--all`, `--type-list`.

### 6. Verify

```bash
scripts/validate-message.sh HEAD
```

Checks structure, type, header length, blank-line separation, footer/trailer form,
and Jira key presence. Run it after committing, and use it on its own when the
task is "is this message any good?" or "fix my last commit message".

## Message format

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

- **Header** — `type`, optional `(scope)`, optional `!`, then `: ` and the description.
  Lowercase type, imperative mood, no trailing period, aim for ≤72 characters.
  Write it as the completion of "if applied, this commit will _____".
- **Body** — starts one blank line after the header, free-form paragraphs, wrapped
  around 72–100 columns. Explain *why*, and what a reviewer couldn't infer from the
  diff. Skip it entirely for changes that are self-evident.
- **Footers** — one blank line after the body. Each is a git trailer: a token using
  `-` for spaces, then `: ` or ` #`, then a value. `BREAKING CHANGE` is the one
  token allowed to contain a space, and it must be uppercase.

## Types

`feat` and `fix` are the only two the spec defines; the rest are the
commitlint/Angular convention and are what most repos expect.

| Type | Use for | SemVer |
|---|---|---|
| `feat` | a new capability for users of the code | MINOR |
| `fix` | a bug fix | PATCH |
| `docs` | documentation only | — |
| `style` | formatting, whitespace, semicolons — no behaviour change | — |
| `refactor` | restructuring that neither fixes a bug nor adds a feature | — |
| `perf` | a change made for performance | — |
| `test` | adding or correcting tests | — |
| `build` | build system, packaging, dependencies | — |
| `ci` | CI configuration and scripts | — |
| `chore` | housekeeping that touches neither src nor tests | — |
| `revert` | reverting an earlier commit | — |

Any commit, of any type, becomes MAJOR if it carries a breaking change.

**Scope** is a noun for the part of the codebase touched: `feat(parser):`,
`fix(api):`. Prefer a scope already used in the repo. Omit it rather than invent
a vague one — `feat(app):` tells nobody anything.

## Breaking changes

Two ways, and they can be combined:

```
feat(api)!: return ISO-8601 timestamps from /events

BREAKING CHANGE: `created_at` is now a string, not a Unix epoch integer.
```

The `!` makes it visible when skimming `git log --oneline`; the footer gives
tooling and the changelog the explanation. Use `!` alone only when the description
already says exactly what broke. `BREAKING-CHANGE` is an accepted synonym token.

## Jira in the footer

The Jira–GitHub integration scans the **whole** commit message for issue keys, so
a footer links the commit just as well as the subject line does — while keeping
the header clean for changelogs. Default to a trailer:

```
fix(auth): reject refresh tokens after logout

Revoked tokens were still accepted until their natural expiry.

Refs: PROJ-123
```

Rules worth knowing:

- The key format is rigid: two or more **uppercase** letters, a hyphen, a number
  (`PROJ-123`). Lowercase `proj-123` will not match. Neither will `#PROJ-123`.
- `Refs:` is the token the spec itself uses in its examples and is a safe default.
  Whatever the repo already uses wins over that — check step 2.
- Multiple tickets: one trailer line each, or `Refs: PROJ-123, PROJ-124`. Separate
  lines are easier for tooling to read back.
- **Smart Commit commands** (`#comment`, `#time`, `#transition`) are different from
  plain linking. A command must sit on the same single line as the key and cannot
  wrap, so give it its own footer line: `PROJ-123 #time 2h #comment rotated tokens`.
  They also require the committer's git email to match exactly one Jira user, so
  they fail silently more often than plain linking does. Don't add them unless
  asked.
- If the repo's PR template or CI requires the key in the subject line instead,
  follow the repo. Note the tradeoff: it will show up in every generated changelog
  entry.

See `references/jira.md` for branch naming, verification, and failure modes.

## Examples

**A feature, with the reason recorded**

```
feat(scheduler): retry failed jobs with exponential backoff

Transient database timeouts were dropping roughly 2% of nightly jobs. Retries
now back off from 1s to 5m over six attempts before the job is parked.

Refs: PROJ-482
```

**A small fix that needs no body**

```
fix(ui): stop dropdown closing on scroll

Refs: PROJ-501
```

**Multiple footers**

```
fix: prevent racing of requests

Introduce a request id and a reference to the latest request; dismiss incoming
responses other than from the latest request.

Reviewed-by: Priya
Refs: PROJ-77
```

**A revert** — name the SHAs being undone:

```
revert: feat(scheduler): retry failed jobs with exponential backoff

Refs: 676104e
Refs: PROJ-482
```

## Gotchas

- The body is not a diff summary. "Changed X, Y, Z" is what `git show` is for.
  Record intent, constraints, and rejected alternatives.
- Don't wrap the header in backticks or quotes, and don't prefix it with the ticket
  key when the footer already carries it.
- Squash-merge workflows: the PR title becomes the commit message, so it needs the
  same treatment — type, scope, and the key somewhere in the title or description.
- `git commit --trailer` and `git interpret-trailers` both **refuse tokens
  containing whitespace**, and silently mangle `BREAKING CHANGE:` into
  `BREAKING CHANGE: <value>: `. Don't route that footer through them — `commit.sh`
  writes the footer block directly for this reason.
- Mixed-convention repos are common. When history is inconsistent, follow the last
  ~30 commits rather than the oldest ones, and say which pattern you followed.

## References

- `references/spec.md` — the v1.0.0 specification rules, trailer mechanics, and
  the spec's own guidance on reverts, wrong types, and initial development.
- `references/jira.md` — Jira issue-key detection, Smart Commits, branch naming,
  and why linking silently fails.
