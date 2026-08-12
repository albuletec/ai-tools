# Claude Code Assistant

Claude Code is the primary assistant. All artifact types are supported, and every item is Claude Code-compatible by default — no `assistants:` entry is required.

## Supported artifact types

| Type | Supported |
|------|-----------|
| Agent | yes |
| Skill | yes |
| Rule | yes |
| Hook | yes — Claude Code only |

## Install paths

| Type | Global | Local |
|------|--------|-------|
| Agent | `~/.claude/agents/{name}.md` | `.claude/agents/{name}.md` |
| Skill | `~/.claude/skills/{name}/SKILL.md` | `.claude/skills/{name}/SKILL.md` |
| Rule | `~/.claude/rules/{name}.md` | `.claude/rules/{name}.md` |
| Hook | `~/.claude/hooks/{name}.sh` | `.claude/hooks/{name}.sh` |

Hooks are also wired into the matching `settings.json`:

| Scope | Settings file |
|-------|---------------|
| Global | `~/.claude/settings.json` |
| Local | `.claude/settings.json` |

## Agent frontmatter

This is the one assistant where the source file and the installed file differ in shape.

In the **source** file, `model` and `tools` are Claude Code's own configuration, so they live
under `assistants.claude-code`:

```yaml
---
name: my-agent
description: What this agent does.
assistants:
  claude-code:
    model: claude-opus-5
    tools: [Bash, Read, Write]
---
```

In the **installed** file they are top-level keys, where Claude Code expects them, and the
`assistants:` block is gone:

```yaml
---
name: my-agent
description: What this agent does.
model: claude-opus-5
tools: [Bash, Read, Write]
---
```

Every other top-level key is passed through as-is, so any key Claude Code supports can be
written at the top level and will arrive untouched.

### `model`

Set as `assistants.claude-code.model`. Any valid Claude model ID. Current options:

| Model | ID |
|-------|----|
| Claude Opus 5 | `claude-opus-5` |
| Claude Sonnet 5 | `claude-sonnet-5` |
| Claude Fable 5 | `claude-fable-5` |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` |

### `tools`

Set as `assistants.claude-code.tools`, inline on one line. Claude Code tool names used
directly:

`Bash`, `Read`, `Write`, `Edit`, `MultiEdit`, `Grep`, `Glob`, `Task`, `WebFetch`, `WebSearch`, `TodoWrite`, `NotebookRead`, `NotebookEdit`

### Agent precedence

A project-level agent (`.claude/agents/`) overrides a global one (`~/.claude/agents/`) of the same name.

## Skill frontmatter

```yaml
---
name: my-skill
description: What this skill does and when to invoke it.
---
```

No `model` or `tools` — skills load as instructions within the invoking context.

### Skill precedence

**Inverted** compared to agents — a global skill (`~/.claude/skills/`) overrides a project-level one (`.claude/skills/`) of the same name. Installing a skill globally shadows the project's own version.

## Rule frontmatter

A rule installs as three keys at most:

```yaml
---
name: logging-conventions
description: "How this service logs, and which dimensions every line must carry."
paths: ["src/**/*.ts"]
---
```

| Key | Source | Notes |
|-----|--------|-------|
| `name` | the file name | Emitted for consistency with every other renderer; Claude Code ignores frontmatter keys it does not use |
| `description` | top-level `description` | Read as a YAML value and re-quoted, so a folded scalar or an embedded colon survives |
| `paths` | `assistants.claude-code.paths`, else a top-level `paths` | **Omitted entirely when neither is set — the rule then always loads** |

`paths` is the only activation control. There is no requirement to declare one: a rule with no
`paths` is valid and loads for every request, which is the common case.

Unlike agents and skills, a rule is **not** passed through with its top-level keys intact. It
is rendered explicitly, key by key, so that a `trigger:` or `globs:` written for Windsurf or
Cursor cannot leak into the Claude Code file.

## Project context file

`ait init` writes the starter `CLAUDE.md` from `claude-code/init/CLAUDE.md`:

| Scope | Target |
|-------|--------|
| Global | `~/.claude/CLAUDE.md` |
| Local | `CLAUDE.md` at the project root |

Claude Code is the only assistant with a documented home-directory context file, so it is the
only one `ait init` offers a global target for. The template is copied verbatim — every
`{curly}` token in the result is a prompt for you to fill in — and an existing file is left
byte-identical unless you answer `y` to the overwrite prompt.

## Hook wiring

The installer reads wiring metadata from comment headers in the hook script:

```bash
## ait:event    PreToolUse
## ait:matcher  Write|Edit|Bash
## ait:timeout  10
```

These are written into `settings.json` under `.hooks.<event>[]`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/my-hook.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Re-running an install never duplicates an existing entry. If the entry cannot be written — no `jq`, a non-numeric timeout, or a `settings.json` that is not valid JSON — the installer reports the reason and returns non-zero rather than printing a success line.

### Hook command paths

| Scope | `command` value |
|-------|----------------|
| Global | `$HOME/.claude/hooks/{name}.sh` |
| Local | `${CLAUDE_PROJECT_DIR}/.claude/hooks/{name}.sh` |

`${CLAUDE_PROJECT_DIR}` is the documented Claude Code placeholder for the project root. A bare relative path is not used because it resolves against the working directory at run time.

### Hook events

There are 31 events, and most of them accept a `matcher` — not just the four tool events.
The authoritative lists live in `scripts/validate.sh` as `_AIT_HOOK_EVENTS` and
`_AIT_MATCHER_EVENTS`; the full table is in
[adding a hook](../how-to/adding-a-hook.md#events).

Accept a matcher: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`,
`PermissionDenied`, `SessionStart`, `Setup`, `SessionEnd`, `Notification`, `SubagentStart`,
`SubagentStop`, `PreCompact`, `PostCompact`, `ConfigChange`, `DirectoryAdded`, `FileChanged`,
`InstructionsLoaded`, `UserPromptExpansion`, `Elicitation`, `ElicitationResult`.

