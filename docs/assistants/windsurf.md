# Windsurf Assistant

Skills and rules. Windsurf has no subagent definition format and no tool-call event system, so
Agent and Hook are both hidden when Windsurf is selected in the wizard — the same way Hook is
hidden for Copilot.

## Why agents are unsupported

Cascade is Windsurf's single agent. There is no file format for defining an additional agent
with its own instructions and tool set, so there is nothing for `ait` to translate an agent
into. Rendering one as an always-on rule was considered and rejected: a rule is not a
subagent, it would apply to every request rather than being invoked deliberately, and it
would silently change what the agent file means. That reasoning still holds now that rules
are supported as their own type — an agent is not installed as a rule, and a rule is authored
as one.

If you want the agent instructions available in Windsurf, the honest route is `AGENTS.md`,
which Windsurf reads through the same rules engine.

## Supported artifact types

| Type | Supported |
|------|-----------|
| Agent | no |
| Skill | yes |
| Rule | yes |
| Hook | no |

## Install paths

| Type | Global | Local |
|------|--------|-------|
| Skill | `~/.codeium/windsurf/skills/{name}/SKILL.md` | `.windsurf/skills/{name}/SKILL.md` |
| Rule | `~/.codeium/windsurf/rules/{name}.md` | `.windsurf/rules/{name}.md` |

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

## Rule frontmatter

A Windsurf rule installs with `trigger`, `description` and — when declared — `globs`:

```yaml
---
trigger: glob
description: "How TypeScript is written in this repo."
globs: ["src/**/*.ts"]
---
```

### The five triggers

| `trigger` | When the rule loads | Also required |
|-----------|--------------------|---------------|
| `always_on` | Every request | — |
| `manual` | Only when referenced by name | — |
| `model_decision` | When the model judges it relevant | a description |
| `glob` | When a matching file is in play | `globs` |
| `agent` | When the agent requests it | a description |

`trigger` is **required**: `ait validate` refuses a rule that opts into Windsurf without one,
and no default is applied, because a default would install the rule with an activation its
author never chose. An unrecognised value is refused as well — the same treatment an unknown
hook event gets. The authoritative list is `_AIT_RULE_TRIGGERS` in `scripts/validate.sh`.

### When `description` is required

For `model_decision` and `agent`, Windsurf needs prose to decide with, so a description must
resolve from somewhere. A top-level `description` satisfies it — every item has one, since it
is required — and only needs restating as `assistants.windsurf.description` to differ there.

`description` is always emitted, unlike on Cursor where its presence selects an activation
mode. An override is written through verbatim as authored; a top-level value has been read out
of YAML by `fm_get`, so it is re-quoted on the way back in.

### When `globs` is required

For `trigger: glob`, `assistants.windsurf.globs` must be set: a glob-triggered rule with no
pattern never fires, which is the same class of defect as an unknown hook event. Write it
inline on one line — a block sequence reads as empty, which would drop the key and widen the
rule's scope, so validation refuses one.

### A note on the rules directory

`ait` installs to `.windsurf/rules/` locally and `{user dir}/rules/` globally. Windsurf's
documentation has begun referring to `.devin/rules/` after the Devin rebrand, but that path is
recent and not yet universally recognised across Windsurf versions, whereas `.windsurf/rules/`
is. If a future release drops `.windsurf/rules/`, `_windsurf_dir` in
`scripts/assistants/windsurf.sh` is the single place to change.

Windsurf also reads a global `~/.codeium/windsurf/memories/global_rules.md`. That is one file
rather than a directory of items, so installing several rules into it would mean merging into
shared state — which `ait` does not do — and it is therefore not a target.

## Workflows are out of scope

Windsurf workflows remain unmodelled. They are a different artifact again, and nothing in the
repo would render into one honestly.

## Project context file

`ait init` writes the starter `AGENTS.md` from `windsurf/init/AGENTS.md`:

| Scope | Target |
|-------|--------|
| Global | — no target offered |
| Local | `AGENTS.md` at the project root |

`AGENTS.md` is a repository file by definition. Windsurf's global equivalent is the single
`memories/global_rules.md` file rather than a context file, so `ait init` reports Windsurf as
skipped at global scope instead of writing somewhere nothing reads.

Cursor reads the same `AGENTS.md`, so selecting both writes the file once and the confirmation
screen names both against it. The two templates are kept byte-identical for exactly that reason.

`.windsurfrules` is legacy and is **not** written. `ait init` says so on the confirmation
screen rather than writing a file Windsurf is moving away from.

## Current items

### Skills

All six skills opt into Windsurf: `dependency-review`, `grill-me`, `incident-runbook`,
`pr-description`, `standards-check`, `update-workspace`.

### Rules

None yet. `common/rules/` ships with its format `README.md` only.

### Agents and hooks

Not supported.

## References

- [Skills](https://docs.devin.ai/desktop/cascade/skills) — `SKILL.md` schema, skill
  locations, supporting files
- [Memories and rules](https://docs.devin.ai/desktop/cascade/memories) — rule locations,
  `trigger` values, `AGENTS.md` handling
