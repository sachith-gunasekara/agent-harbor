# skills

Agent skills I write and reuse across coding agents. Each one is a self-contained
directory under [`skills/`](skills/) with a `SKILL.md` entry point, so it can be
installed with `npx skills`, wired up as a Claude Code plugin marketplace, or just
copied by hand.

## Install

Install everything in this repo:

```bash
npx skills add sachith-gunasekara/skills --all
```

Pick interactively, or target one skill:

```bash
npx skills add sachith-gunasekara/skills            # prompts for which skills and which agents
npx skills add sachith-gunasekara/skills -l         # list what's available, install nothing
npx skills add sachith-gunasekara/skills -s conventional-commits
npx skills add sachith-gunasekara/skills -g         # install globally instead of into the project
npx skills add sachith-gunasekara/skills -a claude-code
```

A single skill by URL works too:

```bash
npx skills add https://github.com/sachith-gunasekara/skills/tree/main/skills/conventional-commits
```

### As a Claude Code plugin

The repo also carries a `.claude-plugin/marketplace.json`, so inside Claude Code:

```
/plugin marketplace add sachith-gunasekara/skills
/plugin install sachith-skills@sachith-skills
```

### By hand

Copy the skill directory into wherever your agent looks for skills — for Claude Code
that's `~/.claude/skills/` (global) or `.claude/skills/` (per project):

```bash
git clone https://github.com/sachith-gunasekara/skills.git
cp -R skills/skills/conventional-commits ~/.claude/skills/
```

## Skills

| Skill | What it does |
|---|---|
| [`conventional-commits`](skills/conventional-commits) | Writes Conventional Commits v1.0.0 messages from the actual diff, matches the conventions already in the repo, and stamps the Jira issue key into a git trailer so the Jira–GitHub integration links the commit to the ticket. Ships five scripts for inspecting changes, mining repo conventions, resolving the issue key, committing, and validating a message. |

## Layout

```
skills/
└── <skill-name>/
    ├── SKILL.md        # frontmatter + workflow — always the entry point
    ├── scripts/        # executable, run without loading into context
    └── references/     # read into context only when needed
```

`SKILL.md` is what the agent loads up front, so it stays short and points outward.
Scripts are run, not read — they keep deterministic work out of the context window.
References are pulled in only when the task actually needs them.

See [docs/adding-a-skill.md](docs/adding-a-skill.md) for the conventions a new skill
in this repo should follow.

## License

MIT — see [LICENSE](LICENSE).
