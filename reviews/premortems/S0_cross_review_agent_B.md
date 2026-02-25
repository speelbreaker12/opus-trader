# Premortem Cross-Review: Agent B
**Reviewing**: S0-000, S0-001, S0-004, S0-005
**Date**: 2026-02-23

---

## S0-000 Review
**Story**: P0-A Launch Policy Baseline

### Strengths
- Honest acknowledgment that all acceptance criteria are review-gated, not machine-gated. The premortem does not pretend this is safe; it explicitly flags the human-judgment dependency.
- Wrong implementation analysis (S5) is excellent for a doc-only story. The "instruments: see exchange documentation" wrong impl is a real-world failure that lazy implementers actually produce. Each wrong impl is specific and actionable.
- Decision D1 (pure Markdown vs. embedded YAML) is well-reasoned. Choosing prose with tables for S0-000 and deferring machine format to P0-F avoids premature commitment and keeps scope tight.
- Decision D2 (concrete numeric values) correctly reads "explicit" from CONTRACT.md as meaning unambiguous numbers, not qualitative prose. This is the right call and the reasoning is sound.
- S9 "exploit" (use deliberately conservative values) is a genuinely useful tactical insight that prevents analysis paralysis on domain judgment.

### Gaps Found
1. **Assumption 6 (P0-F format compatibility) has no concrete test or kill condition.** It is "deferred to P0-F story," but there is no mechanism to detect incompatibility early. If S0-000 produces a policy doc with an idiosyncratic table structure and S0-005 cannot parse it, the failure is discovered late. There should be at minimum a stated expectation of the table format (column names, data types) that P0-F can reference, or an explicit "interface contract" between the two stories.
2. **No assumption about who reviews and what "review" means.** The entire safety of this story rests on human review quality, but no assumption captures "the reviewer understands policy domain constraints" or "the reviewer checks numeric plausibility, not just structural completeness." A reviewer who rubber-stamps a structurally complete but numerically absurd policy (e.g., max position 10,000 BTC for paper trading) is not caught.
3. **Failure mode 4 (internal inconsistency) has no detection mechanism other than "domain expert review."** This is weaker than the other modes. What happens if no domain expert is available at review time? There is no fallback detection. The mitigation ("cross-reference values against exchange/account constraints") is aspirational without a concrete checklist of what to cross-reference.
4. **Debt register assigns all items to "S0-000 reviewer" -- this is a role, not a person.** If the story is reviewed by someone who does not read the debt register, the debt is orphaned. Consider naming an actual owner or at minimum linking to a tracking issue.

### Missing Failure Modes
- **Policy doc uses units that are ambiguous or incompatible with P0-F's eventual schema.** For example, "max position: 0.1" (0.1 what? BTC? contracts? USD-equivalent?). If units are unstated, P0-F's machine loader has to guess. This is distinct from FM-5 (prose-only) because a table with numbers but no unit labels looks structured but is semantically incomplete.
- **Policy doc references a snapshot of exchange constraints that may change.** For example, "exchange daily withdrawal limit: $50,000" -- if the exchange changes this, the policy doc is silently stale in a way that is not detectable by `diff` with the snapshot (both are stale). This is a "known-unknown becomes unknown-unknown" failure.

### Missing Wrong Implementations
- **All four environment names listed but with identical constraints per environment.** A lazy implementer could write a single set of limits and repeat them verbatim for DEV/STAGING/PAPER/LIVE, satisfying the "includes environments" criterion without actually differentiating safety postures per environment. The tightening should require the reviewer to verify at least one value differs between LIVE and non-LIVE environments (or explicitly justify identical limits).

### Stoplight Assessment
YELLOW is honest and appropriate. This is genuinely low-risk (doc only, no runtime behavior). The debt register is complete and items have target slices. No RED concerns.

### Verdict: ACCEPT

---

## S0-001 Review
**Story**: P0-B Environment Isolation

