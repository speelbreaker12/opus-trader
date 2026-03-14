# Contract Autoresearch Design

Two-phase Karpathy-style improvement loop for `specs/CONTRACT.md`. Phase 1 calibrates a detection skill that finds contract gaps. Phase 2 calibrates a patch skill that generates proposals to fix them. Human review gate controls what reaches the contract; shadow graduation earns trust for mechanical auto-apply.

> **Revision note (2026-03-14, v7)**: Applied fixes from the blocker batch plus the remaining high-risk boundary hardening for `cross_ref_broken` and Phase 2 runner isolation. Key changes: AT-ID-only restriction on cross_ref_broken auto-apply (CRITICAL-4), graduation exemption rationale (CRITICAL-5), scope-narrowing detection in check_contradictions.py (CRITICAL-3), no-op patcher blocked via assertion 8 (CRITICAL-1), mechanical_ok/change_type disambiguation (CRITICAL-2), harness-level write isolation architecture (HIGH-1), contract_file_hash field rename (HIGH-2), dual-pass validate_proposals.sh (HIGH-3), json_field_not_match rule type added (HIGH-4), enforcement_point/callsite_evidence allOf branch (HIGH-5), dedupe_key uniqueness assertion (HIGH-6), snapshot fixture tracking in context_manifest (MED-6), expected_gate_input_count refresh in post-apply cycle (MED-2), minLength/minimum schema bounds (MED-3/LOW-1), source_finding_category field added (HIGH-5), idempotency guard in apply_proposals.py (LOW-2), category guard in auto-apply path (LOW-3), SHALL added to contradiction checker (LOW-4), post-verify state transition fix (`verifying` intermediate state + atomic rollback of CONTRACT/index), canonical `./plans/verify.sh full` path, `pending_scope_review` routing for scope narrowing, rubric isolation for `eval.json`/fixture metadata, fail-closed clause outcome-term counting, contradiction-checker crash fail-closed behavior, source-finding referential integrity, ID uniqueness checks, pre-write `verifying` state with recovery via `apply_base_hash`/`apply_candidate_hash`, same-section/same-test-type gating for `cross_ref_broken`, promotion-time common-context hash pinning, concrete `claude --cwd` + local permission-profile enforcement for loop isolation, authoritative category cross-checking against `findings.json`, `check_enforcement.py` wiring into both validation passes, and an explicit fixture-to-live coordinate bridge for promotion.

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Architecture | Two independent loops (Approach 1) | Clean separation: each loop optimizes one skill. Phase 1 planted-gap fixtures are stable across contract changes. |
| Phase 1 fixtures | Planted-gap (6 mutated + 1 clean) | Ground truth is known; detector quality is measurable via precision/recall. |
| Phase 2 fixtures | Dual-layer (static seeds + latest snapshot) | Static seeds prevent ratchet from destroying regression coverage; snapshots track real quality. |
| Phase 2 scoring | Structural assertions on `patched_fixture = apply(proposals, fixture)` | The loop must optimize the patcher, not the current contract state. Proposal-validity assertions are scored separately. |
| Phase 2 write boundary | `phase2/proposals/` (read-only CONTRACT.md during loop) | No accidental commitments. Proposals are reviewed before promotion. |
| Graduation model | Propose-then-apply → shadow graduation → tiered auto-apply | Start conservative, earn trust with evidence, then open throttle per category. |
| Seed sections | §2.2 PolicyGuard + §1 Execution Pipeline | Highest economic blast radius. Densest AT coverage. |

## Prerequisites

This spec extends the skill autoresearch infrastructure at `autoresearch/skills/`:

- `autoresearch/skills/harness.sh` — CLI harness (run, scaffold, baseline, eval, status)
- `autoresearch/skills/evaluate.py` — binary assertion evaluator (11 rule types)
- `autoresearch/skills/program.md` — autonomous loop protocol
- `autoresearch/skills/premortem/` — first eval target (5 fixtures, 25 assertions)

These files exist in the repository. The contract subcommand reuses the same loop protocol and evaluator, adding 7 new rule types and a `contract` command namespace.

---

## 1. Directory Structure

```
autoresearch/
  contract/
    common/                                # Shared context for both phases
      contract_header.md                   # §0.0 normative scope + definitions
      at_registry.json                     # AT registry: at_id, source section, test_type, one-line description, gate_input_names (string array — gate input names this AT's assertion covers, used for cross_ref_broken equivalence gating)
      section_index.md                     # Section → line range mapping for CONTRACT.md
      context_manifest.json                # Hash of each shared file; detects stale context
    phase1/                                # Detection skill optimization
      eval.json                            # Planted-gap assertions
      findings.schema.json                 # JSON Schema for detector output
      internal/
        fixture_metadata.json              # Harness-only metadata (injected_tokens, assertion-side whitelists)
      fixtures/
        s2_2_missing_fail_closed.md
        s2_2_should_vs_must.md
        s1_gate_ordering_gap.md
        s1_missing_at_pair.md
        s2_2_stale_input_no_spec.md
        s1_cross_ref_broken.md             # AT reference to non-existent section
        s2_2_clean.md                      # No defects — precision anchor
      outputs/<run_id>/
        <fixture_id>/
          T1.md                            # Raw model output for this fixture
          findings.json                    # Structured findings for this fixture
      results.tsv
    phase2/                                # Contract quality optimization
      eval.json
      proposals.schema.json
      fixtures/
        static/                            # Never replaced — regression anchor
          s2_2_policyguard_seed.md
          s1_execution_pipeline_seed.md
          s2_2_no_change.md                # Clean fixture — zero proposals expected
        snapshot/                          # Re-extracted after CONTRACT.md changes
          s2_2_policyguard_latest.md
          s1_execution_pipeline_latest.md
      outputs/<run_id>/
        <fixture_id>/
          T1.md                            # Raw model output for this fixture
          findings.json                    # Phase 1 detector output for this fixture
          proposals.json                   # Patch skill output for this fixture
          patched/
            <fixture_id>.patched.md        # Staged apply for this fixture
      proposals/
        CONTRACT_PROPOSALS_<run_id>.md     # Human-readable per-run output
      proposals_index.json                 # Machine-readable run tracker
      results.tsv
  skills/                                  # Existing skill autoresearch
    harness.sh
    evaluate.py
    program.md
    premortem/

SKILLS/
  contract-gap-detector.md                 # Phase 1 target
  contract-patch.md                        # Phase 2 target

specs/
  CONTRACT.md                              # Read-only during loops
```

`proposals_index.json` fields: `run_id`, `timestamp`, `contract_file_hash`, `context_manifest_hash`, `status` (pending|reviewed|verifying|applied|rejected|stale), `proposal_count`, `accepted_count`, `file_path`, optional `apply_base_hash`, optional `apply_candidate_hash`, optional `applied_contract_hash`. `context_manifest_hash` is the SHA256 of `common/context_manifest.json` at proposal generation time.

**`stale` status trigger**: A proposal entry transitions to `stale` when its reviewed generation basis no longer matches the current repository state. At minimum, the harness compares: (a) current CONTRACT.md SHA256 vs `contract_file_hash`, and (b) current `context_manifest.json` SHA256 vs `context_manifest_hash`. Any mismatch blocks promotion and requires re-running Phase 2 on fresh context.

