# Adding an Assistant

An assistant is a target AI coding tool. Each one has its own file formats, install paths,
and supported artifact types.

Adding one is **two changes**. Everything else — the wizard menu, `ait list`,
`ait validate`, the type filtering, the install dispatch — reads the registry, so there is
nowhere else to remember.

An assistant script declares *what differs*: which types it supports, where its files go, and
which frontmatter keys belong in them. Assembling and writing the file is `render_item`'s job,
shared by all four assistants.

## Step 1 — Write the assistant script

Create `scripts/assistants/{name}.sh`. The slug maps to a function prefix by replacing
hyphens with underscores, so `claude-code` looks for `claude_code_types`.

### `{name}_types()` — required

The artifact types this assistant supports, one display label per line:

```bash
myassistant_types() {
  printf 'Agent\nSkill\n'
}
```

Valid values are `Agent`, `Skill`, `Rule`, `Hook` — the set in `AIT_ITEM_TYPES`
(`scripts/collect.sh`). List only what the assistant can actually represent: a type you omit
is hidden from the wizard rather than failing at install time. Windsurf lists `Skill` and
`Rule`, because it has no subagent format; Copilot omits `Rule`, because its instructions
files use `applyTo:` and are a different artifact.

### `{name}_local_base()` and `{name}_global_base()` — required

Where this assistant's tree starts, at each scope. `assistant_dir` appends the item type's
plural to it, so declaring these two is all the path logic an assistant needs:

```bash
myassistant_local_base()  { printf '%s/.myassistant' "$1"; }   # $1 is PROJECT_DIR
myassistant_global_base() { printf '%s' "${AIT_MYASSISTANT_USER_DIR:-$HOME/.myassistant}"; }
```

`assistant_dir myassistant skill local /work/proj` then yields
`/work/proj/.myassistant/skills`. Read `$HOME` inside the function rather than capturing it
when the file is sourced, so the tests can point it at a fixture tree, and offer an
`AIT_{NAME}_USER_DIR` override for the global one.

### `{name}_install()` — required

Installs a single item. Receives five positional arguments and must return non-zero if it
did not install. Resolve the directory, then hand the work to `render_item`:

```bash
# Usage: myassistant_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
myassistant_install() {
  local name="$1"        # item name, e.g. "code-planner"
  local type="$2"        # "agent" | "skill" | "rule" | "hook"
  local rel_path="$3"    # repo-relative path, e.g. "common/agents/code-planner.md"
  local scope="$4"       # "global" | "local"
  local project_dir="$5" # absolute path to the current project
  local dir

  case "$type" in
    agent|skill) dir=$(assistant_dir myassistant "$type" "$scope" "$project_dir") ;;
    rule|hook)   item_skip "$type" "$name" "My Assistant has no such concept"; return 1 ;;
    *)           ait_note "Unknown type: $type"; return 1 ;;
  esac

  case "$type" in
    agent) render_item myassistant agent "$name" "$rel_path" \
             "$dir/$name.md" _myassistant_agent_fm ;;
    skill) render_item myassistant skill "$name" "$rel_path" \
             "$dir/$name/SKILL.md" _myassistant_skill_fm ;;
  esac
}
```

Add a branch for every type in `{name}_types()`. Adding a branch for one you *don't* list is
worth doing anyway, as defence in depth against a direct call — that is what Copilot's `rule)`
branch is for. Use `item_skip` for a type the assistant genuinely cannot represent, so the
reason reaches the user instead of a bare "skipped".

### The frontmatter functions

`render_item` writes the `---` delimiters, the body and the placeholder substitution. Your
job is only the keys in between. A frontmatter function receives `SRC` and `NAME`:

```bash
_myassistant_agent_fm() {
  local src="$1" name="$2"
  fm_name_description "$src" "$name"   # name + yaml_quoted description
  _assistant_opt "$src" myassistant model
  _assistant_opt "$src" myassistant readonly
}
```

Do not print the `---` lines, and do not write the file yourself — that is what keeps every
assistant's output consistent, and what stops the `yaml_quote` rule below from being something
each new assistant has to remember.

### `{name}_label()` — optional

The name shown in the wizard. Defaults to the slug.

```bash
myassistant_label() { printf 'My Assistant'; }
```

### `{name}_init_targets()` — optional

The per-project context files this assistant reads, for `ait init`. Zero or more
`SRC_REL<TAB>TARGET_ABS` lines, one per file:

```bash
# Usage: myassistant_init_targets SCOPE PROJECT_DIR
myassistant_init_targets() {
  local scope="$1" project_dir="$2"
  [ "$scope" = "local" ] || return 0
  printf 'myassistant/init/AGENTS.md\t%s/AGENTS.md\n' "$project_dir"
}
```

