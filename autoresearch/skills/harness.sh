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
#   harness.sh contract  <subcommand> [options]
# ─────────────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="$ROOT/autoresearch/skills"
PROGRAM_MD="$SKILLS_DIR/program.md"
EVALUATE_PY="$SKILLS_DIR/evaluate.py"
CONTRACT_DIR="$ROOT/autoresearch/contract"
CONTRACT_RENDER_PY="$CONTRACT_DIR/render_review.py"

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
  harness.sh baseline          <skill> [--tag TAG]
  harness.sh check-monotonic   <skill>
  harness.sh contract          <subcommand> [options]

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

  check-monotonic  Verify that all 'keep' entries in results.tsv have
             non-decreasing scores. Exits non-zero if any violation is
             found (guards against falsified prior-best rows).

  contract   Contract autoresearch namespace.
             Supported today:
               scaffold       Ensure the tracked contract tree and runtime dirs exist
               status         Summarize phase1/phase2 results.tsv and proposal index state
               render-review  Render review markdown and optional accepted-only patch

             Deferred commands fail closed with a deterministic message:
               phase1 run|baseline|eval
               phase2 run|baseline|eval
               refresh-common
               refresh-fixtures
               refresh-all

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
  ./autoresearch/skills/harness.sh contract status
  ./autoresearch/skills/harness.sh contract render-review --run-id demo-run
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
    find "$fixture_dir" -type f \( -name '*.diff' -o -name '*.txt' -o -name '*.md' \) | wc -l | tr -d ' '
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

ensure_tsv_header() {
  local path="$1"
  local header='commit	score	passed	total	status	description'
  mkdir -p "$(dirname "$path")"
  if [[ ! -f "$path" ]]; then
    printf '%s\n' "$header" > "$path"
    return
  fi
  if [[ ! -s "$path" ]]; then
    printf '%s\n' "$header" > "$path"
    return
  fi
  local first_line
  IFS= read -r first_line < "$path" || first_line=""
  if [[ "$first_line" != "$header" ]]; then
    fail "Refusing to rewrite unexpected results.tsv header in $path"
  fi
}

contract_usage() {
  cat <<'USAGE'
Contract autoresearch commands:
  harness.sh contract scaffold
  harness.sh contract status
  harness.sh contract render-review [--run-id RUN_ID] [--accepted-only] [--review PATH]

Deferred and fail-closed in the current manual-promotion slice:
  harness.sh contract phase1 run|baseline|eval
  harness.sh contract phase2 run|baseline|eval
  harness.sh contract refresh-common
  harness.sh contract refresh-fixtures
  harness.sh contract refresh-all
USAGE
}

require_contract_tree() {
  if [[ ! -d "$CONTRACT_DIR" ]]; then
    fail "Missing contract autoresearch tree: $CONTRACT_DIR"
  fi
  if [[ ! -f "$CONTRACT_DIR/phase1/findings.schema.json" ]]; then
    fail "Missing phase1 schema: $CONTRACT_DIR/phase1/findings.schema.json"
  fi
  if [[ ! -f "$CONTRACT_DIR/phase2/proposals.schema.json" ]]; then
    fail "Missing phase2 schema: $CONTRACT_DIR/phase2/proposals.schema.json"
  fi
  if [[ ! -f "$CONTRACT_DIR/phase2/review.schema.json" ]]; then
    fail "Missing phase2 review schema: $CONTRACT_DIR/phase2/review.schema.json"
  fi
}

summarize_results_file() {
  local label="$1"
  local path="$2"
  if [[ ! -f "$path" ]]; then
    info "  $label: missing results file"
    return
  fi
  local total_lines latest_score latest_status
  total_lines="$(tail -n +2 "$path" | wc -l | tr -d ' ')"
  if [[ "$total_lines" == "0" ]]; then
    info "  $label: 0 runs"
    return
  fi
  latest_score="$(tail -1 "$path" | awk -F'\t' '{print $2}')"
  latest_status="$(tail -1 "$path" | awk -F'\t' '{print $5}')"
  info "  $label: $total_lines runs, latest score=$latest_score status=$latest_status"
}

