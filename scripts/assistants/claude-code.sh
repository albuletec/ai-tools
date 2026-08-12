#!/usr/bin/env bash
# Claude Code assistant.
#
# Agents → .claude/agents/<name>.md
# Skills → .claude/skills/<name>/SKILL.md
# Rules  → .claude/rules/<name>.md
# Hooks  → .claude/hooks/<name>.sh, wired into settings.json
#
# Shared frontmatter keys are passed through verbatim so any key Claude Code
# supports keeps working without a change here. The assistants: block is
# stripped, so Claude Code never sees another assistant's configuration, and
# model and tools are read back out of assistants.claude-code and emitted at the
# top level where Claude Code expects them.
#
# Rules are the exception: they are rendered explicitly rather than passed
# through, because a rule's activation keys are per-assistant. A top-level
# trigger: or globs: written for Windsurf or Cursor must never leak into a
# Claude Code file, and passthrough would copy it verbatim.
#
# Requires: REPO_DIR, body.sh, install.sh (parse_hook_meta, patch_settings_json)

claude_code_label() { printf 'Claude Code'; }

claude_code_types() {
  printf 'Agent\nSkill\nRule\nHook\n'
}

# The per-project context file. Claude Code is the only assistant with a
# documented home-directory equivalent, so it is the only one that offers a global
# target. $HOME is read here, at call time, rather than captured when this file is
# sourced, so the tests can point it at a fixture tree.
# Usage: claude_code_init_targets SCOPE PROJECT_DIR
claude_code_init_targets() {
  local scope="$1" project_dir="$2"
  if [ "$scope" = "global" ]; then
    printf 'claude-code/init/CLAUDE.md\t%s/.claude/CLAUDE.md\n' "$HOME"
  else
    printf 'claude-code/init/CLAUDE.md\t%s/CLAUDE.md\n' "$project_dir"
  fi
}

# Install a single item.
# Usage: claude_code_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
claude_code_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  local base settings_file
  if [ "$scope" = "global" ]; then
    base="$HOME/.claude"
  else
    base="$project_dir/.claude"
  fi
  settings_file="$base/settings.json"

  case "$type" in
    agent) _cc_write_agent "$name" "$rel_path" "$base/agents" ;;
    skill) _cc_write_skill "$name" "$rel_path" "$base/skills" ;;
    rule)  _cc_write_rule  "$name" "$rel_path" "$base/rules" ;;
    hook)  _cc_write_hook  "$name" "$rel_path" "$scope" "$base/hooks" "$settings_file" ;;
    *)     printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type"; return 1 ;;
  esac
}

# Emit an optional frontmatter line when the item sets it for Claude Code.
# The value is written through verbatim: it was authored as YAML in the source.
# Always returns 0 — a missing key is normal, and the caller runs under `set -e`.
_cc_opt() {
  local src="$1" key="$2" val
  val=$(assistant_config "$src" claude-code "$key")
  if [ -n "$val" ]; then
    printf '%s: %s\n' "$key" "$val"
  fi
  return 0
}

# Rewrite an item file for Claude Code: keep the shared frontmatter keys, drop
# the assistants: block, re-emit model and tools from assistants.claude-code,
# substitute placeholders in the body. The two extra keys are emitted only when
# the item declares them, so skills — which never do — are unaffected.
_cc_render() {
  local src="$1"

  printf -- '---\n'
  get_frontmatter "$src" | awk '
    /^assistants:/         { ina=1; next }
    ina && /^[[:space:]]/  { next }
    ina && /^[[:space:]]*$/{ next }
    ina && /^[^[:space:]]/ { ina=0 }
    { print }'
  _cc_opt "$src" model
  _cc_opt "$src" tools
  printf -- '---\n'
  get_body "$src" | substitute_placeholders claude-code
}

_cc_write_agent() {
  local name="$1" rel_path="$2" target_dir="$3"
  mkdir -p "$target_dir"
  _cc_render "$REPO_DIR/$rel_path" > "$target_dir/$name.md"
  printf '  \033[32m✓\033[0m  agent  →  %s/%s.md\n' "$target_dir" "$name"
}

_cc_write_skill() {
  local name="$1" rel_path="$2" target_dir="$3"
  local src="$REPO_DIR/$rel_path"
  mkdir -p "$target_dir/$name"

  if [ -d "$src" ]; then
    copy_skill_support_files "$src" "$target_dir/$name"
    _cc_render "$src/SKILL.md" > "$target_dir/$name/SKILL.md"
  else
    _cc_render "$src" > "$target_dir/$name/SKILL.md"
  fi

  printf '  \033[32m✓\033[0m  skill  →  %s/%s/SKILL.md\n' "$target_dir" "$name"
}

# Rules carry exactly three keys: name, description, and paths when the item
# declares one. paths goes through _shared_opt, so assistants.claude-code.paths
# wins and a top-level paths carries over — the same behaviour skills have.
# Nothing is printed when neither is set, and the rule then always loads.
_cc_write_rule() {
  local name="$1" rel_path="$2" target_dir="$3"
  local src="$REPO_DIR/$rel_path"
  mkdir -p "$target_dir"

  local description
  description=$(fm_get "$src" description)

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$(yaml_quote "$description")"
    _shared_opt "$src" claude-code paths
    printf -- '---\n'
    get_body "$src" | substitute_placeholders claude-code
  } > "$target_dir/$name.md"

  printf '  \033[32m✓\033[0m  rule   →  %s/%s.md\n' "$target_dir" "$name"
}

_cc_write_hook() {
  local name="$1" rel_path="$2" scope="$3" hooks_dir="$4" settings_file="$5"
  mkdir -p "$hooks_dir"
  cp "$REPO_DIR/$rel_path" "$hooks_dir/$name.sh"
  chmod +x "$hooks_dir/$name.sh"
  printf '  \033[32m✓\033[0m  hook   →  %s/%s.sh\n' "$hooks_dir" "$name"

  # Project hooks use the documented ${CLAUDE_PROJECT_DIR} placeholder rather than
  # a bare relative path, which would otherwise resolve against the working
  # directory. There is no equivalent placeholder for the user's home directory,
  # so global hooks fall back to $HOME.
  local cmd
  if [ "$scope" = "global" ]; then
    cmd="\$HOME/.claude/hooks/$name.sh"
  else
    cmd="\${CLAUDE_PROJECT_DIR}/.claude/hooks/$name.sh"
  fi

  local meta event matcher timeout
  meta=$(parse_hook_meta "$REPO_DIR/$rel_path")
  IFS=$'\t' read -r event matcher timeout <<< "$meta"
  patch_settings_json "$settings_file" "$event" "$matcher" "$cmd" "$timeout"
}
