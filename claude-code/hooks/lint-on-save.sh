#!/usr/bin/env bash
## ait:event    PostToolUse
## ait:matcher  Write|Edit
## ait:timeout  60
set -u

# PostToolUse hook for Write|Edit. Lints the single file that was just written, when the
# repository has a lint:changed script and yarn is resolvable. Never blocks - always exits 0.

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

raw=$(cat)
if [ -z "$raw" ]; then
  exit 0
fi

file=$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
if [ -z "$file" ]; then
  exit 0
fi

case "$file" in
  *.ts | *.tsx | *.mts | *.cts) ;;
  *) exit 0 ;;
esac

dir=$(dirname "$file")
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
if [ -z "$root" ] || [ ! -d "$root" ]; then
  exit 0
fi

if [ ! -f "$root/package.json" ]; then
  exit 0
fi

if ! jq -e '.scripts["lint:changed"] // empty' "$root/package.json" >/dev/null 2>&1; then
  exit 0
fi

if ! command -v yarn >/dev/null 2>&1; then
  printf 'lint-on-save: yarn not on PATH, skipping\n'
  exit 0
fi

output=$(cd "$root" && yarn lint:changed "$file" 2>&1)
status=$?

if [ "$status" -ne 0 ]; then
  printf 'lint-on-save: yarn lint:changed reported problems in %s\n' "$file"
  printf '%s\n' "$output" | while IFS= read -r line; do
    printf 'lint-on-save: %s\n' "$line"
  done
fi

exit 0
