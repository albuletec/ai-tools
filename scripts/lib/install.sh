#!/usr/bin/env bash
# Shared install utilities: settings.json patching and hook metadata parsing.
# Type-specific install logic lives in scripts/lib/providers/.

# Read ## ait:key value lines from a hook file header.
# Outputs EVENT<TAB>MATCHER<TAB>TIMEOUT with safe defaults.
parse_hook_meta() {
  local hook_file="$1"
  local event matcher timeout
  event=$(grep   -m1 '^## ait:event'   "$hook_file" 2>/dev/null | awk '{print $3}')
  matcher=$(grep -m1 '^## ait:matcher' "$hook_file" 2>/dev/null | awk '{print $3}')
  timeout=$(grep -m1 '^## ait:timeout' "$hook_file" 2>/dev/null | awk '{print $3}')
  printf '%s\t%s\t%s' \
    "${event:-PreToolUse}" \
    "${matcher:-Bash}" \
    "${timeout:-10}"
}

# True if EVENT is a tool event, i.e. one that accepts a matcher.
# Non-tool events (SessionStart, Stop, UserPromptSubmit, …) must not carry one.
event_supports_matcher() {
  case "$1" in
    PreToolUse|PostToolUse|PostToolUseFailure|PermissionRequest) return 0 ;;
    *) return 1 ;;
  esac
}

# Add a hook entry to settings.json, idempotently.
# MATCHER is ignored for events that don't support one.
# Usage: patch_settings_json FILE EVENT MATCHER CMD TIMEOUT
patch_settings_json() {
  local settings_file="$1"
  local event="$2"
  local matcher="$3"
  local cmd="$4"
  local timeout="$5"

  if ! command -v jq >/dev/null 2>&1; then
    printf '  \033[33m!\033[0m  jq not found — hook installed but not wired into settings.json\n'
    printf '       Install jq (brew install jq) then re-run to wire hooks.\n'
    return
  fi

  if [ ! -f "$settings_file" ]; then
    mkdir -p "$(dirname "$settings_file")"
    echo '{}' > "$settings_file"
  fi

  # Skip if this exact command is already present
  local already
  already=$(jq --arg event "$event" --arg cmd "$cmd" \
    'try (.hooks[$event][]?.hooks[]? | select(.command == $cmd)) catch null' \
    "$settings_file" 2>/dev/null || true)
  if [ -n "$already" ]; then
    printf '  \033[2m    already wired: %s\033[0m\n' "$cmd"
    return
  fi

  # Non-tool events take no matcher; their bucket is the entry without one.
  if ! event_supports_matcher "$event"; then
    matcher=""
  fi

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/ait-settings.XXXXXX")
  jq \
    --arg event "$event" \
    --arg matcher "$matcher" \
    --arg cmd "$cmd" \
    --argjson timeout "$timeout" '
    def entry: {type:"command", command:$cmd, timeout:$timeout};

    .hooks //= {} |
    .hooks[$event] //= [] |
    if $matcher == "" then
      ((.hooks[$event] | map(has("matcher") | not) | index(true)) // null) as $idx |
      if $idx != null then
        .hooks[$event][$idx].hooks += [entry]
      else
        .hooks[$event] += [{hooks: [entry]}]
      end
    else
      ((.hooks[$event] | map(.matcher? == $matcher) | index(true)) // null) as $idx |
      if $idx != null then
        .hooks[$event][$idx].hooks += [entry]
      else
        .hooks[$event] += [{matcher: $matcher, hooks: [entry]}]
      end
    end
  ' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"

  printf '  \033[32m✓\033[0m  wired in %s\n' "$(basename "$settings_file")"
}
