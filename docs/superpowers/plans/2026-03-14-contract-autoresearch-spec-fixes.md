# Contract Autoresearch Spec Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply all 18 findings from the 7-skill review stack to `docs/superpowers/specs/2026-03-14-contract-autoresearch-design.md`.

**Architecture:** All changes are to a single spec document. Fixes are grouped by spec section. No code is written — this updates the design spec that governs what gets built. The spec changes will be committed section-by-section for reviewability.

**Tech Stack:** Markdown spec editing only. No compilation, no tests to run.

---

## Chunk 1: Schema fixes (§2.2 proposals.schema.json + §1 proposals_index.json)

**Files:**
- Modify: `docs/superpowers/specs/2026-03-14-contract-autoresearch-design.md`

### Task 1: proposals_index.json — rename `git_hash` → `contract_file_hash` (HIGH-2)

The `git_hash` field name implies a git commit SHA, but the staleness check compares file content hashes — incompatible hash spaces that make staleness detection never trigger.

- [ ] In §1, find the `proposals_index.json` Fields line:
  ```
  Fields: `run_id`, `timestamp`, `git_hash`, `status` (pending|reviewed|applied|rejected|stale), `proposal_count`, `accepted_count`, `file_path`.
  ```
  Change to:
  ```
  Fields: `run_id`, `timestamp`, `contract_file_hash`, `status` (pending|reviewed|applied|rejected|stale), `proposal_count`, `accepted_count`, `file_path`.
  ```

- [ ] Find the `**Invariant**` / `**\`stale\` status trigger**` prose and update the stale trigger to read:

  > **`stale` status trigger**: A proposal entry transitions to `stale` when CONTRACT.md has changed since the proposal was generated — specifically, when the SHA256 of CONTRACT.md file content at promotion time differs from the `contract_file_hash` value recorded in the entry (which is the SHA256 of CONTRACT.md content at proposal generation time). The harness checks this during promotion and blocks apply of any stale proposal.

- [ ] Commit: `spec: rename git_hash → contract_file_hash in proposals_index (HIGH-2)`

---

### Task 2: proposals.schema.json — add bounds to replace_span (MED-3, LOW-1)

Empty `old_text` trivially matches anywhere; line 0 or negative produces undefined behavior.

- [ ] In §2.2, inside the `replace_span` properties object, change `old_text` from:
  ```json
  "old_text": { "type": "string" },
  ```
  to:
  ```json
  "old_text": { "type": "string", "minLength": 10 },
  ```

- [ ] Add `"minimum": 1` to `start_line` and `end_line`:
  ```json
  "start_line": { "type": "integer", "minimum": 1 },
  "end_line": { "type": "integer", "minimum": 1 },
  ```

- [ ] Commit: `spec: add minLength/minimum bounds to replace_span (MED-3, LOW-1)`

---

### Task 3: proposals.schema.json — fix mechanical_ok/change_type ambiguity (CRITICAL-2)

A proposal can be `change_type: "mechanical"` with `mechanical_ok: false` — no `replace_span` is required yet `apply_proposals.py` receives an ambiguous mechanical proposal with no apply target.

- [ ] In §2.2 proposals schema, add a new `allOf` branch (add after the existing two `allOf` items inside `items`):
  ```json
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
  }
  ```

- [ ] Add a note below the schema:

  > **Constraint**: `change_type: "mechanical"` with `mechanical_ok: false` is prohibited. A mechanical proposal that cannot be auto-applied must be retyped as `new_requirement`. This prevents `apply_proposals.py` from receiving a mechanical proposal with no `replace_span` target.

- [ ] Commit: `spec: prohibit mechanical_ok=false + change_type=mechanical combination (CRITICAL-2)`

---

### Task 4: proposals.schema.json — add source_finding_category + bounded_weak_normative allOf (HIGH-5)

`enforcement_point`/`callsite_evidence` are prose-only requirements for `bounded_weak_normative`; no schema enforcement exists.

- [ ] In §2.2 proposals schema `properties`, add a new optional field after `new_ats`:
  ```json
  "source_finding_category": {
    "type": "string",
    "enum": ["missing_fail_closed", "weak_normative", "missing_at_pair",
             "stale_input_unspecified", "gate_interaction_gap", "cross_ref_broken"],
    "description": "Category of the source finding (mirrors findings.schema.json category). Required for bounded_weak_normative proposals when that subtype is unlocked."
  }
  ```

