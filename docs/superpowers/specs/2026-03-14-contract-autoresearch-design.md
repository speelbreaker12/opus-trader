# Contract Autoresearch Design

Two-phase Karpathy-style improvement loop for `specs/CONTRACT.md`. Phase 1 calibrates a detection skill that finds contract gaps. Phase 2 calibrates a patch skill that generates proposals to fix them. Human review gate controls what reaches the contract. **In v1, the system stops at proposal generation, fixture staging, and review-package rendering; live `CONTRACT.md` mutation remains manual.**

> **Revision note (2026-03-14, v8 manual-promotion baseline)**: Kept the manual-promotion rewrite as the source of truth and closed the three remaining v1 gaps: human decisions now live in a canonical `REVIEW_DECISIONS_<run_id>.json` artifact instead of mutable proposal status fields, `results.tsv` is restored to the existing autoresearch loop's 6-column protocol for harness compatibility, and broken planted-gap fixture mappings now fail closed during `refresh-common`. The spec continues to defer auto-apply, harness-managed live promotion, and automatic threshold rewrites from live snapshot content.

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Architecture | Two independent loops (Approach 1) | Clean separation: each loop optimizes one skill. Phase 1 planted-gap fixtures are stable across contract changes. |
| Phase 1 fixtures | Planted-gap (6 mutated + 1 clean) | Ground truth is known; detector quality is measurable via precision/recall. |
| Phase 2 fixtures | Dual-layer (static seeds + latest snapshot) | Static seeds prevent ratchet from destroying regression coverage; snapshots track real quality. |
| Phase 2 scoring | Structural assertions on `patched_fixture = apply(proposals, fixture)` | The loop must optimize the patcher, not the current contract state. Proposal-validity assertions are scored separately. |
| Phase 2 write boundary | `phase2/proposals/` and `phase2/review/` only; `CONTRACT.md` remains read-only to tooling | Keep proposal generation and review-package rendering inside the harness, but keep live contract mutation manual in v1. |
| Promotion model | Human review → manual `git apply` → `./plans/verify.sh full` → manual refresh | Human review is the constraint, not contract-mutation throughput. Remove fragile state machines until manual promotion becomes the bottleneck. |
| Structural target source | Reviewed `common/gate_input_registry.json` | Prevents snapshot refresh from silently ratcheting expectations downward and blessing regressions. |
| Seed sections | §2.2 PolicyGuard + §1 Execution Pipeline | Highest economic blast radius. Densest AT coverage. |

## Prerequisites

This spec extends the skill autoresearch infrastructure at `autoresearch/skills/`:

- `autoresearch/skills/harness.sh` — CLI harness (run, scaffold, baseline, eval, status)
- `autoresearch/skills/evaluate.py` — binary assertion evaluator
- `autoresearch/skills/program.md` — autonomous loop protocol
- `autoresearch/skills/premortem/` — first eval target (5 fixtures, 25 assertions)

These files exist in the repository. The contract subcommand reuses the same loop protocol and evaluator, adding contract-specific rule types and a `contract` command namespace.

---

## 1. Directory Structure

```
autoresearch/
  contract/
    common/                                # Shared context for both phases
      contract_header.md                   # §0.0 normative scope + definitions
      at_registry.json                     # All AT IDs with one-line descriptions (machine-parsable)
      gate_input_registry.json             # Reviewed source of governed inputs / expected fail-closed coverage per fixture
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
      review.schema.json
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
      review/
        CONTRACT_REVIEW_<run_id>.md        # Full review package with hashes, proposal list, and manual-review checklist
        REVIEW_DECISIONS_<run_id>.json     # Canonical machine-readable human review decisions
        CONTRACT_PATCH_<run_id>.patch      # Accepted-only patch artifact for manual `git apply`
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
  CONTRACT.md                              # Read-only to tooling in v1
```

`proposals_index.json` fields: `run_id`, `timestamp`, `contract_file_hash`, `status` (`pending|reviewed|rejected|stale|applied_manual`), `proposal_count`, `accepted_count`, `file_path`, optional `review_package_path`, optional `review_decisions_path`, optional `accepted_patch_path`, optional `applied_contract_hash`.

