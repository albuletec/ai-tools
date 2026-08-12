#!/usr/bin/env bash
# Installs the ait CLI by symlinking ./ait.sh into ~/.local/bin as "ait".
# Run once from the ai-tools repo: ./install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIT_SRC="$REPO_DIR/ait.sh"
INSTALL_DIR="$HOME/.local/bin"

# The source keeps its .sh extension so it looks like what it is next to the other
# scripts, but the symlink deliberately drops it: what lands on your PATH is the
# command you type, and you type `ait`. ait.sh resolves its own location by
# following the symlink chain, so the two names never have to agree.
INSTALL_PATH="$INSTALL_DIR/ait"

# ─── Colours ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

success() { printf "${GREEN}✓${RESET}  %s\n" "$*"; }
warn()    { printf "${YELLOW}!${RESET}  %s\n" "$*"; }
die()     { printf "\033[0;31merror:\033[0m %s\n" "$*" >&2; exit 1; }

# ─── Checks ───────────────────────────────────────────────────────────────────
[ -f "$AIT_SRC" ] || die "ait.sh not found at $AIT_SRC"
command -v git >/dev/null 2>&1 || die "git is required"

printf "\n${BOLD}ait installer${RESET}\n\n"

# ─── Install ──────────────────────────────────────────────────────────────────
chmod +x "$AIT_SRC"
mkdir -p "$INSTALL_DIR"
ln -sf "$AIT_SRC" "$INSTALL_PATH"
success "Installed: $INSTALL_PATH → $AIT_SRC"

# ─── Optional tools ───────────────────────────────────────────────────────────
printf "\n${BOLD}Optional dependencies${RESET}\n\n"
if command -v jq >/dev/null 2>&1; then
  success "jq found — hooks will be auto-wired into settings.json"
else
  warn "jq not found — install it for auto hook wiring: brew install jq"
fi

# ─── PATH check ───────────────────────────────────────────────────────────────
printf "\n"
if echo ":$PATH:" | grep -q ":$INSTALL_DIR:"; then
  success "$INSTALL_DIR is already in your PATH"
else
  warn "$INSTALL_DIR is not in your PATH"
  printf "\n"

  local_shell="$(basename "${SHELL:-bash}")"
  if [ "$local_shell" = "fish" ]; then
    printf "  Run: ${DIM}fish_add_path %s${RESET}\n" "$INSTALL_DIR"
  else
    case "$local_shell" in
      zsh) RC="$HOME/.zshrc" ;;
      *)   RC="$HOME/.bashrc" ;;
    esac
    printf "  Run: ${DIM}echo 'export PATH=\"%s:\$PATH\"' >> %s && source %s${RESET}\n" \
      "$INSTALL_DIR" "$RC" "$RC"
  fi
fi

printf "\n${GREEN}${BOLD}All done!${RESET} Run ${BOLD}ait help${RESET} to get started.\n\n"
