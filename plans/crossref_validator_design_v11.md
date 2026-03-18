# Cross-Reference Validator Design v11
## Fail-Closed Gating Update (Post v10 Review)

**Version:** 11.3  
**Status:** Updated plan for implementation  
**Supersedes:** `plans/crossref_validator_design_v10.md`

---

## 1. Decision

Adopt the mandatory fixes as hard requirements before treating crossref validation as a merge-grade gate.

This update changes the plan from reporting-oriented to gate-oriented for CI safety, with an explicit rollout:
- PR status gate timing: 1-2 week burn-in, then mandatory required status check.
- Marker rollout: dual parser -> strict marker in CI -> marker-only.
- Canonical evidence source for CI gating: phase checklist docs (roadmap remains informational).

---

## 2. Non-Negotiable Fixes

### F1) Single shared AT parser module + map-level parity (no manual regex sync)

Problem:
- Keeping AT parsing logic in two tools causes drift.
- Totals-only parity can pass with wrong per-AT profile assignment.

Plan:
1. Create shared parser module:
- `tools/at_parser.py`
2. Both tools must import shared parsing (no fallback local AT/Profile regex parsing paths):
- `tools/ci/check_contract_profiles.py`
- `tools/at_coverage_report.py`
3. Shared canonical AT regex:
- `AT_RE = re.compile(r"^\s*(AT-\d+)\b")`
4. Shared canonical Profile regex:
- `PROFILE_RE = re.compile(r"^Profile:\s+(CSP|GOP|FULL)\s*$")`
5. Both tools emit canonical map artifact:
- `{ "AT-###": "CSP|GOP" }`
6. Parity enforcement:
- Parity is asserted in `./plans/verify.sh full`.
- Parity is asserted in CI pipeline on every PR.
- CI parity divergence is fatal (non-zero).
- Parity checks compare exact key/value equality of maps, not only totals.

Acceptance:
- `AT-1070` is detected by both tools.
- Coverage map equals canonical checker map exactly.
- A parity test fails if maps diverge.

---

### F2) Strict mode fail-closed with deterministic categorization

Problem:
- Strict mode can be bypassed if UNKNOWN handling/categorization is ambiguous.

Plan:
1. Strict mode includes:
- `STORY_OWNED`
- `UNKNOWN`
2. Strict mode excludes only:
- `GLOBAL_MANUAL`
3. Deterministic categorization rules:
- Marker exists for required evidence path but producer is missing -> `STORY_OWNED`
- Required evidence appears without any valid marker ownership -> `UNKNOWN`
- Marker exists but malformed -> `UNKNOWN`
- Producer mismatch under exact matching -> `STORY_OWNED`
- Only `GLOBAL_MANUAL` is suppressible in strict mode
4. No manual reclassification flag in CI path.

Acceptance:
- New uncategorized required evidence blocks strict CI until explicitly resolved.

---

### F3) Enforceable CI exit semantics (`--ci`) with stable exit contract

Problem:
- Informational-only output has no gate teeth.
- Opaque non-zero codes reduce CI ergonomics.

Plan:
1. Add CI mode to audit tool (`--ci`; optional alias `--fail-on-gaps`).
2. Default mode remains informational (exit 0).
3. Stable exit codes:
- `0` = pass
- `2` = tool/runtime/parse failure
- `3` = policy gap failure (`STORY_OWNED` / `UNKNOWN`)
- `4` = marker/schema violation (malformed, invalid format, duplicate-normalized, missing required marker intent)
- `5` = AT parity map divergence
4. CI mode must fail when:
- Strict gaps exist (`STORY_OWNED` or `UNKNOWN`)
- Any `UNKNOWN` gaps exist
- Required inputs are missing/unreadable (`--roadmap`, `--checklist`, `--prd`)
- Marker intent is absent in governed files (neither REQUIRED markers nor explicit NONE sentinel)
- Marker/schema violations exist
- AT parity map diverges from canonical checker map
5. Emit deterministic diagnostics for each failure reason.

Acceptance:
- CI mode blocks merges on unresolved strict/unknown gaps, schema violations, and parity divergence.

---

### F4) Exact producer matching by default; fuzzy opt-in only

Problem:
- Default fuzzy matching creates silent false-pass risk.

