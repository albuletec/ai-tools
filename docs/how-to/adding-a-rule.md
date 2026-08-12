# Adding a Rule

A rule is a markdown file that an assistant loads into its context — always, or when a
condition matches. It is not invoked like a skill and it is not a separate agent: it is
standing instruction, layered onto whatever the assistant is already doing.

## File location

One flat file per rule:

```
common/rules/{name}.md
```

Drop it here and it appears in the `ait` wizard immediately — no registry to update. Rules
have no supporting files: they are a flat `.md`, not a directory, so nothing is copied
alongside them.

`common/rules/README.md` documents the format and is skipped by the scanner. Do not rename it
— it would then be discovered as an item, fail validation for having no frontmatter, and make
`ait validate` exit non-zero.

## Frontmatter

```markdown
---
name: typescript-conventions
description: How TypeScript is written in this repo and what to check before finishing.
paths: ["src/**/*.ts"]
assistants:
  cursor:
    globs: ["src/**/*.ts"]
  windsurf:
    trigger: glob
    globs: ["src/**/*.ts"]
---

Rule text goes here.
```

### Required fields

| Field | Notes |
|-------|-------|
| `name` | Lowercase letters, numbers and hyphens only. Must match the file name — validation refuses a mismatch, so the same rule cannot install under two identities. |
| `description` | One line. Shown in the wizard, emitted into the Claude Code and Windsurf files. |

Rules have no `model` or `tools`. They are instructions loaded into an existing context, not
an agent with its own capabilities.

## The `assistants:` block

Claude Code is always supported. Cursor and Windsurf each need a key:

```yaml
assistants:
  cursor:
  windsurf:
    trigger: always_on
```

Activation config lives here rather than at the top level, because the three assistants do not
share a vocabulary for *when* a rule loads:

| Assistant | Keys | Behaviour |
|-----------|------|-----------|
| Claude Code | `paths` | Load the rule only when a matching file is in play. Absent means always loaded. A top-level `paths` carries over. |
| Cursor | `alwaysApply`, `globs`, `description` | Which keys are present selects one of four activation modes. |
| Windsurf | `trigger`, `description`, `globs` | `trigger` is required and comes from a fixed list of five. |

The whole block is stripped before the file is written, so a `trigger` written for Windsurf can
never appear in the Claude Code file. That is why rules are rendered explicitly per assistant
rather than passed through the way agents and skills are.

## Cursor's four activation modes

| Mode | Declared as | Effect |
|------|-------------|--------|
| Always | `alwaysApply: true` | In context for every request |
| Auto Attached | `globs: ["src/**"]` | Attached when a matching file is in play |
| Agent Requested | `description: "..."` | The model decides, using the description |
| Manual | none of the three | Only when referenced by name |

Two things follow from that table:

**A Cursor `description` must be declared under `assistants.cursor`.** It is deliberately
**not** inherited from the top-level `description`, unlike every other shared key. On Cursor
the presence of a `description` is what selects Agent Requested activation, so carrying the
top-level one over would silently change the activation mode of every rule — all of them have
a top-level description, because it is required.

**`alwaysApply: false` is never synthesised.** An absent key already means false, and writing
it out would make a Manual rule indistinguishable from an Auto Attached one when reviewing the
installed file.

Setting both `alwaysApply: true` and `globs` is refused. `alwaysApply` takes precedence, so the
`globs` would be silently ignored — better to fail loudly than install a rule whose declared
scope is not the one it has.

## Windsurf's five triggers

| `trigger` | When the rule loads | Also needs |
|-----------|--------------------|------------|
| `always_on` | Every request | — |
| `manual` | Only when referenced by name | — |
| `model_decision` | When the model judges it relevant | a description |
| `glob` | When a matching file is in play | `globs` |
| `agent` | When the agent requests it | a description |

`trigger` is required: `ait validate` refuses a Windsurf rule without one, and no default is
applied. A default would install a rule with an activation its author never chose, which is
exactly the class of defect the fail-closed checks exist to prevent. An unrecognised value is
refused too, the same way an unknown hook event is.

For `model_decision` and `agent`, a top-level `description` satisfies the requirement — a
Windsurf rule always receives one, so it only needs restating under `assistants.windsurf` to
say something different there.

## Write activation lists inline

`paths` and `globs` must be written **inline on one line**:

```yaml
globs: ["src/**/*.ts", "test/**/*.ts"]     # correct
```

```yaml
globs:                                     # refused
  - "src/**/*.ts"
```

A block sequence reads as an empty value, so the key would be dropped from the installed file
and the rule would load with a **wider** scope than declared — a glob-restricted rule silently
becoming an unrestricted one. `ait validate` refuses it rather than let a dropped restriction
pass as a formatting preference.

A value declared under `assistants:` is re-emitted verbatim, exactly as written. If it contains
`: `, quote it in the source file, or the installed file will not parse.

## Placeholder tokens

```markdown
Read `{instructionsFile}` for anything this rule does not cover.
```

| Assistant | Resolves to |
|----------|-------------|
| Claude Code | `CLAUDE.md` |
| Others | `AGENTS.md` |

Any other `{token}` is left alone.

## Install paths

| Assistant | Global | Local |
|-----------|--------|-------|
| Claude Code | `~/.claude/rules/{name}.md` | `.claude/rules/{name}.md` |
| Cursor | `~/.cursor/rules/{name}.mdc` | `.cursor/rules/{name}.mdc` |
| Windsurf | `~/.codeium/windsurf/rules/{name}.md` | `.windsurf/rules/{name}.md` |

The source file is always `.md`. The `.mdc` rename happens in
`scripts/assistants/cursor.sh` and nowhere else. Override the global base with
`AIT_CURSOR_USER_DIR` or `AIT_WINDSURF_USER_DIR`.

## Why Copilot is excluded

Copilot's nearest equivalent is `.github/instructions/{name}.instructions.md`, which selects
files with `applyTo:` and has its own precedence relative to
`.github/copilot-instructions.md`. That is a different artifact with different semantics, not
the same one under another name, so `Rule` is absent from `copilot_types()` — the wizard never
offers it, and a direct `copilot_install {name} rule ...` returns non-zero and writes nothing.

## Full example

```markdown
---
name: logging-conventions
description: How this service logs, and which dimensions every log line must carry.
paths: ["src/**/*.ts"]
assistants:
  cursor:
    globs: ["src/**/*.ts"]
    alwaysApply: false
  windsurf:
    trigger: glob
    globs: ["src/**/*.ts"]
---

Every log line goes through the shared logger. Never call `console.log` directly.

Required dimensions on every line:

- `zone` — the deployment zone
- `brand` — the canonical brand name

Check `{instructionsFile}` for anything this rule does not cover.
```

## Checklist

- [ ] `common/rules/{name}.md`, with `name` matching the file name
- [ ] Non-empty one-line `description`
- [ ] `assistants:` key for each non-Claude assistant that should get it
- [ ] Windsurf: a `trigger`, plus `globs` for `glob` or a description for `model_decision` / `agent`
- [ ] Cursor: exactly one activation mode — not `alwaysApply: true` and `globs` together
- [ ] Cursor `description` declared under `assistants.cursor` if you want Agent Requested
- [ ] `paths` and `globs` written inline on one line
- [ ] `ait validate` exits 0
