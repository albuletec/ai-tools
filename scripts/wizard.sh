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

# ─── Shared wizard steps ───────────────────────────────────────────────────────
#
# Both wizards open on the same assistant list, both then ask for a scope, and both
# end on the same confirmation gate. Those three are written once here.

# Parallel arrays: _WIZ_ASSISTANT_SLUGS[i] is the slug behind _WIZ_ASSISTANT_LABELS[i].
# Straight from the registry, so a newly registered assistant appears in both
# wizards without touching either.
_load_assistant_choices() {
  _WIZ_ASSISTANT_SLUGS=()
  _WIZ_ASSISTANT_LABELS=()
  local a
  for a in $AIT_ASSISTANTS; do
    _WIZ_ASSISTANT_SLUGS+=("$a")
    _WIZ_ASSISTANT_LABELS+=("$(assistant_label "$a")")
  done
}

# Offer Global/Local and assign the caller's `scope`. Returns 1 on ESC, leaving
# scope untouched so the caller can step back without clearing it itself.
# Usage: _choose_scope BREADCRUMB
_choose_scope() {
  single_menu "Select scope" "$1" \
    "Global  (applies to all projects)" \
    "Local   (current project only)" || return 1
  case "$MENU_INDEX" in
    0) scope="global" ;;
    1) scope="local"  ;;
  esac
}

# The final gate, shared by both wizards. ENTER means yes, because by this point
# the user has already chosen everything on the screen above. Returns 1 when they
# decline. The cursor is shown for the prompt and hidden again after, since the
# rest of the wizard draws without one.
_confirm() {
  printf '\n  %s──────────────────────────────────────────────────%s\n' "$DIM" "$RESET"
  tput cnorm 2>/dev/null || true
  printf '\n  Proceed? [Y/n]: '
  local ans
  IFS= read -r ans
  tput civis 2>/dev/null || true
  [[ -z "$ans" || "$ans" =~ ^[Yy] ]]
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
_WIZ_ASSISTANT_SLUGS=()
_WIZ_ASSISTANT_LABELS=()
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
  local selected_idx=""

  _load_assistant_choices

  while true; do
    case "$step" in

      # ── Step 1: Assistant ──────────────────────────────────────────────────
      1)
        if single_menu "Select an assistant" "" "${_WIZ_ASSISTANT_LABELS[@]}"; then
          assistant="${_WIZ_ASSISTANT_SLUGS[$MENU_INDEX]}"
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
        if _choose_scope "$bc2"; then
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
          type="${_WIZ_TYPE_INTERNAL[$MENU_INDEX]}"
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
          selected_idx="$MENU_INDICES"
          if [[ -z "$selected_idx" ]]; then
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

        local i
        for i in $selected_idx; do
          printf '    \033[36m·\033[0m  %s\n' "${_WIZ_ITEM_NAMES[$i]}"
        done

        if _confirm; then
          menu_exit
          _wizard_install "$assistant" "$scope" "$type" "$selected_idx" "$project_dir"
          return $?
        else
          selected_idx=""
          step=4
        fi
        ;;
    esac
  done
}

# ─── Install dispatcher ────────────────────────────────────────────────────────

# SELECTED_IDX is a space-separated list of positions into _WIZ_ITEM_NAMES and
# _WIZ_ITEM_PATHS, as multi_menu reported them. Addressing the arrays by index is
# what removes the old name-to-path search, and with it the "could not find path"
# branch that search needed — an index from those arrays always resolves.
# Usage: _wizard_install ASSISTANT SCOPE TYPE SELECTED_IDX PROJECT_DIR
_wizard_install() {
  local assistant="$1" scope="$2" type="$3" selected_idx="$4" project_dir="$5"

  printf '\n'

  local installed=0 refused=0 i name rel_path reasons line

  for i in $selected_idx; do
    name="${_WIZ_ITEM_NAMES[$i]}"
    rel_path="${_WIZ_ITEM_PATHS[$i]}"

    # Final gate. Nothing is written for an item that does not validate, so a
    # malformed item can never land as a silently broken file.
    if ! reasons=$(validate_item "$type" "$name" "$rel_path" "$assistant"); then
      item_fail "$type" "refused ($name)"
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ait_detail "$line"
      done <<< "$reasons"
      refused=$((refused + 1))
      continue
    fi

    if assistant_install "$assistant" "$name" "$type" "$rel_path" "$scope" "$project_dir"; then
      installed=$((installed + 1))
    else
      refused=$((refused + 1))
    fi
  done

  printf '\n'
  if [[ "$refused" -gt 0 ]]; then
    ait_note "$installed installed, $refused refused. Fix the reasons above and re-run."
    printf '\n'
    return 1
  fi

  ait_ok "$installed installed. Restart $(assistant_label "$assistant") to pick up the changes."
  printf '\n'
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
    ait_note "$written written, $skipped left alone, $failed failed."
    printf '\n'
    return 1
  fi
  ait_ok "$written written, $skipped left alone. Fill in the {curly} placeholders."
  printf '\n'
  return 0
}

run_init_wizard() {
  local project_dir
  project_dir="$(pwd)"

  menu_enter
  trap 'menu_exit' EXIT INT TERM

  local step=1
  local selected="" scope="" targets=""

  _load_assistant_choices

  while true; do
    case "$step" in

      # ── Step 1: Assistants ─────────────────────────────────────────────────
      1)
        # _MENU_DISABLED is a global the install flow also writes, and nothing
        # here can fail validation, so it is cleared before the menu draws.
        _MENU_DISABLED=""
        if multi_menu "Select assistants to initialise" "" "${_WIZ_ASSISTANT_LABELS[@]}"; then
          selected=""
          local i
          for i in $MENU_INDICES; do
            selected+="${_WIZ_ASSISTANT_SLUGS[$i]}"$'\n'
          done
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
        if _choose_scope "$bc2"; then
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

        if _confirm; then
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