Do not: `UserPromptSubmit`, `PostToolBatch`, `Stop`, `StopFailure`, `TeammateIdle`,
`TaskCreated`, `TaskCompleted`, `MessageDisplay`, `CwdChanged`, `WorktreeCreate`,
`WorktreeRemove`.

An event name that is not on the list at all is refused by `ait validate`, and so is a
matcher set on an event that does not accept one.

Matchers are pipe-separated tool name patterns (`Write|Edit`).

### Hook exit codes

| Code | Effect |
|------|--------|
| `0` | Allow |
| `2` | Block (`PreToolUse` only) |
| Other | Error; action proceeds |

## Reference settings.json

`claude-code/settings.json` is a reference copy of a working Claude Code
configuration: a read-only permission allowlist plus the wiring these five hooks expect.
`ait` does not install it — copy the parts you want into your own
`~/.claude/settings.json`.

## Placeholder substitution

`{instructionsFile}` → `CLAUDE.md`

## Current items

### Agents

| Name | Description | Tools |
|------|-------------|-------|
| `code-planner` | Plans implementations, writes plan to `docs/plans/` | Bash, Read, Write |
| `code-reviewer` | Reviews implementations against plan and standards | Bash, Read |
| `code-tester` | Writes unit, integration, and end-to-end tests | Bash, Read, Edit, Write |
| `code-writer` | Implements features from a plan | Bash, Read, Edit, Write |
| `observability-reviewer` | Validates logging/metrics/tracing against Gaming standards | Bash, Read |
| `security-reviewer` | Reviews changed files for security defects | Bash, Read |

### Skills

| Name | Description |
|------|-------------|
| `dependency-review` | Evaluates a third-party package and produces a decision record |
| `grill-me` | Relentless design interview to stress-test a plan |
| `incident-runbook` | Structures an incident investigation or post-mortem |
| `pr-description` | Writes a PR description from the current branch's diff |
| `standards-check` | Fast compliance check against Gaming standards repos |
| `update-workspace` | Pulls the three Gaming standards repos |

### Rules

None yet. `common/rules/` ships with its format `README.md` only, so no `rule` rows appear in
`ait list` until one is added.

### Hooks

| Name | Event | Matcher | Blocks? | Description |
|------|-------|---------|---------|-------------|
| `destructive-op-guard` | `PreToolUse` | `Bash` | yes | Blocks irreversible shell operations |
| `lint-on-save` | `PostToolUse` | `Write\|Edit` | no | Runs `lint:changed` after file writes |
| `no-verify-guard` | `PreToolUse` | `Bash` | yes | Blocks `git --no-verify` |
| `secret-scrubber` | `PreToolUse` | `Write\|Edit\|Bash` | yes | Blocks tool inputs that look like credentials |
| `terminology-guard` | `PostToolUse` | `Write\|Edit` | no | Warns about banned terminology after file writes |