`SRC_REL` is repo-relative — the caller resolves it against `$REPO_DIR`, which is what lets the
tests point at a fixture tree — while `TARGET_ABS` is already absolute. Emit exactly one tab
between the two; the caller reads them with `IFS=$'\t'`.

**No output means "this assistant has no context file at this scope."** That is a normal
outcome, not an error: `ait init` reports the assistant as skipped. Only Claude Code emits a
global target today, because `~/.claude/CLAUDE.md` is the only home-directory context file that
is actually documented.

Read `$HOME` inside the function rather than capturing it when the file is sourced, so it can be
overridden.

Two assistants may return the same `TARGET_ABS` — Cursor and Windsurf both want `AGENTS.md`.
The wizard deduplicates by target path and reports the file as shared, so keep templates that
land on the same path byte-identical.

### `{name}_init_note()` — optional

One line shown on the init confirmation screen. Use it for something the user needs to know
about what is *not* being written:

```bash
myassistant_init_note() {
  printf '.myassistantrules is legacy and is not written — AGENTS.md is the file it reads.'
}
```

Both init functions are optional, so an assistant that never adds either keeps working and
"adding an assistant is two changes" still holds.

### Helpers available

From `body.sh`:

| Helper | Signature | Returns |
|--------|-----------|---------|
| `fm_get` | `fm_get FILE KEY` | Scalar as one logical line — folds block scalars, unquotes quoted ones |
| `fm_get_raw` | `fm_get_raw FILE KEY` | The value exactly as written, for writing straight back into YAML |
| `fm_get_list` | `fm_get_list FILE KEY` | Sequence, one element per line; handles inline, comma and block forms |
| `yaml_quote` | `yaml_quote VALUE` | A safely double-quoted YAML scalar |
| `get_body` | `get_body FILE` | Body text (after the closing `---`) |
| `substitute_placeholders` | `… \| substitute_placeholders ASSISTANT` | Body with `{token}` replaced |
| `assistant_config` | `assistant_config FILE ASSISTANT KEY` | Per-assistant configuration value |
| `has_assistant` | `has_assistant FILE ASSISTANT` | Exit 0 if the item opts in |
| `fm_name_description` | `fm_name_description SRC NAME` | Emits `name:` and a `yaml_quote`d `description:` |
| `_shared_opt` | `_shared_opt FILE ASSISTANT KEY` | Emits a `key: value` line, override first then top-level |
| `_assistant_opt` | `_assistant_opt FILE ASSISTANT KEY` | Emits a `key: value` line from `assistants.{slug}` only, no top-level fallback |

Use `_assistant_opt` for a key that means something different per assistant — Cursor's
`readonly`, Windsurf's `globs` — and `_shared_opt` for one that carries over unchanged. Both
print nothing when the key is absent and always return 0, so they are safe under `set -e`.

From `collect.sh`: `item_source_file REL_PATH` resolves a rel_path to an absolute path,
handling the directory-versus-flat-file distinction for skills.

From `registry.sh`: `assistant_dir ASSISTANT TYPE SCOPE PROJECT_DIR` resolves the install
directory from your two base functions. It returns non-zero for a type the assistant does not
support, rather than printing a path it would then be written to.

From `output.sh`: `item_ok TYPE TARGET`, `item_skip TYPE NAME REASON`, `item_fail TYPE DETAIL`,
and `ait_note` / `ait_detail` for anything else. Never write a raw `\033[` escape — colour is
resolved once, against stdout, so piped output stays plain text.

From `install.sh`:

| Helper | Signature | Does |
|--------|-----------|------|
| `render_item` | `render_item ASSISTANT TYPE NAME REL_PATH TARGET FM_FN` | Writes the whole file and reports it |
| `copy_skill_support_files` | `copy_skill_support_files SRC DEST` | Copies everything except `SKILL.md`, subdirectories included |
| `install_init_file` | `install_init_file SRC_ABS TARGET_ABS MODE` | Writes one `ait init` template. `MODE` is `ask`, `skip` or `overwrite` |
| `parse_hook_meta` | `parse_hook_meta FILE` | `EVENT<TAB>MATCHER<TAB>TIMEOUT` from the `## ait:` header |
| `patch_settings_json` | `patch_settings_json FILE EVENT MATCHER CMD TIMEOUT` | Adds a hook entry idempotently |

**`render_item` calls `copy_skill_support_files` for you.** Every assistant reads `scripts/`,
`references/` and `assets/` relative to `SKILL.md`, so a skill installed without them has its
own links pointing at nothing. `render_item` copies them whenever the item is a directory,
which is true only of directory-based skills — agents and rules are always single files.

