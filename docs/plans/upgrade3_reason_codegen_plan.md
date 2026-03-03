# Upgrade 3 Plan: Stop String Drift with Manifest-Generated Types

Scope: implement §0.Z.2.5 CSP checklist rewrite / F1 split alignment and Phase 1 deployability support by generating status/reason code types from `specs/status/status_reason_registries_manifest.json`.

## Outcomes
- Single source of truth remains the manifest.
- Rust and Python reason-code types are generated from manifest data.
- Existing Rust execution API surface stays stable.
- Validator stops relying on safety-critical handwritten strings.
- Verify gates fail if generated outputs drift.

## File Landing Zones
- Generator: `tools/generate_reason_codes.py`
- Rust status wrapper: `crates/soldier_core/src/status_codes.rs`
- Rust status generated: `crates/soldier_core/src/status_codes_generated.rs`
- Rust reject generated: `crates/soldier_core/src/execution/reject_reason_generated.rs`
- Python generated: `tools/generated_status_reason_codes.py`
- Dedicated verify gate script: `plans/lib/status_reason_codegen_gate.sh`

## Manifest Codegen Block Update
Keep legacy keys for compatibility, add repo-accurate outputs:

```json
"codegen": {
  "generator": "tools/generate_reason_codes.py",
  "outputs": {
    "rust_status": "crates/soldier_core/src/status_codes_generated.rs",
    "rust_reject": "crates/soldier_core/src/execution/reject_reason_generated.rs",
    "python": "tools/generated_status_reason_codes.py"
  },
  "legacy": {
    "rust_module": "soldier_core::policy::reason_codes",
    "typescript": "src/types/reason_codes.ts",
    "python": "python/types/reason_codes.py"
  }
}
```

## Generator Interface (Required)
- `python tools/generate_reason_codes.py --write`
- `python tools/generate_reason_codes.py --check`

Behavior:
- `--write` rewrites generated targets in-place.
- `--check` renders outputs in memory and exits non-zero when on-disk files differ, with per-target drift diagnostics.

## Rust Strategy
### 1) Preserve `execution::RejectReasonCode` API
- Keep public type at `soldier_core::execution::RejectReasonCode`.
- In `crates/soldier_core/src/execution/reject_reason.rs`:
  - `include!("reject_reason_generated.rs")` inside a local module.
  - `pub use generated::RejectReasonCode;`
  - keep existing registry helpers and gate-step mapping functions.
- Generated enum requirements:
  - explicit per-variant `#[serde(rename = "SCREAMING_SNAKE_CASE")]`
  - `ALL` slice
  - `as_str()` returns manifest contract token
  - `wire_str()` returns serde/wire token used by existing tests

Reject reason normalization contract:
- Manifest token (contract): PascalCase (for example `NetEdgeTooLow`)
- Wire token (serde JSON): SCREAMING_SNAKE_CASE (for example `NET_EDGE_TOO_LOW`)
- Generator owns transformation (`pascal_to_shouty`) and emits both surfaces explicitly.

### 2) Add status-facing generated module
- `crates/soldier_core/src/status_codes_generated.rs` contains:
  - `TradingMode`
  - `ModeReasonCode`
  - optionally other status registries available in manifest
  - `ModeReasonMeta` and `UnblockMeta`
  - generated `as_str()` and `meta()` accessors
- `crates/soldier_core/src/status_codes.rs` is a tiny wrapper:
  - local `include!` module
  - `pub use generated::*;`
- Export from `crates/soldier_core/src/lib.rs`:
  - `pub mod status_codes;`

## Python Strategy
- Generate `tools/generated_status_reason_codes.py` with:
  - `TradingMode` enum
  - `ModeReasonCode` enum
  - open-permission reason enum/set constants (plus additional registries as needed)
- Update `tools/validate_status.py` to import generated enums/constants.
- Replace handwritten literals (including Decision A latch reason) with generated values.

## Verify/CI Drift Gate (Non-Negotiable)
Add a dedicated contract gate in verify flow (quick + full), not inside conditional Python gates.

Gate script:
- New file `plans/lib/status_reason_codegen_gate.sh`
- Uses `ensure_python` from `plans/lib/verify_utils.sh`
- Runs `"$PYTHON_BIN" "$ROOT/tools/generate_reason_codes.py" --check`
- Uses dedicated timeout variable `STATUS_REASON_CODEGEN_TIMEOUT` (fallback to `SPEC_LINT_TIMEOUT`)

Insertion point:
- In `plans/verify_fork.sh`, before Rust gates:

```bash
if [[ -f specs/status/status_reason_registries_manifest.json ]]; then
  log "14h) status reason-code generation"
  bash "$ROOT/plans/lib/status_reason_codegen_gate.sh"
fi
```

Rationale:
- `plans/verify_fork.sh` only runs `plans/lib/python_gates.sh` when root `pyproject.toml` or `requirements.txt` exists.
- This repo has no root Python project marker, so drift protection must be an unconditional verify contract gate.

## Harness/Docs Updates
- Update workflow allowlist/tests if new scripts/files are in governed paths.
- Update status docs to reference generated sources and drift gate.
- Keep `plans/verify.sh` as thin wrapper; place gate logic in canonical verify implementation path.

## Test Simplification After Generation
Keep:
- choke-point mapping tests
- serde round-trip coverage
- one generated coverage test over `RejectReasonCode::ALL` validating round-trip + non-empty `as_str()` + non-empty `wire_str()`

Remove:
- handwritten full reject reason inventories duplicated from manifest
- handwritten “minimum set” arrays that restate generated manifest data

## Validation Sequence
1. Run generator locally with `--write`.
2. Run targeted Rust tests for reject/status registries.
3. Run `tools/validate_status.py` fixture checks.
4. Run `./plans/verify.sh quick`.
5. Run `./plans/verify.sh full` before final pass/merge.

## Acceptance Criteria
- No handwritten reason-code string constants remain in validator decision logic.
- Reject reason enum parity tests stay green with preserved API path.
- Status metadata accessors are generated and consumable.
- Verify fails on generated-file drift.
- Full verify is green on branch/CI.
