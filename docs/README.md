# Documentation

| Doc | What it covers |
|-----|---------------|
| [Overview](overview.md) | Concepts, artifact types, DRY mechanisms (assistants block, placeholders, tool translation), validation |
| [Getting started](getting-started.md) | Install the CLI, run the wizard, CLI commands |
| [Adding an agent](how-to/adding-an-agent.md) | Agent file format, frontmatter, tools, assistants block, install paths |
| [Adding a skill](how-to/adding-a-skill.md) | Skill file format, supporting files, per-assistant overrides, install paths |
| [Adding a hook](how-to/adding-a-hook.md) | Hook metadata headers, the event table, exit codes, STDIN format |
| [Adding an assistant](how-to/adding-an-assistant.md) | Two-step guide to wiring up a new AI assistant |
| [Assistant: Claude Code](assistants/claude-code.md) | All supported features, frontmatter keys, hook wiring, item inventory |
| [Assistant: Copilot](assistants/copilot.md) | All supported features, tool translation, install paths, item inventory |
| [Assistant: Cursor](assistants/cursor.md) | Agent and skill formats, the `readonly` mapping, install paths |
| [Assistant: Windsurf](assistants/windsurf.md) | Skill format, why agents are unsupported, install paths |
| [Testing](testing.md) | What the suite covers and how to add a case |

Plans written by the code-planner agent land in `docs/plans/` and are gitignored.
