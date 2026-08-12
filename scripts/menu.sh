#!/usr/bin/env bash
# Arrow-key menu engine for the ait installer wizard.
# No external dependencies. Uses the terminal alternate screen buffer.
# Provides: menu_enter, menu_exit, menu_clear, single_menu, multi_menu
# Result of each call is placed in MENU_RESULT.

MENU_RESULT=""

# ─── Terminal control ─────────────────────────────────────────────────────────

menu_enter() {
  tput smcup  2>/dev/null || true  # enter alternate screen buffer
  tput civis  2>/dev/null || true  # hide cursor
  menu_clear
}

menu_exit() {
  tput cnorm  2>/dev/null || true  # show cursor
  tput rmcup  2>/dev/null || true  # restore normal screen buffer
}

menu_clear() {
  printf '\033[H\033[2J'           # move to top-left, clear screen
}

# ─── Keypress reader ──────────────────────────────────────────────────────────

# Read one keypress. Outputs: up / down / enter / space / escape / other
#
# Arrow keys send a 3-byte sequence: ESC [ A/B/C/D.
# After reading the leading ESC, we read the remaining 2 bytes in a single
# call with a 1-second integer timeout (fractional timeouts are bash 4+ only;
# macOS ships bash 3.2 where -t 0.1 silently becomes -t 0, timing out
# instantly and misreading every arrow key as ESC).
read_key() {
  local key rest
  IFS= read -rsn1 key
  case "$key" in
    $'\x1b')
      # Read up to 2 more chars; if they arrive it's an arrow sequence,
      # if they don't (pure ESC press) the 1-second timeout fires.
      if IFS= read -rsn2 -t 1 rest 2>/dev/null; then
        case "$rest" in
          '[A') printf 'up'     ;;
          '[B') printf 'down'   ;;
          '[C') printf 'right'  ;;
          '[D') printf 'left'   ;;
          *)    printf 'escape' ;;
        esac
      else
        printf 'escape'
      fi
      ;;
    '' | $'\n' | $'\r') printf 'enter'  ;;
    ' ')                printf 'space'  ;;
    *)                  printf 'other'  ;;
  esac
}

# ─── Layout helpers ────────────────────────────────────────────────────────────

_draw_header() {
  local breadcrumb="${1:-}"
  printf '\n  \033[1mAI Tools Installer\033[0m\n'
  printf '  \033[2m──────────────────────────────────────────────────\033[0m\n'
  if [[ -n "$breadcrumb" ]]; then
    printf '\n  \033[2m%s\033[0m\n' "$breadcrumb"
  fi
  printf '\n'
}

# ─── Single-select menu ────────────────────────────────────────────────────────

# single_menu TITLE BREADCRUMB ITEM...
# Sets MENU_RESULT to the selected item label.
# Returns 0 on select, 1 on ESC.
single_menu() {
  local title="$1" breadcrumb="$2"
  shift 2
  local -a items=("$@")
  local count="${#items[@]}"
  local current=0

  while true; do
    menu_clear
    _draw_header "$breadcrumb"
    printf '  \033[1m%s\033[0m\n\n' "$title"

    local i
    for (( i = 0; i < count; i++ )); do
      if [[ "$i" -eq "$current" ]]; then
        printf '  \033[1;36m▶\033[0m  \033[1m%s\033[0m\n' "${items[$i]}"
      else
        printf '     %s\n' "${items[$i]}"
      fi
    done

    printf '\n  \033[2m↑↓ navigate  ·  ENTER select  ·  ESC back\033[0m\n'

    local key
    key=$(read_key)
    case "$key" in
      up)
        [[ "$current" -gt 0 ]] && current=$(( current - 1 )) || true
        ;;
      down)
        [[ "$current" -lt $(( count - 1 )) ]] && current=$(( current + 1 )) || true
        ;;
      enter)
        MENU_RESULT="${items[$current]}"
        return 0
        ;;
      escape)
        MENU_RESULT=""
        return 1
        ;;
    esac
  done
}