- [ ] Add a new `allOf` branch:
  ```json
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
  ```

- [ ] Commit: `spec: enforce enforcement_point/callsite_evidence for weak_normative proposals (HIGH-5)`

---

### Task 5: proposals.schema.json — dedupe_key uniqueness note (HIGH-6)

Two proposals with identical `dedupe_key` values can both be applied silently.

- [ ] In §2.2, find the `dedupe_key` property definition and change it from:
  ```json
  "dedupe_key": { "type": "string" },
  ```
  to:
  ```json
  "dedupe_key": { "type": "string", "minLength": 1 },
  ```

- [ ] In §4.3 Proposal-validity assertions, add assertion 9 (after the new assertion 8 added in Task 8):
  ```
  9. All `dedupe_key` values across proposals in the array are unique (`json_array_count_bounds` on dedupe_key distinct count equals total proposal count). Blocks duplicate proposals from being applied twice.
  ```

- [ ] Commit: `spec: add dedupe_key uniqueness assertion (HIGH-6)`

---

## Chunk 2: Assertion and rule-type fixes (§3.3, §4.3, §4.4, §5.2)

### Task 6: Phase 1 Assertion #6 — add json_field_not_match rule type (HIGH-4)

Assertion #6 requires a negative JSON field match that no existing rule type can express.

- [ ] In §5.2 evaluate.py new rule types, add a new row to the table:

  | `json_field_not_match` | Assert that no element in a JSON array matches a given pattern/value | `path` (JSONPath), `pattern` or `value`. Fails closed on non-JSON. | `--json-output` |

- [ ] In §3.3 assertions, update assertion 6 for mutated training fixtures to read:
  ```
  6. No P0/P1 findings with `evidence.quote` containing tokens outside the injected region's known token set (`json_field_not_match` on `$.findings[?(@.severity=="P0" || @.severity=="P1")].evidence.quote`, pattern built from each fixture's injected token list defined in `eval.json`)
  ```

- [ ] In `eval.json` format documentation (or in §3.3 inline), note that each mutated fixture entry in `eval.json` includes an `injected_tokens` array — the known tokens from the injection site used by assertion 6.

- [ ] Commit: `spec: add json_field_not_match rule type; fix Phase 1 assertion 6 (HIGH-4)`

---

### Task 7: Phase 2 assertions — add assertions 8, 9, 10 (CRITICAL-1, MED-5)

The no-op patcher (new_text == old_text) passes all 7 existing assertions; semantic-filler new_requirement proposals pass too.

- [ ] In §4.3 Proposal-validity assertions, after assertion 7, add:
  ```
  8. For all `mechanical_ok: true` proposals: `replace_span.new_text != replace_span.old_text` (`json_field_not_match` on `$.proposals[?(@.mechanical_ok==true)].replace_span`, asserting old_text and new_text differ). Blocks the no-op patcher pattern where proposals are generated with identical old and new text.
  9. All `dedupe_key` values across proposals are unique — proposal count equals distinct-dedupe_key count (`json_array_count_bounds` with equality check). Blocks duplicate application.
  10. All `change_type: "new_requirement"` proposals: `proposed_text` references at least one specific named entity — an AT-ID (`AT-\d+`), a gate function name, or a PolicyGuard/EvidenceGuard/DispatcherChokepoint keyword (`regex` on `$.proposals[?(@.change_type=="new_requirement")].proposed_text`, pattern: `(?i)\b(AT-\d+|PolicyGuard|EvidenceGuard|DispatcherChokepoint|evidence_chain|build_order_intent|LiquidityGate|RecordedBeforeDispatch|PrefightCheck)\b`). Blocks semantic-filler proposals ("The system MUST use appropriate thresholds") that degrade contract quality.
  ```

- [ ] Also add a post-apply structural check note:
  > **Post-apply hash check (assertion on patched fixtures)**: For each fixture where at least one proposal was applied, `hash(patched_fixture) != hash(original_fixture)`. If no proposal changed the fixture, the patcher made no improvement — this should be flagged as a potential no-op patcher signal.

- [ ] Commit: `spec: add assertions 8-10 to block no-op patcher and semantic filler (CRITICAL-1, MED-5)`

---

### Task 8: check_contradictions.py — extend scope (CRITICAL-3, LOW-4)

Scope-narrowing MUST weakening (adding conditional guards) and SHALL-to-SHOULD downgrades are undetected.

