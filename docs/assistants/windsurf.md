# Windsurf Assistant

Skills only. Windsurf has no subagent definition format and no tool-call event system, so
Agent and Hook are both hidden when Windsurf is selected in the wizard — the same way Hook is
hidden for Copilot.

## Why agents are unsupported

Cascade is Windsurf's single agent. There is no file format for defining an additional agent
with its own instructions and tool set, so there is nothing for `ait` to translate an agent
into. Rendering one as an always-on rule was considered and rejected: a rule is not a
subagent, it would apply to every request rather than being invoked deliberately, and it
would silently change what the agent file means.

If you want the agent instructions available in Windsurf, the honest route is `AGENTS.md`,
which Windsurf reads through the same rules engine.

## Supported artifact types

| Type | Supported |
|------|-----------|
| Agent | no |
| Skill | yes |
| Hook | no |

## Install paths

| Type | Global | Local |
|------|--------|-------|
| Skill | `~/.codeium/windsurf/skills/{name}/SKILL.md` | `.windsurf/skills/{name}/SKILL.md` |

Note that the global base is the Codeium config tree, not a dotfile directly under `$HOME`.
Override it with `AIT_WINDSURF_USER_DIR`.

Windsurf also scans `.claude/skills/`, `~/.claude/skills/`, `.agents/skills/` and
`~/.agents/skills/` for compatibility, so a Claude Code install is already visible to it.
Installing natively just gets the first-class location.

## Opting an item into Windsurf

```yaml
assistants:
  windsurf:
```

## Skill frontmatter

Per [docs.devin.ai/desktop/cascade/skills](https://docs.devin.ai/desktop/cascade/skills).
`name` and `description` are both required; `name` must be lowercase letters, numbers and
hyphens only. No optional fields are documented, so `ait` emits exactly those two.

```yaml
---
name: pr-description
description: "Write a pull request description from the current branch's changes."
---
```

Because nothing else is emitted, a skill that relies on `argument-hint` or
`disable-model-invocation` still installs — it just loses those hints on Windsurf. That is a
deliberate omission rather than an oversight: inventing frontmatter keys that the reader does
not document risks the file being rejected outright.

## Supporting files

Windsurf documents bundling templates, checklists and examples alongside `SKILL.md`, so
everything except `SKILL.md` is copied across with its subdirectories intact.

## Placeholder substitution

`{instructionsFile}` → `AGENTS.md`. Windsurf processes `AGENTS.md` through its rules engine —
root-level files are always on, subdirectory files auto-glob to that directory.

## Rules and workflows are out of scope

Windsurf also reads `.devin/rules/*.md` (with `.windsurf/rules/*.md` as a legacy fallback)
and a global `~/.codeium/windsurf/memories/global_rules.md`. Those are a different artifact
type from anything `ait` models — rules carry a `trigger` of `always_on`, `model_decision`,
`glob` or `manual`, and the global one is a single file rather than a directory of items, so
installing several would mean merging into shared state. If rules become worth supporting
they should be a new item type, not a skill rendered sideways.

## Current items

### Skills

All six skills opt into Windsurf: `dependency-review`, `grill-me`, `incident-runbook`,
`pr-description`, `standards-check`, `update-workspace`.

### Agents and hooks

Not supported.

## References

- [Skills](https://docs.devin.ai/desktop/cascade/skills) — `SKILL.md` schema, skill
  locations, supporting files
- [Memories and rules](https://docs.devin.ai/desktop/cascade/memories) — rule locations,
  `trigger` values, `AGENTS.md` handling
