# Overview

`ai-tools` is a single source of truth for AI coding-assistant tooling. You write each agent,
skill, or hook once and install it into any project for whichever assistant you are using.
The CLI (`ait`) handles rendering, translation, validation, and wiring automatically.

## Artifact types

| Type | What it is | Assistants |
|------|-----------|------------|
| **Agent** | A specialised subagent with its own system prompt and tool set | Claude Code, Copilot, Cursor |
| **Skill** | A slash-command workflow invocable by the user or the model | Claude Code, Copilot, Cursor, Windsurf |
| **Hook** | A shell script that intercepts tool calls | Claude Code only |

Windsurf exposes Skill only: Cascade is its sole agent and there is no subagent definition
format to translate an agent into. Hooks are Claude Code only — Copilot and Windsurf have no
tool-call event system, and Cursor's hooks live in `.cursor/hooks.json` rather than a
settings file, which is not modelled yet.

## Supported assistants

| Assistant | Agents | Skills | Hooks | Instructions file |
|-----------|--------|--------|-------|-------------------|
| Claude Code | `~/.claude/agents/` or `.claude/agents/` | `~/.claude/skills/{name}/` or `.claude/skills/{name}/` | `~/.claude/hooks/` or `.claude/hooks/` + `settings.json` wiring | `CLAUDE.md` |
| Copilot | `~/.copilot/agents/` or `.github/agents/` | `~/.copilot/skills/{name}/` or `.github/skills/{name}/` | unsupported | `AGENTS.md` |
| Cursor | `~/.cursor/agents/` or `.cursor/agents/` | `~/.cursor/skills/{name}/` or `.cursor/skills/{name}/` | unsupported | `AGENTS.md` |
| Windsurf | unsupported | `~/.codeium/windsurf/skills/{name}/` or `.windsurf/skills/{name}/` | unsupported | `AGENTS.md` |

Override the global base with `AIT_COPILOT_USER_DIR`, `AIT_CURSOR_USER_DIR` or
`AIT_WINDSURF_USER_DIR` when your setup puts them somewhere else.

## How items stay DRY

Each artifact file is written once, in Claude Code terms. Three mechanisms render it
correctly for every target assistant at install time.

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
  copilot:
    model: gpt-5
    tools: [read, search]
    target: vscode
    argument-hint: "[pr-number]"
    user-invocable: false
    disable-model-invocation: true
  cursor:
    model: composer-2
    readonly: true
    is_background: true
```

The entire `assistants:` block is stripped before the file is written to disk, so no
assistant ever sees another's configuration.

Keys that mean the same thing everywhere — `argument-hint`, `user-invocable`,
`disable-model-invocation`, `paths` — carry over from the top level automatically. Restate
one under `assistants:` only to give a specific assistant a different value.

### 2. `{placeholder}` tokens

Tokens in the body are substituted per assistant before writing:

| Token | Claude Code | Others |
|-------|-------------|--------|
| `{instructionsFile}` | `CLAUDE.md` | `AGENTS.md` |

No other token is touched, so `{path}`, `{repo}` and friends can be used freely in prose.

### 3. Tool name translation

Tool names in the `tools:` list are written once in Claude Code terms. The installer
translates them for each target assistant:

| Claude Code | Copilot |
|-------------|---------|
| `Bash`, `shell`, `powershell` | `execute` |
| `Read`, `NotebookRead` | `read` |
| `Edit`, `MultiEdit`, `Write`, `NotebookEdit` | `edit` |
| `Grep`, `Glob` | `search` |
| `Task` | `agent` |
| `WebFetch`, `WebSearch` | `web` |
| `TodoWrite` | `todo` |

Duplicates collapse automatically — `[Bash, Read, Write, Edit]` becomes
`[execute, read, edit]`.

A tool list is never widened. Copilot reads an absent `tools` key as "every tool enabled",
so a name with no alias is never quietly dropped — the install is refused until the item
either drops the name or declares an explicit `assistants.copilot.tools` list.

Cursor is different again: its subagents have no `tools` key and inherit everything from the
parent. `readonly: true` is the only restriction available, and it is derived from the tool
list — set when there is no write tool **and** no indirect route to one. `Bash`, `Task` and
any unrecognised tool count as an indirect route.

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
not itself valid YAML. `tools` accepts inline sequences, bare comma-separated strings, and
block sequences.

## Validation

Nothing is written unless the item validates for the target assistant. The wizard shows a
failing item with its reason and refuses to select it; `_wizard_install` checks again as a
final gate; `ait validate` runs every check across the whole repo for CI.

See [adding an agent](how-to/adding-an-agent.md),
[adding a skill](how-to/adding-a-skill.md) and [adding a hook](how-to/adding-a-hook.md) for
what each type must satisfy.

## Auto-discovery

There is no registry for items. Drop a file in the right directory and it appears in the
`ait` wizard immediately:

```
agents/{name}.md              # agent
skills/{name}/SKILL.md        # skill (flat .md also works)
hooks/{name}.sh               # hook
```

Assistants *are* registered, in one place: `AIT_ASSISTANTS` in `scripts/lib/registry.sh`.
