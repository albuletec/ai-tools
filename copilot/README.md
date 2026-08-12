# Copilot

Artifacts that are specific to GitHub Copilot and are **not** items — configuration
templates, reference settings, wiring files.

`init/copilot-instructions.md` is the starter context file `ait init` copies to
`.github/copilot-instructions.md` in your project. It is plain markdown with no frontmatter
and is copied verbatim, so every `{curly}` token in it is a prompt for the reader to fill in
rather than a placeholder `ait` resolves.

Agents, skills and rules do not belong here. Every item definition lives under `common/`, and
an item opts into Copilot through the `assistants:` block in its own frontmatter:

```yaml
assistants:
  copilot:
```

See [`../docs/assistants/copilot.md`](../docs/assistants/copilot.md) for what `ait`
installs for Copilot, where it lands, and which frontmatter keys it honours.
