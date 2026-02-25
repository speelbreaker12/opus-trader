#!/usr/bin/env bash
set -euo pipefail

# Unified review artifact logger.
#
# Dispatches to codex or opus review tools, captures transcript with
# provenance header and SHA256, writes to standard artifact path.
#
# Usage:
#   plans/review_logged.sh STORY_ID --tool codex [--commit REF | --base REF | --uncommitted] [--title TITLE]
#   plans/review_logged.sh STORY_ID --tool opus  [--base REF] [--title TITLE]

usage() {
  cat <<'EOF'
Usage:
  plans/review_logged.sh STORY_ID --tool <codex|opus|kimi> [options] [-- <extra tool args>]

Options:
  --tool TOOL        Required: codex, opus, or kimi
  --prompt STYLE     Prompt style: generic or enriched (default: enriched)
                     generic  = code-quality focus (SOLID, naming, doc, types)
                     enriched = contract-proof focus (ATs, premortem, fail-closed)
                     Run both for maximum coverage.
  --proof-graph      Generate per-reviewer proof_graph.json skeleton (requires --prompt enriched)
  --commit REF       Review a specific commit (default: HEAD)
  --base REF         Review diff from base to HEAD
  --uncommitted      Review uncommitted changes
  --files LIST       Review specific files (space/comma-separated paths; codex uses exec mode)
  --title TITLE      Review title (default: "<STORY_ID>: <TOOL> review")
  --out-root PATH    Override artifact root (default: artifacts/story)

Modes:
  codex --commit/--base/--uncommitted: uses built-in `codex review` (diff-only)
  codex --files:                       uses `codex exec` with review prompt (stdin)
  opus  --commit/--base/--uncommitted: uses `claude --print` with review prompt (stdin)
  opus  --files:                       uses `claude --print` with file contents (stdin)
  kimi  (all modes):                   uses `kimi --print` with review prompt (stdin)

Artifacts:
  - artifacts/story/<ID>/<tool>/<tool>.<style>.md  (canonical)
  - artifacts/story/<ID>/<tool>/<STAMP>_review.md  (legacy symlink)

Examples:
  plans/review_logged.sh S1-004 --tool codex --base run/slice1-clean
  plans/review_logged.sh S1-004 --tool codex --files "src/gate.rs src/risk.rs"
  plans/review_logged.sh S1-004 --tool opus --prompt enriched --files "src/gate.rs src/risk.rs"
  plans/review_logged.sh S1-004 --tool opus --prompt generic --files "src/gate.rs src/risk.rs"
  plans/review_logged.sh S1-004 --tool opus --proof-graph --files "src/gate.rs src/risk.rs"
  plans/review_logged.sh S1-004 --tool kimi --base main
  plans/review_logged.sh S1-004 --tool codex --commit HEAD -- --c model="o3"
EOF
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

safe_count() {
  local pattern="$1"
  local fallback="${2:-999}"
  set +e
  local count
  count="$(grep -coE "$pattern" "$transcript_tmp" 2>/dev/null || true)"
  local rc="$?"
  set -e
  count="$(printf '%s' "$count" | tr -d '[:space:]')"
  if [[ "$rc" -ne 0 || -z "$count" ]]; then
    echo "$fallback"
  else
    echo "$count"
  fi
}

json_int() {
  local raw="${1:-0}"
  raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo 0
  fi
}

count_review_citations() {
  local inline_count
  local markdown_count
  local total

  inline_count="$(safe_count '[A-Za-z0-9_./:-]+\.[A-Za-z0-9_]+:[0-9]+' 0)"
  markdown_count="$(awk '
    /^[[:space:]]*\*{0,2}File\*{0,2}:/ {
      c++
      pending=1
      next
    }
    {
      if (pending) {
        if ($0 ~ /^\*\*Line:\*\*[[:space:]]*[0-9]+/) {
          c++
          pending=0
        } else if ($0 !~ /^[[:space:]]*$/) {
          pending=0
        }
      }
    }
    END { print c+0 }
  ' "$transcript_tmp" 2>/dev/null || true)"

  inline_count="$(json_int "$inline_count")"
  markdown_count="$(json_int "$markdown_count")"
  total="$(( inline_count + markdown_count ))"
  echo "$total"
}

# Portable uppercase-first (zsh lacks ${var^})
ucfirst() { echo "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'; }

# Portable lowercase (zsh lacks ${var,,})
lcase() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# ── Build enriched review context from prd.json + CONTRACT.md + premortem ──
# Returns enriched text on stdout; empty string if prd.json absent.
build_enriched_context() {
  local story_id="$1"
  local root_dir="$2"
  local prd="$root_dir/plans/prd.json"
  local contract="$root_dir/specs/CONTRACT.md"
  local premortem="$root_dir/reviews/premortems/${story_id}_premortem.md"
  local enriched=""

  # ── 1. Extract story entry from prd.json ──
  if [[ -f "$prd" ]] && command -v jq >/dev/null 2>&1; then
    local story_json
    story_json="$(jq -r --arg id "$story_id" '.items[] | select(.id == $id)' "$prd" 2>/dev/null || true)"
    if [[ -n "$story_json" ]]; then
      local ats acceptance impl_tests
      ats="$(echo "$story_json" | jq -r '.enforcing_contract_ats // [] | join(", ")' 2>/dev/null || true)"
      acceptance="$(echo "$story_json" | jq -r '.acceptance // [] | .[] | "  - " + .' 2>/dev/null || true)"
      impl_tests="$(echo "$story_json" | jq -r '.implementation_tests // [] | .[] | "  - " + .' 2>/dev/null || true)"
      local description
      description="$(echo "$story_json" | jq -r '.description // ""' 2>/dev/null || true)"

      enriched+="
STORY CONTEXT (from prd.json)
- Description: ${description}
- Enforcing ATs: ${ats:-none}
"
      if [[ -n "$acceptance" ]]; then
        enriched+="- Acceptance criteria:
${acceptance}
"
      fi
      if [[ -n "$impl_tests" ]]; then
        enriched+="- Implementation tests:
${impl_tests}
"
      fi

      # ── 2. Extract AT clause text from CONTRACT.md ──
      if [[ -f "$contract" && -n "$ats" ]]; then
        enriched+="
CONTRACT CLAUSES (from specs/CONTRACT.md)
"
        local at_id
        for at_id in $(echo "$ats" | tr ',' ' '); do
          at_id="$(echo "$at_id" | tr -d '[:space:]')"
          if [[ -n "$at_id" ]]; then
            local at_text
            at_text="$(grep -A 5 "^${at_id}$" "$contract" 2>/dev/null | head -6 || true)"
            if [[ -n "$at_text" ]]; then
              enriched+="
${at_text}
"
            fi
          fi
        done
      fi
    fi
  fi

  # ── 3. Extract premortem key sections (§2 assumptions, §4 decisions, §5 wrong-impls) ──
  if [[ -f "$premortem" ]]; then
    enriched+="
PREMORTEM KEY SECTIONS (from ${story_id}_premortem.md)
"
    local section=""
    local capturing=false
    local lines_captured=0
    while IFS= read -r line; do
      if echo "$line" | grep -qE '^## §(2|4|5) '; then
        section="$line"
        capturing=true
        lines_captured=0
        enriched+="
${line}
"
      elif $capturing; then
        if echo "$line" | grep -qE '^## §'; then
          capturing=false
        elif [[ $lines_captured -lt 30 ]]; then
          enriched+="${line}
"
          lines_captured=$((lines_captured + 1))
        fi
      fi
    done < "$premortem"
  fi

  printf '%s' "$enriched"
}

story="${1:-}"
if [[ -z "$story" || "$story" == "-h" || "$story" == "--help" ]]; then
  usage
  exit 2
fi
shift

tool=""
prompt_style="enriched"
proof_graph=false
mode="commit"
commit="HEAD"
base=""
files_list=""
title=""
out_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      tool="${2:?missing tool name}"
      shift 2
      ;;
    --prompt)
      prompt_style="${2:?missing prompt style (generic|enriched)}"
      shift 2
      ;;
    --proof-graph)
      proof_graph=true
      shift 1
      ;;
    --commit)
      mode="commit"
      commit="${2:?missing ref}"
      shift 2
      ;;
    --base)
      mode="base"
      base="${2:?missing ref}"
      shift 2
      ;;
    --uncommitted)
      mode="uncommitted"
      shift 1
      ;;
    --files)
      mode="files"
      files_list="${2:?missing files list}"
      shift 2
      ;;
    --title)
      title="${2:?missing title}"
      shift 2
      ;;
    --out-root)
      out_root="${2:?missing path}"
      shift 2
      ;;
    --)
      shift
      extra=("$@")
      break
      ;;
    *)
      extra+=("$1")
      shift 1
      ;;
  esac
