# Artificial Intelligence Tools

A single source of agents, skills, and hooks for AI coding assistants — write each tool once,
install it into any project for whichever assistant you happen to be using.

Supported today: **Claude Code**, **GitHub Copilot**, **Cursor** and **Windsurf**.

---

## Install the `ait` CLI

One-time bootstrap. Clone the repo, then run the installer:

```bash
git clone git@github.com:albuletec/ai-tools.git ~/Workspace/ai-tools
cd ~/Workspace/ai-tools
./install.sh
```

This symlinks `ait` into `~/.local/bin`, so the CLI always runs the latest version of
your clone — no reinstall needed after `git pull`.

If `~/.local/bin` isn't on your `PATH`, the installer tells you the exact line to add.

Equivalent via make:

```bash
make install
```

### Requirements

| Tool | Required? | Without it |
|------|-----------|------------|
| `bash` | yes | — (3.2 is fine; macOS system bash works) |
| `git` | yes | — |
| `jq` | optional | Hooks are copied but not wired into `settings.json` |
| `ruby` | tests only | `tests/run.sh` can't assert on YAML or JSON |

Install `jq` with `brew install jq`.

---

## Usage

`cd` into the project you want to install into, then:

```bash
ait
```

That opens a four-step wizard:

```
1. Assistant  →  2. Scope  →  3. Type  →  4. Items  →  Confirm
```

| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate |
| `SPACE` | Toggle an item (step 4 only) |
| `ENTER` | Select / confirm |
| `ESC` | Back one step — exits from step 1 |

**Scope** decides where things land:

- **Global** — applies everywhere, installed to your home directory
- **Local** — applies to the current project only

Nothing is written until you confirm at the summary screen.

> **Careful — precedence differs by type in Claude Code.** For **agents**, a project
> definition beats a global one. For **skills**, it's the reverse: a personal
> (`~/.claude`) skill overrides a project one of the same name. So a global skill install
> will shadow a project's own version, not defer to it.

### Commands

```bash
ait              # interactive installer (same as `ait install`)
ait list         # show every item and which assistants support it
ait validate     # lint every item; non-zero exit if any would install badly
ait update       # pull the latest ai-tools without installing anything
ait help         # usage
```

`install`, `list` and `update` pull the repo first (fast-forward only), so you're never
installing a stale copy. If the pull fails — offline, or you have local changes — it warns
and continues.

Make targets: `make list`, `make validate`, `make test`, `make update`. There's deliberately
no `make` equivalent of `ait install` — make always runs from this repo, so a local install
would land here instead of in your project. Always run `ait` from the project you're
installing into.

### Nothing installs unless it validates

Every item is checked against the target assistant before a single byte is written. An item
that would install badly is listed in the wizard with its reason and can't be selected, and
`_wizard_install` refuses it again as a final gate. The checks are:

- the file opens and closes a `---` frontmatter block, and the body isn't empty
- `description` is present
- the item name is lowercase letters, numbers and hyphens, and any frontmatter `name`
  agrees with the file or directory name
- every entry in `tools` has an alias for the target assistant
- hooks: the event is real, the timeout is a whole number, and a matcher only appears on an
  event that accepts one

Run `ait validate` to check the whole repo at once — that's what CI runs.

---

## What's in here

| Type | What it is | Assistants |
|------|-----------|------------|
| **Agent** | A specialised subagent with its own instructions and tool set | Claude Code, Copilot, Cursor |
| **Skill** | A slash-command workflow | Claude Code, Copilot, Cursor, Windsurf |
| **Hook** | A shell script that intercepts tool calls | Claude Code only |

Windsurf has no subagent format, so Agent is hidden when you pick it. Hooks are Claude Code
only: Copilot and Windsurf have no tool-call event system, and Cursor's hooks are configured
through `.cursor/hooks.json` rather than a settings file, which isn't modelled yet.

Run `ait list` to see the current inventory.

### Where things get installed

| Type | Assistant | Global | Local |
|------|-----------|--------|-------|
| Agent | Claude Code | `~/.claude/agents/{name}.md` | `.claude/agents/{name}.md` |
| Agent | Copilot | `~/.copilot/agents/{name}.agent.md` | `.github/agents/{name}.agent.md` |
| Agent | Cursor | `~/.cursor/agents/{name}.md` | `.cursor/agents/{name}.md` |
| Skill | Claude Code | `~/.claude/skills/{name}/SKILL.md` | `.claude/skills/{name}/SKILL.md` |
| Skill | Copilot | `~/.copilot/skills/{name}/SKILL.md` | `.github/skills/{name}/SKILL.md` |
| Skill | Cursor | `~/.cursor/skills/{name}/SKILL.md` | `.cursor/skills/{name}/SKILL.md` |
| Skill | Windsurf | `~/.codeium/windsurf/skills/{name}/SKILL.md` | `.windsurf/skills/{name}/SKILL.md` |
| Hook | Claude Code | `~/.claude/hooks/{name}.sh` | `.claude/hooks/{name}.sh` |

Supporting files in a skill directory are copied across too, subdirectories included — all
four assistants read `scripts/`, `references/` and `assets/` relative to `SKILL.md`.

