#!/usr/bin/env bash
# Claude Code provider — installs items into .claude/ directories.
# Requires: REPO_DIR, parse_hook_meta, patch_settings_json (install.sh)

# Types supported by this provider.
claude_code_types() {
  printf 'Agent\nSkill\nHook\n'
}

# Install a single item.
# Usage: claude_code_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
claude_code_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  local target_base settings_file
  if [ "$scope" = "global" ]; then
    target_base="$HOME/.claude"
    settings_file="$HOME/.claude/settings.json"
  else
    target_base="$project_dir/.claude"
    settings_file="$project_dir/.claude/settings.json"
  fi

  case "$type" in
    agent)   _cc_install_agent "$name" "$rel_path" "$target_base/agents" ;;
    skill)   _cc_install_skill "$name" "$rel_path" "$target_base/skills" ;;
    hook)    _cc_install_hook  "$name" "$rel_path" "$scope" "$target_base/hooks" "$settings_file" ;;
    *)       printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type" ;;
  esac
}

_cc_install_agent() {
  local name="$1" rel_path="$2" target_dir="$3"
  mkdir -p "$target_dir"
  cp "$REPO_DIR/$rel_path" "$target_dir/$name.md"
  printf '  \033[32m✓\033[0m  agent  →  %s/%s.md\n' "$target_dir" "$name"
}

_cc_install_skill() {
  local name="$1" rel_path="$2" target_dir="$3"
  local src="$REPO_DIR/$rel_path"
  mkdir -p "$target_dir"
  if [ -d "$src" ]; then
    [ -d "$target_dir/$name" ] && rm -rf "${target_dir:?}/$name"
    cp -r "$src" "$target_dir/$name"
    printf '  \033[32m✓\033[0m  skill  →  %s/%s/\n' "$target_dir" "$name"
  else
    cp "$src" "$target_dir/$name.md"
    printf '  \033[32m✓\033[0m  skill  →  %s/%s.md\n' "$target_dir" "$name"
  fi
}

_cc_install_hook() {
  local name="$1" rel_path="$2" scope="$3" hooks_dir="$4" settings_file="$5"
  mkdir -p "$hooks_dir"
  cp "$REPO_DIR/$rel_path" "$hooks_dir/$name.sh"
  chmod +x "$hooks_dir/$name.sh"
  printf '  \033[32m✓\033[0m  hook   →  %s/%s.sh\n' "$hooks_dir" "$name"

  local cmd
  if [ "$scope" = "global" ]; then
    cmd="\$HOME/.claude/hooks/$name.sh"
  else
    cmd=".claude/hooks/$name.sh"
  fi

  local meta event matcher timeout
  meta=$(parse_hook_meta "$REPO_DIR/$rel_path")
  IFS=$'\t' read -r event matcher timeout <<< "$meta"
  patch_settings_json "$settings_file" "$event" "$matcher" "$cmd" "$timeout"
}