`install_init_file` is called by the init wizard, not by your assistant script — you only
declare the targets. It writes whole files, never edits one in place, and leaves an existing
file alone (returning 0) unless the mode or the user says otherwise.

### Two rules that matter

**Emit `description` through `fm_name_description`, or `yaml_quote` it yourself.** A value
returned by `fm_get` has been read *out* of YAML, so it is not itself valid YAML — a
description containing `: ` or a leading `[` will produce a file that no longer parses.
`fm_name_description` does the quoting, which is why it is the default path.

**Never omit a tool restriction that the source declared.** Read your own tool list with
`assistant_config "$src" {slug} tools` — items declare it under `assistants.{slug}.tools`, in
your assistant's own tool names, written inline as `tools: [A, B]`. Never fall back to
another assistant's list; that would emit names your assistant does not understand.

Then check what an absent `tools` key means for your assistant. On Copilot it means *every
tool is enabled*, so an item that declares nothing must be refused rather than installed
unrestricted. If you cannot express the declared restriction, add a check to `validate.sh`
and refuse the install instead — see the `assistants.copilot.tools` check in `validate_item`.

### Minimal example

A whole assistant, end to end:

```bash
#!/usr/bin/env bash
# My Assistant.

myassistant_label() { printf 'My Assistant'; }

myassistant_types() { printf 'Agent\nSkill\n'; }

myassistant_local_base()  { printf '%s/.myassistant' "$1"; }
myassistant_global_base() { printf '%s' "${AIT_MYASSISTANT_USER_DIR:-$HOME/.myassistant}"; }

myassistant_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"
  local dir

  case "$type" in
    agent|skill) dir=$(assistant_dir myassistant "$type" "$scope" "$project_dir") ;;
    rule|hook)   item_skip "$type" "$name" "My Assistant has no such concept"; return 1 ;;
    *)           ait_note "Unknown type: $type"; return 1 ;;
  esac

  case "$type" in
    agent) render_item myassistant agent "$name" "$rel_path" \
             "$dir/$name.md" _myassistant_fm ;;
    skill) render_item myassistant skill "$name" "$rel_path" \
             "$dir/$name/SKILL.md" _myassistant_fm ;;
  esac
}

# Both types take the same two keys here, so one function serves both.
_myassistant_fm() {
  fm_name_description "$1" "$2"
}
```

That is the whole file. Compare it with `scripts/assistants/cursor.sh`, which supports three
types and several optional keys and is still under 120 lines including its documentation.

## Step 2 — Register the slug

Add it to `AIT_ASSISTANTS` in `scripts/registry.sh`:

```bash
AIT_ASSISTANTS="claude-code copilot cursor windsurf myassistant"
```

`ait` sources `scripts/assistants/{slug}.sh` for every slug in that list and fails
loudly at startup if the file is missing, so a typo cannot go unnoticed.

## Then

- **Add a `{instructionsFile}` mapping** in `scripts/body.sh` if the assistant does not
  read `AGENTS.md`:

  ```bash
  instructions_file_for() {
    case "$1" in
      claude-code) printf 'CLAUDE.md' ;;
      myassistant) printf 'MYASSISTANT.md' ;;
      *)           printf 'AGENTS.md' ;;
    esac
  }
  ```

- **Opt items in** by adding a key to the `assistants:` block of each item that should
  support it:

  ```yaml
  assistants:
    copilot:
    myassistant:
  ```

  Items without the key do not appear in the wizard when your assistant is selected.

- **Write the assistant doc** at `docs/assistants/{name}.md` and link it from
  `docs/README.md`.

- **Run the tests.** `tests/run.sh golden` installs every item for every registered
  assistant automatically, so a new assistant is covered the moment it is registered. Add
  explicit assertions for anything specific to its frontmatter contract, next to the ones
  for Cursor's missing `tools` key.

## Checklist

- [ ] `scripts/assistants/{name}.sh` with `{name}_types()`, `{name}_install()`,
      `{name}_local_base()` and `{name}_global_base()`
- [ ] Slug added to `AIT_ASSISTANTS` in `scripts/registry.sh`
- [ ] Files written through `render_item`, frontmatter through `fm_name_description`
- [ ] No raw `\033[` escapes — `item_ok`, `item_skip` and `ait_note` instead
- [ ] `{name}_init_targets()` if the assistant reads a per-project context file
- [ ] Tool restrictions preserved, or refused in `validate.sh`
- [ ] `{instructionsFile}` mapping in `body.sh` (if not `AGENTS.md`)
- [ ] `assistants: {name}:` added to the items that should support it
- [ ] `docs/assistants/{name}.md` written and linked
- [ ] `tests/run.sh` passes
