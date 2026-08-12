#!/usr/bin/env bash
# 4-step installation wizard.
# Steps: Provider → Scope → Type → Tools → Confirm → Install
# Requires: menu.sh, collect.sh, install.sh, providers/*.sh

# ─── Label helpers ─────────────────────────────────────────────────────────────

_provider_label() {
  case "$1" in
    claude-code) printf 'Claude Code' ;;
    copilot)     printf 'Copilot'     ;;
    *)           printf '%s' "$1"     ;;
  esac
}

_scope_label() {
  case "$1" in
    global) printf 'Global' ;;
    local)  printf 'Local'  ;;
    *)      printf '%s' "$1" ;;
  esac
}

_type_label() {
  case "$1" in
    agent) printf 'Agent' ;;
    skill) printf 'Skill' ;;
    hook)  printf 'Hook'  ;;
    *)     printf '%s' "$1" ;;
  esac
}

_type_to_internal() {
  case "$1" in
    Agent) printf 'agent' ;;
    Skill) printf 'skill' ;;
    Hook)  printf 'hook'  ;;
    *)     printf '%s' "$1" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

# Build a breadcrumb string from whatever is set so far.
# Usage: _breadcrumb PROVIDER SCOPE TYPE
_breadcrumb() {
  local provider="${1:-}" scope="${2:-}" type="${3:-}"
  local parts=()
  [[ -n "$provider" ]] && parts+=("$(_provider_label "$provider")")
  [[ -n "$scope"    ]] && parts+=("$(_scope_label "$scope")")
  [[ -n "$type"     ]] && parts+=("$type")

  local result="" p
  for p in "${parts[@]+"${parts[@]}"}"; do
    [[ -n "$result" ]] && result+=' › '
    result+="$p"
  done
  printf '%s' "$result"
}

# ─── Provider type lists ───────────────────────────────────────────────────────

# Set _WIZ_TYPE_DISPLAY to display labels and _WIZ_TYPE_INTERNAL to internal names.
_load_types_for_provider() {
  local provider="$1"
  _WIZ_TYPE_DISPLAY=()
  _WIZ_TYPE_INTERNAL=()

  local raw_types
  case "$provider" in
    claude-code) raw_types=$(claude_code_types) ;;
    copilot)     raw_types=$(copilot_types)     ;;
    *)           raw_types=""                   ;;
  esac

  [[ -z "$raw_types" ]] && return

  # Filter to types that actually have items in the repo
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    local internal
    internal=$(_type_to_internal "$label")
    local count
    count=$(collect_items_of_type "$internal" | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      _WIZ_TYPE_DISPLAY+=("$label")
      _WIZ_TYPE_INTERNAL+=("$internal")
    fi
  done <<< "$raw_types"
}

# ─── Tool list loader ──────────────────────────────────────────────────────────

# Populate _WIZ_TOOL_NAMES and _WIZ_TOOL_PATHS for a given type.
_load_tools_for_type() {
  local type="$1"
  _WIZ_TOOL_NAMES=()
  _WIZ_TOOL_PATHS=()

  while IFS=$'\t' read -r name path; do
    [[ -z "$name" ]] && continue
    _WIZ_TOOL_NAMES+=("$name")
    _WIZ_TOOL_PATHS+=("$path")
  done < <(collect_items_of_type "$type")
}

# ─── "No items" notice ────────────────────────────────────────────────────────

_show_notice() {
  local breadcrumb="$1" message="$2"
  menu_clear
  _draw_header "$breadcrumb"
  printf '  \033[33m!\033[0m  %s\n' "$message"
  printf '\n  \033[2mPress any key to go back.\033[0m\n'
  read_key > /dev/null || true
}

# ─── Wizard ────────────────────────────────────────────────────────────────────

# Global state (arrays can't be returned from functions in bash 3.2)
_WIZ_TYPE_DISPLAY=()
_WIZ_TYPE_INTERNAL=()
_WIZ_TOOL_NAMES=()
_WIZ_TOOL_PATHS=()

