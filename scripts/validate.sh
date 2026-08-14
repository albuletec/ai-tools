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

# ─── Windsurf rule triggers ───────────────────────────────────────────────────
#
# Windsurf owns this vocabulary — it is the only assistant whose rules declare a
# trigger. Taken from https://docs.devin.ai/desktop/cascade/memories.

_AIT_RULE_TRIGGERS="always_on manual model_decision glob agent"

_in_word_list() {
  local needle="$1" list="$2" word
  for word in $list; do
    [[ "$word" == "$needle" ]] && return 0
  done
  return 1
}

is_known_hook_event()     { _in_word_list "$1" "$_AIT_HOOK_EVENTS"; }
event_supports_matcher()  { _in_word_list "$1" "$_AIT_MATCHER_EVENTS"; }
is_known_rule_trigger()   { _in_word_list "$1" "$_AIT_RULE_TRIGGERS"; }

# ─── Assistant capabilities ───────────────────────────────────────────────────

# True when the assistant requires name and description in the emitted file.
_assistant_requires_name() {
  case "$1" in
    claude-code) return 1 ;;
    *)           return 0 ;;
  esac
}

# ─── Frontmatter shape probes ─────────────────────────────────────────────────

# True when some line declares KEY with a value on the same line. Used to catch a
# block sequence, which assistant_config and fm_get_raw both read as empty.
# Usage: _fm_key_has_inline_value SRC KEY
_fm_key_has_inline_value() {
  get_frontmatter "$1" | grep -qE "^[[:space:]]*$2:[[:space:]]*[^[:space:]]"
}

# True when the frontmatter declares KEY at the top level, whatever its value.
_fm_key_declared() {
  get_frontmatter "$1" | grep -qE "^$2:"
}

# True when assistants.ASSISTANT declares KEY, whatever its value — including a
# block sequence, which assistant_config reads as empty. Both go through
# _assistant_block, so the two cannot drift apart on what counts as declared.
# Usage: _assistant_key_declared SRC ASSISTANT KEY
_assistant_key_declared() {
  _assistant_block "$1" "$2" | awk -v k="$3" '
    { i = index($0, "\t"); if (substr($0, 1, i - 1) == k) { found = 1; exit } }
    END { exit !found }'
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

  if [ "$type" = "agent" ] && [ "$assistant" = "claude-code" ]; then
    if _assistant_key_declared "$src" "claude-code" "tools"; then
      if ! _fm_key_has_inline_value "$src" "tools"; then
        printf '"tools" under assistants.claude-code is a block sequence, which reads as empty — the agent would install without tool restrictions; write it inline as tools: [Bash, Read]\n'
        problems=1
      fi
    fi
  fi

  if [ "$type" = "agent" ] && [ "$assistant" = "copilot" ]; then
    # Normalise [] → empty: _copilot_agent_fm strips brackets, so [] and absent
    # both produce no tools key in the installed file, granting every Copilot tool.
    local _raw_tools
    _raw_tools=$(assistant_config "$src" copilot tools | tr -d '[] ')
    if [ -z "$_raw_tools" ]; then
      printf 'no assistants.copilot.tools declared — Copilot reads an absent tools key as every tool enabled, so declare the list inline in Copilot tool names\n'
      problems=1
    fi
  fi

  if [ "$type" = "rule" ]; then
    _validate_rule "$src" "$assistant" || problems=1
  fi

  return $problems
}

# Rule activation checks, applied for one assistant only. The caller has already
# established that the item opts into it, so there is no has_assistant call here.
#
# Claude Code imposes no activation requirement: a rule with no paths is valid and
# always loads. Cursor and Windsurf both have activation keys that decide when the
# rule fires, so a dropped or contradictory one is refused — a rule that installs
# with a wider scope than its author declared is worse than one that fails loudly.
# Usage: _validate_rule SRC ASSISTANT
_validate_rule() {
  local src="$1" assistant="$2" problems=0
  local key

  for key in paths globs; do
    if _assistant_key_declared "$src" "$assistant" "$key" || _fm_key_declared "$src" "$key"; then
      if ! _fm_key_has_inline_value "$src" "$key"; then
        printf '"%s" is written as a block sequence, which is read as an empty value — the rule would install with a wider activation scope than intended; write it inline as %s: [a, b]\n' "$key" "$key"
        problems=1
      fi
    fi
  done

  if [ "$assistant" = "cursor" ]; then
    local always globs
    always=$(assistant_config "$src" cursor alwaysApply)
    globs=$(assistant_config "$src" cursor globs)
    if [ -n "$always" ] && [ "$always" != "true" ] && [ "$always" != "false" ]; then
      printf 'assistants.cursor.alwaysApply is "%s"; it must be true or false\n' "$always"
      problems=1
    fi
    if [ "$always" = "true" ] && [ -n "$globs" ]; then
      printf 'assistants.cursor.alwaysApply is true and globs is also set; alwaysApply takes precedence, so the globs would be silently ignored\n'
      problems=1
    fi
  fi

  if [ "$assistant" = "windsurf" ]; then
    local trigger description globs
    trigger=$(assistant_config "$src" windsurf trigger)
    if [ -z "$trigger" ]; then
      printf 'no assistants.windsurf.trigger declared; Windsurf needs one to know when the rule loads, and defaulting would choose an activation the author never asked for\n'
      problems=1
    elif ! is_known_rule_trigger "$trigger"; then
      printf 'unknown assistants.windsurf.trigger "%s"; it must be one of: %s\n' \
        "$trigger" "$_AIT_RULE_TRIGGERS"
      problems=1
    else
      case "$trigger" in
        model_decision|agent)
          description=$(assistant_config "$src" windsurf description)
          [ -z "$description" ] && description=$(fm_get "$src" description)
          if [ -z "$description" ]; then
            printf 'trigger "%s" needs a description for Windsurf to decide when to load the rule, but neither assistants.windsurf.description nor a top-level description is set\n' "$trigger"
            problems=1
          fi
          ;;
        glob)
          globs=$(assistant_config "$src" windsurf globs)
          if [ -z "$globs" ]; then
            printf 'trigger "glob" needs assistants.windsurf.globs; without a pattern the rule would never fire\n'
            problems=1
          fi
          ;;
      esac
    fi
  fi

  return $problems
}

# Validate a hook script's ait: metadata header.
_validate_hook() {
  local name="$1" file="$2" problems=0
  local event matcher timeout

  event=$(hook_meta "$file" event)
  matcher=$(hook_meta "$file" matcher)
  timeout=$(hook_meta "$file" timeout)

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

  for type in $AIT_ITEM_TYPES; do
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
          ait_fail "$(printf '%-8s %-24s %s' "$type" "$name" "$assistant")"
          while IFS= read -r line; do
            [ -z "$line" ] && continue
            printf '         %s\n' "$line"
          done <<< "$reasons"
        fi
      done
    done < <(_all_items_of_type "$type")
  done

  if [ "$failures" -eq 0 ]; then
    ait_ok "$checked checks passed"
    return 0
  fi
  printf '\n  %d of %d checks failed\n' "$failures" "$checked"
  return 1
}
