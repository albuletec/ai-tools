# Copilot Assistant

GitHub Copilot is the second supported assistant. Agents and skills are supported; hooks are not (Copilot has no tool-call interception system).

## Do you need this assistant?

VS Code reads `.claude/agents/`, `.claude/skills/`, `~/.claude/skills/`, and `CLAUDE.md` directly by default, so a Claude Code install is already largely visible to Copilot. Installing for Copilot gets you native filenames (`.agent.md`, `SKILL.md` in `.github/`) and correctly-named tools in the frontmatter rather than relying on VS Code's compatibility layer.

## Supported artifact types

| Type | Supported |
|------|-----------|
| Agent | yes |
| Skill | yes |
| Rule | no — see below |
| Hook | no |

Copilot's nearest equivalent to a rule is `.github/instructions/{name}.instructions.md`, which
selects files with `applyTo:` and has its own precedence relative to
`.github/copilot-instructions.md`. That is a different artifact with different semantics, not
the same one renamed, so `Rule` is absent from `copilot_types()`: the wizard never offers it,
and a direct `copilot_install {name} rule ...` returns non-zero and writes nothing.

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

`name` comes from the file or directory name, and `description` is read as a YAML value and re-quoted, so a folded block scalar or a description containing a colon survives intact. `tools` comes from `assistants.copilot.tools`, written in Copilot's own names, and is required for agents. `model` is omitted unless explicitly set in the `assistants.copilot` block — Copilot inherits the user's default model otherwise.

### Per-assistant agent overrides

```yaml
assistants:
  copilot:
    model: gpt-5
    tools: [execute, read, search]
    target: vscode
    user-invocable: false
    disable-model-invocation: true
```

| Key | Type | Notes |
|-----|------|-------|
| `model` | string | Copilot model ID. Omitted from frontmatter when absent. |
| `tools` | list | The agent's tool list in Copilot names, inline on one line. Required for agents. |
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

## Declaring Copilot tools

An agent's Copilot tool list is written by hand under `assistants.copilot.tools`, in Copilot's
own tool names, inline on one line:

```yaml
assistants:
  copilot:
    tools: [execute, read]
```

The value is emitted verbatim. Nothing is derived from another assistant's list, so if the
agent's Claude Code list changes, change this one too.

**An absent `tools` key means every tool is enabled**, per GitHub's own reference. That makes
the omission an escalation rather than a narrowing, so `ait validate` refuses to install an
agent that opts into Copilot without declaring a list.

### Authoring hint: equivalent names

Not a mapping the installer performs — just a starting point when writing a Copilot list next
to a Claude Code one. The Copilot column holds the names GitHub documents as compatibility
aliases for the Claude Code names beside them.

| Claude Code name | Copilot equivalent |
|-------------|---------|
| `Bash`, `shell`, `powershell` | `execute` |
| `Read`, `NotebookRead` | `read` |
| `Edit`, `MultiEdit`, `Write`, `NotebookEdit` | `edit` |
| `Grep`, `Glob` | `search` |
| `Task` | `agent` |
| `WebFetch`, `WebSearch` | `web` |
| `TodoWrite` | `todo` |

Several Claude Code names share one Copilot name, so a shorter Copilot list is normal —
`[Bash, Read, Write, Edit]` is covered by `[execute, read, edit]`.

These pairings are taken from the [Copilot custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration).

## Project context file

`ait init` writes the starter instructions file from
`copilot/init/copilot-instructions.md`:

| Scope | Target |
|-------|--------|
| Global | — no target offered |
| Local | `.github/copilot-instructions.md` |

`.github/` is created if it does not exist. There is no global target: the file is a repository
file by definition, and no home-directory equivalent for Copilot is as well documented as
`~/.claude/CLAUDE.md`, so `ait init` reports Copilot as skipped at global scope rather than
guessing at a path nothing reads.

The template is copied verbatim, so every `{curly}` token in the result is a prompt for you to
fill in. An existing file is left byte-identical unless you answer `y` to the overwrite prompt.

## Placeholder substitution

`{instructionsFile}` → `AGENTS.md`

## Current items

All items in the repository opt into Copilot via `assistants: copilot:`.

### Agents

| Name | Declared tools |
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

### Rules and hooks

Neither is supported by Copilot.

## References

- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration) — `.agent.md` schema and canonical tools aliases
- [Agent skills in VS Code](https://code.visualstudio.com/docs/agent-customization/agent-skills) — `SKILL.md` schema, skill locations, `chat.agentSkillsLocations`
- [Custom agents in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-agents) — workspace and user-level agent locations, Agent Host behaviour
- [VS Code 1.129 release notes](https://code.visualstudio.com/updates/v1_129) — prompt files are local-harness only; *Migrate Prompts* converts them to skills