run_wizard() {
  local project_dir
  project_dir="$(pwd)"

  menu_enter
  trap 'menu_exit' EXIT INT TERM

  local step=1
  local provider="" scope="" type=""
  local selected_tools=""

  while true; do
    case "$step" in

      # ── Step 1: Provider ───────────────────────────────────────────────────
      1)
        if single_menu "Select a provider" "" "Claude Code" "Copilot"; then
          case "$MENU_RESULT" in
            "Claude Code") provider="claude-code" ;;
            "Copilot")     provider="copilot"     ;;
          esac
          scope=""; type=""
          step=2
        else
          menu_exit
          return 0  # ESC on first step exits
        fi
        ;;

      # ── Step 2: Scope ──────────────────────────────────────────────────────
      2)
        local bc2
        bc2=$(_breadcrumb "$provider")
        if single_menu "Select scope" "$bc2" \
            "Global  (applies to all projects)" \
            "Local   (current project only)"; then
          case "$MENU_RESULT" in
            "Global"*) scope="global" ;;
            "Local"*)  scope="local"  ;;
          esac
          type=""
          step=3
        else
          provider=""
          step=1
        fi
        ;;

      # ── Step 3: Type ───────────────────────────────────────────────────────
      3)
        local bc3
        bc3=$(_breadcrumb "$provider" "$scope")
        _load_types_for_provider "$provider"

        if [[ "${#_WIZ_TYPE_DISPLAY[@]}" -eq 0 ]]; then
          _show_notice "$bc3" "No items available for $(_provider_label "$provider") yet."
          scope=""
          step=2
          continue
        fi

        if single_menu "Select item type" "$bc3" "${_WIZ_TYPE_DISPLAY[@]}"; then
          # Map display label back to internal type name
          local i
          type=""
          for (( i = 0; i < ${#_WIZ_TYPE_DISPLAY[@]}; i++ )); do
            if [[ "${_WIZ_TYPE_DISPLAY[$i]}" == "$MENU_RESULT" ]]; then
              type="${_WIZ_TYPE_INTERNAL[$i]}"
              break
            fi
          done
          step=4
        else
          scope=""
          step=2
        fi
        ;;

      # ── Step 4: Tools (multi-select) ───────────────────────────────────────
      4)
        local type_label
        type_label=$(_type_label "$type")
        local bc4
        bc4=$(_breadcrumb "$provider" "$scope" "$type_label")

        _load_tools_for_type "$type"

        if [[ "${#_WIZ_TOOL_NAMES[@]}" -eq 0 ]]; then
          _show_notice "$bc4" "No $type items available yet."
          type=""
          step=3
          continue
        fi

        if multi_menu "Select items to install" "$bc4" "${_WIZ_TOOL_NAMES[@]}"; then
          selected_tools="$MENU_RESULT"
          if [[ -z "$selected_tools" ]]; then
            # Nothing was toggled — stay on this step
            continue
          fi
          step=5
        else
          type=""
          step=3
        fi
        ;;

      # ── Step 5: Confirmation ───────────────────────────────────────────────
      5)
        local type_label
        type_label=$(_type_label "$type")
        local bc5
        bc5=$(_breadcrumb "$provider" "$scope")
        menu_clear
        _draw_header "$bc5"

        printf '  \033[1mReady to install\033[0m\n\n'
        printf '  Provider   %s\n'   "$(_provider_label "$provider")"
        printf '  Scope      %s\n'   "$(_scope_label "$scope")"
        printf '  Type       %s\n\n' "$type_label"
        printf '  Items:\n'

        while IFS= read -r tool; do
          [[ -z "$tool" ]] && continue
          printf '    \033[36m·\033[0m  %s\n' "$tool"
        done <<< "$selected_tools"

        printf '\n  \033[2m──────────────────────────────────────────────────\033[0m\n'
        tput cnorm 2>/dev/null || true  # show cursor for the prompt
        printf '\n  Proceed? [Y/n]: '

        local ans
        IFS= read -r ans
        tput civis 2>/dev/null || true

        if [[ -z "$ans" || "$ans" =~ ^[Yy] ]]; then
          menu_exit
          _wizard_install "$provider" "$scope" "$type" "$selected_tools" "$project_dir"
          return 0
        else
          selected_tools=""
          step=4
        fi
        ;;
    esac
  done
}

# ─── Install dispatcher ────────────────────────────────────────────────────────

_wizard_install() {
  local provider="$1" scope="$2" type="$3" selected_tools="$4" project_dir="$5"

  printf '\n'

  local tool_name
  while IFS= read -r tool_name; do
    [[ -z "$tool_name" ]] && continue

    # Look up the rel_path for this tool name
    local rel_path="" i
    for (( i = 0; i < ${#_WIZ_TOOL_NAMES[@]}; i++ )); do
      if [[ "${_WIZ_TOOL_NAMES[$i]}" == "$tool_name" ]]; then
        rel_path="${_WIZ_TOOL_PATHS[$i]}"
        break
      fi
    done

    if [[ -z "$rel_path" ]]; then
      printf '  \033[33m!\033[0m  Could not find path for: %s (skipped)\n' "$tool_name"
      continue
    fi

    case "$provider" in
      claude-code) claude_code_install "$tool_name" "$type" "$rel_path" "$scope" "$project_dir" ;;
      copilot)     copilot_install     "$tool_name" "$type" "$rel_path" "$scope" "$project_dir" ;;
      *)           printf '  \033[33m!\033[0m  Unknown provider: %s\n' "$provider" ;;
    esac
  done <<< "$selected_tools"

  printf '\n  \033[32m✓\033[0m  Done. Restart Claude Code to pick up the changes.\n\n'
}
