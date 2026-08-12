---
name: pr-description
description: Write a pull request description from the current branch's changes. Use when the user says "write a PR description", "open a PR", "describe these changes", or asks for a PR body.
assistants:
  copilot:
  cursor:
  windsurf:
---

Produce a PR body from the actual diff. Gather context before writing a single line of it.

## Gather context

1. Detect the default branch — do not assume a name:
   ```
   git symbolic-ref --quiet --short refs/remotes/origin/HEAD
   ```
   If that fails, fall back to `git remote show origin` and read `HEAD branch`. If both fail, ask which branch to compare against.
2. Find the merge base: `git merge-base HEAD {defaultBranch}`.
3. `git diff --stat {mergeBase}..HEAD` for shape, then `git diff {mergeBase}..HEAD` for substance.
4. `git log --oneline {mergeBase}..HEAD` for the commit narrative.
5. `git rev-parse --abbrev-ref HEAD` for the branch name — extract a ticket reference from it if one is encoded there.
6. Discover the real test commands from `package.json` scripts, the equivalent manifest for the language in use, and the project's `{instructionsFile}` or contributing guide.

## Output sections

Emit exactly these, as markdown:

**Summary** — bulleted, one bullet per logical change, not per file. Describe behaviour, not file movement.

**Motivation / context** — why this change exists. Include the ticket or issue reference when it is derivable from the branch name or the commit messages. If no reference is derivable, say so rather than inventing one.

**Test plan** — commands that actually exist in this repository, quoted exactly as they are defined, plus the manual verification steps a reviewer can follow. Never invent a command.

**Reviewer notes** — where a reviewer should spend their attention: the risky areas, the intentional trade-offs, anything deliberately left out of scope, and any follow-up that is expected.

**Checklist** — tests added or updated; docs updated; no secrets committed; pre-commit hooks not bypassed; breaking changes called out.

## Rules

- Never include the raw diff in the output.
- Never invent a test command, a ticket number, or a reviewer concern that the diff does not support.
- Do not hardcode a default branch name — detect it.
- If the diff is empty, say so and stop.
