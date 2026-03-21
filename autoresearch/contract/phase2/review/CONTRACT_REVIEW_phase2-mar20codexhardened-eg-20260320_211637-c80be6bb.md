# Contract Review Package

- run_id: `phase2-mar20codexhardened-eg-20260320_211637-c80be6bb`
- contract_file_hash: `09b3885d5af5f1d3ede265940ff2441e8964042cbfb8abe1d9b2af183c76ff55`
- proposals_file_hash: `bb1ef700c7ef4fdb2ce4453cb050f037c153ffa33e6eb62b86d5a7af378091d8`
- proposal_count: `3`

## Manual Review Checklist

1. Read every proposal below.
2. Record one decision per proposal in `REVIEW_DECISIONS_<run_id>.json`.
3. Use `accepted`, `rejected`, or `pending_scope_review` only.
4. Re-run `harness.sh contract render-review --accepted-only` after writing review decisions.
5. Do not apply any accepted-only patch if the live `CONTRACT.md` hash differs from the recorded `contract_file_hash`.
6. Keep `sample_contract_patch` proposals rejected unless explicitly moved to a first-party fixture.

## P-001 — missing_fail_closed

- fixture: `s2_2_2_evidence_guard_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-eg-20260320_211637-c80be6bb/s2_2_2_evidence_guard_latest/proposals.json`
- section: `2.2.2 EvidenceGuard`
- change_type: `new_requirement`
- source_finding: `F-001`
- current_status: `rejected`

### Rationale

The section defines the evidence chain as both writable and joinable for every dispatched OPEN intent, but GREEN currently depends only on write-error, freshness, and queue-pressure signals. Adding an explicit joinability criterion closes the fail-open path where broken or mismatched evidence links can leave EvidenceChainState GREEN and OPEN permission available.

### Proposed Text

```text
Add an explicit GREEN criterion and paired AT coverage for evidence joinability:
- Joinability MUST be continuously provable for every dispatched OPEN intent within the rolling window: the WAL intent entry, TruthCapsule, Decision Snapshot payload, and any required attribution row for fills MUST resolve to the same intent/evidence identifiers.
- Any missing, mismatched, or unjoinable required evidence link for a dispatched OPEN intent => EvidenceChainState MUST be not GREEN and OPEN intents MUST be blocked until all GREEN criteria plus hysteresis/cooldown are again satisfied.
- Acceptance Tests (required): one AT where a required evidence link is missing or mismatched and EvidenceChainState becomes not GREEN; one AT where joinability is restored but GREEN remains blocked until the clear window and cooldown requirements have fully elapsed.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -29,7 +29,10 @@ EvidenceChainState = GREEN iff ALL are true (rolling window; default `evidenceguard_window_s = 60` seconds, safety-critical; configurable in Appendix A):
 - **All required EvidenceGuard counters MUST be defined and parseable** (fail-closed).
   - Missing/unparseable required counter(s) => EvidenceChainState MUST be not GREEN.
   - Required counters (minimum): `truth_capsule_write_errors`, `decision_snapshot_write_errors`, `wal_write_errors`, `parquet_queue_overflow_count`, `attribution_write_errors`.
+- Joinability MUST be continuously provable for every dispatched OPEN intent within the rolling window: the WAL intent entry, TruthCapsule, Decision Snapshot payload, and any required attribution row for fills MUST resolve to the same intent/evidence identifiers.
+- Any missing, mismatched, or unjoinable required evidence link for a dispatched OPEN intent => EvidenceChainState MUST be not GREEN and OPEN intents MUST be blocked until all GREEN criteria plus hysteresis/cooldown are again satisfied.
@@ -52,0 +55,3 @@ **Acceptance Tests (REQUIRED):**
+- Add a paired AT where a required evidence link is missing or mismatched and EvidenceChainState becomes not GREEN.
+- Add a paired AT where joinability is restored, but GREEN stays blocked until the clear window and cooldown requirements have fully elapsed.
```

## P-002 — missing_at_pair

- fixture: `s2_2_2_evidence_guard_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-eg-20260320_211637-c80be6bb/s2_2_2_evidence_guard_latest/proposals.json`
- section: `2.2.2 EvidenceGuard`
- change_type: `new_requirement`
- source_finding: `F-002`
- current_status: `proposed`

### Rationale

The normative text says GREEN recovery must remain stable for the cooldown window, but the listed AT coverage only proves the clear path with `evidenceguard_global_cooldown = 0`. A paired AT with a longer non-zero cooldown is needed to prove GREEN stays blocked until the larger timer expires.

### Proposed Text

