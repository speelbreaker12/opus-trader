---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- `1e0eccc6`

## 0) What shipped
- Feature/behavior: Added crate-private event-sink seams for the execution liquidity gate and net-edge gate, plus graybox tests that exercise the event paths without production metric side effects.
- Value (what problem it solves): This separates gate decision logic from observability adapters so the execution gates can be tested directly without process-global counters and traced metric lines obscuring behavior.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Execution gate logic still mixed local metrics, process-global atomics, and traced metric-line emission; graybox tests for those paths became race-prone because unrelated tests could increment the same global counters in parallel.
- Time/token drain it caused: It forced metric-parity assertions to depend on global state and made new event-sink pilots riskier than the fee pilot despite being mechanically similar.
- Workaround I used this session (exploit): I added event-sink wrappers for `execution/gate.rs` and `execution/gates.rs`, then introduced a shared `begin_metrics_test()` / `with_metrics_update_lock(...)` helper so the global metric update path serializes under tests.
- Next-agent default behavior (subordinate): When adding a new graybox event seam around execution metrics, route production counter/metric-line updates through the shared metrics-test lock path and keep one wrapper parity test beside the graybox tests.
- Permanent fix proposal (elevate): Continue migrating mixed-observability gates onto typed event sinks and move the remaining metric-sensitive tests onto the shared helper so execution telemetry no longer relies on ad hoc local locks.
- Smallest increment: Apply the same pattern to the next execution or risk gate that still owns both instance metrics and process-global counters.
- Validation (proof it got better): Targeted suites passed for `execution::gate::gate_tests`, `execution::gates::gates_tests`, `execution::gates::gates_prop_net_edge_tests`, `risk::fees::tests`, `test_liquidity_gate`, and `prop_net_edge`; the previously flaky net-edge graybox counter assertion stayed green after the shared lock was added.

## 2) Best follow-up
- Single best next step: Continue the event-sink split on the next mixed-observability execution or risk gate so the new test harness pays down more of the global-telemetry coupling.
- 1-3 upgrades worth considering:
- Add the shared metrics-test helper to the remaining execution metric-parity tests that still open-code buffer draining and mutex access.
- Decide whether `NoopEvents` should stay as a simple test utility or grow into a wider default adapter for future seams.
- Clear the unrelated `docs/contract_kernel.json` drift so `./plans/verify.sh quick` can become useful evidence again for this refactor branch.

## 3) Enforceable rules
- Route any new graybox execution telemetry test through `begin_metrics_test()` before reading process-global counters or execution metric lines.
- Keep exactly one wrapper parity test for each new event seam that still proves traced metric-line/counter behavior.
- If a gate mixes local metrics and process-global telemetry, split it with a crate-private `EventSink` seam before adding more direct logic assertions.
