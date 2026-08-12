#!/usr/bin/env bash
# Frontmatter parsing and placeholder substitution.
#
# Item files are written once, for all assistants. Two mechanisms keep them DRY:
#
#   1. assistants: block — opt-in to non-Claude assistants, with per-assistant
#      configuration.
#        assistants:
#          claude-code:
#            tools: [Bash, Read]  # each assistant names its own tools
#          copilot:
#            tools: [execute, read]
#          cursor:                # presence alone = supported, all defaults
#            model: composer-2
#
#   2. {placeholder} tokens in the body, substituted per assistant.
#        {instructionsFile} → CLAUDE.md (claude-code) | AGENTS.md (others)
#
# Tool names are never mapped between assistants: model and tools live under
# assistants.{name} and are emitted in that assistant's own vocabulary.
#
# Claude Code ignores the assistants: block entirely, so adding it is non-breaking.
#
# Scalars are read as YAML *values*, not as raw lines: folded and literal block
# scalars, quoted scalars, and plain multi-line continuations all collapse to a
# single logical string. Assistants that re-emit frontmatter must pass the result
# through yaml_quote, because a value read from YAML is not itself valid YAML.

# ─── Frontmatter parsing ──────────────────────────────────────────────────────

# Extract the YAML frontmatter (content between the first pair of --- lines).
get_frontmatter() {
  awk 'NR==1 && /^---[[:space:]]*$/{p=1; next} p && /^---[[:space:]]*$/{exit} p' "$1"
}

# Extract the body (everything after the frontmatter's closing ---).
get_body() {
  awk 'f{print} !f && /^---[[:space:]]*$/{c++; if (c==2) f=1}' "$1"
}

# True if the file opens with a frontmatter block that is closed again.
# An item without one would otherwise install with an empty body.
has_frontmatter() {
  awk '
    NR==1 && !/^---[[:space:]]*$/ { exit 1 }
    NR>1  && /^---[[:space:]]*$/  { found=1; exit 0 }
    END { exit !found }
  ' "$1"
}

# Read a top-level scalar from the frontmatter as a single logical line.
#
# Handles, for KEY "description":
#   description: plain text
#   description: "quoted: text"
#   description: >-        (folded block — continuation lines joined with spaces)
#   description: |         (literal block — joined with spaces, since every
#                           consumer of this value wants one line)
#   description: first     (plain continuation — subsequent indented lines
#     second                joined with spaces)
#
# Usage: fm_get FILE KEY
fm_get() {
  get_frontmatter "$1" | awk -v k="$2" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
    }
    # Collecting continuation lines of the key we matched.
    collecting {
      if ($0 ~ /^[[:space:]]*$/) { next }               # blank line inside a block
      if ($0 !~ /^[[:space:]]/)  { exit }               # dedent ends the value
      val = (val == "" ? trim($0) : val " " trim($0))
      next
    }
    $0 ~ "^"k":" {
      rest = $0
      sub("^"k":[[:space:]]*", "", rest)
      rest = trim(rest)
      # Block scalar introducer: >, >-, >+, |, |-, |+ (optional explicit indent)
      if (rest ~ /^[>|][0-9]*[-+]?$/) { collecting = 1; val = ""; next }
      val = rest
      collecting = 1
      next
    }
    END {
      # Unquote a fully quoted scalar, undoing the escapes YAML requires.
      if (val ~ /^".*"$/) {
        val = substr(val, 2, length(val) - 2)
        gsub(/\\"/, "\"", val)
        gsub(/\\\\/, "\\", val)
      } else if (val ~ /^'"'"'.*'"'"'$/) {
        val = substr(val, 2, length(val) - 2)
        gsub(/'"'"''"'"'/, "'"'"'", val)
      }
      print val
    }'
}

# Read a top-level scalar exactly as written, without unquoting or folding.
# Use this when the value is about to be written back into YAML verbatim —
# `argument-hint: "[pr]"` must keep its quotes, `user-invocable: false` must not
# gain any. Returns the first line only, so it is not suitable for descriptions.
# Usage: fm_get_raw FILE KEY
fm_get_raw() {
  get_frontmatter "$1" | awk -v k="$2" '
    $0 ~ "^"k":" { sub("^"k":[[:space:]]*", ""); sub(/[[:space:]]+$/, ""); print; exit }'
}

