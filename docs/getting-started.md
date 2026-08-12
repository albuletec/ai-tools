# Getting Started

## Requirements

| Tool | Required? | Without it |
|------|-----------|------------|
| `bash` | yes | — (3.2 is fine; macOS system bash works) |
| `git` | yes | — |
| `jq` | optional | Hooks are copied but not wired into `settings.json` |

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
1. Provider  →  2. Scope  →  3. Type  →  4. Items  →  Confirm
```

| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate |
| `SPACE` | Toggle an item (step 4 only) |
| `ENTER` | Select / confirm |
| `ESC` | Back one step — exits from step 1 |

### Step 1 — Provider

Choose the AI assistant you are installing for:

- **Claude Code** — installs under `.claude/` (local) or `~/.claude/` (global)
- **Copilot** — installs under `.github/` (local) or `~/.copilot/` (global)

### Step 2 — Scope

- **Global** — applies to every project on your machine; installed to your home directory
- **Local** — applies only to the current project; installed to the project's own directory

> **Precedence note for Claude Code.** For **agents**, a project-level definition beats a global one. For **skills**, it is reversed — a global (`~/.claude`) skill overrides a project skill of the same name. Installing a skill globally will shadow a project's own version.

### Step 3 — Type

Choose Agent, Skill, or Hook. Hook is hidden when Copilot is selected.

### Step 4 — Items

Multi-select with `SPACE`. Press `ENTER` to confirm. Nothing is written until the confirmation screen.

## CLI commands

```bash
ait              # interactive installer (same as `ait install`)
ait list         # show every item and which providers support it
ait update       # pull the latest ai-tools without installing anything
ait help         # usage
```

Every `ait` command performs a `git pull --ff-only` first, so you are never installing a stale copy. If the pull fails (offline or local changes present), it warns and continues.

## Make targets

```bash
make list        # same as `ait list`
make update      # same as `ait update`
```

There is no `make install` equivalent for installing items — `make` always runs from the repo directory, so a local install would land in the repo itself. Always run `ait` from the target project.
