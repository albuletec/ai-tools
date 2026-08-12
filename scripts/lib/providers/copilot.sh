#!/usr/bin/env bash
# GitHub Copilot provider.
#
# Agents → .github/agents/<name>.agent.md   (custom agents, official format)
# Skills → .github/prompts/<name>.prompt.md (reusable prompt files)
# Hooks  → unsupported; Copilot has no tool-call event system.
#
# Frontmatter reference:
#   https://docs.github.com/en/copilot/reference/custom-agents-configuration
#   description is the only required key. model is optional and inherits the
#   user's default, so we omit it unless the item overrides it explicitly.
#
# Requires: REPO_DIR, body.sh (fm_get, get_body, translate_tools,
#           provider_config, substitute_placeholders)

copilot_types() {
  printf 'Agent\nSkill\n'
}

# Resolve the install directory for a given item type and scope.
_copilot_dir() {
  local type="$1" scope="$2" project_dir="$3"

  if [ "$scope" = "local" ]; then
    case "$type" in
      agent) printf '%s/.github/agents'  "$project_dir" ;;
      skill) printf '%s/.github/prompts' "$project_dir" ;;
    esac
    return
  fi

  # Global — VS Code user profile directory
  local vscode_user
  case "$(uname -s)" in
    Darwin) vscode_user="$HOME/Library/Application Support/Code/User" ;;
    Linux)  vscode_user="$HOME/.config/Code/User" ;;
    *)      vscode_user="$HOME/.config/Code/User" ;;
  esac

  case "$type" in
    agent) printf '%s/agents'  "$vscode_user" ;;
    skill) printf '%s/prompts' "$vscode_user" ;;
  esac
}

# Install a single item.
# Usage: copilot_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
copilot_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  case "$type" in
    agent) _copilot_write_agent  "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _copilot_write_prompt "$name" "$rel_path" "$scope" "$project_dir" ;;
    hook)
      printf '  \033[33m!\033[0m  hook   →  skipped (%s): Copilot has no hook system\n' "$name"
      ;;
    *)
      printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type"
      ;;
  esac
}

# ─── Agents → .github/agents/<name>.agent.md ──────────────────────────────────

_copilot_write_agent() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_copilot_dir agent "$scope" "$project_dir")
  target="$target_dir/$name.agent.md"

  mkdir -p "$target_dir"

  local description tools translated model override_tools
  description=$(fm_get "$src" description)
  tools=$(fm_get "$src" tools)
  translated=$(translate_tools "$tools")

  # Per-item overrides from the providers.copilot block
  override_tools=$(provider_config "$src" copilot tools)
  [ -n "$override_tools" ] && translated="${override_tools#[}" && translated="${translated%]}"
  model=$(provider_config "$src" copilot model)

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    [ -n "$translated" ] && printf 'tools: [%s]\n' "$translated"
    [ -n "$model" ]      && printf 'model: %s\n' "$model"

    local dmi ui
    dmi=$(provider_config "$src" copilot disable-model-invocation)
    ui=$(provider_config "$src" copilot user-invocable)
    [ -n "$dmi" ] && printf 'disable-model-invocation: %s\n' "$dmi"
    [ -n "$ui" ]  && printf 'user-invocable: %s\n' "$ui"

    printf -- '---\n'
    get_body "$src" | substitute_placeholders copilot
  } > "$target"

  printf '  \033[32m✓\033[0m  agent  →  %s\n' "$target"
}

# ─── Skills → .github/prompts/<name>.prompt.md ────────────────────────────────

_copilot_write_prompt() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_copilot_dir skill "$scope" "$project_dir")
  target="$target_dir/$name.prompt.md"

  mkdir -p "$target_dir"

  local description mode model
  description=$(fm_get "$src" description)
  mode=$(provider_config "$src" copilot mode)
  [ -z "$mode" ] && mode="agent"
  model=$(provider_config "$src" copilot model)

  {
    printf -- '---\n'
    printf 'mode: %s\n' "$mode"
    printf 'description: %s\n' "$description"
    [ -n "$model" ] && printf 'model: %s\n' "$model"
    printf -- '---\n'
    get_body "$src" | substitute_placeholders copilot
  } > "$target"

  printf '  \033[32m✓\033[0m  skill  →  %s\n' "$target"
}
