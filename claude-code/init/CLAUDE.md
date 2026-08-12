<!-- Starter context file for Claude Code. `ait init` copies this to CLAUDE.md at the repo root, or to ~/.claude/CLAUDE.md at global scope. Replace every {curly} placeholder. -->

# {project name}

## Overview

What this project is, who uses it, and the one thing somebody needs to understand before
changing anything in it.

## Tech stack

- Language and version: {language}
- Framework: {framework}
- Package manager: {package manager}
- Datastores and external services: {list them}

## Commands

| Task | Command |
|------|---------|
| Install dependencies | `{install command}` |
| Build | `{build command}` |
| Test | `{test command}` |
| Lint | `{lint command}` |
| Type-check | `{type-check command}` |

Run the lint and type-check commands before treating a change as finished.

## Code conventions

Describe what this codebase already does, not what you wish it did — naming, file layout,
error handling, logging, how configuration is read. {conventions}

## Testing expectations

Which layers are tested, where the tests live, and what a change is expected to come with.
{testing expectations}

## Do not

- {things that look reasonable but are wrong here}
- Commit generated or vendored files.
- Add a dependency without checking whether one already in the tree does the job.
