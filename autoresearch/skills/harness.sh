#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────
# Skill Auto-Research Harness
# Karpathy-style self-improvement loop for Claude Code skills.
#
# Usage:
#   harness.sh run       <skill> [--tag TAG] [--model MODEL]
#   harness.sh scaffold  <skill>
#   harness.sh status    <skill>
#   harness.sh eval      <skill> [--output-dir DIR] [--generate]
#   harness.sh baseline  <skill> [--tag TAG]
# ─────────────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="$ROOT/autoresearch/skills"
PROGRAM_MD="$SKILLS_DIR/program.md"
EVALUATE_PY="$SKILLS_DIR/evaluate.py"

# ── Colors ───────────────────────────────────────────────────────────
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"
BOLD="${BOLD:-\033[1m}"
NC="${NC:-\033[0m}"

log()  { echo -e "\n${GREEN}=== $* ===${NC}"; }
info() { echo -e "${CYAN}$*${NC}"; }
warn() { echo -e "${YELLOW}WARN: $*${NC}" >&2; }
fail() { echo -e "${RED}FAIL: $*${NC}" >&2; exit 1; }

# ── Usage ────────────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
Skill Auto-Research Harness
Karpathy-style self-improvement loop for Claude Code skills.

Usage:
  harness.sh run       <skill> [--tag TAG] [--model MODEL]
  harness.sh scaffold  <skill>
  harness.sh status    <skill>
  harness.sh eval      <skill> [--output-dir DIR] [--generate]
  harness.sh baseline  <skill> [--tag TAG]

Commands:
  run        Launch the autonomous improvement loop via Claude Code.
             Creates a git branch, invokes Claude with program.md.
             Runs until interrupted or perfect score.

  scaffold   Create eval structure for a skill (eval.json, fixtures/).
             Reads SKILLS/<skill>.md and generates assertion templates.

  status     Show results.tsv summary for a skill — iterations,
             best score, kept changes, current pass rate.

  eval       Run objective evaluation outside of the loop.
             --generate invokes Claude per test to produce outputs.
             Without --generate, scores existing output files.

  baseline   Run all tests once against the current skill (no changes).
             Records the baseline score in results.tsv.

Options:
  --tag TAG      Branch tag (default: today's date, e.g. mar13)
  --model MODEL  Claude model to use (default: sonnet)
  --output-dir   Directory for eval outputs (default: <skill>/outputs/)
  --generate     Generate outputs via claude -p (costs API credits)

Examples:
  ./autoresearch/skills/harness.sh scaffold pr-review
  ./autoresearch/skills/harness.sh run contract-review --tag mar13
  ./autoresearch/skills/harness.sh status contract-review
  ./autoresearch/skills/harness.sh eval contract-review --generate
USAGE
  exit 1
}

# ── Helpers ──────────────────────────────────────────────────────────

require_skill_dir() {
  local skill="$1"
  local skill_eval_dir="$SKILLS_DIR/$skill"
  if [[ ! -d "$skill_eval_dir" ]]; then
    fail "No eval directory for skill '$skill'. Run: harness.sh scaffold $skill"
  fi
  if [[ ! -f "$skill_eval_dir/eval.json" ]]; then
    fail "Missing eval.json for skill '$skill'. Run: harness.sh scaffold $skill"
  fi
}

require_skill_file() {
  local skill="$1"
  local skill_file="$ROOT/SKILLS/$skill.md"
  if [[ ! -f "$skill_file" ]]; then
    # Check subdirectory pattern (SKILLS/skill-name/SKILL.md)
    skill_file="$ROOT/SKILLS/$skill/SKILL.md"
    if [[ ! -f "$skill_file" ]]; then
      fail "Skill file not found: SKILLS/$skill.md or SKILLS/$skill/SKILL.md"
    fi
  fi
  echo "$skill_file"
}

today_tag() {
  date +"%b%d" | tr '[:upper:]' '[:lower:]'
}

