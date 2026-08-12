# Adding an Assistant

An assistant is a target AI coding tool. Each one has its own file formats, install paths,
and supported artifact types.

Adding one is **two changes**. Everything else — the wizard menu, `ait list`,
`ait validate`, the type filtering, the install dispatch — reads the registry, so there is
nowhere else to remember.

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

### `{name}_install()` — required

Installs a single item. Receives five positional arguments and must return non-zero if it
did not install:

```bash
# Usage: myassistant_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
myassistant_install() {
  local name="$1"        # item name, e.g. "code-planner"
  local type="$2"        # "agent" | "skill" | "rule" | "hook"
  local rel_path="$3"    # repo-relative path, e.g. "common/agents/code-planner.md"
  local scope="$4"       # "global" | "local"
  local project_dir="$5" # absolute path to the current project

  case "$type" in
    agent) _myassistant_write_agent "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _myassistant_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    *)     printf '  \033[33m!\033[0m  Unsupported type: %s\n' "$type"; return 1 ;;
  esac
}
```

Add a branch for every type in `{name}_types()`. Adding a branch for one you *don't* list is
worth doing anyway, as defence in depth against a direct call — that is what Copilot's `rule)`
branch is for.

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
| `_shared_opt` | `_shared_opt FILE ASSISTANT KEY` | Emits a `key: value` line, override first then top-level |

From `collect.sh`: `item_source_file REL_PATH` resolves a rel_path to an absolute path,
handling the directory-versus-flat-file distinction for skills.

From `install.sh`:

| Helper | Signature | Does |
|--------|-----------|------|
| `copy_skill_support_files` | `copy_skill_support_files SRC DEST` | Copies everything except `SKILL.md`, subdirectories included |
| `install_init_file` | `install_init_file SRC_ABS TARGET_ABS MODE` | Writes one `ait init` template. `MODE` is `ask`, `skip` or `overwrite` |
| `parse_hook_meta` | `parse_hook_meta FILE` | `EVENT<TAB>MATCHER<TAB>TIMEOUT` from the `## ait:` header |
| `patch_settings_json` | `patch_settings_json FILE EVENT MATCHER CMD TIMEOUT` | Adds a hook entry idempotently |

**Call `copy_skill_support_files` for skills.** Every assistant reads `scripts/`,
`references/` and `assets/` relative to `SKILL.md`, so skipping it installs a skill whose own
links point at nothing. Rules are flat files and never need it.

`install_init_file` is called by the init wizard, not by your assistant script — you only
declare the targets. It writes whole files, never edits one in place, and leaves an existing
file alone (returning 0) unless the mode or the user says otherwise.

### Two rules that matter

**Always run `description` through `yaml_quote`.** A value returned by `fm_get` has been
read *out* of YAML, so it is not itself valid YAML — a description containing `: ` or a
leading `[` will produce a file that no longer parses.

**Never omit a tool restriction that the source declared.** Read your own tool list with
`assistant_config "$src" {slug} tools` — items declare it under `assistants.{slug}.tools`, in
your assistant's own tool names, written inline as `tools: [A, B]`. Never fall back to
another assistant's list; that would emit names your assistant does not understand.

Then check what an absent `tools` key means for your assistant. On Copilot it means *every
tool is enabled*, so an item that declares nothing must be refused rather than installed
unrestricted. If you cannot express the declared restriction, add a check to `validate.sh`
and refuse the install instead — see the `assistants.copilot.tools` check in `validate_item`.

### Minimal example

```bash
#!/usr/bin/env bash
# My Assistant.

myassistant_label() { printf 'My Assistant'; }

myassistant_types() { printf 'Agent\nSkill\n'; }

_myassistant_dir() {
  local type="$1" scope="$2" project_dir="$3" base
  if [ "$scope" = "local" ]; then
    base="$project_dir/.myassistant"
  else
    base="${AIT_MYASSISTANT_USER_DIR:-$HOME/.myassistant}"
  fi
  printf '%s/%ss' "$base" "$type"
}

myassistant_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"
  local src target_dir description
  src=$(item_source_file "$rel_path")
  target_dir=$(_myassistant_dir "$type" "$scope" "$project_dir")
  description=$(fm_get "$src" description)

  case "$type" in
    agent)
      mkdir -p "$target_dir"
      {
        printf -- '---\n'
        printf 'name: %s\n' "$name"
        printf 'description: %s\n' "$(yaml_quote "$description")"
        printf -- '---\n'
        get_body "$src" | substitute_placeholders myassistant
      } > "$target_dir/$name.md"
      printf '  \033[32m✓\033[0m  agent  →  %s/%s.md\n' "$target_dir" "$name"
      ;;
    skill)
      mkdir -p "$target_dir/$name"
      [ -d "$REPO_DIR/$rel_path" ] && copy_skill_support_files "$REPO_DIR/$rel_path" "$target_dir/$name"
      {
        printf -- '---\n'
        printf 'name: %s\n' "$name"
        printf 'description: %s\n' "$(yaml_quote "$description")"
        printf -- '---\n'
        get_body "$src" | substitute_placeholders myassistant
      } > "$target_dir/$name/SKILL.md"
      printf '  \033[32m✓\033[0m  skill  →  %s/%s/SKILL.md\n' "$target_dir" "$name"
      ;;
    *)
      printf '  \033[33m!\033[0m  Unsupported type: %s\n' "$type"
      return 1
      ;;
  esac
}
```

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

- [ ] `scripts/assistants/{name}.sh` with `{name}_types()` and `{name}_install()`
- [ ] Slug added to `AIT_ASSISTANTS` in `scripts/registry.sh`
- [ ] `description` written through `yaml_quote`
- [ ] `copy_skill_support_files` called for skills
- [ ] `{name}_init_targets()` if the assistant reads a per-project context file
- [ ] Tool restrictions preserved, or refused in `validate.sh`
- [ ] `{instructionsFile}` mapping in `body.sh` (if not `AGENTS.md`)
- [ ] `assistants: {name}:` added to the items that should support it
- [ ] `docs/assistants/{name}.md` written and linked
- [ ] `tests/run.sh` passes
