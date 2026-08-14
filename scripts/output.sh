#!/usr/bin/env bash
# Terminal output: colours and the status-line vocabulary every other script uses.
#
# Sourced first, before any script that prints. Two families:
#
#   Top level    die, info, success, warn, header, dim — column 0, for the CLI's
#                own narration ("Syncing ai-tools repo...").
#   Indented     ait_ok, ait_note, ait_fail, ait_detail, ait_faint and the
#                item_* trio — two spaces in, for per-item install results that
#                sit underneath a heading.
#
# Colour is resolved once, here, against stdout. Before this file existed each
# script hardcoded \033[ escapes, so `ait validate | tee log` wrote clean text for
# the heading and raw escape codes for the result line directly below it.
#
# The ait_ prefix is not decoration: tests/run.sh defines its own ok() and bad()
# for the harness, and a bare ok() here would be shadowed by it — or worse, would
# shadow it and silently count installer output as passing assertions.
#
# The menu engine keeps its inline escapes. It draws into the alternate screen
# buffer, which only exists on a terminal, so there is nothing to degrade to.

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BOLD=$'\033[1m';    DIM=$'\033[2m'; RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# ─── Top-level lines ──────────────────────────────────────────────────────────

die()     { printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
info()    { printf '%s→%s  %s\n'     "$CYAN" "$RESET" "$*"; }
success() { printf '%s✓%s  %s\n'     "$GREEN" "$RESET" "$*"; }
warn()    { printf '%s!%s  %s\n'     "$YELLOW" "$RESET" "$*"; }
header()  { printf '\n%s%s%s\n'      "$BOLD" "$*" "$RESET"; }
dim()     { printf '%s%s%s\n'        "$DIM" "$*" "$RESET"; }

# ─── Indented status lines ────────────────────────────────────────────────────

ait_ok()     { printf '  %s✓%s  %s\n' "$GREEN"  "$RESET" "$*"; }
ait_note()   { printf '  %s!%s  %s\n' "$YELLOW" "$RESET" "$*"; }
ait_fail()   { printf '  %s✗%s  %s\n' "$RED"    "$RESET" "$*"; }
ait_faint()  { printf '  %s%s%s\n'    "$DIM" "$*" "$RESET"; }

# A continuation line under an ait_* line — a validation reason, or the second
# half of a two-line warning. Indented past the icon so the block reads as one.
ait_detail() { printf '       %s\n' "$*"; }

# ─── Per-item results ─────────────────────────────────────────────────────────
#
# TYPE is padded to six columns so the arrows line up down the page whether the
# type is "agent" or "rule".

# Usage: item_ok TYPE TARGET
item_ok()   { printf '  %s✓%s  %-6s →  %s\n' "$GREEN" "$RESET" "$1" "$2"; }

# An item the assistant cannot represent. Names the item and says why, because
# "skipped" on its own reads as a bug in ait rather than a deliberate limit.
# Usage: item_skip TYPE NAME REASON
item_skip() { printf '  %s!%s  %-6s →  skipped (%s): %s\n' "$YELLOW" "$RESET" "$1" "$2" "$3"; }

# Usage: item_fail TYPE DETAIL
item_fail() { printf '  %s✗%s  %-6s →  %s\n' "$RED" "$RESET" "$1" "$2"; }
