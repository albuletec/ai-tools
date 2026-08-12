# Artificial Intelligence Tools

A single source of agents, skills, and hooks for AI coding assistants — write each tool once,
install it into any project for whichever provider you happen to be using.

Supported today: **Claude Code** and **GitHub Copilot**.

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

Install `jq` with `brew install jq`.

---

## Usage

`cd` into the project you want to install into, then:

```bash
ait
```

That opens a four-step wizard:

```
1. Provider  →  2. Scope  →  3. Type  →  4. Items  →  Confirm
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

### Commands

```bash
ait              # interactive installer (same as `ait install`)
ait list         # show every item and which providers support it
ait update       # pull the latest ai-tools without installing anything
ait help         # usage
```

Every command pulls the repo first (fast-forward only), so you're never installing a stale
copy. If the pull fails — offline, or you have local changes — it warns and continues.

Make targets: `make list`, `make update`. There's deliberately no `make` equivalent of
`ait install` — make always runs from this repo, so a local install would land here instead
of in your project. Always run `ait` from the project you're installing into.

---

## What's in here

| Type | What it is | Providers |
|------|-----------|-----------|
| **Agent** | A specialised subagent with its own instructions and tool set | Claude Code, Copilot |
| **Skill** | A slash-command workflow | Claude Code, Copilot |
| **Hook** | A shell script that intercepts tool calls | Claude Code only |

Hooks are Claude Code-only because no other provider has a tool-call event system. They're
hidden from the menu when you pick another provider.

Run `ait list` to see the current inventory.

### Where things get installed

| Type | Provider | Global | Local |
|------|----------|--------|-------|
| Agent | Claude Code | `~/.claude/agents/<name>.md` | `.claude/agents/<name>.md` |
| Agent | Copilot | `<VS Code User>/agents/<name>.agent.md` | `.github/agents/<name>.agent.md` |
| Skill | Claude Code | `~/.claude/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` |
| Skill | Copilot | `<VS Code User>/prompts/<name>.prompt.md` | `.github/prompts/<name>.prompt.md` |
| Hook | Claude Code | `~/.claude/hooks/<name>.sh` | `.claude/hooks/<name>.sh` |

`<VS Code User>` is `~/Library/Application Support/Code/User` on macOS,
`~/.config/Code/User` on Linux. Override it with `AIT_COPILOT_USER_DIR` if your setup
differs — the VS Code docs give `~/.copilot/agents` for user-level agents, but
[microsoft/vscode#305642](https://github.com/microsoft/vscode/issues/305642) reports that
as a documentation error and the User profile folder as the one actually picked up. This is
unresolved upstream, so global Copilot installs are the least certain part of this tool.

Hooks are also wired into the matching `settings.json` automatically, under the right event
and matcher. Re-running an install won't duplicate an existing entry.

---

## Writing a tool

Each tool is **one file**, written once, rendered per provider at install time. You never
maintain a Copilot copy and a Claude copy of the same instructions.

```markdown
---
name: code-planner
description: Plans implementations before any code is written.
model: claude-opus-5
tools: [Bash, Read, Write]
providers:
  copilot:
---

You are a senior software architect.

Read `{instructionsFile}` at the repo root before proposing changes.
```

Two mechanisms keep it DRY:

**1. The `providers:` block — opt in per provider.**
Claude Code needs no entry; it's always supported. Any other provider requires a key, so
support is explicit rather than accidental. The whole block is stripped on install, so no
provider ever sees another's configuration.

Per-item overrides go underneath:

```yaml
providers:
  copilot:
    model: gpt-5
    agent: plan                    # skills only: ask | agent | plan | <custom agent>
    tools: [read, search]          # overrides the automatic translation
    disable-model-invocation: true
```

**2. `{placeholder}` tokens — substituted per provider.**

| Placeholder | Claude Code | Others |
|-------------|-------------|--------|
| `{instructionsFile}` | `CLAUDE.md` | `AGENTS.md` |

Tool names translate automatically, so write them once in Claude Code terms:

| You write | Copilot gets |
|-----------|--------------|
| `Bash` | `execute` |
| `Read` | `read` |
| `Write`, `Edit` | `edit` |
| `Grep`, `Glob` | `search` |
| `Task` | `agent` |
| `WebFetch`, `WebSearch` | `web` |
| `TodoWrite` | `todo` |

Duplicates collapse — `[Bash, Read, Write, Edit]` becomes `[execute, read, edit]`. Read-only
agents stay read-only, so a reviewer never gains write access by crossing providers.

`model` is Claude Code-only and omitted elsewhere, since available models vary by Copilot
subscription. Set `providers.<name>.model` if a specific item needs one.

### Adding a new file

Drop it in the right directory and it appears in the menu — there's no registry to update.

```
agents/<name>.md              # agent
skills/<name>/SKILL.md        # skill (supporting files in the same folder are copied too)
hooks/<name>.sh               # hook
```

Hooks declare their wiring in a comment header, read by the installer:

```bash
#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Write|Edit|Bash
## ait:timeout  10
```

---

## Layout

```
ait                       CLI entry point
install.sh                one-time bootstrap
Makefile                  convenience targets
agents/                   agent definitions
skills/                   skill definitions
hooks/                    hook scripts
scripts/lib/
  body.sh                 frontmatter parsing, placeholders, tool translation
  collect.sh              item discovery and provider filtering
  install.sh              settings.json patching
  menu.sh                 arrow-key menu engine
  wizard.sh               the four-step flow
  providers/
    claude-code.sh        renders and installs for Claude Code
    copilot.sh            renders and installs for Copilot
```

### Adding a provider

1. Write `scripts/lib/providers/<name>.sh` with `<name>_types()` and `<name>_install()`.
2. Source it in `ait` and add it to the provider menu in `scripts/lib/wizard.sh`.
3. Add a `{instructionsFile}` mapping in `body.sh` if it differs.
4. Add `providers: <name>:` to the items that should support it.

---

## References

The Copilot file formats and frontmatter schemas this tool generates are taken from:

- [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
  — `.agent.md` schema and the canonical `tools` alias table
- [Custom agents in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-agents)
  — workspace and user-level agent locations
- [Use prompt files in VS Code](https://code.visualstudio.com/docs/copilot/customization/prompt-files)
  — `.prompt.md` schema; note there is no `mode` property, it's `agent`
- [Custom instructions in VS Code](https://code.visualstudio.com/docs/copilot/customization/custom-instructions)
  — confirms `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` are all read

Worth knowing: VS Code reads `.claude/agents/` directly, and supports `CLAUDE.md` as well as
`AGENTS.md`. So a Claude Code install is partly portable to VS Code on its own — the Copilot
provider exists to produce native files with correctly-named tools rather than relying on
that compatibility layer.
