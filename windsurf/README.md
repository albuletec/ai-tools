# Windsurf

Artifacts that are specific to Windsurf and are **not** items — configuration templates,
reference settings, wiring files.

There are none yet, so this directory holds only this file.

Agents and skills do not belong here. Every item definition lives under `common/`, and an
item opts into Windsurf through the `assistants:` block in its own frontmatter:

```yaml
assistants:
  windsurf:
```

See [`../docs/assistants/windsurf.md`](../docs/assistants/windsurf.md) for what `ait`
installs for Windsurf, where it lands, and why it gets skills but no agents.