count_fixtures() {
  local skill="$1"
  local fixture_dir="$SKILLS_DIR/$skill/fixtures"
  if [[ -d "$fixture_dir" ]]; then
    find "$fixture_dir" -type f -name '*.diff' -o -name '*.txt' -o -name '*.md' | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

count_assertions() {
  local skill="$1"
  python3 -c "
import json, sys
with open('$SKILLS_DIR/$skill/eval.json') as f:
    data = json.load(f)
total = sum(len(t.get('assertions', [])) for t in data.get('tests', []))
print(total)
" 2>/dev/null || echo "?"
}

# ── Command: scaffold ────────────────────────────────────────────────

cmd_scaffold() {
  local skill="$1"
  local skill_file
  skill_file="$(require_skill_file "$skill")"

  local eval_dir="$SKILLS_DIR/$skill"

  if [[ -d "$eval_dir" ]] && [[ -f "$eval_dir/eval.json" ]]; then
    warn "Eval directory already exists: $eval_dir"
    warn "To regenerate, remove it first: rm -rf $eval_dir"
    exit 2
  fi

  log "Scaffolding eval for skill: $skill"
  mkdir -p "$eval_dir/fixtures" "$eval_dir/outputs"

  # Create eval.json template
  local skill_escaped="$skill"
  python3 -c "
import json
template = {
    'skill': 'SKILLS/${skill_escaped}.md',
    'description': 'Binary assertion tests for /${skill_escaped} skill output quality',
    'total_assertions': 0,
    'tests': [{
        'id': 'T1',
        'name': 'example_test',
        'description': 'Describe what this test validates',
        'fixture': 'fixtures/example.diff',
        'prompt': 'Run /${skill_escaped} on this diff.',
        'assertions': [{
            'id': 'T1-A1',
            'check': 'Output contains expected header',
            'rule': {'type': 'contains', 'value': 'REPLACE_ME'},
            'expected': True
        }]
    }]
}
print(json.dumps(template, indent=2))
" > "$eval_dir/eval.json"

  # Create results.tsv
  printf 'commit\tscore\tpassed\ttotal\tstatus\tdescription\n' > "$eval_dir/results.tsv"

  # Create example fixture
  cat > "$eval_dir/fixtures/example.diff" <<'FIXTURE'
diff --git a/example.rs b/example.rs
index 0000000..1111111 100644
--- a/example.rs
+++ b/example.rs
@@ -1,3 +1,3 @@
-fn old_name() -> bool {
+fn new_name() -> bool {
     true
 }
FIXTURE

  info "Created:"
  info "  $eval_dir/eval.json        — edit assertions here"
  info "  $eval_dir/fixtures/         — add test diffs here"
  info "  $eval_dir/outputs/          — generated outputs go here"
  info "  $eval_dir/results.tsv       — score tracking"
  echo ""
  info "Next steps:"
  info "  1. Edit eval.json — add test scenarios with binary assertions"
  info "  2. Add fixture diffs to fixtures/"
  info "  3. Run: harness.sh baseline $skill"
  info "  4. Run: harness.sh run $skill"
  echo ""
  info "Tip: Ask Claude to generate assertions from your skill:"
  info "  claude -p \"Read SKILLS/$skill.md and create binary assertions"
  info "  for autoresearch/skills/$skill/eval.json. Use the format from"
  info "  autoresearch/skills/contract-review/eval.json as a template.\""
}

# ── Command: run ─────────────────────────────────────────────────────

cmd_run() {
  local skill="$1"
  shift
  local tag model
  tag="$(today_tag)"
  model="sonnet"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)   tag="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  require_skill_dir "$skill"
  local skill_file
  skill_file="$(require_skill_file "$skill")"

  local branch="skill-autoresearch/${skill}-${tag}"
  local n_fixtures n_assertions
  n_fixtures="$(count_fixtures "$skill")"
  n_assertions="$(count_assertions "$skill")"

  log "Launching auto-research loop"
  info "Skill:       $skill"
  info "Skill file:  $skill_file"
  info "Branch:      $branch"
  info "Model:       $model"
  info "Fixtures:    $n_fixtures"
  info "Assertions:  $n_assertions"
  echo ""

  # Check branch doesn't already exist
  if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    warn "Branch '$branch' already exists."
    info "To resume, switch to it manually. To restart, delete it first."
    info "  git branch -D $branch"
    exit 2
  fi

  # Build the launch prompt
  local launch_prompt
  launch_prompt="$(cat <<PROMPT
You are an autonomous skill improvement agent. Follow these instructions exactly:

1. Read the loop protocol: autoresearch/skills/program.md
2. Read the eval config: autoresearch/skills/$skill/eval.json
3. Read the current skill file: $skill_file
4. Read ALL fixture files in autoresearch/skills/$skill/fixtures/

Then execute the auto-research loop as described in program.md.
Target skill: $skill
Run tag: $tag

CRITICAL RULES:
- Only modify the skill file ($skill_file) — never touch eval.json or fixtures
- ONE change per iteration
- Binary assertions must be checked literally
- Never weaken safety semantics to improve score
- Log every iteration to autoresearch/skills/$skill/results.tsv
- NEVER STOP — keep looping until perfect score or manually interrupted
PROMPT
  )"

  info "Creating branch and launching Claude..."
  git checkout -b "$branch" 2>/dev/null || git checkout "$branch"

  # Launch Claude with the prompt
  exec claude --model "$model" -p "$launch_prompt"
}

