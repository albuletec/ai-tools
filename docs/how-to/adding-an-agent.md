# Adding an Agent

An agent is a specialised subagent with its own system prompt and tool set. It runs in a dedicated context and does not inherit the parent conversation.

## File location

```
agents/{name}.md
```

Drop the file here and it appears in the `ait` wizard immediately — no registry to update.

## Frontmatter

```markdown
---
name: my-agent
description: One-line description shown in the installer menu.
model: claude-opus-5
tools: [Bash, Read, Write]
assistants:
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
| `model` | Claude model ID. Claude Code uses this; other assistants ignore it unless overridden in the `assistants:` block. |
| `tools` | List of tools the agent may use, in Claude Code terms. Translated automatically per assistant. See [Tool translation](overview.md#3-tool-name-translation). |

### Tool list

Write tools in Claude Code terms once:

```yaml
tools: [Bash, Read, Write, Edit, Grep, Glob, WebFetch, WebSearch, Task]
```

Write the list in any of the three forms Claude Code accepts — inline (`[Bash, Read]`),
comma-separated (`Bash, Read`) or a block sequence — they are all parsed the same way.

The installer deduplicates and translates per assistant. `Write` and `Edit` both become `edit`
for Copilot, so the list collapses safely.

### A tool list is never widened

Omitting `Write` and `Edit` means the agent gains no write alias on any assistant. Two things
make that a real guarantee rather than a hope:

- **Copilot reads an absent `tools` key as "every tool enabled."** So a name with no alias —
  an MCP tool, `Skill`, `AskUserQuestion` — is never quietly dropped. If dropping it would
  leave the key absent, `ait validate` refuses the install and asks you to either remove the
  name or declare an explicit `assistants.copilot.tools` list.
- **Cursor subagents have no `tools` key at all** and inherit everything from the parent. The
  only lever is `readonly`, which is derived from the list.

Be careful about what "read-only" means, though. `readonly: true` is set only when the list
grants no write access **and** no indirect route to one — `Bash` can write through a
redirection, and `Task` can delegate to something that writes, so both disqualify it. None of
the six shipped agents qualifies, because all of them hold `Bash`. An agent with shell access
was never really read-only, on any assistant.

## The `assistants:` block

Claude Code is always supported. To make an agent available for other assistants, add a key under `assistants:`:

```yaml
assistants:
  copilot:
```

Per-assistant overrides go under that key:

```yaml
assistants:
  copilot:
    model: gpt-5
    tools: [read, search]          # overrides automatic translation
    target: vscode                 # vscode | github-copilot
    user-invocable: false
    disable-model-invocation: true
```

| Override key | Type | Notes |
|--------------|------|-------|
| `model` | string | Assistant-specific model ID |
| `tools` | list | Raw tool list for this assistant — skips automatic translation |
| `target` | string | Copilot target: `vscode` or `github-copilot` |
| `user-invocable` | bool | Whether the agent can be invoked directly by the user |
| `disable-model-invocation` | bool | Prevent the model from invoking this agent |
| `mcp-servers` | list | Copilot only — extra MCP servers for the agent |
| `readonly` | bool | Cursor only — overrides the value derived from `tools` |
| `is_background` | bool | Cursor only — run the subagent in the background |

`user-invocable` and `disable-model-invocation` mean the same thing everywhere, so a
top-level value carries over automatically; restate one here only to differ.

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
model: claude-opus-5
tools: [Bash, Read, Write]
assistants:
  copilot:
---

You are a senior software architect. Your sole output is a structured
implementation plan saved to `docs/plans/`.

Read `{instructionsFile}` at the repo root before proposing anything.
```
