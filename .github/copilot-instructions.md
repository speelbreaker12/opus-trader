# Copilot Code Review Instructions

## Project Context

This is a trading execution system (Rust + Python). Safety-critical code where incorrect behavior can cause financial loss. The canonical spec is `specs/CONTRACT.md`.

## Critical Invariants (Flag violations as HIGH)

1. **Fail-closed defaults**: When uncertain, code MUST choose the restrictive/safe option. Flag any `unwrap_or(TradingMode::Active)` or optimistic defaults. Correct: `unwrap_or(TradingMode::ReduceOnly)`.

2. **No unwrap() in production Rust**: `unwrap()` and `expect()` without meaningful context in non-test code are bugs. Use `?` or `.ok_or()`.

3. **Single chokepoint**: All order dispatch MUST flow through `build_order_intent()` in `crates/soldier_core/src/execution/build_order_intent.rs`. Any code calling exchange APIs or placing orders outside this chokepoint is a critical violation.

4. **8-gate pipeline**: Orders pass through: RiskState -> Preflight -> Quantize -> NetEdge -> Pricer -> LiquidityGate -> RecordedBeforeDispatch -> Dispatch. Skipping or reordering gates is a contract violation.

5. **Latch pattern**: Safety latches (e.g., `open_permission_blocked_latch`) are set on bad events and cleared ONLY on explicit reconciliation. Flag any code that clears a latch without a reconcile call.

## Rust Code Review

- Error handling: prefer `?` operator over `unwrap`/`expect`. Silently ignoring errors (`let _ = dangerous_op()`) is a bug.
- Use newtypes for domain concepts (`InstrumentId`, `Side`), not raw strings.
- Structured logging via `tracing` crate with context fields (instrument_id, intent_id, trading_mode).
- `#[serde(deny_unknown_fields)]` on config structs.
- Clippy must pass with strict settings.

## Python Code Review

- All function signatures must have type hints.
- No bare `except:` — catch specific exceptions.
- Scripts in `plans/` and `scripts/` are verification gates — exit codes matter: 0 = pass, 1 = error, 2 = findings.
- YAML parsing must handle missing pyyaml (fallback parser pattern).

## Shell Script Review

- All scripts must use `set -euo pipefail`.
- Avoid GNU-only tools (macOS compatibility required).
- `wait -n` is not available on macOS default bash.
- Timeouts use the `timeout` command with configurable env vars.

## Test Review

- Tests must prove causality: dispatch count (0 vs 1), specific reject reason codes, specific latch reason codes.
- Table-driven tests preferred for state machine / mode resolution logic.
- Test both happy path and at least one error/fail-closed path.

## Verification Pipeline

- `plans/verify_fork.sh` runs numbered gates (1-14+). New gates need timeout vars and `run_logged_or_exit` wiring.
- Gate scripts that are defense-in-depth (heuristic) should be fail-open (exit 0 when uncertain).
- Gate scripts that enforce contract invariants should be fail-closed (exit non-zero when uncertain).

## What NOT to flag

- `artifacts/` directory is gitignored — don't flag missing artifacts.
- `plans/prd.json` metadata changes (passes, story_ref) are routine.
- Warn-only checks (INFO/WARN to stderr) that exit 0 are intentional fail-open design.