done

[[ -n "$tool" ]] || { echo "ERROR: --tool is required (codex, opus, or kimi)" >&2; exit 2; }
case "$tool" in
  codex|opus|kimi) ;;
  *) echo "ERROR: unknown tool '$tool' (expected: codex, opus, or kimi)" >&2; exit 2 ;;
esac
case "$prompt_style" in
  generic|enriched) ;;
  *) echo "ERROR: unknown --prompt '$prompt_style' (expected: generic or enriched)" >&2; exit 2 ;;
esac

# --proof-graph guards
if [[ "$proof_graph" == "true" ]]; then
  if [[ "$prompt_style" == "generic" ]]; then
    echo "ERROR: --proof-graph requires --prompt enriched (generic lacks AT/premortem context)" >&2
    exit 2
  fi
  if [[ "$tool" == "codex" && "$mode" != "files" ]]; then
    echo "ERROR: --proof-graph requires --tool opus|kimi or --tool codex --files (codex diff mode bypasses prompt injection)" >&2
    exit 2
  fi
fi

if [[ -z "$title" ]]; then
  title="$story: $(ucfirst "$tool") review"
fi

if [[ "$mode" == "base" && -z "$base" ]]; then
  echo "ERROR: --base requires a ref" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$root"

# Verify tool is available
case "$tool" in
  codex)
    command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found in PATH" >&2; exit 2; }
    ;;
  opus)
    command -v claude >/dev/null 2>&1 || { echo "ERROR: claude CLI not found in PATH" >&2; exit 2; }
    ;;
  kimi)
    command -v kimi >/dev/null 2>&1 || { echo "ERROR: kimi CLI not found in PATH" >&2; exit 2; }
    ;;