# ─── Multi-select menu ─────────────────────────────────────────────────────────

# multi_menu TITLE BREADCRUMB ITEM...
# Sets MENU_RESULT to a newline-separated list of selected item labels.
# Returns 0 on confirm, 1 on ESC.
#
# Reads _MENU_DISABLED — a space-separated list of item indices that cannot be
# toggled. Disabled entries are still shown, so an item rejected by validation is
# visible with its reason instead of vanishing from the list.
multi_menu() {
  local title="$1" breadcrumb="$2"
  shift 2
  local -a items=("$@")
  local count="${#items[@]}"
  local current=0
  local -a selected=()
  local disabled=" ${_MENU_DISABLED:-} "

  _is_disabled() {
    case "$disabled" in
      *" $1 "*) return 0 ;;
      *)        return 1 ;;
    esac
  }

  while true; do
    menu_clear
    _draw_header "$breadcrumb"
    printf '  \033[1m%s\033[0m\n\n' "$title"

    local i
    for (( i = 0; i < count; i++ )); do
      # Check if this index is selected
      local is_sel=0
      local j
      for (( j = 0; j < ${#selected[@]}; j++ )); do
        [[ "${selected[$j]}" -eq "$i" ]] && is_sel=1 && break
      done

      if _is_disabled "$i"; then
        if [[ "$i" -eq "$current" ]]; then
          printf '  \033[1;36m▶\033[0m \033[31m✗\033[0m  \033[2m%s\033[0m\n' "${items[$i]}"
        else
          printf '    \033[31m✗\033[0m  \033[2m%s\033[0m\n' "${items[$i]}"
        fi
      elif [[ "$i" -eq "$current" && "$is_sel" -eq 1 ]]; then
        printf '  \033[1;36m▶\033[0m \033[1;32m◉\033[0m  \033[1m%s\033[0m\n' "${items[$i]}"
      elif [[ "$i" -eq "$current" ]]; then
        printf '  \033[1;36m▶\033[0m \033[2m○\033[0m  \033[1m%s\033[0m\n' "${items[$i]}"
      elif [[ "$is_sel" -eq 1 ]]; then
        printf '    \033[32m◉\033[0m  \033[32m%s\033[0m\n' "${items[$i]}"
      else
        printf '    \033[2m○\033[0m  %s\n' "${items[$i]}"
      fi
    done

    if [[ -n "${_MENU_DISABLED:-}" ]]; then
      printf '\n  \033[2m✗ items failed validation and cannot be selected\033[0m\n'
    fi
    printf '\n  \033[2mSPACE toggle  ·  ENTER confirm  ·  ESC back\033[0m\n'

    local key
    key=$(read_key)
    case "$key" in
      up)
        [[ "$current" -gt 0 ]] && current=$(( current - 1 )) || true
        ;;
      down)
        [[ "$current" -lt $(( count - 1 )) ]] && current=$(( current + 1 )) || true
        ;;
      space)
        _is_disabled "$current" && continue
        local already=0
        local -a new_sel=()
        local j
        for (( j = 0; j < ${#selected[@]}; j++ )); do
          if [[ "${selected[$j]}" -eq "$current" ]]; then
            already=1
          else
            new_sel+=("${selected[$j]}")
          fi
        done
        [[ "$already" -eq 0 ]] && new_sel+=("$current")
        selected=("${new_sel[@]+"${new_sel[@]}"}")
        ;;
      enter)
        MENU_RESULT=""
        for (( j = 0; j < ${#selected[@]}; j++ )); do
          MENU_RESULT+="${items[${selected[$j]}]}"$'\n'
        done
        MENU_RESULT="${MENU_RESULT%$'\n'}"
        return 0
        ;;
      escape)
        MENU_RESULT=""
        return 1
        ;;
    esac
  done
}