Copilot skills are installed as `SKILL.md`, **not** as `.prompt.md` prompt files. Copilot
supports Anthropic-style skills natively, and prompt files are now the legacy path — the VS
Code docs state that agents on the Agent Host don't use them, and VS Code ships a *Migrate
Prompts* command that converts prompt files into skills.

Global Copilot scope targets `~/.copilot/`, the harness-agnostic tree the Agent Host reads
and what `chat.agentSkillsLocations` enables by default. The older in-extension harness
instead reads the VS Code profile's `prompts/` folder
(`~/Library/Application Support/Code/User/prompts/` on macOS,
`~/.config/Code/User/prompts/` on Linux) — set `AIT_COPILOT_USER_DIR` to target that if
you're on the local harness. `AIT_CURSOR_USER_DIR` and `AIT_WINDSURF_USER_DIR` do the same
job for the other two.

> **You may not need a second assistant at all.** Copilot, Cursor and Windsurf all read
> `.claude/agents/`, `.claude/skills/` and `~/.claude/skills/` as a compatibility layer, so
> a Claude Code install is already largely visible to them. Installing natively gets you
> their own filenames, their own frontmatter, and correctly-named tools instead.

Hooks are also wired into the matching `settings.json` automatically, under the right event
and matcher. Re-running an install won't duplicate an existing entry, and a hook that can't
be wired says so instead of reporting success.

---

## Writing a tool

Each tool is **one file**, written once, rendered per assistant at install time. You never
maintain a Copilot copy and a Claude copy of the same instructions.

```markdown
---
name: code-planner
description: Plans implementations before any code is written.
model: claude-opus-5
tools: [Bash, Read, Write]
assistants:
  copilot:
  cursor:
---

You are a senior software architect.

Read `{instructionsFile}` at the repo root before proposing changes.
```

Two mechanisms keep it DRY:

**1. The `assistants:` block — opt in per assistant.**
Claude Code needs no entry; it's always supported. Any other assistant requires a key, so
support is explicit rather than accidental. The whole block is stripped on install, so no
assistant ever sees another's configuration.

Per-item overrides go underneath:

```yaml
assistants:
  copilot:
    model: gpt-5                   # agents only
    tools: [read, search]          # agents only — overrides automatic translation
    target: vscode                 # agents only — vscode | github-copilot
    mcp-servers: [jira]            # agents only
    argument-hint: "[pr-number]"   # skills only
    context: fork                  # skills only
    user-invocable: false
    disable-model-invocation: true
  cursor:
    model: composer-2              # agents only
    readonly: true                 # agents only — overrides the derived value
    is_background: true            # agents only
    paths: "src/**"                # skills only
```

`argument-hint`, `user-invocable`, `disable-model-invocation` and `paths` mean the same
thing in Claude Code as they do elsewhere, so a **top-level** value carries over
automatically. Only restate one under `assistants:` when a specific assistant needs a
different value.

**2. `{placeholder}` tokens — substituted per assistant.**

| Placeholder | Claude Code | Others |
|-------------|-------------|--------|
| `{instructionsFile}` | `CLAUDE.md` | `AGENTS.md` |

Any other `{token}` is left alone, so you can write `{path}` or `{repo}` in prose freely.

### Frontmatter is read as YAML, not as lines

`description` may be a folded or literal block scalar, a quoted string containing a colon,
or a plain value continued across indented lines — all three collapse to one logical string
before an assistant re-emits it, and the result is re-quoted so it stays valid YAML.
`tools` accepts all three forms Claude Code allows:

```yaml
tools: [Bash, Read]      # inline
tools: Bash, Read        # comma-separated
tools:                   # block sequence
  - Bash
  - Read
```

### Tool translation

Write tool names once in Claude Code terms:

| You write | Copilot gets |
|-----------|--------------|
| `Bash` | `execute` |
| `Read` | `read` |
| `Write`, `Edit` | `edit` |
| `Grep`, `Glob` | `search` |
| `Task` | `agent` |
| `WebFetch`, `WebSearch` | `web` |
| `TodoWrite` | `todo` |

Duplicates collapse — `[Bash, Read, Write, Edit]` becomes `[execute, read, edit]`.

**A tool list is never widened.** Copilot treats an absent `tools` key as "every tool
enabled", so a name with no alias — an MCP tool, say — is not silently dropped: the install
is refused until you either remove it or state an explicit `assistants.copilot.tools` list.

Cursor subagents have no `tools` key at all; they inherit everything from the parent. The
only lever is `readonly`, which is set automatically when a tool list grants no write access
**and** no indirect route to one. `Bash`, `Task` and any unrecognised tool count as an
indirect route, so an agent holding those is not marked read-only — it could write through
a redirection or a delegate.

`model` is Claude Code-only and omitted elsewhere, since available models vary by
subscription. Set `assistants.{name}.model` if a specific item needs one.

### Adding a new file

Drop it in the right directory and it appears in the menu — there's no registry to update.

