#!/usr/bin/env bash
# ai-tools test suite. No framework: bash for the harness, Ruby for YAML and JSON
# assertions (Ruby ships with macOS and every GitHub runner).
#
#   tests/run.sh            run everything
#   tests/run.sh unit       run one section:
#                           syntax | install | unit | validate | rules | init |
#                           wizard | golden | hooks
#
# Every case here maps to a real defect. Sections marked "regression" reproduce a
# bug found in the 2026-08-12 audit and fail against the code that shipped it.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$REPO_DIR/scripts"

# shellcheck source=../scripts/output.sh
source "$SCRIPTS_DIR/output.sh"
# shellcheck source=../scripts/body.sh
source "$SCRIPTS_DIR/body.sh"
# shellcheck source=../scripts/registry.sh
source "$SCRIPTS_DIR/registry.sh"
# shellcheck source=../scripts/collect.sh
source "$SCRIPTS_DIR/collect.sh"
# shellcheck source=../scripts/install.sh
source "$SCRIPTS_DIR/install.sh"
# shellcheck source=../scripts/validate.sh
source "$SCRIPTS_DIR/validate.sh"
# menu.sh and wizard.sh both define functions and initialise empty variables only,
# so loading them has no side effects outside the flows the wizard section drives.
# shellcheck source=../scripts/menu.sh
source "$SCRIPTS_DIR/menu.sh"
# shellcheck source=../scripts/wizard.sh
source "$SCRIPTS_DIR/wizard.sh"
for a in $AIT_ASSISTANTS; do
  # shellcheck source=/dev/null
  source "$SCRIPTS_DIR/assistants/$a.sh"
done

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ait-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
CURRENT_SECTION=""

# RED, GREEN, BOLD, DIM and RESET come from output.sh, which gates them on stdout
# being a terminal — so a piped test log is plain text throughout, including the
# installer output the golden section provokes.

section() { CURRENT_SECTION="$1"; printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }

ok()   { PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
bad()  {
  FAIL=$((FAIL + 1))
  printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"
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
  printf '%s' "$payload" | "$REPO_DIR/claude-code/hooks/$hook" >/dev/null 2>&1
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
    printf '%s\n' "$REPO_DIR/ait.sh" "$REPO_DIR/install.sh"
    find "$REPO_DIR/scripts" "$REPO_DIR/claude-code/hooks" "$REPO_DIR/tests" -name '*.sh' -type f | sort
  )
  [ "$failed" -eq 0 ] && ok "all scripts parse under /bin/bash"

  # Hooks must also be executable, or Claude Code cannot run them.
  local h nonexec=""
  for h in "$REPO_DIR"/claude-code/hooks/*.sh; do
    [ -x "$h" ] || nonexec+="$(basename "$h") "
  done
  assert_eq "every hook is executable" "" "$nonexec"
}

# ─────────────────────────────────────────────────────────────────────────────
# install — the bootstrap symlink
# ─────────────────────────────────────────────────────────────────────────────
test_install() {
  section "install: bootstrap symlinks ait.sh as extensionless ait"
  local root saved_home out
  root=$(new_dir install)
  saved_home="$HOME"

  HOME="$root"
  out=$(bash "$REPO_DIR/install.sh" 2>&1)
  HOME="$saved_home"

  local link="$root/.local/bin/ait"

  assert_true  "creates ~/.local/bin/ait"        bash -c "[ -L '$link' ]"
  assert_false "does not create ait.sh on PATH"  bash -c "[ -e '$root/.local/bin/ait.sh' ]"
  assert_eq    "the link points at ait.sh"       "$REPO_DIR/ait.sh" "$(readlink "$link")"
  assert_true  "the link target is executable"   bash -c "[ -x '$link' ]"

  # The point of the rename: ait.sh resolves its own repo root by walking the
  # symlink chain, so it must still find scripts/ when invoked under a different
  # name from a different directory.
  local help_out list_out
  help_out=$(cd "$root" && "$link" help 2>&1)
  assert_contains "invoking the link runs the CLI" "AI Tools installer" "$help_out"

  list_out=$(cd "$root" && "$link" list 2>&1)
  assert_contains "the link resolves scripts/ correctly" "code-planner" "$list_out"
  assert_contains "and finds every assistant" "windsurf" "$list_out"

  # Re-running must not stack up or leave the old name behind.
  HOME="$root"
  bash "$REPO_DIR/install.sh" >/dev/null 2>&1
  HOME="$saved_home"
  assert_eq "re-running leaves exactly one entry" "1" \
    "$(find "$root/.local/bin" -maxdepth 1 -name 'ait*' | wc -l | tr -d ' ')"

  assert_contains "reports where it installed to" ".local/bin/ait" "$out"
}

# ─────────────────────────────────────────────────────────────────────────────
# unit — frontmatter parsing, yaml_quote, hook metadata
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
  mkdir -p "$d/common/agents" "$d/common/skills" "$d/claude-code/hooks"

  # regression: a body-only file installed as an 8-byte empty skill
  printf 'body with no frontmatter\n' > "$d/common/skills/nofm.md"
  assert_false "no frontmatter is refused" validate_item skill nofm common/skills/nofm.md claude-code
  assert_contains "reason names the empty body" "install empty" \
    "$(validate_item skill nofm common/skills/nofm.md claude-code 2>&1)"

  printf -- '---\nname: emptybody\ndescription: Has a description but nothing else.\n---\n\n' > "$d/common/skills/emptybody.md"
  assert_false "empty body is refused" validate_item skill emptybody common/skills/emptybody.md claude-code

  printf -- '---\nname: nodesc\n---\nBody.\n' > "$d/common/skills/nodesc.md"
  assert_false "missing description is refused" validate_item skill nodesc common/skills/nodesc.md copilot

  printf -- '---\nname: Mixed_Case\ndescription: Not slug safe.\n---\nBody.\n' > "$d/common/skills/Mixed_Case.md"
  assert_false "non-slug name refused for copilot" validate_item skill Mixed_Case common/skills/Mixed_Case.md copilot
  assert_true  "non-slug name allowed for claude-code" validate_item skill Mixed_Case common/skills/Mixed_Case.md claude-code

  printf -- '---\nname: something-else\ndescription: Name disagrees with the file.\n---\nBody.\n' > "$d/common/skills/mismatch.md"
  assert_false "name/file mismatch is refused" validate_item skill mismatch common/skills/mismatch.md copilot
  assert_contains "reason names both identities" "does not match" \
    "$(validate_item skill mismatch common/skills/mismatch.md copilot 2>&1)"

  # regression: an absent tools key means "every tool enabled" on Copilot, so an
  # agent that opts in without declaring a list must be refused
  printf -- '---\nname: notools\ndescription: Opts into Copilot without a tool list.\nassistants:\n  copilot:\n  cursor:\n---\nBody.\n' \
    > "$d/common/agents/notools.md"
  assert_false "missing copilot tools refused for copilot" validate_item agent notools common/agents/notools.md copilot
  assert_contains "reason explains the escalation" "every tool enabled" \
    "$(validate_item agent notools common/agents/notools.md copilot 2>&1)"
  assert_true "missing copilot tools fine for claude-code" validate_item agent notools common/agents/notools.md claude-code
  assert_true "missing copilot tools fine for cursor" validate_item agent notools common/agents/notools.md cursor

  printf -- '---\nname: declared\ndescription: Declares its own Copilot tool list.\nassistants:\n  claude-code:\n    tools: [Read]\n  copilot:\n    tools: [read]\n---\nBody.\n' \
    > "$d/common/agents/declared.md"
  assert_true "declared copilot tools are accepted" \
    validate_item agent declared common/agents/declared.md copilot

  printf '#!/usr/bin/env bash\n## ait:event    PreToolUse\n## ait:timeout  10s\necho\n' > "$d/claude-code/hooks/badtime.sh"
  assert_false "non-integer timeout is refused" validate_item hook badtime claude-code/hooks/badtime.sh claude-code

  printf '#!/usr/bin/env bash\n## ait:event    PreToolUsee\necho\n' > "$d/claude-code/hooks/badevent.sh"
  assert_false "unknown event is refused" validate_item hook badevent claude-code/hooks/badevent.sh claude-code

  printf '#!/usr/bin/env bash\n## ait:event    Stop\n## ait:matcher  Bash\necho\n' > "$d/claude-code/hooks/badmatcher.sh"
  assert_false "matcher on a non-matcher event is refused" validate_item hook badmatcher claude-code/hooks/badmatcher.sh claude-code

  printf '#!/usr/bin/env bash\n## ait:event    SessionStart\n## ait:matcher  startup\necho\n' > "$d/claude-code/hooks/goodmatcher.sh"
  assert_true "matcher on SessionStart is accepted" validate_item hook goodmatcher claude-code/hooks/goodmatcher.sh claude-code

  REPO_DIR="$saved_repo"

  section "validate: the shipped repo is clean"
  assert_true "every real item validates for every assistant" validate_repo
}

# ─────────────────────────────────────────────────────────────────────────────
# rules — the fourth item type: discovery, rendering per assistant, activation
# ─────────────────────────────────────────────────────────────────────────────
test_rules() {
  section "rules: discovery skips the format README"
  local fx; fx=$(new_dir rules)
  local saved_repo="$REPO_DIR" saved_home="$HOME"
  mkdir -p "$fx/common/rules" "$fx/proj" "$fx/home"

  printf '# Rules\n\nFormat notes, not a rule.\n' > "$fx/common/rules/README.md"

  cat > "$fx/common/rules/code-conventions.md" <<'EOF'
---
name: code-conventions
description: How this codebase is written.
paths: ["src/**/*.ts"]
assistants:
  cursor:
    alwaysApply: true
  windsurf:
    trigger: always_on
---
Follow the conventions in {instructionsFile}.
EOF

  REPO_DIR="$fx"

  # regression: without the README skip, `ait list` shows a "readme" rule and
  # validate_repo fails on it for having no frontmatter.
  assert_eq "the rule is discovered, the README is not" \
    "code-conventions|common/rules/code-conventions.md" \
    "$(_all_items_of_type rule | tr '\t' '|')"
  assert_eq "rule sits between skill and hook in the type list" \
    "agent skill rule hook" "$AIT_ITEM_TYPES"

  HOME="$fx/home"
  AIT_WINDSURF_USER_DIR="$fx/wsuser"
  claude_code_install code-conventions rule common/rules/code-conventions.md local  "$fx/proj" >/dev/null 2>&1
  claude_code_install code-conventions rule common/rules/code-conventions.md global "$fx/proj" >/dev/null 2>&1
  cursor_install      code-conventions rule common/rules/code-conventions.md local  "$fx/proj" >/dev/null 2>&1
  windsurf_install    code-conventions rule common/rules/code-conventions.md local  "$fx/proj" >/dev/null 2>&1
  windsurf_install    code-conventions rule common/rules/code-conventions.md global "$fx/proj" >/dev/null 2>&1
  unset AIT_WINDSURF_USER_DIR
  HOME="$saved_home"

  section "rules: claude-code"
  local ccr="$fx/proj/.claude/rules/code-conventions.md"
  assert_true "local rule lands in .claude/rules"     bash -c "[ -f '$ccr' ]"
  assert_true "global rule lands in ~/.claude/rules"  bash -c "[ -f '$fx/home/.claude/rules/code-conventions.md' ]"
  assert_true "the file parses as YAML plus a body"   yaml_parses "$ccr"
  assert_eq   "it keeps the declared paths" '["src/**/*.ts"]' "$(yaml_key "$ccr" paths)"
  assert_eq   "it keeps its name"           '"code-conventions"' "$(yaml_key "$ccr" name)"
  assert_eq   "it drops the assistants block" "KEY_MISSING" "$(yaml_key "$ccr" assistants)"
  # A top-level trigger or globs written for another assistant must never leak in,
  # which is why rules are rendered explicitly rather than passed through.
  assert_eq   "it carries no windsurf trigger" "KEY_MISSING" "$(yaml_key "$ccr" trigger)"
  assert_contains "the body says CLAUDE.md" "CLAUDE.md" "$(cat "$ccr")"

  section "rules: cursor"
  local curr="$fx/proj/.cursor/rules/code-conventions.mdc"
  assert_true  "the rule installs as .mdc" bash -c "[ -f '$curr' ]"
  assert_false "no .md is left beside it"  bash -c "[ -e '$fx/proj/.cursor/rules/code-conventions.md' ]"
  assert_eq "alwaysApply carries over" "true"        "$(yaml_key "$curr" alwaysApply)"
  assert_eq "no name key is emitted"   "KEY_MISSING" "$(yaml_key "$curr" name)"
  assert_eq "no assistants key leaks"  "KEY_MISSING" "$(yaml_key "$curr" assistants)"
  # regression: falling back to the top-level description would silently make
  # every rule Agent Requested, because on Cursor a present description is what
  # selects that activation mode.
  assert_eq "an undeclared description stays absent" "KEY_MISSING" "$(yaml_key "$curr" description)"
  assert_contains "the body says AGENTS.md" "AGENTS.md" "$(cat "$curr")"

  section "rules: windsurf"
  local winr="$fx/proj/.windsurf/rules/code-conventions.md"
  assert_true "the local rule lands in .windsurf/rules" bash -c "[ -f '$winr' ]"
  assert_true "the global rule lands under the user dir" \
    bash -c "[ -f '$fx/wsuser/rules/code-conventions.md' ]"
  assert_eq "the declared trigger is emitted" '"always_on"' "$(yaml_key "$winr" trigger)"
  assert_eq "a top-level description is re-quoted" '"How this codebase is written."' \
    "$(yaml_key "$winr" description)"
  assert_eq "no assistants key leaks" "KEY_MISSING" "$(yaml_key "$winr" assistants)"

  section "rules: copilot refuses them"
  assert_false "copilot does not support the type" assistant_supports_type copilot rule
  assert_false "a direct install returns non-zero" \
    copilot_install code-conventions rule common/rules/code-conventions.md local "$fx/proj"
  assert_false "and writes nothing under .github/" bash -c "[ -e '$fx/proj/.github' ]"

  section "rules: validation"
  assert_true "the valid rule passes for claude-code" \
    validate_item rule code-conventions common/rules/code-conventions.md claude-code
  assert_true "the valid rule passes for cursor" \
    validate_item rule code-conventions common/rules/code-conventions.md cursor
  assert_true "the valid rule passes for windsurf" \
    validate_item rule code-conventions common/rules/code-conventions.md windsurf

  cat > "$fx/common/rules/notrigger.md" <<'EOF'
---
name: notrigger
description: Opts into Windsurf without declaring a trigger.
assistants:
  cursor:
  windsurf:
---
Body.
EOF
  assert_false "no windsurf trigger is refused" \
    validate_item rule notrigger common/rules/notrigger.md windsurf
  assert_contains "the reason names the trigger" "trigger" \
    "$(validate_item rule notrigger common/rules/notrigger.md windsurf 2>&1)"
  assert_true "the same rule is fine for claude-code" \
    validate_item rule notrigger common/rules/notrigger.md claude-code
  assert_true "the same rule is fine for cursor" \
    validate_item rule notrigger common/rules/notrigger.md cursor

  cat > "$fx/common/rules/badtrigger.md" <<'EOF'
---
name: badtrigger
description: Declares a trigger Windsurf does not know.
assistants:
  windsurf:
    trigger: whenever
---
Body.
EOF
  assert_false "an unknown trigger is refused" \
    validate_item rule badtrigger common/rules/badtrigger.md windsurf
  assert_true  "always_on is a known trigger"    is_known_rule_trigger always_on
  assert_true  "model_decision is a known trigger" is_known_rule_trigger model_decision
  assert_false "whenever is not a known trigger" is_known_rule_trigger whenever

  cat > "$fx/common/rules/asks.md" <<'EOF'
---
name: asks
assistants:
  windsurf:
    trigger: model_decision
---
Body.
EOF
  assert_false "model_decision with no description anywhere is refused" \
    validate_item rule asks common/rules/asks.md windsurf
  assert_contains "the reason names the trigger that needs one" "model_decision" \
    "$(validate_item rule asks common/rules/asks.md windsurf 2>&1)"

  cat > "$fx/common/rules/noglobs.md" <<'EOF'
---
name: noglobs
description: Glob-triggered with no pattern to match.
assistants:
  windsurf:
    trigger: glob
---
Body.
EOF
  assert_false "trigger glob with no globs is refused" \
    validate_item rule noglobs common/rules/noglobs.md windsurf

  cat > "$fx/common/rules/both.md" <<'EOF'
---
name: both
description: Contradictory Cursor activation.
assistants:
  cursor:
    alwaysApply: true
    globs: ["src/**"]
---
Body.
EOF
  assert_false "alwaysApply plus globs is refused for cursor" \
    validate_item rule both common/rules/both.md cursor
  assert_contains "the reason says alwaysApply wins" "takes precedence" \
    "$(validate_item rule both common/rules/both.md cursor 2>&1)"

  cat > "$fx/common/rules/badapply.md" <<'EOF'
---
name: badapply
description: alwaysApply is not a boolean.
assistants:
  cursor:
    alwaysApply: sometimes
---
Body.
EOF
  assert_false "a non-boolean alwaysApply is refused" \
    validate_item rule badapply common/rules/badapply.md cursor

  cat > "$fx/common/rules/blockseq.md" <<'EOF'
---
name: blockseq
description: Activation list written as a block sequence.
assistants:
  cursor:
    globs:
      - src/**
---
Body.
EOF
  # A block sequence under an assistants: key reads as empty, so the key would be
  # dropped and the rule installed with a wider scope than the author declared.
  assert_false "a block-sequence globs list is refused" \
    validate_item rule blockseq common/rules/blockseq.md cursor
  assert_contains "the reason names the inline form" "inline" \
    "$(validate_item rule blockseq common/rules/blockseq.md cursor 2>&1)"

  REPO_DIR="$saved_repo"
}

# ─────────────────────────────────────────────────────────────────────────────
# init — the per-project context files, which are not items
# ─────────────────────────────────────────────────────────────────────────────
test_init() {
  section "init: declared targets per assistant and scope"
  local fx; fx=$(new_dir init)
  local saved_home="$HOME"
  mkdir -p "$fx/proj" "$fx/home"
  HOME="$fx/home"

  assert_eq "claude-code local targets the project CLAUDE.md" \
    "claude-code/init/CLAUDE.md|$fx/proj/CLAUDE.md" \
    "$(assistant_init_targets claude-code local "$fx/proj" | tr '\t' '|')"
  assert_eq "claude-code global reads \$HOME at call time" \
    "claude-code/init/CLAUDE.md|$fx/home/.claude/CLAUDE.md" \
    "$(assistant_init_targets claude-code global "$fx/proj" | tr '\t' '|')"
  assert_eq "copilot local targets .github/copilot-instructions.md" \
    "copilot/init/copilot-instructions.md|$fx/proj/.github/copilot-instructions.md" \
    "$(assistant_init_targets copilot local "$fx/proj" | tr '\t' '|')"
  assert_eq "cursor local targets AGENTS.md" \
    "cursor/init/AGENTS.md|$fx/proj/AGENTS.md" \
    "$(assistant_init_targets cursor local "$fx/proj" | tr '\t' '|')"
  assert_eq "copilot has no global target"  "" "$(assistant_init_targets copilot  global "$fx/proj")"
  assert_eq "cursor has no global target"   "" "$(assistant_init_targets cursor   global "$fx/proj")"
  assert_eq "windsurf has no global target" "" "$(assistant_init_targets windsurf global "$fx/proj")"

  section "init: cursor and windsurf share one AGENTS.md"
  local shared
  shared=$(_init_collect "$(printf 'cursor\nwindsurf')" local "$fx/proj")
  assert_eq "the shared target is collected once" "1" \
    "$(printf '%s\n' "$shared" | wc -l | tr -d ' ')"
  assert_contains "the target is AGENTS.md"      "$fx/proj/AGENTS.md" "$shared"
  assert_contains "Cursor is named as an owner"   "Cursor"   "$shared"
  assert_contains "Windsurf is named as an owner" "Windsurf" "$shared"
  assert_eq "the two AGENTS.md templates are byte-identical" "0" \
    "$(cmp -s "$REPO_DIR/cursor/init/AGENTS.md" "$REPO_DIR/windsurf/init/AGENTS.md"; printf '%s' "$?")"
  assert_eq "an unselected assistant contributes nothing" "" \
    "$(_init_collect "$(printf 'copilot')" global "$fx/proj")"

  section "init: install_init_file writes whole files only"
  local src="$fx/tpl.md" tgt="$fx/nested/deep/CONTEXT.md"
  printf 'template body\n' > "$src"

  assert_true "it creates the file and its parent directory" \
    install_init_file "$src" "$tgt" ask
  assert_eq "the content equals the template" "template body" "$(cat "$tgt")"

  printf 'local edits\n' > "$tgt"
  assert_true "skip returns 0 on an existing file" install_init_file "$src" "$tgt" skip
  assert_eq   "skip leaves the content untouched" "local edits" "$(cat "$tgt")"

  printf 'n\n' | install_init_file "$src" "$tgt" ask >/dev/null 2>&1
  assert_eq "ask fed n leaves the content untouched" "local edits" "$(cat "$tgt")"

  printf 'y\n' | install_init_file "$src" "$tgt" ask >/dev/null 2>&1
  assert_eq "ask fed y replaces the content" "template body" "$(cat "$tgt")"

  printf 'local edits\n' > "$tgt"
  install_init_file "$src" "$tgt" overwrite >/dev/null 2>&1
  assert_eq "overwrite replaces the content" "template body" "$(cat "$tgt")"

  assert_false "a missing template is refused" \
    install_init_file "$fx/nope.md" "$fx/never-written.md" overwrite
  assert_false "and nothing is written" bash -c "[ -e '$fx/never-written.md' ]"

  section "init: _init_write reports what it did"
  local lines out
  lines="claude-code/init/CLAUDE.md"$'\t'"$fx/proj/CLAUDE.md"$'\t'"Claude Code"
  out=$(_init_write "$lines" overwrite 2>&1)
  assert_true "the template is written" bash -c "[ -s '$fx/proj/CLAUDE.md' ]"
  assert_contains "the summary counts the write" "1 written" "$out"

  printf 'local edits\n' > "$fx/proj/CLAUDE.md"
  out=$(_init_write "$lines" skip 2>&1)
  assert_contains "an existing file is reported as left alone" "left alone" "$out"
  assert_eq "and is not touched" "local edits" "$(cat "$fx/proj/CLAUDE.md")"

  section "init: every declared template exists in the repo"
  # Catches a renamed or moved template, which would otherwise only surface as a
  # failed `ait init` in somebody else's project.
  local a scope srcrel target missing=""
  for a in $AIT_ASSISTANTS; do
    for scope in local global; do
      while IFS=$'\t' read -r srcrel target; do
        [ -z "$srcrel" ] && continue
        [ -f "$REPO_DIR/$srcrel" ] || missing+="$srcrel "
      done < <(assistant_init_targets "$a" "$scope" "$fx/proj")
    done
  done
  assert_eq "no assistant names a template that is missing" "" "$missing"

  HOME="$saved_home"
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
    for type in $AIT_ITEM_TYPES; do
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
  #
  # The glob stays *.md and deliberately does not include *.mdc: a Cursor rule
  # legitimately has no description — one would switch it to Agent Requested
  # activation — so the nodesc assertion below would fail on it. Cursor rules are
  # asserted on in the `rules` section instead.
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
  # code-reviewer declares Bash+Read for Claude Code and execute+read for Copilot.
  # It must not gain 'edit' anywhere, and it must not be marked readonly either,
  # because Bash can write via redirection. The two lists are now written by hand
  # and independently, so the loop below cross-checks that they agree on write
  # access rather than checking a translation.
  local cop_tools; cop_tools=$(yaml_key "$cop" tools)
  case "$cop_tools" in
    *edit*) bad "code-reviewer gained edit on copilot" "no edit" "$cop_tools" ;;
    *)      ok  "code-reviewer keeps no write tool on copilot" ;;
  esac
  local a src cc_decl cop_decl ctools
  for a in "$root/proj/.github/agents"/*.agent.md; do
    [ -f "$a" ] || continue
    name=$(basename "$a" .agent.md)
    src="$REPO_DIR/common/agents/$name.md"
    cc_decl=$(assistant_config "$src" claude-code tools)
    cop_decl=$(assistant_config "$src" copilot tools)
    ctools=$(yaml_key "$a" tools)
    if [ -z "$cop_decl" ] || [ "$ctools" = "KEY_MISSING" ]; then
      bad "$name: copilot tools must be declared and emitted" "a tools list" "${ctools}"
    fi
    # Word boundaries, because the declaration is a bracketed comma list and
    # NotebookRead must not read as a write tool.
    if ! printf '%s' "$cc_decl" | grep -qE '(^|[^[:alnum:]])(Write|Edit|MultiEdit|NotebookEdit)([^[:alnum:]]|$)'; then
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
  claude_code_install secret-scrubber hook claude-code/hooks/secret-scrubber.sh local "$root/proj" >/dev/null 2>&1
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
# wizard — the interactive flows, driven by a recorded keystroke stream
#
# The menus read single bytes from stdin, so a file of keystrokes drives them just
# like a terminal: \033[B is Down, a space toggles, \n confirms, a lone \033 is
# ESC. Input comes from a file rather than a pipe so the menu runs in this shell
# and its MENU_* globals can be asserted on.
#
# Until this section existed the wizard was the only part of ait with no coverage
# at all, because it needs a TTY to look at. It does not need one to run.
# ─────────────────────────────────────────────────────────────────────────────
test_wizard() {
  section "wizard: menus report the selected position"
  local d; d=$(new_dir wizard)
  mkdir -p "$d/home" "$d/proj"

  printf '\033[B\n' > "$d/k-down-enter"
  MENU_INDEX=""; MENU_RESULT=""
  single_menu "pick one" "" alpha beta gamma < "$d/k-down-enter" >/dev/null
  assert_eq "single_menu reports the index"       "1"    "$MENU_INDEX"
  assert_eq "single_menu still reports the label" "beta" "$MENU_RESULT"

  # A lone ESC byte: read_key sees \033 and no arrow sequence follows it.
  printf '\033' > "$d/k-esc"
  MENU_INDEX="stale"
  if single_menu "pick one" "" alpha beta < "$d/k-esc" >/dev/null; then
    bad "ESC on a single menu returns non-zero" "failure" "success"
  else
    ok "ESC on a single menu returns non-zero"
  fi
  assert_eq "ESC clears the index" "" "$MENU_INDEX"

  # Two toggles, reported in the order they were made.
  printf ' \033[B \n' > "$d/k-two"
  MENU_INDICES=""; _MENU_DISABLED=""
  multi_menu "pick some" "" alpha beta gamma < "$d/k-two" >/dev/null
  assert_eq "multi_menu reports every index" "0 1" "$MENU_INDICES"

  printf '\n' > "$d/k-none"
  MENU_INDICES="stale"; _MENU_DISABLED=""
  multi_menu "pick some" "" alpha beta < "$d/k-none" >/dev/null
  assert_eq "confirming with nothing toggled reports no indices" "" "$MENU_INDICES"

  section "wizard: install flow writes the selected item"
  # claude-code (ENTER) → global (ENTER) → Agent (ENTER) → toggle first → confirm
  printf '\n\n\n \ny\n' > "$d/k-install"
  (
    cd "$d/proj" || exit 1
    export HOME="$d/home"
    run_wizard < "$d/k-install"
  ) >/dev/null 2>&1
  assert_true "the agent lands in the global tree" \
    bash -c "[ -s '$d/home/.claude/agents/code-planner.md' ]"
  assert_true "it parses as YAML plus a body" \
    yaml_parses "$d/home/.claude/agents/code-planner.md"

  section "wizard: arrow keys, local scope and multi-select"
  # Down→Copilot, Down→Local, Agent, toggle two, confirm
  printf '\033[B\n\033[B\n\n \033[B \ny\n' > "$d/k-copilot"
  local proj2="$d/proj2" home2="$d/home2"
  mkdir -p "$proj2" "$home2"
  (
    cd "$proj2" || exit 1
    export HOME="$home2"
    run_wizard < "$d/k-copilot"
  ) >/dev/null 2>&1
  assert_eq "both toggled agents install" "2" \
    "$(find "$proj2/.github/agents" -name '*.agent.md' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "local scope writes nothing to \$HOME" "0" \
    "$(find "$home2" -type f 2>/dev/null | wc -l | tr -d ' ')"

  section "wizard: ESC on the first step exits without writing"
  local home3="$d/home3" proj3="$d/proj3"
  mkdir -p "$home3" "$proj3"
  printf '\033' > "$d/k-escape"
  (
    cd "$proj3" || exit 1
    export HOME="$home3"
    run_wizard < "$d/k-escape"
  ) >/dev/null 2>&1
  assert_eq "nothing is installed" "0" \
    "$(find "$home3" "$proj3" -type f 2>/dev/null | wc -l | tr -d ' ')"

  section "wizard: init flow writes the context file"
  local home4="$d/home4" proj4="$d/proj4"
  mkdir -p "$home4" "$proj4"
  # toggle claude-code → confirm list → global → confirm
  printf ' \n\ny\n' > "$d/k-init"
  (
    cd "$proj4" || exit 1
    export HOME="$home4"
    run_init_wizard < "$d/k-init"
  ) >/dev/null 2>&1
  assert_true "the global CLAUDE.md is written" \
    bash -c "[ -s '$home4/.claude/CLAUDE.md' ]"
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
      | "$REPO_DIR/claude-code/hooks/terminology-guard.sh" 2>&1)
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
    | "$REPO_DIR/claude-code/hooks/terminology-guard.sh" 2>&1 | grep -c '^terminology-guard: ' || true)
  assert_eq "README.md produces no terminology warnings" "0" "$own_docs"
}

# ─────────────────────────────────────────────────────────────────────────────

main() {
  local want="${1:-all}"
  printf '%sai-tools test suite%s %s(%s)%s\n' "$BOLD" "$RESET" "$DIM" "$want" "$RESET"

  case "$want" in
    syntax)   test_syntax ;;
    install)  test_install ;;
    unit)     test_unit ;;
    validate) test_validate ;;
    rules)    test_rules ;;
    init)     test_init ;;
    wizard)   test_wizard ;;
    golden)   test_golden ;;
    hooks)    test_hooks ;;
    all)      test_syntax; test_install; test_unit; test_validate
              test_rules; test_init; test_wizard; test_golden; test_hooks ;;
    *)        printf 'unknown section: %s\n' "$want" >&2; exit 2 ;;
  esac

  printf '\n%s──────────────────────────────%s\n' "$DIM" "$RESET"
  if [ "$FAIL" -eq 0 ]; then
    printf '%s✓ %d passed%s\n\n' "$GREEN" "$PASS" "$RESET"
    return 0
  fi
  printf '%s✗ %d failed%s, %d passed\n\n' "$RED" "$FAIL" "$RESET" "$PASS"
  return 1
}

main "$@"
