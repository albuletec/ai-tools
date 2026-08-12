#!/usr/bin/env bash
# GitHub Copilot provider (VS Code, JetBrains, Copilot CLI, cloud agent).
#
# Agents → <dir>/<name>.agent.md
# Skills → <dir>/<name>/SKILL.md
# Hooks  → unsupported; Copilot has no tool-call event system.
#
# Skills are NOT installed as .prompt.md files. Copilot supports Anthropic-style
# SKILL.md natively, and the VS Code docs state that agents running on the Agent
# Host don't use prompt files at all — VS Code even ships a "Migrate Prompts"
# command that converts prompt files into skills. Prompt files are the legacy path.
#   https://code.visualstudio.com/docs/agent-customization/agent-skills
#   https://code.visualstudio.com/updates/v1_129
#
# Global scope targets the harness-agnostic ~/.copilot tree, which is what the
# Agent Host reads and what chat.agentSkillsLocations enables by default. The
# older in-extension harness instead reads the VS Code profile's prompts folder;
# set AIT_COPILOT_USER_DIR to target that if you're on the local harness.
#
# Requires: REPO_DIR, body.sh, collect.sh (item_source_file)

copilot_types() {
  printf 'Agent\nSkill\n'
}

# Install directory for a type and scope.
_copilot_dir() {
  local type="$1" scope="$2" project_dir="$3"

  if [ "$scope" = "local" ]; then
    case "$type" in
      agent) printf '%s/.github/agents' "$project_dir" ;;
      skill) printf '%s/.github/skills' "$project_dir" ;;
    esac
    return
  fi

  local user_base="${AIT_COPILOT_USER_DIR:-$HOME/.copilot}"
  case "$type" in
    agent) printf '%s/agents' "$user_base" ;;
    skill) printf '%s/skills' "$user_base" ;;
  esac
}

# Install a single item.
# Usage: copilot_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
copilot_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  case "$type" in
    agent) _copilot_write_agent "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _copilot_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    hook)
      printf '  \033[33m!\033[0m  hook   →  skipped (%s): Copilot has no hook system\n' "$name"
      ;;
    *)
      printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type"
      ;;
  esac
}

# Emit an optional frontmatter line when the item overrides it for Copilot.
# Always returns 0 — a missing key is normal, and the caller runs under `set -e`.
_copilot_opt() {
  local src="$1" key="$2" val
  val=$(provider_config "$src" copilot "$key")
  if [ -n "$val" ]; then
    printf '%s: %s\n' "$key" "$val"
  fi
  return 0
}

# ─── Agents → <dir>/<name>.agent.md ───────────────────────────────────────────
#
# Frontmatter per https://docs.github.com/en/copilot/reference/custom-agents-configuration
# description is the only required key; model is optional and inherits the user's
# default, so it's omitted unless the item sets one explicitly.

_copilot_write_agent() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_copilot_dir agent "$scope" "$project_dir")
  target="$target_dir/$name.agent.md"

  mkdir -p "$target_dir"

  local description tools override_tools
  description=$(fm_get "$src" description)
  tools=$(translate_tools "$(fm_get "$src" tools)")

  override_tools=$(provider_config "$src" copilot tools)
  if [ -n "$override_tools" ]; then
    override_tools="${override_tools#[}"
    tools="${override_tools%]}"
  fi

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    if [ -n "$tools" ]; then printf 'tools: [%s]\n' "$tools"; fi
    _copilot_opt "$src" model
    _copilot_opt "$src" target
    _copilot_opt "$src" user-invocable
    _copilot_opt "$src" disable-model-invocation
    printf -- '---\n'
    get_body "$src" | substitute_placeholders copilot
  } > "$target"

  printf '  \033[32m✓\033[0m  agent  →  %s\n' "$target"
}

# ─── Skills → <dir>/<name>/SKILL.md ───────────────────────────────────────────
#
# Frontmatter per https://code.visualstudio.com/docs/agent-customization/agent-skills
# name and description are both REQUIRED here (unlike Claude Code, where both are
# optional) — name must be lowercase letters, numbers and hyphens only.

_copilot_write_skill() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_copilot_dir skill "$scope" "$project_dir")
  target="$target_dir/$name"

  mkdir -p "$target"

  # Copy supporting files verbatim; SKILL.md itself is rendered below.
  if [ -d "$REPO_DIR/$rel_path" ]; then
    local f
    for f in "$REPO_DIR/$rel_path"/*; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = "SKILL.md" ] && continue
      cp "$f" "$target/"
    done
  fi

  local description
  description=$(fm_get "$src" description)

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    _copilot_opt "$src" argument-hint
    _copilot_opt "$src" user-invocable
    _copilot_opt "$src" disable-model-invocation
    _copilot_opt "$src" context
    printf -- '---\n'
    get_body "$src" | substitute_placeholders copilot
  } > "$target/SKILL.md"

  printf '  \033[32m✓\033[0m  skill  →  %s/SKILL.md\n' "$target"
}