cmd_contract_scaffold() {
  [[ $# -eq 0 ]] || fail "contract scaffold takes no arguments"
  require_contract_tree
  log "Contract autoresearch scaffold"

  mkdir -p \
    "$CONTRACT_DIR/phase1/fixtures" \
    "$CONTRACT_DIR/phase1/outputs" \
    "$CONTRACT_DIR/phase2/fixtures/static" \
    "$CONTRACT_DIR/phase2/fixtures/snapshot" \
    "$CONTRACT_DIR/phase2/outputs" \
    "$CONTRACT_DIR/phase2/proposals" \
    "$CONTRACT_DIR/phase2/review"

  ensure_tsv_header "$CONTRACT_DIR/phase1/results.tsv"
  ensure_tsv_header "$CONTRACT_DIR/phase2/results.tsv"

  info "Contract tree ready:"
  info "  $CONTRACT_DIR/common"
  info "  $CONTRACT_DIR/phase1"
  info "  $CONTRACT_DIR/phase2"
}

cmd_contract_status() {
  [[ $# -eq 0 ]] || fail "contract status takes no arguments"
  require_contract_tree
  log "Contract autoresearch status"
  summarize_results_file "phase1" "$CONTRACT_DIR/phase1/results.tsv"
  summarize_results_file "phase2" "$CONTRACT_DIR/phase2/results.tsv"

  local index_file="$CONTRACT_DIR/phase2/proposals_index.json"
  if [[ -f "$index_file" ]]; then
    python3 - <<'PY' "$index_file"
import json
import sys
from collections import Counter

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
if isinstance(data, list):
    entries = data
elif isinstance(data, dict):
    if "entries" in data:
        entries = data["entries"]
    elif "runs" in data:
        entries = data["runs"]
    else:
        raise SystemExit("FAIL: proposals_index.json must contain an entries or runs array")
else:
    raise SystemExit("FAIL: proposals_index.json must be an array or object")
if not isinstance(entries, list):
    raise SystemExit("FAIL: proposals_index.json entries/runs must be a JSON array")
statuses = Counter()
for entry in entries:
    if not isinstance(entry, dict):
        raise SystemExit("FAIL: proposals_index.json contains a non-object entry")
    statuses[entry.get("status", "unknown")] += 1
print("  proposals_index entries:", len(entries))
if statuses:
    print("  proposals_index status_counts:", ", ".join(f"{k}={v}" for k, v in sorted(statuses.items())))
PY
  else
    info "  proposals_index: missing"
  fi
}

cmd_contract_render_review() {
  require_contract_tree
  [[ -f "$CONTRACT_RENDER_PY" ]] || fail "Missing renderer: $CONTRACT_RENDER_PY"

  local args=("--root" "$ROOT")
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id)
        [[ $# -ge 2 ]] || fail "Missing value for --run-id"
        args+=("$1" "$2")
        shift 2
        ;;
      --review)
        [[ $# -ge 2 ]] || fail "Missing value for --review"
        args+=("$1" "$2")
        shift 2
        ;;
      --accepted-only)
        args+=("$1")
        shift
        ;;
      *)
        fail "Unknown contract render-review option: $1"
        ;;
    esac
  done

  python3 "$CONTRACT_RENDER_PY" "${args[@]}"
}

contract_deferred_fail() {
  fail "contract $* is deferred in the current manual-promotion slice. Available today: scaffold, status, render-review."
}

cmd_contract() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    scaffold)      cmd_contract_scaffold "$@" ;;
    status)        cmd_contract_status "$@" ;;
    render-review) cmd_contract_render_review "$@" ;;
    phase1)
      case "${1:-}" in
        run|baseline|eval) contract_deferred_fail "phase1 ${1:-}" ;;
        *) contract_usage; fail "Unknown contract phase1 subcommand: ${1:-}" ;;
      esac
      ;;
    phase2)
      case "${1:-}" in
        run|baseline|eval) contract_deferred_fail "phase2 ${1:-}" ;;
        *) contract_usage; fail "Unknown contract phase2 subcommand: ${1:-}" ;;
      esac
      ;;
    refresh-common|refresh-fixtures|refresh-all)
      contract_deferred_fail "$subcommand"
      ;;
    ""|-h|--help)
      contract_usage
      ;;
    *)
      contract_usage
      fail "Unknown contract subcommand: $subcommand"
      ;;
  esac
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
- NEVER falsify results.tsv — scores for 'keep' entries must be strictly non-decreasing
- NEVER STOP — keep looping until perfect score or manually interrupted
PROMPT
  )"

  info "Creating branch and launching Claude..."
  git checkout -b "$branch" 2>/dev/null || git checkout "$branch"

  # Launch Claude with the prompt. Do NOT use exec so the shell remains alive
  # to catch crashes — a clean exit means Claude finished normally, a non-zero
  # exit means it crashed (which should be logged as status=crash by the agent).
  claude --model "$model" -p "$launch_prompt"
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

  local eval_json results_file output_dir short_head
  eval_json="$SKILLS_DIR/$skill/eval.json"
  results_file="$SKILLS_DIR/$skill/results.tsv"
  output_dir="$SKILLS_DIR/$skill/outputs/baseline-$tag"
  short_head="$(git rev-parse --short HEAD)"

  log "Running baseline for skill: $skill"
  info "Output dir: $output_dir"
  echo ""

  mkdir -p "$output_dir"

  # Baselines must reflect the current skill behavior, not cached prior outputs.
  generate_skill_outputs "$skill" "$output_dir" "$model" 1

  # Score mechanically via evaluate.py — never self-attested
  if [[ ! -f "$EVALUATE_PY" ]]; then
    fail "Evaluator not found: $EVALUATE_PY"
  fi

  local score_json score passed total
  score_json="$(python3 "$EVALUATE_PY" \
    --eval "$eval_json" \
    --output-dir "$output_dir" \
    --skill-dir "$SKILLS_DIR/$skill" \
    --json)"

  score="$(printf '%s' "$score_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['score'])")"
  passed="$(printf '%s' "$score_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['passed'])")"
  total="$(printf '%s' "$score_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['total'])")"

  # Append mechanical score row to results.tsv
  ensure_tsv_header "$results_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$short_head" "$score" "$passed" "$total" "baseline" "baseline - no changes" \
    >> "$results_file"

  log "Baseline recorded"
  info "Score: $score ($passed/$total)"
}

