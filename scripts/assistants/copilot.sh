#!/usr/bin/env bash
# GitHub Copilot assistant (VS Code, JetBrains, Copilot CLI, cloud agent).
#
# Agents → <dir>/<name>.agent.md
# Skills → <dir>/<name>/SKILL.md
# Rules  → unsupported. Copilot's nearest equivalent is
#          .github/instructions/<name>.instructions.md, which selects files with
#          applyTo: and has its own precedence rules, so it is a different
#          artifact from the rule directories Claude Code, Cursor and Windsurf
#          read. Rule is absent from copilot_types() so the wizard never offers
#          it; the branch in copilot_install is defence in depth for a direct call.
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
# Requires: REPO_DIR, body.sh, collect.sh (item_source_file), install.sh

copilot_label() { printf 'Copilot'; }

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

# The per-project context file. .github/copilot-instructions.md is a repository
# file by definition, and no home-directory equivalent is as well documented as
# ~/.claude/CLAUDE.md, so global scope emits nothing and `ait init` reports Copilot
# as skipped there.
# Usage: copilot_init_targets SCOPE PROJECT_DIR
copilot_init_targets() {
  local scope="$1" project_dir="$2"
  [ "$scope" = "local" ] || return 0
  printf 'copilot/init/copilot-instructions.md\t%s/.github/copilot-instructions.md\n' "$project_dir"
}

# Install a single item.
# Usage: copilot_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
copilot_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  case "$type" in
    agent) _copilot_write_agent "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _copilot_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    rule)
      printf '  \033[33m!\033[0m  rule   →  skipped (%s): Copilot instructions files use applyTo: and are not modelled\n' "$name"
      return 1
      ;;
    hook)
      printf '  \033[33m!\033[0m  hook   →  skipped (%s): Copilot has no hook system\n' "$name"
      return 1
      ;;
    *)
      printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type"
      return 1
      ;;
  esac
}

# Emit an optional frontmatter line when the item overrides it for Copilot.
# The value is written through verbatim: it was authored as YAML in the source.
# Always returns 0 — a missing key is normal, and the caller runs under `set -e`.
_copilot_opt() {
  local src="$1" key="$2" val
  val=$(assistant_config "$src" copilot "$key")
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
#
# tools comes only from assistants.copilot.tools, written in Copilot's own tool
# names. There is no fallback to a top-level tools key: Copilot treats an absent
# tools key as "every tool enabled", so an agent that opts into Copilot must
# declare its own list — validate.sh refuses the install when it does not.

_copilot_write_agent() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_copilot_dir agent "$scope" "$project_dir")
  target="$target_dir/$name.agent.md"

  mkdir -p "$target_dir"

  local description tools=""
  description=$(fm_get "$src" description)

  tools=$(assistant_config "$src" copilot tools)
  if [ -n "$tools" ]; then
    tools="${tools#[}"
    tools="${tools%]}"
  fi

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$(yaml_quote "$description")"
    if [ -n "$tools" ]; then printf 'tools: [%s]\n' "$tools"; fi
    _copilot_opt "$src" model
    _copilot_opt "$src" target
    _copilot_opt "$src" user-invocable
    _copilot_opt "$src" disable-model-invocation
    _copilot_opt "$src" mcp-servers
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
#
# argument-hint, user-invocable and disable-model-invocation mean the same thing
# in Claude Code and Copilot, so a top-level value carries over automatically and
# only needs restating under assistants.copilot to differ.

_copilot_write_skill() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_copilot_dir skill "$scope" "$project_dir")
  target="$target_dir/$name"

  mkdir -p "$target"

  if [ -d "$REPO_DIR/$rel_path" ]; then
    copy_skill_support_files "$REPO_DIR/$rel_path" "$target"
  fi

  local description
  description=$(fm_get "$src" description)

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$(yaml_quote "$description")"
    _shared_opt "$src" copilot argument-hint
    _shared_opt "$src" copilot user-invocable
    _shared_opt "$src" copilot disable-model-invocation
    _copilot_opt "$src" context
    printf -- '---\n'
    get_body "$src" | substitute_placeholders copilot
  } > "$target/SKILL.md"

  printf '  \033[32m✓\033[0m  skill  →  %s/SKILL.md\n' "$target"
}