**`stale` status trigger**: a proposal batch becomes `stale` when the SHA256 of the current `CONTRACT.md` differs from the `contract_file_hash` recorded at proposal generation time. The operator MUST stop and re-run Phase 2 rather than hand-applying a stale patch onto a changed contract.

**No `verifying` state in v1**: the harness does not own a live-apply recovery window because it does not own live apply. There is no intermediate machine-managed promotion state between `reviewed` and `applied_manual`.

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
          "section": { "type": "string" },
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
          "section": { "type": "string" },
          "change_type": { "type": "string", "enum": ["mechanical", "new_requirement"] },
          "rationale": { "type": "string" },
          "status": { "type": "string", "enum": ["proposed", "pending_scope_review", "rejected", "stale"] },
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
            "description": "Category of the source finding (mirrors findings.schema.json category). Required on every proposal so category-specific validation cannot be bypassed by omission. The validation layer MUST cross-check this against the sibling finding object; self-declared category is never trusted on its own."
          }
        },
        "allOf": [
          {
            "if": {
              "properties": { "mechanical_ok": { "const": true } },
              "required": ["mechanical_ok"]
            },
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
              "description": "weak_normative proposals require enforcement_point (named function) and callsite_evidence (call path) per check_enforcement.py scope rules. These proposals remain human-reviewed in v1."
            }
          }
        ]
      }
    }
  }
}
```

Note: `proposed_text` is required when `change_type = new_requirement`. This is the actual clause text the human reviews and `check_contradictions.py` checks. `enforcement_point` and `callsite_evidence` are required for `weak_normative` proposals that suggest SHOULD→MUST enforcement upgrades; these remain human-reviewed in v1. Freshly generated `proposals.json` entries MUST start as `status: "proposed"`; later statuses in this file are assigned only by automated validation flow (`pending_scope_review`, `rejected`, `stale`).

> **Cross-file integrity requirement**: validation MUST cross-check `proposal.source_finding`, `proposal.source_finding_category`, and `proposal.section` against the sibling `findings.json` for the same `<run_id>/<fixture_id>`. The proposal file is not trusted to self-declare any of those values.

> **Constraint**: `change_type: "mechanical"` with `mechanical_ok: false` is prohibited. A mechanical proposal that cannot be auto-applied must be retyped as `new_requirement`. This prevents `apply_proposals.py` from receiving a mechanical proposal with no `replace_span` target.

### 2.3 Review Decision Schema (`phase2/review.schema.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["run_id", "reviewed_at", "contract_file_hash", "proposals_file_hash", "decisions"],
  "additionalProperties": false,
  "properties": {
    "run_id": { "type": "string" },
    "reviewed_at": { "type": "string", "format": "date-time" },
    "contract_file_hash": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
    "proposals_file_hash": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
    "decisions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["proposal_id", "decision", "reviewer", "reason_code"],
        "additionalProperties": false,
        "properties": {
          "proposal_id": { "type": "string", "pattern": "^P-[0-9]{3,}$" },
          "decision": { "type": "string", "enum": ["accepted", "rejected", "pending_scope_review"] },
          "reviewer": { "type": "string", "minLength": 1 },
          "reason_code": { "type": "string", "minLength": 1 },
          "notes": { "type": "string" }
        }
      }
    }
  }
}
```

`REVIEW_DECISIONS_<run_id>.json` is the sole machine-readable source of human review outcomes in v1. `proposals.json.status` is never authoritative for human acceptance or rejection.

### 2.4 Results.tsv Canonical Row Schema

```
commit  score  passed  total  status  description
```

- `commit`: short git hash (7 chars)
- `score`: `passed / total` — fraction of binary assertions that passed. Primary optimization metric.
- `passed` / `total`: legacy harness counters consumed by `autoresearch/skills/program.md` and `autoresearch/skills/harness.sh`.
- `status`: `baseline | keep | discard | crash`
- `description`: short free-form summary of the run.

Phase-specific metrics such as precision, recall, proposal counts, and accepted counts belong in run-local review artifacts or summaries. They MUST NOT change the canonical `results.tsv` column layout in v1.

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

F1 is the harmonic mean of precision and recall where both are defined. It may be surfaced in per-run summaries, but it is not an exit gate and it is not part of the canonical `results.tsv` protocol.

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
2. All `mechanical_ok: true` proposals resolve to **one unique exact target slice** in the pre-patch fixture. Validation checks line bounds and exact slice content, not just verbatim substring existence. Static fixtures: `fixture_path` only. Snapshot fixtures: `fixture_path` + `snapshot_path` (dual validation).
3. Zero proposals flagged by `check_contradictions.py`. Any non-zero exit, timeout, parse failure, or missing output from `check_contradictions.py` is treated as a failed contradiction check and aborts the batch (fail-closed).
4. No-change fixture emits zero proposals (`json_array_count_bounds`, min=0, max=0)
5. Every `source_finding` resolves to an actual `finding_id` in the sibling `findings.json` for the same `<run_id>/<fixture_id>` (`json_cross_ref_exists` between `proposals.json` and sibling `findings.json`). Fabricated source-finding IDs fail closed.
6. Every proposal's `source_finding_category` exactly matches the sibling finding's `category`, and every proposal's `section` exactly matches the sibling finding's `section` (`json_cross_ref_match` between `proposals.json` and sibling `findings.json`). Category spoofing and section spoofing fail closed.
7. All `proposal_id` values are unique within `proposals.json` (`json_unique_field` on `$.proposals[*].proposal_id`)
8. Freshly generated `proposals.json` entries all start as `status: "proposed"` before any validation transition. A patcher MUST NOT pre-set `pending_scope_review`, `rejected`, or `stale`.
9. For all `mechanical_ok: true` proposals: normalized `replace_span.new_text` differs from normalized `replace_span.old_text` (`json_field_not_match` on `$.proposals[?(@.mechanical_ok==true)].replace_span`, with whitespace normalization enabled before comparison). Blocks no-op and whitespace-only patcher patterns.
10. All `dedupe_key` values across proposals are unique (`json_unique_field` on `$.proposals[*].dedupe_key`). Blocks duplicate application.
11. All `change_type: "new_requirement"` proposals: `proposed_text` references at least one specific named entity — an AT-ID (`AT-\d+`), a gate function name, or a PolicyGuard/EvidenceGuard/DispatcherChokepoint keyword (`regex` on `$.proposals[?(@.change_type=="new_requirement")].proposed_text`, pattern: `(?i)\b(AT-\d+|PolicyGuard|EvidenceGuard|DispatcherChokepoint|evidence_chain|build_order_intent|LiquidityGate|RecordedBeforeDispatch|PreflightCheck)\b`). Blocks semantic-filler proposals ("The system MUST use appropriate thresholds") that degrade contract quality.

> **Post-apply hash check (assertion on patched fixtures)**: For each fixture where at least one proposal was applied, `hash(patched_fixture) != hash(original_fixture)`. If no proposal changed the fixture, the patcher made no improvement — this should be flagged as a potential no-op patcher signal.

**Structural assertions on `patched_fixture` (6 per real-section fixture = 24 total):**
1. Every governed input listed for the fixture in `common/gate_input_registry.json` has an explicit fail-closed clause. Each clause must name both (a) a degraded input condition (`NaN|missing|stale|absent`) and (b) a fail-closed outcome term (`ReduceOnly|Kill|reject|block|latch`). `gate_input_registry.json` is a reviewed source of truth; it is not auto-derived from refreshed snapshot content.
2. Every AT referenced has both TRIP and NON-TRIP specified
3. No SHOULD in lines containing any of: `TradingMode`, `dispatch`, `reject`, `block`, `latch`, `Kill`, `ReduceOnly`, `position limit`, `exposure limit`
4. Every gate-to-gate data dependency has an explicit ordering constraint
5. All proposals reference real line ranges in fixture or explicit staging copy (no hallucinated evidence)
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

Contradictions are flagged `status: rejected` with reason code `CONTRADICTION`. Scope-narrowings are flagged `status: pending_scope_review` with reason code `SCOPE_NARROWING`; they require explicit human review and manual application if accepted. Both run before any review package is rendered.

Any non-zero exit, timeout, parse failure, or missing result from `check_contradictions.py` is treated as a contradiction-check failure. The harness aborts the batch fail-closed rather than interpreting tool failure as "no contradictions found."

> **Note on scope narrowing**: A `SCOPE_NARROWING` finding is not necessarily wrong — it may reflect legitimate contract refinement. It is flagged to ensure human review rather than silent acceptance. No category may bypass SCOPE_NARROWING review, including `cross_ref_broken`.

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
harness.sh contract render-review   [--run-id RUN_ID] [--accepted-only] [--review PATH]
harness.sh contract refresh-fixtures
harness.sh contract refresh-common          # Rebuild common/ from CONTRACT.md + AT registry
harness.sh contract refresh-all             # refresh-common then refresh-fixtures
harness.sh contract status
```

