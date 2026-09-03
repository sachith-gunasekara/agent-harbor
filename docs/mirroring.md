# Mirroring skills from other repos

This repo publishes two kinds of skill. Ones written here live in `skills/own/`.
Ones written elsewhere are **mirrored** into `skills/mirrored/` — vendored copies,
re-synced automatically, so that everything installs from a single source:

```bash
npx skills add sachith-gunasekara/agent-harbor --all
```

You never add a mirrored skill by copying files. You add a line to
[`mirrors.yaml`](../mirrors.yaml) and let CI do the rest.

## Adding a mirror

Add an entry:

```yaml
mirrors:
  - repo: obra/superpowers
    skill: brainstorming
    ref: main
    license: MIT
    notes: Structured idea generation before committing to an approach.
```

`repo`, `skill`, and `license` are required. `ref` defaults to `defaults.ref` (the
upstream default branch).

You name the skill, not its location. The sync finds it the same way an installer
does — the directory called `<skill>` that contains a `SKILL.md` — so you do not
have to know or track where in the upstream repo it lives. If upstream reorganises
its directories, the mirror keeps working.

Two optional escape hatches:

- `name:` vendors the skill under a different local directory name, for when the
  upstream name collides with something already here.
- `path:` pins an explicit upstream directory, needed only to break a tie when a
  repo has several directories with the same name. The sync tells you when this
  happens and lists the candidates.

If the name does not resolve at all, the error lists every skill the repo actually
publishes, which is usually enough to spot a typo.

Open a PR with that change. Once it is **merged to `main`**, the `mirror-sync`
workflow fires, clones the upstream, and opens a second PR adding the vendored
skill. Review that diff like any other dependency bump, then merge it too.

So adding a mirror is two merges: one for the intent (`mirrors.yaml`), one for the
content (`skills/mirrored/`). The workflow runs on `main` only and never on a
feature branch — it opens pull requests and pushes branches, so an unreviewed
version of it must not be able to act on the repo.

To do it locally instead:

```bash
./scripts/sync-mirrors.sh --dry-run   # what would change
./scripts/sync-mirrors.sh             # apply
./scripts/gen-catalog.sh              # refresh README, catalog, NOTICE, manifests
```

