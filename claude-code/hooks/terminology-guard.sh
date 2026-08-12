#!/usr/bin/env bash
## ait:event    PostToolUse
## ait:matcher  Write|Edit
## ait:timeout  10
set -u

# PostToolUse hook for Write|Edit. Warns about banned terminology on stdout.
# Never blocks - always exits 0.
#
# Line numbers are relative to the content that was written, not to the whole
# file, because an Edit only carries the replacement text.

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

raw=$(cat)
if [ -z "$raw" ]; then
  exit 0
fi

file=$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
text=$(printf '%s' "$raw" | jq -r '[.tool_input.content?, .tool_input.new_string?] | map(select(type == "string")) | join("\n")' 2>/dev/null) || exit 0

if [ -z "$text" ]; then
  exit 0
fi

if [ -z "$file" ]; then
  file="(unknown)"
fi

# Fields: case-insensitive flag ~ regex ~ label ~ guidance
#
# Every rule below corresponds to one line of the Terminology section of the
# global instructions. Patterns are deliberately anchored so a rule fires on an
# identifier or a quoted value rather than on any prose that mentions the word.
# Emitted from a function rather than captured into a variable: a quoted heredoc
# inside $( ) is scanned for quote balance by bash 3.2, which macOS still ships,
# and these patterns necessarily contain both kinds of quote.
emit_rules() {
  cat <<'RULES'
0~(^|[^A-Za-z0-9_])TLA([^A-Za-z0-9_]|$)~TLA~use TSA, the canonical service identifier
1~(^|[^A-Za-z0-9_])service[ _]?id([^A-Za-z0-9_]|$)~Service ID~use TSA, never Service ID or service_id
1~(^|[^A-Za-z0-9_])app[_-]?id([^A-Za-z0-9_]|$)~app_id~use TSA, never app_id
0~("dc"[[:space:]]*:|(^|[^A-Za-z0-9_])dc[[:space:]]*=|(^|[^A-Za-z0-9_])dc:[[:space:]]|\.dc([^A-Za-z0-9_]|$))~dc~use `zone` as the dimension name
1~(^|[^A-Za-z0-9_])provider([^A-Za-z0-9_]|$)~provider~use `supplier` when referring to a game supplier
1~(^|[^A-Za-z0-9_])squad([^A-Za-z0-9_]|$)~squad~use `team`
0~["'](bf|pp|sbg|bfi)["']~brand short name~use the canonical brand name: betfair, paddypower or skybet
1~(^|[^A-Za-z0-9_])license~license~use the British spelling: `licence`, `licenceModel`
1~the monorepo~the monorepo~name the repository explicitly, e.g. gaming-venus-monorepo
0~(^|[^A-Za-z0-9_])Dockerfile([^A-Za-z0-9_]|$)~Dockerfile~use `Containerfile`
0~docker-compose~docker-compose~use `compose.yaml`
1~docker image~Docker image~use `container image`
0~"[^"]*<[a-z][a-zA-Z0-9_]*>|'[^']*<[a-z][a-zA-Z0-9_]*>~<angle> placeholder~use {curly} placeholders; <angle> is reserved for HTML and XML
0~\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}~{{double}} placeholder~use {curly} placeholders; {{double}} is template-engine syntax
RULES
}

warn_matches() {
  # $1 = case-insensitive flag (0/1), $2 = regex, $3 = term label, $4 = guidance
  local flags="-nE"
  if [ "$1" = "1" ]; then
    flags="-inE"
  fi
  printf '%s\n' "$text" | grep $flags -e "$2" 2>/dev/null | while IFS= read -r hit; do
    printf 'terminology-guard: %s:%s: %s - %s\n' "$file" "${hit%%:*}" "$3" "$4"
  done
}

while IFS='~' read -r ci pattern term guidance; do
  if [ -z "${pattern:-}" ]; then
    continue
  fi
  warn_matches "$ci" "$pattern" "$term" "$guidance"
done < <(emit_rules)

exit 0
