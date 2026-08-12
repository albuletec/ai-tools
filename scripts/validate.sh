#!/usr/bin/env bash
# Item validation. Nothing is written unless the item validates for the target
# assistant, so a malformed item fails loudly at install time instead of landing
# as a silently broken file.
#
# Requires: body.sh, collect.sh ($REPO_DIR must be set by the caller).

# ─── Claude Code hook events ──────────────────────────────────────────────────
#
# Both lists are taken from https://code.claude.com/docs/en/hooks. Only events
# in _AIT_MATCHER_EVENTS may carry a matcher; writing one on any other event
# produces an invalid settings.json entry.

_AIT_HOOK_EVENTS="SessionStart Setup UserPromptSubmit UserPromptExpansion PreToolUse
PermissionRequest PermissionDenied PostToolUse PostToolUseFailure PostToolBatch
Notification MessageDisplay SubagentStart SubagentStop TaskCreated TaskCompleted
Stop StopFailure TeammateIdle InstructionsLoaded ConfigChange CwdChanged
DirectoryAdded FileChanged WorktreeCreate WorktreeRemove PreCompact PostCompact
Elicitation ElicitationResult SessionEnd"

_AIT_MATCHER_EVENTS="PreToolUse PostToolUse PostToolUseFailure PermissionRequest
PermissionDenied SessionStart Setup SessionEnd Notification SubagentStart
SubagentStop PreCompact PostCompact ConfigChange DirectoryAdded FileChanged
InstructionsLoaded UserPromptExpansion Elicitation ElicitationResult"

_in_word_list() {
  local needle="$1" list="$2" word
  for word in $list; do
    [[ "$word" == "$needle" ]] && return 0
  done
  return 1
}

is_known_hook_event()     { _in_word_list "$1" "$_AIT_HOOK_EVENTS"; }
event_supports_matcher()  { _in_word_list "$1" "$_AIT_MATCHER_EVENTS"; }

# ─── Assistant capabilities ───────────────────────────────────────────────────

# True when the assistant re-emits a per-tool list, so an untranslatable tool
# name would silently widen the agent's access rather than narrow it.
_assistant_translates_tools() {
  case "$1" in
    copilot) return 0 ;;
    *)       return 1 ;;
  esac
}

# True when the assistant requires name and description in the emitted file.
_assistant_requires_name() {
  case "$1" in
    claude-code) return 1 ;;
    *)           return 0 ;;
  esac
}

# ─── Validation ───────────────────────────────────────────────────────────────

# Validate one item for one assistant.
# Prints one human-readable reason per problem on stdout; returns non-zero if any.
# Usage: validate_item TYPE NAME REL_PATH ASSISTANT
validate_item() {
  local type="$1" name="$2" rel_path="$3" assistant="$4"
  local src problems=0

  if [ "$type" = "hook" ]; then
    _validate_hook "$name" "$REPO_DIR/$rel_path" || problems=1
    return $problems
  fi

  src=$(item_source_file "$rel_path")

  if [ ! -f "$src" ]; then
    printf 'source file is missing: %s\n' "$src"
    return 1
  fi

  if ! has_frontmatter "$src"; then
    printf 'no closed --- frontmatter block; the body would install empty\n'
    return 1
  fi

  if [ -z "$(get_body "$src" | tr -d '[:space:]')" ]; then
    printf 'body is empty; there would be no instructions to install\n'
    problems=1
  fi

  local description
  description=$(fm_get "$src" description)
  if [ -z "$description" ]; then
    printf 'description is empty (required by every assistant except Claude Code)\n'
    problems=1
  fi

  # The emitted name comes from the file or directory name, so that is what has
  # to be slug-safe. A frontmatter name that disagrees would install two
  # different identities for the same item.
  if _assistant_requires_name "$assistant"; then
    if ! printf '%s' "$name" | grep -qE '^[a-z0-9-]+$'; then
      printf 'name "%s" must be lowercase letters, numbers and hyphens only\n' "$name"
      problems=1
    fi
  fi

  local fm_name
  fm_name=$(fm_get "$src" name)
  if [ -n "$fm_name" ] && [ "$fm_name" != "$name" ]; then
    printf 'frontmatter name "%s" does not match the item name "%s"\n' "$fm_name" "$name"
    problems=1
  fi

  if [ "$type" = "agent" ] && _assistant_translates_tools "$assistant"; then
    local tools unmapped
    tools=$(fm_get_list "$src" tools)
    if [ -n "$tools" ] && [ -z "$(assistant_config "$src" "$assistant" tools)" ]; then
      unmapped=$(unmapped_tools "$tools" | paste -sd ', ' - | sed 's/,$//')
      if [ -n "$unmapped" ]; then
        printf 'no %s alias for: %s — omitting the tools list would grant every tool, so set assistants.%s.tools explicitly\n' \
          "$assistant" "$unmapped" "$assistant"
        problems=1
      fi
    fi
  fi

  return $problems
}

# Validate a hook script's ait: metadata header.
_validate_hook() {
  local name="$1" file="$2" problems=0
  local event matcher timeout

  event=$(grep   -m1 '^## ait:event'   "$file" 2>/dev/null | awk '{print $3}')
  matcher=$(grep -m1 '^## ait:matcher' "$file" 2>/dev/null | awk '{print $3}')
  timeout=$(grep -m1 '^## ait:timeout' "$file" 2>/dev/null | awk '{print $3}')

  if [ -z "$event" ]; then
    printf 'no "## ait:event" header; add one so the hook is wired to a real event\n'
    problems=1
  elif ! is_known_hook_event "$event"; then
    printf 'unknown hook event "%s"; it would be written to settings.json as a bucket that never fires\n' "$event"
    problems=1
  elif [ -n "$matcher" ] && ! event_supports_matcher "$event"; then
    printf 'event "%s" does not accept a matcher, but "## ait:matcher %s" is set\n' "$event" "$matcher"
    problems=1
  fi

  if [ -n "$timeout" ] && ! printf '%s' "$timeout" | grep -qE '^[0-9]+$'; then
    printf 'timeout "%s" is not a whole number of seconds\n' "$timeout"
    problems=1
  fi

  if [ ! -s "$file" ]; then
    printf 'hook script is empty\n'
    problems=1
  fi

  return $problems
}

# Lint every item in the repo for every assistant it opts into.
# Prints a report and returns non-zero if anything failed.
validate_repo() {
  local failures=0 checked=0
  local type name rel_path assistant src reasons

  for type in agent skill hook; do
    while IFS=$'\t' read -r name rel_path; do
      [ -z "$name" ] && continue
      src=$(item_source_file "$rel_path")
      for assistant in $AIT_ASSISTANTS; do
        if [ "$type" = "hook" ] && [ "$assistant" != "claude-code" ]; then continue; fi
        assistant_supports_type "$assistant" "$type" || continue
        has_assistant "$src" "$assistant" || continue
        checked=$((checked + 1))
        if ! reasons=$(validate_item "$type" "$name" "$rel_path" "$assistant"); then
          failures=$((failures + 1))
          printf '  \033[31m✗\033[0m  %-8s %-24s %s\n' "$type" "$name" "$assistant"
          while IFS= read -r line; do
            [ -z "$line" ] && continue
            printf '         %s\n' "$line"
          done <<< "$reasons"
        fi
      done
    done < <(_all_items_of_type "$type")
  done

  if [ "$failures" -eq 0 ]; then
    printf '  \033[32m✓\033[0m  %d checks passed\n' "$checked"
    return 0
  fi
  printf '\n  %d of %d checks failed\n' "$failures" "$checked"
  return 1
}
