# Copilot

Artifacts that are specific to GitHub Copilot and are **not** items — configuration
templates, reference settings, wiring files.

There are none yet, so this directory holds only this file.

Agents and skills do not belong here. Every item definition lives under `common/`, and an
item opts into Copilot through the `assistants:` block in its own frontmatter:

```yaml
assistants:
  copilot:
```

See [`../docs/assistants/copilot.md`](../docs/assistants/copilot.md) for what `ait`
installs for Copilot, where it lands, and which frontmatter keys it honours.