Plan:
1. Default producer resolution uses exact path match only.
2. Add opt-in fuzzy mode:
- `--fuzzy`
3. When fuzzy is enabled, output must include explicit fuzzy resolution records:
- `fuzzy_matches: [...]`
4. CI semantics for fuzzy matching:
- In CI mode, fuzzy matches satisfy requirements only when `--fuzzy` is explicitly passed.
- In CI mode without `--fuzzy`, fuzzy candidates are treated as unmatched.

Acceptance:
- Without `--fuzzy`, only exact producer paths satisfy requirements.
- With `--fuzzy`, every fuzzy-resolved path is visible and auditable.

---

### F5) Deterministic REQUIRED_EVIDENCE grammar (AND/OR/NONE)

Problem:
- Prose/context-window markdown scraping is brittle.
- OR fallback evidence requirements need first-class representation.

Plan:
1. Define marker grammar:
- AND requirement: `<!-- REQUIRED_EVIDENCE: <relative-path> -->`
- OR requirement: `<!-- REQUIRED_EVIDENCE_ANY_OF: <relative-path> | <relative-path> [ | ... ] -->`
- Explicit none sentinel: `<!-- REQUIRED_EVIDENCE_NONE -->`
2. Marker semantics:
- `REQUIRED_EVIDENCE`: path is mandatory
- `REQUIRED_EVIDENCE_ANY_OF`: at least one path in the group must have producer/evidence satisfaction
- `REQUIRED_EVIDENCE_NONE`: file intentionally contributes no required evidence entries
- `REQUIRED_EVIDENCE_NONE` is invalid if combined with any REQUIRED marker in same file
3. Path constraints (deterministic):
- One path token per REQUIRED marker; multiple tokens only allowed in ANY_OF
- Paths must be repo-root-relative
- File paths only (no directories)
- No globbing
- Trim leading/trailing whitespace in path tokens
- Reject absolute paths
- Normalize `./` and redundant segments
- Reject paths that escape repo root (`..` traversal after normalization)
- Normalize path separators to `/`
- Case-sensitive matching in CI (Linux semantics)
- Deduplicate using normalized path value
- Duplicate normalized declarations are schema violations
4. Marker placement and scope:
- In CI gating phases, marker parsing authority is canonical phase checklist docs only.
- Roadmap markers (if present) are informational and non-gating.
5. Malformed markers and unknown/invalid path formats are explicit schema violations in CI mode.

Acceptance:
- Required evidence extraction remains stable across prose/heading refactors.
- CI fails on malformed/invalid markers and ambiguous NONE usage.

---

### F6) GLOBAL_MANUAL anti-gaming controls

Problem:
- Reclassification to `GLOBAL_MANUAL` can bypass strict gating if not governed.

Plan:
1. Maintain `GLOBAL_MANUAL` allowlist in dedicated file under version control.
2. Each allowlist entry must include source and rationale.
3. Validator report must emit every `GLOBAL_MANUAL` classification with source marker location.
4. In CI mode, classification as `GLOBAL_MANUAL` is allowed only when path exists in allowlist.
5. CI warns/fails (policy-configurable) when allowlist grows without rationale metadata.

Acceptance:
- `GLOBAL_MANUAL` cannot be expanded silently to bypass gating.

---

## 3. Rollout Decisions (Adopted)

### R1) PR status gate timing
- Week 0-2: burn-in mode (status reported, not required).
- After burn-in: make crossref status check mandatory in branch protection.

### R2) Marker rollout sequence
1. Dual parser phase:
- Parse checklist markers + legacy heuristics; report drift deltas.
2. Strict-marker-in-CI phase:
- `--ci` requires valid marker intent in canonical checklist docs; legacy parser remains informational only.
3. Marker-only phase:
- Remove legacy heuristics from CI path.

Exit criteria for phase advancement:
- No unexplained marker/legacy drift for one full sprint.
- CI false-positive rate acceptable to owners.

---

## 4. Implementation Slices (Order)

### Slice A: Shared parser + parity baseline (F1)
- Add `tools/at_parser.py`.
- Refactor both AT tools to consume shared module.
- Add parity tests and fixtures (including trailing-description AT case).
- Add import-lock test to fail if AT/Profile parser logic is duplicated outside shared module.
- Add map equality assertion test (`{at_id: profile}` exact match).

