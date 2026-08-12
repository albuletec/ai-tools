# Adding an Assistant

An assistant is a target AI coding tool. Each one has its own file formats, install paths,
and supported artifact types.

Adding one is **two changes**. Everything else — the wizard menu, `ait list`,
`ait validate`, the type filtering, the install dispatch — reads the registry, so there is
nowhere else to remember.

## Step 1 — Write the assistant script

Create `scripts/lib/assistants/{name}.sh`. The slug maps to a function prefix by replacing
hyphens with underscores, so `claude-code` looks for `claude_code_types`.

### `{name}_types()` — required

The artifact types this assistant supports, one display label per line:

```bash
myassistant_types() {
  printf 'Agent\nSkill\n'
}
```

Valid values are `Agent`, `Skill`, `Hook`. List only what the assistant can actually
represent — a type you omit is hidden from the wizard rather than failing at install time.
Windsurf lists `Skill` only, because it has no subagent format.

### `{name}_install()` — required

Installs a single item. Receives five positional arguments and must return non-zero if it
did not install:

```bash
# Usage: myassistant_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
myassistant_install() {
  local name="$1"        # item name, e.g. "code-planner"
  local type="$2"        # "agent" | "skill" | "hook"
  local rel_path="$3"    # repo-relative path, e.g. "agents/code-planner.md"
  local scope="$4"       # "global" | "local"
  local project_dir="$5" # absolute path to the current project

  case "$type" in
    agent) _myassistant_write_agent "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _myassistant_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    *)     printf '  \033[33m!\033[0m  Unsupported type: %s\n' "$type"; return 1 ;;
  esac
}
```

### `{name}_label()` — optional

The name shown in the wizard. Defaults to the slug.

```bash
myassistant_label() { printf 'My Assistant'; }
```

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
| `translate_tools` | `translate_tools LIST` | Deduplicated Copilot-style tool list |
| `unmapped_tools` | `unmapped_tools LIST` | Names with no alias, one per line |
| `tools_are_readonly` | `tools_are_readonly LIST` | Exit 0 if the list grants no write access, direct or indirect |
| `assistant_config` | `assistant_config FILE ASSISTANT KEY` | Per-assistant override value |
| `has_assistant` | `has_assistant FILE ASSISTANT` | Exit 0 if the item opts in |
| `_shared_opt` | `_shared_opt FILE ASSISTANT KEY` | Emits a `key: value` line, override first then top-level |

From `collect.sh`: `item_source_file REL_PATH` resolves a rel_path to an absolute path,
handling the directory-versus-flat-file distinction for skills.

From `install.sh`: `copy_skill_support_files SRC DEST` copies everything except `SKILL.md`,
subdirectories included. **Call it for skills.** Every assistant reads `scripts/`,
`references/` and `assets/` relative to `SKILL.md`, so skipping it installs a skill whose own
links point at nothing.

### Two rules that matter

**Always run `description` through `yaml_quote`.** A value returned by `fm_get` has been
read *out* of YAML, so it is not itself valid YAML — a description containing `: ` or a
leading `[` will produce a file that no longer parses.

**Never omit a tool restriction that the source declared.** Check what an absent `tools` key
means for your assistant. On Copilot it means *every tool is enabled*, so dropping an
untranslatable name would widen access rather than narrow it. If you cannot express the
source's restriction, add a check to `validate.sh` and refuse the install instead. See
`_assistant_translates_tools` there.

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

Add it to `AIT_ASSISTANTS` in `scripts/lib/registry.sh`:

```bash
AIT_ASSISTANTS="claude-code copilot cursor windsurf myassistant"
```

`ait` sources `scripts/lib/assistants/{slug}.sh` for every slug in that list and fails
loudly at startup if the file is missing, so a typo cannot go unnoticed.

## Then

- **Add a `{instructionsFile}` mapping** in `scripts/lib/body.sh` if the assistant does not
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

- [ ] `scripts/lib/assistants/{name}.sh` with `{name}_types()` and `{name}_install()`
- [ ] Slug added to `AIT_ASSISTANTS` in `scripts/lib/registry.sh`
- [ ] `description` written through `yaml_quote`
- [ ] `copy_skill_support_files` called for skills
- [ ] Tool restrictions preserved, or refused in `validate.sh`
- [ ] `{instructionsFile}` mapping in `body.sh` (if not `AGENTS.md`)
- [ ] `assistants: {name}:` added to the items that should support it
- [ ] `docs/assistants/{name}.md` written and linked
- [ ] `tests/run.sh` passes
