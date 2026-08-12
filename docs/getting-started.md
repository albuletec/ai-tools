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

This opens a four-step wizard:

```
1. Assistant  →  2. Scope  →  3. Type  →  4. Items  →  Confirm
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

Choose Agent, Skill, or Hook. Only the types the chosen assistant actually supports are
offered, and only when the repo has at least one item of that type for it — Hook is hidden for
everything except Claude Code, and Agent is hidden for Windsurf.

### Step 4 — Items

Multi-select with `SPACE`. Press `ENTER` to confirm. Nothing is written until the confirmation
screen.

An item that would install badly for the chosen assistant is listed with a `✗` and its
reason, and cannot be selected. Run `ait validate` to see every such reason across the whole
repo at once.

## CLI commands

```bash
ait              # interactive installer (same as `ait install`)
ait list         # show every item and which assistants support it
ait validate     # lint every item; non-zero exit if any would install badly
ait update       # pull the latest ai-tools without installing anything
ait help         # usage
```

Every `ait` command performs a `git pull --ff-only` first, so you are never installing a stale copy. If the pull fails (offline or local changes present), it warns and continues.

## Make targets

```bash
make list        # same as `ait list`
make validate    # same as `ait validate`
make test        # run the test suite
make update      # same as `ait update`
```

There is no `make install` equivalent for installing items — `make` always runs from the repo directory, so a local install would land in the repo itself. Always run `ait` from the target project.
