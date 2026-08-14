#!/usr/bin/env bash
# Shared install utilities: supporting-file copying, context-file writing,
# settings.json patching and hook metadata parsing. Type-specific install logic
# lives in scripts/assistants/.

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

# Render one item to TARGET and report it.
#
# Every assistant writes the same shape of file — frontmatter between --- lines,
# then the body with its placeholders resolved — and differs only in where the file
# goes and which frontmatter keys belong in it. That variation is the last two
# arguments; everything else is identical, so it lives here once.
#
# FM_FN is the name of a function that emits the frontmatter lines, called with
# SRC and NAME. It must not print the --- delimiters.
#
# A skill authored as a directory has its supporting files copied alongside, since
# every assistant reads scripts/, references/ and assets/ relative to SKILL.md. The
# -d test is what distinguishes those from flat files, so agents and rules — always
# single files — never trigger it.
# Usage: render_item ASSISTANT TYPE NAME REL_PATH TARGET FM_FN
render_item() {
  local assistant="$1" type="$2" name="$3" rel_path="$4" target="$5" fm_fn="$6"
  local src dir
  src=$(item_source_file "$rel_path")
  dir=$(dirname "$target")

  mkdir -p "$dir"
  if [ -d "$REPO_DIR/$rel_path" ]; then
    copy_skill_support_files "$REPO_DIR/$rel_path" "$dir"
  fi

  {
    printf -- '---\n'
    "$fm_fn" "$src" "$name"
    printf -- '---\n'
    get_body "$src" | substitute_placeholders "$assistant"
  } > "$target"

  item_ok "$type" "$target"
}

# Set to "written" or "left-alone" by the last install_init_file call. The caller
# needs to know which happened to report a summary, and it cannot capture stdout:
# in ask mode the overwrite prompt has to reach the terminal.
AIT_INIT_LAST_ACTION=""

# Copy one `ait init` template to its target. MODE is ask | skip | overwrite.
#
# Whole files only — an existing file is replaced with consent or left alone, never
# edited in place and never appended to, because a context file is the user's own
# prose and merging into it would mean guessing where their edits belong.
#
# Leaving an existing file alone is a correct outcome, not a failure, so skip and a
# declined prompt both return 0. Only a missing template is an error.
# Usage: install_init_file SRC_ABS TARGET_ABS MODE
install_init_file() {
  local src="$1" target="$2" mode="$3"
  AIT_INIT_LAST_ACTION="left-alone"

  if [ ! -f "$src" ]; then
    ait_fail "template is missing: $src"
    return 1
  fi

  if [ -e "$target" ]; then
    case "$mode" in
      overwrite) ;;
      skip)
        ait_note "exists, left alone: $target"
        return 0
        ;;
      *)
        local answer=""
        printf '  overwrite %s? [y/N]: ' "$target"
        IFS= read -r answer || answer=""
        case "$answer" in
          y|Y) ;;
          *)
            ait_note "exists, left alone: $target"
            return 0
            ;;
        esac
        ;;
    esac
  fi

  mkdir -p "$(dirname "$target")"
  cp "$src" "$target"
  AIT_INIT_LAST_ACTION="written"
  ait_ok "$target"
  return 0
}

# Read one `## ait:KEY value` header from a hook file, exactly as written. Prints
# nothing when the hook omits it, which is how validate.sh tells "absent" from
# "defaulted": a hook with no event must be refused, not silently wired to
# PreToolUse, so the raw read lives here and the defaulting in parse_hook_meta.
# Usage: hook_meta FILE KEY
hook_meta() {
  grep -m1 "^## ait:$2" "$1" 2>/dev/null | awk '{print $3}'
}

# Outputs EVENT<TAB>MATCHER<TAB>TIMEOUT with safe defaults. Values are validated
# separately by validate.sh, which runs before any install writes a file.
parse_hook_meta() {
  local event matcher timeout
  event=$(hook_meta "$1" event)
  matcher=$(hook_meta "$1" matcher)
  timeout=$(hook_meta "$1" timeout)
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
    ait_note "jq not found — hook installed but not wired into settings.json"
    ait_detail "Install jq (brew install jq) then re-run to wire hooks."
    return 1
  fi

  if ! printf '%s' "$timeout" | grep -qE '^[0-9]+$'; then
    ait_fail "not wired: timeout \"$timeout\" is not a whole number of seconds"
    return 1
  fi

  if [ ! -f "$settings_file" ]; then
    mkdir -p "$(dirname "$settings_file")"
    printf '{}\n' > "$settings_file"
  fi

  if ! jq -e . "$settings_file" >/dev/null 2>&1; then
    ait_fail "not wired: $settings_file is not valid JSON"
    return 1
  fi

  # Skip if this exact command is already present under this event.
  local already
  already=$(jq -r --arg event "$event" --arg cmd "$cmd" \
    '[ (.hooks[$event]? // [])[] | (.hooks? // [])[] | select(.command == $cmd) ] | length' \
    "$settings_file" 2>/dev/null || printf '0')
  if [ "${already:-0}" != "0" ]; then
    ait_faint "    already wired: $cmd"
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
    ait_fail "not wired: could not patch $settings_file"
    return 1
  fi

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    ait_fail "not wired: refusing to write an empty $settings_file"
    return 1
  fi

  mv "$tmp" "$settings_file" || return 1
  ait_ok "wired in $(basename "$settings_file")"
  return 0
}
