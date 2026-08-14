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
# Requires: REPO_DIR, body.sh, install.sh (render_item, parse_hook_meta,
# patch_settings_json)

claude_code_label() { printf 'Claude Code'; }

claude_code_types() {
  printf 'Agent\nSkill\nRule\nHook\n'
}

# Claude Code is the only assistant whose global tree mirrors its local one, which
# is also why it is the only one offering a global `ait init` target.
claude_code_local_base()  { printf '%s/.claude' "$1"; }
claude_code_global_base() { printf '%s/.claude' "$HOME"; }

# The per-project context file. $HOME is read here, at call time, rather than
# captured when this file is sourced, so the tests can point it at a fixture tree.
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
  local dir
  dir=$(assistant_dir claude-code "$type" "$scope" "$project_dir") || {
    ait_note "Unknown type: $type"
    return 1
  }

  case "$type" in
    agent) render_item claude-code agent "$name" "$rel_path" \
             "$dir/$name.md" _cc_passthrough_fm ;;
    skill) render_item claude-code skill "$name" "$rel_path" \
             "$dir/$name/SKILL.md" _cc_passthrough_fm ;;
    rule)  render_item claude-code rule "$name" "$rel_path" \
             "$dir/$name.md" _cc_rule_fm ;;
    hook)  _cc_write_hook "$name" "$rel_path" "$scope" "$dir" \
             "$(dirname "$dir")/settings.json" ;;
  esac
}

# Keep the shared frontmatter keys, drop the assistants: block, re-emit model and
# tools from assistants.claude-code. The two extra keys are emitted only when the
# item declares them, so skills — which never do — are unaffected.
_cc_passthrough_fm() {
  local src="$1"

  get_frontmatter "$src" | awk '
    /^assistants:/         { ina=1; next }
    ina && /^[[:space:]]/  { next }
    ina && /^[[:space:]]*$/{ next }
    ina && /^[^[:space:]]/ { ina=0 }
    { print }'
  _assistant_opt "$src" claude-code model
  _assistant_opt "$src" claude-code tools
}

# Rules carry exactly three keys: name, description, and paths when the item
# declares one. paths goes through _shared_opt, so assistants.claude-code.paths
# wins and a top-level paths carries over — the same behaviour skills have.
# Nothing is printed when neither is set, and the rule then always loads.
_cc_rule_fm() {
  fm_name_description "$1" "$2"
  _shared_opt "$1" claude-code paths
}

_cc_write_hook() {
  local name="$1" rel_path="$2" scope="$3" hooks_dir="$4" settings_file="$5"
  mkdir -p "$hooks_dir"
  cp "$REPO_DIR/$rel_path" "$hooks_dir/$name.sh"
  chmod +x "$hooks_dir/$name.sh"
  item_ok hook "$hooks_dir/$name.sh"

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
