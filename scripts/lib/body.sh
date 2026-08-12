#!/usr/bin/env bash
# Frontmatter parsing, placeholder substitution, and cross-provider translation.
#
# Item files are written once, for all providers. Two mechanisms keep them DRY:
#
#   1. providers: block — opt-in to non-Claude providers, with optional overrides.
#        providers:
#          copilot:              # presence alone = supported, all defaults
#          cursor:
#            model: gpt-5        # optional per-provider override
#
#   2. {placeholder} tokens in the body, substituted per provider.
#        {instructionsFile} → CLAUDE.md (claude-code) | AGENTS.md (others)
#
# Claude Code ignores the providers: block entirely, so adding it is non-breaking.

# ─── Frontmatter parsing ──────────────────────────────────────────────────────

# Extract the YAML frontmatter (content between the first pair of --- lines).
get_frontmatter() {
  awk 'NR==1 && /^---[[:space:]]*$/{p=1; next} p && /^---[[:space:]]*$/{exit} p' "$1"
}

# Extract the body (everything after the frontmatter's closing ---).
get_body() {
  awk 'f{print} !f && /^---[[:space:]]*$/{c++; if (c==2) f=1}' "$1"
}

# Read a top-level scalar from the frontmatter.
# Usage: fm_get FILE KEY
fm_get() {
  get_frontmatter "$1" | awk -v k="$2" '
    $0 ~ "^"k":" { sub("^"k":[[:space:]]*", ""); print; exit }'
}

# True if the file supports PROVIDER.
# claude-code is always supported; others require an entry under providers:.
# Usage: has_provider FILE PROVIDER
has_provider() {
  local file="$1" provider="$2"
  [[ "$provider" == "claude-code" ]] && return 0
  get_frontmatter "$file" | awk -v p="$provider" '
    /^providers:/          { inp=1; next }
    inp && /^[^[:space:]]/ { inp=0 }
    inp && $0 ~ "^[[:space:]]+"p":" { found=1; exit }
    END { exit !found }'
}

# Read providers.PROVIDER.KEY, if set. Prints nothing when absent.
# Usage: provider_config FILE PROVIDER KEY
provider_config() {
  local file="$1" provider="$2" key="$3"
  get_frontmatter "$file" | awk -v p="$provider" -v k="$key" '
    /^providers:/                     { inp=1; next }
    inp && /^[^[:space:]]/            { inp=0; intgt=0 }
    inp && $0 ~ "^[[:space:]]+"p":"   { intgt=1; next }
    intgt && /^[[:space:]]{2}[^[:space:]]/ { intgt=0 }
    intgt && $0 ~ "^[[:space:]]+"k":" {
      sub("^[[:space:]]*"k":[[:space:]]*", ""); print; exit
    }'
}

# ─── Placeholder substitution ─────────────────────────────────────────────────

# The repo-level instructions file each provider reads by convention.
instructions_file_for() {
  case "$1" in
    claude-code) printf 'CLAUDE.md' ;;
    *)           printf 'AGENTS.md' ;;
  esac
}

# Substitute {placeholder} tokens on stdin for the given provider.
substitute_placeholders() {
  local provider="$1"
  sed -e "s|{instructionsFile}|$(instructions_file_for "$provider")|g"
}

# ─── Tool translation ─────────────────────────────────────────────────────────

# Map one Claude Code tool name to its Copilot-family alias.
# Copilot aliases: execute, read, edit, search, agent, web, todo
_translate_tool() {
  case "$1" in
    Bash)                  printf 'execute' ;;
    Read)                  printf 'read'    ;;
    Write|Edit|NotebookEdit) printf 'edit'  ;;
    Grep|Glob)             printf 'search'  ;;
    Task)                  printf 'agent'   ;;
    WebFetch|WebSearch)    printf 'web'     ;;
    TodoWrite)             printf 'todo'    ;;
    *)                     printf ''        ;;
  esac
}

# Translate a Claude Code tools list into a deduplicated Copilot tools list.
# Input:  "[Bash, Read, Write]"  → Output: "execute, read, edit"
translate_tools() {
  local raw="$1"
  raw="${raw#[}"; raw="${raw%]}"

  local out="" tool mapped
  local IFS=','
  for tool in $raw; do
    tool="${tool// /}"
    [[ -z "$tool" ]] && continue
    mapped=$(_translate_tool "$tool")
    [[ -z "$mapped" ]] && continue
    # Deduplicate — Write and Edit both map to 'edit'
    case ",$out," in
      *",$mapped,"*) continue ;;
    esac
    [[ -n "$out" ]] && out+=","
    out+="$mapped"
  done
  printf '%s' "${out//,/, }"
}
