#!/usr/bin/env bash
# Claude Code provider.
#
# Agents → .claude/agents/<name>.md
# Skills → .claude/skills/<name>/SKILL.md
# Hooks  → .claude/hooks/<name>.sh, wired into settings.json
#
# The providers: block is stripped on install so Claude Code never sees
# another provider's configuration.
#
# Requires: REPO_DIR, body.sh, install.sh (parse_hook_meta, patch_settings_json)

claude_code_types() {
  printf 'Agent\nSkill\nHook\n'
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
    hook)  _cc_write_hook  "$name" "$rel_path" "$scope" "$base/hooks" "$settings_file" ;;
    *)     printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type" ;;
  esac
}

# Rewrite an item file for Claude Code: keep Claude's own frontmatter keys,
# drop the providers: block, substitute placeholders in the body.
_cc_render() {
  local src="$1"

  printf -- '---\n'
  get_frontmatter "$src" | awk '
    /^providers:/          { inp=1; next }
    inp && /^[[:space:]]/  { next }
    inp && /^[^[:space:]]/ { inp=0 }
    { print }'
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
    # Copy supporting files verbatim, then render SKILL.md
    local f
    for f in "$src"/*; do
      [ -f "$f" ] || continue
      [ "$(basename "$f")" = "SKILL.md" ] && continue
      cp "$f" "$target_dir/$name/"
    done
    _cc_render "$src/SKILL.md" > "$target_dir/$name/SKILL.md"
  else
    _cc_render "$src" > "$target_dir/$name/SKILL.md"
  fi

  printf '  \033[32m✓\033[0m  skill  →  %s/%s/SKILL.md\n' "$target_dir" "$name"
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
