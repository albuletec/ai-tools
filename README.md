# Artificial Intelligence Tools

A single source of agents, skills, rules, and hooks for AI coding assistants — write each tool
once, install it into any project for whichever assistant you happen to be using.

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
ait init         # create the per-project context file for an assistant
ait list         # show every item and which assistants support it
ait validate     # lint every item; non-zero exit if any would install badly
ait update       # pull the latest ai-tools without installing anything
ait help         # usage
```

`install`, `init`, `list` and `update` pull the repo first (fast-forward only), so you're
never installing a stale copy. If the pull fails — offline, or you have local changes — it
warns and continues.

Make targets: `make list`, `make validate`, `make test`, `make update`. There's deliberately
no `make` equivalent of `ait install` or `ait init` — make always runs from this repo, so a
local install or a new context file would land here instead of in your project. Always run
`ait` from the project you're installing into. Running `ait init` from inside the `ai-tools`
clone itself will write to this repo's own root; the three files it would land on there are
gitignored so the tree stays clean, but it isn't what you want.

### Initialise a project

`ait init` writes the per-project context file each assistant reads at the repo root. That
file is one per project rather than a list of composable items, so it isn't an item and
doesn't go through the four-step installer.

```
1. Assistant (multi-select)  →  2. Scope  →  3. Confirm
```

| Assistant | Global | Local |
|-----------|--------|-------|
| Claude Code | `~/.claude/CLAUDE.md` | `CLAUDE.md` |
| Copilot | — | `.github/copilot-instructions.md` |
| Cursor | — | `AGENTS.md` |
| Windsurf | — | `AGENTS.md` |

Cursor and Windsurf share one `AGENTS.md`, so selecting both writes it once and the
confirmation screen names both against that single file. Claude Code is the only assistant
with a documented home-directory context file, so it's the only one with a global target;
select another at global scope and `ait init` tells you it has nothing to write there.

Templates are copied verbatim — every `{curly}` token in one is a prompt for you to fill in,
not a placeholder `ait` resolves. An existing file is never overwritten without an explicit
`y`, and `ait init` only ever writes whole files: it never edits or appends to one you
already have.

`.cursorrules` and `.windsurfrules` are legacy and are not written; `ait init` says so and
writes `AGENTS.md` instead.

### Nothing installs unless it validates

Every item is checked against the target assistant before a single byte is written. An item
that would install badly is listed in the wizard with its reason and can't be selected, and
`_wizard_install` refuses it again as a final gate. The checks are:

- the file opens and closes a `---` frontmatter block, and the body isn't empty
- `description` is present
- the item name is lowercase letters, numbers and hyphens, and any frontmatter `name`
  agrees with the file or directory name
- agents: one that opts into Copilot declares `assistants.copilot.tools`
- rules: a Windsurf rule declares a `trigger` and it's one of the five real ones, with a
  description when the trigger needs one and `globs` when it's `glob`; a Cursor rule doesn't
  set both `alwaysApply: true` and `globs`, since the first wins and the second would be
  ignored silently; and an activation list written as a block sequence is refused, because it
  reads as empty and would install the rule with a wider scope than declared
- hooks: the event is real, the timeout is a whole number, and a matcher only appears on an
  event that accepts one

Run `ait validate` to check the whole repo at once — that's what CI runs.

---

## What's in here

| Type | What it is | Assistants |
|------|-----------|------------|
| **Agent** | A specialised subagent with its own instructions and tool set | Claude Code, Copilot, Cursor |
| **Skill** | A slash-command workflow | Claude Code, Copilot, Cursor, Windsurf |
| **Rule** | A markdown file loaded into the assistant's context, always or on a condition | Claude Code, Cursor, Windsurf |
| **Hook** | A shell script that intercepts tool calls | Claude Code only |

Windsurf has no subagent format, so Agent is hidden when you pick it. Hooks are Claude Code
only: Copilot and Windsurf have no tool-call event system, and Cursor's hooks are configured
through `.cursor/hooks.json` rather than a settings file, which isn't modelled yet. Rules
exclude Copilot: its nearest equivalent, `.github/instructions/{name}.instructions.md`,
selects files with `applyTo:` and has its own precedence, so it's a different artifact rather
than the same one under another name.

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
| Rule | Claude Code | `~/.claude/rules/{name}.md` | `.claude/rules/{name}.md` |
| Rule | Cursor | `~/.cursor/rules/{name}.mdc` | `.cursor/rules/{name}.mdc` |
| Rule | Windsurf | `~/.codeium/windsurf/rules/{name}.md` | `.windsurf/rules/{name}.md` |
| Hook | Claude Code | `~/.claude/hooks/{name}.sh` | `.claude/hooks/{name}.sh` |

A rule source file is always `.md`. The `.mdc` rename is Cursor-only and happens at install
time, in `scripts/assistants/cursor.sh` and nowhere else.

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
assistants:
  claude-code:
    model: claude-opus-5
    tools: [Bash, Read, Write]
  copilot:
    tools: [execute, read, edit]
  cursor:
---

You are a senior software architect.

Read `{instructionsFile}` at the repo root before proposing changes.
```

Two mechanisms keep it DRY:

