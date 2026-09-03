# Jira ↔ GitHub linking from commit messages

Two separate mechanisms get conflated constantly. Know which one you're using.

## 1. Plain issue-key linking (what you almost always want)

The Jira GitHub integration scans commit messages for issue keys and attaches the
commit to the matching work item, visible under the ticket's **Development** panel.
No command syntax, no special placement — the key just has to appear somewhere in
the message.

The key format is unforgiving: **two or more uppercase letters, a hyphen, then the
number.** `PROJ-123`, `AB-7`, `DATA2-45`. These do **not** work:

| Written as | Why it fails |
|---|---|
| `proj-123` | lowercase |
| `Proj-123` | only one uppercase letter leading |
| `#PROJ-123` | the `#` makes it a Smart Commit command prefix, not a key |
| `PROJ 123` | no hyphen |
| `P-123` | needs 2+ letters |

Because the scan covers the whole message, a footer works exactly as well as the
subject line — and keeps the generated changelog free of ticket noise:

```
fix(auth): reject refresh tokens after logout

Revoked tokens were still accepted until their natural expiry, so a stolen token
survived sign-out for up to 15 minutes.

Refs: PROJ-123
```

### Choosing the footer token

`Refs:` is used in the Conventional Commits spec's own examples and is the safe
default. Other common choices: `Ticket:`, `Jira:`, `Issue:`, `Closes:`. Whatever
the repo already uses beats the default — `repo-conventions.sh` reports it.

The token must be one word using `-` for spaces (`Jira-Ticket:` is fine,
`Jira Ticket:` is not — git won't parse it as a trailer).

Multiple tickets, one per line, is easier for tooling to read back than a
comma-joined list:

```
Refs: PROJ-123
Refs: PROJ-124
```

## 2. Smart Commits (only when you actually want side effects)

Smart Commits let a commit act on the ticket: comment, log time, or transition it.
Syntax:

```
<ignored text> ISSUE_KEY <ignored text> #<command> <arguments>
```

Commands: `#comment <text>`, `#time <w> <d> <h> <m> <comment>`, and transitions
such as `#done`, `#in-progress`, `#close` (the transition names come from the
project's workflow).

Constraints that catch people out:

- **A command cannot span lines.** Carriage returns end it. Several commands may
  share one line; a command may not wrap onto the next.
- Text between the key and the command is ignored, so the key must precede the
  command on that line.
- The **committer's git email must match exactly one Jira user** with permission
  for that action. A mismatch, or a match against several users, makes the command
  fail silently — the commit still lands and still shows on the ticket, but nothing
  is logged or transitioned. Mismatched email is the single most common cause of
  "smart commits don't work".
- Server/DC deployments need the Jira DVCS Connector plugin; Cloud needs the
  GitHub for Jira app installed with access to the repo.

Because of the one-line rule, put a Smart Commit command on its own footer line
rather than trying to fold it into a trailer:

```
feat(billing): add proration on plan downgrade

Refs: PROJ-410
PROJ-410 #time 3h #comment proration handled at the invoice-item level
```

`commit.sh --smart-commit "#time 3h"` appends exactly this form. Don't add
commands unless the user asked — silently logging work to someone's timesheet is
not a good surprise.

## Branch naming

If a branch is created from within Jira, commits on it are associated with the
ticket without the key appearing in each message. This is why some teams stop
including keys and then wonder why linking breaks when someone branches manually.
Including the key in the footer costs nothing and removes the dependency.

The convention `feature/PROJ-123-short-slug` also makes `jira-key.sh` able to
resolve the key with no input from anyone.

## When linking doesn't appear in Jira

Work through, in order:

1. Is the key uppercase and correctly formatted in the message?
   `git log -1 --pretty=%B | grep -oE '[A-Z][A-Z0-9]+-[0-9]+'`
2. Has the commit been **pushed**? Jira only sees what reaches GitHub.
3. Is the ticket in a project the integration has access to?
4. GitHub → Organization settings → installed apps → *GitHub for Jira*: does it
   still have access to this repository?
5. Jira → Project settings → Development tools: is development information enabled?
6. For Smart Commit actions specifically: does `git config user.email` match your
   Jira account email exactly?

## Squash merges

With squash-merge, the PR title becomes the commit subject and the PR body becomes
the commit body. The message that lands is the one that gets scanned — so the PR
title needs the conventional format and the key needs to be in the title or body.
A branch name containing the key does not carry over into the squashed commit.
