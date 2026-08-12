# Overview

`ai-tools` is a single source of truth for AI coding-assistant tooling. You write each agent, skill, or hook once and install it into any project for whichever provider you are using. The CLI (`ait`) handles rendering, translation, and wiring automatically.

## Artifact types

| Type | What it is | Providers |
|------|-----------|-----------|
| **Agent** | A specialised subagent with its own system prompt and tool set | Claude Code, Copilot |
| **Skill** | A slash-command workflow invocable by the user or the model | Claude Code, Copilot |
| **Hook** | A shell script that intercepts tool calls | Claude Code only |

Hooks are Claude Code-only because no other provider has a tool-call event system.

## Supported providers

| Provider | Agents | Skills | Hooks |
|----------|--------|--------|-------|
| Claude Code | `~/.claude/agents/` or `.claude/agents/` | `~/.claude/skills/<name>/` or `.claude/skills/<name>/` | `~/.claude/hooks/` or `.claude/hooks/` + `settings.json` wiring |
| Copilot | `~/.copilot/agents/` or `.github/agents/` | `~/.copilot/skills/<name>/` or `.github/skills/<name>/` | unsupported |

## How items stay DRY

Each artifact file is written once, in Claude Code terms. Two mechanisms render it correctly for every target provider at install time.

### 1. The `providers:` block

Claude Code is always supported — no entry needed. Every other provider must be explicitly opted in:

```yaml
providers:
  copilot:
```

Presence alone means "supported with all defaults." Per-item overrides sit under the provider key:

```yaml
providers:
  copilot:
    model: gpt-5
    tools: [read, search]
    target: vscode
    argument-hint: "[pr-number]"
    user-invocable: false
    disable-model-invocation: true
```

The entire `providers:` block is stripped before the file is written to disk, so no provider ever sees another's configuration.

### 2. `{placeholder}` tokens

Tokens in the body are substituted per provider before writing:

| Token | Claude Code | Others |
|-------|-------------|--------|
| `{instructionsFile}` | `CLAUDE.md` | `AGENTS.md` |

### 3. Tool name translation

Tool names in the `tools:` list are written once in Claude Code terms. The installer translates them automatically for each target provider:

| Claude Code | Copilot |
|-------------|---------|
| `Bash`, `shell`, `powershell` | `execute` |
| `Read`, `NotebookRead` | `read` |
| `Edit`, `MultiEdit`, `Write`, `NotebookEdit` | `edit` |
| `Grep`, `Glob` | `search` |
| `Task` | `agent` |
| `WebFetch`, `WebSearch` | `web` |
| `TodoWrite` | `todo` |

Duplicates collapse automatically — `[Bash, Read, Write, Edit]` becomes `[execute, read, edit]`.

## Auto-discovery

There is no registry. Drop a file in the right directory and it appears in the `ait` wizard immediately:

```
agents/<name>.md              # agent
skills/<name>/SKILL.md        # skill (flat .md also works)
hooks/<name>.sh               # hook
```
