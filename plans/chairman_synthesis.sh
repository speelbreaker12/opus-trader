#!/usr/bin/env bash
set -euo pipefail

# chairman_synthesis.sh — synthesize parallel review artifacts into one prioritized finding list.
#
# Reads all <tool>/<tool>.<style>.md artifacts under a review run directory,
# feeds them to a chairman model, and writes:
#   <run_dir>/chairman/chairman.md          — prose synthesis with consensus annotations
#   <run_dir>/chairman/chairman.sidecar.json — machine-readable finding list with consensus counts
#
# Usage:
#   plans/chairman_synthesis.sh <RUN_DIR> [options]
#
# Arguments:
#   RUN_DIR    Path to review run directory (e.g. artifacts/story/<RUN_ID>)
#              Can be absolute or relative to repo root.
#
# Options:
#   --tool TOOL      Chairman model: sonnet or opus (default: opus)
#   --style STYLE    Which prompt-style artifacts to read: generic or enriched (default: enriched)
#   --dry-run        Print prompt to stdout without calling the model
#
# Exit codes:
#   0 — synthesis complete
#   1 — chairman model failed
#   2 — usage error or missing artifacts

usage() {
  sed -n '4,/^$/{ s/^# //; s/^#$//; p; }' "$0" >&2
}

die() { echo "ERROR: $*" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"

# ── Argument parsing ─────────────────────────────────────────────────
[[ $# -ge 1 ]] || { usage; exit 2; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }

RUN_DIR_ARG="$1"; shift

CHAIRMAN_TOOL="opus"
STYLE="enriched"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)    CHAIRMAN_TOOL="${2:?missing tool}"; shift 2 ;;
    --style)   STYLE="${2:?missing style}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$CHAIRMAN_TOOL" in
  sonnet|opus) ;;
  *) die "--tool must be sonnet or opus (got: $CHAIRMAN_TOOL)" ;;
esac
case "$STYLE" in
  generic|enriched) ;;
  *) die "--style must be generic or enriched (got: $STYLE)" ;;
esac

# ── Resolve model ID early (used by dry-run and real run) ────────────
case "$CHAIRMAN_TOOL" in
  sonnet) model_id="claude-sonnet-4-6" ;;
  opus)   model_id="claude-opus-4-6" ;;
esac