### Strengths
- Assumption 4 (key permissions actually enforced at exchange level) is sharp and shows genuine adversarial thinking. Most doc-story premortems would not question whether the documented permissions match reality.
- Assumption 5 (secrets not committed to repo) is concrete and testable -- `git log --all -p` is an actual command that could be run.
- Wrong implementation "Lists 'full permissions' for all environments including DEV" is an excellent catch. This is exactly the kind of wrong impl that would pass acceptance criteria while violating the spirit of environment isolation.
- Decision D1 (secrets storage granularity) shows good scope discipline -- documenting the storage system without tracing the full injection pipeline, explicitly noting P0-C owns the deeper treatment.
- The P0-C conflict boundary is clearly drawn: S0-001 documents WHAT exists; P0-C documents HOW keys are managed.

### Gaps Found
1. **No assumption about whether the four environment names (DEV/STAGING/PAPER/LIVE) are the actual canonical names.** Assumption 1 mentions the risk of different names but calls the test "manual review: compare against actual infrastructure config." In a Phase 0 doc-only story, if no actual infrastructure exists yet, this comparison is impossible. The assumption should acknowledge this and decide: are we documenting PLANNED environments or EXISTING ones? If planned, the doc is aspirational, which is fine, but should be explicitly stated.
2. **Failure mode 2 (aspirational documentation) is the most dangerous one, but its mitigation relies entirely on P0-C.** If P0-C is implemented much later or never, the aspirational-vs-factual gap is never checked. There should be a self-contained mitigation for S0-001, not just a cross-reference to another story. For instance: "Each environment row must be marked VERIFIED or PLANNED" so reviewers know what has been confirmed vs. assumed.
3. **The snapshot drift failure mode (FM-5) is identical to S0-000's FM-2.** Both stories have the same gap (snapshot goes stale) with the same non-mitigation (process discipline). This is a systemic gap across all Phase 0 doc stories. Neither premortem proposes a shared solution, suggesting each story will independently hope for discipline. A shared CI script would close this for all Phase 0 stories at once.

### Missing Failure Modes
- **Environment matrix is complete but self-contradictory.** For example, DEV row says "no trade permissions" but STAGING row says "shared account with DEV" -- if STAGING has trade permissions and shares an account with DEV, DEV effectively has trade permissions too. The matrix passes all structural checks while documenting a configuration that violates its own isolation claims. Detection requires row-level cross-referencing, not just cell-level completeness.
- **Document omits network isolation.** P0-B says "document environment separation" but the matrix as described covers only accounts, keys, and secrets. If environments share a VPC, subnet, or deployment host, they are not truly isolated regardless of having separate API keys. This may be out of scope for the story, but the premortem should acknowledge it as a known limitation.

### Missing Wrong Implementations
- **Matrix uses "N/A" for unprovisioned environments instead of leaving them out.** A matrix with DEV and LIVE rows fully populated and STAGING/PAPER rows filled with "N/A" satisfies "lists each environment" and "shows which exchange account per env" (the answer is "N/A"). This is technically correct but practically useless for isolation assurance. The tightening should require that "N/A" entries are accompanied by a provisioning plan or explicitly marked as blocking for Phase 1.

### Stoplight Assessment
YELLOW is appropriate. The debt register is well-structured with target slices. One observation: the debt item "acceptance criteria accept vacuous docs" with owner "S0-001 author" and target "PRD amendment" is realistic but the timeline for PRD amendments is unclear. If no one ever amends the PRD, this debt lives forever.

### Verdict: ACCEPT

---

## S0-004 Review
**Story**: P0-E Health + Owner Status Scaffolding

### Strengths
- The AT-022 tension analysis is the best part of this premortem. It clearly identifies that the story claims AT-022 but can only partially satisfy it (data model, no HTTP), flags this as CLAIMED-NOT-PROVEN, and tracks it with an explicit completion target (S8-008). This is exactly the right way to handle scope gaps.
- Assumption 1 (`contract_version` exact format) is precise and testable. Identifying `"v5.2"` vs `"5.2"` as a real failure mode with F1_CERT implications shows awareness of downstream impacts.
- Wrong implementation analysis is thorough. The `ok` hardcoded-as-const wrong impl is particularly good -- it catches a subtle mistake where the field technically exists but cannot be set to `false`, which would break health reporting in S8-008.
- Decision D3 (build_id as constructor parameter) is sound engineering -- dependency injection keeps tests deterministic and defers production wiring.
- The proof plan correctly notes that TRIP/NON-TRIP is not meaningful for pure scaffolding and explains why.

