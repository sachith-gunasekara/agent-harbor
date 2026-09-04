# agent-harbor

Agent skills I write and reuse across coding agents, plus skills mirrored from other
repos so everything installs from one place. Each one is a self-contained directory
under [`skills/`](skills/) with a `SKILL.md` entry point, so it can be installed with
`npx skills`, wired up as a Claude Code plugin marketplace, or just copied by hand.

- [`skills/own/`](skills/own) — written and maintained here.
- [`skills/mirrored/`](skills/mirrored) — vendored verbatim from upstream repos and
  kept in sync automatically. Declared in [`mirrors.yaml`](mirrors.yaml); see
  [docs/mirroring.md](docs/mirroring.md).

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
| [`systematic-debugging`](skills/mirrored/systematic-debugging) | [obra/superpowers](https://github.com/obra/superpowers/tree/b36e0829c6d0140e93cfef2ca599b1b07d4a7797/skills/systematic-debugging) `b36e082` | MIT | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes |
<!-- skills:end -->

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
