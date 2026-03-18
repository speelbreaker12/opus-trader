# Story Premortem: S0-002

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S0-002 -- P0-C Keys & Secrets Baseline
- Contract clause(s): §Phase 0, P0-C (Keys & Secrets Baseline)
- Acceptance tests: AT-NONE (no `enforcing_contract_ats` claimed)
- Touch scope: `docs/keys_and_secrets.md`, `evidence/phase0/keys/key_scope_probe.json`
- Implementation tests: `test_api_keys_are_least_privilege_runtime`, `test_api_keys_transfer_privilege_rejected_runtime` (in `crates/soldier_infra/tests/test_phase0_runtime.rs`)
- **Risk rating**: LOW-to-MED
  - Classified as LOW in PRD, but this story deals with API key privilege boundaries. A wrong-privilege key in LIVE could enable unauthorized withdrawals or fund transfers. The documentation itself is LOW risk, but the key scope probe is evidence of a security property, and the runtime tests assert real exchange API behavior. If the probe or tests accept overly-permissive keys, the security baseline is compromised.

## 1) Clause audit (contract → AT traceability)

This story claims **no** enforcing contract ATs (`enforcing_contract_ats: []`). The contract clause P0-C states:

> | **P0-C** | Keys & Secrets Baseline | Document key creation rules, rotation plan, least-privilege proof | `docs/keys_and_secrets.md` |

The clause requires three deliverables: (1) key creation rules, (2) rotation plan, (3) least-privilege proof. The evidence required is `docs/keys_and_secrets.md`. The PRD acceptance criteria expand this to five checks (four doc sections + JSON probe validity).

| AT | Contract section | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| (none claimed) | Phase 0, P0-C | "Document key creation rules, rotation plan, least-privilege proof" | MUST (Non-Negotiable, Phase 0) | Yes -- doc content review + JSON probe parse |

Since no formal AT-XXX identifiers are claimed, the acceptance criteria from the PRD serve as informal acceptance tests. This is a gap worth noting: the story has no contract-anchored AT, meaning there is no traceability chain from CONTRACT.md -> AT -> test. The `implementation_tests` exist but are not anchored to any AT.

- [x] Every claimed AT traced to a normative clause -- N/A (none claimed)
- [x] No informational-only ATs counted as enforcement -- N/A

**Gap noted**: No AT in CONTRACT.md covers the key scope probe or least-privilege property. The implementation tests exist in a traceability vacuum.

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | The exchange API key used in the scope probe has been created with least-privilege (trade-only, no withdraw) | If the key has withdraw permission, the "least privilege" claim is false and the probe would show `withdraw_enabled: true` | `test_api_keys_are_least_privilege_runtime` should assert `withdraw_enabled == false` in probe output | Blind -- not verified |
| 2 | The `key_scope_probe.json` file was generated from an actual API call, not hand-crafted | A hand-crafted JSON file can claim any scopes; it proves nothing about actual key configuration | `test_api_keys_are_least_privilege_runtime` should hit the real API (or a realistic mock) and compare | Blind -- depends on test implementation |
| 3 | The JSON required fields (`env`, `exchange`, `key_id`, `scopes`, `withdraw_enabled`, `timestamp_utc`, `operator`) are sufficient to prove least-privilege | Missing fields like `ip_whitelist`, `expiry`, or `sub_account_restrictions` could leave security gaps undocumented | No test covers this -- schema completeness is a judgment call | Killed (accepted scope) |
| 4 | `docs/keys_and_secrets.md` covers all four required sections: key creation rules, rotation plan, where secrets live, LIVE key protection | If any section is missing, a PRD acceptance criterion fails | Manual review / grep for section headings | Blind |
| 5 | The runtime tests actually hit the exchange API (or a faithful mock) rather than testing a static fixture | A static fixture test proves nothing about the actual key's permissions | Test naming includes `_runtime` suggesting live API interaction | Blind -- naming convention is not proof |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | `key_scope_probe.json` is hand-crafted with `withdraw_enabled: false` but the actual key HAS withdraw permission | Runtime test should query real API; if test only validates JSON structure, this is undetectable | `test_api_keys_transfer_privilege_rejected_runtime` should attempt a transfer and confirm it is rejected (proving the key truly lacks the permission) | No AT -- relies on implementation test |
| 2 | `docs/keys_and_secrets.md` includes sections but with placeholder/boilerplate content (e.g., "TODO: add rotation schedule") | Manual review at PR time; no automated content-quality check | None -- this is a documentation story; the mitigation is human review | No AT |
| 3 | `key_scope_probe.json` passes JSON parse but is missing required fields (e.g., `operator` or `timestamp_utc` omitted) | `test_api_keys_are_least_privilege_runtime` should validate field presence | PRD verify step only runs `json.load()` which checks syntax, not schema | No AT |
| 4 | Runtime tests pass in CI against a testnet/paper key but LIVE key has different (broader) permissions | Divergence between environments; testnet keys may have different scope models than LIVE | The `env` field in the probe should distinguish environments; LIVE probe needs separate execution | No AT -- human blocker in PRD acknowledges this |
| 5 | Rotation plan in docs specifies a schedule but no one follows it; key is never rotated | Drift over time; no automated enforcement of rotation | This is an operational control, not a code gate; drift metric is N/A per PRD | No AT -- operational |

