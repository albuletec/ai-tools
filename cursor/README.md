# Cursor

Artifacts that are specific to Cursor and are **not** items — configuration templates,
reference settings, wiring files.

`init/AGENTS.md` is the starter context file `ait init` copies to `AGENTS.md` in your project.
It is plain markdown with no frontmatter and is copied verbatim, so every `{curly}` token in it
is a prompt for the reader to fill in rather than a placeholder `ait` resolves. It is kept
byte-identical to `../windsurf/init/AGENTS.md`, because both assistants read the same file and
`ait init` writes it once.

Agents, skills and rules do not belong here. Every item definition lives under `common/`, and
an item opts into Cursor through the `assistants:` block in its own frontmatter:

```yaml
assistants:
  cursor:
```

See [`../docs/assistants/cursor.md`](../docs/assistants/cursor.md) for what `ait` installs
for Cursor, where it lands, and which frontmatter keys it honours.
