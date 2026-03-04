# Architecture Map

**Analysis date:** 2026-03-04  
**Scope:** runtime trading engine, durability adapters, status publication sidecar, and verification/workflow harness.

## 1) System shape
- The repo is a contract-first monolith with a split runtime core/infrastructure boundary in Rust: `crates/soldier_core` and `crates/soldier_infra` (`Cargo.toml`).
- Trading decision logic is concentrated in `soldier_core::execution` and exposed through a constrained facade in `crates/soldier_core/src/execution/api.rs`.
- Infra concerns (bootstrap, WAL, trade-id registry, Deribit DTOs) are kept in `crates/soldier_infra/src/*` and intentionally depend on `soldier_core`, not the reverse (`crates/soldier_infra/Cargo.toml`).
- Operational governance is implemented as a separate control plane in `plans/verify_fork.sh` + `plans/lib/*.sh`, with `plans/verify.sh` as a thin wrapper.
- Status publication is sidecar-style: transform/validate in Python (`dashboard/publisher/*.py`) and persist/query in Convex TypeScript (`dashboard/convex/*.ts`).

## 2) Architectural patterns
- **Layered core + adapter boundary:** policy/gates in `crates/soldier_core/src/execution/*`, persistence/venue IO shapes in `crates/soldier_infra/src/*`.
- **Single chokepoint dispatch model:** gate order and final allow/reject authority in `crates/soldier_core/src/execution/build_order_intent.rs`.
- **Fail-closed safety model:** missing or invalid inputs reject by default in modules like `preflight.rs`, `quantize.rs`, `gates.rs`, and `store/ledger.rs`.
- **Proof-token APIs for anti-bypass:** internal proofs such as `BaseGatesPassed` (`base_gates.rs`) and `DispatchConsistencyProof` (`dispatch_map.rs`) make unsafe shortcuts harder.
- **Artifact-backed workflow gating:** verify writes deterministic gate artifacts to `artifacts/verify/<run_id>/` (`plans/verify_fork.sh`, `plans/lib/verify_utils.sh`).

## 3) Module boundaries

### 3.1 Core runtime boundary (`soldier_core`)
- Public crate boundary in `crates/soldier_core/src/lib.rs`.
- Execution facade in `crates/soldier_core/src/execution/api.rs`; most execution modules remain private behind `mod.rs` to prevent uncontrolled surface growth (`crates/soldier_core/src/execution/mod.rs`).
- Gate orchestration split:
  - Shared gates 1-6: `crates/soldier_core/src/execution/base_gates.rs`.
  - OPEN runtime wiring: `crates/soldier_core/src/execution/open_runtime.rs`.
  - Non-OPEN pipeline path: `crates/soldier_core/src/execution/pipeline.rs`.
  - Single engine entrypoint: `crates/soldier_core/src/execution/engine.rs`.
- Adjacent domain modules:
  - Risk: `crates/soldier_core/src/risk/mod.rs`.
  - Venue capabilities/lifecycle: `crates/soldier_core/src/venue/mod.rs`.
  - Idempotency hash primitives: `crates/soldier_core/src/idempotency/mod.rs`.
  - Recovery matching: `crates/soldier_core/src/recovery/mod.rs`.

### 3.2 Infrastructure boundary (`soldier_infra`)
- Public exports from `crates/soldier_infra/src/lib.rs`.
- Startup and wiring: `crates/soldier_infra/src/bootstrap.rs`.
- Config/default resolution from contract Appendix A: `crates/soldier_infra/src/config.rs`.
- Durable persistence boundary:
  - WAL adapter + gate-10 bridge: `crates/soldier_infra/src/wal.rs`.
  - Ledger store + replay: `crates/soldier_infra/src/store/ledger.rs`.
  - Trade-id idempotency registry: `crates/soldier_infra/src/store/trade_id_registry.rs`.
- Venue DTO mapping for Deribit metadata: `crates/soldier_infra/src/deribit/public/mod.rs`.

### 3.3 Workflow/control-plane boundary
- Stable entrypoint wrapper: `plans/verify.sh`.
- Canonical gate orchestration: `plans/verify_fork.sh`.
- Shared gate execution/logging primitives: `plans/lib/verify_utils.sh`.
- Language-specific execution gates:
  - Rust: `plans/lib/rust_gates.sh`
  - Python: `plans/lib/python_gates.sh`
  - Node: `plans/lib/node_gates.sh`
- Pass mutation guardrail: `plans/prd_set_pass.sh`.
- Step receipt state machine: `plans/wf_step.sh`.

## 4) Data and control flow

