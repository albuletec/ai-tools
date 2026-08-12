#!/usr/bin/env bash
# Windsurf assistant.
#
# Skills → <dir>/skills/<name>/SKILL.md
# Agents → unsupported. Cascade is the only agent; Windsurf has no subagent
#          definition format, so there is nothing to translate an agent into.
#          Agent is therefore hidden from the wizard when Windsurf is selected,
#          the same way Hook is hidden for Copilot.
# Hooks  → unsupported; no tool-call event system.
#
# Skill frontmatter is name and description, both required, name restricted to
# lowercase letters, numbers and hyphens. Supporting files in the skill folder
# are read relative to SKILL.md.
#   https://docs.devin.ai/desktop/cascade/skills
#
# Windsurf also scans .claude/skills/ and .agents/skills/ for compatibility;
# installing here gets the native locations. Global skills live under the
# Codeium config tree, not under a dotfile in $HOME directly.
#
# Requires: REPO_DIR, body.sh, collect.sh (item_source_file), install.sh

windsurf_label() { printf 'Windsurf'; }

windsurf_types() {
  printf 'Skill\n'
}

_windsurf_dir() {
  local type="$1" scope="$2" project_dir="$3"
  local base
  if [ "$scope" = "local" ]; then
    base="$project_dir/.windsurf"
  else
    base="${AIT_WINDSURF_USER_DIR:-$HOME/.codeium/windsurf}"
  fi
  case "$type" in
    skill) printf '%s/skills' "$base" ;;
  esac
}

# Install a single item.
# Usage: windsurf_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
windsurf_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  case "$type" in
    skill) _windsurf_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    agent)
      printf '  \033[33m!\033[0m  agent  →  skipped (%s): Windsurf has no subagent format\n' "$name"
      return 1
      ;;
    hook)
      printf '  \033[33m!\033[0m  hook   →  skipped (%s): Windsurf has no hook system\n' "$name"
      return 1
      ;;
    *)
      printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type"
      return 1
      ;;
  esac
}

_windsurf_write_skill() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_windsurf_dir skill "$scope" "$project_dir")
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
    printf -- '---\n'
    get_body "$src" | substitute_placeholders windsurf
  } > "$target/SKILL.md"

  printf '  \033[32m✓\033[0m  skill  →  %s/SKILL.md\n' "$target"
}