**1. The `assistants:` block — opt in per assistant.**
Claude Code needs no entry to be supported, so a `claude-code:` key is configuration rather
than opt-in — it is where an agent's Claude Code `model` and `tools` live. Any other assistant requires a key, so
support is explicit rather than accidental. The whole block is stripped on install, so no
assistant ever sees another's configuration.

Per-item overrides go underneath:

```yaml
assistants:
  claude-code:
    model: claude-opus-5           # agents only
    tools: [Bash, Read]            # agents only — Claude Code's own tool names
  copilot:
    model: gpt-5                   # agents only
    tools: [execute, read]         # agents only — the list for this assistant, in its own names
    target: vscode                 # agents only — vscode | github-copilot
    mcp-servers: [jira]            # agents only
    argument-hint: "[pr-number]"   # skills only
    context: fork                  # skills only
    user-invocable: false
    disable-model-invocation: true
  cursor:
    model: composer-2              # agents only
    readonly: true                 # agents only — declared explicitly
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

### Each assistant declares its own tools

There is no shared tool list, because no two assistants name their tools the same way. Each
one declares its own, under its own key:

```yaml
assistants:
  claude-code:
    tools: [Bash, Read, Write]
  copilot:
    tools: [execute, read, edit]
```

Nothing is mapped between them — each list is emitted verbatim into that assistant's file,
so keeping them in step is yours to do. Write the list **inline on one line**: a block
sequence under an `assistants:` key reads as an empty value and drops the restriction instead
of applying it.

**An agent that opts into Copilot must declare `assistants.copilot.tools`.** Copilot treats
an absent `tools` key as "every tool enabled", so `ait validate` refuses the install rather
than let the omission hand the agent everything.

Cursor subagents have no `tools` key at all; they inherit everything from the parent. The
only lever is `readonly: true`, declared as `assistants.cursor.readonly`. None of the shipped
agents sets it — all of them hold a shell, and an agent that can redirect into a file was
never read-only anyway.

`model` is Claude Code-only and omitted elsewhere, since available models vary by
subscription. Declare it as `assistants.claude-code.model`, or `assistants.{name}.model` if
another assistant needs a specific one.

### A rule declares its activation per assistant

The three assistants that read rule directories don't share a vocabulary for *when* a rule
loads, so activation lives under `assistants:` rather than at the top level:

```markdown
---
name: typescript-conventions
description: How TypeScript is written in this repo.
paths: ["src/**/*.ts"]
assistants:
  cursor:
    globs: ["src/**/*.ts"]
  windsurf:
    trigger: glob
    globs: ["src/**/*.ts"]
---

Prefer named exports. Read `{instructionsFile}` for anything not covered here.
```

Claude Code takes `paths` (absent means always loaded, and a top-level `paths` carries over).
Cursor picks one of four modes from which keys are present — `alwaysApply: true`,
`globs`, `description`, or none of them for manual-only. Windsurf needs a `trigger`:
`always_on`, `manual`, `model_decision`, `glob` or `agent`.

A Cursor `description` is the one shared key that deliberately does **not** carry over from
the top level, because on Cursor the mere presence of a description is what selects Agent
Requested activation — inheriting it would change every rule's mode silently.

### Adding a new file

Drop it in the right directory and it appears in the menu — there's no registry to update.

```
common/agents/{name}.md              # agent
common/skills/{name}/SKILL.md        # skill (supporting files and subdirectories are copied too)
common/rules/{name}.md               # rule
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
common/rules/             rule definitions, shared across assistants
claude-code/hooks/        hook scripts — Claude Code only
claude-code/init/         CLAUDE.md starter template, written by `ait init`
claude-code/settings.json reference Claude Code settings — not installed by ait
copilot/init/             .github/copilot-instructions.md starter template
cursor/init/              AGENTS.md starter template
windsurf/init/            AGENTS.md starter template — byte-identical to Cursor's
tests/run.sh              test suite
scripts/
  body.sh                 frontmatter parsing and placeholders
  registry.sh             the list of assistants and the dispatch to their scripts
  collect.sh              item discovery and assistant filtering
  validate.sh             the fail-closed checks, and the hook event tables
  install.sh              shared install helpers — not the bootstrap above
  menu.sh                 arrow-key menu engine
  wizard.sh               the four-step install flow and the three-step init flow
  assistants/
    claude-code.sh        renders and installs for Claude Code
    copilot.sh            renders and installs for Copilot
    cursor.sh             renders and installs for Cursor
    windsurf.sh           renders and installs for Windsurf
```

Every item definition lives under `common/` and opts into an assistant through its own
`assistants:` frontmatter block; a directory named after an assistant holds only that
assistant's non-item artifacts — its hooks, its reference settings, and its `init/` template.
A context file is not an item, so its template belongs to one assistant and lives there.

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
tests/run.sh unit      # syntax | install | unit | validate | rules | init | golden | hooks
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
- [Memory](https://code.claude.com/docs/en/memory) — `CLAUDE.md` locations and the
  `.claude/rules/` directory
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

- [Rules](https://cursor.com/docs/rules) — `.mdc` frontmatter, the four activation modes,
  `AGENTS.md`

**Windsurf**

- [Skills](https://docs.devin.ai/desktop/cascade/skills) — `SKILL.md` schema and skill
  locations
- [Memories and rules](https://docs.devin.ai/desktop/cascade/memories) — rule locations,
  `trigger` values, `AGENTS.md` handling
