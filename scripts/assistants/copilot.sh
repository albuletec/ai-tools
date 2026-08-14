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
# Requires: REPO_DIR, body.sh, install.sh (render_item)

copilot_label() { printf 'Copilot'; }

copilot_types() {
  printf 'Agent\nSkill\n'
}

# Locally these land in .github/, which is a repository directory Copilot reads by
# convention rather than a dotfile of its own.
copilot_local_base()  { printf '%s/.github' "$1"; }
copilot_global_base() { printf '%s' "${AIT_COPILOT_USER_DIR:-$HOME/.copilot}"; }

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
  local dir

  case "$type" in
    agent|skill) dir=$(assistant_dir copilot "$type" "$scope" "$project_dir") ;;
    rule)
      item_skip rule "$name" \
        "Copilot instructions files use applyTo: and are not modelled"
      return 1
      ;;
    hook)
      item_skip hook "$name" "Copilot has no hook system"
      return 1
      ;;
    *)
      ait_note "Unknown type: $type"
      return 1
      ;;
  esac

  case "$type" in
    agent) render_item copilot agent "$name" "$rel_path" \
             "$dir/$name.agent.md" _copilot_agent_fm ;;
    skill) render_item copilot skill "$name" "$rel_path" \
             "$dir/$name/SKILL.md" _copilot_skill_fm ;;
  esac
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

_copilot_agent_fm() {
  local src="$1" name="$2" tools

  fm_name_description "$src" "$name"

  tools=$(assistant_config "$src" copilot tools)
  if [ -n "$tools" ]; then
    tools="${tools#[}"
    tools="${tools%]}"
  fi
  if [ -n "$tools" ]; then printf 'tools: [%s]\n' "$tools"; fi

  _assistant_opt "$src" copilot model
  _assistant_opt "$src" copilot target
  _assistant_opt "$src" copilot user-invocable
  _assistant_opt "$src" copilot disable-model-invocation
  _assistant_opt "$src" copilot mcp-servers
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

_copilot_skill_fm() {
  local src="$1" name="$2"
  fm_name_description "$src" "$name"
  _shared_opt "$src" copilot argument-hint
  _shared_opt "$src" copilot user-invocable
  _shared_opt "$src" copilot disable-model-invocation
  _assistant_opt "$src" copilot context
}
