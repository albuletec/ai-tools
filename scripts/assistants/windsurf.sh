#!/usr/bin/env bash
# Windsurf assistant.
#
# Skills → <dir>/skills/<name>/SKILL.md
# Rules  → <dir>/rules/<name>.md
# Agents → unsupported. Cascade is the only agent; Windsurf has no subagent
#          definition format, so there is nothing to translate an agent into.
#          Agent is therefore hidden from the wizard when Windsurf is selected,
#          the same way Hook is hidden for Copilot.
# Hooks  → unsupported; no tool-call event system.
#
# Rule frontmatter is trigger, description and globs. trigger is required and
# takes one of five values — always_on, manual, model_decision, glob, agent —
# which is why validate.sh refuses a rule that omits it rather than picking a
# default: a default would install a rule with an activation the author never
# chose. description is required for model_decision and agent, globs for glob.
# The install path is .windsurf/rules/ locally and <user dir>/rules/ globally.
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
# Requires: REPO_DIR, body.sh, install.sh (render_item)

windsurf_label() { printf 'Windsurf'; }

windsurf_types() {
  printf 'Skill\nRule\n'
}

windsurf_local_base()  { printf '%s/.windsurf' "$1"; }
windsurf_global_base() { printf '%s' "${AIT_WINDSURF_USER_DIR:-$HOME/.codeium/windsurf}"; }

# The per-project context file. AGENTS.md is a repository file by definition, and
# Windsurf's global equivalent is a single memories/global_rules.md rather than a
# context file, so global scope emits nothing.
# Usage: windsurf_init_targets SCOPE PROJECT_DIR
windsurf_init_targets() {
  local scope="$1" project_dir="$2"
  [ "$scope" = "local" ] || return 0
  printf 'windsurf/init/AGENTS.md\t%s/AGENTS.md\n' "$project_dir"
}

windsurf_init_note() {
  printf '.windsurfrules is legacy and is not written — AGENTS.md is the file Windsurf reads.'
}

# Install a single item.
# Usage: windsurf_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
windsurf_install() {
  local name="$1" type="$2" rel_path="$3" scope="$4" project_dir="$5"
  local dir

  case "$type" in
    skill|rule) dir=$(assistant_dir windsurf "$type" "$scope" "$project_dir") ;;
    agent)
      item_skip agent "$name" "Windsurf has no subagent format"
      return 1
      ;;
    hook)
      item_skip hook "$name" "Windsurf has no hook system"
      return 1
      ;;
    *)
      ait_note "Unknown type: $type"
      return 1
      ;;
  esac

  case "$type" in
    skill) render_item windsurf skill "$name" "$rel_path" \
             "$dir/$name/SKILL.md" _windsurf_skill_fm ;;
    rule)  render_item windsurf rule "$name" "$rel_path" \
             "$dir/$name.md" _windsurf_rule_fm ;;
  esac
}

_windsurf_skill_fm() {
  fm_name_description "$1" "$2"
}

# trigger is always emitted, because validate.sh refuses a Windsurf rule without
# one. description is always emitted too — unlike on Cursor, where it selects an
# activation mode — because a Windsurf rule is a .md file and is therefore
# inspected by the golden section's whole-tree pass, which requires one.
_windsurf_rule_fm() {
  local src="$1" description

  # The two sources are handled differently on purpose: an override under
  # assistants.windsurf is already YAML as the author wrote it, while a value
  # returned by fm_get has been read *out* of YAML and has to be re-quoted.
  description=$(assistant_config "$src" windsurf description)
  if [ -z "$description" ]; then
    description=$(yaml_quote "$(fm_get "$src" description)")
  fi

  printf 'trigger: %s\n' "$(assistant_config "$src" windsurf trigger)"
  printf 'description: %s\n' "$description"
  _assistant_opt "$src" windsurf globs
}
