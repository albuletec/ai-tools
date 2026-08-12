# Adding an Agent

An agent is a specialised subagent with its own system prompt and tool set. It runs in a dedicated context and does not inherit the parent conversation.

## File location

```
agents/<name>.md
```

Drop the file here and it appears in the `ait` wizard immediately — no registry to update.

## Frontmatter

```markdown
---
name: my-agent
description: One-line description shown in the installer menu.
model: claude-opus-5
tools: [Bash, Read, Write]
providers:
  copilot:
---

Agent system prompt goes here.
```

### Required fields

| Field | Notes |
|-------|-------|
| `name` | Kebab-case identifier. Becomes the filename and the slash command name. |
| `description` | One-line description. Used in the wizard and in Copilot's `@` picker. |

### Optional fields

| Field | Notes |
|-------|-------|
| `model` | Claude model ID. Claude Code uses this; other providers ignore it unless overridden in the `providers:` block. |
| `tools` | List of tools the agent may use, in Claude Code terms. Translated automatically per provider. See [Tool translation](overview.md#3-tool-name-translation). |

### Tool list

Write tools in Claude Code terms once:

```yaml
tools: [Bash, Read, Write, Edit, Grep, Glob, WebFetch, WebSearch, Task]
```

The installer deduplicates and translates per provider. `Write` and `Edit` both become `edit` for Copilot, so the list collapses safely.

A read-only agent stays read-only across providers — omitting `Write`/`Edit` from the list means the agent never gains write access, regardless of provider.

## The `providers:` block

Claude Code is always supported. To make an agent available for other providers, add a key under `providers:`:

```yaml
providers:
  copilot:
```

Per-provider overrides go under that key:

```yaml
providers:
  copilot:
    model: gpt-5
    tools: [read, search]          # overrides automatic translation
    target: vscode                 # vscode | github-copilot
    user-invocable: false
    disable-model-invocation: true
```

| Override key | Type | Notes |
|--------------|------|-------|
| `model` | string | Provider-specific model ID |
| `tools` | list | Raw tool list for this provider — skips automatic translation |
| `target` | string | Copilot target: `vscode` or `github-copilot` |
| `user-invocable` | bool | Whether the agent can be invoked directly by the user |
| `disable-model-invocation` | bool | Prevent the model from invoking this agent |

The entire `providers:` block is stripped before the file is written to disk.

## Placeholder tokens

Use `{instructionsFile}` in the body to reference the repo-level instructions file:

```markdown
Read `{instructionsFile}` at the repo root before starting.
```

| Provider | Resolves to |
|----------|-------------|
| Claude Code | `CLAUDE.md` |
| Others | `AGENTS.md` |

## Install paths

| Scope | Claude Code | Copilot |
|-------|-------------|---------|
| Global | `~/.claude/agents/<name>.md` | `~/.copilot/agents/<name>.agent.md` |
| Local | `.claude/agents/<name>.md` | `.github/agents/<name>.agent.md` |

## Full example

```markdown
---
name: code-planner
description: Plans implementations before any code is written.
model: claude-opus-5
tools: [Bash, Read, Write]
providers:
  copilot:
---

You are a senior software architect. Your sole output is a structured
implementation plan saved to `docs/plans/`.

Read `{instructionsFile}` at the repo root before proposing anything.
```