### 4.1 OPEN trading decision path
1. Caller enters via `ExecutionEngine::decide` (`crates/soldier_core/src/execution/engine.rs`).
2. OPEN uses `build_open_order_intent_runtime` (`open_runtime.rs`).
3. Shared gates 1-6 run in `evaluate_base_gates` (`base_gates.rs`).
4. OPEN-only checks run: pending exposure, global exposure budget, liquidity, net-edge, pricer (`open_runtime.rs`, `risk/*`, `gate.rs`, `gates.rs`, `pricer.rs`).
5. Chokepoint gate order + WAL gate authority resolve in `build_order_intent_with_wal_gate` (`build_order_intent.rs`).
6. Engine maps chokepoint outcome into `ExecutionDecision` (`engine.rs`).

### 4.2 CLOSE/HEDGE/CANCEL path
1. Input routes through `evaluate_pipeline_variant` in `engine.rs`.
2. Pipeline executes `evaluate_intent_pipeline` (`pipeline.rs`) after assembly in `intent_assembly.rs` where relevant.
3. Cancel-only short-circuits intentionally to avoid blocking cancels on assembly failures (`intent_assembly.rs`, `base_gates.rs`).

### 4.3 Durability/restart path
1. Startup calls `bootstrap_storage`/`bootstrap_full` (`crates/soldier_infra/src/bootstrap.rs`).
2. WAL and registry are initialized with durable paths under `{data_dir}/wal` (`bootstrap.rs`).
3. Replay output (`ReplayOutcome`) is returned and must drive startup latch decisions (documented in `bootstrap.rs`).
4. Runtime append path uses `WalLedger::append` and gate adapter `DurableWalGate` (`store/ledger.rs`, `wal.rs`).

### 4.4 Verification flow (engineering control path)
1. `./plans/verify.sh [quick|full]` delegates to `plans/verify_fork.sh`.
2. `verify_fork.sh` runs contract/spec validators, status/schema checks, and language gates, with partial parallelization.
3. Each gate writes `<gate>.log`, `<gate>.rc`, `<gate>.time`, optional `FAILED_GATE`, and `verify.meta.json` in `artifacts/verify/<run_id>/`.
4. `plans/prd_set_pass.sh` consumes those artifacts before allowing `passes=true` in `plans/prd.json`.

### 4.5 Status publication flow
1. Runtime snapshot is read/validated/normalized in `dashboard/publisher/transform.py`.
2. Publisher loop handles retry/spool/state in `dashboard/publisher/publisher.py`, `spool.py`, `state.py`.
3. Convex mutation stores deduped snapshots in `dashboard/convex/status.ts` with shape constraints in `dashboard/convex/status_contract.ts` and schema table in `dashboard/convex/schema.ts`.
4. Contract validator tooling for status fixtures/liveness lives in `tools/validate_status.py`.

## 5) Entrypoints to plan around
- `plans/verify.sh` -> canonical local/CI verification wrapper.
- `plans/verify_fork.sh` -> authoritative gate sequence.
- `crates/soldier_core/src/execution/engine.rs` -> runtime decision entrypoint.
- `crates/soldier_infra/src/bootstrap.rs` -> startup assembly + replay checkpoint.
- `dashboard/publisher/publisher.py` -> status sidecar process entrypoint.
- `dashboard/convex/status.ts` -> status write/query API boundary.

## 6) Key abstractions
- `ExecutionInput` / `ExecutionDecision` (`engine.rs`) define the top-level runtime API.
- `ChokeResult`, `GateStep`, and `GateResults` (`build_order_intent.rs`) encode deterministic gate sequencing.
- `BaseGatesPassed` proof token (`base_gates.rs`) and `DispatchConsistencyProof` (`dispatch_map.rs`) encode validated invariants.
- `RecordedBeforeDispatchGate` trait (`build_order_intent.rs`) separates chokepoint logic from concrete persistence implementation.
- `WalLedger`, `ReplayOutcome`, `TradeIdRegistry` (`store/ledger.rs`, `store/trade_id_registry.rs`) represent durability + idempotency state.
- Receipt artifacts under `.wf/receipts/<story_id>/` (`plans/wf_step.sh`) encode workflow step completion.

## 7) Planning hotspots
- Gate ordering and reject-code semantics are tightly coupled across `base_gates.rs`, `pipeline.rs`, `open_runtime.rs`, and `reject_reason.rs`.
- Any persistence behavior change should be planned across `wal.rs`, `store/ledger.rs`, `bootstrap.rs`, and contract assertions in `specs/CONTRACT.md`.
- Workflow changes must preserve wrapper/thin-entrypoint assumptions in `plans/verify.sh` and artifact contracts in `plans/prd_set_pass.sh`.
