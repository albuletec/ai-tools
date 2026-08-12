---
name: update-workspace
description: Refresh the three local Gaming standards repos with a fast-forward-only pull and report per-repo status. Use when the user says "update workspace", "pull standards", "refresh the standards docs", or invokes "/update-workspace" — and before dispatching any agent or skill that cites the standards.
assistants:
  copilot:
  cursor:
  windsurf:
---

You are the single owner of standards-repo freshness. No other agent or skill pulls these repos; they rely on you having run first.

## Repos

Operate on exactly these three repos, in this order:

1. `gaming-context-docs`
2. `gaming-process-docs`
3. `gaming-architecture-docs`

Resolve each one to a path before doing anything else, taking the first location that
exists — the same order every other agent and skill here uses, so they all read the
same checkout:

1. `workspace/{repo}` relative to the project root
2. `$HOME/Workspace/{repo}`

If neither exists, treat the repo as **skipped** and report the clone command for
`$HOME/Workspace/{repo}`. Never hardcode a home directory: this skill is installed on
other machines and by other people.

Touch nothing else. Never touch the project working tree.

## Per-repo procedure

For each path, in order:

1. If the directory does not exist, or it exists but `git -C {path} rev-parse --git-dir` fails, record the repo as **skipped**, note the reason (missing directory, or present but not a git repository), and report the clone command:

   ```
   git clone https://github.com/Flutter-Global/{repo} {path}
   ```

   Then continue to the next repo. A skip is a notice, never a failure.

2. Otherwise run:

   ```
   git -C {path} pull --ff-only
   ```

   Classify the outcome from its output:

   - **updated** — new commits were fast-forwarded. Report the short commit range git printed (for example `a1b2c3d..e4f5g6h`) and the number of commits if git reported it.
   - **up-to-date** — output contains `Already up to date`.
   - **failed** — non-fast-forward, dirty working tree, detached HEAD, no upstream configured, or a network error. Report the git error verbatim and the suggested manual fix:
     - dirty working tree → commit or stash the local changes in `{path}`, then re-run
     - non-fast-forward → the local branch has diverged; inspect with `git -C {path} log --oneline --graph HEAD..@{u}` and reconcile manually
     - detached HEAD or no upstream → `git -C {path} switch main`
     - network error → check connectivity or VPN, then re-run

   A failure on one repo does not stop the others. Continue.

## Output

Print a summary table with one row per repo:

| Repo | Status | Detail |
|---|---|---|
| gaming-context-docs | updated / up-to-date / skipped / failed | commit range, git error, or skip reason |
| gaming-process-docs | … | … |
| gaming-architecture-docs | … | … |

Close with a one-line verdict stating whether all present repos are now current, followed by an explicit list of every repo that is skipped or failed — so the caller knows which standards an agent will be unable to cite on this run.

## Rules

- `--ff-only` only. Never merge, rebase, reset, stash, checkout, or force anything.
- Never clone automatically. Report the clone command and let the developer decide.
- A missing or non-git repo is a notice, not a failure. The skill always completes and always prints the summary table.
- Resolve paths with the lookup order above. Report the resolved path for each repo in the Detail column so the caller can see which checkout was used.
- This is the only place in the setup permitted to run `git pull`.
