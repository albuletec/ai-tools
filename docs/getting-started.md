# Getting Started

## Requirements

| Tool | Required? | Without it |
|------|-----------|------------|
| `bash` | yes | — (3.2 is fine; macOS system bash works) |
| `git` | yes | — |
| `jq` | optional | Hooks are copied but not wired into `settings.json` |
| `ruby` | tests only | `tests/run.sh` cannot assert on YAML or JSON |

Install `jq` with `brew install jq`.

## Install the CLI

One-time bootstrap. Clone the repo, then run the installer:

```bash
git clone git@github.com:albuletec/ai-tools.git ~/Workspace/ai-tools
cd ~/Workspace/ai-tools
./install.sh
```

This symlinks `ait` into `~/.local/bin`. Because it is a symlink, `git pull` inside the repo is all you ever need — no reinstall.

If `~/.local/bin` is not on your `PATH`, the installer prints the exact line to add to your shell profile.

Equivalent via make:

```bash
make install
```

## Run the installer

`cd` into the project you want to install into, then run:

```bash
ait
```

This opens a four-step wizard that loops until you are done:

```
1. Assistant  →  2. Scope  →  3. Type  →  4. Items  →  Confirm  →  install
                              ▲                                      │
                              └──────────  install anything else?  ───┘
```

| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate |
| `SPACE` | Toggle an item (step 4 only) |
| `ENTER` | Select / confirm |
| `ESC` | Back one step — exits from step 1 |

### Step 1 — Assistant

Choose the AI coding assistant you are installing for:

- **Claude Code** — installs under `.claude/` (local) or `~/.claude/` (global)
- **Copilot** — installs under `.github/` (local) or `~/.copilot/` (global)
- **Cursor** — installs under `.cursor/` (local) or `~/.cursor/` (global)
- **Windsurf** — installs under `.windsurf/` (local) or `~/.codeium/windsurf/` (global)

The list comes from `AIT_ASSISTANTS` in `scripts/registry.sh`, so a newly registered
assistant appears here with no other change.

### Step 2 — Scope

- **Global** — applies to every project on your machine; installed to your home directory
- **Local** — applies only to the current project; installed to the project's own directory

> **Precedence note for Claude Code.** For **agents**, a project-level definition beats a global one. For **skills**, it is reversed — a global (`~/.claude`) skill overrides a project skill of the same name. Installing a skill globally will shadow a project's own version.

### Step 3 — Type

Choose Agent, Skill, Rule, or Hook. Only the types the chosen assistant actually supports are
offered, and only when the repo has at least one item of that type for it — Hook is hidden for
everything except Claude Code, Agent is hidden for Windsurf, and Rule is hidden for Copilot.

### Step 4 — Items

Multi-select with `SPACE`. Press `ENTER` to confirm. Nothing is written until the confirmation
screen.

An item that would install badly for the chosen assistant is listed with a `✗` and its
reason, and cannot be selected. Run `ait validate` to see every such reason across the whole
repo at once.

### Installing more than one type

Item types install one at a time, because each type has its own list to choose from. So after
writing the files the wizard asks:

```
  ✓  3 installed.

  Install anything else? [Y/n]:
```

Answering yes returns you to **Step 3** with the same assistant and scope, ready to pick a
different type — agents, then skills, then hooks, in one run. The question is asked on the
normal screen, next to the results, rather than in a menu that would hide them.

`ESC` at that Type step steps back to Scope, and again to Assistant, so a later round can
install somewhere else or for a different assistant entirely. When you finish, a single closing
line names every assistant you touched:

```
  ✓  7 installed across 3 rounds. Restart Claude Code, Cursor to pick up the changes.
```

## Initialise a project

`ait init` writes the per-project context file each assistant reads at the repo root. It is a
separate command because that file is one per project rather than a list of items, so it does
not fit the installer at all.

```bash
cd ~/Workspace/my-project
ait init
```

```
1. Assistant  →  2. Scope  →  3. Confirm
```

### Step 1 — Assistant

Multi-select with `SPACE`, confirm with `ENTER`. Cursor and Windsurf both read `AGENTS.md`, so
selecting both writes it once and the confirmation screen names both against that one file.

### Step 2 — Scope

Only Claude Code has a documented home-directory context file (`~/.claude/CLAUDE.md`). Pick
Global with anything else selected and `ait init` says it has nothing to write there.

| Assistant | Global | Local |
|-----------|--------|-------|
| Claude Code | `~/.claude/CLAUDE.md` | `CLAUDE.md` |
| Copilot | — | `.github/copilot-instructions.md` |
| Cursor | — | `AGENTS.md` |
| Windsurf | — | `AGENTS.md` |

### Step 3 — Confirm

Every target is listed with the assistants that share it. On confirming, a file that does not
exist yet is written straight away; an existing one prompts `overwrite {path}? [y/N]` and is
left byte-identical unless you answer `y`. `ait init` only ever writes whole files — it never
edits or appends to one you already have.

The templates are copied verbatim, so every `{curly}` token in the result is a prompt for you
to fill in rather than something `ait` resolved.

Run it from the target project. Running it inside the `ai-tools` clone itself will write to
this repo's own root.

## CLI commands

```bash
ait              # interactive installer (same as `ait install`)
ait init         # create the per-project context file for an assistant
ait list         # show every item and which assistants support it
ait validate     # lint every item; non-zero exit if any would install badly
ait update       # pull the latest ai-tools without installing anything
ait help         # usage
```

Every `ait` command performs a `git pull --ff-only` first, so you are never installing a stale copy or writing a stale template. If the pull fails (offline or local changes present), it warns and continues.

## Make targets

```bash
make list        # same as `ait list`
make validate    # same as `ait validate`
make test        # run the test suite
make update      # same as `ait update`
```

There is no `make install` or `make init` equivalent — `make` always runs from the repo directory, so a local install or a new context file would land in the repo itself. Always run `ait` from the target project.