- [ ] In §4.4, replace the contradiction rule enforcement section with:

  **Enforcement**: `check_contradictions.py` performs:
  - Extract all MUST and SHALL sentences from CONTRACT.md (both treated as normatively equivalent per RFC 2119)
  - **Mechanical proposals**: diff `old_text` vs `new_text`:
    - MUST/SHALL present in `old_text` but absent/weakened in `new_text` → CONTRADICTION
    - MUST/SHALL present in `old_text` but changed to SHOULD/MAY in `new_text` → CONTRADICTION
    - New MUST/SHALL with overlapping subject and negated predicate → CONTRADICTION
    - **Scope narrowing**: MUST/SHALL clause in `old_text` is unconditional, but equivalent clause in `new_text` adds a conditional guard (`AND`, `OR`, `EXCEPT`, `IF`, `WHEN`, `UNLESS`) → SCOPE_NARROWING (flagged separately, always requires human review regardless of category)
    - MUST NOT changed to MUST (negation flip) → CONTRADICTION
  - **New-requirement proposals**: extract MUST/SHALL clauses from `proposed_text` field; check each against existing MUSTs/SHALLs for subject overlap + negation conflict

  Contradictions and scope-narrowings are flagged `status: rejected` with reason code (`CONTRADICTION` or `SCOPE_NARROWING`). Both run before any proposal is promoted.

  > **Note on scope narrowing**: A `SCOPE_NARROWING` finding is not necessarily wrong — it may reflect legitimate contract refinement. It is flagged to ensure human review rather than auto-rejected. No category may bypass SCOPE_NARROWING review, including `cross_ref_broken`.

- [ ] Commit: `spec: extend contradiction checker for SHALL, scope-narrowing, negation flip (CRITICAL-3, LOW-4)`

---

## Chunk 3: Write barrier, sequencing, and staleness fixes (§5.3, §5.5, §6.1)

### Task 9: Context staleness — add snapshot fixture tracking (MED-6)

Snapshot fixture staleness is invisible to `context_manifest.json`.

- [ ] In §5.3 Context Staleness Enforcement, extend the description:

  Before each `run` or `baseline`, the harness compares `context_manifest.json` hashes against current file hashes. `context_manifest.json` tracks:
  - All files in `common/` (contract_header.md, at_registry.json, section_index.md)
  - All snapshot fixture files in `phase2/fixtures/snapshot/` (SHA256 of content)
  - The CONTRACT.md file itself (SHA256 of content, stored as `contract_content_hash`)

  Mismatch on any tracked file → abort with exit code 2: `Stale context: <filename> changed. Run 'harness.sh contract refresh-fixtures' first`.

  The `contract_content_hash` field in `context_manifest.json` is the authoritative source for staleness detection — it is compared against `contract_file_hash` in `proposals_index.json` entries at promotion time.

- [ ] Commit: `spec: add snapshot fixtures and CONTRACT.md hash to context_manifest (MED-6)`

---

### Task 10: Write barrier — rearchitect from chmod to harness-level isolation (HIGH-1)

`chmod 444` is not a write barrier against the LLM agent (which can call `chmod 644` as a shell command), and is not SIGKILL-safe.