`--eval` and `--workdir` are explicit. Defaults resolve to `autoresearch/contract/phase{1,2}/eval.json`. `baseline` is pure scoring — no skill or contract file modifications. `render-review` produces review artifacts only; it does not mutate `specs/CONTRACT.md`. When invoked with `--accepted-only`, it reads `REVIEW_DECISIONS_<run_id>.json` (or the path passed via `--review`) and emits a patch containing only proposals whose human decision is `accepted`.

### 5.2 evaluate.py New Rule Types

| Rule Type | Purpose | Parameters |
|-----------|---------|------------|
| `json_schema_valid` | Validate output against a JSON Schema | `schema_path`. Fails closed on non-JSON or multiple JSON objects. |
| `json_field_match` | Check JSON field value/pattern | `path` (JSONPath, e.g. `$.findings[*].category`), `pattern` or `value`. Type mismatches fail closed. |
| `json_array_count_bounds` | Assert array length bounds | `path`, `min`, `max` |
| `resolved_span_exists` | Verify `replace_span` resolves to one unique exact slice in the pre-patch source file | `fixture_path` (always — pre-patch source), optional `snapshot_path` for snapshot fixtures, `require_unique=true`, exact line-bound match semantics. **Never targets `patched/` directory.** |
| `json_field_not_match` | Assert that no element in a JSON array matches a given pattern/value | `path` (JSONPath), `pattern` or `value`. Fails closed on non-JSON. Used with `--json-output`. |
| `json_cross_ref_exists` | Verify that an ID in one JSON artifact resolves in a sibling JSON artifact | `source_path`, `target_path`, source JSONPath, target JSONPath. |
| `json_cross_ref_match` | Verify that named fields in one JSON artifact exactly match fields in a resolved sibling artifact | `source_path`, `target_path`, lookup field, and field map. |
| `json_unique_field` | Assert that all values selected by a JSONPath are unique | `path`. Fails closed on duplicates or non-JSON. |

