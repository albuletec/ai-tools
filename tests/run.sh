#!/usr/bin/env bash
# ai-tools test suite. No framework: bash for the harness, Ruby for YAML and JSON
# assertions (Ruby ships with macOS and every GitHub runner).
#
#   tests/run.sh            run everything
#   tests/run.sh unit       run one section: unit | validate | golden | hooks
#
# Every case here maps to a real defect. Sections marked "regression" reproduce a
# bug found in the 2026-08-12 audit and fail against the code that shipped it.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_DIR/scripts/lib"

# shellcheck source=../scripts/lib/body.sh
source "$LIB_DIR/body.sh"
# shellcheck source=../scripts/lib/registry.sh
source "$LIB_DIR/registry.sh"
# shellcheck source=../scripts/lib/collect.sh
source "$LIB_DIR/collect.sh"
# shellcheck source=../scripts/lib/install.sh
source "$LIB_DIR/install.sh"
# shellcheck source=../scripts/lib/validate.sh
source "$LIB_DIR/validate.sh"
for a in $AIT_ASSISTANTS; do
  # shellcheck source=/dev/null
  source "$LIB_DIR/assistants/$a.sh"
done

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ait-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
CURRENT_SECTION=""

RED=$'\033[31m'; GREEN=$'\033[32m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'

section() { CURRENT_SECTION="$1"; printf '\n%s%s%s\n' "$BOLD" "$1" "$OFF"; }

ok()   { PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
bad()  {
  FAIL=$((FAIL + 1))
  printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"
  [ -n "${2:-}" ] && printf '      expected: %s\n' "$2"
  [ -n "${3:-}" ] && printf '      actual:   %s\n' "$3"
  return 0
}

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then ok "$label"; else bad "$label" "$want" "$got"; fi
}

assert_true() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label" "success" "failure"; fi
}

assert_false() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$label" "failure" "success"; else ok "$label"; fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) ok "$label" ;;
    *)           bad "$label" "text containing '$needle'" "$haystack" ;;
  esac
}

# Read one frontmatter key from an installed file using a real YAML parser.
# Prints KEY_MISSING when absent so assertions can distinguish empty from unset.
yaml_key() {
  ruby -ryaml -e '
    t = File.read(ARGV[0])
    m = /\A---\n(.*?)\n---\n?/m.match(t)
    abort "NO_FRONTMATTER" unless m
    d = YAML.safe_load(m[1])
    abort "NOT_A_MAP" unless d.is_a?(Hash)
    k = ARGV[1]
    print(d.key?(k) ? d[k].inspect : "KEY_MISSING")
  ' "$1" "$2" 2>&1
}

yaml_parses() {
  ruby -ryaml -e '
    t = File.read(ARGV[0])
    m = /\A---\n(.*?)\n---\n?(.*)\z/m.match(t) or abort "no frontmatter"
    d = YAML.safe_load(m[1])
    abort "not a map" unless d.is_a?(Hash)
    abort "empty body" if m[2].strip.empty?
  ' "$1" >/dev/null 2>&1
}