### Gaps Found
1. **Assumption 3 (TradingMode enum availability) has no fallback plan.** The assumption says "Depends on prior story ordering; verify before coding" but does not state what happens if TradingMode does not exist yet. Should S0-004 define it? Import it? Block on another story? The premortem should resolve this: either declare a dependency on a specific prior story or include TradingMode definition in S0-004's scope.
2. **No assumption about serialization format.** The structs need `#[derive(Serialize)]` but the premortem does not discuss whether the JSON field names must match CONTRACT.md exactly (e.g., `ok` vs `is_ok`, `build_id` vs `buildId`, snake_case vs camelCase). AT-022 specifies key names `ok`, `build_id`, `contract_version` -- if serde's default (Rust field name) does not match the contract-mandated JSON key name, the serialization is silently wrong. This is especially dangerous because Rust convention is snake_case (which happens to match for these fields), but `is_trading_allowed` vs `isTradingAllowed` could diverge. There should be a golden-vector test that asserts the exact JSON keys.
3. **Failure mode 3 (structs never exported) mentions a visibility test but is vague.** "Construct from an integration test (different crate boundary)" is the right approach but the premortem does not commit to actually creating an integration test. If only unit tests within the same crate are written, `pub(crate)` passes all tests. This should be a mandatory test, not a suggestion.
4. **The owner status fields (`trading_mode`, `is_trading_allowed`) have no formal AT anchor in CONTRACT.md S7.0.** The premortem flags this in the debt register but treats it as Low severity. Given that `is_trading_allowed` is operator-facing and incorrect derivation could cause delayed incident response (FM-2), this should arguably be Medium severity. An operator trusting `is_trading_allowed=true` during ReduceOnly is a real safety concern.

### Missing Failure Modes
- **Serde field name mismatch with CONTRACT.md.** The health response JSON must have keys exactly as specified: `ok`, `build_id`, `contract_version`. If the Rust struct uses `#[serde(rename = "...")]` or relies on default naming that does not match (unlikely for these specific fields but possible for `is_trading_allowed` in owner status), the serialized output will not match what S8-008 or external consumers expect. A golden-vector test that serializes the struct and asserts exact JSON output would catch this. This is different from FM-1 (wrong value) -- here the value is correct but the key name is wrong.
- **`OwnerStatus` struct does not include all fields mandated by the Phase 0 table.** P0-E in CONTRACT.md says "returning `ok`, `build_id`, `contract_version`, `trading_mode`, `is_trading_allowed`." If the scaffolding produces separate `HealthResponse` and `OwnerStatus` structs (a reasonable design), there is a risk that the combined surface does not cover all five fields. The premortem discusses `HealthResponse` and `OwnerStatus` as separate concerns but does not verify that together they satisfy P0-E completely.

### Missing Wrong Implementations
- **`is_trading_allowed` derived from a default match arm `_ => false` instead of exhaustive matching.** This passes the three-variant test (Active->true, ReduceOnly->false, Kill->false) but if a fourth TradingMode variant is added later (e.g., `Maintenance`), the wildcard silently maps it to `false`. The wrong impl should require exhaustive matching without wildcards to force explicit decisions when variants change. The premortem mentions this parenthetically ("no wildcard `_ => false`") in S5 but does not escalate it to a mandatory tightening -- it is buried in a comment.

### Stoplight Assessment
YELLOW is honest but borderline. The AT-022 CLAIMED-NOT-PROVEN is the most significant gap. The debt register correctly tracks it at Medium severity with S8-008 as the target. The `is_trading_allowed` AT anchor gap at Low severity is arguably under-rated but not a blocker.

### Verdict: ACCEPT

---

## S0-005 Review
**Story**: P0-F Machine Policy Loader Baseline