# ── Helper: generate outputs via Claude ──────────────────────────────
# generate_skill_outputs <skill> <output_dir> <model>
# For each test in eval.json, invokes Claude to produce an output file.
# Skips tests whose output file already exists and is non-empty.

generate_skill_outputs() {
  local skill="$1"
  local output_dir="$2"
  local model="${3:-sonnet}"
  local force_regenerate="${4:-0}"
  local eval_json="$SKILLS_DIR/$skill/eval.json"
  local skill_file
  skill_file="$(require_skill_file "$skill")"

  log "Generating outputs via Claude"
  info "Skill:      $skill_file"
  info "Output dir: $output_dir"
  echo ""

  # Read test IDs and fixtures from eval.json.
  # Replace tabs in prompt to prevent IFS-split corruption.
  local test_ids
  test_ids="$(python3 -c "
import json
with open('$eval_json') as f:
    data = json.load(f)
for t in data['tests']:
    prompt = t.get('prompt', '').replace('\t', ' ')
    print(t['id'] + '\t' + t.get('fixture', '') + '\t' + prompt)
")"

  while IFS=$'\t' read -r test_id fixture prompt; do
    # Strip any residual tabs that survived the Python sanitisation
    prompt="${prompt//$'\t'/ }"
    local fixture_path="$SKILLS_DIR/$skill/$fixture"
    local output_file="$output_dir/${test_id}.md"

    if [[ "$force_regenerate" -ne 1 ]] && [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
      info "  [$test_id] Output exists, skipping (delete to regenerate)"
      continue
    fi

    if [[ ! -f "$fixture_path" ]]; then
      warn "  [$test_id] Fixture not found: $fixture_path"
      continue
    fi

    info "  [$test_id] Generating output..."

    local fixture_content gen_prompt fence context_label
    fixture_content="$(cat "$fixture_path")"

    # Choose fence type and context label based on fixture extension.
    # .diff files are git diffs; .txt/.md are plain context (e.g. story content).
    case "$fixture" in
      *.diff) fence="diff";     context_label="diff" ;;
      *.md)   fence="markdown"; context_label="content" ;;
      *)      fence="text";     context_label="content" ;;
    esac

    gen_prompt="Read the skill file: $skill_file
