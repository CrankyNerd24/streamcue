# Git hooks

Version-controlled hooks for StreamCue.

## Enable (once per clone)

Git doesn't auto-use this directory. After cloning, run:

```sh
git config core.hooksPath .githooks
```

## Hooks

- **commit-msg** — appends each commit's subject line as a bullet under the
  `## [Unreleased]` section of `CHANGELOG.md` and stages it into the same
  commit. Skips merges, reverts, changelog-housekeeping commits, and
  duplicate subjects.
