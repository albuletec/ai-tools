#!/usr/bin/env bash
# Assistant registry — the single list of supported assistants.
#
# Adding an assistant is two changes: write scripts/lib/assistants/<name>.sh
# exposing <name>_types(), <name>_install() and optionally <name>_label(), then
# add its slug to AIT_ASSISTANTS below. The wizard, `ait list` and `ait validate`
# all read this list, so there is nowhere else to remember.
#
# Slugs map to function prefixes by replacing hyphens with underscores:
# claude-code → claude_code_types / claude_code_install.

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

# True when the assistant supports an internal type name (agent|skill|hook).
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
    printf '  \033[33m!\033[0m  no installer for assistant: %s\n' "$assistant"
    return 1
  fi
  "$fn" "$@"
}

# True when the slug is a registered assistant.
is_known_assistant() {
  local candidate="$1" a
  for a in $AIT_ASSISTANTS; do
    [ "$a" = "$candidate" ] && return 0
  done
  return 1
}
