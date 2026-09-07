# agent-harbor

**A home port for the agent skills you write and the ones you borrow.** Keep your own
skills in one repo, vendor the good ones you find elsewhere, and let CI watch upstream
for you — then install the whole set into any agent with a single command.

[![validate](https://img.shields.io/github/actions/workflow/status/sachith-gunasekara/agent-harbor/validate.yml?branch=main&label=validate)](https://github.com/sachith-gunasekara/agent-harbor/actions/workflows/validate.yml)
[![mirror sync](https://img.shields.io/github/actions/workflow/status/sachith-gunasekara/agent-harbor/mirror-sync.yml?branch=main&label=mirror%20sync)](https://github.com/sachith-gunasekara/agent-harbor/actions/workflows/mirror-sync.yml)
[![install with npx skills](https://img.shields.io/badge/install-npx%20skills-black)](#install)
[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin%20marketplace-d97757)](#as-a-claude-code-plugin)
[![agent agnostic](https://img.shields.io/badge/agents-any%20that%20read%20SKILL.md-4c8eda)](#by-hand)
[![license: MIT](https://img.shields.io/github/license/sachith-gunasekara/agent-harbor)](LICENSE)

Every skill is a self-contained directory under [`skills/`](skills/) with a `SKILL.md`
entry point, so it installs with `npx skills`, mounts as a Claude Code plugin
marketplace, or gets copied by hand into whatever directory your agent reads.

- [`skills/own/`](skills/own) — written and maintained here.
- [`skills/mirrored/`](skills/mirrored) — vendored verbatim from upstream repos and
  kept in sync automatically. Declared in [`mirrors.yaml`](mirrors.yaml); see
  [docs/mirroring.md](docs/mirroring.md).

## Why this exists

Skills accumulate faster than anyone tracks them. You write two or three of your own,
then find a dozen more scattered across other people's repos, copy the ones you like
into `~/.claude/skills/`, and six months later you cannot say where any of them came
from, which have been improved upstream, which were renamed or moved to a new repo, or
which you quietly edited and can no longer tell apart from the original.

This repo is the fix, and it is meant to be **forked and used as your own**:

- **One place for everything you actually use.** Yours and other people's, installed
  from a single source, with one command per agent instead of one copy per machine.
- **Borrowed skills keep their provenance.** Each mirrored skill is pinned to an
  upstream commit in [`mirrors.lock.json`](mirrors.lock.json), with its repo, license,
  and a note on why you keep it around.
- **Upstream changes arrive as a pull request, not a surprise.** A scheduled workflow
  re-reads every upstream and opens one PR per skill that actually changed — so
  adopting a new version is a decision you make on a diff. Skip it and your pinned
  copy keeps working.
- **Migrating and forking stay your call.** If an upstream author moves a skill to a
  new repo, repoint one line in [`mirrors.yaml`](mirrors.yaml). If you want to change
  a borrowed skill rather than track it, fork it into `skills/own/` and drop the
  mirror — the repo stops chasing upstream for you and it becomes yours.

## Install

Install everything in this repo:

```bash
npx skills add sachith-gunasekara/agent-harbor --all
```

Pick interactively, or target one skill:

```bash
npx skills add sachith-gunasekara/agent-harbor            # prompts for which skills and which agents
npx skills add sachith-gunasekara/agent-harbor -l         # list what's available, install nothing
npx skills add sachith-gunasekara/agent-harbor -s conventional-commits
npx skills add sachith-gunasekara/agent-harbor -g         # install globally instead of into the project
npx skills add sachith-gunasekara/agent-harbor -a claude-code
```

A single skill by URL works too:

```bash
npx skills add https://github.com/sachith-gunasekara/agent-harbor/tree/main/skills/own/conventional-commits
```

### As a Claude Code plugin

The repo also carries a `.claude-plugin/marketplace.json`, so inside Claude Code:

```
/plugin marketplace add sachith-gunasekara/agent-harbor
/plugin install agent-harbor@agent-harbor
```

### By hand

Copy the skill directory into wherever your agent looks for skills — for Claude Code
that's `~/.claude/skills/` (global) or `.claude/skills/` (per project):

```bash
git clone https://github.com/sachith-gunasekara/agent-harbor.git
cp -R agent-harbor/skills/own/conventional-commits ~/.claude/skills/
```

## Skills

<!-- skills:start -->
### Written here

| Skill | What it does |
|---|---|
| [`conventional-commits`](skills/own/conventional-commits) | Write Conventional Commits v1.0.0 messages and stamp the Jira issue key into a git trailer footer so the Jira–GitHub integration links the commit to the ticket. |

### Mirrored

Vendored verbatim from upstream and kept in sync automatically. Do not edit
these in place; see [docs/mirroring.md](docs/mirroring.md).

| Skill | Upstream | License | What it does |
|---|---|---|---|
| [`brainstorming`](skills/mirrored/brainstorming) | [obra/superpowers](https://github.com/obra/superpowers/tree/b36e0829c6d0140e93cfef2ca599b1b07d4a7797/skills/brainstorming) `b36e082` | MIT | You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. |
| [`find-skills`](skills/mirrored/find-skills) | [vercel-labs/skills](https://github.com/vercel-labs/skills/tree/435076e78988e1e6ec40d00b0b1d76bdbbc5419a/skills/find-skills) `435076e` | MIT | Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities. |
| [`python-test`](skills/mirrored/python-test) | [DeerHide/agent_skills](https://github.com/DeerHide/agent_skills/tree/14b1dd8b0a80e26b812a6120b06500d850a5a881/skills/python-test) `14b1dd8` | MIT | Best practices and patterns for testing Python applications using pytest, pytest-xdist, and testcontainers. |
| [`systematic-debugging`](skills/mirrored/systematic-debugging) | [obra/superpowers](https://github.com/obra/superpowers/tree/b36e0829c6d0140e93cfef2ca599b1b07d4a7797/skills/systematic-debugging) `b36e082` | MIT | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes |
| [`verification-before-completion`](skills/mirrored/verification-before-completion) | [obra/superpowers](https://github.com/obra/superpowers/tree/b36e0829c6d0140e93cfef2ca599b1b07d4a7797/skills/verification-before-completion) `b36e082` | MIT | Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always |
<!-- skills:end -->

## Run your own harbor

Fork this repo — the tooling, the sync workflow and the checks come with it, and every
install command above becomes `npx skills add <you>/<your-fork>`. Then there are only
ever two moves.

### Add a skill you wrote

Drop it in `skills/own/<skill-name>/` with a `SKILL.md`, and let the tooling register
it:

```bash
mkdir -p skills/own/my-skill && $EDITOR skills/own/my-skill/SKILL.md
./scripts/gen-catalog.sh     # rewrites the README table, catalog and plugin manifests
```

The conventions worth following — how to write a description that actually triggers,
what belongs in `scripts/` versus `references/` — are in
[docs/adding-a-skill.md](docs/adding-a-skill.md).

### Borrow a skill someone else wrote

You never copy files in. You add four lines to [`mirrors.yaml`](mirrors.yaml) and merge
them:

```yaml
  - repo: obra/superpowers
    skill: brainstorming
    ref: main          # or a tag, or a full SHA to freeze it
    license: MIT       # required — mirroring is redistribution
    notes: Structured idea generation before committing to an approach.
```

On merge, `mirror-sync` clones the upstream, resolves the skill wherever it lives in
that repo, vendors it verbatim into `skills/mirrored/`, records the exact commit in
`mirrors.lock.json`, and opens the PR that adds it. Full workflow, including name
collisions and license handling, in [docs/mirroring.md](docs/mirroring.md).

### Living with borrowed skills

This is the part that usually rots, so it is automated:

| What happens | What you do |
|---|---|
| Upstream changes | Nothing. The sync runs weekly, and opens **one PR per skill that actually changed**, with the upstream diff. Merge it or close it — closing keeps your pinned copy. |
| You want a skill frozen | Put a full SHA in `ref:`. It will never open a PR again until you change that line. |
| The author moved it to a new repo | Change `repo:` (and `skill:` if it was renamed). The next sync re-vendors it from the new home; the old copy is pruned. |
| You want to *change* a borrowed skill | `git mv skills/mirrored/<name> skills/own/<name>`, delete its `mirrors.yaml` entry, edit freely. It is yours now, and you have given up automatic updates — a deliberate trade, not an accident. |
| You stop using it | Delete the entry. The next sync opens a PR removing the directory, the lock entry and every generated row. Re-adding it later re-vendors from scratch. |

Two rules hold the whole thing together: **never edit anything under
`skills/mirrored/`** (it is overwritten wholesale on every sync, and a pre-commit hook
plus CI will stop you), and **never hand-edit a generated region** — the README table,
[docs/skill-library.md](docs/skill-library.md), `NOTICE.md` and the plugin manifests all
come from the skills themselves.

## Layout

```
mirrors.yaml            # which upstream skills to mirror — the only file you edit to add one
mirrors.lock.json       # generated: upstream commit + tree hash per mirrored skill
skills/
├── own/<skill-name>/
│   ├── SKILL.md        # frontmatter + workflow — always the entry point
│   ├── scripts/        # executable, run without loading into context
│   └── references/     # read into context only when needed
└── mirrored/
    ├── NOTICE.md       # generated: upstream + license for each mirrored skill
    └── <skill-name>/   # verbatim copy of the upstream skill directory
scripts/                # repo tooling (sync, validate, catalog) — not skill scripts
```

`SKILL.md` is what the agent loads up front, so it stays short and points outward.
Scripts are run, not read — they keep deterministic work out of the context window.
References are pulled in only when the task actually needs them.

Anything under `skills/mirrored/` is a byte-for-byte copy of upstream and is
overwritten on every sync — never edit it in place. To diverge from upstream, fork the
skill into `skills/own/` and drop the mirror entry.

See [docs/adding-a-skill.md](docs/adding-a-skill.md) for the conventions a new skill in
this repo should follow, and [docs/mirroring.md](docs/mirroring.md) for how mirroring
works.

## Repo tooling

Set up once, and the rest is automatic:

```bash
brew install yq pre-commit
pre-commit install && pre-commit install --hook-type pre-push
```

That wires the same checks CI runs into your commits — shellcheck, actionlint, skill
validation, the mirror drift guard, and regeneration of the README table, catalog,
`NOTICE.md` and plugin manifests. You never update those by hand; if a commit would
leave them stale, the hook rewrites them and asks you to re-add.

The scripts are still there to run directly:

```bash
./scripts/sync-mirrors.sh --dry-run   # what would change against upstream
./scripts/sync-mirrors.sh --verify    # mirrored skills still match the lockfile
./scripts/validate-skills.sh          # frontmatter, naming, scripts, referenced paths
./scripts/gen-catalog.sh              # regenerate README table, catalog, NOTICE, manifests
./scripts/gen-catalog.sh --check      # ...or just report staleness
./scripts/test-sync.sh                # offline tests for the sync, incl. removal
```

`sync-mirrors.sh` needs [`yq`](https://github.com/mikefarah/yq); `gen-catalog.sh` needs
`jq`. CI runs the same [`.pre-commit-config.yaml`](.pre-commit-config.yaml) on every
pull request, so the hooks and the pipeline cannot drift apart.

## License

MIT — see [LICENSE](LICENSE).
