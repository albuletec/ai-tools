#!/usr/bin/env bash
# Interactive menus — item selection.
# Requires: format_record (collect.sh), colour vars, die/warn/header (ait)

# Present a numbered item picker. Writes selected records to $selected_file.
pick_items() {
  local items_file="$1"
  local selected_file="$2"

  local -a display_arr=()
  local -a record_arr=()

  while IFS= read -r record; do
    [ -z "$record" ] && continue
    display_arr+=("$(format_record "$record")")
    record_arr+=("$record")
  done < "$items_file"

  local count="${#display_arr[@]}"
  [ "$count" -eq 0 ] && die "No items found."

  header "Available items"
  printf "\n"
  local i
  for ((i = 0; i < count; i++)); do
    printf "  %3d)  %s\n" "$((i + 1))" "${display_arr[$i]}"
  done

  printf "\n"
  printf "Select numbers (space-separated), ${BOLD}a${RESET} for all, ${BOLD}q${RESET} to quit: "
  local input
  read -r input

  [ "$input" = "q" ] && exit 0

  > "$selected_file"
  if [ "$input" = "a" ]; then
    for ((i = 0; i < count; i++)); do
      echo "${record_arr[$i]}" >> "$selected_file"
    done
    return
  fi

  local n idx
  for n in $input; do
    if [[ "$n" =~ ^[0-9]+$ ]]; then
      idx=$((n - 1))
      if [ "$idx" -ge 0 ] && [ "$idx" -lt "$count" ]; then
        echo "${record_arr[$idx]}" >> "$selected_file"
      else
        warn "No item at position $n (skipped)"
      fi
    else
      warn "Not a number: '$n' (skipped)"
    fi
  done
}
