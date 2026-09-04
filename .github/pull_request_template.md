<!--
Default template. There are others for specific kinds of change — append the query
parameter to the compare URL:

  ?template=mirror.md   vendored skill content, usually raised by mirror-sync
  ?template=skill.md    a skill written here, under skills/own/

Keep the headings you use and delete the ones you do not. An empty heading is worse
than no heading.
-->

## What

<!-- The change itself, in a sentence or two. -->

## Why

<!-- The problem this solves. If it fixes something, say what was broken and how it
     showed up — a reviewer who knows the symptom can check the fix addresses it. -->

## Verification

<!-- What you actually ran, and what it printed. Not "tested locally" — the command
     and its output. If something could not be verified, say so and say why. -->

```
```

## Notes

<!-- Optional. Trade-offs, anything deliberately left out, follow-ups, or decisions a
     reviewer might otherwise have to guess at. Delete if there are none. -->

---

- [ ] `pre-commit run --all-files` passes
- [ ] `./scripts/test-sync.sh` passes, if the sync or repo tooling changed
- [ ] Generated files were regenerated, not hand-edited — README table,
      `docs/skill-library.md`, `skills/mirrored/NOTICE.md`, `.claude-plugin/*`
- [ ] Nothing under `skills/mirrored/` was edited by hand