`sync-mirrors.sh` needs [`yq`](https://github.com/mikefarah/yq) — `brew install yq`.

## How change detection works

The sync does **not** diff files. It compares git tree hashes.

`git rev-parse <commit>:<path>` is the content hash of a directory, and git tree
hashes depend only on the names, modes, and contents of what is inside — not on
where the directory sits. So the hash of `skills/brainstorming` upstream and the
hash of `skills/mirrored/brainstorming` here are equal exactly when the two
directories are identical.

That gives the property the whole design rests on: **a sync with no upstream
change produces no diff, and therefore no pull request.** Running it hourly would
be as quiet as running it never.

It also means a mirrored directory has to stay byte-identical to upstream. Nothing
is injected into it — no provenance header, no rewritten frontmatter. All the
metadata lives in [`mirrors.lock.json`](../mirrors.lock.json), the generated
[catalog](skill-library.md), and [`NOTICE.md`](../skills/mirrored/NOTICE.md)
sitting *beside* the mirrored skills rather than inside any of them.

Related: `.gitignore` anchors its `dist/` and `node_modules/` patterns to the repo
root. Unanchored, they would silently drop files from a mirrored skill that
happened to contain such a directory, and the copy would no longer hash to
upstream.

## Pinning

`ref` takes a branch, a tag, or a full 40-character SHA:

```yaml
    ref: v2.1.0                                      # tag
    ref: 05d90ac59248e6716f1a81e79757d850e62f4f7d    # frozen
```

A branch means "track this and tell me when it moves" — the weekly run opens a PR
whenever upstream changes. A SHA means "freeze here" and will never produce a PR
until you change the line yourself. Pin anything whose upstream you do not want
moving under you.

`mirrors.lock.json` always records the exact commit that was vendored, whichever
you use.

## Removing a mirror

Delete the entry from `mirrors.yaml`. The next sync notices the lockfile has an
entry `mirrors.yaml` no longer declares, and opens a PR deleting both the vendored
directory and the lock entry.

As a safety measure, removal is skipped entirely if any entry in `mirrors.yaml`
failed to parse — otherwise a typo in one entry could be read as "this mirror was
removed" and delete a skill you still wanted.

## Never edit a mirrored skill

`skills/mirrored/` is overwritten wholesale on every sync — upstream deletions
propagate, and local edits are destroyed. CI blocks this before it bites:
`./scripts/sync-mirrors.sh --verify` re-hashes every mirrored directory against the
lockfile and fails on any mismatch, including directories that are not declared at
all.

If you need a mirrored skill to behave differently:

1. `git mv skills/mirrored/<name> skills/own/<name>`
2. Delete its entry from `mirrors.yaml`.
3. Edit freely, and keep the upstream attribution in the file.

It is now yours to maintain, and you have given up automatic updates. That is the
trade, and it should be a deliberate one.

## Name collisions

Installers resolve a skill by the `name` in its frontmatter, not by its path, so
names must be unique across `skills/own/` and `skills/mirrored/` together. Two
skills called `brainstorming` would be ambiguous no matter which directories they
sit in.

The sync refuses to vendor a skill whose name collides with something in
`skills/own/`, and `./scripts/validate-skills.sh` fails on any duplicate. To
mirror a skill whose name is taken, rename the local copy:

```yaml
  - repo: someone/repo
    skill: brainstorming
    name: someone-brainstorming
```

Note this renames the *directory*, not the frontmatter — the vendored copy stays
byte-identical to upstream, so the skill still reports its original name to
installers. Where the upstream frontmatter name itself is the collision, mirroring
is not enough; fork it into `skills/own/` and rename it there.

## Licensing

`license` is required because mirroring is redistribution. The sync reads the
upstream `LICENSE` file and warns when it is missing entirely or disagrees with
what you declared — that check is advisory, not authoritative, and it is on you to
confirm you have the right to redistribute.

Some repos publish skills with no license at all (`anthropics/skills` is one).
Absent a license, you have no redistribution grant, and the honest options are to
reference it rather than vendor it, or to ask upstream to add one.

`skills/mirrored/NOTICE.md` is generated on every sync and records the upstream
URL, exact commit, and declared license for each mirrored skill.

## Handling two mirror PRs at once

Every mirror PR touches `mirrors.lock.json` and the generated README, so when two
are open at the same time the second will conflict after the first merges. The
matrix runs serially to reduce this, but it can still happen. The fix is never a
manual merge:

```bash
git checkout mirror/<name>
git rebase main
./scripts/sync-mirrors.sh --skill <name>
./scripts/gen-catalog.sh
git add -A && git rebase --continue
```

Both files are fully generated, so regenerating them is always the correct
resolution.

## Reference

| Command | What it does |
|---|---|
| `./scripts/sync-mirrors.sh` | Sync every mirror, update the lockfile |
| `./scripts/sync-mirrors.sh --dry-run` | Report what would change, write nothing |
| `./scripts/sync-mirrors.sh --skill NAME` | Limit to one mirror |
| `./scripts/sync-mirrors.sh --force` | Re-materialise even when up to date |
| `./scripts/sync-mirrors.sh --verify` | Fail if any mirrored dir drifted from the lock |
| `./scripts/sync-mirrors.sh --json` | Machine-readable summary (used by CI) |
| `./scripts/gen-catalog.sh` | Regenerate README table, catalog, NOTICE, manifests |
| `./scripts/gen-catalog.sh --check` | Fail if any generated file is stale |
| `./scripts/validate-skills.sh` | Validate every skill in the repo |

Workflows: [`mirror-sync.yml`](../.github/workflows/mirror-sync.yml) opens the PRs;
[`validate.yml`](../.github/workflows/validate.yml) gates them.

### Linting

Install the hooks once and none of this is your problem again:

```bash
brew install yq pre-commit && pre-commit install
```

Every check CI runs then runs before the commit lands, from the same
[`.pre-commit-config.yaml`](../.pre-commit-config.yaml). The catalog, `NOTICE.md`
and plugin manifests are regenerated for you rather than checked — if a commit
would leave them stale, the hook rewrites them and stops once so you can re-add.

Two things about that config are load-bearing:

- **`exclude: ^skills/mirrored/`.** The whitespace fixers must never touch a
  vendored skill. A trimmed trailing newline changes the directory's hash, which
  the sync reads as upstream drift, and `--verify` starts failing for no reason.
- **`gen-catalog.sh` normalises its output to a single trailing newline.** Without
  that it fights `end-of-file-fixer` forever: the hook trims the blank line, the
  generator writes it back, and every commit fails in a loop.

`actionlint` is in there because plain YAML validity is not enough. A workflow can
parse fine and still be rejected by GitHub at startup — an invalid context
reference is the usual cause — and it fails in under a second with no usable log.

### One-time setup: `MIRROR_PAT`

Without this, the sync pushes its branch and then fails to open the pull request:

```
GitHub Actions is not permitted to create or approve pull requests.
```

Create a fine-grained personal access token scoped to this repository, with
**Contents: read and write** and **Pull requests: read and write**, then:

```bash
gh secret set MIRROR_PAT --repo <owner>/agent-skills
```

The alternative is to enable Settings → Actions → General → *Allow GitHub Actions
to create and approve pull requests*. That unblocks PR creation, but pull requests
opened with the default `GITHUB_TOKEN` do not trigger other workflows, so
`validate.yml` never runs on them and mirror PRs arrive unchecked. The token is the
better fix for that reason.

If the pull request cannot be opened, nothing is lost — the branch
`mirror/<skill>` has already been pushed, and you can raise it by hand:

```bash
gh pr create --base main --head mirror/<skill>
```

The workflow also expects two labels to exist, `mirror` and `automated`. Create
them once:

```bash
gh label create mirror --color 0E8A16 --description "Vendored copy of an upstream skill"
gh label create automated --color 5319E7 --description "Opened by a workflow, not a human"
```
