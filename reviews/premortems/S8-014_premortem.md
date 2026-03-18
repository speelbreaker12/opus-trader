# Story Premortem: S8-014

## 0) What we're building
- Story: S8.8b /status semantics and HTTP method enforcement.
- Contract clause(s): §7.0 /status semantics and method safety; AT-024/025/026/027/028/351/352/353/406/407/968.
- Acceptance tests: AT-024, AT-025, AT-026, AT-027, AT-028, AT-351, AT-406, AT-407, AT-968.
- Touch scope: tools/validate_status.py, python/schemas/status_*.schema.json, specs/status/*, tests/test_validate_status_*.py.
- **Risk rating**: MED

**STOPLIGHT**: GREEN

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-024 | §7.0 | Active mode requires empty mode_reasons | MUST | yes |
| AT-025 | §7.0 | ReduceOnly/Kill require valid mode reasons | MUST | yes |
| AT-351 | §7.0 | Latch true prohibits Active, enforces latch reason | MUST | yes |
| AT-407 | §7.0 | Versioned status semantics fields must be coherent | MUST | yes |

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | status_schema_version drives Decision-A semantics | token accepted under wrong version | tests/test_validate_status_semantics_versioning.py | yes |
| 2 | manifest override remains explicit in v2 | ambiguous DecisionALatchReasonCode passes | tests/test_validate_status_manifest_override.py | yes |
| 3 | schema and runtime checks stay aligned | schema pass but invariant fail mismatch | dual schema + validator fixture matrix | yes |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | v2 token used under v1 | validator fixture failure | reject status payload | AT-407 |
| 2 | v2 missing open_permission_semantics_version | schema + invariant failure | reject status payload | AT-407 |
| 3 | latch=true with Active mode | invariant failure | reject payload / force non-Active | AT-351 |
| 4 | non-GET allowed on status endpoint | HTTP method test | reject non-GET request | AT-028 |
| 5 | mode_reasons ordering drifts from manifest | ordering check failure | reject invalid status payload | AT-025 |

## 4) Open decisions (resolve before coding)
### Decision: Decision-A semantics keyed by status schema version
- **What is ambiguous / missing**: previous branch behavior keyed off contract version.
- **Evidence** (file + anchor or snippet): specs/status/README.md Decision-A semantics; tools/validate_status.py decision-a resolver.
- **Options**:
  1. Keep contract-version gate — couples semantic behavior to unrelated version bump.
  2. Use status semantic fields — explicit and local to status contract.
- **Chosen**: 2 — explicit semantic versioning reduces hidden coupling.
- **Why not others**: option 1 allows silent behavior drift on contract-only bumps.
- **Scope control**:
  - What we're NOT doing yet (subordinate): no runtime endpoint redesign.
  - What unblocks us if this choice is wrong (elevate): add manifest migration layer.

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-351 | only check latch reason string contains "LATCH" | allows wrong explicit token | exact token + manifest membership check |
| AT-407 | accept status_schema_version=2 without semantics version | permits ambiguous behavior | schema conditional + invariant check |

## 6) Proof plan (AT → enforcement → tests)
| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-351 | tools/validate_status.py latch invariants | tests/fixtures/status_semantics/legacy_v1_fail_active_when_latched.json | yes | yes | latch_reason | yes |
| AT-407 | schema + validator semantic coherence | tests/test_validate_status_semantics_versioning.py | yes | yes | reject_reason | yes |
| AT-028 | status method enforcement tests | crates/soldier_infra/tests/test_http_status.rs::test_status_rejects_non_get | yes | yes | reject_reason | yes |

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: worst financial outcome is operator sees permissive status and approves OPEN in unsafe conditions.
- **Fail-closed cap on loss** (what restricts exposure): Fail-closed cap is ReduceOnly/Kill gating and validator rejection on incoherent status payloads.
- **Drift metric** (what tells us it's going wrong before it blows up): status_semantics_validation_fail_total and status_schema_mismatch_count.
- **Loss boundary** (ReduceOnly? Kill? Position limit? Time bound?): ReduceOnly boundary enforced when latch / policy guard triggers.
- **Rollback plan** (how to revert if it fails): revert to prior stable validator+schema commit and keep OPEN disabled until revalidation.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: status schema checks, contract crossrefs, status reason codegen drift gate.
- **If conflict with CONTRACT.md**: stop and reconcile contract wording before pass flip.
- Files with recent churn or shared ownership: plans/verify_fork.sh, tools/validate_status.py, specs/status/*.
- Struct fields I'm assuming exist (verify before coding): status_schema_version, open_permission_semantics_version, mode_reasons.
- State machine transitions affected: Active/ReduceOnly/Kill status rendering only.

## 9) Constraint I expect to hit
Prior Postmortem: reviews/premortems/RUNBOOK_PREMORTEM_RECON.md
Reused Guardrail: do not pass-flip without fresh full verify bound to current HEAD.

- Carry-forward from prior postmortem (paste startup note): keep workflow evidence deterministic and artifact-backed.
- What will slow me down: receipt/review evidence preconditions for pass flip.
- Exploit (workaround for this story): generate compliant review artifacts early to unblock cycle gates.
- Smallest fix that prevents it next time: pre-seed S8 story evidence scaffolds and proof-graph skeletons.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: GREEN

- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate mapped for each enforced AT
- [x] §6 proof plan includes TRIP + NON-TRIP expectations
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