# ── Command: baseline ────────────────────────────────────────────────

cmd_baseline() {
  local skill="$1"
  shift
  local tag model
  tag="$(today_tag)"
  model="sonnet"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)   tag="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  require_skill_dir "$skill"
  local skill_file
  skill_file="$(require_skill_file "$skill")"
  local n_assertions
  n_assertions="$(count_assertions "$skill")"

  log "Running baseline for skill: $skill"
  info "Assertions: $n_assertions"
  echo ""

  local short_head
  short_head="$(git rev-parse --short HEAD)"

  local baseline_prompt="You are evaluating a skill's baseline score. Follow these steps:

1. Read the eval config: autoresearch/skills/${skill}/eval.json
2. Read the current skill file: ${skill_file}
3. Read ALL fixture files in autoresearch/skills/${skill}/fixtures/

For each test in eval.json:
  a) Read the fixture diff
  b) Execute the skill: follow the skill instructions exactly as written, producing full output
  c) Check each assertion (binary: TRUE or FALSE) against your output

Report:
- Total score: passed / total
- Per-test breakdown (test id, name, passed/total, failed assertion IDs)
- Overall pass rate as a percentage

Append the baseline to autoresearch/skills/${skill}/results.tsv:
  commit: ${short_head}
  score: (calculated)
  passed: (count)
  total: ${n_assertions}
  status: baseline
  description: baseline - no changes

Do NOT modify any files except results.tsv."

  exec claude --model "$model" -p "$baseline_prompt"
}

# ── Command: eval ────────────────────────────────────────────────────

cmd_eval() {
  local skill="$1"
  shift
  local output_dir generate model
  output_dir="$SKILLS_DIR/$skill/outputs"
  generate=0
  model="sonnet"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-dir) output_dir="$2"; shift 2 ;;
      --generate)   generate=1; shift ;;
      --model)      model="$2"; shift 2 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  require_skill_dir "$skill"
  local skill_file eval_json
  skill_file="$(require_skill_file "$skill")"
  eval_json="$SKILLS_DIR/$skill/eval.json"

  mkdir -p "$output_dir"

  if [[ "$generate" -eq 1 ]]; then
    log "Generating outputs via Claude"
    info "Skill:      $skill_file"
    info "Output dir: $output_dir"
    echo ""

    # Read test IDs and fixtures from eval.json
    local test_ids
    test_ids="$(python3 -c "
import json
with open('$eval_json') as f:
    data = json.load(f)
for t in data['tests']:
    print(t['id'] + '\t' + t.get('fixture', '') + '\t' + t.get('prompt', ''))
")"

    while IFS=$'\t' read -r test_id fixture prompt; do
      local fixture_path="$SKILLS_DIR/$skill/$fixture"
      local output_file="$output_dir/${test_id}.md"

      if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
        info "  [$test_id] Output exists, skipping (delete to regenerate)"
        continue
      fi

      if [[ ! -f "$fixture_path" ]]; then
        warn "  [$test_id] Fixture not found: $fixture_path"
        continue
      fi

      info "  [$test_id] Generating output..."

      local fixture_content
      fixture_content="$(cat "$fixture_path")"

      local gen_prompt
      gen_prompt="Read the skill file: $skill_file
Follow its instructions exactly to review this diff:

