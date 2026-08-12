# Cursor Assistant

Agents, skills and rules are supported. Hooks are not: Cursor does have a hooks system, but it
is configured through `.cursor/hooks.json` rather than a settings file, and `ait` does not model
that yet.

## Do you need this assistant?

Cursor reads `.claude/agents/`, `.claude/skills/`, `~/.claude/agents/` and `~/.claude/skills/`
as a compatibility layer, with `.cursor/` taking precedence on a name clash. So a Claude Code
install is already visible to Cursor. Installing natively gets you `.cursor/` paths and
Cursor's own frontmatter — in particular `readonly`, which is the only way to restrict a
Cursor subagent at all.

## Supported artifact types

| Type | Supported |
|------|-----------|
| Agent | yes |
| Skill | yes |
| Rule | yes |
| Hook | no |

## Install paths

| Type | Global | Local |
|------|--------|-------|
| Agent | `~/.cursor/agents/{name}.md` | `.cursor/agents/{name}.md` |
| Skill | `~/.cursor/skills/{name}/SKILL.md` | `.cursor/skills/{name}/SKILL.md` |
| Rule | `~/.cursor/rules/{name}.mdc` | `.cursor/rules/{name}.mdc` |

Override the global base with `AIT_CURSOR_USER_DIR`.

Rules are the one type whose extension changes on install: the source is always
`common/rules/{name}.md`, and the `.mdc` rename happens in `scripts/assistants/cursor.sh` and
nowhere else.

## Opting an item into Cursor

```yaml
assistants:
  cursor:
```

Items without this key do not appear in the wizard when Cursor is selected.

## Agent frontmatter