> The harness validates `eval.json` at startup: any `resolved_span_exists` rule referencing a fixture under `fixtures/snapshot/` that lacks a `snapshot_path` field → fail with exit code 2: `eval.json error: snapshot fixture <path> requires snapshot_path in resolved_span_exists rule`.

### 5.3 Context Staleness Enforcement

Before each `run` or `baseline`, the harness compares `context_manifest.json` hashes against current file hashes. `context_manifest.json` tracks:
- All files in `common/` (`contract_header.md`, `at_registry.json`, `gate_input_registry.json`, `section_index.md`)
- All snapshot fixture files in `phase2/fixtures/snapshot/` (SHA256 of content)
- The CONTRACT.md file itself (SHA256 of content, stored as `contract_content_hash`)

Mismatch on any tracked file → abort with exit code 2, with error message depending on artifact class:
- `common/` file stale → `Stale context: <filename> changed. Run 'harness.sh contract refresh-common' first`
- snapshot fixture stale → `Stale context: snapshot/<filename> changed. Run 'harness.sh contract refresh-fixtures' first`
- CONTRACT.md hash stale (proposal index) → `Stale proposal: CONTRACT.md changed since generation (contract_file_hash mismatch). Re-run Phase 2.`

At manual promotion time, the operator MUST compare the current `CONTRACT.md` SHA256 to the `contract_file_hash` surfaced in both `proposals_index.json` and the review package. Any mismatch marks the batch `stale`; the patch MUST NOT be applied and Phase 2 must be re-run against the new contract base.

