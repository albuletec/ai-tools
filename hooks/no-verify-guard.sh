#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Bash
## ait:timeout  5
set -u

# PreToolUse hook for Bash. Blocks (exit 2) any git invocation that bypasses the
# repository's pre-commit and commit-msg hooks. Non-git commands that happen to
# use --no-verify are left alone.

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

raw=$(cat)
if [ -z "$raw" ]; then
  exit 0
fi

cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
if [ -z "$cmd" ]; then
  exit 0
fi

segments=$(printf '%s' "$cmd" | tr ';|&' '\n\n\n')

offender=""
while IFS= read -r seg; do
  if [ -z "${seg:-}" ]; then
    continue
  fi
  if ! printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])git([[:space:]]|$)'; then
    continue
  fi
  if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])--no-verify([[:space:]=]|$)'; then
    offender="$seg"
    break
  fi
  if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])commit([[:space:]]|$)' && printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])-n([[:space:]]|$)'; then
    offender="$seg"
    break
  fi
done <<SEGMENTS
$segments
SEGMENTS

if [ -z "$offender" ]; then
  exit 0
fi

printf 'no-verify-guard: blocked - this git command bypasses the repository hooks:\n  %s\n' "$offender" >&2
printf 'no-verify-guard: husky runs yarn lint and validates the commit message on every commit. The project CLAUDE.md (section Pre-commit) states these must never be bypassed.\n' >&2
printf 'no-verify-guard: instead - fix the lint failure (yarn lint:fix, then yarn lint), or reword the commit message to match the required convention.\n' >&2
printf 'no-verify-guard: if the hooks have stopped firing altogether, re-run yarn prepare rather than skipping them.\n' >&2
exit 2
