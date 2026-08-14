#!/usr/bin/env bash
# ait — AI Tools installer for Claude Code, Copilot, Cursor and Windsurf items.
# Usage: ait [install|init|list|validate|update|help]
set -euo pipefail

# ─── Resolve repo root (follows symlinks) ────────────────────────────────────
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
readonly REPO_DIR="$(cd "$(dirname "$_src")" && pwd)"
readonly SCRIPTS_DIR="$REPO_DIR/scripts"

# ─── Load library modules ─────────────────────────────────────────────────────
# output.sh first: it owns the colour variables and the status-line helpers that
# every module below prints through.
# shellcheck source=scripts/output.sh
source "$SCRIPTS_DIR/output.sh"
# shellcheck source=scripts/body.sh
source "$SCRIPTS_DIR/body.sh"
# shellcheck source=scripts/registry.sh
source "$SCRIPTS_DIR/registry.sh"
# shellcheck source=scripts/collect.sh
source "$SCRIPTS_DIR/collect.sh"
# shellcheck source=scripts/install.sh
source "$SCRIPTS_DIR/install.sh"
# shellcheck source=scripts/validate.sh
source "$SCRIPTS_DIR/validate.sh"
# shellcheck source=scripts/menu.sh
source "$SCRIPTS_DIR/menu.sh"
# shellcheck source=scripts/wizard.sh
source "$SCRIPTS_DIR/wizard.sh"

# Every registered assistant contributes one script, loaded by slug.
for _assistant in $AIT_ASSISTANTS; do
  _assistant_script="$SCRIPTS_DIR/assistants/$_assistant.sh"
  [ -f "$_assistant_script" ] || die "no script for registered assistant '$_assistant' (expected $_assistant_script)"
  # shellcheck source=/dev/null
  source "$_assistant_script"
done
unset _assistant _assistant_script

# ─── Auto-pull ────────────────────────────────────────────────────────────────
auto_pull() {
  printf '%s→%s  Syncing ai-tools repo... ' "$CYAN" "$RESET"
  if git -C "$REPO_DIR" pull --ff-only --quiet 2>/dev/null; then
    printf '%sdone%s\n' "$GREEN" "$RESET"
  else
    printf '%sskipped%s %s(offline or local changes present)%s\n' \
      "$YELLOW" "$RESET" "$DIM" "$RESET"
  fi
}

# ─── Commands ────────────────────────────────────────────────────────────────
cmd_install() {
  auto_pull
  run_wizard
}

# Pulls first, like cmd_install, so a stale template is never written.
cmd_init() {
  auto_pull
  run_init_wizard
}

cmd_list() {
  auto_pull
  header "Available items"
  printf "\n${BOLD}%-8s  %-24s  %s${RESET}\n" "TYPE" "NAME" "ASSISTANTS"
  printf "%s\n" "──────────────────────────────────────────────────────────────────────"

  local type name rel_path
  for type in $AIT_ITEM_TYPES; do
    while IFS=$'\t' read -r name rel_path; do
      [ -z "$name" ] && continue
      printf "%-8s  %-24s  ${DIM}%s${RESET}\n" \
        "$type" "$name" "$(assistants_for_item "$type" "$rel_path")"
    done < <(_all_items_of_type "$type")
  done
  printf "\n"
}

cmd_validate() {
  header "Validating every item for every assistant it opts into"
  printf "\n"
  if validate_repo; then
    printf "\n"
    return 0
  fi
  printf "\n"
  return 1
}

cmd_update() {
  auto_pull
}

cmd_help() {
  cat <<HELP

${BOLD}ait${RESET} — AI Tools installer

${BOLD}USAGE${RESET}
  ait [command]

${BOLD}COMMANDS${RESET}
  install    4-step interactive installer ${DIM}(default)${RESET}
  init       Create the per-project context file for an assistant
  list       List all available items and the assistants that support them
  validate   Lint every item; exits non-zero if any would install badly
  update     Pull latest from repo
  help       Show this help

${BOLD}WIZARD STEPS${RESET}
  1. Assistant  Claude Code | Copilot | Cursor | Windsurf
  2. Scope      Global (home directory) | Local (current project)
  3. Type       Agent | Skill | Rule | Hook ${DIM}(only what the assistant supports)${RESET}
  4. Items      Multi-select with SPACE, confirm with ENTER

  ESC goes back one step.  ESC on step 1 exits.

${BOLD}INIT STEPS${RESET}
  1. Assistant  Multi-select with SPACE, confirm with ENTER
  2. Scope      Global (home directory) | Local (current project)
  3. Confirm    Nothing is overwritten without an explicit y

${BOLD}REQUIREMENTS${RESET}
  jq ${DIM}(optional, brew install jq)${RESET}  auto hook wiring in settings.json

HELP
}

# ─── Entry point ─────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-install}"
  shift || true
  case "$cmd" in
    install)        cmd_install ;;
    init)           cmd_init ;;
    list)           cmd_list ;;
    validate)       cmd_validate ;;
    update)         cmd_update ;;
    help|--help|-h) cmd_help ;;
    *) die "Unknown command: '$cmd'. Run 'ait help' for usage." ;;
  esac
}

main "$@"