### Strengths
- This is the strongest premortem of the four. The failure mode analysis is genuinely adversarial and practical.
- FM-1 (loader accepts empty JSON `{}`) is the most important failure mode for this story, and it is correctly identified as the top risk. The mitigation is specific: required field list, test with `{}`, assert non-zero exit.
- FM-2 (policy path not bound at runtime / "paper-only" loader) is the deepest insight in any of the four premortems. It identifies the risk that the Python loader validates one path while the Rust binary reads from a completely different source, making the entire validation chain cosmetic. The mitigation (prove runtime path binding by removing the file and observing failure) is the right approach.
- Wrong implementation analysis is the most comprehensive of the four. The cross-cutting entry (Python validates, Rust ignores) is particularly valuable -- it catches a failure mode that spans two languages and two stories.
- Decision D1 (schema strictness) correctly rejects Option B (any valid JSON) by reasoning that a loader accepting `{}` is "effectively doc-only," which directly contradicts P0-F's contract purpose.
- The proof plan's TRIP/NON-TRIP for runtime binding is well-structured and uses the right causality proof (the ONLY difference is file presence/absence).

### Gaps Found
1. **Assumption 2 (runtime path binding) is the most critical assumption but its test is described generically.** "Must prove the Rust side reads the same path" -- how? The test needs to assert something like "the runtime reads from env var $POLICY_PATH which is the same var used by the Python loader" or "both read from the hardcoded path `config/policy.json`." If the Python loader uses `config/policy.json` but the Rust binary uses `$POLICY_PATH` (or vice versa), the test must detect the mismatch. The premortem should specify the binding mechanism (shared path constant, shared env var, or runtime flag) so the test can verify identity, not just that "some file is read."
2. **No assumption about what happens to the loader when the schema evolves.** The premortem acknowledges in S9 that "the policy schema will evolve as S2.2 PolicyGuard is implemented" but does not create an assumption or failure mode for schema migration. When a later story adds a required field to `config/policy.json`, the strict loader will reject all existing policy files that lack the new field. This is fail-closed (good) but could cause a deployment outage if the policy file is not updated atomically with the loader. This is a cross-story interaction concern.
3. **Assumption 3 (unknown fields rejected) does not address forward compatibility.** If `deny_unknown_fields` is enforced, a policy file written for a newer schema version (with extra fields) cannot be loaded by an older loader. This may be intentional (strict lockstep) but should be an explicit decision, not an unstated assumption.
4. **The debt register flags "no formal AT-XXX in CONTRACT.md for P0-F" at Medium severity.** This is the right severity, but the owner is "Story implementor" which is vague. In contrast, S0-004's debt register assigns to "S8-008 implementor" which is more specific. Who is the S0-005 story implementor? If it is the current agent, the debt should be resolved during implementation, not deferred.

### Missing Failure Modes
- **Loader validates schema but not value ranges.** A policy file with `{"max_position_btc": -5.0, "daily_loss_limit_usd": 0, "max_order_rate_per_sec": 999999}` could pass structural validation (all required fields present, correct types) while specifying nonsensical or dangerous values. This is the policy-loader equivalent of S0-000's FM-4 (internal inconsistency). The loader should either validate ranges or explicitly document that range validation is deferred.
- **Loader succeeds but produces different behavior on different Python versions.** If the loader uses Python-version-specific JSON parsing behavior (e.g., `json.loads` handling of trailing commas, large integers, or NaN), the same policy file could pass on one Python version and fail on another. This is particularly relevant for a CI vs. production environment mismatch.
- **The meta-test tests the loader but not the policy file checked into the repo.** The meta-test might use a test fixture (`test_policy.json`) that passes validation, while the actual `config/policy.json` checked into the repo fails. If CI runs the meta-test with the fixture and not the real file, the actual policy file is never validated. The meta-test should also validate the canonical `config/policy.json`.

### Missing Wrong Implementations
- **The Rust runtime test asserts policy loading but accepts a default/fallback policy.** If the Rust side has `config.policy.unwrap_or(default_policy())`, removing the file does not cause failure -- the runtime just uses defaults. The TRIP test (file absent -> failure) would not trip. The test must verify that no default policy exists or that the runtime panics/enters ReduceOnly specifically due to file absence. The premortem's assumption 5 partially covers this but does not identify it as a wrong implementation that could pass the proposed tests.

