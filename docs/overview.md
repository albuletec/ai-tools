# Overview

`ai-tools` is a single source of truth for AI coding-assistant tooling. You write each agent,
skill, rule, or hook once and install it into any project for whichever assistant you are
using. The CLI (`ait`) handles rendering, validation, and wiring automatically.

## Artifact types

| Type | What it is | Assistants |
|------|-----------|------------|
| **Agent** | A specialised subagent with its own system prompt and tool set | Claude Code, Copilot, Cursor |
| **Skill** | A slash-command workflow invocable by the user or the model | Claude Code, Copilot, Cursor, Windsurf |
| **Rule** | A markdown file loaded into context, always or when a condition matches | Claude Code, Cursor, Windsurf |
| **Hook** | A shell script that intercepts tool calls | Claude Code only |

Windsurf exposes Skill and Rule: Cascade is its sole agent and there is no subagent definition
format to translate an agent into. Hooks are Claude Code only — Copilot and Windsurf have no
tool-call event system, and Cursor's hooks live in `.cursor/hooks.json` rather than a
settings file, which is not modelled yet. Rules exclude Copilot, whose nearest equivalent —
`.github/instructions/{name}.instructions.md` — selects files with `applyTo:` and has its own
precedence, making it a different artifact rather than the same one renamed.

## Supported assistants

| Assistant | Agents | Skills | Rules | Hooks | Instructions file |
|-----------|--------|--------|-------|-------|-------------------|
| Claude Code | `~/.claude/agents/` or `.claude/agents/` | `~/.claude/skills/{name}/` or `.claude/skills/{name}/` | `~/.claude/rules/` or `.claude/rules/` | `~/.claude/hooks/` or `.claude/hooks/` + `settings.json` wiring | `CLAUDE.md` |
| Copilot | `~/.copilot/agents/` or `.github/agents/` | `~/.copilot/skills/{name}/` or `.github/skills/{name}/` | unsupported | unsupported | `AGENTS.md` |
| Cursor | `~/.cursor/agents/` or `.cursor/agents/` | `~/.cursor/skills/{name}/` or `.cursor/skills/{name}/` | `~/.cursor/rules/{name}.mdc` or `.cursor/rules/{name}.mdc` | unsupported | `AGENTS.md` |
| Windsurf | unsupported | `~/.codeium/windsurf/skills/{name}/` or `.windsurf/skills/{name}/` | `~/.codeium/windsurf/rules/` or `.windsurf/rules/` | unsupported | `AGENTS.md` |

Override the global base with `AIT_COPILOT_USER_DIR`, `AIT_CURSOR_USER_DIR` or
`AIT_WINDSURF_USER_DIR` when your setup puts them somewhere else.

## How items stay DRY

Each artifact file is written once: keys that mean the same thing everywhere sit at the top
level, and anything assistant-specific sits under `assistants:`. Three mechanisms render the
file correctly for every target assistant at install time.

### 1. The `assistants:` block

Claude Code is always supported — no entry needed. Every other assistant must be explicitly
opted in:

```yaml
assistants:
  copilot:
  cursor:
```

Presence alone means "supported with all defaults." Per-item overrides sit under the
assistant key:

```yaml
assistants:
  claude-code:
    model: claude-opus-5
    tools: [Bash, Read, Write]
  copilot:
    model: gpt-5
    tools: [execute, read, search]
    target: vscode
    argument-hint: "[pr-number]"
    user-invocable: false
    disable-model-invocation: true
  cursor:
    model: composer-2
    readonly: true
    is_background: true
```

`claude-code:` is the one key that is configuration rather than opt-in — Claude Code is
always supported, with or without it.

The entire `assistants:` block is stripped before the file is written to disk, so no
assistant ever sees another's configuration.

Keys that mean the same thing everywhere — `argument-hint`, `user-invocable`,
`disable-model-invocation`, `paths` — carry over from the top level automatically. Restate
one under `assistants:` only to give a specific assistant a different value.

### Rule activation is per-assistant by nature

A rule's activation keys are the exception to the carry-over rule, because the three
assistants that read rule directories do not describe activation the same way at all: Claude
Code has `paths`, Cursor has `alwaysApply` / `globs` / `description`, and Windsurf has a
`trigger` from a fixed vocabulary. Those live under `assistants:` and nowhere else, so a
`trigger` written for Windsurf can never leak into the Claude Code file — which is why rules
are rendered explicitly per assistant rather than passed through.