### Slice B: Audit gate hardening (F2 + F3 + F4 + F6)
- Deterministic categorization.
- CI exit semantics including stable exit-code contract.
- Exact-by-default matching + fuzzy opt-in reporting.
- GLOBAL_MANUAL allowlist enforcement + reporting.

### Slice C: Marker grammar + rollout (F5 + R2)
- Add REQUIRED_EVIDENCE / REQUIRED_EVIDENCE_ANY_OF / REQUIRED_EVIDENCE_NONE markers to canonical checklist docs.
- Enable dual parser, then strict marker CI, then marker-only.
- Add drift report schema output with sections:
- `marker_only`
- `legacy_only`
- `intersection`
- `delta_counts`

### Slice D: Branch protection enforcement (R1)
- Promote status check to required after burn-in window.

---

## 5. Verification Plan

Run during iteration:
- `./plans/verify.sh quick`

Run before merge-grade/pass flip:
- `./plans/verify.sh full`

Targeted checks:
1. Shared parser parity:
- `python3 tools/ci/check_contract_profiles.py --contract specs/CONTRACT.md`
- `python3 tools/at_coverage_report.py --contract specs/CONTRACT.md --prd plans/prd.json --output-json /tmp/at_cov.json`
- Assert exact map equality of `{at_id: profile}`.
- CI mode treats parity mismatch as fatal (exit `5`).
2. Trailing-description AT coverage:
- Fixture includes `AT-1070 (...)` style line and asserts detection.
3. Audit CI behavior:
- `--strict --ci` exits `3` on `STORY_OWNED` and `UNKNOWN` gaps.
- `--ci` exits `2` on missing/unreadable inputs.
- `--ci` exits `4` on malformed markers, invalid path format, duplicate-normalized declarations, invalid NONE usage, and root-escape paths.
4. Matching behavior:
- Exact-only mode fails fuzzy-only path mismatches.
- `--fuzzy` reports all fuzzy-resolved matches explicitly.
5. ANY_OF behavior:
- OR group passes if at least one option is satisfied.
- OR group fails in CI when no option is satisfied.
6. Rollout drift check:
- Dual parser phase emits marker-vs-legacy drift report; unexplained drift blocks promotion.

Gate wiring:
- Add dedicated crossref gate script and wire into `./plans/verify.sh full`.
- Wire the same crossref gate in CI workflow on every PR.
- After burn-in, set crossref gate as required branch-protection status.

---

## 6. Definition of Done

The plan is complete when all are true:
1. Both AT tools share one parser module and stay parity-locked by exact map equality.
2. Strict mode is fail-closed (`UNKNOWN` blocks).
3. CI mode enforces stable exit-code contract and non-zero exits on policy/schema/parity failures.
4. Producer matching is exact by default; fuzzy is opt-in and explicitly logged.
5. REQUIRED_EVIDENCE marker grammar (AND/OR/NONE) and normalization rules are implemented and validated.
6. GLOBAL_MANUAL classification is allowlist-governed and fully reported.
7. Rollout completes: dual parser -> strict marker CI -> marker-only.
8. Crossref status check is mandatory after burn-in.
9. `./plans/verify.sh full` is green for final head.

---

## 7. Assumptions and Boundaries

- `PROFILE_RE` remains strict (single profile token, exact casing, no trailing comment syntax) unless contract grammar changes.
- This validator governs crossref/evidence integrity only.
- `mode_reasons` ordering validation remains in contract/runtime validation tools, not in this validator.
- CI gating source-of-truth for required evidence is canonical phase checklist docs, not roadmap prose.

---

## 8. Risk Notes

- Biggest correctness risk: parser drift between canonical and coverage tools.
- Mitigation: shared parser module + exact map parity tests + import-lock test.

- Biggest workflow risk: silent green through ambiguous categorization or permissive matching.
- Mitigation: deterministic category rules + fail-closed CI + exact-default matching.

- Biggest rollout risk: marker migration noise.
- Mitigation: phased rollout with explicit drift reporting and promotion criteria.

---

*End of v11.3 (Fail-Closed Gating Update)*
