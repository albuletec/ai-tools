#!/usr/bin/env bash
## ait:event    PostToolUse
## ait:matcher  Write|Edit
## ait:timeout  10
set -u

# PostToolUse hook for Write|Edit. Warns about banned terminology on stdout.
# Never blocks - always exits 0.

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

is_markdown=1
case "$file" in
  *.md | *.mdx) is_markdown=0 ;;
esac

rules=$(cat <<'RULES'
0~(^|[^A-Za-z0-9_])TLA([^A-Za-z0-9_]|$)~TLA~use TSA, the canonical service identifier
0~("dc"[[:space:]]*:|(^|[^A-Za-z0-9_])dc[[:space:]]*=|(^|[^A-Za-z0-9_])dc:[[:space:]]|\.dc([^A-Za-z0-9_]|$))~dc~use `zone` as the dimension name
0~(^|[^A-Za-z0-9_])Dockerfile([^A-Za-z0-9_]|$)~Dockerfile~use `Containerfile`
0~docker-compose~docker-compose~use `compose.yaml`
1~docker image~Docker image~use `container image`
1~(^|[^A-Za-z0-9_])squad([^A-Za-z0-9_]|$)~squad~use `team`
RULES
)

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
done <<RULE_INPUT
$rules
RULE_INPUT

if [ "$is_markdown" -eq 0 ]; then
  warn_matches 1 '(^|[^A-Za-z0-9_])provider([^A-Za-z0-9_]|$)' "provider" "use \`supplier\` when referring to a game supplier"
fi

exit 0