The `contract_content_hash` field in `context_manifest.json` is the authoritative source for staleness detection. In v1, staleness handling is a checklist gate, not a harness-managed recovery state machine.

### 5.4 Refresh Commands

#### refresh_fixtures.sh (phase-2 snapshot refresh)

1. Read `section_index.md` for line ranges
2. Extract sections from CONTRACT.md
3. Write to `phase2/fixtures/snapshot/`
4. Validate that every governed input declared in `common/gate_input_registry.json` still resolves in the extracted snapshot fixtures. Missing or ambiguous registry references fail closed and require manual registry review.
5. Update `context_manifest.json` (snapshot fixture hashes + contract_content_hash)
6. Fail fast if `section_index.md` ranges no longer align — require `refresh-common` first
7. Produce diff report if extraction anchors changed
8. **MUST NOT** rewrite `phase2/eval.json` or `common/gate_input_registry.json` from refreshed snapshot content

#### refresh_common.sh (shared context rebuild)

Rebuilds `common/` artifacts that both phases depend on. Run when:
- CONTRACT.md structure changes (new sections, renamed sections)
- AT registry changes (new ATs, retired ATs)
- The stale-context gate fires on a `common/` file

Steps:
1. Re-extract `contract_header.md` from CONTRACT.md §0.0 scope + definitions
2. Re-generate `at_registry.json` from CONTRACT.md AT-### anchors (all AT IDs + one-line descriptions)
3. Re-generate `section_index.md` section-to-line-range mapping from CONTRACT.md headings
4. Update `context_manifest.json` (common/ hashes)
5. Fail closed if any Phase 1 planted-gap fixture references a section that no longer exists in `section_index.md` — the fixture set is stale and must be manually repaired before further Phase 1 or Phase 2 runs
6. `gate_input_registry.json` is **not** regenerated automatically. Changes to governed-input inventory are manual spec edits reviewed like any other contract change.

Note: Phase 1 planted-gap fixtures (the mutated versions) are NOT rebuilt automatically — they encode specific injected defects and must be manually verified after `refresh-common` changes AT references or section structure.

### 5.5 Write Isolation Architecture

`CONTRACT.md` is protected by a **harness-level architectural barrier** during Phase 2 loops and review-package rendering.

**Primary barrier (architectural)**: Neither the LLM loop agent (`program.md`) nor the harness has an authorized write path to `specs/CONTRACT.md` in v1. Live contract changes are performed manually by the operator on a normal git branch after human review. `apply_proposals.py` and related tooling may write only under `autoresearch/contract/phase2/outputs/` and `autoresearch/contract/phase2/review/`.

The harness enforces this by:
1. Running the loop agent in a subprocess with a working directory restricted to `autoresearch/contract/` (not the repo root)
2. The loop agent's tool permissions do not include write access to `specs/`
3. Review-package rendering targets `phase2/review/` only; it does not receive a live-write mode in v1

**Secondary barrier (belt-and-suspenders)**:
```bash
# Before invoking any Phase 2 loop run or review-package render:
chmod 444 specs/CONTRACT.md

# After loop completes (harness restores via trap):
chmod 644 specs/CONTRACT.md
```

The `chmod 444` guard is a secondary, belt-and-suspenders measure. It will not fire on SIGKILL and can be bypassed by an agent with shell execution permissions. It is NOT relied upon as the primary safety barrier — the primary barrier is the architectural isolation above.

`CONTRACT_READONLY=1` is set as an advisory signal to tooling that checks it.

**SIGKILL recovery**: If the harness is killed without restoring permissions, the operator runs:
```bash
chmod 644 specs/CONTRACT.md
```
This is documented in the RUNBOOK. A CI check verifies CONTRACT.md permissions before each run.

---

