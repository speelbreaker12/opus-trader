#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plans/recon_trace.sh init <story_id> <slice_id> [--run-root PATH] [--base-branch BRANCH]
  plans/recon_trace.sh record-step <story_id> <step_name> --run-root PATH --start ISO8601Z --end ISO8601Z --status PASS|FAIL|BLOCKED --retries N --wf-receipt PATH --step-report PATH [--attempt N] [--kind KIND] [--log-path PATH] [--notes TEXT]
  plans/recon_trace.sh log-failure <story_id> <step_name> --run-root PATH --type SEARCH|CEREMONY|CONTEXT_LOSS|TOOLING|AMBIGUITY|HALLUCINATION --evidence TEXT --action TEXT
  plans/recon_trace.sh add-delta --run-root PATH --item TEXT

Subcommands:
  init         Create run card + ledgers for a single-story reconciliation run.
  record-step  Validate step report + receipt, append timing/receipt ledgers (+ JSONL), and emit trace receipt JSON.
  log-failure  Append a fail/ambiguity event to FAILURE_LOG.md + failures.jsonl.
  add-delta    Append workflow improvement item to DELTA_LIST.md.
USAGE
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

subcmd="${1:-}"
if [[ -z "$subcmd" || "$subcmd" == "-h" || "$subcmd" == "--help" ]]; then
  usage
  exit 2
fi
shift || true

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    sha256sum "$path" | awk '{print $1}'
  fi
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

step_index() {
  case "$1" in
    preflight) echo 0 ;;
    implement) echo 1 ;;
    self_review) echo 2 ;;
    cycle1) echo 3 ;;
    fix) echo 4 ;;
    cycle2) echo 5 ;;
    resolution) echo 6 ;;
    verify_full) echo 7 ;;
    pass) echo 8 ;;
    *) return 1 ;;
  esac
}

duration_seconds() {
  local start="$1"
  local end="$2"
  python3 - "$start" "$end" <<'PY'
import datetime as dt
import sys
start = dt.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
end = dt.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ")
secs = int((end - start).total_seconds())
print(max(0, secs))
PY
}

validate_kind() {
  case "$1" in
    doc_read|gate|execution|review|scaffold|handoff_update) return 0 ;;
    *) return 1 ;;
  esac
}

validate_failure_type() {
  case "$1" in
    SEARCH|CEREMONY|CONTEXT_LOSS|TOOLING|AMBIGUITY|HALLUCINATION) return 0 ;;
    *) return 1 ;;
  esac
}

case "$subcmd" in
  init)
    story_id="${1:-}"
    slice_id="${2:-}"
    shift 2 || true
    [[ -n "$story_id" && -n "$slice_id" ]] || { echo "ERROR: init requires <story_id> <slice_id>" >&2; exit 2; }

    run_root=""
    base_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --run-root) run_root="${2:?missing path}"; shift 2 ;;
        --base-branch) base_branch="${2:?missing branch}"; shift 2 ;;
        *) echo "ERROR: unknown arg for init: $1" >&2; exit 2 ;;
      esac
    done

    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    if [[ -z "$run_root" ]]; then
      run_root="reviews/reconciliations/${slice_id}/experiments/${story_id}-operator-${ts}"
    fi
    mkdir -p "$run_root/receipts" "$run_root/logs"

    run_id="$(basename "$run_root")"
    head_commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    started_at="$(iso_now)"

    template="$ROOT/plans/recon_run_card_template.md"
    run_card="$run_root/RUN_CARD.md"
    if [[ -f "$template" ]]; then
      sed \
        -e "s/__RUN_ID__/${run_id}/g" \
        -e "s/__STORY_ID__/${story_id}/g" \
        -e "s/__SLICE_ID__/${slice_id}/g" \
        -e "s/__STARTED_AT__/${started_at}/g" \
        -e "s/__BASE_BRANCH__/${base_branch}/g" \
        -e "s/__HEAD_COMMIT__/${head_commit}/g" \
        "$template" > "$run_card"
    else
      echo "# Reconciliation Run Card" > "$run_card"
    fi

    cat > "$run_root/STEP_TIMING_LEDGER.md" <<'EOF'
