# Conventional Commits v1.0.0 — the rules that matter

Source: https://www.conventionalcommits.org/en/v1.0.0/ (CC BY 3.0)

## Structure

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Normative rules (paraphrased from the specification)

1. A commit is prefixed with a type — a noun such as `feat` or `fix` — followed by
   an optional scope, an optional `!`, then a required colon and space.
2. `feat` is required when the commit adds a new feature.
3. `fix` is required when the commit fixes a bug.
4. A scope may follow the type. It is a noun describing a section of the codebase,
   wrapped in parentheses: `fix(parser):`.
5. A description follows immediately after the colon and space, summarising the
   change.
6. A longer body may follow, beginning one blank line after the description.
7. The body is free-form and may run to any number of newline-separated paragraphs.
8. One or more footers may follow, one blank line after the body. Each consists of
   a word token, then either `: ` or ` #`, then a value.
9. Footer tokens use `-` in place of whitespace (`Acked-by`). This is what
   distinguishes the footer block from a multi-paragraph body. `BREAKING CHANGE`
   is the sole exception and may contain a space.
10. A footer value may contain spaces and newlines; parsing stops at the next
    valid token/separator pair.
11. Breaking changes are indicated in the type/scope prefix or in a footer.
12. As a footer, a breaking change is the uppercase text `BREAKING CHANGE`, a
    colon, a space, and a description.
13. As a prefix, it is `!` immediately before the `:`. When `!` is used, the
    `BREAKING CHANGE:` footer may be omitted and the description explains the break.
14. Types other than `feat` and `fix` may be used.
15. None of this is case-sensitive to implementors, except `BREAKING CHANGE`,
    which must be uppercase.
16. `BREAKING-CHANGE` is synonymous with `BREAKING CHANGE` as a footer token.

## SemVer mapping

- `fix` → PATCH
- `feat` → MINOR
- any type carrying a breaking change → MAJOR

Types beyond `feat` and `fix` carry no implicit version effect unless they break
something.

## Trailer mechanics (git-interpret-trailers)

Footers are git trailers — RFC 822-ish lines at the end of the message. Git
recognises a trailer block as a group of lines at the end of the message that is
either all trailers, or contains at least one known trailer and is at least 25%
trailers, preceded by a blank line.

Reading rules worth remembering:

- No whitespace before or inside the token. Any amount of space is allowed between
  the token and its separator.
- Only `:` is a separator by default (`trailer.separators` can add others; `=` is
  always accepted on the command line).
- A value may fold across lines if continuation lines start with whitespace:

  ```
  Refs: this value continues
    onto the following line
  ```

- `git interpret-trailers --parse <file>` prints just the trailers, unfolded —
  the reliable way to check whether a footer block will actually be seen as one.
- `git interpret-trailers --trailer "K: V" --in-place <file>` inserts a trailer in
  the right place, adding the blank line if needed.
- `git commit --trailer "K: V"` does the same inline (git ≥ 2.32).

## Guidance from the spec's FAQ

- **Initial development**: write commits as though you have already shipped.
  Somebody is using the code, even if that somebody is a teammate.
- **Casing of the type**: any casing is permitted, but be consistent. In practice
  lowercase is near-universal.
- **A commit that fits more than one type**: split it. The spec explicitly frames
  this as a benefit — the format pushes toward better-organised commits.
- **Wrong type used, not yet merged**: `git rebase -i` to fix it. After release,
  cleanup depends on your tooling.
- **Type not in the spec at all** (`feet` instead of `feat`): not fatal. The commit
  is simply invisible to spec-driven tooling.
- **Contributors who don't follow the convention**: a squash-merge workflow lets a
  maintainer write the final message at merge time, so casual contributors carry no
  burden.
- **Reverts**: the spec deliberately does not define revert semantics. The
  recommended pattern is a `revert` type plus a footer naming the reverted SHAs:

  ```
  revert: let us never again speak of the noodle incident

  Refs: 676104e, a215868
  ```

## Type vocabulary in practice

`@commitlint/config-conventional`, derived from the Angular convention, is what
most repos actually enforce:

`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`,
`chore`, `revert`

Typical enforced rules alongside it: `type-case` lower-case, `type-empty` never,
`subject-empty` never, `subject-full-stop` never, `subject-case` not
start/pascal/upper-case, `body-leading-blank`, `footer-leading-blank`, and a
header length cap (72 or 100). If `commitlint.config.*` exists in the repo, its
`type-enum` and rules override everything above.

## Why the format is worth the friction

- Changelogs generate themselves.
- The version bump is derivable from the commits in a release.
- Reviewers and future readers can skim intent from `git log --oneline`.
- Build and publish pipelines can key off commit types.
- Newcomers can navigate history by structure rather than by reading everything.