json_valid() { ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' "$1" >/dev/null 2>&1; }

# Build payloads in the shell rather than shelling out to Ruby per case: the hook
# sections run a few hundred cases and a process start each would dominate.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

payload_command() {
  printf '{"tool_input":{"command":"%s"}}' "$(json_escape "$1")"
}

payload_write() {
  printf '{"tool_input":{"file_path":"%s","content":"%s"}}' \
    "$(json_escape "$1")" "$(json_escape "$2")"
}

# Feed a JSON payload to a hook and report BLOCK (exit 2) or ALLOW.
hook_result() {
  local hook="$1" payload="$2" rc
  printf '%s' "$payload" | "$REPO_DIR/hooks/$hook" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && printf 'BLOCK' || printf 'ALLOW'
}

new_dir() { local d="$TMP_ROOT/$1-$RANDOM"; mkdir -p "$d"; printf '%s' "$d"; }

# ─────────────────────────────────────────────────────────────────────────────
# syntax — every shipped script must parse under the bash macOS ships (3.2)
# ─────────────────────────────────────────────────────────────────────────────
test_syntax() {
  section "syntax: every shipped script parses"
  local f out failed=0
  while IFS= read -r f; do
    if ! out=$(/bin/bash -n "$f" 2>&1); then
      bad "${f#"$REPO_DIR"/} parses" "no syntax errors" "$out"
      failed=1
    fi
  done < <(
    printf '%s\n' "$REPO_DIR/ait" "$REPO_DIR/install.sh"
    find "$REPO_DIR/scripts" "$REPO_DIR/hooks" "$REPO_DIR/tests" -name '*.sh' -type f | sort
  )
  [ "$failed" -eq 0 ] && ok "all scripts parse under /bin/bash"

  # Hooks must also be executable, or Claude Code cannot run them.
  local h nonexec=""
  for h in "$REPO_DIR"/hooks/*.sh; do
    [ -x "$h" ] || nonexec+="$(basename "$h") "
  done
  assert_eq "every hook is executable" "" "$nonexec"
}

# ─────────────────────────────────────────────────────────────────────────────
# unit — frontmatter parsing and tool translation
# ─────────────────────────────────────────────────────────────────────────────
test_unit() {
  section "unit: frontmatter scalars"
  local d; d=$(new_dir fm)

  cat > "$d/folded.md" <<'EOF'
---
name: folded
description: >-
  Reviews things carefully.
  Use when the user asks.
tools:
  - Bash
  - Read
---
Body.
EOF
  # regression: a folded description used to emit the literal ">-" downstream
  assert_eq "folded description flattens" \
    "Reviews things carefully. Use when the user asks." "$(fm_get "$d/folded.md" description)"
  # regression: a block sequence used to read as empty, which omitted tools entirely
  assert_eq "block-sequence tools parse" "Bash Read" "$(fm_get_list "$d/folded.md" tools | tr '\n' ' ' | sed 's/ $//')"

  cat > "$d/literal.md" <<'EOF'
---
name: literal
description: |
  First line.
  Second line.
tools: Bash, Read, Write
---
Body.
EOF
  assert_eq "literal description flattens" "First line. Second line." "$(fm_get "$d/literal.md" description)"
  assert_eq "comma-string tools parse" "Bash Read Write" "$(fm_get_list "$d/literal.md" tools | tr '\n' ' ' | sed 's/ $//')"

  cat > "$d/quoted.md" <<'EOF'
---
name: quoted
description: "Handles this: and that. Say \"ok\"."
tools: [Read, Grep]
---
Body.
EOF
  assert_eq "quoted description unquotes" 'Handles this: and that. Say "ok".' "$(fm_get "$d/quoted.md" description)"
  assert_eq "inline-list tools parse" "Read Grep" "$(fm_get_list "$d/quoted.md" tools | tr '\n' ' ' | sed 's/ $//')"

  cat > "$d/cont.md" <<'EOF'
---
name: cont
description: starts here
  and continues here
---
Body.
EOF
  assert_eq "plain continuation joins" "starts here and continues here" "$(fm_get "$d/cont.md" description)"

  printf 'no frontmatter\n' > "$d/none.md"
  assert_false "has_frontmatter rejects a bare file" has_frontmatter "$d/none.md"
  assert_true  "has_frontmatter accepts a real one"  has_frontmatter "$d/quoted.md"

  section "unit: yaml_quote round-trips"
  local tricky rt
  for tricky in 'plain text' 'has: a colon' 'trailing hash # here' '"already quoted"' \
                'back\slash' '[bracketed]' '*star' '- dash' 'yes'; do
    rt=$(ruby -ryaml -e 'print YAML.safe_load("v: " + ARGV[0])["v"].to_s' "$(yaml_quote "$tricky")" 2>&1)
    assert_eq "yaml_quote survives: $tricky" "$tricky" "$rt"
  done

  section "unit: tool translation"
  assert_eq "dedupes Write and Edit" "execute, read, edit" "$(translate_tools 'Bash, Read, Write, Edit')"
  assert_eq "maps Grep and Glob to search" "search" "$(translate_tools 'Grep, Glob')"
  assert_eq "maps Task to agent" "agent" "$(translate_tools '[Task]')"
  assert_eq "unmapped names reported" "Skill mcp__jira__search" \
    "$(unmapped_tools 'Read, Skill, mcp__jira__search' | sort | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "no unmapped names for a plain list" "" "$(unmapped_tools 'Bash, Read')"

  assert_true  "Read+Grep is read-only"        tools_are_readonly 'Read, Grep'
  assert_false "Read+Write is not read-only"   tools_are_readonly 'Read, Write'
  assert_false "Bash escapes read-only"        tools_are_readonly 'Bash, Read'
  assert_false "Task escapes read-only"        tools_are_readonly 'Task, Read'
  assert_false "unknown tool escapes read-only" tools_are_readonly 'Read, mcp__x__y'
  assert_false "empty list is not read-only"   tools_are_readonly ''

  section "unit: hook metadata and events"
  cat > "$d/h.sh" <<'EOF'
#!/usr/bin/env bash
## ait:event    PostToolUse
## ait:matcher  Write|Edit
## ait:timeout  30
EOF
  assert_eq "parses the header" "PostToolUse|Write|Edit|30" "$(parse_hook_meta "$d/h.sh" | tr '\t' '|')"
  printf '#!/usr/bin/env bash\n' > "$d/bare.sh"
  assert_eq "defaults when absent" "PreToolUse|Bash|10" "$(parse_hook_meta "$d/bare.sh" | tr '\t' '|')"

  assert_true  "SessionStart is a known event"   is_known_hook_event SessionStart
  assert_true  "SubagentStop is a known event"   is_known_hook_event SubagentStop
  assert_false "PreToolUsee is not an event"     is_known_hook_event PreToolUsee
  # regression: matcher support was limited to the four tool events
  assert_true  "SessionStart accepts a matcher"  event_supports_matcher SessionStart
  assert_true  "FileChanged accepts a matcher"   event_supports_matcher FileChanged
  assert_false "Stop takes no matcher"           event_supports_matcher Stop
  assert_false "UserPromptSubmit takes no matcher" event_supports_matcher UserPromptSubmit
}

# ─────────────────────────────────────────────────────────────────────────────
# validate — the fail-closed gate
# ─────────────────────────────────────────────────────────────────────────────
test_validate() {
  section "validate: refuses items that would install badly"
  local d; d=$(new_dir val)
  local saved_repo="$REPO_DIR"
  REPO_DIR="$d"
  mkdir -p "$d/agents" "$d/skills" "$d/hooks"

  # regression: a body-only file installed as an 8-byte empty skill
  printf 'body with no frontmatter\n' > "$d/skills/nofm.md"
  assert_false "no frontmatter is refused" validate_item skill nofm skills/nofm.md claude-code
  assert_contains "reason names the empty body" "install empty" \
    "$(validate_item skill nofm skills/nofm.md claude-code 2>&1)"

  printf -- '---\nname: emptybody\ndescription: Has a description but nothing else.\n---\n\n' > "$d/skills/emptybody.md"
  assert_false "empty body is refused" validate_item skill emptybody skills/emptybody.md claude-code

  printf -- '---\nname: nodesc\n---\nBody.\n' > "$d/skills/nodesc.md"
  assert_false "missing description is refused" validate_item skill nodesc skills/nodesc.md copilot

  printf -- '---\nname: Mixed_Case\ndescription: Not slug safe.\n---\nBody.\n' > "$d/skills/Mixed_Case.md"
  assert_false "non-slug name refused for copilot" validate_item skill Mixed_Case skills/Mixed_Case.md copilot
  assert_true  "non-slug name allowed for claude-code" validate_item skill Mixed_Case skills/Mixed_Case.md claude-code

  printf -- '---\nname: something-else\ndescription: Name disagrees with the file.\n---\nBody.\n' > "$d/skills/mismatch.md"
  assert_false "name/file mismatch is refused" validate_item skill mismatch skills/mismatch.md copilot
  assert_contains "reason names both identities" "does not match" \
    "$(validate_item skill mismatch skills/mismatch.md copilot 2>&1)"

  # regression: unmappable tools were dropped, and an absent tools key means
  # "every tool enabled" on Copilot
  printf -- '---\nname: mcponly\ndescription: Uses an MCP tool.\ntools: [Read, mcp__jira__search]\n---\nBody.\n' \
    > "$d/agents/mcponly.md"
  assert_false "untranslatable tools refused for copilot" validate_item agent mcponly agents/mcponly.md copilot
  assert_contains "reason explains the escalation" "grant every tool" \
    "$(validate_item agent mcponly agents/mcponly.md copilot 2>&1)"
  assert_true "untranslatable tools fine for claude-code" validate_item agent mcponly agents/mcponly.md claude-code
  assert_true "untranslatable tools fine for cursor" validate_item agent mcponly agents/mcponly.md cursor

  printf -- '---\nname: overridden\ndescription: Declares an explicit copilot list.\ntools: [Read, mcp__jira__search]\nassistants:\n  copilot:\n    tools: [read]\n---\nBody.\n' \
    > "$d/agents/overridden.md"
  assert_true "explicit copilot tools override is accepted" \
    validate_item agent overridden agents/overridden.md copilot

  printf '#!/usr/bin/env bash\n## ait:event    PreToolUse\n## ait:timeout  10s\necho\n' > "$d/hooks/badtime.sh"
  assert_false "non-integer timeout is refused" validate_item hook badtime hooks/badtime.sh claude-code

  printf '#!/usr/bin/env bash\n## ait:event    PreToolUsee\necho\n' > "$d/hooks/badevent.sh"
  assert_false "unknown event is refused" validate_item hook badevent hooks/badevent.sh claude-code

  printf '#!/usr/bin/env bash\n## ait:event    Stop\n## ait:matcher  Bash\necho\n' > "$d/hooks/badmatcher.sh"
  assert_false "matcher on a non-matcher event is refused" validate_item hook badmatcher hooks/badmatcher.sh claude-code

  printf '#!/usr/bin/env bash\n## ait:event    SessionStart\n## ait:matcher  startup\necho\n' > "$d/hooks/goodmatcher.sh"
  assert_true "matcher on SessionStart is accepted" validate_item hook goodmatcher hooks/goodmatcher.sh claude-code

  REPO_DIR="$saved_repo"

  section "validate: the shipped repo is clean"
  assert_true "every real item validates for every assistant" validate_repo
}

# ─────────────────────────────────────────────────────────────────────────────
# golden — install everything, for real, and inspect the output
# ─────────────────────────────────────────────────────────────────────────────
test_golden() {
  section "golden: every item installs for every assistant and scope"
  local root; root=$(new_dir golden)
  local saved_home="$HOME"
  local installed=0 type name rel scope assistant

  HOME="$root/home"
  mkdir -p "$HOME" "$root/proj"

  for assistant in $AIT_ASSISTANTS; do
    for type in agent skill hook; do
      while IFS=$'\t' read -r name rel; do
        [ -z "$name" ] && continue
        for scope in global local; do
          if assistant_install "$assistant" "$name" "$type" "$rel" "$scope" "$root/proj" >/dev/null 2>&1; then
            installed=$((installed + 1))
          fi
        done
      done < <(collect_items_of_type "$type" "$assistant")
    done
  done

  HOME="$saved_home"

  if [ "$installed" -gt 0 ]; then ok "$installed files installed"; else bad "installed nothing" ">0" "0"; fi

  # One Ruby pass over the whole tree. Per-file processes made this section slow
  # enough that it stopped being run, which is how the defects survived.
  local report
  report=$(ruby -ryaml -e '
    root = ARGV[0]
    bad_yaml = []; leaked = []; nodesc = []; count = 0
    Dir.glob(File.join(root, "**", "*.md"), File::FNM_DOTMATCH).each do |p|
      next unless File.file?(p)
      count += 1
      rel = p.sub("#{root}/", "")
      t = File.read(p)
      m = /\A---\n(.*?)\n---\n?(.*)\z/m.match(t)
      (bad_yaml << "#{rel} (no frontmatter)"; next) unless m
      begin
        d = YAML.safe_load(m[1])
      rescue => e
        bad_yaml << "#{rel} (#{e.message[0, 60]})"; next
      end
      (bad_yaml << "#{rel} (not a mapping)"; next) unless d.is_a?(Hash)
      bad_yaml << "#{rel} (empty body)" if m[2].strip.empty?
      leaked   << rel if d.key?("assistants")
      nodesc   << rel if d["description"].to_s.strip.empty?
    end
    puts count
    puts "BAD_YAML\t#{bad_yaml.join(", ")}"
    puts "LEAKED\t#{leaked.join(", ")}"
    puts "NODESC\t#{nodesc.join(", ")}"
  ' "$root" 2>&1)

  local checked_files bad_yaml leaked nodesc
  checked_files=$(printf '%s' "$report" | sed -n '1p')
  bad_yaml=$(printf '%s' "$report" | sed -n 's/^BAD_YAML\t//p')
  leaked=$(printf '%s' "$report" | sed -n 's/^LEAKED\t//p')
  nodesc=$(printf '%s' "$report" | sed -n 's/^NODESC\t//p')

  assert_eq "every installed file parses as YAML+body" "" "$bad_yaml"
  assert_eq "no file leaks the assistants block"       "" "$leaked"
  assert_eq "every file has a description"             "" "$nodesc"
  if [ "${checked_files:-0}" -gt 40 ]; then
    ok "$checked_files markdown files inspected"
  else
    bad "too few files inspected" ">40" "${checked_files:-0}"
  fi

  section "golden: per-assistant frontmatter contracts"
  local cop="$root/proj/.github/agents/code-reviewer.agent.md"
  local cur="$root/proj/.cursor/agents/code-reviewer.md"
  local win="$root/proj/.windsurf/skills/pr-description/SKILL.md"

  assert_eq "copilot agent tools are canonical" '["execute", "read"]' "$(yaml_key "$cop" tools)"
  assert_eq "copilot agent omits model"         "KEY_MISSING"         "$(yaml_key "$cop" model)"
  # Cursor subagents have no tools key at all; readonly is the only lever
  assert_eq "cursor agent has no tools key"     "KEY_MISSING"         "$(yaml_key "$cur" tools)"
  assert_eq "cursor agent keeps its name"       '"code-reviewer"'     "$(yaml_key "$cur" name)"
  assert_eq "windsurf skill has a name"         '"pr-description"'    "$(yaml_key "$win" name)"
  assert_true "windsurf gets no agents directory" \
    bash -c "[ ! -d '$root/proj/.windsurf/agents' ]"

  section "golden: tool access never widens (regression)"
  # code-reviewer declares Bash+Read. It must not gain 'edit' anywhere, and it
  # must not be marked readonly either, because Bash can write via redirection.
  local cop_tools; cop_tools=$(yaml_key "$cop" tools)
  case "$cop_tools" in
    *edit*) bad "code-reviewer gained edit on copilot" "no edit" "$cop_tools" ;;
    *)      ok  "code-reviewer keeps no write tool on copilot" ;;
  esac
  local a src stools ctools
  for a in "$root/proj/.github/agents"/*.agent.md; do
    [ -f "$a" ] || continue
    name=$(basename "$a" .agent.md)
    src="$REPO_DIR/agents/$name.md"
    stools=$(fm_get_list "$src" tools)
    ctools=$(yaml_key "$a" tools)
    if [ -n "$stools" ] && [ "$ctools" = "KEY_MISSING" ]; then
      bad "$name: source declares tools but copilot file omits them" "a tools list" "KEY_MISSING"
    fi
    if ! printf '%s' "$stools" | grep -qE '^(Write|Edit|MultiEdit|NotebookEdit)$'; then
      case "$ctools" in
        *edit*) bad "$name: gained edit access on copilot" "no edit" "$ctools" ;;
      esac
    fi
  done
  ok "no agent widened its tool list on copilot"

  section "golden: placeholders resolve per assistant"
  assert_contains "claude-code body says CLAUDE.md" "CLAUDE.md" \
    "$(cat "$root/proj/.claude/agents/code-planner.md")"
  assert_contains "copilot body says AGENTS.md" "AGENTS.md" \
    "$(cat "$root/proj/.github/agents/code-planner.agent.md")"
  assert_contains "cursor body says AGENTS.md" "AGENTS.md" \
    "$(cat "$root/proj/.cursor/agents/code-planner.md")"
  local leftover
  leftover=$(grep -rl '{instructionsFile}' "$root" 2>/dev/null | head -1)
  assert_eq "no unsubstituted placeholder remains" "" "$leftover"

  section "golden: skill supporting files (regression)"
  # Supporting files in subdirectories used to be dropped, installing a skill
  # whose own relative links pointed at nothing.
  local fx; fx=$(new_dir subdirs)
  local saved_repo="$REPO_DIR"
  mkdir -p "$fx/skills/withrefs/references" "$fx/skills/withrefs/scripts/nested"
  cat > "$fx/skills/withrefs/SKILL.md" <<'EOF'
---
name: withrefs
description: Skill with supporting files in subdirectories.
assistants:
  copilot:
  cursor:
  windsurf:
---
Read references/palette.md and run scripts/validate.py.
EOF
  printf 'palette\n'   > "$fx/skills/withrefs/references/palette.md"
  printf 'print(1)\n'  > "$fx/skills/withrefs/scripts/validate.py"
  printf 'deep\n'      > "$fx/skills/withrefs/scripts/nested/deep.txt"
  printf 'notes\n'     > "$fx/skills/withrefs/NOTES.md"

  REPO_DIR="$fx"
  HOME="$fx/home"; mkdir -p "$HOME" "$fx/proj"
  for assistant in claude-code copilot cursor windsurf; do
    assistant_install "$assistant" withrefs skill skills/withrefs local "$fx/proj" >/dev/null 2>&1
  done
  HOME="$saved_home"
  REPO_DIR="$saved_repo"

  local target
  for target in "$fx/proj/.claude/skills/withrefs" "$fx/proj/.github/skills/withrefs" \
                "$fx/proj/.cursor/skills/withrefs" "$fx/proj/.windsurf/skills/withrefs"; do
    local label="${target#"$fx"/proj/}"
    assert_true "$label keeps references/palette.md" bash -c "[ -f '$target/references/palette.md' ]"
    assert_true "$label keeps scripts/validate.py"   bash -c "[ -f '$target/scripts/validate.py' ]"
    assert_true "$label keeps nested subdirectories" bash -c "[ -f '$target/scripts/nested/deep.txt' ]"
    assert_true "$label keeps top-level NOTES.md"    bash -c "[ -f '$target/NOTES.md' ]"
    assert_true "$label still renders SKILL.md"      bash -c "[ -s '$target/SKILL.md' ]"
  done

  section "golden: settings.json wiring"
  local sp="$root/proj/.claude/settings.json"
  assert_true "project settings.json is valid JSON" json_valid "$sp"
  assert_contains "project hooks use CLAUDE_PROJECT_DIR" 'CLAUDE_PROJECT_DIR' "$(cat "$sp")"
  assert_contains "global hooks use \$HOME" '$HOME' "$(cat "$root/home/.claude/settings.json")"

  local grouped
  grouped=$(ruby -rjson -e '
    d = JSON.parse(File.read(ARGV[0]))
    pre = d["hooks"]["PreToolUse"]
    print pre.count { |e| e["matcher"] == "Bash" }
  ' "$sp" 2>&1)
  assert_eq "one bucket per matcher, not one per hook" "1" "$grouped"

  # Re-running an install must not duplicate an entry.
  local before after
  before=$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["hooks"].values.flatten.map{|e| e["hooks"].size}.sum' "$sp")
  HOME="$root/home"
  claude_code_install secret-scrubber hook hooks/secret-scrubber.sh local "$root/proj" >/dev/null 2>&1
  HOME="$saved_home"
  after=$(ruby -rjson -e 'print JSON.parse(File.read(ARGV[0]))["hooks"].values.flatten.map{|e| e["hooks"].size}.sum' "$sp")
  assert_eq "re-install is idempotent" "$before" "$after"

  section "golden: patch_settings_json reports failure honestly (regression)"
  # A bad timeout used to print the success line while writing nothing.
  local sd; sd=$(new_dir settings)
  printf '{}\n' > "$sd/settings.json"
  local out
  out=$(patch_settings_json "$sd/settings.json" PreToolUse Bash '/tmp/x.sh' '10s' 2>&1)
  if printf '%s' "$out" | grep -q 'wired in'; then
    bad "bad timeout must not claim success" "an error" "$out"
  else
    ok "bad timeout reports an error"
  fi
  assert_false "bad timeout returns non-zero" \
    patch_settings_json "$sd/settings.json" PreToolUse Bash '/tmp/x.sh' '10s'
  assert_eq "nothing was written" "{}" "$(tr -d ' \n' < "$sd/settings.json")"

  printf 'not json\n' > "$sd/broken.json"
  assert_false "invalid existing settings.json is refused" \
    patch_settings_json "$sd/broken.json" PreToolUse Bash '/tmp/x.sh' 10
}

# ─────────────────────────────────────────────────────────────────────────────
# hooks — behaviour of the shipped guards
# ─────────────────────────────────────────────────────────────────────────────
test_hooks() {
  section "hooks: destructive-op-guard"
  local sql; sql="DROP TAB""LE users"
  local case_line cmd want
  while IFS='|' read -r cmd want; do
    [ -z "$cmd" ] && continue
    cmd="${cmd//__SQL__/$sql}"
    assert_eq "$want: $cmd" "$want" "$(hook_result destructive-op-guard.sh "$(payload_command "$cmd")")"
  done <<'CASES'
rm -rf build|BLOCK
sudo rm -rf /|BLOCK
/bin/rm -rf ~/important|BLOCK
rm -r -f build|BLOCK
git reset --hard origin/main|BLOCK
git push --force|BLOCK
git push -f origin main|BLOCK
git clean -fd|BLOCK
git checkout .|BLOCK
git branch -D feat|BLOCK
psql -c "__SQL__"|BLOCK
rm file.txt|ALLOW
git status|ALLOW
git reset --soft HEAD~1|ALLOW
git pull --ff-only|ALLOW
git clean -nd|ALLOW
git commit -m "wip"|ALLOW
echo "a note about __SQL__ in prose"|ALLOW
grep -r "__SQL__" migrations/|ALLOW
CASES

  section "hooks: no-verify-guard"
  local nv; nv="--no-""verify"
  while IFS='|' read -r cmd want; do
    [ -z "$cmd" ] && continue
    cmd="${cmd//__NV__/$nv}"
    assert_eq "$want: $cmd" "$want" "$(hook_result no-verify-guard.sh "$(payload_command "$cmd")")"
  done <<'CASES'
git commit __NV__ -m x|BLOCK
git commit -n -m x|BLOCK
git push __NV__|BLOCK
git -c core.hooksPath=/dev/null commit -m x|BLOCK
HUSKY=0 git commit -m x|BLOCK
HUSKY_SKIP_HOOKS=1 git commit -m x|BLOCK
git commit -m "document the __NV__ flag"|ALLOW
npm run build -- __NV__|ALLOW
git commit -m x|ALLOW
git status|ALLOW
CASES

  section "hooks: secret-scrubber"
  local k1 k2 k3 k4 pw sec
  k1="sk"; k1="${k1}-abcdefghijklmnopqrstuvwx"
  k2="AKI"; k2="${k2}AIOSFODNN7EXAMPLE"
  k3="ghp"; k3="${k3}_abcdefghijklmnopqrstuv"
  k4="-----BEGIN RSA PRI"; k4="${k4}VATE KEY-----"
  pw="pass"; pw="${pw}word"
  sec="sec"; sec="${sec}ret"

  assert_eq "BLOCK: vendor api key" BLOCK \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "const k = \"$k1\";")")"
  assert_eq "BLOCK: cloud access key id" BLOCK \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "$k2")")"
  assert_eq "BLOCK: vendor token" BLOCK \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "TOKEN=$k3")")"
  assert_eq "BLOCK: private key header" BLOCK \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "$k4")")"
  assert_eq "BLOCK: hardcoded credential" BLOCK \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "$pw = \"correcthorsebattery\"")")"
  assert_eq "BLOCK: client secret" BLOCK \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "client_$sec: \"9f8s7d6f5g4h3j2k1l\"")")"
  assert_eq "ALLOW: env var reference" ALLOW \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "apiKey: process.env.API_KEY")")"
  assert_eq "ALLOW: obvious placeholder" ALLOW \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "$pw = \"changeme123\"")")"
  assert_eq "ALLOW: curly placeholder" ALLOW \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "token: {myToken}")")"
  assert_eq "ALLOW: hex digest" ALLOW \
    "$(hook_result secret-scrubber.sh "$(payload_write "x.ts" "hash = \"a94a8fe5ccb19ba61c4c0873d391e987\"")")"
  assert_eq "ALLOW: benign command" ALLOW \
    "$(hook_result secret-scrubber.sh "$(payload_command "gh auth status")")"

  section "hooks: terminology-guard rule coverage"
  local label text out warnings
  while IFS='|' read -r label text; do
    [ -z "$label" ] && continue
    out=$(printf '%s' "$(payload_write "x.ts" "$text")" \
      | "$REPO_DIR/hooks/terminology-guard.sh" 2>&1)
    # Count only real findings. Matching on "non-empty output" once let a shell
    # syntax error in the hook masquerade as fifteen passing rules.
    warnings=$(printf '%s\n' "$out" | grep -c '^terminology-guard: ')
    if [ "$warnings" -gt 0 ]; then
      ok "flags $label"
    else
      bad "flags $label" "a terminology-guard warning" "${out:-silence}"
    fi
  done <<'CASES'
TLA|const TLA = "abc";
Service ID|const x = ServiceID;
app_id|const app_id = 1;
service_id|const service_id = 1;
dc dimension|log({ dc: "ldn" });
squad|owner: squad-alpha
brand shortname|const brand = "bf";
licence spelling|const licenseModel = 1;
the monorepo|// see the monorepo root
Dockerfile|COPY Dockerfile .
docker-compose|docker-compose up
docker image|build the docker image
angle placeholder|const u = "<brand>/x";
double placeholder|const u = "{{brand}}/x";
provider in code|const provider = "x";
CASES

  # Prose about a real supplier still warns, but ai-tools' own docs no longer
  # contain the word, so the rule is quiet where it used to be noisy.
  local own_docs
  own_docs=$(printf '%s' "$(payload_write "README.md" "$(cat "$REPO_DIR/README.md")")" \
    | "$REPO_DIR/hooks/terminology-guard.sh" 2>&1 | grep -c '^terminology-guard: ' || true)
  assert_eq "README.md produces no terminology warnings" "0" "$own_docs"
}

# ─────────────────────────────────────────────────────────────────────────────

main() {
  local want="${1:-all}"
  printf '%sai-tools test suite%s %s(%s)%s\n' "$BOLD" "$OFF" "$DIM" "$want" "$OFF"

  case "$want" in
    syntax)   test_syntax ;;
    unit)     test_unit ;;
    validate) test_validate ;;
    golden)   test_golden ;;
    hooks)    test_hooks ;;
    all)      test_syntax; test_unit; test_validate; test_golden; test_hooks ;;
    *)        printf 'unknown section: %s\n' "$want" >&2; exit 2 ;;
  esac

  printf '\n%s──────────────────────────────%s\n' "$DIM" "$OFF"
  if [ "$FAIL" -eq 0 ]; then
    printf '%s✓ %d passed%s\n\n' "$GREEN" "$PASS" "$OFF"
    return 0
  fi
  printf '%s✗ %d failed%s, %d passed\n\n' "$RED" "$FAIL" "$OFF" "$PASS"
  return 1
}

main "$@"