### Stoplight Assessment
YELLOW is appropriate and arguably generous -- the "no formal AT-XXX" gap is a real traceability hole. However, for a Phase 0 infrastructure story, it is reasonable to defer formal AT creation. The debt register is complete.

### Verdict: ACCEPT

---

## Cross-Story Findings

### 1. Systemic snapshot-drift gap across all doc stories (S0-000, S0-001)
Both S0-000 and S0-001 identify snapshot staleness as a failure mode (S0-000 FM-2, S0-001 FM-5) with the same non-mitigation: "process discipline" and "could add a CI check." Neither premortem proposes a shared solution. Since all Phase 0 doc stories (P0-A through P0-D) produce evidence snapshots, this gap applies to at least four stories. A single CI script that diffs all `docs/*.md` against their corresponding `evidence/phase0/*/` snapshots would close this for all of them. The fact that both premortems independently identify this and independently defer it suggests it should be elevated to a cross-cutting concern with its own tracking item.

### 2. S0-000 to S0-005 interface is loosely defined
S0-000's assumption 6 says P0-F will consume the policy document, and S0-000 chooses "pure Markdown prose with tables." S0-005's decision D3 says the Python loader is the canonical strict validator of `config/policy.json`. But there is a missing link: who creates `config/policy.json` from `docs/launch_policy.md`? S0-000 produces the human-readable doc. S0-005 validates and loads the machine-readable JSON. But neither story owns the transformation from Markdown tables to JSON. If no story owns this, `config/policy.json` could be hand-created with values that disagree with `docs/launch_policy.md`, and the strict loader would happily validate a policy file that contradicts the launch policy doc. This is a gap between the two stories, not within either one individually.

### 3. S0-004 and S0-005 have an implicit ordering dependency that neither acknowledges
S0-004 scaffolds the health/status data model including `TradingMode`. S0-005 creates a policy loader that binds `config/policy.json` to the runtime. If the policy JSON includes a `trading_mode_default` field (as S0-005's S9 suggests), and S0-004 defines the `TradingMode` enum, then S0-005's schema must align with S0-004's enum variants. Neither premortem identifies this as a cross-story constraint. If S0-005 is implemented first and uses a string `"active"` where S0-004 later defines `TradingMode::Active`, there is a deserialization mismatch.

### 4. Review-gated vs. machine-gated asymmetry
S0-000 and S0-001 are entirely review-gated (no ATs, no automated checks). S0-004 has a partial AT (AT-022, data model only). S0-005 has no formal ATs but has implementation tests with TRIP/NON-TRIP. The four stories form a spectrum from "pure human judgment" (S0-000) to "partial machine proof" (S0-005), but the premortems do not acknowledge this asymmetry or its implications. The weakest links in the Phase 0 chain are the doc-only stories, and their failure modes compound: if S0-000 has vague policy values AND S0-005's loader does not validate value ranges, garbage flows from human doc to machine config without resistance.

### 5. No premortem considers the "all Phase 0 stories pass but the system is still unsafe" scenario
Each premortem evaluates its own story in isolation. None asks: "If every Phase 0 story passes its acceptance criteria, is the system actually safe to proceed to Phase 1?" This is a composition gap. For example: S0-000 could have valid policy values, S0-001 could have a correct env matrix, S0-004 could have correct health scaffolding, S0-005 could have a working loader -- but if the policy values in S0-000 are never loaded into `config/policy.json` (the S0-000/S0-005 interface gap from finding #2), the system enters Phase 1 with a validated-but-wrong machine policy. The premortems are individually sound but collectively incomplete because no story owns the integration.

### 6. Shared blind spot: no premortem discusses what happens if Phase 0 items are completed out of order
The CONTRACT.md Phase 0 table lists P0-A through P0-F but does not specify an ordering. The premortems assume independence (each says "prior postmortem: NONE"). But if S0-005 (policy loader) is implemented before S0-000 (launch policy doc), the loader has no `docs/launch_policy.md` to reference, and the `config/policy.json` is created from scratch without a human-approved policy baseline. This is not necessarily wrong, but it means the "machine-readable policy derived from human policy" chain that CONTRACT.md implies (P0-A -> P0-F) is not enforced by story ordering. The premortems should either declare independence explicitly or document the assumed ordering.
