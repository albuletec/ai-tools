# Copilot Provider

GitHub Copilot is the second supported provider. Agents and skills are supported; hooks are not (Copilot has no tool-call interception system).

## Do you need this provider?

VS Code reads `.claude/agents/`, `.claude/skills/`, `~/.claude/skills/`, and `CLAUDE.md` directly by default, so a Claude Code install is already largely visible to Copilot. Installing for Copilot gets you native filenames (`.agent.md`, `SKILL.md` in `.github/`) and correctly-named tools in the frontmatter rather than relying on VS Code's compatibility layer.

## Supported artifact types

| Type | Supported |
|------|-----------|
| Agent | yes |
| Skill | yes |
| Hook | no |

## Install paths

| Type | Global | Local |
|------|--------|-------|
| Agent | `~/.copilot/agents/<name>.agent.md` | `.github/agents/<name>.agent.md` |
| Skill | `~/.copilot/skills/<name>/SKILL.md` | `.github/skills/<name>/SKILL.md` |

Global scope targets `~/.copilot/`, the harness-agnostic tree the Agent Host reads. If you are on the older in-extension harness that reads the VS Code profile's `prompts/` folder, set `AIT_COPILOT_USER_DIR` to override the global base:

```bash
AIT_COPILOT_USER_DIR="$HOME/Library/Application Support/Code/User" ait
# Linux: AIT_COPILOT_USER_DIR="$HOME/.config/Code/User" ait
```

## Opting an item into Copilot

Add a `copilot:` key under `providers:` in the item's frontmatter:

```yaml
providers:
  copilot:
```

Items without this key do not appear in the wizard when Copilot is selected.

## Agent frontmatter

The installer produces a `.agent.md` file with Copilot-native frontmatter:

```yaml
---
name: my-agent
description: What this agent does.
tools: [execute, read, edit]
---
```

`name` and `description` come from the source file. `tools` is translated automatically from the Claude Code names. `model` is omitted unless explicitly set in the `providers.copilot` block — Copilot inherits the user's default model otherwise.

### Per-provider agent overrides

```yaml
providers:
  copilot:
    model: gpt-5
    tools: [read, search]
    target: vscode
    user-invocable: false
    disable-model-invocation: true
```

| Key | Type | Notes |
|-----|------|-------|
| `model` | string | Copilot model ID. Omitted from frontmatter when absent. |
| `tools` | list | Raw tool list — bypasses automatic translation entirely |
| `target` | string | `vscode` or `github-copilot`. Omitted when absent. |
| `user-invocable` | bool | Whether the user can invoke this agent directly |
| `disable-model-invocation` | bool | Prevent the model from invoking this agent |

## Skill frontmatter

The installer produces a `SKILL.md` with Copilot-native frontmatter:

```yaml
---
name: my-skill
description: What this skill does.
---
```

Skills are installed as `SKILL.md`, **not** as `.prompt.md` prompt files. Copilot supports the Anthropic-style `SKILL.md` format natively. The VS Code docs state that agents on the Agent Host do not use prompt files, and VS Code ships a *Migrate Prompts* command that converts prompt files to skills.

### Per-provider skill overrides

```yaml
providers:
  copilot:
    argument-hint: "[pr-number]"
    user-invocable: false
    disable-model-invocation: true
    context: selection
```

| Key | Type | Notes |
|-----|------|-------|
| `argument-hint` | string | Hint shown in the slash-command picker |
| `user-invocable` | bool | Whether the user can invoke this skill directly |
| `disable-model-invocation` | bool | Prevent the model from invoking this skill |
| `context` | string | Copilot context type passed to the skill |

## Tool translation

Tools are written once in Claude Code terms and translated to Copilot's canonical aliases:

| Claude Code | Copilot |
|-------------|---------|
| `Bash`, `shell`, `powershell` | `execute` |
| `Read`, `NotebookRead` | `read` |
| `Edit`, `MultiEdit`, `Write`, `NotebookEdit` | `edit` |
| `Grep`, `Glob` | `search` |
| `Task` | `agent` |
| `WebFetch`, `WebSearch` | `web` |
| `TodoWrite` | `todo` |

Duplicates collapse — `[Bash, Read, Write, Edit]` becomes `[execute, read, edit]`. A read-only agent (`tools: [Bash, Read]`) translates to `[execute, read]` and never gains write access.

These pairings follow the documented compatibility aliases from the [Copilot custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration).

## Placeholder substitution

`{instructionsFile}` → `AGENTS.md`

## Current items

All items in the repository opt into Copilot via `providers: copilot:`.

### Agents

| Name | Translated tools |
|------|-----------------|
| `code-planner` | `execute, read, edit` |
| `code-reviewer` | `execute, read` |
| `code-tester` | `execute, read, edit` |
| `code-writer` | `execute, read, edit` |
| `observability-reviewer` | `execute, read` |
| `security-reviewer` | `execute, read` |

### Skills

| Name | Description |
|------|-------------|
| `dependency-review` | Evaluates a third-party package and produces a decision record |
| `grill-me` | Relentless design interview to stress-test a plan |
| `incident-runbook` | Structures an incident investigation or post-mortem |
| `pr-description` | Writes a PR description from the current branch's diff |
| `standards-check` | Fast compliance check against Gaming standards repos |
| `update-workspace` | Pulls the three Gaming standards repos |

### Hooks

Hooks are not supported by Copilot.

## References

- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration) — `.agent.md` schema and canonical tools aliases
- [Agent skills in VS Code](https://code.visualstudio.com/docs/agent-customization/agent-skills) — `SKILL.md` schema, skill locations, `chat.agentSkillsLocations`
- [Custom agents in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-agents) — workspace and user-level agent locations, Agent Host behaviour
- [VS Code 1.129 release notes](https://code.visualstudio.com/updates/v1_129) — prompt files are local-harness only; *Migrate Prompts* converts them to skills