- [ ] In §5.5, replace the entire section with:

  ### 5.5 Write Isolation Architecture

  CONTRACT.md is protected by a **harness-level architectural barrier** during Phase 2 loops:

  **Primary barrier (architectural)**: The LLM loop agent (`program.md`) has no authorized write path to `specs/CONTRACT.md`. All writes to CONTRACT.md are performed exclusively by `apply_proposals.py`, which is invoked by the harness (not the loop agent). The loop agent's output is `proposals.json` in the `phase2/outputs/<run_id>/` directory — it never touches `specs/` directly.

  The harness enforces this by:
  1. Running the loop agent in a subprocess with a working directory restricted to `autoresearch/contract/` (not the repo root)
  2. The loop agent's tool permissions do not include write access to `specs/`

  **Secondary barrier (belt-and-suspenders)**:
  ```bash
  # Before invoking any Phase 2 loop run:
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

- [ ] Commit: `spec: rearchitect write barrier to harness-level isolation (HIGH-1)`

---

### Task 11: validate_proposals.sh — fix sequencing (HIGH-3, MED-1)

The flow diagram shows pre-review validation; prose says post-review. The fix: pre-review is correct. Add hash sidecar for TOCTOU diagnostic.

- [ ] In §6.1, update the flow diagram to explicitly show:
  ```
  SETUP → PHASE 1 (detection calibration) → PHASE 2 (propose-then-apply)
       → VALIDATE PROPOSALS (pre-review gate) → HUMAN REVIEW GATE
       → [accepted proposals only] → VALIDATE PROPOSALS (pre-apply gate, re-check for drift)
       → SHADOW GRADUATION (cross_ref_broken only) → AUTO-APPLY
       → POST-APPLY REFRESH
  ```
  (Two validation passes: once before human review to catch stale/invalid proposals early, once after review to catch CONTRACT.md drift since review)

- [ ] Update the `validate_proposals.sh` prose to:

  **Pre-promotion validation gate** (`validate_proposals.sh`): Runs **twice**:

  **Pass 1 — Pre-review** (immediately after Phase 2 run, before presenting proposals to reviewer):
  1. Validate `proposals.json` against `proposals.schema.json`
  2. Check all `mechanical_ok: true` spans against the **snapshot fixture** (not CONTRACT.md yet)
  3. Run `check_contradictions.py` against current CONTRACT.md
  4. Surface `context_manifest.json` contract_content_hash and proposal `contract_file_hash` to reviewer in `CONTRACT_PROPOSALS_<run_id>.md` — reviewer sees whether they're reviewing against a current or stale CONTRACT.md base
  5. Any schema or contradiction failure → abort and notify; reviewer does not see invalid proposals

  **Pass 2 — Pre-apply** (after human review, before `apply_proposals.py` runs on accepted proposals):
  1. Re-validate accepted proposals against `proposals.schema.json`
  2. Re-check all `mechanical_ok: true` spans against **current CONTRACT.md** (not snapshot) — span may have drifted since generation. Mismatch → mark proposal `stale`, abort that proposal
  3. Re-run `check_contradictions.py` against current CONTRACT.md
  4. Any failure → abort **entire promotion batch**; notify reviewer; do not apply partial batch
  5. Record pre-apply CONTRACT.md hash in `proposals_index.json` as `apply_base_hash`

  `apply_proposals.py` logs the CONTRACT.md hash it observed vs. `apply_base_hash` from the index. If they differ (TOCTOU race), abort with: `CONTRACT.md changed between validation and apply: expected <hash>, found <hash>`. This provides a clear diagnostic rather than a cryptic span-not-found abort.

- [ ] Commit: `spec: fix validate_proposals.sh to pre-review + pre-apply dual-pass, add TOCTOU diagnostic (HIGH-3, MED-1)`

---

## Chunk 4: Auto-apply restriction, graduation, post-apply cycle (§6.3, §6.4, §6.5)

### Task 12: cross_ref_broken auto-apply — restrict to AT-ID token repairs (CRITICAL-4)

`cross_ref_broken` auto-apply can silently redirect an AT reference to a less-restrictive or monitoring-only section. The "zero semantic content" claim is unproven for section-number repairs.

- [ ] In §6.3, update the `cross_ref_broken` row:

  | `cross_ref_broken` | `cross_ref_broken` | **YES — restricted** | **Restricted to AT-ID token repairs only** (see §6.4 boundary rule). Section-number reference repairs require human review. |

- [ ] In §6.4, update the `cross_ref_broken` GRADUATED entry:

  | 1 | `cross_ref_broken` | **GRADUATED (AT-ID repairs only)** | **Boundary rule**: Auto-apply is restricted to proposals that replace an AT-ID reference token (`AT-\d+` pattern) with another AT-ID reference token, where the target AT-ID exists in `at_registry.json`. A pre-apply gate verifies: (1) `old_text` contains exactly one `AT-\d+` token, (2) `new_text` contains exactly one `AT-\d+` token, (3) the new AT-ID exists in `at_registry.json`. Section-number repairs, prose changes, and any other structural changes require human review. No semantic change is possible when an AT-ID is replaced with another AT-ID in `at_registry.json`. |

- [ ] Add a note below the table:

  > **`cross_ref_broken` pre-graduation rationale**: This category is marked GRADUATED without running the §6.2 N/M/agreement-rate process because the auto-apply boundary rule (AT-ID token replacement only, verified against `at_registry.json`) reduces the problem to a structural lookup with zero semantic judgment required. The adversarial pre-condition (§6.2) is satisfied by construction: an adversarial proposal that attempts to replace an AT-ID with a non-existent AT-ID is blocked by the `at_registry.json` existence check. An adversarial proposal that replaces an AT-ID with an existing but semantically different AT-ID is considered an accepted risk for `cross_ref_broken` repairs, since AT-IDs in `at_registry.json` have machine-readable descriptions that make wrong-ID substitutions detectable by the human reviewing the proposals index.

- [ ] Add `category_guard` step to §7.1 apply_proposals.py description:

  > **Auto-apply category guard**: Before applying any proposal in the auto-apply path (not human-triggered), `apply_proposals.py` verifies `source_finding_category == "cross_ref_broken"` AND the AT-ID boundary rule: `old_text` contains exactly one `AT-\d+` token and `new_text` contains exactly one `AT-\d+` token that exists in `at_registry.json`. Any violation → hard-abort with non-zero exit. Human-triggered apply (Pass 2 of validate_proposals.sh) does not apply the category guard — human review is the gate.

- [ ] Commit: `spec: restrict cross_ref_broken auto-apply to AT-ID token repairs only (CRITICAL-4)`

---

### Task 13: cross_ref_broken graduation — document §6.2 exemption (CRITICAL-5)

The spec marks `cross_ref_broken` as GRADUATED without applying the §6.2 graduation machinery. This needs explicit justification.

- [ ] In §6.2, add a note at the end:

  > **Graduation process applicability**: The §6.2 graduation process (N=10 runs, M=20 proposals, ≥0.95 agreement, adversarial pre-condition) applies to the categories in **Order 2–6** when they are candidates for auto-apply. `cross_ref_broken` (Order 1) is GRADUATED by design decision rather than by running the §6.2 process because its auto-apply boundary rule (AT-ID token replacement, existence check in `at_registry.json`) eliminates LLM judgment from the apply decision entirely. The graduation criteria in §6.2 measure "can the machine's accept/reject judgment match human judgment?" — a question that is vacuous when no judgment is required. The adversarial pre-condition from §6.2 is satisfied by construction per §6.4's boundary rule note.

- [ ] Commit: `spec: document cross_ref_broken §6.2 graduation exemption rationale (CRITICAL-5)`

---

### Task 14: Post-apply refresh cycle — add expected_gate_input_count refresh and idempotency (MED-2, LOW-2)

After applying a `missing_fail_closed` proposal, the fail-closed clause count in CONTRACT.md increases. The `eval.json` threshold is not updated. Subsequent Phase 2 runs score against a stale floor.

- [ ] In §6.5, update the post-apply refresh cycle steps:

  After any accepted proposal is applied to CONTRACT.md:
  1. `validate_proposals.sh` Pass 2 pre-apply gate must pass before apply (see §6.1)
  2. **Idempotency pre-check**: Before applying, `apply_proposals.py` checks `proposals_index.json` — if any proposal already has `status: "applied"`, skip it and log a warning. This prevents double-apply if the process dies between CONTRACT.md write and index update.
  3. `apply_proposals.py` writes CONTRACT.md atomically (write to temp, rename), then immediately updates `proposals_index.json` with `status: "applied"` and `apply_base_hash`. The index update must complete before the harness proceeds.
  4. `verify.sh full` — runs immediately after apply, before any fixture refresh. If `verify.sh full` fails, revert the apply (`git checkout specs/CONTRACT.md`) and block the run. The apply is not committed until `verify.sh full` exits 0.
  5. `refresh_fixtures.sh` re-extracts snapshot fixtures
  6. **Threshold refresh**: For each fixture in `phase2/fixtures/`, recount fail-closed clauses matching the `eval.json` assertion 1 pattern (MUST + input_name + NaN|missing|stale|absent) in the refreshed fixture. Update `phase2/eval.json` `expected_gate_input_count` for each affected fixture. Commit the `eval.json` update alongside the CONTRACT.md change.
  7. Re-run Phase 2 to confirm ratchet (patched fixture structural assertions should now pass on clean run)
  8. Phase 1 smoke set (clean fixture + 1 mutated fixture) to verify shared context drift
  9. If smoke fails: re-extract `common/` and re-run Phase 1 baseline

- [ ] Commit: `spec: add threshold refresh + idempotency to post-apply cycle (MED-2, LOW-2)`

---

## Chunk 5: apply_proposals.py description and remaining fixes (§7.1, §2.3, §4.3)

### Task 15: apply_proposals.py — add idempotency, category guard, hash sidecar to §7.1 (LOW-2, LOW-3, MED-1)

- [ ] In §7.1 What Gets Built, update the `apply_proposals.py` row:

  | `apply_proposals.py` | Python | Deterministic proposal applicator. **Failure behavior**: on any error (span not found, `old_text` guard mismatch, overlapping spans, I/O error) → hard-abort with non-zero exit, zero partial output. The `patched/` directory is written atomically: all patches succeed or nothing is written. **Additional behaviors**: (1) **Idempotency check**: reads `proposals_index.json` before each proposal — skips any with `status: "applied"`, logs warning. (2) **Auto-apply category guard**: in auto-apply path, verifies `source_finding_category == "cross_ref_broken"` and AT-ID boundary rule; hard-aborts on violation. (3) **TOCTOU diagnostic**: on `old_text` guard mismatch or span-not-found, logs current CONTRACT.md SHA256 vs `apply_base_hash` from `proposals_index.json`; error message includes both hashes to distinguish "CONTRACT.md changed" from "wrong proposal" cases. |

- [ ] Commit: `spec: add idempotency, category guard, TOCTOU diagnostic to apply_proposals.py spec (LOW-2, LOW-3, MED-1)`

---

### Task 16: snapshot_path required for snapshot fixtures in line_span_exists (MED-4)

`snapshot_path` is optional in the rule definition but is required for snapshot fixtures, creating a silent degradation path.

- [ ] In §5.2, update the `line_span_exists` row:

  | `line_span_exists` | Verify `replace_span.old_text` exists in pre-patch source file | `fixture_path` (always — pre-patch source); `snapshot_path` (**required** for fixtures under `fixtures/snapshot/`, optional otherwise — harness errors if `snapshot_path` is absent for a snapshot fixture). **Never targets `patched/` directory.** | `--json-output` (reads span) + `fixture_path` (checks source) |

- [ ] In the JSON output integration path note (below the table), add:

  > The harness validates `eval.json` at startup: any `line_span_exists` rule referencing a fixture under `fixtures/snapshot/` that lacks a `snapshot_path` field → fail with exit code 2: `eval.json error: snapshot fixture <path> requires snapshot_path in line_span_exists rule`.

- [ ] Commit: `spec: make snapshot_path required for snapshot fixtures in line_span_exists (MED-4)`

---

### Task 17: Update revision note to document this second review round

- [ ] In the revision note at the top of the spec, add:

  > **Revision note (2026-03-14, v3)**: Applied fixes from 7-skill review stack (v2) `artifacts/design-reviews/2026-03-14-contract-autoresearch-review-v2.md`. Key changes: AT-ID-only restriction on cross_ref_broken auto-apply (CRITICAL-4), graduation exemption rationale (CRITICAL-5), scope-narrowing detection in check_contradictions.py (CRITICAL-3), no-op patcher blocked via assertion 8 (CRITICAL-1), mechanical_ok/change_type disambiguation (CRITICAL-2), harness-level write isolation architecture (HIGH-1), contract_file_hash field rename (HIGH-2), dual-pass validate_proposals.sh (HIGH-3), json_field_not_match rule type added (HIGH-4), enforcement_point/callsite_evidence allOf branch (HIGH-5), dedupe_key uniqueness assertion (HIGH-6), snapshot fixture tracking in context_manifest (MED-6), expected_gate_input_count refresh in post-apply cycle (MED-2), minLength/minimum schema bounds (MED-3/LOW-1), source_finding_category field added (HIGH-5), idempotency guard in apply_proposals.py (LOW-2), category guard in auto-apply path (LOW-3), SHALL added to contradiction checker (LOW-4).

- [ ] Commit: `spec: update revision note for v3 fixes`

---

## Execution Notes

- All edits are to the single file: `docs/superpowers/specs/2026-03-14-contract-autoresearch-design.md`
- Use targeted Edit calls (old_string → new_string) rather than full rewrites
- Commit after each task group for reviewability
- No code to compile, no tests to run — these are spec edits only
- The review artifacts are in `artifacts/design-reviews/` (gitignored) — do not commit those

## Verification

After all tasks complete, run a quick self-check:
- [ ] Search for `git_hash` in the spec — should find zero occurrences
- [ ] Search for `chmod 444` — should appear only in "secondary barrier" context, not as "primary guard"
- [ ] Count proposal-validity assertions in §4.3 — should be 10 (was 7)
- [ ] Verify `cross_ref_broken` row in §6.4 says "AT-ID repairs only"
- [ ] Verify `validate_proposals.sh` prose describes two passes (pre-review + pre-apply)
- [ ] Verify `json_field_not_match` appears in §5.2 rule types table