```text
Add a paired acceptance test covering non-zero global cooldown that exceeds the clear window:
AT-NEW-COOLDOWN
- Given: `parquet_queue_trip_pct = 0.80`, `parquet_queue_trip_window_s = 5`, `parquet_queue_clear_pct = 0.75`, `queue_clear_window_s = 10`, `evidenceguard_global_cooldown = 120`, and all other EvidenceGuard criteria are satisfied.
- When: `parquet_queue_depth_pct` is 0.85 for 6s, then 0.72 for 10s, and remains 0.72 through 120s.
- Then: after 10s EvidenceChainState remains not GREEN because the global cooldown has not expired; only after 120s may EvidenceChainState become GREEN if all criteria remain satisfied.
- Pass criteria: GREEN stays blocked until `max(queue_clear_window_s, evidenceguard_global_cooldown)` expires.
- Fail criteria: GREEN clears after only the 10s clear window or otherwise ignores the non-zero cooldown.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -118,6 +118,13 @@ AT-422
 - Given: config overrides are set to `parquet_queue_trip_pct = 0.80`, `parquet_queue_trip_window_s = 5`, `parquet_queue_clear_pct = 0.75`, `queue_clear_window_s = 10`, and `evidenceguard_global_cooldown = 0`, and all other EvidenceGuard criteria are satisfied.
 - When: `parquet_queue_depth_pct` is 0.85 for 6s, then 0.72 for 9s, then 0.72 for 10s.
 - Then: after 6s, EvidenceChainState != GREEN and TradingMode == ReduceOnly; after 9s, EvidenceChainState != GREEN; after 10s, EvidenceChainState == GREEN and EvidenceGuard no longer forces ReduceOnly.
 - Pass criteria: trip/clear behavior follows overridden config values, not defaults.
 - Fail criteria: no trip, no clear, or behavior matches hard-coded defaults instead of config.
+
+AT-NEW-COOLDOWN
+- Given: `parquet_queue_trip_pct = 0.80`, `parquet_queue_trip_window_s = 5`, `parquet_queue_clear_pct = 0.75`, `queue_clear_window_s = 10`, `evidenceguard_global_cooldown = 120`, and all other EvidenceGuard criteria are satisfied.
+- When: `parquet_queue_depth_pct` is 0.85 for 6s, then 0.72 for 10s, and remains 0.72 through 120s.
+- Then: after 10s EvidenceChainState remains not GREEN because the global cooldown has not expired; only after 120s may EvidenceChainState become GREEN if all criteria remain satisfied.
+- Pass criteria: GREEN stays blocked until `max(queue_clear_window_s, evidenceguard_global_cooldown)` expires.
+- Fail criteria: GREEN clears after only the 10s clear window or otherwise ignores the non-zero cooldown.
```

## P-003 — weak_normative

- fixture: `s2_2_2_evidence_guard_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codexhardened-eg-20260320_211637-c80be6bb/s2_2_2_evidence_guard_latest/proposals.json`
- section: `2.2.2 EvidenceGuard`
- change_type: `new_requirement`
- source_finding: `F-003`
- current_status: `pending_scope_review`

### Rationale

The combined permission sentence ambiguously attaches the `NOT risk-increasing` qualifier to CLOSE, HEDGE, and CANCEL instead of only to cancel/replace. Splitting the permissions into separate bullets makes the dispatch rule unambiguous and preserves the distinct restriction already stated for risk-increasing CANCEL/REPLACE.

### Proposed Text

```text
Replace the combined permission sentence with separate normative bullets:
- CLOSE intents are allowed while `EvidenceChainState != GREEN` only when not constrained by §2.2.3 Kill semantics and only if the dispatch is risk-reducing.
- HEDGE intents are allowed while `EvidenceChainState != GREEN` only when not constrained by §2.2.3 Kill semantics and only if the dispatch is risk-reducing.
- CANCEL intents without a replacement leg are allowed while `EvidenceChainState != GREEN` only when not constrained by §2.2.3 Kill semantics.
- CANCEL/REPLACE intents are allowed while `EvidenceChainState != GREEN` only if the replace leg is NOT risk-increasing per §2.2.5.
- Risk-increasing CANCEL/REPLACE MUST be rejected while `EvidenceChainState != GREEN`.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -22,4 +22,7 @@ **Invariant (Non-Negotiable):**
 - If Evidence Chain is not GREEN → **block ALL new OPEN intents**.
-- CLOSE / HEDGE / CANCEL intents are allowed only if the cancel/replace is NOT risk-increasing per §2.2.5, and only when not constrained by §2.2.3 Kill semantics (risk-reducing only).
+- CLOSE intents are allowed while `EvidenceChainState != GREEN` only when not constrained by §2.2.3 Kill semantics and only if the dispatch is risk-reducing.
+- HEDGE intents are allowed while `EvidenceChainState != GREEN` only when not constrained by §2.2.3 Kill semantics and only if the dispatch is risk-reducing.
+- CANCEL intents without a replacement leg are allowed while `EvidenceChainState != GREEN` only when not constrained by §2.2.3 Kill semantics.
+- CANCEL/REPLACE intents are allowed while `EvidenceChainState != GREEN` only if the replace leg is NOT risk-increasing per §2.2.5.
 - Risk-increasing CANCEL/REPLACE MUST be rejected while `EvidenceChainState != GREEN` (see §2.2.5 definition).
 - When `enforced_profile != CSP`: EvidenceGuard triggers `RiskState::Degraded`; PolicyGuard computes `TradingMode::ReduceOnly` via the canonical axis resolver while `EvidenceChainState != GREEN`, and until GREEN recovers and remains stable for the cooldown window.
```