## 6. Manual Promotion Path (v1)

### 6.1 End-to-End Flow

```
SETUP → PHASE 1 (detection calibration) → PHASE 2 (propose-then-apply-on-fixtures)
     → VALIDATE PROPOSALS (pre-review gate) → RENDER REVIEW PACKAGE
     → HUMAN REVIEW GATE (`REVIEW_DECISIONS_<run_id>.json`)
     → RENDER ACCEPTED-ONLY PATCH → MANUAL STALE CHECK
     → MANUAL `git apply` OR MANUAL EDIT
     → `./plans/verify.sh full`
     → MANUAL REFRESH / MANUAL REGISTRY REVIEW
```

There is **one harness-owned validation gate before review** and **one canonical machine-readable human review artifact**. Live `CONTRACT.md` mutation is outside the harness in v1.

**Pre-review validation gate** (`validate_proposals.sh`):
1. Validate `proposals.json` against `proposals.schema.json`
2. Re-resolve all `mechanical_ok: true` spans against the fixture using exact, unique slice validation
3. Run `check_contradictions.py` against current `CONTRACT.md`
4. Verify `source_finding`, `source_finding_category`, and `section` against sibling `findings.json`
5. Surface `context_manifest.json` `contract_content_hash` and proposal `contract_file_hash` in `CONTRACT_REVIEW_<run_id>.md`
6. Any schema, contradiction, span, or integrity failure → abort and do not render a review package

**Human review gate**:
1. Reviewer opens `CONTRACT_REVIEW_<run_id>.md`
2. Reviewer records one decision per proposal in `REVIEW_DECISIONS_<run_id>.json`
3. `REVIEW_DECISIONS_<run_id>.json` MUST validate against `phase2/review.schema.json`
4. `render-review --accepted-only` consumes the decision artifact and emits `CONTRACT_PATCH_<run_id>.patch`
5. If the review artifact is missing, invalid, references unknown proposal IDs, or omits a reviewed proposal, accepted-only rendering fails closed

### 6.2 Manual Promotion Checklist

1. Open `phase2/review/CONTRACT_REVIEW_<run_id>.md`
2. Record decisions in `phase2/review/REVIEW_DECISIONS_<run_id>.json`
3. Re-render the accepted-only patch from the decision artifact
4. Confirm the current `CONTRACT.md` SHA256 equals the review package `contract_file_hash`
5. If the hash differs, mark the batch `stale` and re-run Phase 2. Do **not** hand-apply an old patch onto a changed contract.
6. `cross_ref_broken` gets **no** auto-apply exemption in v1; any accepted proposal in that category is still manually reviewed and manually applied.
7. Apply the patch manually (`git apply phase2/review/CONTRACT_PATCH_<run_id>.patch`) or by manual edit on a normal git branch
8. Run `./plans/verify.sh full`
9. If verification fails, revert with normal git operations and leave the batch not applied
10. If verification passes, record `status: "applied_manual"`, `applied_contract_hash`, `review_decisions_path`, and `accepted_patch_path` in `proposals_index.json`, then run refresh commands manually

There is no partial-batch recovery state, no harness-owned rollback, and no machine-managed promotion window in v1.

### 6.3 Deferred Automation Ledger

The following are **explicitly deferred** and are not part of v1:
- Shadow graduation tracking infrastructure
- All category-based auto-apply, including `cross_ref_broken`
- Any harness or script that writes live `specs/CONTRACT.md`
- Any `verifying` intermediate state or automatic rollback / recovery workflow
- Automatic post-apply refresh that rewrites structural targets from live snapshot content
- Automatic regeneration of `gate_input_registry.json` from refreshed contract text

Automation may be reconsidered only after manual promotion is proven to be the active bottleneck over a meaningful sample of reviewed runs and the manual flow is stable.

### 6.4 Explicit Redlines (Normative)

