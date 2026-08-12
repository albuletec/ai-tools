# Rules

A rule is a markdown file that an assistant loads into its context — always, or when a
condition matches. Claude Code, Cursor and Windsurf each read a directory of them.

**This file is not a rule.** The scanner in `scripts/collect.sh` skips any file named
`README.md` explicitly. Do not rename it to `rules.md` or anything else: it would then be
discovered as an item, fail validation for having no frontmatter, and make `ait validate`
exit non-zero.

## File location

One flat file per rule:

```
common/rules/{name}.md
```

Drop it here and it appears in the `ait` wizard — there is no registry to update.

## Frontmatter

```markdown
---
name: code-conventions
description: How this codebase is written and what to check before finishing.
paths: ["src/**/*.ts"]
assistants:
  cursor:
    globs: ["src/**/*.ts"]
  windsurf:
    trigger: glob
    globs: ["src/**/*.ts"]
---

Rule text goes here. Read `{instructionsFile}` for the project's own conventions.
```

| Field | Required | Notes |
|-------|----------|-------|
| `name` | yes | Lowercase letters, numbers and hyphens. Must match the file name. |
| `description` | yes | One line. Claude Code and Windsurf both emit it. |
| `assistants:` | no | Opt-in for Cursor and Windsurf, plus per-assistant activation config. Claude Code needs no entry. |

## Per-assistant activation

Activation is per-assistant by nature — the three readers do not share a vocabulary — so it
lives under `assistants:` rather than at the top level.

| Assistant | Keys | Meaning |
|-----------|------|---------|
| Claude Code | `paths` | Load the rule only for matching files. Absent means always loaded. Carries over from a top-level `paths`. |
| Cursor | `alwaysApply`, `globs`, `description` | Picks one of four activation modes — see below. |
| Windsurf | `trigger`, `description`, `globs` | `trigger` is required: `always_on`, `manual`, `model_decision`, `glob` or `agent`. |

Copilot is **not** supported. Its instructions files (`.github/instructions/*.instructions.md`)
use `applyTo:` with different precedence, so `Rule` is absent from `copilot_types()` and a
direct install returns non-zero.

### Cursor's four modes

| Mode | Declared as |
|------|-------------|
| Always | `alwaysApply: true` |
| Auto Attached | `globs: ["src/**"]` |
| Agent Requested | `description: "..."` |
| Manual | none of them |

A Cursor `description` must be declared under `assistants.cursor`. It is deliberately **not**
inherited from the top-level `description`, because its presence alone selects Agent Requested
activation.

### Windsurf's triggers

`description` is required for `model_decision` and `agent`; `globs` is required for `glob`.
A top-level `description` satisfies the first requirement, since Windsurf always receives one.

## Writing activation lists

Write `paths` and `globs` **inline on one line** — `globs: ["src/**", "test/**"]`. A block
sequence reads as an empty value, which would drop the key and install the rule with a wider
scope than you declared, so `ait validate` refuses one.

A value declared under `assistants:` is re-emitted verbatim, so quote it in the source if it
contains `: `.

## Placeholder tokens

`{instructionsFile}` resolves to `CLAUDE.md` for Claude Code and `AGENTS.md` for the others.
Any other `{token}` is left alone.

## Install paths

| Assistant | Global | Local |
|-----------|--------|-------|
| Claude Code | `~/.claude/rules/{name}.md` | `.claude/rules/{name}.md` |
| Cursor | `~/.cursor/rules/{name}.mdc` | `.cursor/rules/{name}.mdc` |
| Windsurf | `~/.codeium/windsurf/rules/{name}.md` | `.windsurf/rules/{name}.md` |

The `.mdc` rename is Cursor-only; the source file is always `.md`.

Full walkthrough: [`../../docs/how-to/adding-a-rule.md`](../../docs/how-to/adding-a-rule.md).
