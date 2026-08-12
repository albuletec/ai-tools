#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Bash
## ait:timeout  5
set -u

# PreToolUse hook for Bash. Blocks (exit 2) irreversible operations. The message always
# explains how to proceed deliberately, so the user can re-issue the command themselves.
# Read-only inspection (git status/log/diff/show, git reset without --hard, git pull
# --ff-only, rm without -r and -f together) is never blocked.

deny() {
  printf 'destructive-op-guard: blocked - %s\n' "$1" >&2
  printf 'destructive-op-guard: command: %s\n' "$2" >&2
  printf 'destructive-op-guard: what would be lost: %s\n' "$3" >&2
  printf 'destructive-op-guard: safer alternative: %s\n' "$4" >&2
  printf 'destructive-op-guard: if this really is what you want, run it yourself in a terminal or grant an explicit override - it is being blocked so the decision is yours, not mine.\n' >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

raw=$(cat)
if [ -z "$raw" ]; then
  exit 0
fi

cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
if [ -z "$cmd" ]; then
  exit 0
fi

if printf '%s' "$cmd" | grep -qiE -e '(drop[[:space:]]+(table|database)|truncate[[:space:]]+table)'; then
  deny "the command contains a destructive SQL statement (DROP TABLE / DROP DATABASE / TRUNCATE TABLE)" \
    "$cmd" \
    "the table or database contents, with no rollback once the statement commits" \
    "run it against a disposable local database only, inside an explicit transaction you can ROLLBACK, and take a dump first (pg_dump / mysqldump)"
fi

segments=$(printf '%s' "$cmd" | tr ';|&' '\n\n\n')

while IFS= read -r seg; do
  if [ -z "${seg:-}" ]; then
    continue
  fi

  is_git=1
  if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])git([[:space:]]|$)'; then
    is_git=0
  fi

  if [ "$is_git" -eq 0 ]; then
    if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])reset([[:space:]]|$)' && printf '%s' "$seg" | grep -qE -e '--hard([[:space:]=]|$)'; then
      deny "git reset --hard discards work irreversibly" \
        "$seg" \
        "every uncommitted change in the working tree and the index, plus any commit between the current HEAD and the target ref" \
        "git reset --soft to keep the changes staged, git stash to park them, or git revert to undo a commit while keeping history"
    fi

    if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])push([[:space:]]|$)'; then
      if printf '%s' "$seg" | grep -qE -e '(--force([[:space:]=]|$)|--force-with-lease|(^|[[:space:]])-f([[:space:]]|$))'; then
        deny "force-pushing rewrites published history" \
          "$seg" \
          "any commit on the remote branch that is not an ancestor of what you are pushing - including a colleague's work if the branch is shared, and the protected refs main, master and release/*" \
          "push a new commit instead, or if the rewrite is genuinely required use git push --force-with-lease on a branch you own after confirming with git log --oneline @{u}..HEAD that nothing of anyone else's is being dropped"
      fi
    fi

    if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])clean([[:space:]]|$)'; then
      if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])-[a-zA-Z]*f' && printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])-[a-zA-Z]*d'; then
        deny "git clean with -f and -d deletes untracked files and directories" \
          "$seg" \
          "every untracked file and directory under the current path - including .env files, local scratch work, and with -x anything gitignored" \
          "git clean -nd first to see exactly what would go, then delete the specific paths you actually want gone with an explicit path argument"
      fi
    fi

    if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])(checkout|restore)[[:space:]]+\.([[:space:]]|$)'; then
      deny "checking out or restoring '.' overwrites the whole working tree" \
        "$seg" \
        "every uncommitted modification below the current directory, silently and with no reflog entry to recover from" \
        "git stash to park the changes recoverably, or name the specific file you want reverted instead of '.'"
    fi

    if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])branch([[:space:]]|$)' && printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])-D([[:space:]]|$)'; then
      deny "git branch -D force-deletes a branch without checking it is merged" \
        "$seg" \
        "any commit reachable only from that branch - recoverable from the reflog for a while, then garbage collected" \
        "git branch -d, which refuses unless the branch is merged; or push the branch to the remote first if you may want it back"
    fi
  fi

  if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])rm([[:space:]])'; then
    recursive_force=1
    if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])-[a-zA-Z]*([rR][a-zA-Z]*f|f[a-zA-Z]*[rR])'; then
      recursive_force=0
    fi
    if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])-[a-zA-Z]*[rR]([[:space:]]|$)' && printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])-[a-zA-Z]*f([[:space:]]|$)'; then
      recursive_force=0
    fi
    if [ "$recursive_force" -eq 0 ]; then
      if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])(/|~|\.|\.\.|\*|\$HOME|\$\{HOME\})([[:space:]]|$)'; then
        deny "rm -rf against a root, home, current, parent, or glob target" \
          "$seg" \
          "the entire tree below that target - the filesystem root, your home directory, or the whole current repository including untracked and gitignored files" \
          "never run this form; name the exact subdirectory you mean, and list it with ls first"
      fi
      deny "rm -rf deletes recursively with no confirmation and no undo" \
        "$seg" \
        "every file and directory below the target, including untracked and gitignored files that no commit can restore" \
        "list the target with ls -la first, then delete the narrowest path that achieves the goal - or use git clean -nd if the intent is to clear build output from a repository"
    fi
  fi
done <<SEGMENTS
$segments
SEGMENTS

exit 0
