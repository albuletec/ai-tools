# Windsurf

Artifacts that are specific to Windsurf and are **not** items — configuration templates,
reference settings, wiring files.

`init/AGENTS.md` is the starter context file `ait init` copies to `AGENTS.md` in your project.
It is plain markdown with no frontmatter and is copied verbatim, so every `{curly}` token in it
is a prompt for the reader to fill in rather than a placeholder `ait` resolves. It is kept
byte-identical to `../cursor/init/AGENTS.md`, because both assistants read the same file and
`ait init` writes it once.

Agents, skills and rules do not belong here. Every item definition lives under `common/`, and
an item opts into Windsurf through the `assistants:` block in its own frontmatter:

```yaml
assistants:
  windsurf:
```

See [`../docs/assistants/windsurf.md`](../docs/assistants/windsurf.md) for what `ait`
installs for Windsurf, where it lands, and why it gets skills and rules but no agents.