Per [cursor.com/docs/subagents](https://cursor.com/docs/subagents). Every field is optional;
`name` defaults to the filename and `model` defaults to `inherit`.

```yaml
---
name: code-reviewer
description: "Reviews implementations against the plan."
readonly: true
---
```

### There is no `tools` key

A Cursor subagent **inherits every tool from its parent**, including MCP tools. There is no
per-tool list to emit, so no agent declares `assistants.cursor.tools` — the key would have
nowhere to go.

The one available restriction is `readonly`, and it is declared, not derived. `ait` emits
`readonly` only when the item sets `assistants.cursor.readonly`:

```yaml
assistants:
  cursor:
    readonly: true
```

| `assistants.cursor.readonly` | Cursor result |
|------------------------------|---------------|
| `true` | `readonly: true` |
| `false` | `readonly: false` |
| absent | no `readonly` key |

None of the six shipped agents sets it, because all of them hold a shell. An agent that can
redirect output into a file was never really read-only on any assistant, Claude Code
included, so inferring `readonly` from a tool list would have been a claim the tool could not
back.

### Per-assistant agent overrides

```yaml
assistants:
  cursor:
    model: composer-2
    readonly: true
    is_background: true
```

| Key | Type | Notes |
|-----|------|-------|
| `model` | string | `inherit`, or an id such as `composer-2` or `claude-opus-5[effort=high]`. Omitted when absent, which means `inherit`. |
| `readonly` | bool | Declared here or not at all — nothing derives it |
| `is_background` | bool | Run the subagent in the background |

## Skill frontmatter

Per [cursor.com/docs/skills](https://cursor.com/docs/skills). `name` and `description` are
both required, and **`name` must match the parent folder name** — `ait` emits the directory
name for exactly that reason, and validation refuses an item whose frontmatter `name`
disagrees with it.

```yaml
---
name: pr-description
description: "Write a pull request description from the current branch's changes."
---
```

### Per-assistant skill overrides

```yaml
assistants:
  cursor:
    paths: "src/**"
    disable-model-invocation: true
    metadata:
      team: platform
```

| Key | Type | Notes |
|-----|------|-------|
| `paths` | string | Glob restricting the skill to matching files. Carries over from a top-level `paths`. |
| `disable-model-invocation` | bool | Only include the skill when invoked as `/name`. Carries over from the top level. |
| `metadata` | map | Free-form; Cursor does not act on it |

## Rule frontmatter

A `.mdc` rule is identified by its **filename**, so no `name` key is emitted. The documented
keys are `description`, `globs` and `alwaysApply`, and only the ones declared under
`assistants.cursor` are written:

```yaml
---
globs: ["src/**/*.ts"]
---
```

### The four activation modes

Which keys are present is what selects the mode:

| Mode | Declared as | Effect |
|------|-------------|--------|
| Always | `alwaysApply: true` | In context for every request |
| Auto Attached | `globs: ["src/**"]` | Attached when a matching file is in play |
| Agent Requested | `description: "..."` | The model decides, using the description |
| Manual | none of the three | Only when referenced by name |

### `description` does not carry over

This is the one shared key that is deliberately **not** inherited from the top-level
`description`. On Cursor a present `description` is what selects Agent Requested activation, so
carrying the top-level one over would silently switch every rule to that mode — every rule has
a top-level description, because it is required. Declare it explicitly to opt in:

```yaml
assistants:
  cursor:
    description: "Read when changing anything under src/."
```

### `alwaysApply: false` is never synthesised

An absent key already means false. Emitting it would make a Manual rule indistinguishable from
an Auto Attached one when reading the installed file, so `ait` writes it only when the item
declares it.

### Contradictory activation is refused

Setting both `alwaysApply: true` and `globs` fails validation. `alwaysApply` takes precedence,
so the `globs` would be silently ignored — a rule whose declared scope is not the scope it has.
`validate.sh` has one channel and everything it prints is fatal, so this is a refusal rather
than a warning.

A non-boolean `alwaysApply` is refused too.

### Values are emitted verbatim

Everything under `assistants.cursor` is written through exactly as authored, so a `description`
containing `: ` must be quoted in the source file or the installed rule will not parse. Write
`globs` inline on one line: a block sequence reads as empty, which would drop the key and widen
the rule's scope, so validation refuses it.

## Supporting files

Cursor documents `scripts/`, `references/` and `assets/` inside a skill directory, so
everything except `SKILL.md` is copied across with its subdirectories intact. Rules are flat
files and bundle nothing.

## Project context file

`ait init` writes the starter `AGENTS.md` from `cursor/init/AGENTS.md`:

| Scope | Target |
|-------|--------|
| Global | — no target offered |
| Local | `AGENTS.md` at the project root |

`AGENTS.md` is a repository file by definition, and Cursor's global equivalent is User Rules,
which live in the settings UI rather than on disk — so there is genuinely nothing to write at
global scope, and `ait init` reports Cursor as skipped there.

Windsurf reads the same `AGENTS.md`, so selecting both writes the file once and the confirmation
screen names both against it. The two templates are kept byte-identical for exactly that reason.

`.cursorrules` is legacy and is **not** written. `ait init` says so on the confirmation screen
rather than writing a file Cursor is moving away from.

## Placeholder substitution

`{instructionsFile}` → `AGENTS.md`. Cursor reads `AGENTS.md`.

## Current items

### Agents

None of the six declares `assistants.cursor.readonly`, so none is installed with a `readonly`
key: every one of them holds a shell.

| Name | Cursor `readonly` |
|------|-------------------|
| `code-planner` | not declared |
| `code-reviewer` | not declared |
| `code-tester` | not declared |
| `code-writer` | not declared |
| `observability-reviewer` | not declared |
| `security-reviewer` | not declared |

### Skills

All six skills opt into Cursor: `dependency-review`, `grill-me`, `incident-runbook`,
`pr-description`, `standards-check`, `update-workspace`.

### Rules

None yet. `common/rules/` ships with its format `README.md` only.

### Hooks

Not supported.

## References

- [Subagents](https://cursor.com/docs/subagents) — agent locations, frontmatter, tool
  inheritance, `readonly`
- [Skills](https://cursor.com/docs/skills) — `SKILL.md` schema, locations, supporting
  directories
- [Rules](https://cursor.com/docs/rules) — `.mdc` frontmatter, the four activation modes,
  rule locations, `AGENTS.md`
