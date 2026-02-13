# Phase1 Code Delta (Frozen Refs)

- Generated (UTC): 2026-02-13T22:27:09Z
- opus ref: phase1-impl-opus
- ralph ref: phase1-impl-ralph
- Scope: crates/soldier_core/src/execution + crates/soldier_core/tests

## Inventory
- opus files: 34
- ralph files: 38
- common files: 34
- only in opus: 0
- only in ralph: 4
- common files with same hash: 0
- common files with code differences: 34

## Only In opus
- (none)

## Only In ralph
crates/soldier_core/src/execution/order_type_guard.rs
crates/soldier_core/src/execution/state.rs
crates/soldier_core/tests/test_fee_cache.rs
crates/soldier_core/tests/test_phase1_dispatch_auth.rs

## Top Changed Files By Churn (adds,dels,path)
292	285	crates/soldier_core/src/execution/build_order_intent.rs
225	448	crates/soldier_core/src/execution/gate.rs
218	345	crates/soldier_core/tests/test_missing_config.rs
212	192	crates/soldier_core/src/execution/tlsm.rs
208	514	crates/soldier_core/tests/test_dispatch_map.rs
203	93	crates/soldier_core/src/execution/label.rs
196	350	crates/soldier_core/tests/test_intent_determinism.rs
173	405	crates/soldier_core/tests/test_rejection_side_effects.rs
160	178	crates/soldier_core/src/execution/quantize.rs
151	20	crates/soldier_core/src/execution/mod.rs
147	875	crates/soldier_core/tests/test_gate_ordering.rs
124	183	crates/soldier_core/src/execution/dispatch_map.rs
118	358	crates/soldier_core/tests/test_net_edge_gate.rs
108	252	crates/soldier_core/tests/test_label_match.rs
100	203	crates/soldier_core/tests/test_idempotency.rs
97	310	crates/soldier_core/tests/test_intent_id_propagation.rs
96	436	crates/soldier_core/tests/test_instrument_cache_ttl.rs
92	146	crates/soldier_core/src/execution/gates.rs
89	521	crates/soldier_core/tests/test_liquidity_gate.rs
84	422	crates/soldier_core/tests/test_tlsm.rs
78	232	crates/soldier_core/tests/test_order_size.rs
77	178	crates/soldier_core/src/execution/pricer.rs
77	153	crates/soldier_core/src/execution/preflight.rs
67	302	crates/soldier_core/tests/test_pricer.rs
66	115	crates/soldier_core/src/execution/order_size.rs
65	325	crates/soldier_core/tests/test_preflight.rs
62	76	crates/soldier_core/src/execution/post_only_guard.rs
61	292	crates/soldier_core/tests/test_dispatch_chokepoint.rs
60	544	crates/soldier_core/tests/test_quantize.rs
46	198	crates/soldier_core/tests/test_instrument_kind_mapping.rs
38	153	crates/soldier_core/tests/test_fee_staleness.rs
37	255	crates/soldier_core/tests/test_label.rs
34	153	crates/soldier_core/tests/test_post_only_guard.rs
34	150	crates/soldier_core/tests/test_capabilities.rs

## Raw Diffs
- Stored under: /Users/admin/Desktop/opus-trader/artifacts/phase1_compare/20260213_222628_code_delta/diffs
