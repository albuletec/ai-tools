#!/usr/bin/env bash
# Shared install utilities: supporting-file copying, settings.json patching and
# hook metadata parsing. Type-specific install logic lives in scripts/assistants/.

# Copy everything in a skill's source directory except SKILL.md, preserving
# subdirectories. Skills bundle reference material in scripts/, references/ and
# assets/, and every assistant that supports skills reads those relative paths,
# so a shallow copy installs a skill whose own links are broken.
# Usage: copy_skill_support_files SRC_DIR DEST_DIR
copy_skill_support_files() {
  local src="$1" dest="$2" entry base
  mkdir -p "$dest"
  for entry in "$src"/* "$src"/.[!.]*; do
    [ -e "$entry" ] || continue
    base=$(basename "$entry")
    [ "$base" = "SKILL.md" ] && continue
    if [ -d "$entry" ]; then
      mkdir -p "$dest/$base"
      cp -R "$entry/." "$dest/$base/"
    else
      cp "$entry" "$dest/$base"
    fi
  done
}

# Read ## ait:key value lines from a hook file header.
# Outputs EVENT<TAB>MATCHER<TAB>TIMEOUT with safe defaults. Values are validated
# separately by validate.sh, which runs before any install writes a file.
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

# Add a hook entry to settings.json, idempotently.
# MATCHER is ignored for events that don't accept one.
# Returns non-zero without printing a success line if the write did not happen.
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
    return 1
  fi

  if ! printf '%s' "$timeout" | grep -qE '^[0-9]+$'; then
    printf '  \033[31m✗\033[0m  not wired: timeout "%s" is not a whole number of seconds\n' "$timeout"
    return 1
  fi

  if [ ! -f "$settings_file" ]; then
    mkdir -p "$(dirname "$settings_file")"
    printf '{}\n' > "$settings_file"
  fi

  if ! jq -e . "$settings_file" >/dev/null 2>&1; then
    printf '  \033[31m✗\033[0m  not wired: %s is not valid JSON\n' "$settings_file"
    return 1
  fi

  # Skip if this exact command is already present under this event.
  local already
  already=$(jq -r --arg event "$event" --arg cmd "$cmd" \
    '[ (.hooks[$event]? // [])[] | (.hooks? // [])[] | select(.command == $cmd) ] | length' \
    "$settings_file" 2>/dev/null || printf '0')
  if [ "${already:-0}" != "0" ]; then
    printf '  \033[2m    already wired: %s\033[0m\n' "$cmd"
    return 0
  fi

  # Non-tool events take no matcher; their bucket is the entry without one.
  if ! event_supports_matcher "$event"; then
    matcher=""
  fi

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/ait-settings.XXXXXX") || return 1
  if ! jq \
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
  ' "$settings_file" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    printf '  \033[31m✗\033[0m  not wired: could not patch %s\n' "$settings_file"
    return 1
  fi

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    printf '  \033[31m✗\033[0m  not wired: refusing to write an empty %s\n' "$settings_file"
    return 1
  fi

  mv "$tmp" "$settings_file" || return 1
  printf '  \033[32m✓\033[0m  wired in %s\n' "$(basename "$settings_file")"
  return 0
}
