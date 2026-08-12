# Cursor Assistant

Agents and skills are supported. Hooks are not: Cursor does have a hooks system, but it is
configured through `.cursor/hooks.json` rather than a settings file, and `ait` does not model
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
| Hook | no |

## Install paths

| Type | Global | Local |
|------|--------|-------|
| Agent | `~/.cursor/agents/{name}.md` | `.cursor/agents/{name}.md` |
| Skill | `~/.cursor/skills/{name}/SKILL.md` | `.cursor/skills/{name}/SKILL.md` |

Override the global base with `AIT_CURSOR_USER_DIR`.

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
per-tool list to translate into, so the source `tools:` list cannot be reproduced directly.

The one available restriction is `readonly`, and `ait` derives it: a non-empty tool list that
grants no write access **and** no indirect route to one renders `readonly: true`.

| Source `tools` | Cursor result | Why |
|----------------|---------------|-----|
| `[Read, Grep]` | `readonly: true` | Read-only, no escape |
| `[Read, Write]` | no `readonly` | `Write` is a write tool |
| `[Bash, Read]` | no `readonly` | `Bash` can write through a redirection |
| `[Task, Read]` | no `readonly` | `Task` can delegate to something that writes |
| `[Read, mcp__x__y]` | no `readonly` | An unrecognised tool is assumed capable |
| absent | no `readonly` | No restriction was declared |

This is deliberately conservative. None of the six shipped agents is marked `readonly`,
because all of them hold `Bash` — which means they were never really read-only on any
assistant, Claude Code included.

Set `assistants.cursor.readonly` explicitly to override the derived value.

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
| `readonly` | bool | Overrides the value derived from `tools` |
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

## Supporting files

Cursor documents `scripts/`, `references/` and `assets/` inside a skill directory, so
everything except `SKILL.md` is copied across with its subdirectories intact.

## Placeholder substitution

`{instructionsFile}` → `AGENTS.md`. Cursor reads `AGENTS.md`.

## Current items

### Agents

| Name | Cursor `readonly` |
|------|-------------------|
| `code-planner` | no — holds `Bash` |
| `code-reviewer` | no — holds `Bash` |
| `code-tester` | no — holds `Bash` and `Write` |
| `code-writer` | no — holds `Bash` and `Write` |
| `observability-reviewer` | no — holds `Bash` |
| `security-reviewer` | no — holds `Bash` |

### Skills

All six skills opt into Cursor: `dependency-review`, `grill-me`, `incident-runbook`,
`pr-description`, `standards-check`, `update-workspace`.

### Hooks

Not supported.

## References

- [Subagents](https://cursor.com/docs/subagents) — agent locations, frontmatter, tool
  inheritance, `readonly`
- [Skills](https://cursor.com/docs/skills) — `SKILL.md` schema, locations, supporting
  directories
