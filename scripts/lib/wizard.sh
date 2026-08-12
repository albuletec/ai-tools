#!/usr/bin/env bash
# 4-step installation wizard.
# Steps: Assistant → Scope → Type → Items → Confirm → Install
# Requires: menu.sh, registry.sh, collect.sh, install.sh, validate.sh, assistants/*.sh

# ─── Label helpers ─────────────────────────────────────────────────────────────

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
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Build a breadcrumb string from whatever is set so far.
# Usage: _breadcrumb ASSISTANT SCOPE TYPE
_breadcrumb() {
  local assistant="${1:-}" scope="${2:-}" type="${3:-}"
  local parts=()
  [[ -n "$assistant" ]] && parts+=("$(assistant_label "$assistant")")
  [[ -n "$scope"     ]] && parts+=("$(_scope_label "$scope")")
  [[ -n "$type"      ]] && parts+=("$type")

  local result="" p
  for p in "${parts[@]+"${parts[@]}"}"; do
    [[ -n "$result" ]] && result+=' › '
    result+="$p"
  done
  printf '%s' "$result"
}

# ─── Assistant type lists ──────────────────────────────────────────────────────

# Set _WIZ_TYPE_DISPLAY to display labels and _WIZ_TYPE_INTERNAL to internal names,
# filtered to types that actually have items for this assistant.
_load_types_for_assistant() {
  local assistant="$1"
  _WIZ_TYPE_DISPLAY=()
  _WIZ_TYPE_INTERNAL=()

  local label internal count
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    internal=$(_type_to_internal "$label")
    count=$(collect_items_of_type "$internal" "$assistant" | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      _WIZ_TYPE_DISPLAY+=("$label")
      _WIZ_TYPE_INTERNAL+=("$internal")
    fi
  done < <(assistant_types "$assistant")
}

# ─── Item list loader ──────────────────────────────────────────────────────────

# Populate _WIZ_ITEM_NAMES, _WIZ_ITEM_PATHS, _WIZ_ITEM_LABELS and _MENU_DISABLED.
# An item that fails validation is listed with its reason and cannot be selected,
# so a malformed item is visible rather than silently missing.
_load_items_for_type() {
  local type="$1" assistant="${2:-claude-code}"
  _WIZ_ITEM_NAMES=()
  _WIZ_ITEM_PATHS=()
  _WIZ_ITEM_LABELS=()
  _MENU_DISABLED=""

  local name path reasons first idx=0
  while IFS=$'\t' read -r name path; do
    [[ -z "$name" ]] && continue
    _WIZ_ITEM_NAMES+=("$name")
    _WIZ_ITEM_PATHS+=("$path")
    if reasons=$(validate_item "$type" "$name" "$path" "$assistant"); then
      _WIZ_ITEM_LABELS+=("$name")
    else
      first=$(printf '%s' "$reasons" | head -1)
      _WIZ_ITEM_LABELS+=("$name  —  $first")
      _MENU_DISABLED+="$idx "
    fi
    idx=$((idx + 1))
  done < <(collect_items_of_type "$type" "$assistant")
}

# Map a selected label back to its item name.
_label_to_name() {
  local label="$1" i
  for (( i = 0; i < ${#_WIZ_ITEM_LABELS[@]}; i++ )); do
    if [[ "${_WIZ_ITEM_LABELS[$i]}" == "$label" ]]; then
      printf '%s' "${_WIZ_ITEM_NAMES[$i]}"
      return 0
    fi
  done
  printf '%s' "$label"
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
_WIZ_ITEM_NAMES=()
_WIZ_ITEM_PATHS=()
_WIZ_ITEM_LABELS=()

run_wizard() {
  local project_dir
  project_dir="$(pwd)"

  menu_enter
  trap 'menu_exit' EXIT INT TERM

  local step=1
  local assistant="" scope="" type=""
  local selected_items=""

  # Step 1 options come straight from the registry, so a newly registered
  # assistant appears here without touching the wizard.
  local -a assistant_slugs=() assistant_labels=()
  local a
  for a in $AIT_ASSISTANTS; do
    assistant_slugs+=("$a")
    assistant_labels+=("$(assistant_label "$a")")
  done

  while true; do
    case "$step" in

      # ── Step 1: Assistant ──────────────────────────────────────────────────
      1)
        if single_menu "Select an assistant" "" "${assistant_labels[@]}"; then
          local i
          for (( i = 0; i < ${#assistant_labels[@]}; i++ )); do
            if [[ "${assistant_labels[$i]}" == "$MENU_RESULT" ]]; then
              assistant="${assistant_slugs[$i]}"
              break
            fi
          done
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
        bc2=$(_breadcrumb "$assistant")
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
          assistant=""
          step=1
        fi
        ;;

      # ── Step 3: Type ───────────────────────────────────────────────────────
      3)
        local bc3
        bc3=$(_breadcrumb "$assistant" "$scope")
        _load_types_for_assistant "$assistant"

        if [[ "${#_WIZ_TYPE_DISPLAY[@]}" -eq 0 ]]; then
          _show_notice "$bc3" "No items available for $(assistant_label "$assistant") yet."
          scope=""
          step=2
          continue
        fi

        if single_menu "Select item type" "$bc3" "${_WIZ_TYPE_DISPLAY[@]}"; then
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

      # ── Step 4: Items (multi-select) ───────────────────────────────────────
      4)
        local type_label bc4
        type_label=$(_type_label "$type")
        bc4=$(_breadcrumb "$assistant" "$scope" "$type_label")

        _load_items_for_type "$type" "$assistant"

        if [[ "${#_WIZ_ITEM_NAMES[@]}" -eq 0 ]]; then
          _show_notice "$bc4" "No $type items available yet."
          type=""
          step=3
          continue
        fi

        if multi_menu "Select items to install" "$bc4" "${_WIZ_ITEM_LABELS[@]}"; then
          selected_items=""
          while IFS= read -r label; do
            [[ -z "$label" ]] && continue
            selected_items+="$(_label_to_name "$label")"$'\n'
          done <<< "$MENU_RESULT"
          selected_items="${selected_items%$'\n'}"
          if [[ -z "$selected_items" ]]; then
            continue   # nothing was toggled — stay on this step
          fi
          step=5
        else
          type=""
          step=3
        fi
        ;;

      # ── Step 5: Confirmation ───────────────────────────────────────────────
      5)
        local type_label bc5
        type_label=$(_type_label "$type")
        bc5=$(_breadcrumb "$assistant" "$scope")
        menu_clear
        _draw_header "$bc5"

        printf '  \033[1mReady to install\033[0m\n\n'
        printf '  Assistant  %s\n'   "$(assistant_label "$assistant")"
        printf '  Scope      %s\n'   "$(_scope_label "$scope")"
        printf '  Type       %s\n\n' "$type_label"
        printf '  Items:\n'

        while IFS= read -r item; do
          [[ -z "$item" ]] && continue
          printf '    \033[36m·\033[0m  %s\n' "$item"
        done <<< "$selected_items"

        printf '\n  \033[2m──────────────────────────────────────────────────\033[0m\n'
        tput cnorm 2>/dev/null || true  # show cursor for the prompt
        printf '\n  Proceed? [Y/n]: '

        local ans
        IFS= read -r ans
        tput civis 2>/dev/null || true

        if [[ -z "$ans" || "$ans" =~ ^[Yy] ]]; then
          menu_exit
          _wizard_install "$assistant" "$scope" "$type" "$selected_items" "$project_dir"
          return $?
        else
          selected_items=""
          step=4
        fi
        ;;
    esac
  done
}

# ─── Install dispatcher ────────────────────────────────────────────────────────

_wizard_install() {
  local assistant="$1" scope="$2" type="$3" selected_items="$4" project_dir="$5"

  printf '\n'

  local installed=0 refused=0 item_name rel_path i reasons

  while IFS= read -r item_name; do
    [[ -z "$item_name" ]] && continue

    rel_path=""
    for (( i = 0; i < ${#_WIZ_ITEM_NAMES[@]}; i++ )); do
      if [[ "${_WIZ_ITEM_NAMES[$i]}" == "$item_name" ]]; then
        rel_path="${_WIZ_ITEM_PATHS[$i]}"
        break
      fi
    done

    if [[ -z "$rel_path" ]]; then
      printf '  \033[33m!\033[0m  Could not find path for: %s (skipped)\n' "$item_name"
      refused=$((refused + 1))
      continue
    fi

    # Final gate. Nothing is written for an item that does not validate, so a
    # malformed item can never land as a silently broken file.
    if ! reasons=$(validate_item "$type" "$item_name" "$rel_path" "$assistant"); then
      printf '  \033[31m✗\033[0m  %-6s →  refused (%s)\n' "$type" "$item_name"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf '         %s\n' "$line"
      done <<< "$reasons"
      refused=$((refused + 1))
      continue
    fi

    if assistant_install "$assistant" "$item_name" "$type" "$rel_path" "$scope" "$project_dir"; then
      installed=$((installed + 1))
    else
      refused=$((refused + 1))
    fi
  done <<< "$selected_items"

  printf '\n'
  if [[ "$refused" -gt 0 ]]; then
    printf '  \033[33m!\033[0m  %d installed, %d refused. Fix the reasons above and re-run.\n\n' \
      "$installed" "$refused"
    return 1
  fi

  printf '  \033[32m✓\033[0m  %d installed. Restart %s to pick up the changes.\n\n' \
    "$installed" "$(assistant_label "$assistant")"
  return 0
}