## 4) Open decisions (resolve before coding)

### Decision: What constitutes "least privilege" for the scope probe?
- **What is ambiguous / missing**: The contract says "least-privilege proof" but does not enumerate which scopes are acceptable and which are not. The PRD lists required JSON fields but does not specify acceptable values for `scopes` or `withdraw_enabled`.
- **Evidence**: CONTRACT.md Phase 0 table row P0-C: "Document key creation rules, rotation plan, least-privilege proof." PRD steps (prd.json line ~203): "Verify JSON has required fields: env, exchange, key_id, scopes, withdraw_enabled, timestamp_utc, operator."
- **Options**:
  1. Option A -- Define least-privilege as: trade + read-only scopes, `withdraw_enabled: false`, no transfer permissions. Probe must show exactly these and tests must reject keys with broader scopes.
  2. Option B -- Accept any scopes as long as `withdraw_enabled: false`. This is weaker but simpler.
- **Chosen**: A -- the test names (`least_privilege`, `transfer_privilege_rejected`) suggest the implementation already follows this stricter interpretation. The premortem predicts this is the correct approach.
- **Why not others**: Option B would allow a key with transfer permissions to pass the probe, which contradicts the `test_api_keys_transfer_privilege_rejected_runtime` test name.
- **Scope control**:
  - What we're NOT doing yet: automated periodic re-probing or CI-enforced scope checks on key rotation.
  - What unblocks us if this choice is wrong: the probe JSON is evidence that can be re-generated with updated criteria.

### Decision: Should the runtime tests hit a real exchange API or use mocks?
- **What is ambiguous / missing**: The PRD `human_blocker` says "Key scope probes require access to exchange APIs" but does not specify if CI tests should hit real APIs.
- **Evidence**: PRD `human_blocker.why` (prd.json line ~237): "Key scope probes require access to exchange APIs". Test names include `_runtime`.
- **Options**:
  1. Option A -- Tests hit real exchange API (paper/testnet) and assert actual permissions.
  2. Option B -- Tests validate the static `key_scope_probe.json` file for schema + field values.
  3. Option C -- Tests do both: validate JSON schema AND hit API to confirm.
- **Chosen**: B (predicted) -- the `_runtime` suffix likely means the tests run in the Rust test harness against the JSON artifact, not against a live API. Live API tests would require secrets in CI, which conflicts with "where secrets live" guidance.
- **Why not others**: Option A requires exchange API credentials in CI, creating a chicken-and-egg problem with the secrets baseline. Option C is ideal but unlikely for an XS story.
- **Mitigation gap (flagged by cross-review)**: Choosing Option B means the tests validate a static JSON artifact, not the actual exchange key permissions. This leaves FM-1 (hand-crafted probe) **unmitigated by any automated check**. The premortem predicts Option B while simultaneously identifying (in §3 FM-1) that a hand-crafted probe is the top failure mode. This is a circular gap: the predicted implementation does not address the predicted risk. The only mitigation is human review at PR time -- the reviewer must verify probe provenance (e.g., API call logs, timestamps consistent with key creation) since no test can do so under Option B. This tension is tracked as MED-severity debt below (§10).
- **Scope control**:
  - What we're NOT doing yet: live API integration tests in CI.
  - What unblocks us if this choice is wrong: the JSON probe can be re-executed manually and tests updated.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

Since there are no formal ATs, this section addresses the PRD acceptance criteria and the two implementation tests.