Follow its instructions exactly to review this ${context_label}:

\`\`\`${fence}
$fixture_content
\`\`\`

$prompt

Produce the complete skill output as specified in the skill file."

    local stderr_file
    stderr_file="$(mktemp)"
    claude --model "$model" -p "$gen_prompt" > "$output_file" 2>"$stderr_file" || {
      warn "  [$test_id] Claude invocation failed"
      [[ -s "$stderr_file" ]] && warn "  [$test_id] Error: $(cat "$stderr_file")"
      rm -f "$output_file"
    }
    rm -f "$stderr_file"
  done <<< "$test_ids"

  echo ""
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
  local eval_json
  eval_json="$SKILLS_DIR/$skill/eval.json"

  mkdir -p "$output_dir"

  [[ "$generate" -eq 1 ]] && generate_skill_outputs "$skill" "$output_dir" "$model"

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

# ── Command: check-monotonic ─────────────────────────────────────────

cmd_check_monotonic() {
  local skill="$1"
  require_skill_dir "$skill"

  local results_file="$SKILLS_DIR/$skill/results.tsv"
  if [[ ! -f "$results_file" ]]; then
    fail "No results.tsv for skill '$skill'"
  fi

  log "Checking monotonicity of 'keep' entries: $skill"

  # Extract scores for rows where status == "keep", in file order
  local violations=0
  local prev_score=""
  local line_num=1
  while IFS=$'\t' read -r commit score passed total status _description; do
    ((line_num++)) || true
    [[ "$status" != "keep" ]] && continue
    if [[ -n "$prev_score" ]]; then
      local compare_rc=0
      set +e
      awk -v current="$score" -v previous="$prev_score" '
        BEGIN {
          numeric = "^-?[0-9]+([.][0-9]+)?$"
          if (current !~ numeric || previous !~ numeric) {
            exit 2
          }
          exit !(current < previous)
        }
      '
      compare_rc=$?
      set -e
      if [[ "$compare_rc" -eq 2 ]]; then
        fail "invalid numeric score in keep rows near line $line_num: current='$score' previous='$prev_score'"
      elif [[ "$compare_rc" -ne 0 && "$compare_rc" -ne 1 ]]; then
        fail "monotonicity comparison failed near line $line_num"
      elif [[ "$compare_rc" -eq 0 ]]; then
        warn "  Line $line_num: score $score < prior keep $prev_score (commit $commit)"
        ((violations++)) || true
      fi
    fi
    prev_score="$score"
  done < <(tail -n +2 "$results_file")

  if [[ "$violations" -gt 0 ]]; then
    fail "Monotonicity violated: $violations 'keep' row(s) have lower score than a prior keep — results.tsv may have been falsified"
  fi

  info "OK — all 'keep' entries have non-decreasing scores"
}

# ── Main ─────────────────────────────────────────────────────────────

if [[ "${1:-}" == "contract" ]]; then
  shift
  cmd_contract "$@"
  exit 0
fi

if [[ $# -lt 2 ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "-h" ]]; then
  usage
fi

COMMAND="${1:-}"
SKILL="${2:-}"

case "$COMMAND" in
  run)              shift 2; cmd_run "$SKILL" "$@" ;;
  scaffold)         cmd_scaffold "$SKILL" ;;
  status)           cmd_status "$SKILL" ;;
  eval)             shift 2; cmd_eval "$SKILL" "$@" ;;
  baseline)         shift 2; cmd_baseline "$SKILL" "$@" ;;
  check-monotonic)  cmd_check_monotonic "$SKILL" ;;
  -h|--help)        usage ;;
  *)                fail "Unknown command: $COMMAND. Run with --help for usage." ;;
esac
