# Phase 1 CI Links

Links to CI runs for each AUTO gate.

All Phase 1 AUTO gates run as part of the `verify` job in the CI workflow.
Latest green run on `main`: [Run 22120884887](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) (2026-02-18, verify: success).

| Gate | Test Name | CI Run | Build ID | Status |
|------|-----------|--------|----------|--------|
| P1-A | `test_dispatch_chokepoint_no_direct_exchange_client_usage` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-A | `test_dispatch_visibility_is_restricted` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-B | `test_full_pipeline_determinism` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-B | `test_chokepoint_same_inputs_same_trace` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-C | `test_rejected_intent_has_no_side_effects` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-D | `test_intent_id_propagates_through_approved_pipeline` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-D | `test_intent_id_propagates_through_rejected_pipeline` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-D | `test_metrics_attributable_to_intent` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-E | `test_constraint_reject_gates_before_persist` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-E | `test_constraint_wal_after_all_validation_gates` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-E | `test_constraint_approval_requires_all_gates_pass` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-F | `test_missing_tick_size_fails_closed` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-F | `test_config_missing_no_side_effects` | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS |
| P1-G | crash-mid-intent (7 tests in `soldier_infra`) | [Run](https://github.com/speelbreaker12/opus-trader/actions/runs/22120884887) | 22120884887 | PASS (drill) |
