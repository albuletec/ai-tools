# Adding an Agent

An agent is a specialised subagent with its own system prompt and tool set. It runs in a dedicated context and does not inherit the parent conversation.

## File location

```
common/agents/{name}.md
```

Drop the file here and it appears in the `ait` wizard immediately — no registry to update.

## Frontmatter

```markdown
---
name: my-agent
description: One-line description shown in the installer menu.
assistants:
  claude-code:
    model: claude-opus-5
    tools: [Bash, Read, Write]
  copilot:
    tools: [execute, read, edit]
---

Agent system prompt goes here.
```

### Required fields

| Field | Notes |
|-------|-------|
| `name` | Kebab-case identifier. Becomes the filename and the slash command name. |
| `description` | One-line description. Used in the wizard and in Copilot's `@` picker. |

### Optional fields

There is no optional top-level field for an agent. `model` and `tools` are per-assistant and
live under `assistants:` — see [Tool list](#tool-list) below and
[per-assistant `model` and `tools`](../overview.md#3-per-assistant-model-and-tools).

### Tool list

Each assistant declares its own tools, under its own key, in its own names:

```yaml
assistants:
  claude-code:
    tools: [Bash, Read, Write, Edit, Grep, Glob, WebFetch, WebSearch, Task]
  copilot:
    tools: [execute, read, edit, search, web, agent]
```

Nothing is mapped between the lists — each one is emitted verbatim into that assistant's
installed file, so keeping them in step is your job.

Write the list **inline on one line**: `tools: [Bash, Read]`. A block sequence under an
`assistants:` key reads as an empty value, which drops the restriction instead of applying
it.

### Copilot needs a list; Cursor has no list at all

- **Copilot reads an absent `tools` key as "every tool enabled."** An agent that opts into
  Copilot must declare `assistants.copilot.tools`, or `ait validate` refuses the install
  rather than hand the agent every tool.
- **Cursor subagents have no `tools` key at all** and inherit everything from the parent. The
  only lever is `readonly: true`, and it is declared as `assistants.cursor.readonly` — never
  inferred from a tool list.

None of the six shipped agents sets `readonly`, because all of them hold `Bash`. An agent
with shell access was never really read-only, on any assistant.

## The `assistants:` block

Claude Code is always supported. To make an agent available for other assistants, add a key under `assistants:`:

```yaml
assistants:
  copilot:
```

Per-assistant overrides go under that key:

```yaml
assistants:
  claude-code:
    model: claude-opus-5
    tools: [Bash, Read]
  copilot:
    model: gpt-5
    tools: [execute, read, search]
    target: vscode                 # vscode | github-copilot
    user-invocable: false
    disable-model-invocation: true
```

`claude-code`, `copilot` and `cursor` may each carry `model` and `tools`. For Claude Code the
key is configuration only — the assistant is supported whether or not the block is there.

| Override key | Type | Notes |
|--------------|------|-------|
| `model` | string | Assistant-specific model ID |
| `tools` | list | The tool list for this assistant, in that assistant's own names |
| `target` | string | Copilot target: `vscode` or `github-copilot` |
| `user-invocable` | bool | Whether the agent can be invoked directly by the user |
| `disable-model-invocation` | bool | Prevent the model from invoking this agent |
| `mcp-servers` | list | Copilot only — extra MCP servers for the agent |
| `readonly` | bool | Cursor only — declared, not derived |
| `is_background` | bool | Cursor only — run the subagent in the background |

For agents every optional key must be declared inside the assistant block — there is no
top-level carry-over. Skills behave differently: `user-invocable` and `disable-model-invocation`
carry over from a top-level value in a skill; they do not in an agent.

The entire `assistants:` block is stripped before the file is written to disk.

## Placeholder tokens

Use `{instructionsFile}` in the body to reference the repo-level instructions file:

```markdown
Read `{instructionsFile}` at the repo root before starting.
```

| Assistant | Resolves to |
|----------|-------------|
| Claude Code | `CLAUDE.md` |
| Others | `AGENTS.md` |

## Install paths

| Scope | Claude Code | Copilot | Cursor |
|-------|-------------|---------|--------|
| Global | `~/.claude/agents/{name}.md` | `~/.copilot/agents/{name}.agent.md` | `~/.cursor/agents/{name}.md` |
| Local | `.claude/agents/{name}.md` | `.github/agents/{name}.agent.md` | `.cursor/agents/{name}.md` |

Windsurf has no subagent format, so agents are not installed for it at all — see
[the Windsurf doc](../assistants/windsurf.md) for why.

## Full example

```markdown
---
name: code-planner
description: Plans implementations before any code is written.
assistants:
  claude-code:
    model: claude-opus-5
    tools: [Bash, Read, Write]
  copilot:
    tools: [execute, read, edit]
---

You are a senior software architect. Your sole output is a structured
implementation plan saved to `docs/plans/`.

Read `{instructionsFile}` at the repo root before proposing anything.
```
