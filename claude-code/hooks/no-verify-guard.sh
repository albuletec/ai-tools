#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Bash
## ait:timeout  5
set -u

# PreToolUse hook for Bash. Blocks (exit 2) any git invocation that bypasses the
# repository's pre-commit and commit-msg hooks. Non-git commands that happen to
# use --no-verify are left alone, and so is a commit message that merely mentions
# the flag.
#
# Three bypass routes are covered: the --no-verify / -n flags, pointing git at an
# empty hooks directory with -c core.hooksPath, and the environment switches the
# common hook managers respect.

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
reason=""
while IFS= read -r seg; do
  if [ -z "${seg:-}" ]; then
    continue
  fi

  # A hook manager switch counts even before the word git appears, because it is
  # set as a leading environment assignment.
  if printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])(HUSKY|HUSKY_SKIP_HOOKS|HUSKY_SKIP_INSTALL|PRE_COMMIT_ALLOW_NO_CONFIG|SKIP_SIMPLE_GIT_HOOKS|LEFTHOOK)=' \
     && printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])git([[:space:]]|$)'; then
    offender="$seg"
    reason="it disables the hook manager through the environment"
    break
  fi

  if ! printf '%s' "$seg" | grep -qE -e '(^|[[:space:]])git([[:space:]]|$)'; then
    continue
  fi

  if printf '%s' "$seg" | grep -qE -e 'core\.hooksPath[[:space:]]*=' ; then
    offender="$seg"
    reason="it repoints core.hooksPath so the repository's hooks are never found"
    break
  fi

  # Strip a quoted commit message before looking for the flags, so documenting
  # --no-verify in a message is not mistaken for using it.
  stripped=$(printf '%s' "$seg" | sed -e 's/"[^"]*"/""/g' -e "s/'[^']*'/''/g")

  if printf '%s' "$stripped" | grep -qE -e '(^|[[:space:]])--no-verify([[:space:]=]|$)'; then
    offender="$seg"
    reason="it passes --no-verify"
    break
  fi

  if printf '%s' "$stripped" | grep -qE -e '(^|[[:space:]])commit([[:space:]]|$)' \
     && printf '%s' "$stripped" | grep -qE -e '(^|[[:space:]])-[a-zA-Z]*n([[:space:]]|$)'; then
    offender="$seg"
    reason="it passes -n, the short form of --no-verify"
    break
  fi
done <<SEGMENTS
$segments
SEGMENTS

if [ -z "$offender" ]; then
  exit 0
fi

printf 'no-verify-guard: blocked - this git command bypasses the repository hooks because %s:\n  %s\n' "$reason" "$offender" >&2
printf 'no-verify-guard: those hooks are what enforce the lint and commit-message rules the project has agreed on, so skipping them pushes the failure onto CI or onto a reviewer.\n' >&2
printf 'no-verify-guard: instead - run the checks and fix what they report, or reword the commit message to match the required convention.\n' >&2
printf 'no-verify-guard: if the hooks have stopped firing altogether, reinstall them (for example yarn prepare, npm run prepare, or pre-commit install) rather than skipping them.\n' >&2
printf 'no-verify-guard: if this really is what you want, run it yourself in a terminal - it is being blocked so the decision is yours, not mine.\n' >&2
exit 2