\`\`\`diff
$fixture_content
\`\`\`

$prompt

Produce the complete skill output as specified in the skill file."

      claude --model "$model" -p "$gen_prompt" > "$output_file" 2>/dev/null || {
        warn "  [$test_id] Claude invocation failed"
        rm -f "$output_file"
      }
    done <<< "$test_ids"

    echo ""
  fi

  # Run programmatic evaluation
  log "Evaluating outputs"

  if [[ ! -f "$EVALUATE_PY" ]]; then
    fail "Evaluator not found: $EVALUATE_PY"
  fi

  python3 "$EVALUATE_PY" \
    --eval "$eval_json" \
    --output-dir "$output_dir" \
    --skill-dir "$SKILLS_DIR/$skill"
}

# ── Command: status ──────────────────────────────────────────────────

cmd_status() {
  local skill="$1"
  require_skill_dir "$skill"

  local results_file="$SKILLS_DIR/$skill/results.tsv"

  if [[ ! -f "$results_file" ]]; then
    fail "No results.tsv for skill '$skill'"
  fi

  local total_lines
  total_lines="$(tail -n +2 "$results_file" | wc -l | tr -d ' ')"

  if [[ "$total_lines" -eq 0 ]]; then
    info "No results yet for skill '$skill'. Run: harness.sh baseline $skill"
    exit 0
  fi

  log "Auto-Research Status: $skill"
  echo ""

  # Parse results
  local best_score best_commit kept_count discarded_count crash_count
  best_score="$(tail -n +2 "$results_file" | awk -F'\t' '{print $2}' | sort -rn | head -1)"
  best_commit="$(tail -n +2 "$results_file" | awk -F'\t' -v s="$best_score" '$2 == s {print $1; exit}')"
  kept_count="$(tail -n +2 "$results_file" | awk -F'\t' '$5 == "keep"' | wc -l | tr -d ' ')"
  discarded_count="$(tail -n +2 "$results_file" | awk -F'\t' '$5 == "discard"' | wc -l | tr -d ' ')"
  crash_count="$(tail -n +2 "$results_file" | awk -F'\t' '$5 == "crash"' | wc -l | tr -d ' ')"

  local latest_score latest_status
  latest_score="$(tail -1 "$results_file" | awk -F'\t' '{print $2}')"
  latest_status="$(tail -1 "$results_file" | awk -F'\t' '{print $5}')"

  # Display
  printf "  ${BOLD}Iterations:${NC}  %s total (%s kept, %s discarded, %s crashed)\n" \
    "$total_lines" "$kept_count" "$discarded_count" "$crash_count"
  printf "  ${BOLD}Best score:${NC}  %s (commit %s)\n" "$best_score" "$best_commit"
  printf "  ${BOLD}Latest:${NC}      %s (%s)\n" "$latest_score" "$latest_status"
  echo ""

  # Show last 10 entries
  info "Recent results:"
  echo -e "  ${BOLD}commit\tscore\tpassed\ttotal\tstatus\tdescription${NC}"
  tail -n 10 "$results_file" | tail -n +1 | while IFS=$'\t' read -r c s p t st d; do
    local color="$NC"
    case "$st" in
      keep)     color="$GREEN" ;;
      discard)  color="$YELLOW" ;;
      crash)    color="$RED" ;;
      baseline) color="$CYAN" ;;
    esac
    printf "  ${color}%s\t%s\t%s\t%s\t%s\t%s${NC}\n" "$c" "$s" "$p" "$t" "$st" "$d"
  done
  echo ""

  # Show improvement trajectory
  if [[ "$total_lines" -ge 2 ]]; then
    local first_score
    first_score="$(tail -n +2 "$results_file" | head -1 | awk -F'\t' '{print $2}')"
    info "Trajectory: $first_score -> $latest_score (best: $best_score)"
  fi
}

# ── Main ─────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "-h" ]]; then
  usage
fi

COMMAND="${1:-}"
SKILL="${2:-}"

case "$COMMAND" in
  run)       shift 2; cmd_run "$SKILL" "$@" ;;
  scaffold)  cmd_scaffold "$SKILL" ;;
  status)    cmd_status "$SKILL" ;;
  eval)      shift 2; cmd_eval "$SKILL" "$@" ;;
  baseline)  shift 2; cmd_baseline "$SKILL" "$@" ;;
  -h|--help) usage ;;
  *)         fail "Unknown command: $COMMAND. Run with --help for usage." ;;
esac
