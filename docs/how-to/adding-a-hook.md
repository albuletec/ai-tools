# Adding a Hook

Hooks are shell scripts that intercept Claude Code tool calls. They are **Claude Code only** — no other provider has a tool-call event system.

## File location

```
hooks/<name>.sh
```

Drop the file here and it appears in the `ait` wizard immediately. The installer copies the script, sets it executable, and wires it into `settings.json` automatically (requires `jq`).

## Metadata header

The installer reads wiring instructions from comment lines at the top of the script:

```bash
#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Write|Edit|Bash
## ait:timeout  10
```

| Key | Values | Notes |
|-----|--------|-------|
| `ait:event` | See table below | Which Claude Code event fires the hook. Defaults to `PreToolUse`. |
| `ait:matcher` | Pipe-separated tool names | Pattern matched against the tool name. Only valid on tool events. Ignored (and omitted from `settings.json`) on non-tool events. Defaults to `Bash`. |
| `ait:timeout` | Integer (seconds) | How long Claude Code waits before giving up on the hook. Defaults to `10`. |

## Events

| Event | Is a tool event? | Description |
|-------|-----------------|-------------|
| `PreToolUse` | yes | Fires before a tool runs. Exit 2 to block. |
| `PostToolUse` | yes | Fires after a tool succeeds. |
| `PostToolUseFailure` | yes | Fires after a tool fails. |
| `PermissionRequest` | yes | Fires when Claude Code asks for permission. |
| `SessionStart` | no | Fires when a session begins. |
| `SessionEnd` | no | Fires when a session ends. |
| `UserPromptSubmit` | no | Fires when the user submits a prompt. |
| `Stop` | no | Fires when Claude Code stops normally. |
| `StopFailure` | no | Fires when Claude Code stops due to an error. |
| `FileChanged` | no | Fires when a file changes on disk. |
| `ConfigChange` | no | Fires when the configuration changes. |

Only tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`) accept a `matcher`. For all other events the matcher is omitted from `settings.json` — including one there would be invalid.

## Exit codes

| Exit code | Effect |
|-----------|--------|
| `0` | Allow / continue |
| `2` | Block the action (only meaningful on `PreToolUse`) |
| Other | Treated as an error; action proceeds |

Print a message to stderr before exiting 2 to explain what was blocked and why.

## STDIN

Claude Code passes tool context as JSON on stdin. Parse it with `jq`:

```bash
raw=$(cat)
cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // empty')
file=$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty')
```

Common fields by tool:

| Tool | Useful fields |
|------|---------------|
| `Bash` | `.tool_input.command` |
| `Write`, `Edit` | `.tool_input.file_path`, `.tool_input.content`, `.tool_input.new_string` |

## Install paths

| Scope | Script path | Settings file |
|-------|-------------|---------------|
| Global | `~/.claude/hooks/<name>.sh` | `~/.claude/settings.json` |
| Local | `.claude/hooks/<name>.sh` | `.claude/settings.json` |

The generated `command` in `settings.json` uses `$HOME/.claude/hooks/<name>.sh` for global installs and `${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh` for local installs. A bare relative path is not used because it would resolve against the working directory at run time.

Re-running an install never duplicates an existing entry — `patch_settings_json` checks for the exact command string before adding.

## Full example

```bash
#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Bash
## ait:timeout  5
set -u

# Block --no-verify on git commands.

if ! command -v jq >/dev/null 2>&1; then exit 0; fi

raw=$(cat)
cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$cmd" ]] && exit 0

if printf '%s' "$cmd" | grep -qE '^git\b' && printf '%s' "$cmd" | grep -qE '\-\-no-verify'; then
  printf 'hook: blocked git --no-verify\n' >&2
  exit 2
fi
```
