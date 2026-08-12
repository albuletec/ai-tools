# Adding a Hook

Hooks are shell scripts that intercept Claude Code events. They are **Claude Code only** —
Copilot and Windsurf have no tool-call event system, and Cursor configures its hooks through
`.cursor/hooks.json` rather than a settings file, which `ait` does not model yet.

## File location

```
hooks/{name}.sh
```

Drop the file here and it appears in the `ait` wizard immediately. The installer copies the
script, sets it executable, and wires it into `settings.json` automatically (requires `jq`).

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
| `ait:event` | Any event in the table below | Which Claude Code event fires the hook. Defaults to `PreToolUse`. An unrecognised name is refused, not written. |
| `ait:matcher` | Pipe-separated tool names | Pattern matched against the tool name. Only valid on events that accept one; setting it on an event that doesn't is refused. Defaults to `Bash`. |
| `ait:timeout` | Whole number of seconds | How long Claude Code waits before giving up on the hook. Defaults to `10`. Anything non-numeric is refused. |

All three are checked by `ait validate` before an install writes anything.

## Events

Taken from the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks). Most
events accept a `matcher`; for the rest it is omitted from `settings.json`, because including
one there would be invalid.

| Event | Accepts matcher? |
|-------|------------------|
| `PreToolUse` | yes |
| `PostToolUse` | yes |
| `PostToolUseFailure` | yes |
| `PermissionRequest` | yes |
| `PermissionDenied` | yes |
| `SessionStart` | yes |
| `Setup` | yes |
| `SessionEnd` | yes |
| `Notification` | yes |
| `SubagentStart` | yes |
| `SubagentStop` | yes |
| `PreCompact` | yes |
| `PostCompact` | yes |
| `ConfigChange` | yes |
| `DirectoryAdded` | yes |
| `FileChanged` | yes |
| `InstructionsLoaded` | yes |
| `UserPromptExpansion` | yes |
| `Elicitation` | yes |
| `ElicitationResult` | yes |
| `UserPromptSubmit` | no |
| `PostToolBatch` | no |
| `Stop` | no |
| `StopFailure` | no |
| `TeammateIdle` | no |
| `TaskCreated` | no |
| `TaskCompleted` | no |
| `MessageDisplay` | no |
| `CwdChanged` | no |
| `WorktreeCreate` | no |
| `WorktreeRemove` | no |

Both lists live in `scripts/validate.sh` as `_AIT_HOOK_EVENTS` and
`_AIT_MATCHER_EVENTS`. If Claude Code adds an event, update them there — the docs and the
validator should never disagree.

## Exit codes

| Exit code | Effect |
|-----------|--------|
| `0` | Allow / continue |
| `2` | Block the action (most useful on `PreToolUse`) |
| Other | Treated as an error; the action proceeds |

Print a message to stderr before exiting 2 to explain what was blocked and why. The shipped
guards end that message by telling the user they can run the command themselves — a hook
should inform a decision, not quietly remove it.

## STDIN

Claude Code passes context as JSON on stdin. Parse it with `jq`:

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

On an `Edit`, only the replacement text is available — so a line number computed from it is
relative to that snippet, not to the file. Say so in the output rather than implying a file
position.

## Writing a guard that isn't noisy

A hook sees the raw command or the raw text, which means it cannot tell an instruction from
a mention of one. Two rules keep false positives down, both learned the hard way:

- **Match on the command, not the words.** `destructive-op-guard` only treats
  `DROP TABLE` as destructive when the segment actually invokes a database client. Matching
  the phrase alone made it impossible to grep a migrations directory or write about a schema
  change.
- **Strip quoted arguments before looking for flags.** `no-verify-guard` blanks out quoted
  strings first, so `git commit -m "document the --no-verify flag"` is allowed while
  `git commit --no-verify` is not.

## Portability

A hook installed globally runs in every repository, so it cannot assume a toolchain. Say
"reinstall them (for example yarn prepare, npm run prepare, or pre-commit install)" rather
than naming one package manager as though it were the only option.

## Bash version

macOS ships bash 3.2. Two traps that cost real debugging time here:

- A quoted heredoc inside `$( )` is scanned for quote balance by 3.2, so
  `rules=$(cat <<'EOF' ... EOF)` breaks once the body contains both kinds of quote. Emit
  from a function and read it with `< <(emit_rules)` instead.
- `read -t 0.1` silently becomes `-t 0`. Use whole-second timeouts.

`tests/run.sh syntax` runs `/bin/bash -n` over every shipped script to catch the first class
of problem, because a hook with a syntax error still exits 0 and looks like it ran.

## Install paths

| Scope | Script path | Settings file |
|-------|-------------|---------------|
| Global | `~/.claude/hooks/{name}.sh` | `~/.claude/settings.json` |
| Local | `.claude/hooks/{name}.sh` | `.claude/settings.json` |

The generated `command` uses `$HOME/.claude/hooks/{name}.sh` for global installs and
`${CLAUDE_PROJECT_DIR}/.claude/hooks/{name}.sh` for local ones. A bare relative path is not
used because it would resolve against the working directory at run time.

Re-running an install never duplicates an existing entry — `patch_settings_json` checks for
the exact command string first. If it cannot write, it reports the reason and returns
non-zero instead of printing a success line.

## Full example

```bash
#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Bash
## ait:timeout  5
set -u

# Block a git command that skips the repository's own hooks.

if ! command -v jq >/dev/null 2>&1; then exit 0; fi

raw=$(cat)
cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0

# Blank out quoted arguments so a commit message that mentions the flag is fine.
stripped=$(printf '%s' "$cmd" | sed -e 's/"[^"]*"/""/g' -e "s/'[^']*'/''/g")

if printf '%s' "$stripped" | grep -qE '(^|[[:space:]])git([[:space:]]|$)' \
   && printf '%s' "$stripped" | grep -qE '(^|[[:space:]])--no-verify([[:space:]=]|$)'; then
  printf 'hook: blocked - this skips the repository hooks\n' >&2
  printf 'hook: run the checks and fix what they report, or run it yourself in a terminal.\n' >&2
  exit 2
fi
```
