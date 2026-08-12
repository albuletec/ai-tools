#!/usr/bin/env bash
## ait:event    PreToolUse
## ait:matcher  Write|Edit|Bash
## ait:timeout  10
set -u

# PreToolUse hook for Write|Edit|Bash. Blocks (exit 2) when the tool input carries
# something that looks like a credential. Never prints more than the first four
# characters of a match.

excerpt() {
  printf '%s' "${1:0:4}"
}

block() {
  printf 'secret-scrubber: blocked - possible %s at line %s of the tool input (redacted: %s...)\n' "$1" "$2" "$3" >&2
  printf 'secret-scrubber: move the value into an environment variable or a secret manager and reference it from there.\n' >&2
  printf 'secret-scrubber: if it is not a secret, use an obvious placeholder such as {mySecret}, process.env.MY_SECRET, or changeme.\n' >&2
  exit 2
}

raw=$(cat)
if [ -z "$raw" ]; then
  exit 0
fi

payload=""
parsed=""
parse_ok=1
if command -v jq >/dev/null 2>&1; then
  if parsed=$(printf '%s' "$raw" | jq -r '[.tool_input.content?, .tool_input.new_string?, .tool_input.command?] | map(select(type == "string")) | join("\n")' 2>/dev/null); then
    parse_ok=0
  fi
fi

if [ "$parse_ok" -eq 0 ]; then
  payload="$parsed"
else
  printf 'secret-scrubber: could not parse hook input as JSON, scanning raw input instead\n' >&2
  payload="$raw"
fi

if [ -z "$payload" ]; then
  exit 0
fi

rules=$(cat <<'RULES'
OpenAI-style API key~sk-[A-Za-z0-9]{16,}
GitHub personal access token~ghp_[A-Za-z0-9]{20,}
GitHub OAuth, app, or refresh token~(gho_|ghs_|ghu_|ghr_)[A-Za-z0-9]{20,}
Slack token~(xoxb-|xoxp-|xoxa-|xapp-)[0-9][0-9A-Za-z-]{8,}
AWS access key id~AKIA[0-9A-Z]{16}
Google API key~AIza[0-9A-Za-z_-]{35}
GitLab personal access token~glpat-[A-Za-z0-9_-]{20,}
private key header~-----BEGIN [A-Z ]*PRIVATE KEY-----
RULES
)

while IFS='~' read -r class pattern; do
  if [ -z "${pattern:-}" ]; then
    continue
  fi
  hit=$(printf '%s\n' "$payload" | grep -noE -e "$pattern" 2>/dev/null | head -1)
  if [ -n "$hit" ]; then
    block "$class" "${hit%%:*}" "$(excerpt "${hit#*:}")"
  fi
done <<RULE_INPUT
$rules
RULE_INPUT

assign_re='(password|passwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)[[:space:]]*(=>|=|:)[[:space:]]*["'"'"']?[^[:space:]"'"'"'`,;)]{8,}'
exclude_re='^[x*.]+$|^\{[a-zA-Z_]+\}|^\$\{?[A-Za-z_]+\}?|^process\.env\.|^import\.meta\.env\.|^<[a-zA-Z_]+>|^your[_-]?|example|changeme|dummy|redacted|placeholder|todo|^(null|undefined|true|false)$'

assign_hits=$(printf '%s\n' "$payload" | grep -inoE -e "$assign_re" 2>/dev/null)

while IFS= read -r hit; do
  if [ -z "${hit:-}" ]; then
    continue
  fi
  lineno="${hit%%:*}"
  match="${hit#*:}"
  value=$(printf '%s' "$match" | sed -E 's/^[^=:>]*(=>|=|:)[[:space:]]*//' | sed -E 's/^["'"'"']//')
  if [ -z "$value" ]; then
    continue
  fi
  if printf '%s' "$value" | grep -qiE -e "$exclude_re"; then
    continue
  fi
  block "hardcoded credential assignment" "$lineno" "$(excerpt "$value")"
done <<ASSIGN_INPUT
$assign_hits
ASSIGN_INPUT

exit 0
