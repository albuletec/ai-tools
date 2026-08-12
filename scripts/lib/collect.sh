#!/usr/bin/env bash
# Item discovery — scans the repo and emits item records.
# $REPO_DIR must be set by the caller.

# Output NAME<TAB>REL_PATH lines for a given type.
collect_items_of_type() {
  local type="$1"
  case "$type" in
    agent)
      for f in "$REPO_DIR"/agents/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .md)
        printf '%s\tagents/%s.md\n' "$name" "$name"
      done
      ;;
    skill)
      # Single-file skills
      for f in "$REPO_DIR"/skills/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .md)
        printf '%s\tskills/%s.md\n' "$name" "$name"
      done
      # Directory-based skills (must contain SKILL.md)
      for d in "$REPO_DIR"/skills/*/; do
        [ -d "$d" ] || continue
        [ -f "${d}SKILL.md" ] || continue
        name=$(basename "$d")
        printf '%s\tskills/%s\n' "$name" "$name"
      done
      ;;
    hook)
      for f in "$REPO_DIR"/hooks/*.sh; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .sh)
        printf '%s\thooks/%s.sh\n' "$name" "$name"
      done
      ;;
  esac
}

# Output the list of types that have at least one item available.
available_types() {
  local type
  for type in agent skill hook; do
    local count
    count=$(collect_items_of_type "$type" | wc -l | tr -d ' ')
    [ "$count" -gt 0 ] && printf '%s\n' "$type"
  done
}
