#!/usr/bin/env bash
# Cursor assistant.
#
# Agents → <dir>/agents/<name>.md
# Skills → <dir>/skills/<name>/SKILL.md
# Rules  → <dir>/rules/<name>.mdc
# Hooks  → unsupported here. Cursor does have a hooks system (.cursor/hooks.json)
#          but it is configured differently from Claude Code's settings.json, so
#          hooks stay Claude Code-only until that is modelled properly.
#
# A rule source file is always .md; the .mdc rename happens here and nowhere
# else, because Cursor is the only reader that uses that extension. Which keys
# are present decides the activation mode, so nothing is synthesised:
#   Always           alwaysApply: true
#   Auto Attached    globs: ["src/**"]
#   Agent Requested  description: "..."
#   Manual           none of them
# Every value comes from assistants.cursor and is re-emitted verbatim, so an
# author whose description contains ": " has to quote it in the source file.
#
# Cursor also reads .claude/agents/ and .claude/skills/ for compatibility, with
# .cursor/ taking precedence. Installing for Cursor gets native paths rather than
# relying on that fallback.
#   https://cursor.com/docs/subagents
#   https://cursor.com/docs/skills
#
# Subagent frontmatter is name, description, model, readonly, is_background.
# There is no tools key: a Cursor subagent inherits every tool from its parent,
# including MCP tools. The only way to narrow it is `readonly: true`, which is
# declared per item as assistants.cursor.readonly rather than inferred from a
# tool list — an agent holding a shell was never really read-only anyway.
#
# Requires: REPO_DIR, body.sh, collect.sh (item_source_file), install.sh

cursor_label() { printf 'Cursor'; }

cursor_types() {
  printf 'Agent\nSkill\nRule\n'
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
    rule)  printf '%s/rules'  "$base" ;;
  esac
}

# The per-project context file. AGENTS.md is a repository file by definition, and
# Cursor's global equivalent is User Rules, which live in the settings UI rather
# than on disk, so global scope emits nothing.
# Usage: cursor_init_targets SCOPE PROJECT_DIR
cursor_init_targets() {
  local scope="$1" project_dir="$2"
  [ "$scope" = "local" ] || return 0
  printf 'cursor/init/AGENTS.md\t%s/AGENTS.md\n' "$project_dir"
}

cursor_init_note() {
  printf '.cursorrules is legacy and is not written — AGENTS.md is the file Cursor reads.'
}

# Install a single item.
# Usage: cursor_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
cursor_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"

  case "$type" in
    agent) _cursor_write_agent "$name" "$rel_path" "$scope" "$project_dir" ;;
    skill) _cursor_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    rule)  _cursor_write_rule  "$name" "$rel_path" "$scope" "$project_dir" ;;
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

  local description
  description=$(fm_get "$src" description)

  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$(yaml_quote "$description")"
    _cursor_opt "$src" model
    _cursor_opt "$src" readonly
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

# A .mdc rule is identified by its filename, so no name key is emitted. The
# documented keys are description, globs and alwaysApply, and only the ones the
# item declares under assistants.cursor are written: an absent alwaysApply
# already means false, and synthesising `alwaysApply: false` would make a Manual
# rule indistinguishable from an Auto Attached one in review.
_cursor_write_rule() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_cursor_dir rule "$scope" "$project_dir")
  target="$target_dir/$name.mdc"

  mkdir -p "$target_dir"

  {
    printf -- '---\n'
    # regression: description comes only from assistants.cursor.description, and
    # deliberately does not fall back to the top-level one the way every other
    # shared key does. On Cursor the mere presence of a description selects Agent
    # Requested activation, so a carry-over would silently change the activation
    # mode of every rule that has a top-level description — which is all of them.
    _cursor_opt "$src" description
    _cursor_opt "$src" globs
    _cursor_opt "$src" alwaysApply
    printf -- '---\n'
    get_body "$src" | substitute_placeholders cursor
  } > "$target"

  printf '  \033[32m✓\033[0m  rule   →  %s\n' "$target"
}