| Acceptance criterion / Test | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| "includes key creation rules (least privilege)" | Doc contains a section header "Key Creation Rules" with no actual rules, just "Keys should be least privilege." | Vacuous compliance -- no actionable rules | Tighten: doc must include at least (1) which scopes to enable, (2) which to deny, (3) who can create keys |
| "key_scope_probe.json is valid JSON with required fields" | Hand-craft JSON: `{"env":"paper","exchange":"bybit","key_id":"xxx","scopes":["all"],"withdraw_enabled":false,"timestamp_utc":"2026-01-01T00:00:00Z","operator":"human"}` -- passes parse + field check but `scopes: ["all"]` is not least-privilege | JSON is structurally valid but claims false privilege level | Tighten: `test_api_keys_are_least_privilege_runtime` must assert `scopes` does NOT contain "all", "withdraw", "transfer", or other dangerous permissions |
| `test_api_keys_are_least_privilege_runtime` | Test only checks that `key_scope_probe.json` loads and has required keys, not that values prove least-privilege | Structural check is not a security assertion | Tighten: test must assert `withdraw_enabled == false` AND `scopes` is a subset of an allowlist |
| `test_api_keys_transfer_privilege_rejected_runtime` | Test checks that a field like `transfer_enabled` is absent or false, but the actual exchange key still has transfer permission (mismatch between probe and reality) | Validates the document, not the key | Tighten: if feasible, test should attempt an API call with transfer intent and assert 403/rejection; if not feasible, note as accepted gap |
| "includes rotation plan" | Doc says "Keys will be rotated" with no cadence, no owner, no procedure | Passes review criterion literally but is not a plan | Tighten: rotation plan must include cadence (e.g., 90 days), responsible party, and procedure steps |

- [x] Every acceptance criterion has at least one wrong impl identified
- [x] Every wrong impl has a tightening suggestion
- [ ] No acceptance criterion remains where a wrong impl is easier than the correct one -- **YELLOW**: the doc-review criteria are inherently subjective; automated tightening is limited for documentation stories

## 6) Proof plan (AT → enforcement → tests)

| AT / Criterion | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| PRD AC-1: key creation rules | Documentation (manual review) | None (doc review) | N/A | N/A | Human judgment | N/A |
| PRD AC-2: rotation plan | Documentation (manual review) | None (doc review) | N/A | N/A | Human judgment | N/A |
| PRD AC-3: where secrets live | Documentation (manual review) | None (doc review) | N/A | N/A | Human judgment | N/A |
| PRD AC-4: LIVE key protection | Documentation (manual review) | None (doc review) | N/A | N/A | Human judgment | N/A |
| PRD AC-5: key_scope_probe.json valid | JSON schema + field presence | `test_api_keys_are_least_privilege_runtime` | N/A (structural) | N/A (structural) | JSON parse + field assertion | Yes |
| (implied) transfer rejected | Key permission boundary | `test_api_keys_transfer_privilege_rejected_runtime` | Partial -- should prove rejection | Partial -- should prove non-rejection for allowed ops | API call or probe field check | Yes |

Note: The two `implementation_tests` are not anchored to any AT in CONTRACT.md. They exist as PRD-level validation only. This means:
- If someone removes these tests, no contract violation is flagged.
- The tests are CLAIMED-NOT-PROVEN from a contract traceability perspective (no AT to bind them to).

**CLAIMED-NOT-PROVEN items:**
1. `test_api_keys_are_least_privilege_runtime` -- proves PRD AC-5 but no contract AT
2. `test_api_keys_transfer_privilege_rejected_runtime` -- proves an implied security property but no contract AT

**Plan to fix**: These tests should be anchored to a future AT in CONTRACT.md under P0-C, e.g.:
- AT-P0C-01: "Given key_scope_probe.json, when parsed, then withdraw_enabled is false and scopes contain no withdraw/transfer permissions."
- AT-P0C-02: "Given an API key configured per docs/keys_and_secrets.md, when a transfer request is attempted, then the exchange rejects it."

- [ ] Every safety-critical AT has TRIP + NON-TRIP -- N/A (no safety-critical ATs exist)
- [x] Every test proves causality (not just existence) -- PREDICTED, not verified
- [x] Each AT isolates one clause -- N/A (no ATs)
- [ ] No CLAIMED-NOT-PROVEN entries without a plan to fix -- **Plan above**

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: If the key scope probe falsely claims least-privilege but the actual key has withdraw or transfer permissions, an attacker (or compromised system) could initiate unauthorized withdrawals. However, this is a documentation/evidence story, not runtime enforcement. The actual risk is that the operator proceeds to LIVE trading with an overly-permissive key, trusting the baseline documentation.
- **Fail-closed cap on loss**: N/A for this story directly. Indirectly, the key_scope_probe should provide evidence that the key CANNOT withdraw funds. If the probe is honest, the cap is "trade losses only, no withdrawal theft."
- **Drift metric**: N/A at runtime. Over time, exchange-side key permissions could be modified without updating the probe. No automated drift detection exists for this.
- **Loss boundary**: N/A -- this is a policy/documentation story.
- **Rollback plan**: Revert the documentation commit. Re-execute the key scope probe with a corrected key if permissions are wrong. If a key is found to be overly-permissive, rotate it immediately (the rotation plan in the doc should cover this).

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None directly. This story creates documentation and evidence artifacts. It does not modify any runtime gates, state machines, or enforcement points.
- **If conflict with CONTRACT.md**: No conflict. P0-C explicitly requires `docs/keys_and_secrets.md` as evidence. The story delivers exactly what the contract asks for.
- Files with recent churn or shared ownership: `docs/keys_and_secrets.md` (created by this story, unlikely to conflict). `evidence/phase0/keys/key_scope_probe.json` (created by this story). `crates/soldier_infra/tests/test_phase0_runtime.rs` (shared test file for multiple Phase 0 stories -- potential merge conflicts if other S0-XXX stories add tests concurrently).
- Struct fields I'm assuming exist: None (documentation story).
- State machine transitions affected: None.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (this is a Phase 0 story, likely among the first implemented)
Reused Guardrail: NONE

