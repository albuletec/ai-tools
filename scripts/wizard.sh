#!/usr/bin/env bash
# 4-step installation wizard.
# Steps: Assistant → Scope → Type → Items → Confirm → Install
#
# Plus the 3-step init wizard, which writes each assistant's per-project context
# file: Assistant → Scope → Confirm. A context file is one file per project rather
# than a composable list, so it is not an item and does not go through the install
# flow at all.
#
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
    rule)  printf 'Rule'  ;;
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

# ─── Init flow ─────────────────────────────────────────────────────────────────

# True when SLUG appears in a newline-separated list of slugs.
# Usage: _init_selected LIST SLUG
_init_selected() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# Comma-joined labels for a newline-separated list of assistant slugs.
_init_labels() {
  local slug out=""
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    [[ -n "$out" ]] && out+=", "
    out+="$(assistant_label "$slug")"
  done <<< "$1"
  printf '%s' "$out"
}

# Resolve the context files a set of assistants wants at SCOPE, deduplicated by
# target path with the first occurrence winning. Two assistants that both want
# {project}/AGENTS.md produce one line, reported as shared.
#
# Iterates $AIT_ASSISTANTS rather than the caller's order so the output is
# deterministic, and tracks what it has seen in a newline-delimited string matched
# with case, because bash 3.2 has no associative arrays.
#
# ASSISTANTS is newline-separated. Prints SRC_REL<TAB>TARGET_ABS<TAB>OWNER_LABELS.
# Usage: _init_collect ASSISTANTS SCOPE PROJECT_DIR
_init_collect() {
  local assistants="$1" scope="$2" project_dir="$3"
  local a src target all="" seen="" labels slug other_slug other_src other_target

  for a in $AIT_ASSISTANTS; do
    _init_selected "$assistants" "$a" || continue
    while IFS=$'\t' read -r src target; do
      [[ -z "$target" ]] && continue
      all+="$a"$'\t'"$src"$'\t'"$target"$'\n'
    done < <(assistant_init_targets "$a" "$scope" "$project_dir")
  done

  while IFS=$'\t' read -r slug src target; do
    [[ -z "$target" ]] && continue
    case $'\n'"$seen" in
      *$'\n'"$target"$'\n'*) continue ;;
    esac
    seen+="$target"$'\n'

    labels=""
    while IFS=$'\t' read -r other_slug other_src other_target; do
      [[ "$other_target" == "$target" ]] || continue
      [[ -n "$labels" ]] && labels+=", "
      labels+="$(assistant_label "$other_slug")"
    done <<< "$all"

    printf '%s\t%s\t%s\n' "$src" "$target" "$labels"
  done <<< "$all"
}

# Write every collected target. MODE is passed straight to install_init_file, so
# this is callable without a TTY when MODE is skip or overwrite.
# Usage: _init_write TARGET_LINES MODE
_init_write() {
  local lines="$1" mode="$2"
  local src target labels written=0 skipped=0 failed=0

  printf '\n'
  while IFS=$'\t' read -r src target labels; do
    [[ -z "$target" ]] && continue
    if install_init_file "$REPO_DIR/$src" "$target" "$mode"; then
      if [[ "$AIT_INIT_LAST_ACTION" == "written" ]]; then
        written=$((written + 1))
      else
        skipped=$((skipped + 1))
      fi
    else
      failed=$((failed + 1))
    fi
  done <<< "$lines"

  printf '\n'
  if [[ "$failed" -gt 0 ]]; then
    printf '  \033[33m!\033[0m  %d written, %d left alone, %d failed.\n\n' \
      "$written" "$skipped" "$failed"
    return 1
  fi
  printf '  \033[32m✓\033[0m  %d written, %d left alone. Fill in the {curly} placeholders.\n\n' \
    "$written" "$skipped"
  return 0
}

run_init_wizard() {
  local project_dir
  project_dir="$(pwd)"

  menu_enter
  trap 'menu_exit' EXIT INT TERM

  local step=1
  local selected="" scope="" targets=""

  local -a assistant_slugs=() assistant_labels=()
  local a
  for a in $AIT_ASSISTANTS; do
    assistant_slugs+=("$a")
    assistant_labels+=("$(assistant_label "$a")")
  done

  while true; do
    case "$step" in

      # ── Step 1: Assistants ─────────────────────────────────────────────────
      1)
        # _MENU_DISABLED is a global the install flow also writes, and nothing
        # here can fail validation, so it is cleared before the menu draws.
        _MENU_DISABLED=""
        if multi_menu "Select assistants to initialise" "" "${assistant_labels[@]}"; then
          selected=""
          local label i
          while IFS= read -r label; do
            [[ -z "$label" ]] && continue
            for (( i = 0; i < ${#assistant_labels[@]}; i++ )); do
              if [[ "${assistant_labels[$i]}" == "$label" ]]; then
                selected+="${assistant_slugs[$i]}"$'\n'
                break
              fi
            done
          done <<< "$MENU_RESULT"
          selected="${selected%$'\n'}"
          if [[ -z "$selected" ]]; then
            continue   # nothing was toggled — stay on this step
          fi
          scope=""
          step=2
        else
          menu_exit
          return 0  # ESC on first step exits
        fi
        ;;

      # ── Step 2: Scope ──────────────────────────────────────────────────────
      2)
        local bc2
        bc2=$(_init_labels "$selected")
        if single_menu "Select scope" "$bc2" \
            "Global  (applies to all projects)" \
            "Local   (current project only)"; then
          case "$MENU_RESULT" in
            "Global"*) scope="global" ;;
            "Local"*)  scope="local"  ;;
          esac
          step=3
        else
          selected=""
          step=1
        fi
        ;;

      # ── Step 3: Confirmation ───────────────────────────────────────────────
      3)
        local bc3
        bc3="$(_init_labels "$selected") › $(_scope_label "$scope")"
        targets=$(_init_collect "$selected" "$scope" "$project_dir")

        if [[ -z "$targets" ]]; then
          _show_notice "$bc3" \
            "No selected assistant has a context file at $(_scope_label "$scope") scope."
          scope=""
          step=2
          continue
        fi

        menu_clear
        _draw_header "$bc3"

        printf '  \033[1mReady to write\033[0m\n\n'
        local src target labels
        while IFS=$'\t' read -r src target labels; do
          [[ -z "$target" ]] && continue
          printf '    \033[36m·\033[0m  %s\n' "$target"
          printf '       \033[2m%s\033[0m\n' "$labels"
        done <<< "$targets"

        local slug note
        while IFS= read -r slug; do
          [[ -z "$slug" ]] && continue
          note=$(assistant_init_note "$slug")
          [[ -n "$note" ]] && printf '\n  \033[2m%s\033[0m\n' "$note"
        done <<< "$selected"

        printf '\n  \033[2m──────────────────────────────────────────────────\033[0m\n'
        tput cnorm 2>/dev/null || true  # show cursor for the prompt
        printf '\n  Proceed? [Y/n]: '

        local ans
        IFS= read -r ans
        tput civis 2>/dev/null || true

        if [[ -z "$ans" || "$ans" =~ ^[Yy] ]]; then
          # Leave the alternate screen before writing, so the per-file overwrite
          # prompts appear on the normal screen and survive the wizard exiting.
          menu_exit
          _init_write "$targets" ask
          return $?
        else
          scope=""
          step=2
        fi
        ;;
    esac
  done
}