Cursor's `description` deliberately does **not** carry over from the top level. On Cursor a
present `description` is what selects Agent Requested activation, so inheriting the top-level
one would quietly change the activation mode of every rule that has a description — that is,
all of them. It must be declared as `assistants.cursor.description` to appear.

### 2. `{placeholder}` tokens

Tokens in the body are substituted per assistant before writing:

| Token | Claude Code | Others |
|-------|-------------|--------|
| `{instructionsFile}` | `CLAUDE.md` | `AGENTS.md` |

No other token is touched, so `{path}`, `{repo}` and friends can be used freely in prose.

### 3. Per-assistant `model` and `tools`

Neither key means the same thing across assistants, so neither is shared. Both are declared
under `assistants.{name}`, in that assistant's own vocabulary:

```yaml
assistants:
  claude-code:
    model: claude-opus-5
    tools: [Bash, Read, Write]
  copilot:
    tools: [execute, read, edit]
```

Nothing is mapped between the two lists. Whatever an assistant declares is what its
installed file gets, verbatim.

Write the list inline on one line — `tools: [A, B]`. A block sequence under an `assistants:`
key reads as an empty value, which drops the restriction rather than applying it.

An agent that opts into Copilot **must** declare `assistants.copilot.tools`. Copilot reads
an absent `tools` key as "every tool enabled", so `ait validate` refuses the install rather
than let the omission hand the agent everything.

Cursor is different again: its subagents have no `tools` key and inherit everything from the
parent. `readonly: true` is the only restriction available, and it is declared explicitly as
`assistants.cursor.readonly` — never inferred from a tool list.

## Frontmatter is parsed as YAML

Scalars are read as YAML values, not as raw lines, so all of these work and all of them
collapse to one logical string before being re-emitted:

```yaml
description: plain text
description: "text with a colon: like this"
description: >-
  folded across
  several lines
description: |
  literal block
  across lines
description: plain value
  continued on an indented line
```

Anything re-emitted for another assistant is re-quoted, because a value read out of YAML is
not itself valid YAML. Inside an `assistants:` block only the inline form of a sequence is
read, so `tools` must be written as `tools: [A, B]` on one line.

## Validation

Nothing is written unless the item validates for the target assistant. The wizard shows a
failing item with its reason and refuses to select it; `_wizard_install` checks again as a
final gate; `ait validate` runs every check across the whole repo for CI.

See [adding an agent](how-to/adding-an-agent.md),
[adding a skill](how-to/adding-a-skill.md), [adding a rule](how-to/adding-a-rule.md) and
[adding a hook](how-to/adding-a-hook.md) for what each type must satisfy.

## Auto-discovery

There is no registry for items. Drop a file in the right directory and it appears in the
`ait` wizard immediately:

```
common/agents/{name}.md              # agent
common/skills/{name}/SKILL.md        # skill (flat .md also works)
common/rules/{name}.md               # rule (README.md is skipped, being the format doc)
claude-code/hooks/{name}.sh          # hook
```

Assistants *are* registered, in one place: `AIT_ASSISTANTS` in `scripts/registry.sh`. The set
of item types is written down in one place too: `AIT_ITEM_TYPES` in `scripts/collect.sh`,
which `ait list`, `validate_repo` and the golden test section all iterate.

## Project context files

One thing `ait` handles is not an item: the per-project context file each assistant reads at
the repo root — `CLAUDE.md`, `.github/copilot-instructions.md`, `AGENTS.md`. There is exactly
one per project rather than a list of composable pieces, so it cannot be discovered,
validated or rendered the way an item is. `ait init` writes it from a starter template
instead.

| Assistant | Global | Local |
|-----------|--------|-------|
| Claude Code | `~/.claude/CLAUDE.md` | `CLAUDE.md` |
| Copilot | — | `.github/copilot-instructions.md` |
| Cursor | — | `AGENTS.md` |
| Windsurf | — | `AGENTS.md` |

Cursor and Windsurf share one `AGENTS.md`, so selecting both writes it once. Only Claude Code
has a documented home-directory context file, so it is the only one with a global target.
Templates are copied verbatim — a `{curly}` token in one is a prompt for the reader, not a
placeholder `ait` resolves — and an existing file is never overwritten without an explicit
`y`. Each assistant declares its own targets through `{name}_init_targets`, dispatched from
the registry, so init needs no `case` on an assistant slug anywhere.
