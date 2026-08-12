# Testing

```bash
make test               # everything
tests/run.sh            # same
tests/run.sh golden     # one section
```

Sections: `syntax`, `install`, `unit`, `validate`, `rules`, `init`, `golden`, `hooks`.

No framework. Bash runs the harness; Ruby does the YAML and JSON assertions, because parsing
YAML with `grep` is how several of the bugs this suite exists to catch got in. Ruby ships with
macOS and with every GitHub runner.

## What each section covers

| Section | Covers |
|---------|--------|
| `syntax` | `/bin/bash -n` over every shipped script, plus the executable bit on every hook |
| `install` | The bootstrap symlink: `ait.sh` reachable as an extensionless `ait` from anywhere |
| `unit` | Frontmatter scalars and sequences, `yaml_quote` round-trips, hook metadata, the event tables |
| `validate` | Every fail-closed rule, and that the shipped repo is clean |
| `rules` | Rule discovery, the three renderers, Copilot's refusal, and every activation check |
| `init` | `assistant_init_targets` per assistant and scope, target dedup, and `install_init_file`'s three modes |
| `golden` | Installs every item for every assistant and scope into a temp tree, then inspects the result |
| `hooks` | Payload matrices for all five guards, plus terminology rule coverage |

The `rules` and `init` sections both build a fixture tree and point `REPO_DIR` at it, saving
and restoring `REPO_DIR` and `HOME` around the calls. `run_init_wizard` is never called — it
needs a TTY — so `init` drives `_init_collect`, `_init_write` and `install_init_file` directly.

## The golden section is the important one

It installs the real inventory for every registered assistant, both scopes, and then asserts
on what landed:

- every file parses as YAML frontmatter plus a non-empty body
- no file leaks the `assistants:` block
- every file has a non-empty description
- per-assistant frontmatter contracts — Copilot tools match the item's
  `assistants.copilot.tools` declaration, Cursor agents have no `tools` key, Windsurf gets no
  agents directory
- no agent gains `edit` on Copilot without a write tool in its `assistants.claude-code.tools`
  list
- `{instructionsFile}` resolved, with nothing left unsubstituted
- skill subdirectories arrive intact for all four assistants
- `settings.json` is valid JSON, groups one bucket per matcher, uses `${CLAUDE_PROJECT_DIR}`
  for project scope and `$HOME` for global, and is idempotent on re-install
- `patch_settings_json` reports failure honestly instead of printing a success line

Because it walks `AIT_ASSISTANTS` and `AIT_ITEM_TYPES`, a newly registered assistant — or a
newly modelled item type — is covered the moment it is registered. You only add assertions for
its own frontmatter quirks.

Its whole-tree pass globs `*.md` only, deliberately. A Cursor rule is a `.mdc` file and
legitimately has no `description`, since one would switch it to Agent Requested activation, so
widening the glob would break the "every file has a description" assertion. Cursor rules are
asserted on in the `rules` section instead.

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
