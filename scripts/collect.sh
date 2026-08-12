#!/usr/bin/env bash
# Item discovery — scans the repo and emits item records.
# Requires: has_assistant (body.sh), registry.sh. $REPO_DIR must be set by the caller.

# Absolute path to an item's primary markdown file.
# Directory-based skills resolve to their SKILL.md.
item_source_file() {
  local rel_path="$1"
  if [ -d "$REPO_DIR/$rel_path" ]; then
    printf '%s/%s/SKILL.md' "$REPO_DIR" "$rel_path"
  else
    printf '%s/%s' "$REPO_DIR" "$rel_path"
  fi
}

# Emit NAME<TAB>REL_PATH for every item of TYPE, unfiltered.
_all_items_of_type() {
  local type="$1"
  case "$type" in
    agent)
      for f in "$REPO_DIR"/common/agents/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .md)
        printf '%s\tcommon/agents/%s.md\n' "$name" "$name"
      done
      ;;
    skill)
      for f in "$REPO_DIR"/common/skills/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .md)
        printf '%s\tcommon/skills/%s.md\n' "$name" "$name"
      done
      for d in "$REPO_DIR"/common/skills/*/; do
        [ -d "$d" ] || continue
        [ -f "${d}SKILL.md" ] || continue
        name=$(basename "$d")
        printf '%s\tcommon/skills/%s\n' "$name" "$name"
      done
      ;;
    hook)
      for f in "$REPO_DIR"/claude-code/hooks/*.sh; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .sh)
        printf '%s\tclaude-code/hooks/%s.sh\n' "$name" "$name"
      done
      ;;
  esac
}

# Emit NAME<TAB>REL_PATH for items of TYPE that ASSISTANT supports and opts into.
# Usage: collect_items_of_type TYPE [ASSISTANT]
collect_items_of_type() {
  local type="$1" assistant="${2:-claude-code}"

  assistant_supports_type "$assistant" "$type" || return 0

  local name rel_path
  while IFS=$'\t' read -r name rel_path; do
    [ -z "$name" ] && continue
    if has_assistant "$(item_source_file "$rel_path")" "$assistant"; then
      printf '%s\t%s\n' "$name" "$rel_path"
    fi
  done < <(_all_items_of_type "$type")
}

# Assistants that support TYPE and that the item opts into, space-separated.
# Usage: assistants_for_item TYPE REL_PATH
assistants_for_item() {
  local type="$1" rel_path="$2"
  local src out="" a
  src=$(item_source_file "$rel_path")
  for a in $AIT_ASSISTANTS; do
    assistant_supports_type "$a" "$type" || continue
    has_assistant "$src" "$a" || continue
    [ -n "$out" ] && out+=", "
    out+="$a"
  done
  printf '%s' "$out"
}