# Resolve RUN_DIR
if [[ "$RUN_DIR_ARG" = /* ]]; then
  RUN_DIR="$RUN_DIR_ARG"
else
  RUN_DIR="$ROOT/$RUN_DIR_ARG"
fi
[[ -d "$RUN_DIR" ]] || die "run directory not found: $RUN_DIR"

# ── Discover reviewer artifacts ──────────────────────────────────────
KNOWN_TOOLS=(codex sonnet opus kimi gemini)
ARTIFACTS=()
TOOLS_FOUND=()

for tool in "${KNOWN_TOOLS[@]}"; do
  artifact="$RUN_DIR/$tool/${tool}.${STYLE}.md"
  if [[ -f "$artifact" ]]; then
    ARTIFACTS+=("$artifact")
    TOOLS_FOUND+=("$tool")
  fi
done

[[ ${#ARTIFACTS[@]} -ge 2 ]] || die "need at least 2 reviewer artifacts in $RUN_DIR (found ${#ARTIFACTS[@]})"

echo "Chairman synthesis"
echo "  run dir:  $RUN_DIR"
echo "  reviewers: ${TOOLS_FOUND[*]}"
echo "  style:    $STYLE"
echo "  chairman: $CHAIRMAN_TOOL"
echo

# ── Temp file management (single trap) ──────────────────────────────
CLEANUP_FILES=()
DRY_RUN_KEEP_PROMPT=false
add_cleanup() { CLEANUP_FILES+=("$@"); }
cleanup() {
  if [[ "$DRY_RUN_KEEP_PROMPT" == "true" ]]; then
    local filtered=()
    for f in "${CLEANUP_FILES[@]}"; do
      [[ "$f" != "$PROMPT_TMP" ]] && filtered+=("$f")
    done
    [[ ${#filtered[@]} -gt 0 ]] && rm -f "${filtered[@]}" 2>/dev/null || true
  else
    [[ ${#CLEANUP_FILES[@]} -gt 0 ]] && rm -f "${CLEANUP_FILES[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ── Build prompt ─────────────────────────────────────────────────────
PROMPT_TMP="$(mktemp)"
add_cleanup "$PROMPT_TMP"

{
  cat <<'PREAMBLE'
You are the Chairman of a multi-model code review council. Several AI reviewers have independently reviewed the same code changes. Your job is to synthesize their findings into one authoritative, deduplicated list.

Instructions:
1. Read all reviewer reports below.
2. Group findings that describe the same underlying issue (same file, same root cause) — even if reviewers assigned different severities or described it differently.
3. For each unique issue, assign the HIGHEST severity any reviewer gave it, and note how many reviewers flagged it (consensus count).
4. Order findings by: severity first (P0→P3), then consensus count descending.
5. For each finding include:
   - Severity (P0/P1/P2/P3)
   - Consensus: N/M reviewers (where M = total reviewers)
   - File:line citation
   - One-sentence description
   - Concrete fix

6. After the finding list, add a ## Solo Findings section for findings flagged by only one reviewer that may be lower confidence.
7. End with ## Reviewer Agreement — a one-paragraph summary of where reviewers agreed and where they diverged.

Output format for each finding:
### [SEVERITY] <short title> (N/M reviewers)
**Citation:** `path/to/file.rs:line`
**Issue:** ...
**Fix:** ...

PREAMBLE

  echo "---"
  echo "## Reviewer Reports"
  echo ""

  for i in "${!ARTIFACTS[@]}"; do
    tool="${TOOLS_FOUND[$i]}"
    artifact="${ARTIFACTS[$i]}"
    echo "### Reviewer: $tool"
    echo ""
    # Strip YAML frontmatter and provenance header — just the transcript
    if grep -q "REVIEW_TRANSCRIPT_BEGIN" "$artifact"; then
      awk '/<<<REVIEW_TRANSCRIPT_BEGIN>>>/{p=1; next} /<<<REVIEW_TRANSCRIPT_END>>>/{p=0} p' "$artifact"
    elif grep -qm1 '^---$' "$artifact"; then
      # Has YAML frontmatter — skip it (content starts after second ---)
      awk '/^---$/{n++; if(n==2){p=1; next}} p' "$artifact"
    else
      # No frontmatter, no transcript markers — include full file
      cat "$artifact"
    fi
    echo ""
    echo "---"
    echo ""
  done
} > "$PROMPT_TMP"

# ── Dry run ──────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  DRY_RUN_KEEP_PROMPT=true
  echo "[dry-run] Prompt written to: $PROMPT_TMP (file preserved for inspection)"
  echo "[dry-run] Chairman command would be: claude --model \"$model_id\" --print --verbose"
  cat "$PROMPT_TMP"
  exit 0
fi

# ── Verify chairman CLI available ────────────────────────────────────
command -v claude >/dev/null 2>&1 || die "claude CLI not found in PATH"

# ── Run chairman model ───────────────────────────────────────────────
OUTDIR="$RUN_DIR/chairman"
mkdir -p "$OUTDIR"

CANONICAL="$OUTDIR/chairman.md"
SIDECAR="$OUTDIR/chairman.sidecar.json"
TRANSCRIPT_TMP="$(mktemp)"
add_cleanup "$TRANSCRIPT_TMP"

ts_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
head_sha="$(git rev-parse HEAD 2>/dev/null || echo "?")"

echo "Running chairman ($model_id)..."
start_epoch="$(date +%s)"

set +e
# Stderr goes to /dev/null to avoid contaminating the artifact
# with --verbose CLI metadata, token counts, and warnings.
claude --model "$model_id" --print --verbose < "$PROMPT_TMP" 2>/dev/null | tee "$TRANSCRIPT_TMP"
# Capture full PIPESTATUS array on one line — reading PIPESTATUS[0] resets the
# array in bash 3.2 (macOS), causing PIPESTATUS[1] to be unbound under set -u.
_ps=("${PIPESTATUS[@]}")
chairman_rc="${_ps[0]}"
tee_rc="${_ps[1]:-0}"
set -e

end_epoch="$(date +%s)"
duration="$((end_epoch - start_epoch))"

if [[ $chairman_rc -ne 0 ]]; then
  echo "ERROR: chairman model exited $chairman_rc (${duration}s)" >&2
  exit 1
fi
if [[ $tee_rc -ne 0 ]]; then
  echo "ERROR: transcript capture failed (tee exit $tee_rc) — artifact may be truncated" >&2
  exit 1
fi

# ── Write canonical artifact ─────────────────────────────────────────
{
  cat <<HEADER
---
provenance:
  tool: chairman
  model: $model_id
  style: $STYLE
  reviewers: "${TOOLS_FOUND[*]}"
  run_dir: "$RUN_DIR_ARG"
  head_commit: "$head_sha"
  generated_at: "$ts_iso"
  duration_seconds: $duration
---

HEADER
  cat "$TRANSCRIPT_TMP"
} > "$CANONICAL"

# ── Parse findings for sidecar ───────────────────────────────────────
python3 - "$CANONICAL" "$SIDECAR" "$ts_iso" "$model_id" "${TOOLS_FOUND[@]}" <<'PY'
import json, re, sys
from pathlib import Path

canonical = Path(sys.argv[1])
sidecar   = Path(sys.argv[2])
ts        = sys.argv[3]
model     = sys.argv[4]
reviewers = sys.argv[5:]

try:
    text = canonical.read_text(encoding="utf-8")
except (OSError, IOError) as e:
    print(f"ERROR: failed to read canonical artifact: {e}", file=sys.stderr)
    sys.exit(1)

findings = []
heading_pat = re.compile(
    r"###\s+\[(P[0-3])\]\s+(.+?)\s+\((\d+)/(\d+)\s+reviewers?\)",
    re.IGNORECASE
)
# Match backtick-quoted citations: `path/file.ext:line` or `path/file.ext:line-line`
# Also handles extensionless files like `Makefile:42` via optional extension group.
citation_pat = re.compile(r"`([A-Za-z0-9_./:-]+(?:\.[A-Za-z0-9_]+)?:\d+(?:-\d+)?)`")

lines = text.splitlines()
for idx, line in enumerate(lines):
    m = heading_pat.search(line)
    if not m:
        continue
    severity, title, count, total = m.group(1), m.group(2).strip(), int(m.group(3)), int(m.group(4))
    # Look ahead for citation, description, fix — stop at next heading
    citation = ""
    description = ""
    suggested_fix = ""
    for la in lines[idx + 1 : idx + 10]:
        # Stop at the next finding heading to prevent cross-pollination
        if heading_pat.search(la):
            break
        if not citation:
            cm = citation_pat.search(la)
            if cm:
                citation = cm.group(1)
        if not description and la.strip().startswith("**Issue:**"):
            description = la.strip().removeprefix("**Issue:**").strip()
        if not suggested_fix and la.strip().startswith("**Fix:**"):
            suggested_fix = la.strip().removeprefix("**Fix:**").strip()
    findings.append({
        "severity": severity,
        "title": title,
        "consensus_count": count,
        "reviewer_total": total,
        "citation": citation,
        "description": description,
        "suggested_fix": suggested_fix,
    })

if not findings and len(text.strip()) > 100:
    print("WARN: 0 findings parsed from non-empty transcript — chairman output may not match expected format", file=sys.stderr)

payload = {
    "schema_version": 1,
    "tool": "chairman_synthesis.sh",
    "model": model,
    "generated_at": ts,
    "reviewers": reviewers,
    "finding_count": len(findings),
    "findings": findings,
}
sidecar.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(f"Parsed {len(findings)} findings into sidecar.")
PY

# ── Validate sidecar JSON ────────────────────────────────────────────
if ! python3 -m json.tool "$SIDECAR" > /dev/null 2>&1; then
  echo "ERROR: sidecar JSON is malformed" >&2
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Chairman synthesis complete (${duration}s)"
echo "  Artifact:  ${CANONICAL#$ROOT/}"
echo "  Sidecar:   ${SIDECAR#$ROOT/}"
echo "═══════════════════════════════════════════════════════════════"