- The harness **MUST NOT** write `specs/CONTRACT.md` in v1.
- `apply_proposals.py` **MUST NOT** mutate live contract files; it may only patch fixture copies and render review artifacts.
- `cross_ref_broken` **MUST NOT** bypass human review in v1.
- `proposals_index.json` **MUST NOT** use or persist `verifying` as a valid v1 status.
- `refresh_fixtures.sh` **MUST NOT** derive or rewrite structural targets from current snapshot text.
- Proposal validation **MUST** cross-check `source_finding`, `source_finding_category`, and `section` against sibling `findings.json`.
- `REVIEW_DECISIONS_<run_id>.json` **MUST** be the sole machine-readable source of human acceptance/rejection in v1.
- `proposals.json.status` **MUST NOT** be treated as authoritative for human review outcomes.
- Span validation **MUST** resolve one unique exact target slice; verbatim substring existence alone is insufficient.
- `gate_input_registry.json` **MUST** be a human-reviewed source of truth; changes to governed-input inventory are manual spec edits.

### 6.5 Manual Post-Apply Maintenance

After a manual apply that passes `./plans/verify.sh full`:
1. Run `harness.sh contract refresh-fixtures`
2. If contract structure or AT inventory changed, run `harness.sh contract refresh-common`
3. Review whether `common/gate_input_registry.json` must change. Do not auto-rewrite it from extracted snapshot content.
4. Re-run Phase 2 baseline/run to confirm snapshot fixtures and review-package logic remain aligned
5. Run a Phase 1 smoke set (clean fixture + 1 mutated fixture) to confirm shared context still scores correctly

---

## 7. Implementation Scope

### 7.1 What Gets Built

| Component | Type | Description |
|-----------|------|-------------|
| `SKILLS/contract-gap-detector.md` | Skill | Phase 1 loop target |
| `SKILLS/contract-patch.md` | Skill | Phase 2 loop target |
| `autoresearch/contract/` tree | Data | Eval configs, fixtures, schemas, shared context, review artifacts |
| `phase2/review.schema.json` | Schema | Canonical schema for `REVIEW_DECISIONS_<run_id>.json` human review artifacts |
| `evaluate.py` extensions | Python | Contract-specific rule types for schema validation, cross-file integrity, exact span resolution, and uniqueness |
| `harness.sh` contract subcommand | Bash | Phase 1/2 run/baseline, `render-review`, refresh-fixtures, refresh-common, status |
| `check_contradictions.py` | Python | Deterministic MUST-conflict checker (handles both mechanical and new_requirement proposals via `proposed_text` field) |
| `check_enforcement.py` | Python | Traceable enforcement-point verifier for `weak_normative` SHOULD→MUST proposals (rejects grep-only matches) |
| `apply_proposals.py` | Python | Deterministic proposal applicator for fixture copies and review-package rendering. Reads per-fixture `proposals.json` from `outputs/<run_id>/<fixture_id>/proposals.json`; writes patched fixture output to `outputs/<run_id>/<fixture_id>/patched/<fixture_id>.patched.md` and may render `review/CONTRACT_PATCH_<run_id>.patch`. In accepted-only mode it consumes `REVIEW_DECISIONS_<run_id>.json` and emits only human-accepted proposals. **Failure behavior**: on any error (span not found, exact-slice mismatch, overlapping spans, invalid review decisions, I/O error) → hard-abort with non-zero exit, zero partial output. The `patched/` and `review/` outputs are written atomically. **v1 boundary**: MUST NOT write live `specs/CONTRACT.md`; MUST NOT manage `verifying`, rollback, or live promotion state. |
| `refresh_fixtures.sh` | Bash | Section extraction with hash validation and registry-reference checks; no automatic threshold rewrites |

### 7.2 What Does NOT Get Built (Yet)

- Shadow graduation tracking infrastructure (manual review remains the trust boundary)
- Automated promotion pipeline or any tool-owned live write path to `specs/CONTRACT.md`
- Auto-apply exceptions by category, including `cross_ref_broken`
- Harness-managed `verifying` state, automatic rollback, or recovery logic for live contract promotion
- Automatic refresh that rewrites gate-input expectations or `gate_input_registry.json` from live contract content
- Sections beyond §2.2 and §1 (add after the loop proves value)
- Phase 1 fixtures beyond the 7 seeds (add based on detector failure modes)
