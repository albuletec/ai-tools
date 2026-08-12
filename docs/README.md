# Documentation

| Doc | What it covers |
|-----|---------------|
| [Overview](overview.md) | Concepts, artifact types, DRY mechanisms (assistants block, placeholders, per-assistant tool declarations), validation |
| [Getting started](getting-started.md) | Install the CLI, run the wizard, initialise a project with `ait init`, CLI commands |
| [Adding an agent](how-to/adding-an-agent.md) | Agent file format, frontmatter, tools, assistants block, install paths |
| [Adding a skill](how-to/adding-a-skill.md) | Skill file format, supporting files, per-assistant overrides, install paths |
| [Adding a rule](how-to/adding-a-rule.md) | Rule file format, per-assistant activation, Cursor's four modes, Windsurf's triggers, install paths |
| [Adding a hook](how-to/adding-a-hook.md) | Hook metadata headers, the event table, exit codes, STDIN format |
| [Adding an assistant](how-to/adding-an-assistant.md) | Two-step guide to wiring up a new AI assistant |
| [Assistant: Claude Code](assistants/claude-code.md) | All supported features, frontmatter keys, rule `paths`, hook wiring, `CLAUDE.md`, item inventory |
| [Assistant: Copilot](assistants/copilot.md) | All supported features, per-assistant tool declarations, why rules are unsupported, install paths, item inventory |
| [Assistant: Cursor](assistants/cursor.md) | Agent, skill and rule formats, the four rule activation modes, the explicit `readonly` override, install paths |
| [Assistant: Windsurf](assistants/windsurf.md) | Skill and rule formats, the five rule triggers, why agents are unsupported, install paths |
| [Testing](testing.md) | What the suite covers and how to add a case |

Plans written by the code-planner agent land in `docs/plans/` and are gitignored.