esac

if [[ "$out_root" = /* ]]; then
  outdir="$out_root/$story/$tool"
else
  outdir="$root/$out_root/$story/$tool"
fi
mkdir -p "$outdir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
ts_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stamp="${ts}_$$_${RANDOM}"

# Canonical filename: <tool>.<prompt_style>.md (per RUNBOOK §6.1)
# Legacy timestamped name kept as symlink for backwards compat.
canonical_name="${tool}.${prompt_style}.md"
outfile="$outdir/${canonical_name}"
legacy_name="${stamp}_review.md"
legacy_file="$outdir/${legacy_name}"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
head_sha="$(git rev-parse HEAD 2>/dev/null || echo "?")"

# ── Build tool-specific command ─────────────────────────────────────

cmd=()
prompt_tmp=""

# ── Build file contents for --files mode ────────────────────────────
files_context=""
if [[ "$mode" == "files" && -n "$files_list" ]]; then
  # Normalize: replace commas with spaces
  normalized_files="${files_list//,/ }"
  for f in $normalized_files; do
    if [[ -f "$f" ]]; then
      files_context+="
=== FILE: $f ===
$(cat "$f")
"
    else
      files_context+="
=== FILE: $f === (NOT FOUND)
"
    fi
  done
fi

# ── Build diff/files context (shared by opus, kimi, and codex --files) ──
diff_context=""
review_context_label="Diff"
codex_exec_mode=false
if [[ "$tool" == "opus" || "$tool" == "kimi" || ("$tool" == "codex" && "$mode" == "files") ]]; then
  case "$mode" in
    commit)
      resolved="$(git rev-parse "${commit}^{commit}" 2>/dev/null || true)"
      if [[ -n "$resolved" ]]; then
        if git rev-parse "${resolved}^" >/dev/null 2>&1; then
          diff_context="$(git diff "${resolved}^..${resolved}" 2>/dev/null || true)"
        else
          diff_context="$(git show --format= "${resolved}" 2>/dev/null || true)"
        fi
      fi
      ;;
    base)
      diff_context="$(git diff "${base}...HEAD" 2>/dev/null || true)"
      ;;
    uncommitted)
      diff_context="$(git diff HEAD 2>/dev/null || true)"
      ;;
    files)
      diff_context="$files_context"
      ;;
  esac
  [[ "$mode" == "files" ]] && review_context_label="Files to review"
fi

# ── Build review prompt (shared by opus and kimi) ─────────────────
build_review_prompt() {
  local style="$1"
  local ctx_label="$2"
  local diff_ctx="$3"

  if [[ "$style" == "generic" ]]; then
    cat <<PROMPT_EOF
You are a senior code reviewer for story $story on branch $branch (HEAD: $head_sha).

Review the following $(lcase "$ctx_label") and provide findings ordered by severity (P0-Critical, P1-High, P2-Medium, P3-Low).

Focus on:
- Correctness bugs and logic errors
- Safety violations (unwrap in production, silent error drops, fail-open paths)
- Missing or inadequate tests
- Contract violations (specs/CONTRACT.md)
- Security issues (injection, auth gaps, race conditions)
- Performance regressions
- Code quality (naming, doc comments, type precision, dead code, misleading fields)
- SOLID principles (SRP, OCP, LSP, ISP, DIP)

For each finding, include:
- File path and line number
- Severity level (P0-P3)
- Description of the issue
- Suggested fix

Title: $title

${ctx_label}:
\`\`\`
${diff_ctx:-(no content available)}
\`\`\`
PROMPT_EOF
  else
    # enriched: contract-proof audit with AT clauses, premortem, priorities
    local enriched_ctx
    enriched_ctx="$(build_enriched_context "$story" "$root")"
    cat <<PROMPT_EOF
You are a senior contract-proof code reviewer for story $story on branch $branch (HEAD: $head_sha).

This is a retroactive contract-proof audit of existing implementation.
Review the story proof scope: ATs, enforcement points, proving tests, premortem.
${enriched_ctx}

PRIORITIES (check in this order)

1. **Contract alignment (AT-by-AT)** — Does each claimed AT have a real proving test? Does it prove causality (dispatch_count, reject_reason, latch_reason), not just existence? Re-read the AT anchor text above — does the enforcement point implement the clause's *specific requirement*, or merely a prerequisite/side-effect?
2. **Paper compliance detection** — AT claimed in PRD but not causally proven? implementation_tests[] points to real tests? No fake "passes" logic?
3. **Fail-closed behavior** — For EACH input AND intermediate computation in enforcement functions: (1) Missing/None → reject? (2) NaN/Inf → reject? (3) Negative where unsigned expected → reject? (4) Out-of-domain (type::MAX, percentage > 1.0, timestamp beyond sane range) → reject? (5) Corrupt/garbage extreme values → reject or degrade? (6) Narrowing type casts (\`as i64\`, \`as u32\`) — is the source value bounded before the cast? "Invalid" means all six — not just NaN.
4. **Premortem conformance** — §4 decisions implemented as chosen? §5 wrong impls blocked by tightening tests? §2 assumptions turned into tests?
5. **Observability** — Reason code / structured log / metric on reject/degrade/latch paths?
6. **Pattern conformance** — Gates use real quantities, state transitions explicit, small blast radius (including deserialization: strict serde enums in batch-deserialized types must not poison sibling elements), idempotent where retries happen?
7. **Combinatorial coverage** — For functions with 2+ branching inputs (Option, enum, bool): are cross-cutting input combinations tested? Does one input's presence cause checks on other inputs to be skipped? For constants with magnitude comments, does the comment match the literal value?

For each finding, include:
- File path and line number
- Severity level (P0-Critical, P1-High, P2-Medium, P3-Low)
- Which PRIORITY it falls under (1-7)
- Description of the issue
- Suggested fix

Title: $title

${ctx_label}:
\`\`\`
${diff_ctx:-(no content available)}
\`\`\`
PROMPT_EOF
  fi

  # F-11: Inject proof graph skeleton into prompt when --proof-graph is active
  if [[ "${proof_graph:-}" == "true" && -f "${pg_skeleton:-}" ]]; then
    cat <<'PG_INSTR_EOF'

--- PROOF GRAPH ---
A proof_graph.json skeleton has been generated for this story.
For each AT entry in the `ats[]` array, fill the `at_verdict` block:

  "at_verdict": {
    "verdict": "<one of: PROVEN_INTEGRATED, PROVEN_UNIT, WEAK_PROOF, CLAIMED_NOT_PROVEN, UNTESTED_ENFORCEMENT, WRONG_IMPL_UNBLOCKED, FAIL_OPEN_RISK, MISSING, DEFERRED>",
    "severity": "<BLOCKING|HARDENING|INFO>",
    "rationale": "<one sentence explaining your verdict>"
  }

Also fill `enforcement.status` and `wiring.status` if you have evidence.
Leave other fields as-is (they are pre-populated from PRD + premortem).

Rules:
- DEFERRED = "I cannot evaluate this AT" (not "it's fine")
- If uncertain, use the MORE RESTRICTIVE verdict (fail-closed)
- Do NOT modify schema_version, head_sha, or story_meta

Skeleton content follows:
PG_INSTR_EOF
    cat "$pg_skeleton"
  fi
}

# ── Proof graph skeleton generation (before review) ───────────────
# NOTE: The flag is named --proof-graph (not --init-proof-graph) for brevity.
# It both generates the skeleton AND injects fill instructions into the prompt.
pg_skeleton=""
if [[ "$proof_graph" == "true" ]]; then
  pg_outdir="$outdir"  # artifacts/story/<ID>/<tool>/
  echo "Generating proof graph skeleton for $story (reviewer: $tool)..." >&2
  python3 "$root/python/proof_graph/init.py" "$story" \
    --prd-path "$root/plans/prd.json" \
    --contract-path "$root/specs/CONTRACT.md" \
    --premortem-dir "$root/artifacts/story/$story/" \
    --output-dir "$pg_outdir" >&2
  pg_skeleton="$pg_outdir/proof_graph.json"
  if [[ ! -f "$pg_skeleton" ]]; then
    echo "ERROR: proof_graph.json skeleton not created at $pg_skeleton" >&2
    exit 1
  fi
  echo "Proof graph skeleton: $pg_skeleton" >&2
fi

# ── Build tool-specific command ─────────────────────────────────────
case "$tool" in
  codex)
    if [[ "$mode" == "files" ]]; then
      # --files mode: use `codex exec` with review prompt piped via stdin
      prompt_tmp="$(mktemp)"
      build_review_prompt "$prompt_style" "$review_context_label" "$diff_context" > "$prompt_tmp"
      cmd=("codex" "exec")
      codex_exec_mode=true
    else
      # Standard diff modes: use built-in `codex review`
      cmd=("codex" "review" "--title" "$title")
      case "$mode" in
        commit)      cmd+=("--commit" "$commit") ;;
        base)        cmd+=("--base" "$base") ;;
        uncommitted) cmd+=("--uncommitted") ;;
      esac
    fi
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;

  opus)
    prompt_tmp="$(mktemp)"
    build_review_prompt "$prompt_style" "$review_context_label" "$diff_context" > "$prompt_tmp"

    cmd=("claude" "--model" "claude-opus-4-6" "--print" "--verbose")
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;

  kimi)
    prompt_tmp="$(mktemp)"
    build_review_prompt "$prompt_style" "$review_context_label" "$diff_context" > "$prompt_tmp"

    cmd=("kimi" "--print" "--final-message-only" "--model" "k2.5")
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;
esac

# ── Run review command ──────────────────────────────────────────────

transcript_tmp="$(mktemp)"
cleanup() {
  rm -f "$transcript_tmp" ${prompt_tmp:+"$prompt_tmp"} ${files_tmp:+"$files_tmp"}
}
trap cleanup EXIT

start_epoch="$(date +%s)"
set +e
if [[ -n "$prompt_tmp" ]]; then
  # opus always, kimi always, codex exec (--files mode): pipe prompt via stdin
  "${cmd[@]}" < "$prompt_tmp" 2>&1 | tee "$transcript_tmp"
else
  # codex review (built-in diff modes): no stdin
  "${cmd[@]}" 2>&1 | tee "$transcript_tmp"
fi
rc="${PIPESTATUS[0]}"
set -e
end_epoch="$(date +%s)"
duration_seconds="$((end_epoch - start_epoch))"

printf '\n' >> "$transcript_tmp"
transcript_hash="$(sha256_file "$transcript_tmp")"
transcript_bytes="$(wc -c < "$transcript_tmp" | tr -d '[:space:]')"

# ── Determine model name for provenance ───────────────────────────
model_name="n/a"
case "$tool" in
  codex) model_name="${CODEX_MODEL:-gpt-4.1}" ;;
  opus)  model_name="claude-opus-4-6" ;;
  kimi)  model_name="kimi-k2.5" ;;
esac

# ── Determine cycle and phase equivalent from context ─────────────
# Cycle detection: C2 if reviewing fix diff, C1 if story scope, SELF otherwise.
# Phase equivalent: R3 for C1, R7d for C2.
prov_cycle="C1"
prov_phase="R3"
prov_basis="STORY_SCOPE (Cycle 1)"
prov_basis_short="STORY_SCOPE"
if [[ "$mode" == "base" && -n "$base" ]]; then
  # Check if this looks like a Cycle 2 review (fix diff after cycle1)
  cycle1_receipt="$root/.wf/receipts/$story/03_cycle1.json"
  if [[ -f "$cycle1_receipt" ]]; then
    prov_cycle="C2"
    prov_phase="R7d"
    prov_basis="FIX_DIFF + AT_REGRESSION (Cycle 2)"
    prov_basis_short="FIX_DIFF_AT_REGRESSION"
  fi
fi

# ── Determine slice ID from story ID ─────────────────────────────
slice_id="$(echo "$story" | sed -n 's/^\([A-Z][A-Za-z0-9]*\)-.*/\1/p')"
slice_id="${slice_id:-UNKNOWN}"

# ── Write artifact with YAML front matter provenance ──────────────

{
  echo "---"
  echo "provenance:"
  echo "  tool: $tool"
  echo "  model: $model_name"
  echo "  prompt_style: $prompt_style"
  echo "  cycle: $prov_cycle"
  echo "  phase_equivalent: $prov_phase"
  echo "  review_basis: \"$prov_basis\""
  echo "  story_id: $story"
  echo "  slice_id: $slice_id"
  echo "  head_commit: \"$head_sha\""
  if [[ "$prov_cycle" == "C2" && "$mode" == "base" ]]; then
    echo "  base_commit: \"$base\""
  fi
  echo "  generated_at: \"$ts_iso\""
  echo "  artifact_provenance: \"logger-v2\""
  echo "  schema_version: \"review_markdown_header.v1\""
  echo "---"
  echo
  echo "# $(ucfirst "$tool") review"
  echo
  echo "- Story: $story"
  echo "- Timestamp (UTC): $ts"
  echo "- Branch: $branch"
  echo "- HEAD: $head_sha"
  echo "- Mode: $mode"
  if [[ "$mode" == "commit" ]]; then
    echo "- Commit ref: $commit"
  fi
  if [[ "$mode" == "base" ]]; then
    echo "- Base ref: $base"
  fi
  if [[ "$mode" == "files" ]]; then
    echo "- Files: $files_list"
  fi
  echo "- Model: $model_name"
  if [[ "${codex_exec_mode}" == "true" ]]; then
    echo "- Codex Mode: exec (prompt pass-through)"
  fi
  echo "- Prompt style: $prompt_style"
  echo "- Review basis: $prov_basis"
  echo "- Phase equivalent: $prov_phase"
  if [[ "$proof_graph" == "true" ]]; then
    echo "- Proof graph: $pg_skeleton"
  fi
  echo "- Command: ${cmd[*]}"
  echo "- Artifact Provenance: logger-v2"
  echo "- Generator Script: plans/review_logged.sh"
  echo "- Command Exit Code: $rc"
  echo "- Transcript SHA256: $transcript_hash"
  echo "- Transcript Bytes: $transcript_bytes"
  echo "- Duration Seconds: $duration_seconds"
  echo
  echo "<<<REVIEW_TRANSCRIPT_BEGIN>>>"
} > "$outfile"
cat "$transcript_tmp" >> "$outfile"
echo "<<<REVIEW_TRANSCRIPT_END>>>" >> "$outfile"

# Emit structured findings summary for deterministic gate parsing.
# Counts P0-P3 by matching "| P<N>" or "P<N>:" or "**P<N>**" patterns in transcript.
# Falls back to 999 if counting fails (fail-closed: assume findings exist).
p0="$(safe_count '\\bP0\\b' 999)"
p1="$(safe_count '\\bP1\\b' 999)"
p2="$(safe_count '\\bP2\\b' 999)"
echo "FINDINGS_SUMMARY: P0=$p0 P1=$p1 P2=$p2" >> "$outfile"

# ── Extract review_meta for deterministic gate checks ────────────────
# Scans transcript for file:line citations, classifies as enforcement vs test.
# This structured block is the source of truth for manifest checks —
# no heuristic prose scanning needed by downstream consumers.

enforcement_cites=()
test_cites=()

# Extract file:line or file:line::function patterns from transcript
while IFS= read -r cite; do
  [[ -z "$cite" ]] && continue
  if [[ "$cite" == *"/tests/"* || "$cite" == *"/test_"* ]]; then
    test_cites+=("$cite")
  else
    enforcement_cites+=("$cite")
  fi
done < <(grep -oE '[a-zA-Z0-9_/.:-]+\.rs:[0-9]+(::[ a-zA-Z0-9_]+)?' "$transcript_tmp" 2>/dev/null | sort -u || true)

# diff_only_review_rejected:
# enriched prompts explicitly request full contract-proof scope → rejected by construction.
# generic prompts → check if transcript explicitly mentions rejecting diff-only scope.
# fail-closed: if uncertain, treat as NOT rejected (conservative for R3 gate).
diff_rejected=false
if [[ "$prompt_style" == "enriched" ]]; then
  diff_rejected=true
elif grep -qiE '(reject.*diff.only|beyond.*diff|full.*scope|contract.proof|story.scope)' "$transcript_tmp" 2>/dev/null; then
  diff_rejected=true
fi

{
  echo ""
  echo "---"
  echo "review_meta:"
  echo "  evidence_citations:"
  if [[ ${#enforcement_cites[@]} -gt 0 ]]; then
    echo "    preexisting_enforcement:"
    for c in "${enforcement_cites[@]}"; do
      echo "      - \"$c\""
    done
  else
    echo "    preexisting_enforcement: []"
  fi
  if [[ ${#test_cites[@]} -gt 0 ]]; then
    echo "    preexisting_tests:"
    for c in "${test_cites[@]}"; do
      echo "      - \"$c\""
    done
  else
    echo "    preexisting_tests: []"
  fi
  echo "  checks:"
  echo "    diff_only_review_rejected: $diff_rejected"
  echo "---"
} >> "$outfile"

# ── Post-validation hard gates (v3.0) ──────────────────────────────
# These checks validate the generated artifact meets structural requirements.
# Artifact is still written (for debugging), but exit code is nonzero on failure.
gate_exit=0

# Gate 1: Missing "Review basis:" line in artifact (exit 3)
# Checks full artifact (header + transcript). Script injects basis in provenance
# header; gate validates it survived the write.
if ! grep -qi 'Review basis:' "$outfile" 2>/dev/null; then
  echo "HARD_GATE_FAIL: Missing 'Review basis:' line in review artifact" >&2
  echo "HARD_GATE: MISSING_REVIEW_BASIS (exit 3)" >> "$outfile"
  gate_exit=3
fi

# Gate 2: Missing pre-existing enforcement + test citations (Cycle 1 only, exit 4)
# Cycle 1 reviews MUST cite at least one pre-existing enforcement point or test.
# Uses authoritative cycle from provenance (not transcript-extracted).
if [[ "$gate_exit" -eq 0 && "$prov_cycle" == "C1" ]]; then
  # Require at least one file:line citation in the transcript (pattern: path/file.rs:123)
  citation_count="$(count_review_citations)"
  if [[ "$citation_count" -eq 0 ]]; then
    echo "HARD_GATE_FAIL: Cycle 1 review has zero file:line citations (pre-existing enforcement/test)" >&2
    echo "HARD_GATE: MISSING_PRE_EXISTING_CITATIONS (exit 4)" >> "$outfile"
    gate_exit=4
  fi
fi

# Gate 3: Missing "Phase equivalent:" label in artifact (exit 5)
# Checks full artifact. Script injects phase_equivalent in provenance header.
if [[ "$gate_exit" -eq 0 ]]; then
  if ! grep -qi 'Phase equivalent:' "$outfile" 2>/dev/null; then
    echo "HARD_GATE_FAIL: Missing 'Phase equivalent:' label in review artifact" >&2
    echo "HARD_GATE: MISSING_PHASE_EQUIVALENT (exit 5)" >> "$outfile"
    gate_exit=5
  fi
fi

# Gate 4: Sidecar validation (exit 6)
# If a sidecar schema exists for this review type, generate and validate sidecar.
if [[ "$gate_exit" -eq 0 ]]; then
  sidecar_schema="$root/specs/schemas/recon/review_artifact_sidecar.schema.json"
  validator="$root/plans/validate_recon_artifact.sh"
  if [[ -f "$sidecar_schema" && -x "$validator" ]]; then
    sidecar_file="${outfile%.md}.sidecar.json"
    # Use provenance fields computed earlier (authoritative, not transcript-extracted)
    citations_ct="$(count_review_citations)"
    citations_ct="$(json_int "$citations_ct")"
    p0="$(json_int "$p0")"
    p1="$(json_int "$p1")"
    p2="$(json_int "$p2")"

    # Build sidecar JSON with full provenance
    cat > "$sidecar_file" <<SIDECAR_EOF
{
  "schema_version": "review_artifact_sidecar.v1",
  "head_commit": "$head_sha",
  "created_at": "$ts_iso",
  "markdown_sha256": "$(sha256_file "$outfile")",
  "markdown_path": "$outfile",
  "story_id": "$story",
  "review_type": "external",
  "review_basis": "$prov_basis_short",
  "phase_equivalent": "$prov_phase",
  "tool": "$tool",
  "model": "$model_name",
  "prompt_style": "$prompt_style",
  "cycle": "$prov_cycle",
  "citations_count": $citations_ct,
  "pre_existing_citations_count": $citations_ct,
  "basis_line_present": true,
  "finding_counts": {
    "P0": $p0,
    "P1": $p1,
    "P2": $p2,
    "INFO": 0
  }
}
SIDECAR_EOF

    if ! "$validator" review_artifact_sidecar "$sidecar_file"; then
      echo "HARD_GATE_FAIL: Sidecar validation failed for $sidecar_file" >&2
      echo "HARD_GATE: SIDECAR_VALIDATION_FAILED (exit 6)" >> "$outfile"
      gate_exit=6
    else
      echo "Sidecar validated: $sidecar_file" >&2
    fi
  fi
fi

# Override exit code if any gate failed (artifact still written for debugging)
if [[ "$gate_exit" -ne 0 ]]; then
  rc="$gate_exit"
fi

# Run codex digest if available (codex only)
if [[ "$tool" == "codex" ]]; then
  digest_script="$root/plans/codex_review_digest.sh"
  if [[ -x "$digest_script" ]]; then
    if ! "$digest_script" "$outfile" >&2; then
      echo "WARN: failed to generate digest for $outfile" >&2
    fi
  fi
fi

# ── Normalize: copy to canonical path for deterministic pipeline lookup ──
# Canonical name: <tool>.<prompt_style>.md  (e.g., codex.enriched.md, opus.generic.md)
# This keeps review_logged.sh's timestamped filenames while providing a stable
# path that reconciliation validators and external manifest builders can rely on.
canonical_name="${tool}.${prompt_style}.md"
canonical_path="$outdir/$canonical_name"

# Overwrite any previous canonical file for this tool+prompt combo
cp "$outfile" "$canonical_path"
echo "Normalized: $canonical_path" >&2

echo "Saved $(ucfirst "$tool") review: $outfile (canonical: $canonical_name)" >&2
exit "$rc"
