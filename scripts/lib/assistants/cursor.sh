#!/usr/bin/env bash
# Cursor assistant.
#
# Agents → <dir>/agents/<name>.md
# Skills → <dir>/skills/<name>/SKILL.md
# Hooks  → unsupported here. Cursor does have a hooks system (.cursor/hooks.json)
#          but it is configured differently from Claude Code's settings.json, so
#          hooks stay Claude Code-only until that is modelled properly.
#
# Cursor also reads .claude/agents/ and .claude/skills/ for compatibility, with
# .cursor/ taking precedence. Installing for Cursor gets native paths rather than
# relying on that fallback.
#   https://cursor.com/docs/subagents
#   https://cursor.com/docs/skills
#
# Subagent frontmatter is name, description, model, readonly, is_background.
# There is no tools key: a Cursor subagent inherits every tool from its parent,
# including MCP tools. The only way to narrow it is `readonly: true`, so a tools
# list that grants neither write access nor a shell/delegation escape renders as
# readonly. Anything with Bash, Task or an unrecognised tool is not marked
# readonly, because it could write through that route.
#
# Requires: REPO_DIR, body.sh, collect.sh (item_source_file), install.sh

cursor_label() { printf 'Cursor'; }

cursor_types() {
  printf 'Agent\nSkill\n'
}

_cursor_dir() {
  local type="$1" scope="$2" project_dir="$3"
  local base
  if [ "$scope" = "local" ]; then
    base="$project_dir/.cursor"
  else
    base="${AIT_CURSOR_USER_DIR:-$HOME/.cursor}"
  fi
  case "$type" in
    agent) printf '%s/agents' "$base" ;;
    skill) printf '%s/skills' "$base" ;;
  esac
}

# Install a single item.
# Usage: cursor_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
cursor_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  case "$type" in
    agent) _cursor_write_agent "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _cursor_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    hook)
      printf '  \033[33m!\033[0m  hook   →  skipped (%s): Cursor hooks are not modelled yet\n' "$name"
      return 1
      ;;
    *)
      printf '  \033[33m!\033[0m  Unknown type: %s\n' "$type"
      return 1
      ;;
  esac
}

_cursor_opt() {
  local src="$1" key="$2" val
  val=$(assistant_config "$src" cursor "$key")
  if [ -n "$val" ]; then
    printf '%s: %s\n' "$key" "$val"
  fi
  return 0
}

_cursor_write_agent() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_cursor_dir agent "$scope" "$project_dir")
  target="$target_dir/$name.md"

  mkdir -p "$target_dir"

  local description tools readonly_override
  description=$(fm_get "$src" description)
  tools=$(fm_get_list "$src" tools)

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$(yaml_quote "$description")"
    _cursor_opt "$src" model
    readonly_override=$(assistant_config "$src" cursor readonly)
    if [ -n "$readonly_override" ]; then
      printf 'readonly: %s\n' "$readonly_override"
    elif [ -n "$tools" ] && tools_are_readonly "$tools"; then
      printf 'readonly: true\n'
    fi
    _cursor_opt "$src" is_background
    printf -- '---\n'
    get_body "$src" | substitute_placeholders cursor
  } > "$target"

  printf '  \033[32m✓\033[0m  agent  →  %s\n' "$target"
}

# Skill frontmatter per https://cursor.com/docs/skills — name and description are
# both required, and name must match the parent folder name.
_cursor_write_skill() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_cursor_dir skill "$scope" "$project_dir")
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
    _shared_opt "$src" cursor disable-model-invocation
    _shared_opt "$src" cursor paths
    _cursor_opt "$src" metadata
    printf -- '---\n'
    get_body "$src" | substitute_placeholders cursor
  } > "$target/SKILL.md"

  printf '  \033[32m✓\033[0m  skill  →  %s/SKILL.md\n' "$target"
}
