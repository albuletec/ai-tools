# Adding a Skill

A skill is a slash-command workflow. The user (or the model) invokes it by name and the skill's instructions load into the current context as a directive to follow.

## File location

Directory-based (preferred — supports supporting files):

```
skills/<name>/SKILL.md
```

Flat file (no supporting files needed):

```
skills/<name>.md
```

Drop the file here and it appears in the `ait` wizard immediately — no registry to update. Any non-`SKILL.md` files in a directory-based skill folder are copied to the install target verbatim (reference data, lookup tables, palette files, etc.).

## Frontmatter

```markdown
---
name: my-skill
description: One-line description of what this skill does and when to use it.
providers:
  copilot:
---

Skill instructions go here.
```

### Required fields

| Field | Notes |
|-------|-------|
| `name` | Kebab-case identifier. Becomes the `/name` slash command. |
| `description` | One-line description. Used in the wizard and as the trigger description the model reads. |

Skills have no `model` or `tools` frontmatter — those are agent concepts. The skill loads as instructions within the invoking agent's context.

## The `providers:` block

Claude Code is always supported. To make a skill available for other providers, add a key under `providers:`:

```yaml
providers:
  copilot:
```

Per-provider overrides for skills:

```yaml
providers:
  copilot:
    argument-hint: "[pr-number]"
    user-invocable: false
    disable-model-invocation: true
    context: selection
```

| Override key | Type | Notes |
|--------------|------|-------|
| `argument-hint` | string | Hint shown in the UI when the user types the slash command |
| `user-invocable` | bool | Whether the user can invoke the skill directly |
| `disable-model-invocation` | bool | Prevent the model from invoking this skill |
| `context` | string | Copilot context type passed to the skill |

The entire `providers:` block is stripped before the file is written to disk.

## Placeholder tokens

Use `{instructionsFile}` in the body to reference the repo-level instructions file:

```markdown
Read `{instructionsFile}` before writing anything.
```

| Provider | Resolves to |
|----------|-------------|
| Claude Code | `CLAUDE.md` |
| Others | `AGENTS.md` |

## Install paths

| Scope | Claude Code | Copilot |
|-------|-------------|---------|
| Global | `~/.claude/skills/<name>/SKILL.md` | `~/.copilot/skills/<name>/SKILL.md` |
| Local | `.claude/skills/<name>/SKILL.md` | `.github/skills/<name>/SKILL.md` |

Supporting files in the source directory are copied alongside `SKILL.md` at the install target.

## Full example

```markdown
---
name: pr-description
description: Write a pull request description from the current branch's changes.
providers:
  copilot:
    argument-hint: "[branch]"
---

Produce a PR body from the actual diff. Gather context before writing a single line:

1. Detect the default branch.
2. Run `git diff <default>..<current> --stat` and `git log`.
3. Read `{instructionsFile}` for any PR conventions.
4. Write the description.
```
