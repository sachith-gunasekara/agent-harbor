<!--
For a skill written here, under skills/own/.
Use ?template=skill.md on the compare URL.
-->

## What the skill does

<!-- One or two sentences. The same thing the frontmatter description says, in
     your own words. -->

## When it should fire

<!-- The description is the whole of what the agent sees when deciding whether to
     load the skill, so triggering is the design. Which phrasings should reach it,
     and which nearby ones should not? -->

## Why it is a skill

<!-- Rather than a prompt, a script, or nothing at all. What does it save doing
     from scratch each time? -->

## Verification

<!-- Skills are judged by whether they fire and whether following them works.
     Say what you ran, including at least: -->

```
./scripts/validate-skills.sh
npx skills add . -l
```

---

- [ ] Directory name matches the frontmatter `name`, and the name is unique across
      `skills/own/` and `skills/mirrored/`
- [ ] `description` says *what it does* **and** *when to use it*, with the
      vocabulary a user would actually type, and is under 1024 characters
- [ ] Long or rarely needed material is in `references/`, not inlined in `SKILL.md`
- [ ] Deterministic steps are in `scripts/`, executable, with a usage header and a
      `--dry-run` on anything that writes
- [ ] `./scripts/gen-catalog.sh` was run so the README and catalog list it