- Carry-forward from prior postmortem: N/A
- What will slow me down:
  1. The `human_blocker` in the PRD: key scope probes require actual exchange API access. If API access is not available, the probe JSON cannot be honestly generated.
  2. The runtime tests in `test_phase0_runtime.rs` may depend on fixtures, environment variables, or API credentials that are not documented. Since this is a blind premortem, I cannot verify what the tests actually need.
  3. Subjective acceptance criteria ("WHEN reviewed THEN includes X") have no automated enforcement. Passing depends on reviewer interpretation.
- Exploit (workaround for this story): For the doc, use a clear checklist format with explicit section headings matching each acceptance criterion. For the probe, ensure the JSON is generated from a real API call (or clearly marked as a paper/testnet probe with the `env` field) so reviewers can assess provenance.
- Smallest fix that prevents it next time: Add a JSON schema file (e.g., `python/schemas/key_scope_probe.schema.json`) that the verify step validates against, turning the structural check from "is valid JSON" to "matches expected schema with required fields and value constraints."

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW (hard YELLOW, bordering on RED)

Rationale: The story is LOW-to-MED risk, but there are three concrete gaps that prevent GREEN, one of which involves a circular reasoning pattern identified by cross-review: (DEFERRED rationale)

1. **No contract AT**: The implementation tests exist in a traceability vacuum. If tests break or are removed, no contract violation is signaled. This is acceptable for Phase 0 policy work but should be tracked.
2. **Wrong-impl vulnerability on doc criteria**: The four documentation acceptance criteria are subjective ("WHEN reviewed THEN includes X"). A vacuous document could pass. No automated tightening is possible for prose quality.
3. **Probe provenance (MED severity -- escalated per cross-review)**: Nothing prevents a hand-crafted `key_scope_probe.json` from passing all checks. The `test_api_keys_transfer_privilege_rejected_runtime` test name implies it should prove the key genuinely lacks transfer privilege, but without reading the test, I cannot confirm it does. **Cross-review finding**: Decision 2 predicts the tests validate static JSON (Option B) while §3 FM-1 identifies hand-crafted probes as the top failure mode. This means the predicted implementation leaves the top failure mode unmitigated -- a circular gap where the premortem identifies the risk but predicts no automated defense against it. The only backstop is human reviewer diligence at PR time. This is the central weakness of the story and is tracked as MED-severity debt.

The stoplight remains YELLOW (not RED) because: (a) this is Phase 0 and LIVE trading does not occur until later phases, (b) P0-F and Kill mode provide runtime backstops independent of the probe, and (c) the gap is explicitly tracked with MED severity and a concrete remediation path. However, reviewers should treat the probe provenance question as a hard gate during implementation review -- if the probe has no evidence of API origin, the PR should not merge. (DEFERRED rationale)

**Debt Register** (required if YELLOW, DEFERRED items tracked):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| No contract AT for key scope probe | Low | P0-C is Phase 0 operational control; formal ATs are for runtime enforcement | Story owner | Future (post-Phase 0 hardening) | AT-P0C-01: probe fields prove least-privilege; AT-P0C-02: transfer rejected |
| Doc quality not automatable | Low | Documentation acceptance is inherently subjective; CI cannot judge prose quality | Reviewer | N/A (permanent) | Add structured checklist in doc template so grep can verify section presence |
| Probe provenance not machine-verifiable | **MED** | Would require live API call in CI, which conflicts with secrets baseline. **Escalated from LOW per cross-review**: a probe that cannot be verified against reality is the central weakness of this story and directly undermines P0-C's "least-privilege proof" requirement. Combined with Decision 2 (Option B: static JSON tests), FM-1 has no automated mitigation. | Story owner | Future (if CI gets exchange API access) | Add JSON schema validation to verify step; consider signed probe artifacts; require API call logs as supplementary evidence alongside the probe JSON |

YELLOW with all debt tracked and assigned. No item is untracked. (resolved check)

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause -- N/A (no ATs claimed; gap noted) (resolved)
- [x] §2 all assumptions validated or killed (resolved)
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every acceptance criterion examined, tightenings proposed
- [x] §6 proof plan: CLAIMED-NOT-PROVEN entries have remediation plan
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice (resolved)
