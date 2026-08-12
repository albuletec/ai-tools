#!/usr/bin/env bash
# Copilot provider — VS Code / GitHub Copilot items.
# Currently a stub; full support coming soon.

# Types supported by this provider.
copilot_types() {
  printf ''  # no types available yet
}

# Install a single item.
# Usage: copilot_install NAME TYPE REL_PATH SCOPE PROJECT_DIR
copilot_install() {
  local name="$1"
  printf '  \033[33m!\033[0m  Copilot install support is coming soon (skipped: %s)\n' "$name"
}
