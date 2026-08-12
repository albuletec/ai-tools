# Testing

```bash
make test               # everything
tests/run.sh            # same
tests/run.sh golden     # one section
```

Sections: `syntax`, `unit`, `validate`, `golden`, `hooks`.

No framework. Bash runs the harness; Ruby does the YAML and JSON assertions, because parsing
YAML with `grep` is how several of the bugs this suite exists to catch got in. Ruby ships with
macOS and with every GitHub runner.

## What each section covers

| Section | Covers |
|---------|--------|
| `syntax` | `/bin/bash -n` over every shipped script, plus the executable bit on every hook |
| `unit` | Frontmatter scalars and sequences, `yaml_quote` round-trips, tool translation, `readonly` derivation, hook metadata, the event tables |
| `validate` | Every fail-closed rule, and that the shipped repo is clean |
| `golden` | Installs every item for every assistant and scope into a temp tree, then inspects the result |
| `hooks` | Payload matrices for all five guards, plus terminology rule coverage |

## The golden section is the important one

It installs the real inventory for every registered assistant, both scopes, and then asserts
on what landed:

- every file parses as YAML frontmatter plus a non-empty body
- no file leaks the `assistants:` block
- every file has a non-empty description
- per-assistant frontmatter contracts — Copilot tools are canonical aliases, Cursor agents have
  no `tools` key, Windsurf gets no agents directory
- no agent widened its tool list relative to the source
- `{instructionsFile}` resolved, with nothing left unsubstituted
- skill subdirectories arrive intact for all four assistants
- `settings.json` is valid JSON, groups one bucket per matcher, uses `${CLAUDE_PROJECT_DIR}`
  for project scope and `$HOME` for global, and is idempotent on re-install
- `patch_settings_json` reports failure honestly instead of printing a success line

Because it walks `AIT_ASSISTANTS`, a newly registered assistant is covered the moment it is
registered — you only add assertions for its own frontmatter quirks.

## Adding a case

Every case in the suite maps to a defect that was once real. Keep that property: write the
assertion first, watch it fail against the current code, then fix the code.

Mark a case that reproduces a specific past bug with a `# regression:` comment explaining what
used to happen, so nobody later "simplifies" the assertion and quietly restores the bug.

Two harness rules worth knowing:

- **Assert on the shape of the output, not merely on its presence.** The terminology-guard
  cases originally checked "output is non-empty", which let a shell syntax error in the hook
  masquerade as fifteen passing rules. They now count lines matching `^terminology-guard: `.
  That is why the `syntax` section exists too.
- **Build hook payloads in the shell.** `payload_command` and `payload_write` assemble JSON
  without starting a process, which keeps a few hundred cases fast enough that the suite
  actually gets run.

## Writing test fixtures that the guards allow

The shipped hooks scan tool input, so a test containing a literal that looks like a secret,
a destructive command, or a hook-skipping git flag will be blocked when it is written or run
by an agent that has these hooks installed. Assemble those strings at run time instead:

```bash
key="sk"; key="${key}-abcdefghijklmnopqrstuvwx"
nv="--no-"; nv="${nv}verify"
```

This is a real constraint of dogfooding the guards, not a workaround for a bug — the hooks
cannot tell an instruction from a mention of one, which is why they are written to match on the
invoking command rather than on words alone.

## CI

`.github/workflows/test.yml` runs `tests/run.sh` and `ait validate` on push and pull request,
on Ubuntu and macOS. macOS matters: it is the platform with bash 3.2, where the parser quirks
documented in [adding a hook](how-to/adding-a-hook.md#bash-version) actually bite.
