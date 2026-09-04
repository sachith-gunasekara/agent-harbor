# Adding a skill to this repo

This is for skills **written here**, which live in `skills/own/`. To vendor an existing
skill from someone else's repo, add it to `mirrors.yaml` instead — see
[mirroring.md](mirroring.md).

## 1. Scaffold

```bash
mkdir -p skills/own/<skill-name>/{scripts,references}
touch skills/own/<skill-name>/SKILL.md
```

The directory name is the skill's identity — lowercase, hyphenated, and identical to
the `name` in the frontmatter. Both `scripts/` and `references/` are optional; a skill
that is pure prose is just a `SKILL.md`.

The name also has to be unique across `skills/own/` *and* `skills/mirrored/`, since
that is what an installer resolves; `./scripts/validate-skills.sh` fails on collisions.

## 2. Write the frontmatter

```yaml
---
name: skill-name
description: What it does, followed by when to use it — the concrete phrases and
  situations that should trigger it, including ones the user might phrase differently.
---
```

`name` and `description` are the only required fields, and the description is the whole
of what the agent sees when deciding whether to load the skill. Write it as *what it
does + when to reach for it*, and include the vocabulary a user would actually type.
Keep it under roughly 1024 characters.

Optional: `metadata.internal: true` hides a skill from discovery unless explicitly
enabled.

## 3. Write SKILL.md

Everything under the frontmatter is loaded into context when the skill fires, so keep
it to the workflow and the decisions — a few hundred lines at most.

- **Workflow first.** Numbered steps, each naming the script to run and what to do with
  its output.
- **Push detail outward.** Anything long, rarely needed, or reference-shaped goes in
  `references/` and gets linked, not inlined.
- **Push determinism into scripts.** If a step is the same every time, it's a script —
  the agent runs it and reads the output instead of reasoning through it.
- **Say what not to do.** The failure modes are usually more valuable than the happy
  path.
- Refer to files by their path relative to the skill root: `scripts/foo.sh`,
  `references/spec.md`.

## 4. Scripts

- `#!/usr/bin/env bash`, `set -uo pipefail`, and a usage comment block at the top.
- `chmod +x` before committing — the executable bit is tracked by git and installers
  preserve it.
- Read-only by default. Anything that writes, mutates, or commits gets a `--dry-run`
  and says so in its header.
- Print output meant to be *read by the agent*: structured, bounded, no unbounded dumps.

## 5. Register it

```bash
./scripts/gen-catalog.sh
```

That regenerates the table in the top-level [`README.md`](../README.md),
[`skill-library.md`](skill-library.md), and the descriptions in `.claude-plugin/` from
the frontmatter you just wrote. Don't hand-edit those regions — CI fails if they are
stale. The plugin manifests otherwise pick up everything under `skills/` automatically.

## 6. Check it

If you have run `pre-commit install`, steps 5 and 6 happen on their own — the hooks
regenerate the catalog and run every check below when you commit.

To run them by hand:

```bash
pre-commit run --all-files        # everything CI runs
npx skills add . -l               # installs cleanly and shows up in discovery
```

Or individually:

```bash
./scripts/validate-skills.sh      # frontmatter, name/dir agreement, uniqueness,
                                  # referenced paths, script syntax + exec bit
./scripts/gen-catalog.sh --check  # generated regions are current
```

`validate-skills.sh` is the automated form of the checks this section used to spell
out, and it runs on every pull request.

## 7. Open the PR

Use the skill template, which asks the questions worth answering about a skill —
what it does, when it should fire, and why it is a skill rather than a prompt:

```
https://github.com/sachith-gunasekara/agent-harbor/compare/main...<branch>?expand=1&template=skill.md
```

`gh pr create` does not apply templates, so paste the body from
[`.github/PULL_REQUEST_TEMPLATE/skill.md`](../.github/PULL_REQUEST_TEMPLATE/skill.md)
if you use the CLI.
