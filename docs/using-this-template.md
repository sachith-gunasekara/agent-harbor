# Starting your own harbor from this one

This repo is a template. Copying it gives you the whole machine — the mirror sync, the
catalog generation, the validation hooks, the CI — with none of my skills baked in
unless you want them.

## Template or fork?

Both work. They differ in what comes along.

| | **Use this template** | **Fork** |
|---|---|---|
| Commit history | None — your repo starts at one commit, authored by you | Full history, mine included |
| Link to this repo | None. It is an ordinary repo of yours | Stays in the fork network, listed under this repo's forks |
| Sending changes back | Open a PR from a branch, like any contributor | Same, slightly easier |
| Getting later scaffolding fixes | Add this repo as a remote and cherry-pick (below) | `git merge upstream/main` |
| Repo name | Whatever you want | Same as this one, by default |

**Take the template if this is going to be your own library** and you do not want a
year of my commits in your `git log` or your repo listed as a fork of mine. Take the
fork if you mostly want to track what I do here and occasionally send something back.

## 1. Make the copy

Click **Use this template → Create a new repository** on GitHub, or:

```bash
gh repo create my-harbor --template sachith-gunasekara/agent-harbor --public --clone
cd my-harbor
```

## 2. Make it yours

**This usually happens on its own.** `.github/workflows/template-bootstrap.yml` runs on
the copy's first push, rebrands it, commits the result, and deletes itself. It skips
the repo it came from (a string comparison against the manifest's homepage, so renaming
this repo cannot break it) and skips forks, which mean to stay linked. Delete that file
before your first push if you would rather do it by hand — or if the bootstrap already
ran and you want to change the answers, just run the script again:

```bash
./scripts/init-template.sh --dry-run     # what it would rewrite
./scripts/init-template.sh               # do it
```

It reads the identity it is replacing out of `.claude-plugin/marketplace.json`, works
out yours from the `origin` remote (`--repo owner/name` to override), and rewrites
every mention of the old slug, plugin name and owner across the README, the docs, the
workflows and both plugin manifests — then regenerates the catalog and validates the
result.

| Flag | Use it when |
|---|---|
| `--fresh` | You want the machinery and none of my skills. Empties `skills/own/`, the `mirrors:` list and the lockfile. |
| `--owner-name` / `--email` | The display name and contact for the plugin manifests, if the guesses are wrong. |
| `--no-attribution` | You would rather not keep the one-line credit at the end of the README. |
| `--dry-run` | Always, first. |

Two things it deliberately leaves alone:

- **`LICENSE`.** You are redistributing MIT-licensed code, so the original copyright
  notice stays. Add your own line beside it.
- **`skills/mirrored/`.** Those directories are byte-identical to their upstreams and
  the sync detects change by hashing them. A substituted word in there would read as
  upstream drift and fail `./scripts/sync-mirrors.sh --verify`.

Review the diff and commit:

```bash
git diff
git add -A && git commit -m "chore: make this repo mine"
```

## 3. Turn on the machinery

The sync workflow needs a little setup that cannot travel with a template copy:

```bash
pre-commit install && pre-commit install --hook-type pre-push   # local checks

gh label create mirror --color 0E8A16 --description "Vendored copy of an upstream skill"
gh label create automated --color 5319E7 --description "Opened by a workflow, not a human"

gh secret set MIRROR_PAT --repo <you>/<your-harbor>             # see docs/mirroring.md
```

`MIRROR_PAT` is a fine-grained token scoped to your repo with **Contents: read and
write** and **Pull requests: read and write**. Without it the sync falls back to the
workflow token, which can open pull requests only if you enable *Settings → Actions →
General → Allow GitHub Actions to create and approve pull requests* — and those pull
requests do not trigger `validate.yml`, so mirrors arrive unchecked.
[mirroring.md](mirroring.md) covers both paths.

Check the whole thing works before you rely on it:

```bash
pre-commit run --all-files
./scripts/sync-mirrors.sh --dry-run
```

## 4. Fill it

- Your own skills go in `skills/own/` — [adding-a-skill.md](adding-a-skill.md).
- Skills you want from other people's repos go in `mirrors.yaml` —
  [mirroring.md](mirroring.md).

If you kept my mirrors, they are now yours to track: the weekly sync will open pull
requests against *your* repo when those upstreams move, and nothing routes through me.

## 5. Later: picking up scaffolding fixes

A template copy has no upstream link, so improvements to the tooling here do not
arrive on their own. When you want them:

```bash
git remote add harbor https://github.com/sachith-gunasekara/agent-harbor.git
git fetch harbor
git log --oneline HEAD..harbor/main -- scripts/ .github/    # what changed
git cherry-pick <sha>                                       # take what you want
```

Cherry-picking `scripts/` and `.github/` is usually clean, since your divergence is
almost entirely in the README, the manifests and the skills themselves. Re-run
`./scripts/init-template.sh` afterwards if a picked commit reintroduces the old slug —
it is idempotent, and a no-op when there is nothing to rewrite.
