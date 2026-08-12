# Copilot Assistant

GitHub Copilot is the second supported assistant. Agents and skills are supported; hooks are not (Copilot has no tool-call interception system).

## Do you need this assistant?

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
| Agent | `~/.copilot/agents/{name}.agent.md` | `.github/agents/{name}.agent.md` |
| Skill | `~/.copilot/skills/{name}/SKILL.md` | `.github/skills/{name}/SKILL.md` |

Global scope targets `~/.copilot/`, the harness-agnostic tree the Agent Host reads. If you are on the older in-extension harness that reads the VS Code profile's `prompts/` folder, set `AIT_COPILOT_USER_DIR` to override the global base:

```bash
AIT_COPILOT_USER_DIR="$HOME/Library/Application Support/Code/User" ait
# Linux: AIT_COPILOT_USER_DIR="$HOME/.config/Code/User" ait
```

## Opting an item into Copilot

Add a `copilot:` key under `assistants:` in the item's frontmatter:

```yaml
assistants:
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

`name` comes from the file or directory name, and `description` is read as a YAML value and re-quoted, so a folded block scalar or a description containing a colon survives intact. `tools` is translated automatically from the Claude Code names. `model` is omitted unless explicitly set in the `assistants.copilot` block — Copilot inherits the user's default model otherwise.

### Per-assistant agent overrides

```yaml
assistants:
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

### Per-assistant skill overrides

```yaml
assistants:
  copilot:
    argument-hint: "[pr-number]"
    user-invocable: false
    disable-model-invocation: true
    context: fork
```

| Key | Type | Notes |
|-----|------|-------|
| `argument-hint` | string | Hint shown in the slash-command picker |
| `user-invocable` | bool | Whether the user can invoke this skill directly |
| `disable-model-invocation` | bool | Prevent the model from invoking this skill |
| `context` | string | How the skill is loaded. Assistant-specific, so it is only ever taken from the `assistants.copilot` block, never from a top-level `context`. |

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

Duplicates collapse — `[Bash, Read, Write, Edit]` becomes `[execute, read, edit]`. A source
list is never widened: `tools: [Bash, Read]` becomes `[execute, read]` and gains no write
alias.

**An absent `tools` key means every tool is enabled**, per GitHub's own reference. So a name
with no alias — an MCP tool, `Skill`, `AskUserQuestion` — is never silently dropped, because
dropping the last recognised name would leave the key absent and hand the agent everything.
`ait validate` refuses the install and tells you to either drop the name or declare an
explicit `assistants.copilot.tools` list.

These pairings follow the documented compatibility aliases from the [Copilot custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration).

## Placeholder substitution

`{instructionsFile}` → `AGENTS.md`

## Current items

All items in the repository opt into Copilot via `assistants: copilot:`.

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