**`verifying` status semantics**: `verifying` means the proposal batch is in a recoverable promotion window. Before the live `CONTRACT.md` rename, the harness records `apply_base_hash` and `apply_candidate_hash` in `proposals_index.json` and marks the batch `verifying`. Recovery logic compares the current `CONTRACT.md` hash against those values:
- current hash == `apply_base_hash` → interrupted before live apply; restore index state to `reviewed`
- current hash == `apply_candidate_hash` → interrupted after live apply; resume or re-run `./plans/verify.sh full`, or restore both `CONTRACT.md` and `proposals_index.json` from the pre-apply snapshot
- any other hash → block with manual recovery required

A batch in `verifying` is not a successful promotion state and MUST block new apply attempts until recovery completes.

---

## 2. Schemas

### 2.1 Findings Schema (`phase1/findings.schema.json`)

> **Artifact location convention**: outputs are stored at `outputs/<run_id>/<fixture_id>/findings.json` and `outputs/<run_id>/<fixture_id>/proposals.json`. The `run_id` and `fixture_id` are derived from the directory path; they are NOT required fields in the JSON file itself. The harness validates the directory structure before scoring. This eliminates single-`fixture_id` ambiguity and enables per-fixture failure attribution.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["generated_at", "validator_version", "findings"],
  "additionalProperties": false,
  "properties": {
    "generated_at": { "type": "string", "format": "date-time" },
    "validator_version": { "type": "string" },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["finding_id", "section", "category", "severity", "description", "evidence", "proposed_fix_type", "proposed_fix"],
        "additionalProperties": false,
        "properties": {
          "finding_id": { "type": "string", "pattern": "^F-[0-9]{3,}$" },
          "section": {
            "type": "string",
            "description": "Canonical section anchor from section_index.md. Promotion resolves against the current CONTRACT.md section identified here; fixture-local line numbers are never reused as live write coordinates."
          },
          "category": {
            "type": "string",
            "enum": ["missing_fail_closed", "weak_normative", "missing_at_pair",
                     "stale_input_unspecified", "gate_interaction_gap", "cross_ref_broken"]
          },
          "severity": { "type": "string", "enum": ["P0", "P1", "P2"] },
          "description": { "type": "string" },
          "evidence": {
            "type": "object",
            "required": ["line", "quote"],
            "additionalProperties": false,
            "properties": {
              "line": { "type": "integer" },
              "quote": { "type": "string", "maxLength": 200 },
              "context": { "type": "string" }
            }
          },
          "proposed_fix_type": { "type": "string", "enum": ["mechanical", "new_requirement"] },
          "proposed_fix": { "type": "string" }
        }
      }
    }
  }
}
```

### 2.2 Proposals Schema (`phase2/proposals.schema.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["generated_at", "validator_version", "proposals"],
  "additionalProperties": false,
  "properties": {
    "generated_at": { "type": "string", "format": "date-time" },
    "validator_version": { "type": "string" },
    "proposals": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["proposal_id", "source_finding", "source_finding_category", "section", "change_type", "rationale", "status", "dedupe_key"],
        "additionalProperties": false,
        "properties": {
          "proposal_id": { "type": "string", "pattern": "^P-[0-9]{3,}$" },
          "source_finding": { "type": "string", "pattern": "^F-[0-9]{3,}$" },
          "section": {
            "type": "string",
            "description": "Canonical section anchor from section_index.md. Promotion resolves against the current CONTRACT.md section identified here; fixture-local line numbers are never reused as live write coordinates."
          },
          "change_type": { "type": "string", "enum": ["mechanical", "new_requirement"] },
          "rationale": { "type": "string" },
          "status": { "type": "string", "enum": ["proposed", "accepted", "pending_scope_review", "rejected", "stale"] },
          "dedupe_key": { "type": "string", "minLength": 1 },
          "replace_span": {
            "type": "object",
            "required": ["start_line", "end_line", "old_text", "new_text"],
            "additionalProperties": false,
            "properties": {
              "start_line": { "type": "integer", "minimum": 1 },
              "end_line": { "type": "integer", "minimum": 1 },
              "old_text": { "type": "string", "minLength": 10 },
              "new_text": { "type": "string", "minLength": 1 }
            }
          },
          "proposed_text": { "type": "string" },
          "mechanical_ok": { "type": "boolean" },
          "mechanical_details": { "type": "string" },
          "enforcement_point": { "type": "string" },
          "callsite_evidence": { "type": "string" },
          "new_ats": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["at_id", "description"],
              "additionalProperties": false,
              "properties": {
                "at_id": { "type": "string", "pattern": "^AT-PROP-[0-9]{3,}$" },
                "description": { "type": "string" }
              }
            }
          },
          "diff_preview": { "type": "string" },
          "source_finding_category": {
            "type": "string",
            "enum": ["missing_fail_closed", "weak_normative", "missing_at_pair",
                     "stale_input_unspecified", "gate_interaction_gap", "cross_ref_broken"],
            "description": "Category of the source finding (mirrors findings.schema.json category). Required on every proposal so category-specific validation cannot be bypassed by omission."
          }
        },
        "allOf": [
          {
            "if": { "properties": { "mechanical_ok": { "const": true } } },
            "then": { "required": ["replace_span", "mechanical_details"] }
          },
          {
            "if": { "properties": { "change_type": { "const": "new_requirement" } } },
            "then": { "required": ["proposed_text"] }
          },
          {
            "if": {
              "properties": { "change_type": { "const": "mechanical" } },
              "required": ["change_type"]
            },
            "then": {
              "required": ["mechanical_ok"],
              "description": "mechanical change_type requires mechanical_ok to be explicitly true or false. If mechanical_ok is false, the proposal must be retyped as new_requirement."
            }
          },
          {
            "if": {
              "properties": {
                "change_type": { "const": "mechanical" },
                "mechanical_ok": { "const": false }
              },
              "required": ["change_type", "mechanical_ok"]
            },
            "then": {
              "not": {},
              "description": "FORBIDDEN: change_type=mechanical with mechanical_ok=false. Use change_type=new_requirement for proposals without a verified replace_span."
            }
          },
          {
            "if": {
              "properties": { "source_finding_category": { "const": "weak_normative" } },
              "required": ["source_finding_category"]
            },
            "then": {
              "required": ["enforcement_point", "callsite_evidence"],
              "description": "weak_normative proposals require enforcement_point (named function) and callsite_evidence (call path) per check_enforcement.py scope rules."
            }
          }
        ]
      }
    }
  }
}
```

Note: `proposed_text` is required when `change_type = new_requirement`. This is the actual clause text the human reviews and `check_contradictions.py` checks. `enforcement_point` and `callsite_evidence` are required for `weak_normative` proposals so the validator can prove or reject the claimed enforcement trace before review. Freshly generated `proposals.json` entries MUST start as `status: "proposed"`; later statuses are assigned only by validation/review flow.

`source_finding_category` is duplicated trace data for readability, not an authoritative classifier. `validate_proposals.sh` MUST resolve `source_finding` in the sibling `findings.json` and require `proposal.source_finding_category == findings[source_finding].category`; any mismatch is a hard validation failure. All category-specific gates and auto-apply decisions use the resolved finding category, never the proposal-declared category alone.

`replace_span.start_line` and `replace_span.end_line` are fixture-local evidence coordinates only. They prove where the patcher found the text inside the Phase 2 source fixture. Promotion to live `specs/CONTRACT.md` MUST recompute live coordinates from the current section anchor plus exact `old_text` matching; the fixture-local line numbers are never interpreted as live-contract coordinates.

> **Constraint**: `change_type: "mechanical"` with `mechanical_ok: false` is prohibited. A mechanical proposal that cannot be auto-applied must be retyped as `new_requirement`. This prevents `apply_proposals.py` from receiving a mechanical proposal with no `replace_span` target.

### 2.3 Results.tsv Canonical Row Schema

```
run_id  timestamp  contract_file_hash  fixture_set_hash  eval_version  branch  tag  score  passed  total  precision  recall  f1  proposal_count  mechanical_count  new_req_count  status  description
```

- `run_id`: `<git-short-hash>-<ISO8601-compact>` (e.g., `a1b2c3d-20260314T1430`)
- `fixture_set_hash`: SHA256 of concatenated fixture contents
- `eval_version`: SHA256 of `eval.json` (detects assertion changes between runs)
- `score`: `passed / total` — fraction of binary assertions that passed. Primary optimization metric.
- Phase 1 rows use `precision`, `recall`, `f1`; Phase 2 rows use `proposal_count`, `mechanical_count`, `new_req_count`. Unused columns set to `-`.

---

## 3. Phase 1: Detection Calibration

### 3.1 Skill Target

`SKILLS/contract-gap-detector.md` — instructions for reading a contract section and producing structured findings.

The skill sweeps for 6 defect categories:
- **missing_fail_closed**: gate input with no explicit NaN/missing/stale handling
- **weak_normative**: SHOULD where behavior governs trading permission or fund movement
- **missing_at_pair**: TRIP AT exists but no corresponding NON-TRIP (or vice versa)
- **stale_input_unspecified**: gate input with no freshness/staleness clause
- **gate_interaction_gap**: shared state between gates with no ordering/race specification
- **cross_ref_broken**: AT references non-existent section, or section references non-existent AT

Output: JSON matching `findings.schema.json`. Each finding includes machine-readable evidence (line, quote, optional context range).

### 3.2 Planted-Gap Fixtures (7 seed fixtures)

| Fixture | Source | Injected Defect | Expected |
|---------|--------|-----------------|----------|
| `s2_2_missing_fail_closed.md` | §2.2 axis resolver | Remove NaN handling from evidence_chain_score | 1 finding: missing_fail_closed, P0/P1 |
| `s2_2_should_vs_must.md` | §2.2 staleness | Weaken "MUST force ReduceOnly" → "SHOULD force" | 1 finding: weak_normative, P0/P1 |
| `s1_gate_ordering_gap.md` | §1 pipeline | Remove ordering constraint between LiquidityGate and RecordedBeforeDispatch | 1 finding: gate_interaction_gap, P0/P1 |
| `s1_missing_at_pair.md` | §1 gate ATs | Delete NON-TRIP AT for a gate that has TRIP AT | 1 finding: missing_at_pair, P1 |
| `s2_2_stale_input_no_spec.md` | §2.2 inputs | Remove staleness threshold from a PolicyGuard input | 1 finding: stale_input_unspecified, P1 |
| `s1_cross_ref_broken.md` | §1 gate ATs | Change AT reference to non-existent section | 1 finding: cross_ref_broken, P1 |
| `s2_2_clean.md` | §2.2 verbatim | No defects | 0 P0/P1 findings |

### 3.3 Assertions (7 per mutated fixture, 5 for clean = 47 total)

**Per mutated fixture (7 x 6 = 42):**
1. Output is valid JSON matching `findings.schema.json` (`json_schema_valid`)
2. At least one finding has the correct `category` for the planted defect (`json_field_match`)
3. Finding `evidence.quote` contains a token/phrase from the injection site (`regex`)
4. Finding `severity` is P0 or P1 (`json_field_match`)
5. Finding count is 1..3 (`json_array_count_bounds`)
6. All `finding_id` values are unique within `findings.json` (`json_unique_field` on `$.findings[*].finding_id`)
7. No P0/P1 findings with `evidence.quote` containing tokens outside the injected region's known token set (`json_field_not_match` on `$.findings[?(@.severity=="P0" || @.severity=="P1")].evidence.quote`, pattern built from harness-only fixture metadata)

**Clean fixture (1 x 5 = 5):**
1. Valid JSON matching `findings.schema.json`
2. Zero P0/P1 findings
3. Total finding count 0..2
4. All traceability fields present
5. All `finding_id` values are unique within `findings.json`

> **Rubric isolation**: `injected_tokens` and any equivalent answer-key metadata are stored in `phase1/internal/fixture_metadata.json`, not in `eval.json`. `fixture_metadata.json`, `phase1/eval.json`, and `phase2/eval.json` are harness-only inputs. They MUST NOT be passed to the calibrated skill prompt, MUST NOT be writable by the loop agent, and are used only during post-generation scoring.

### 3.4 Exit Criteria

- **Precision** >= 0.90 (P0/P1 findings matching a planted gap / total P0/P1 findings). Evaluated only across fixtures that produced at least one P0/P1 finding; logged as `N/A` when finding count is zero.
- **Recall** >= 0.95 (planted gaps found / total planted gaps across mutated fixtures)
- **Clean fixture**: zero P0/P1 false positives for 5 consecutive runs
- **Stability**: score unchanged (±0.01) across 5 consecutive iterations after floors are met

F1 is the harmonic mean of precision and recall where both are defined, logged in results.tsv but not used as an exit gate.

---

## 4. Phase 2: Contract Quality & Patch Generation

### 4.1 Skill Target and Scoring Model

`SKILLS/contract-patch.md` — instructions for consuming findings and generating proposals.

**Critical: Phase 2 must optimize the patcher, not the current contract state.** Each iteration:

1. **Step A — Detect**: Run the calibrated Phase 1 detector on the real/snapshot fixture → produces `phase2/outputs/<run_id>/<fixture_id>/findings.json`
2. **Step B — Patch**: Run `contract-patch.md` on the findings → produces `<fixture_id>/proposals.json`
3. **Step C — Apply**: Deterministically apply proposals to a staging copy of the fixture → produces `outputs/<run_id>/<fixture_id>/patched/<fixture_id>.patched.md`
4. **Step D — Score**: Run structural assertions on the **patched** fixture, not the original

This means the loop measures: "if we applied the patcher's proposals, would the contract quality assertions pass?" A patcher that generates correct proposals improves the score. The current contract state is constant; only the patcher changes.

Proposal-validity assertions (schema, span, zero-contradictions) are scored separately and must all pass before structural assertions are evaluated.

### 4.2 Fixtures (dual-layer)

**Static seed fixtures (never replaced):**

| Fixture | Source | Purpose |
|---------|--------|---------|
| `static/s2_2_policyguard_seed.md` | §2.2 as of spec lock date | Regression anchor |
| `static/s1_execution_pipeline_seed.md` | §1 as of spec lock date | Regression anchor |
| `static/s2_2_no_change.md` | §2.2 with all known gaps pre-fixed | Zero proposals expected — precision anchor |

**Snapshot fixtures (re-extracted after CONTRACT.md changes):**

| Fixture | Source | Purpose |
|---------|--------|---------|
| `snapshot/s2_2_policyguard_latest.md` | Current §2.2 | Ratchet |
| `snapshot/s1_execution_pipeline_latest.md` | Current §1 | Ratchet |

### 4.3 Assertions

**Proposal-validity assertions (gate — all must pass before structural scoring):**
1. `proposals.json` is valid JSON matching `proposals.schema.json`
2. All `mechanical_ok: true` proposals have `replace_span.old_text` present at the exact `[start_line, end_line]` slice in the source fixture, and that slice is unique within the proposal's declared `section`. Static fixtures: `fixture_path` only. Snapshot fixtures: `fixture_path` + `snapshot_path` (dual validation).
3. Zero proposals flagged by `check_contradictions.py`. Any non-zero exit, timeout, parse failure, or missing output from `check_contradictions.py` is treated as a failed contradiction check and aborts the batch (fail-closed).
4. No-change fixture emits zero proposals (`json_array_count_bounds`, min=0, max=0)
5. Every `source_finding` resolves to an actual `finding_id` in the sibling `findings.json` for the same `<run_id>/<fixture_id>`, and `source_finding_category` exactly matches the resolved finding's `category`. Fabricated source-finding IDs or category mismatches fail closed.
6. All `proposal_id` values are unique within `proposals.json` (`json_unique_field` on `$.proposals[*].proposal_id`)
7. Freshly generated `proposals.json` entries all start as `status: "proposed"` before any validation/review transition. A patcher MUST NOT pre-set `accepted`, `pending_scope_review`, `rejected`, or `stale`.
8. For all `mechanical_ok: true` proposals: normalized `replace_span.new_text` differs from normalized `replace_span.old_text` (`json_field_not_match` on `$.proposals[?(@.mechanical_ok==true)].replace_span`, with whitespace normalization enabled before comparison). Blocks no-op and whitespace-only patcher patterns.
9. All `dedupe_key` values across proposals are unique (`json_unique_field` on `$.proposals[*].dedupe_key`). Blocks duplicate application.
10. All `change_type: "new_requirement"` proposals: `proposed_text` references at least one specific named entity — an AT-ID (`AT-\d+`), a gate function name, or a PolicyGuard/EvidenceGuard/DispatcherChokepoint keyword (`regex` on `$.proposals[?(@.change_type=="new_requirement")].proposed_text`, pattern: `(?i)\b(AT-\d+|PolicyGuard|EvidenceGuard|DispatcherChokepoint|evidence_chain|build_order_intent|LiquidityGate|RecordedBeforeDispatch|PreflightCheck)\b`). Blocks semantic-filler proposals ("The system MUST use appropriate thresholds") that degrade contract quality.

> **Post-apply hash check (assertion on patched fixtures)**: For each fixture where at least one proposal was applied, `hash(patched_fixture) != hash(original_fixture)`. If no proposal changed the fixture, the patcher made no improvement — this should be flagged as a potential no-op patcher signal.

**Structural assertions on `patched_fixture` (6 per real-section fixture = 24 total):**
1. Every gate input has an explicit fail-closed clause — count of clauses that name both (a) the degraded input condition (`NaN|missing|stale|absent`) and (b) a fail-closed outcome term (`ReduceOnly|Kill|reject|block|latch`) is >= `expected_gate_input_count`. The `expected_gate_input_count` for each fixture is stored in `eval.json` and is derived during `refresh_fixtures.sh` (not hardcoded). Seed counts at spec-lock time: `s2_2_policyguard_seed` = 12, `s1_execution_pipeline_seed` = 8 — these are recorded values, not permanent constants. Snapshot fixtures derive their own count independently on each refresh.
2. Every AT referenced has both TRIP and NON-TRIP specified
3. No SHOULD in lines containing any of: `TradingMode`, `dispatch`, `reject`, `block`, `latch`, `Kill`, `ReduceOnly`, `position limit`, `exposure limit`
4. Every gate-to-gate data dependency has an explicit ordering constraint
5. All proposals reference exact, unique fixture spans inside their declared section (no hallucinated evidence)
6. All traceability fields present

### 4.4 Contradiction Rule

**Enforcement**: `check_contradictions.py` performs:
- Extract all MUST and SHALL sentences from CONTRACT.md (both treated as normatively equivalent per RFC 2119)
- **Mechanical proposals**: diff `old_text` vs `new_text`:
  - MUST/SHALL present in `old_text` but absent/weakened in `new_text` → CONTRADICTION
  - MUST/SHALL present in `old_text` but `new_text` is empty or whitespace-only → CONTRADICTION
  - MUST/SHALL present in `old_text` but changed to SHOULD/MAY in `new_text` → CONTRADICTION
  - New MUST/SHALL with overlapping subject and negated predicate → CONTRADICTION
  - **Scope narrowing**: MUST/SHALL clause in `old_text` is unconditional, but equivalent clause in `new_text` adds a conditional guard (`AND`, `OR`, `EXCEPT`, `IF`, `WHEN`, `UNLESS`) → SCOPE_NARROWING (flagged separately, always requires human review regardless of category)
  - MUST NOT changed to MUST (negation flip) → CONTRADICTION
- **New-requirement proposals**: extract MUST/SHALL clauses from `proposed_text` field; check each against existing MUSTs/SHALLs for subject overlap + negation conflict

Contradictions are flagged `status: rejected` with reason code `CONTRADICTION`. Scope-narrowings are flagged `status: pending_scope_review` with reason code `SCOPE_NARROWING`; they are blocked from auto-apply and require explicit human review. Both run before any proposal is promoted.

Any non-zero exit, timeout, parse failure, or missing result from `check_contradictions.py` is treated as a contradiction-check failure. The harness aborts the batch fail-closed rather than interpreting tool failure as "no contradictions found."

> **Note on scope narrowing**: A `SCOPE_NARROWING` finding is not necessarily wrong — it may reflect legitimate contract refinement. It is flagged to ensure human review rather than auto-approval. No category may bypass SCOPE_NARROWING review, including `cross_ref_broken`.

> **Batch-internal contradiction check**: After all per-proposal checks pass, `check_contradictions.py` performs a pairwise check across all proposals in the batch:
> - For each pair (P_i, P_j): extract MUST/SHALL clauses from `proposed_text` (for new_requirement) or `new_text` in `replace_span` (for mechanical). Check each clause from P_i against each clause from P_j for subject overlap + negation conflict or scope contradiction.
> - If P_i's new text introduces "MUST do X under condition C" and P_j's new text introduces "MUST NOT do X under condition C" (or equivalent), flag as `BATCH_CONTRADICTION`.
> - `BATCH_CONTRADICTION` findings abort the entire batch — the reviewer is shown which proposals conflict and must resolve before re-submitting.

### 4.5 Exit Criteria

- 100% of proposals pass `proposals.schema.json` validation
- 100% of mechanical proposals have valid spans
- Zero proposals on no-change fixture for 5 consecutive runs
- Zero contradictions for 5 consecutive runs
- Structural assertions on patched fixture stable (±0.01) across 5 consecutive iterations

---

## 5. Harness Extensions

### 5.1 New Commands

```bash
harness.sh contract phase1 run      [--tag TAG] [--model MODEL] [--eval PATH] [--workdir PATH]
harness.sh contract phase1 baseline [--tag TAG] [--model MODEL] [--eval PATH]
harness.sh contract phase2 run      [--tag TAG] [--model MODEL] [--eval PATH] [--workdir PATH]
harness.sh contract phase2 baseline [--tag TAG] [--model MODEL] [--eval PATH]
harness.sh contract refresh-fixtures
harness.sh contract refresh-common          # Rebuild common/ from CONTRACT.md + AT registry
harness.sh contract refresh-all             # refresh-common then refresh-fixtures
harness.sh contract status
```

`--eval` and `--workdir` are explicit. Defaults resolve to `autoresearch/contract/phase{1,2}/eval.json`. `baseline` is pure scoring — no skill or contract file modifications.

**Concrete runner launch contract**: `harness.sh contract phase{1,2} run` launches the loop agent as `claude --settings "$ROOT/autoresearch/contract/.claude/settings.json" -p "$launch_prompt"`. The `--settings` flag is mandatory because it loads the contract-loop permission profile that restricts the agent's writable surface; if the selected runner lacks `--settings` support, the harness MUST abort before launching the loop.

**Contract-loop prompt isolation**: The `contract` subcommands use a derived launch prompt that includes fixture text, shared `common/` context, and contract-loop protocol rules, but excludes direct reads of `phase1/eval.json`, `phase2/eval.json`, and `phase1/internal/fixture_metadata.json`. Those files remain harness-only scoring inputs. If the selected runner cannot enforce this separation, `harness.sh contract ... run` MUST abort rather than falling back to a rubric-visible run.

### 5.2 evaluate.py New Rule Types

| Rule Type | Purpose | Parameters |
|-----------|---------|------------|
| `json_schema_valid` | Validate output against a JSON Schema | `schema_path`. Fails closed on non-JSON or multiple JSON objects. |
| `json_field_match` | Check JSON field value/pattern | `path` (JSONPath, e.g. `$.findings[*].category`), `pattern` or `value`. Type mismatches fail closed. |
| `json_array_count_bounds` | Assert array length bounds | `path`, `min`, `max` |
| `line_span_exists` | Verify `replace_span.old_text` matches the exact `[start_line, end_line]` slice in the pre-patch source file and is unique within the proposal's declared `section` | `fixture_path` (always — pre-patch source); `snapshot_path` (**required** for fixtures under `fixtures/snapshot/`, optional otherwise — harness errors if `snapshot_path` is absent for a snapshot fixture). **Never targets `patched/` directory.** |
| `json_field_not_match` | Assert that no element in a JSON array matches a given pattern/value | `path` (JSONPath), `pattern` or `value`. Supports optional whitespace normalization before compare for paired text fields. Fails closed on non-JSON. Used with `--json-output`. |
| `json_unique_field` | Assert that all values selected by a JSONPath are unique | `path` (JSONPath). Fails closed on missing/non-scalar values. |
| `json_cross_ref_exists` | Assert that every selected local ID exists in a referenced JSON artifact | `path`, `foreign_file`, `foreign_path`. Fails closed if the foreign artifact is missing/unparseable. |

> The harness validates `eval.json` at startup: any `line_span_exists` rule referencing a fixture under `fixtures/snapshot/` that lacks a `snapshot_path` field → fail with exit code 2: `eval.json error: snapshot fixture <path> requires snapshot_path in line_span_exists rule`.

### 5.3 Context Staleness Enforcement

Before each `run` or `baseline`, the harness compares `context_manifest.json` hashes against current file hashes. `context_manifest.json` tracks:
- All files in `common/` (contract_header.md, at_registry.json, section_index.md)
- All snapshot fixture files in `phase2/fixtures/snapshot/` (SHA256 of content)
- The CONTRACT.md file itself (SHA256 of content, stored as `contract_content_hash`)

Mismatch on any tracked file → abort with exit code 2, with error message depending on artifact class:
- `common/` file stale → `Stale context: <filename> changed. Run 'harness.sh contract refresh-common' first`
- snapshot fixture stale → `Stale context: snapshot/<filename> changed. Run 'harness.sh contract refresh-fixtures' first`
- CONTRACT.md hash stale (proposal index) → `Stale proposal: CONTRACT.md changed since generation (contract_file_hash mismatch). Re-run Phase 2.`
- common-context hash stale (proposal index) → `Stale proposal: common context changed since generation (context_manifest_hash mismatch). Re-run refresh-common/refresh-fixtures, then Phase 2.`

The `contract_content_hash` field in `context_manifest.json` is the authoritative source for CONTRACT.md staleness detection, and the SHA256 of the full `context_manifest.json` file is the authoritative source for shared-context staleness detection. Both are compared against `proposals_index.json` entries at promotion time.

### 5.4 Refresh Commands

#### refresh_fixtures.sh (phase-2 snapshot refresh)

1. Read `section_index.md` for line ranges
2. Extract sections from CONTRACT.md
3. Write to `phase2/fixtures/snapshot/`
4. For each extracted snapshot fixture: count fail-closed clauses that name both the degraded input condition and an outcome term using the pattern `(MUST|SHALL) + input_name + (NaN|missing|stale|absent) + .*(ReduceOnly|Kill|reject|block|latch)`, where `input_name` is drawn from the union of all `gate_input_names` arrays in `at_registry.json`. Write the count as `expected_gate_input_count` for that fixture in `phase2/eval.json`. This count is authoritative for subsequent Phase 2 runs — it replaces any previously stored value.
5. Update `context_manifest.json` (snapshot fixture hashes + contract_content_hash)
6. Fail fast if `section_index.md` ranges no longer align — require `refresh-common` first
7. Produce diff report if extraction anchors changed

#### refresh_common.sh (shared context rebuild)

Rebuilds `common/` artifacts that both phases depend on. Run when:
- CONTRACT.md structure changes (new sections, renamed sections)
- AT registry changes (new ATs, retired ATs)
- The stale-context gate fires on a `common/` file

Steps:
1. Re-extract `contract_header.md` from CONTRACT.md §0.0 scope + definitions
2. Re-generate `at_registry.json` from CONTRACT.md AT-### anchors. Each entry MUST include: `at_id`, `section_anchor`, `test_type` (`TRIP|NON_TRIP|OTHER`), and a one-line description. If `test_type` cannot be derived mechanically, emit `OTHER` and force human review for any proposal that references that AT.
3. Re-generate `section_index.md` section-to-line-range mapping from CONTRACT.md headings
4. Update `context_manifest.json` (common/ hashes)
5. Warn if any Phase 1 planted-gap fixture references a section that no longer exists in `section_index.md` — those fixtures require manual update

Note: Phase 1 planted-gap fixtures (the mutated versions) are NOT rebuilt automatically — they encode specific injected defects and must be manually verified after `refresh-common` changes AT references or section structure.

### 5.5 Write Isolation Architecture

CONTRACT.md is protected by a **harness-level architectural barrier** during Phase 2 loops:

**Primary barrier (architectural)**: The LLM loop agent (`program.md`) has no authorized write path to `specs/CONTRACT.md` or to any harness-owned scoring artifact. All writes to CONTRACT.md are performed exclusively by `apply_proposals.py`, which is invoked by the harness (not the loop agent). The loop agent's writable surface is limited to the current phase skill target plus per-run outputs/results artifacts.

The harness enforces this with a concrete runner contract:
1. Launch the loop agent as `claude --settings "$ROOT/autoresearch/contract/.claude/settings.json" -p "$launch_prompt"`. The `--settings` flag loads the contract-loop permission profile directly; no working-directory switch is required.
2. `autoresearch/contract/.claude/settings.json` defines the contract-loop permission profile. It MUST:
   - allow writes only to the active phase target skill file (`SKILLS/contract-gap-detector.md` for Phase 1 or `SKILLS/contract-patch.md` for Phase 2), `phase{1,2}/outputs/**`, and `phase{1,2}/results.tsv`
   - deny writes to `specs/**`, `common/**`, `phase1/eval.json`, `phase2/eval.json`, `phase1/internal/**`, `phase2/proposals/**`, and `phase2/proposals_index.json`
   - deny shell/Bash execution for the loop agent
3. Before launch, `harness.sh contract ... run` performs a fail-closed startup check:
   - verify the selected runner supports `--settings`
   - verify `autoresearch/contract/.claude/settings.json` exists and matches the expected checked-in hash
   - verify the phase permission profile selected for this run matches the intended writable paths
   - run a denied-path probe against a temporary file under `specs/` (or another harness-owned path) and require the probe to fail
4. If any startup check fails, the harness aborts without launching the loop agent.

**Secondary barrier (belt-and-suspenders)**:
```bash
# Before invoking any Phase 2 loop run:
chmod 444 specs/CONTRACT.md

# After loop completes (harness restores via trap):
chmod 644 specs/CONTRACT.md
```

The `chmod 444` guard is a secondary, belt-and-suspenders measure. It will not fire on SIGKILL and can be bypassed by an agent with shell execution permissions. It is NOT relied upon as the primary safety barrier — the primary barrier is the checked-in permission profile + startup capability check above.

`CONTRACT_READONLY=1` is set as an advisory signal to tooling that checks it.

**SIGKILL recovery**: If the harness is killed without restoring permissions, the operator runs:
```bash
chmod 644 specs/CONTRACT.md
```
This is documented in the RUNBOOK. A CI check verifies CONTRACT.md permissions before each run.

---

## 6. Graduation Path

### 6.1 End-to-End Flow

> **Implementation status (this revision): Future state.** The automated promotion pipeline (`apply_proposals.py`, `validate_proposals.sh`, atomic rename, verify-then-apply transaction) described in §6.1 and §6.5 is **not built in this revision**. Current promotion is manual — see §7.2. This section documents the target architecture for when the automated pipeline is implemented.

```
SETUP → PHASE 1 (detection calibration) → PHASE 2 (propose-then-apply)
     → VALIDATE PROPOSALS (pre-review gate) → HUMAN REVIEW GATE
     → [accepted proposals only] → VALIDATE PROPOSALS (pre-apply gate, re-check for drift)
     → SHADOW GRADUATION (cross_ref_broken only) → AUTO-APPLY
     → POST-APPLY REFRESH
```

(Two validation passes: once before human review to catch stale/invalid proposals early, once after review to catch CONTRACT.md drift since review)

**Pre-promotion validation gate** (`validate_proposals.sh`): Runs **twice**:

**Pass 1 — Pre-review** (immediately after Phase 2 run, before presenting proposals to reviewer):
1. Validate `proposals.json` against `proposals.schema.json`
2. Check all `mechanical_ok: true` spans against the **snapshot fixture** (not CONTRACT.md yet)
3. Run `check_contradictions.py` against current CONTRACT.md
4. Run referential-integrity, category-parity, uniqueness, and freshness checks: `source_finding -> findings.json`, `source_finding_category == findings[source_finding].category`, unique `proposal_id`, unique `dedupe_key`, fresh-status=`proposed`, and `context_manifest_hash == sha256(context_manifest.json)`
5. Run `check_enforcement.py` on every proposal whose resolved source finding category is `weak_normative`. The checker must verify the named `enforcement_point` and `callsite_evidence` against production call paths; dead code, test-only paths, comments, parse failures, timeouts, or missing output are hard failures.
6. Surface `context_manifest.json` contract_content_hash, the proposal `contract_file_hash`, and the proposal `context_manifest_hash` to reviewer in `CONTRACT_PROPOSALS_<run_id>.md` — reviewer sees whether they're reviewing against a current or stale CONTRACT/common-context base. Any `pending_scope_review` proposals are emitted in a dedicated section for explicit human triage.
7. Any schema failure, referential-integrity failure, category mismatch, uniqueness failure, freshness failure, enforcement-verification failure, tool failure, or `CONTRADICTION` result → abort and notify; reviewer does not see invalid proposals. `pending_scope_review` is review-blocking for auto-apply but is still presented to the human reviewer.

**Pass 2 — Pre-apply** (after human review, before `apply_proposals.py` runs on accepted proposals):
1. Re-validate accepted proposals against `proposals.schema.json`
2. Re-check all `mechanical_ok: true` proposals against **current CONTRACT.md** (not snapshot) using the live coordinate bridge defined below: resolve the current section range from `section_index.md`, search only within that section, require exactly one normalized match for `replace_span.old_text`, recompute the live `[start_line, end_line]`, and require the exact live slice to equal `old_text` byte-for-byte. Zero matches, multiple matches, missing section anchor, or slice mismatch → mark proposal `stale`, abort that proposal.
3. Re-run `check_contradictions.py` against current CONTRACT.md
4. Re-run referential-integrity, category-parity, uniqueness, freshness, and enforcement checks on the accepted proposal set (`context_manifest_hash` must still match current `context_manifest.json`; `check_enforcement.py` must still pass for weak-normative proposals)
5. Batch-internal contradiction check: re-run pairwise check across all accepted proposals
6. Any failure → abort **entire promotion batch**; notify reviewer; do not apply partial batch
7. Record pre-apply CONTRACT.md hash in `proposals_index.json` as `apply_base_hash` (status remains `reviewed` until the write step begins)

`apply_proposals.py` logs the CONTRACT.md hash it observed vs. `apply_base_hash` from the index. If they differ (TOCTOU race), abort with: `CONTRACT.md changed between validation and apply: expected <hash>, found <hash>`. This provides a clear diagnostic rather than a cryptic span-not-found abort.

**Fixture-to-live coordinate bridge (authoritative promotion model)**:
- `replace_span.start_line` / `end_line` are evidence on the Phase 2 fixture only.
- `section` is the bridge field. It MUST name a canonical section anchor present in `common/section_index.md`.
- Promotion MUST resolve the current live section bounds from `section_index.md`, search only within that section for normalized `replace_span.old_text`, and require exactly one live candidate span.
- The recomputed live span MUST map to a byte-for-byte exact slice match for `replace_span.old_text` before any replacement is attempted.
- `apply_proposals.py` MUST ignore fixture-local line numbers as live write coordinates. If the live section is missing, the text is absent, or more than one candidate exists, the proposal is `stale` and the batch aborts fail-closed.

### 6.2 Shadow Graduation Threshold

- **N**: 10 reviewed runs minimum
- **M**: 20 total proposals minimum per category across N runs (prevents graduation on thin evidence)
- **Agreement rate**: >= 0.95 (machine accept/reject matches human, computed across all M proposals)
- **Failure modes**: machine applies but human rejects; machine rejects but human accepts; stale span applied
- **Per-category**: graduates independently. Regresses if post-graduation agreement drops below 0.90 over 5 consecutive runs.

> **Graduation process applicability**: The §6.2 graduation process (N=10 runs, M=20 proposals, ≥0.95 agreement, adversarial pre-condition) applies to the categories in **Order 2–6** when they are candidates for auto-apply. `cross_ref_broken` (Order 1) is GRADUATED by design decision rather than by running the §6.2 process because its auto-apply boundary rule is reduced to a same-section, same-test-type, same-gate-input-names AT-ID token substitution against a pinned reviewed context. The graduation criteria in §6.2 measure "can the machine's accept/reject judgment match human judgment?" — a question that is largely vacuous once the apply surface is bounded to registry-backed structural replacement with no prose edits. The adversarial pre-condition from §6.2 is satisfied by construction per §6.4's boundary rule note.

### 6.3 Graduation Subtypes

The findings `category` enum has 6 values. Graduation uses **subtypes** that narrow a base category to a mechanical pattern. Subtype is derived at shadow-evaluation time, not stored in findings JSON.

| Base Category | Graduation Subtype | Auto-Apply | Qualifies When |
|---------------|-------------------|------------|----------------|
| `cross_ref_broken` | `cross_ref_broken` | **YES — restricted** | **Restricted to AT-ID token repairs only** (see §6.4 boundary rule). Auto-apply requires same `section_anchor`, same `test_type`, matching `gate_input_names` sets, and a fresh pinned `context_manifest_hash`. Section-number reference repairs require human review. |
| `missing_at_pair` | `mechanical_mirrorable_missing_at_pair` | After graduation | Paired AT exists + missing AT is logical negation + no new enforcement behavior |
| `missing_at_pair` | *(human review)* | No | Requires new enforcement logic or non-standard pair structure |
| `missing_fail_closed` | `template_backed_missing_fail_closed` | After graduation | Sibling gate input in same section has explicit fail-closed clause + new clause follows same grammatical pattern |
| `missing_fail_closed` | *(human review)* | No | No template exists or unusual input semantics |
| `weak_normative` | `bounded_weak_normative` | After graduation | SHOULD→MUST single-word change + code enforcement proven via named enforcement point + callsite trace (see §6.4) |
| `weak_normative` | *(human review)* | No | Code doesn't enforce or clause requires restructuring |
| `stale_input_unspecified` | *(always human review)* | No | New requirement |
| `gate_interaction_gap` | *(always human review)* | No | Highest semantic risk |

### 6.4 Graduation Ordering

| Order | Subtype | Status | Boundary Rule |
|-------|---------|--------|---------------|
| 1 | `cross_ref_broken` | **GRADUATED (AT-ID repairs only)** | **Boundary rule**: Auto-apply is restricted to proposals that replace an AT-ID reference token (`AT-\d+` pattern) with another AT-ID reference token, where both the source and target AT-IDs exist in `at_registry.json`, share the same `section_anchor`, share the same `test_type` (`TRIP` or `NON_TRIP`; `OTHER` is never auto-applied), **and cover the same set of gate inputs**. A pre-apply gate verifies: (1) `old_text` contains exactly one `AT-\d+` token, (2) `new_text` contains exactly one `AT-\d+` token, (3) the source and target AT-IDs both exist in `at_registry.json`, (4) `section_anchor(old) == section_anchor(new)`, (5) `test_type(old) == test_type(new)` and neither is `OTHER`, (6) the proposal `context_manifest_hash` still matches current `context_manifest.json`, and **(7) `set(gate_input_names(old_at_id)) == set(gate_input_names(new_at_id))`** — same-section same-test-type is insufficient when a section contains multiple ATs covering different gate inputs; the input-name sets must match exactly. Section-number repairs, prose changes, or any mismatch on checks 1–7 require human review. |
| 2 | `mechanical_mirrorable_missing_at_pair` | Requires §6.2 graduation | Paired AT exists. New AT text is logical negation (TRIP↔NON-TRIP). No new enforcement behavior. |
| 3 | `template_backed_missing_fail_closed` | Requires §6.2 graduation | Sibling gate input has explicit fail-closed clause using same grammatical pattern (MUST + input_name + fail-closed verb + ReduceOnly/reject). Diff confined to adding a sentence or bullet. |
| 4 | `bounded_weak_normative` | Requires §6.2 graduation | SHOULD→MUST single-word change AND `enforcement_point` field names the Rust function AND `callsite_evidence` provides a traceable call path from that function to the MUST behavior (verified by `check_enforcement.py` in both validation passes, not just grep). Clause governs trading permission or fund movement. |
| 5 | `stale_input_unspecified` | Always human review | Always human review. |
| 6 | `gate_interaction_gap` | Always human review | Highest semantic risk. |

**Note on category 4**: grep is explicitly rejected as evidence for `bounded_weak_normative`. `check_enforcement.py` must trace: `enforcement_point` (named function) → call path → the specific behavior being upgraded to MUST. Dead code, test code, and comment matches do not qualify. `validate_proposals.sh` runs this checker in both Pass 1 and Pass 2, and any checker failure is a hard validation failure rather than an advisory warning.

> **`cross_ref_broken` pre-graduation rationale**: This category is marked GRADUATED without running the §6.2 N/M/agreement-rate process because the auto-apply boundary rule is bounded to a same-section, same-test-type, same-gate-input-names AT-ID token substitution against a pinned reviewed context, with no prose changes. Same section and same test type alone are not sufficient — a section may contain multiple ATs of the same type covering different gate inputs (e.g., §2.2.1.2 has multiple TRIP tests); check 7 (`gate_input_names` set equality) is required to prevent a substitution from silently pointing a clause at the wrong AT. The graduation criteria in §6.2 measure "can the machine's accept/reject judgment match human judgment?" — a question that is largely vacuous once the apply decision is reduced to registry-backed structural replacement gated by checks 1–7. The adversarial pre-condition (§6.2) is satisfied by construction: an adversarial proposal that attempts to replace an AT-ID with a non-existent AT-ID, a different `test_type`, a different `section_anchor`, a mismatched `gate_input_names` set, or a stale common-context basis is blocked before apply.

### 6.5 Post-Apply Refresh Cycle

> **Implementation status (this revision): Future state.** See §7.2.

After any accepted proposal is applied to CONTRACT.md:
0. **Promotion lock**: Before any state read or write, the harness acquires an exclusive lock on `autoresearch/contract/promotion.lock` via `flock -x -n`. If the lock is already held, abort with: `Promotion already in progress (promotion.lock held). Retry after the other process completes.` Stale-lock detection: if `promotion.lock` exists, its mtime is older than 30 minutes, and the PID recorded inside is no longer running, the harness may force-clear the lock only when invoked with `--force-clear-lock`; otherwise abort. The lock is released unconditionally via `trap ... EXIT`. Any lock acquisition failure is a hard abort — the harness MUST NOT proceed with state transitions while unable to guarantee mutual exclusion.
1. `validate_proposals.sh` Pass 2 pre-apply gate must pass before apply (see §6.1)
2. **Recovery-aware idempotency pre-check**: Before applying, the harness checks `proposals_index.json`:
   - `status: "applied"` → skip and log warning (already promoted successfully)
   - `status: "verifying"` → compare the current CONTRACT hash against `apply_base_hash` and `apply_candidate_hash`
     - matches `apply_base_hash` → interrupted before live apply; restore index to `reviewed`
     - matches `apply_candidate_hash` → interrupted after live apply; resume verification or restore both snapshots
     - matches neither → hard-block with manual recovery message
3. The harness snapshots both `specs/CONTRACT.md` and `proposals_index.json` before any write. These snapshots are the rollback source if post-apply verification fails or recovery determines the batch must be rewound.
4. The harness stages the would-be post-apply `CONTRACT.md` content to a temp file, computes `apply_candidate_hash`, and atomically updates `proposals_index.json` to `status: "verifying"` with `apply_base_hash` and `apply_candidate_hash`. If this index write fails, abort before touching live `CONTRACT.md`.
5. Only after the `verifying` record is durable does the harness atomically rename the staged temp file into `specs/CONTRACT.md`.
6. `./plans/verify.sh full` runs immediately after apply, before any fixture refresh.
   - If `./plans/verify.sh full` fails: restore both `specs/CONTRACT.md` and `proposals_index.json` from the pre-apply snapshots, return the batch to `status: "reviewed"`, and block the run.
   - If `./plans/verify.sh full` passes: atomically update `proposals_index.json` to `status: "applied"` and persist `applied_contract_hash`.
7. `refresh_fixtures.sh` re-extracts snapshot fixtures
8. **Threshold refresh**: For each fixture in `phase2/fixtures/`, recount fail-closed clauses matching the `eval.json` assertion 1 pattern (MUST/SHALL + input_name + degraded-input term + outcome term) in the refreshed fixture. Update `phase2/eval.json` `expected_gate_input_count` for each affected fixture. Commit the `eval.json` update alongside the CONTRACT.md change.
9. Re-run Phase 2 to confirm ratchet (patched fixture structural assertions should now pass on clean run)
10. Phase 1 smoke set (clean fixture + 1 mutated fixture) to verify shared context drift
11. If smoke fails: re-extract `common/` and re-run Phase 1 baseline

---

## 7. Implementation Scope

### 7.1 What Gets Built

| Component | Type | Description |
|-----------|------|-------------|
| `SKILLS/contract-gap-detector.md` | Skill | Phase 1 loop target |
| `SKILLS/contract-patch.md` | Skill | Phase 2 loop target |
| `autoresearch/contract/` tree | Data | Eval configs, fixtures, schemas, shared context |
| `autoresearch/contract/.claude/settings.json` | Config | Contract-loop permission profile: allow only target skill/results/outputs writes; deny shell + harness-owned paths |
| `evaluate.py` extensions | Python | 7 new rule types |
| `harness.sh` contract subcommand | Bash | Phase 1/2 run/baseline, refresh-fixtures, status, and fail-closed runner-isolation startup checks (`--settings` support, permission-profile hash, denied-path probe) |
| `validate_proposals.sh` | Bash/Python wrapper | Deterministic proposal gate: schema, contradiction checker, referential integrity, category parity against `findings.json`, unique IDs, exact-span/live-coordinate checks, fresh-status checks, `check_enforcement.py` wiring for weak-normative proposals, fail-closed on tool errors |
| `check_contradictions.py` | Python | Deterministic MUST-conflict checker (handles both mechanical and new_requirement proposals via `proposed_text` field) |
| `check_enforcement.py` | Python | Traceable enforcement-point verifier for `bounded_weak_normative` (rejects grep-only matches) |
| `apply_proposals.py` | Python | Deterministic proposal applicator. Reads per-fixture `proposals.json` from `outputs/<run_id>/<fixture_id>/proposals.json`; writes patched output to `outputs/<run_id>/<fixture_id>/patched/<fixture_id>.patched.md`. **Failure behavior**: on any error (span not found, `old_text` guard mismatch, overlapping spans, I/O error) → hard-abort with non-zero exit, zero partial output. The `patched/` directory is written atomically: all patches succeed or nothing is written. **Additional behaviors**: (1) **Recovery-aware idempotency check**: skips only `status: "applied"`; `status: "verifying"` is reconciled against `apply_base_hash`/`apply_candidate_hash` before any new apply. (2) **Auto-apply category guard**: in auto-apply path, resolves `source_finding` in sibling `findings.json`, treats the resolved category as authoritative, requires it to equal `cross_ref_broken`, and then enforces the AT-ID boundary rule; any category mismatch hard-aborts. (3) **Live promotion coordinates**: for live CONTRACT apply, resolves the target from current `section_index.md` + exact unique `old_text` match inside the live section and ignores fixture-local line numbers as write coordinates. (4) **TOCTOU diagnostic**: on `old_text` guard mismatch or span-not-found, logs current CONTRACT.md SHA256 vs `apply_base_hash` from `proposals_index.json`; error message includes both hashes to distinguish "CONTRACT.md changed" from "wrong proposal" cases. (5) **Promotion boundary**: the harness must durably write the `verifying` record before live CONTRACT rename; only the harness may finalize `status: "applied"` after `./plans/verify.sh full` exits 0. |
| `refresh_fixtures.sh` | Bash | Section extraction with hash validation |

### 7.2 What Does NOT Get Built (Yet)

- Shadow graduation tracking infrastructure (manual spreadsheet until volume warrants tooling)
- Automated promotion pipeline — **current promotion is manual**: after human review, the operator applies accepted proposals via `git apply` directly against `specs/CONTRACT.md`. The automated pipeline (§6.1, §6.5) — `validate_proposals.sh`, `apply_proposals.py`, atomic rename, lock, and verify-then-apply transaction — is the target design for a future revision.
- Sections beyond §2.2 and §1 (add after loop proves value)
- Phase 1 fixtures beyond the 7 seeds (add based on detector failure modes)