# Step Timing Ledger

| Step | Start (UTC) | End (UTC) | Duration(s) | Retries | Result |
|---|---:|---:|---:|---:|---|
EOF

    cat > "$run_root/RECEIPT_LEDGER.md" <<'EOF'
# Receipt Ledger

| Step | Receipt Path | SHA256 | Exit | Notes |
|---|---|---|---:|---|
EOF

    cat > "$run_root/FAILURE_LOG.md" <<'EOF'
# Failure Log

| Time (UTC) | Step | Type | Evidence | Action |
|---|---|---|---|---|
EOF

    cat > "$run_root/DELTA_LIST.md" <<'EOF'
# Delta List
EOF

    : > "$run_root/step_timing.jsonl"
    : > "$run_root/failures.jsonl"

    printf 'Initialized recon trace run:\n- run_root: %s\n- run_id: %s\n' "$run_root" "$run_id"
    ;;

  record-step)
    story_id="${1:-}"
    step_name="${2:-}"
    shift 2 || true
    [[ -n "$story_id" && -n "$step_name" ]] || { echo "ERROR: record-step requires <story_id> <step_name>" >&2; exit 2; }
    idx="$(step_index "$step_name" 2>/dev/null || true)"
    [[ -n "$idx" ]] || { echo "ERROR: unknown step_name: $step_name" >&2; exit 2; }

    run_root=""
    start_at=""
    end_at=""
    status=""
    retries=""
    wf_receipt=""
    step_report=""
    attempt="1"
    kind="execution"
    log_path=""
    notes=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --run-root) run_root="${2:?missing path}"; shift 2 ;;
        --start) start_at="${2:?missing start}"; shift 2 ;;
        --end) end_at="${2:?missing end}"; shift 2 ;;
        --status) status="${2:?missing status}"; shift 2 ;;
        --retries) retries="${2:?missing retries}"; shift 2 ;;
        --wf-receipt) wf_receipt="${2:?missing path}"; shift 2 ;;
        --step-report) step_report="${2:?missing path}"; shift 2 ;;
        --attempt) attempt="${2:?missing attempt}"; shift 2 ;;
        --kind) kind="${2:?missing kind}"; shift 2 ;;
        --log-path) log_path="${2:?missing log path}"; shift 2 ;;
        --notes) notes="${2:?missing notes}"; shift 2 ;;
        *) echo "ERROR: unknown arg for record-step: $1" >&2; exit 2 ;;
      esac
    done

    [[ -n "$run_root" && -n "$start_at" && -n "$end_at" && -n "$status" && -n "$retries" && -n "$wf_receipt" && -n "$step_report" ]] || {
      echo "ERROR: record-step missing required args" >&2
      exit 2
    }

    case "$status" in
      PASS|FAIL|BLOCKED) ;;
      *) echo "ERROR: --status must be PASS|FAIL|BLOCKED" >&2; exit 2 ;;
    esac
    [[ "$retries" =~ ^[0-9]+$ ]] || { echo "ERROR: --retries must be an integer >= 0" >&2; exit 2; }
    [[ "$attempt" =~ ^[0-9]+$ ]] || { echo "ERROR: --attempt must be an integer >= 1" >&2; exit 2; }
    [[ "$attempt" -ge 1 ]] || { echo "ERROR: --attempt must be >= 1" >&2; exit 2; }
    validate_kind "$kind" || {
      echo "ERROR: --kind must be one of: doc_read|gate|execution|review|scaffold|handoff_update" >&2
      exit 2
    }

    [[ -d "$run_root" ]] || { echo "ERROR: run_root not found: $run_root" >&2; exit 3; }
    [[ -f "$wf_receipt" ]] || { echo "ERROR: wf receipt not found: $wf_receipt" >&2; exit 3; }
    [[ -f "$step_report" ]] || { echo "ERROR: step report not found: $step_report" >&2; exit 3; }
    if [[ -n "$log_path" && ! -f "$log_path" ]]; then
      echo "ERROR: --log-path not found: $log_path" >&2
      exit 3
    fi

    jq empty "$wf_receipt" >/dev/null 2>&1 || { echo "ERROR: wf receipt invalid JSON: $wf_receipt" >&2; exit 4; }
    python3 "$ROOT/plans/validate_recon_step_report.py" "$step_report" >/dev/null

    wf_sha="$(sha256_file "$wf_receipt")"
    report_sha="$(sha256_file "$step_report")"
    dur="$(duration_seconds "$start_at" "$end_at")"
    exit_code="$(jq -r '.exit_code // 1' "$step_report" 2>/dev/null || echo 1)"
    log_sha=""
    if [[ -n "$log_path" ]]; then
      log_sha="$(sha256_file "$log_path")"
    fi
    slice_id="$(echo "$story_id" | sed -n 's/^\([A-Za-z][A-Za-z0-9]*\)-.*/\1/p')"
    slice_id="${slice_id:-UNKNOWN}"
    run_id="$(basename "$run_root")"
    created_at="$(iso_now)"
    head_commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

    printf '| %s | %s | %s | %s | %s | %s |\n' \
      "$step_name" "$start_at" "$end_at" "$dur" "$retries" "$status" >> "$run_root/STEP_TIMING_LEDGER.md"

    jq -cn \
      --arg story_id "$story_id" \
      --arg trace_id "$run_id" \
      --arg step "$step_name" \
      --arg kind "$kind" \
      --arg ts_start "$start_at" \
      --arg ts_end "$end_at" \
      --arg log_path "$log_path" \
      --arg log_sha256 "$log_sha" \
      --arg wf_receipt_path "$wf_receipt" \
      --arg step_report_path "$step_report" \
      --arg status "$status" \
      --argjson attempt "$attempt" \
      --argjson duration_s "$dur" \
      --argjson exit_code "$exit_code" \
      '{
        story_id: $story_id,
        trace_id: $trace_id,
        step: $step,
        attempt: $attempt,
        kind: $kind,
        ts_start: $ts_start,
        ts_end: $ts_end,
        duration_s: $duration_s,
        exit_code: $exit_code,
        status: $status,
        log_path: $log_path,
        log_sha256: $log_sha256,
        wf_receipt_path: $wf_receipt_path,
        step_report_path: $step_report_path
      }' >> "$run_root/step_timing.jsonl"

    printf '| %s | %s | %s | %s | %s |\n' \
      "$step_name" "$wf_receipt" "$wf_sha" "$exit_code" "${notes:-recorded}" >> "$run_root/RECEIPT_LEDGER.md"

    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    trace_receipt="$run_root/receipts/${ts}_${step_name}_attempt${attempt}_trace_receipt.json"
    jq -n \
      --arg schema_version "recon_trace_receipt.v1" \
      --arg head_commit "$head_commit" \
      --arg created_at "$created_at" \
      --arg run_id "$run_id" \
      --arg story_id "$story_id" \
      --arg slice_id "$slice_id" \
      --arg step_name "$step_name" \
      --arg start_at "$start_at" \
      --arg end_at "$end_at" \
      --arg result "$status" \
      --arg wf_receipt_path "$wf_receipt" \
      --arg wf_receipt_sha256 "$wf_sha" \
      --arg step_report_path "$step_report" \
      --arg step_report_sha256 "$report_sha" \
      --arg log_path "$log_path" \
      --arg log_sha256 "$log_sha" \
      --arg notes "${notes:-}" \
      --argjson step_index "$idx" \
      --argjson duration_seconds "$dur" \
      --argjson attempt "$attempt" \
      --argjson retries "$retries" \
      '{
        schema_version: $schema_version,
        head_commit: $head_commit,
        created_at: $created_at,
        run_id: $run_id,
        story_id: $story_id,
        slice_id: $slice_id,
        step_name: $step_name,
        step_index: $step_index,
        start_at: $start_at,
        end_at: $end_at,
        duration_seconds: $duration_seconds,
        retries: $retries,
        result: $result,
        attempt: $attempt,
        wf_receipt_path: $wf_receipt_path,
        wf_receipt_sha256: $wf_receipt_sha256,
        step_report_path: $step_report_path,
        step_report_sha256: $step_report_sha256,
        notes: $notes
      }
      + (if $log_path != "" then {log_path: $log_path, log_sha256: $log_sha256} else {} end)
      ' > "$trace_receipt"

    {
      echo ""
      echo "## Progress Updates"
      echo "- [$created_at] step=$step_name attempt=$attempt status=$status wf_receipt=$wf_receipt trace_receipt=$trace_receipt"
    } >> "$run_root/RUN_CARD.md"

    printf 'Recorded step trace:\n- trace_receipt: %s\n' "$trace_receipt"
    ;;

  log-failure)
    story_id="${1:-}"
    step_name="${2:-}"
    shift 2 || true
    [[ -n "$story_id" && -n "$step_name" ]] || { echo "ERROR: log-failure requires <story_id> <step_name>" >&2; exit 2; }

    run_root=""
    failure_type=""
    evidence=""
    action=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --run-root) run_root="${2:?missing path}"; shift 2 ;;
        --type) failure_type="${2:?missing type}"; shift 2 ;;
        --evidence) evidence="${2:?missing evidence}"; shift 2 ;;
        --action) action="${2:?missing action}"; shift 2 ;;
        *) echo "ERROR: unknown arg for log-failure: $1" >&2; exit 2 ;;
      esac
    done
    [[ -n "$run_root" && -n "$failure_type" && -n "$evidence" && -n "$action" ]] || {
      echo "ERROR: log-failure missing required args" >&2
      exit 2
    }
    if ! validate_failure_type "$failure_type"; then
      echo "ERROR: --type must be one of SEARCH|CEREMONY|CONTEXT_LOSS|TOOLING|AMBIGUITY|HALLUCINATION" >&2
      exit 2
    fi
    [[ -f "$run_root/FAILURE_LOG.md" ]] || { echo "ERROR: FAILURE_LOG missing under run_root: $run_root" >&2; exit 3; }
    [[ -f "$run_root/failures.jsonl" ]] || { echo "ERROR: failures.jsonl missing under run_root: $run_root" >&2; exit 3; }
    now="$(iso_now)"
    printf '| %s | %s | %s | %s | %s |\n' "$now" "$step_name" "$failure_type" "$evidence" "$action" >> "$run_root/FAILURE_LOG.md"
    jq -cn \
      --arg ts "$now" \
      --arg story_id "$story_id" \
      --arg step "$step_name" \
      --arg category "$failure_type" \
      --arg summary "$action" \
      --arg evidence_path "$evidence" \
      '{
        ts: $ts,
        story_id: $story_id,
        step: $step,
        category: $category,
        summary: $summary,
        evidence_path: $evidence_path
      }' >> "$run_root/failures.jsonl"
    echo "Recorded failure event at $now"
    ;;

  add-delta)
    run_root=""
    item=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --run-root) run_root="${2:?missing path}"; shift 2 ;;
        --item) item="${2:?missing item}"; shift 2 ;;
        *) echo "ERROR: unknown arg for add-delta: $1" >&2; exit 2 ;;
      esac
    done
    [[ -n "$run_root" && -n "$item" ]] || { echo "ERROR: add-delta requires --run-root and --item" >&2; exit 2; }
    [[ -f "$run_root/DELTA_LIST.md" ]] || { echo "ERROR: DELTA_LIST missing under run_root: $run_root" >&2; exit 3; }
    printf -- '- %s\n' "$item" >> "$run_root/DELTA_LIST.md"
    echo "Recorded delta item."
    ;;

  *)
    echo "ERROR: unknown subcommand: $subcmd" >&2
    usage >&2
    exit 2
    ;;
esac
