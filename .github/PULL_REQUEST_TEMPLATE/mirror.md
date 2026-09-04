<!--
For vendored skill content under skills/mirrored/. mirror-sync fills this in
automatically; use it by hand only when opening a mirror PR yourself.

Use ?template=mirror.md on the compare URL.
-->

## Summary

<!-- added / updated / removed which skill, and from where. -->

| | |
|---|---|
| Upstream | `<owner>/<repo>/<path>` |
| From | `<old commit>` |
| To | `<new commit>` |
| License | `<SPDX>` |

## Upstream changes

<!-- For an update: the upstream log for this path, and a compare link.
     For a removal: say the record was dropped from mirrors.yaml. -->

```
```

## Review notes

The vendored directory is a **byte-for-byte copy of upstream**. Review it as you
would a dependency bump — especially anything under `scripts/`, which runs on your
machine when the skill fires.

Everything else in the diff is generated: `mirrors.lock.json`, the README table,
`docs/skill-library.md`, `skills/mirrored/NOTICE.md`, and the plugin manifest
descriptions.

Do not hand-edit files under `skills/mirrored/` — the pre-commit hook and CI both
enforce that they hash to the lockfile. To diverge from upstream, fork the skill
into `skills/own/` and drop its `mirrors.yaml` record.

---

- [ ] The upstream diff contains nothing I would not want running in my agent
- [ ] The declared license still matches upstream
- [ ] `validate` passed on this PR — if it did not run at all, see
      [docs/mirroring.md](../../docs/mirroring.md) on `MIRROR_PAT`
