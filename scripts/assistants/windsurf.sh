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
# Requires: REPO_DIR, body.sh, collect.sh (item_source_file), install.sh

windsurf_label() { printf 'Windsurf'; }

windsurf_types() {
  printf 'Skill\nRule\n'
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
    rule)  printf '%s/rules'  "$base" ;;
  esac
}

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

  case "$type" in
    skill) _windsurf_write_skill "$name" "$rel_path" "$scope" "$project_dir" ;;
    rule)  _windsurf_write_rule  "$name" "$rel_path" "$scope" "$project_dir" ;;
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

# Emit an optional frontmatter line when the item sets it for Windsurf.
# The value is written through verbatim: it was authored as YAML in the source.
# Always returns 0 — a missing key is normal, and the caller runs under `set -e`.
_windsurf_opt() {
  local src="$1" key="$2" val
  val=$(assistant_config "$src" windsurf "$key")
  if [ -n "$val" ]; then
    printf '%s: %s\n' "$key" "$val"
  fi
  return 0
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

# trigger is always emitted, because validate.sh refuses a Windsurf rule without
# one. description is always emitted too — unlike on Cursor, where it selects an
# activation mode — because a Windsurf rule is a .md file and is therefore
# inspected by the golden section's whole-tree pass, which requires one.
_windsurf_write_rule() {
  local name="$1" rel_path="$2" scope="$3" project_dir="$4"
  local src target_dir target
  src=$(item_source_file "$rel_path")
  target_dir=$(_windsurf_dir rule "$scope" "$project_dir")
  target="$target_dir/$name.md"

  mkdir -p "$target_dir"

  # The two sources are handled differently on purpose: an override under
  # assistants.windsurf is already YAML as the author wrote it, while a value
  # returned by fm_get has been read *out* of YAML and has to be re-quoted.
  local description
  description=$(assistant_config "$src" windsurf description)
  if [ -z "$description" ]; then
    description=$(yaml_quote "$(fm_get "$src" description)")
  fi

  {
    printf -- '---\n'
    printf 'trigger: %s\n' "$(assistant_config "$src" windsurf trigger)"
    printf 'description: %s\n' "$description"
    _windsurf_opt "$src" globs
    printf -- '---\n'
    get_body "$src" | substitute_placeholders windsurf
  } > "$target"

  printf '  \033[32m✓\033[0m  rule   →  %s\n' "$target"
}
