# Adding a Provider

A provider is a target AI assistant. Each provider has its own file formats, install paths, and supported artifact types. Adding a provider requires four changes.

## Step 1 — Write the provider script

Create `scripts/lib/providers/<name>.sh`. The script must export two functions.

### `<name>_types()`

Returns the artifact types this provider supports, one per line:

```bash
myprovider_types() {
  printf 'Agent\nSkill\n'
}
```

Valid values: `Agent`, `Skill`, `Hook`. Hooks are Claude Code-specific; only add `Hook` if your provider has a tool-call interception system.

### `<name>_install()`

Installs a single item. Receives five positional arguments:

```bash
# Usage: myProvider_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
myProvider_install() {
  local name="$1"        # item name, e.g. "code-planner"
  local type="$2"        # "agent" | "skill" | "hook"
  local rel_path="$3"    # repo-relative path, e.g. "agents/code-planner.md"
  local scope="$4"       # "global" | "local"
  local project_dir="$5" # absolute path to the current project

  case "$type" in
    agent) _myProvider_write_agent "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _myProvider_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    *)     printf '  \033[33m!\033[0m  Unsupported type: %s\n' "$type" ;;
  esac
}
```

Inside the install functions, use the helpers from `body.sh`:

| Helper | Signature | Returns |
|--------|-----------|---------|
| `fm_get` | `fm_get FILE KEY` | Scalar frontmatter value |
| `get_body` | `get_body FILE` | Body text (after the closing `---`) |
| `substitute_placeholders` | `… \| substitute_placeholders PROVIDER` | Body with `{token}` replaced |
| `translate_tools` | `translate_tools "[Bash, Read]"` | Provider tool list string |
| `provider_config` | `provider_config FILE PROVIDER KEY` | Per-provider override value |
| `has_provider` | `has_provider FILE PROVIDER` | Exit 0 if supported |

Use `item_source_file` from `collect.sh` to resolve a `rel_path` to an absolute path (handles the directory-vs-flat-file distinction for skills).

### Minimal example

```bash
#!/usr/bin/env bash
# My provider

myProvider_types() {
  printf 'Agent\nSkill\n'
}

myProvider_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"
  local src target_dir
  src=$(item_source_file "$rel_path")

  local base
  if [ "$scope" = "global" ]; then
    base="$HOME/.myprovider"
  else
    base="$project_dir/.myprovider"
  fi

  case "$type" in
    agent)
      target_dir="$base/agents"
      mkdir -p "$target_dir"
      {
        printf -- '---\n'
        printf 'name: %s\n' "$name"
        printf 'description: %s\n' "$(fm_get "$src" description)"
        printf -- '---\n'
        get_body "$src" | substitute_placeholders myProvider
      } > "$target_dir/$name.md"
      printf '  \033[32m✓\033[0m  agent  →  %s/%s.md\n' "$target_dir" "$name"
      ;;
    skill)
      target_dir="$base/skills/$name"
      mkdir -p "$target_dir"
      {
        printf -- '---\n'
        printf 'name: %s\n' "$name"
        printf 'description: %s\n' "$(fm_get "$src" description)"
        printf -- '---\n'
        get_body "$src" | substitute_placeholders myProvider
      } > "$target_dir/SKILL.md"
      printf '  \033[32m✓\033[0m  skill  →  %s/SKILL.md\n' "$target_dir"
      ;;
    *)
      printf '  \033[33m!\033[0m  Unsupported type: %s\n' "$type"
      ;;
  esac
}
```

## Step 2 — Source the script in `ait`

Open `ait` and add a `source` line alongside the existing providers:

```bash
# shellcheck source=scripts/lib/providers/myprovider.sh
source "$LIB_DIR/providers/myprovider.sh"
```

## Step 3 — Add the provider to the wizard

Open `scripts/lib/wizard.sh` and add the new provider in two places.

**Provider menu** (inside `run_wizard`, step 1):

```bash
if single_menu "Select a provider" "" "Claude Code" "Copilot" "My Provider"; then
  case "$MENU_RESULT" in
    "Claude Code") provider="claude-code"  ;;
    "Copilot")     provider="copilot"      ;;
    "My Provider") provider="myprovider"   ;;
  esac
```

**Type loader** (inside `_load_types_for_provider`):

```bash
case "$provider" in
  claude-code) raw_types=$(claude_code_types)   ;;
  copilot)     raw_types=$(copilot_types)        ;;
  myprovider)  raw_types=$(myProvider_types)     ;;
  *)           raw_types=""                      ;;
esac
```

**Label helper** (inside `_provider_label`, optional but nice):

```bash
myprovider) printf 'My Provider' ;;
```

**Install dispatcher** (inside `_wizard_install`):

```bash
case "$provider" in
  claude-code) claude_code_install "$tool_name" "$type" "$rel_path" "$scope" "$project_dir" ;;
  copilot)     copilot_install     "$tool_name" "$type" "$rel_path" "$scope" "$project_dir" ;;
  myprovider)  myProvider_install  "$tool_name" "$type" "$rel_path" "$scope" "$project_dir" ;;
esac
```

## Step 4 — Add a `{instructionsFile}` mapping (if needed)

If your provider uses a different instructions filename, open `scripts/lib/body.sh` and add a case to `instructions_file_for`:

```bash
instructions_file_for() {
  case "$1" in
    claude-code) printf 'CLAUDE.md' ;;
    myprovider)  printf 'MYPROVIDER.md' ;;
    *)           printf 'AGENTS.md' ;;
  esac
}
```

## Step 5 — Opt items into the new provider

For any agent, skill, or hook that should be available for your provider, add it to the `providers:` block in the item file:

```yaml
providers:
  copilot:
  myprovider:
```

Items without a `myprovider:` key will not appear in the wizard when your provider is selected.

## Checklist

- [ ] `scripts/lib/providers/<name>.sh` with `<name>_types()` and `<name>_install()`
- [ ] Sourced in `ait`
- [ ] Added to provider menu in `scripts/lib/wizard.sh`
- [ ] Added to type loader in `scripts/lib/wizard.sh`
- [ ] Added to install dispatcher in `scripts/lib/wizard.sh`
- [ ] `{instructionsFile}` mapping in `scripts/lib/body.sh` (if needed)
- [ ] `providers: <name>:` added to items that should support it
