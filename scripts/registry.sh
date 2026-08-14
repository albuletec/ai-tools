#!/usr/bin/env bash
# Assistant registry — the single list of supported assistants.
#
# Adding an assistant is two changes: write scripts/assistants/<name>.sh
# exposing <name>_types(), <name>_install(), <name>_local_base(),
# <name>_global_base() and optionally <name>_label(), then add its slug to
# AIT_ASSISTANTS below. The wizard, `ait list` and `ait validate` all read this
# list, so there is nowhere else to remember.
#
# Slugs map to function prefixes by replacing hyphens with underscores:
# claude-code → claude_code_types / claude_code_install.
#
# Two optional functions cover `ait init`, which writes an assistant's per-project
# context file rather than installing an item:
#
#   <name>_init_targets SCOPE PROJECT_DIR
#     Zero or more SRC_REL<TAB>TARGET_ABS lines, one per file. SRC_REL is
#     repo-relative and the caller resolves it against $REPO_DIR; TARGET_ABS is
#     already absolute. No output means the assistant has no context file at this
#     scope, which is a normal outcome — `ait init` reports it as skipped.
#
#   <name>_init_note
#     One line of context shown on the init confirmation screen.

AIT_ASSISTANTS="claude-code copilot cursor windsurf"

# Function prefix for an assistant slug.
_assistant_fn_prefix() {
  printf '%s' "${1//-/_}"
}

# Human-readable label. Falls back to the slug.
assistant_label() {
  local fn
  fn="$(_assistant_fn_prefix "$1")_label"
  if declare -f "$fn" >/dev/null 2>&1; then
    "$fn"
  else
    printf '%s' "$1"
  fi
}

# Display labels of the item types an assistant supports, one per line.
assistant_types() {
  local fn
  fn="$(_assistant_fn_prefix "$1")_types"
  declare -f "$fn" >/dev/null 2>&1 || return 0
  "$fn"
}

# Context files this assistant writes at SCOPE, as SRC_REL<TAB>TARGET_ABS lines.
# Prints nothing when the assistant declares none, or none at this scope.
# Usage: assistant_init_targets ASSISTANT SCOPE PROJECT_DIR
assistant_init_targets() {
  local assistant="$1"; shift
  local fn
  fn="$(_assistant_fn_prefix "$assistant")_init_targets"
  declare -f "$fn" >/dev/null 2>&1 || return 0
  "$fn" "$@"
}

# A one-line note to show alongside this assistant's init targets. Optional.
assistant_init_note() {
  local fn
  fn="$(_assistant_fn_prefix "$1")_init_note"
  declare -f "$fn" >/dev/null 2>&1 || return 0
  "$fn"
}

# True when the assistant supports an internal type name (agent|skill|rule|hook).
assistant_supports_type() {
  local assistant="$1" type="$2" label
  while IFS= read -r label; do
    [ -z "$label" ] && continue
    [ "$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')" = "$type" ] && return 0
  done < <(assistant_types "$assistant")
  return 1
}

# Install one item for one assistant.
# Usage: assistant_install ASSISTANT NAME TYPE REL_PATH SCOPE PROJECT_DIR
assistant_install() {
  local assistant="$1"; shift
  local fn
  fn="$(_assistant_fn_prefix "$assistant")_install"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    ait_note "no installer for assistant: $assistant"
    return 1
  fi
  "$fn" "$@"
}

# Install directory for one type at one scope, as <base>/<type>s.
#
# Every assistant lays its tree out the same way — a base directory that depends
# only on the scope, then one subdirectory per item type, named as the plural of
# the type. So an assistant declares just the two bases:
#
#   <name>_local_base PROJECT_DIR   e.g. {project}/.cursor
#   <name>_global_base              e.g. ${AIT_CURSOR_USER_DIR:-$HOME/.cursor}
#
# Read $HOME inside those functions rather than capturing it when the file is
# sourced, so the tests can point it at a fixture tree.
#
# Returns non-zero for a type the assistant does not support, rather than printing
# a path it would then write to: an unsupported type is a caller bug, and the old
# per-assistant case statements answered it with an empty string.
# Usage: assistant_dir ASSISTANT TYPE SCOPE PROJECT_DIR
assistant_dir() {
  local assistant="$1" type="$2" scope="$3" project_dir="$4"
  assistant_supports_type "$assistant" "$type" || return 1

  local prefix base
  prefix="$(_assistant_fn_prefix "$assistant")"
  if [ "$scope" = "local" ]; then
    base=$("${prefix}_local_base" "$project_dir")
  else
    base=$("${prefix}_global_base")
  fi
  [ -n "$base" ] || return 1
  printf '%s/%ss' "$base" "$type"
}

# True when the slug is a registered assistant.
is_known_assistant() {
  local candidate="$1" a
  for a in $AIT_ASSISTANTS; do
    [ "$a" = "$candidate" ] && return 0
  done
  return 1
}