```
common/agents/{name}.md              # agent
common/skills/{name}/SKILL.md        # skill (supporting files and subdirectories are copied too)
claude-code/hooks/{name}.sh          # hook
```

Hooks declare their wiring in a comment header, read by the installer:

```bash
#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Write|Edit|Bash
## ait:timeout  10
```

`ait:event` accepts any Claude Code hook event, and the name is checked against the real
list — a typo is refused rather than written into `settings.json` as a bucket that never
fires. Most events accept a `matcher`; the ones that don't have it omitted, since including
one there would be invalid. See
[adding a hook](docs/how-to/adding-a-hook.md#events) for the full table. `ait:timeout` is in
seconds and must be a whole number. Exit 2 from a hook blocks the action.

The generated `command` differs by scope — `${CLAUDE_PROJECT_DIR}/.claude/hooks/{name}.sh`
for a project install (a bare relative path would resolve against the working directory),
and `$HOME/.claude/hooks/{name}.sh` for a global one, as there's no documented placeholder
for the home directory.

---

## Layout

```
ait.sh                    CLI entry point — symlinked onto your PATH as `ait`
install.sh                one-time bootstrap — symlinks ait onto your PATH
Makefile                  convenience targets
common/agents/            agent definitions, shared across assistants
common/skills/            skill definitions, shared across assistants
claude-code/hooks/        hook scripts — Claude Code only
claude-code/settings.json reference Claude Code settings — not installed by ait
copilot/                  Copilot-specific artifacts — none yet
cursor/                   Cursor-specific artifacts — none yet
windsurf/                 Windsurf-specific artifacts — none yet
tests/run.sh              test suite
scripts/
  body.sh                 frontmatter parsing, placeholders, tool translation
  registry.sh             the list of assistants and the dispatch to their scripts
  collect.sh              item discovery and assistant filtering
  validate.sh             the fail-closed checks, and the hook event tables
  install.sh              shared install helpers — not the bootstrap above
  menu.sh                 arrow-key menu engine
  wizard.sh               the four-step flow
  assistants/
    claude-code.sh        renders and installs for Claude Code
    copilot.sh            renders and installs for Copilot
    cursor.sh             renders and installs for Cursor
    windsurf.sh           renders and installs for Windsurf
```

Every item definition lives under `common/` and opts into an assistant through its own
`assistants:` frontmatter block; a directory named after an assistant holds only that
assistant's non-item artifacts.

`claude-code/settings.json` is a reference copy of a working Claude Code configuration —
permissions plus the hook wiring these hooks expect. `ait` does not install it; copy the
parts you want into your own `~/.claude/settings.json`.

### Adding an assistant

Two changes, because the registry drives everything else:

1. Write `scripts/assistants/{name}.sh` with `{name}_types()`, `{name}_install()` and
   optionally `{name}_label()`.
2. Add the slug to `AIT_ASSISTANTS` in `scripts/registry.sh`.

Then opt items in with `assistants: {name}:`, and add a `{instructionsFile}` mapping in
`body.sh` if it doesn't read `AGENTS.md`. Full walkthrough:
[adding an assistant](docs/how-to/adding-an-assistant.md).

---

## Tests

```bash
make test              # everything
tests/run.sh unit      # syntax | unit | validate | golden | hooks
```

The suite installs every item for every assistant and scope into a temporary tree and
asserts on the result with a real YAML parser, so a rendering regression fails the build
rather than landing in someone's `~/.claude`. Every case in it maps to a defect that was
once real.

---

## Documentation

Longer-form docs live in [`docs/`](docs/README.md).

## References

The file formats and frontmatter schemas this tool generates are taken from:

**Claude Code**

- [Subagents](https://code.claude.com/docs/en/sub-agents) — frontmatter schema, locations,
  precedence, valid `model` values
- [Skills](https://code.claude.com/docs/en/skills) — `SKILL.md` schema, locations, and the
  precedence inversion versus agents
- [Hooks](https://code.claude.com/docs/en/hooks) — event list, which events accept a
  `matcher`, `${CLAUDE_PROJECT_DIR}`, exit codes
- [Settings](https://code.claude.com/docs/en/settings) — settings file locations and
  precedence

**Copilot**

- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
  — `.agent.md` schema, the canonical `tools` alias table, and the rule that an absent
  `tools` key enables every tool
- [Agent skills in VS Code](https://code.visualstudio.com/docs/agent-customization/agent-skills)
  — `SKILL.md` schema, skill locations, `chat.agentSkillsLocations`
- [Custom agents in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-agents)
  — workspace and user-level agent locations, Agent Host behaviour
- [VS Code 1.129 release notes](https://code.visualstudio.com/updates/v1_129)
  — prompt files are Local-harness only; *Migrate Prompts* converts them to skills

**Cursor**

- [Subagents](https://cursor.com/docs/subagents) — agent locations, frontmatter, the absence
  of a `tools` key, `readonly`
- [Skills](https://cursor.com/docs/skills) — `SKILL.md` schema, skill locations, supporting
  directories

**Windsurf**

- [Skills](https://docs.devin.ai/desktop/cascade/skills) — `SKILL.md` schema and skill
  locations