# Emit a frontmatter line for a key that means the same thing in Claude Code and
# in the target assistant: the assistant-specific override wins, otherwise the
# top-level value carries over so it only has to be written once. Prints nothing
# when neither is set.
# Usage: _shared_opt FILE ASSISTANT KEY
_shared_opt() {
  local src="$1" assistant="$2" key="$3" val
  val=$(assistant_config "$src" "$assistant" "$key")
  [ -z "$val" ] && val=$(fm_get_raw "$src" "$key")
  [ -n "$val" ] && printf '%s: %s\n' "$key" "$val"
  return 0
}

# Read a top-level sequence from the frontmatter, one element per line.
#
# Accepts all three forms Claude Code allows:
#   tools: [Bash, Read]      inline flow sequence
#   tools: Bash, Read        bare comma-separated string
#   tools:                   block sequence
#     - Bash
#     - Read
#
# Usage: fm_get_list FILE KEY
fm_get_list() {
  get_frontmatter "$1" | awk -v k="$2" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
    }
    function emit(s,   n, i, parts) {
      gsub(/^\[/, "", s); gsub(/\]$/, "", s)
      n = split(s, parts, ",")
      for (i = 1; i <= n; i++) {
        item = trim(parts[i])
        gsub(/^["'"'"']|["'"'"']$/, "", item)
        if (item != "") print item
      }
    }
    collecting {
      if ($0 ~ /^[[:space:]]*$/) { next }
      if ($0 !~ /^[[:space:]]/)  { exit }
      line = trim($0)
      if (line ~ /^-[[:space:]]*/) { sub(/^-[[:space:]]*/, "", line); emit(line) }
      next
    }
    $0 ~ "^"k":" {
      rest = $0
      sub("^"k":[[:space:]]*", "", rest)
      rest = trim(rest)
      if (rest == "") { collecting = 1; next }   # block sequence follows
      emit(rest)
      exit
    }'
}

# Quote a value read from YAML so it is safe to write back into YAML.
# Always double-quotes: a plain scalar cannot express a leading indicator
# character, a ": " sequence, or a trailing " #" without quoting.
yaml_quote() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

# True if the file supports ASSISTANT.
# claude-code is always supported; others require an entry under assistants:.
# Usage: has_assistant FILE ASSISTANT
has_assistant() {
  local file="$1" assistant="$2"
  [[ "$assistant" == "claude-code" ]] && return 0
  get_frontmatter "$file" | awk -v a="$assistant" '
    /^assistants:/         { ina=1; next }
    ina && /^[^[:space:]]/ { ina=0 }
    ina && $0 ~ "^[[:space:]]+"a":" { found=1; exit }
    END { exit !found }'
}

# Read assistants.ASSISTANT.KEY, if set. Prints nothing when absent.
# Usage: assistant_config FILE ASSISTANT KEY
assistant_config() {
  local file="$1" assistant="$2" key="$3"
  get_frontmatter "$file" | awk -v a="$assistant" -v k="$key" '
    /^assistants:/                    { ina=1; next }
    ina && /^[^[:space:]]/            { ina=0; intgt=0 }
    ina && $0 ~ "^[[:space:]]+"a":"   { intgt=1; next }
    intgt && /^[[:space:]][[:space:]][^[:space:]]/ { intgt=0 }
    intgt && $0 ~ "^[[:space:]]+"k":" {
      sub("^[[:space:]]*"k":[[:space:]]*", ""); print; exit
    }'
}

# ─── Placeholder substitution ─────────────────────────────────────────────────

# The repo-level instructions file each assistant reads by convention.
# Copilot, Cursor and Windsurf all read AGENTS.md.
instructions_file_for() {
  case "$1" in
    claude-code) printf 'CLAUDE.md' ;;
    *)           printf 'AGENTS.md' ;;
  esac
}

# Substitute {placeholder} tokens on stdin for the given assistant.
substitute_placeholders() {
  local assistant="$1"
  sed -e "s|{instructionsFile}|$(instructions_file_for "$assistant")|g"
}
