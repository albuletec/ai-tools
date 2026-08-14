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
# Requires: REPO_DIR, body.sh, install.sh (render_item)

cursor_label() { printf 'Cursor'; }

cursor_types() {
  printf 'Agent\nSkill\nRule\n'
}

cursor_local_base()  { printf '%s/.cursor' "$1"; }
cursor_global_base() { printf '%s' "${AIT_CURSOR_USER_DIR:-$HOME/.cursor}"; }

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
  local dir

  case "$type" in
    agent|skill|rule) dir=$(assistant_dir cursor "$type" "$scope" "$project_dir") ;;
    hook)
      item_skip hook "$name" "Cursor hooks are not modelled yet"
      return 1
      ;;
    *)
      ait_note "Unknown type: $type"
      return 1
      ;;
  esac

  case "$type" in
    agent) render_item cursor agent "$name" "$rel_path" \
             "$dir/$name.md" _cursor_agent_fm ;;
    skill) render_item cursor skill "$name" "$rel_path" \
             "$dir/$name/SKILL.md" _cursor_skill_fm ;;
    rule)  render_item cursor rule "$name" "$rel_path" \
             "$dir/$name.mdc" _cursor_rule_fm ;;
  esac
}

_cursor_agent_fm() {
  local src="$1" name="$2"
  fm_name_description "$src" "$name"
  _assistant_opt "$src" cursor model
  _assistant_opt "$src" cursor readonly
  _assistant_opt "$src" cursor is_background
}

# Skill frontmatter per https://cursor.com/docs/skills — name and description are
# both required, and name must match the parent folder name.
_cursor_skill_fm() {
  local src="$1" name="$2"
  fm_name_description "$src" "$name"
  _shared_opt "$src" cursor disable-model-invocation
  _shared_opt "$src" cursor paths
  _assistant_opt "$src" cursor metadata
}

# A .mdc rule is identified by its filename, so no name key is emitted. The
# documented keys are description, globs and alwaysApply, and only the ones the
# item declares under assistants.cursor are written: an absent alwaysApply
# already means false, and synthesising `alwaysApply: false` would make a Manual
# rule indistinguishable from an Auto Attached one in review.
_cursor_rule_fm() {
  local src="$1"
  # regression: description comes only from assistants.cursor.description, and
  # deliberately does not fall back to the top-level one the way every other
  # shared key does. On Cursor the mere presence of a description selects Agent
  # Requested activation, so a carry-over would silently change the activation
  # mode of every rule that has a top-level description — which is all of them.
  # This is also why _cursor_rule_fm does not call fm_name_description.
  _assistant_opt "$src" cursor description
  _assistant_opt "$src" cursor globs
  _assistant_opt "$src" cursor alwaysApply
}
