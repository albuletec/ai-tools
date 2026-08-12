# Adding a Skill

A skill is a slash-command workflow. The user (or the model) invokes it by name and the skill's instructions load into the current context as a directive to follow.

## File location

Directory-based (preferred — supports supporting files):

```
common/skills/{name}/SKILL.md
```

Flat file (no supporting files needed):

```
common/skills/{name}.md
```

Drop the file here and it appears in the `ait` wizard immediately — no registry to update. Any non-`SKILL.md` files in a directory-based skill folder are copied to the install target verbatim (reference data, lookup tables, palette files, etc.).

## Frontmatter

```markdown
---
name: my-skill
description: One-line description of what this skill does and when to use it.
assistants:
  copilot:
---

Skill instructions go here.
```

### Required fields

| Field | Notes |
|-------|-------|
| `name` | Kebab-case identifier, lowercase letters, numbers and hyphens only. Becomes the `/name` slash command. It must match the file or directory name — Cursor requires that, and validation refuses a mismatch for every assistant so the same item cannot install under two identities. |
| `description` | One-line description. Used in the wizard and as the trigger description the model reads. |

Skills have no `model` or `tools` frontmatter — those are agent concepts. The skill loads as instructions within the invoking agent's context.

## The `assistants:` block

Claude Code is always supported. To make a skill available for other assistants, add a key under `assistants:`:

```yaml
assistants:
  copilot:
```

Per-assistant overrides for skills:

```yaml
assistants:
  copilot:
    argument-hint: "[pr-number]"
    user-invocable: false
    disable-model-invocation: true
    context: fork
```

| Override key | Type | Notes |
|--------------|------|-------|
| `argument-hint` | string | Hint shown in the UI when the user types the slash command |
| `user-invocable` | bool | Whether the user can invoke the skill directly |
| `disable-model-invocation` | bool | Prevent the model from invoking this skill |
| `context` | string | Copilot and Claude Code only, and the values differ, so it is only ever read from the assistant block — never carried over from a top-level `context` |
| `paths` | string | Cursor only — glob restricting the skill to matching files |

`argument-hint`, `user-invocable`, `disable-model-invocation` and `paths` mean the same thing
in Claude Code as they do elsewhere, so a top-level value carries over automatically. Restate
one under `assistants:` only when a specific assistant needs a different value. Windsurf
documents no optional keys, so it receives `name` and `description` only.

The entire `assistants:` block is stripped before the file is written to disk.

## Placeholder tokens

Use `{instructionsFile}` in the body to reference the repo-level instructions file:

```markdown
Read `{instructionsFile}` before writing anything.
```

| Assistant | Resolves to |
|----------|-------------|
| Claude Code | `CLAUDE.md` |
| Others | `AGENTS.md` |

## Install paths

| Assistant | Global | Local |
|-----------|--------|-------|
| Claude Code | `~/.claude/skills/{name}/SKILL.md` | `.claude/skills/{name}/SKILL.md` |
| Copilot | `~/.copilot/skills/{name}/SKILL.md` | `.github/skills/{name}/SKILL.md` |
| Cursor | `~/.cursor/skills/{name}/SKILL.md` | `.cursor/skills/{name}/SKILL.md` |
| Windsurf | `~/.codeium/windsurf/skills/{name}/SKILL.md` | `.windsurf/skills/{name}/SKILL.md` |

## Supporting files

Everything in the source directory except `SKILL.md` is copied to the install target,
**subdirectories included**. All four assistants document reading `scripts/`, `references/`
and `assets/` relative to `SKILL.md`, so a skill that bundles reference material works
unchanged wherever it lands:

```
common/skills/dataviz/
  SKILL.md
  references/palette.md
  scripts/validate.py
```

Reference them with relative links from `SKILL.md`. `tests/run.sh golden` asserts that a
nested fixture arrives intact for every assistant.

## Full example

```markdown
---
name: pr-description
description: Write a pull request description from the current branch's changes.
assistants:
  copilot:
    argument-hint: "[branch]"
---

Produce a PR body from the actual diff. Gather context before writing a single line:

1. Detect the default branch.
2. Run `git diff <default>..<current> --stat` and `git log`.
3. Read `{instructionsFile}` for any PR conventions.
4. Write the description.
```
