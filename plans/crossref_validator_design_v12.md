# Cross-Reference Validator Design v12
## Hard CI Gate + Short Rollout (Safety/Traceability Constraint)

**Version:** 12.2
**Status:** Implemented spec
**Supersedes:** `plans/crossref_validator_design_v11.md`

---

## 1. Decision

The repo constraint is safety + traceability. Crossref validation is enforced with fail-closed gates, with rollout staged by strict sentinel:

- Always gated in CI/report mode (`--ci`) for parser/parity/schema safety.
- Strict evidence gaps (`--strict`) are enabled when `plans/crossref_ci_strict` is present.
- Canonical evidence source for CI gating is checklist markers (`docs/PHASE0_CHECKLIST_BLOCK.md`, `docs/PHASE1_CHECKLIST_BLOCK.md`).
- Roadmap remains informational in CI mode.

---

## 2. Non-Negotiable Requirements

### F1) Shared AT parser and trailing-description AT support

- Shared parser module: `tools/at_parser.py`
- Canonical regexes:
  - `AT_RE = re.compile(r"^\s*(AT-\d+)\b")`
  - `PROFILE_RE = re.compile(r"^Profile:\s+(CSP|GOP|FULL)\s*$")`
- `check_contract_profiles.py` and `at_coverage_report.py` both import the shared parser.

### F1.5) Exact set parity on `(AT_ID -> Profile)`

- Both tools emit map artifacts.
- `tools/ci/check_contract_profile_map_parity.py` enforces exact key/value map equality.
- Totals-only parity is forbidden.

### F1.6) Profile completeness gate

- Missing profile / conflicting profile / invalid profile inheritance is fail-closed.
- Exit semantics:
  - `check_contract_profiles.py`: `5` on profile incompleteness.
  - `at_coverage_report.py`: `5` on profile incompleteness.
  - Parity checker: `6` on map mismatch.

### F2/F3) CI semantics and exit codes

`tools/roadmap_evidence_audit.py` exit contract:

- `0` PASS
- `2` TOOL_ERROR (missing inputs, parse/runtime failure, no marker intent in CI)
- `3` CI_FAIL_UNKNOWN_GAPS
- `4` CI_FAIL_STRICT_GAPS (`--ci --strict`)
- `7` CI_FAIL_MARKER_SCHEMA

Crossref wrapper gate (`plans/crossref_gate.sh`) propagates underlying exit codes.

### F4) Exact matching default, fuzzy opt-in

- Default matching is exact.
- Fuzzy matching requires `--fuzzy`.
- Fuzzy resolutions are emitted in report output.

### F5) Deterministic marker grammar

Supported markers:

- `<!-- REQUIRED_EVIDENCE: <relative-path> -->`
- `<!-- REQUIRED_EVIDENCE_ANY_OF: <relative-path> | <relative-path> -->`
- `<!-- REQUIRED_EVIDENCE_NONE -->`

Schema rules:

- NONE cannot be mixed with REQUIRED/ANY_OF in the same file.
- Multiple NONE markers in one file are invalid.
- Duplicate normalized declarations are invalid.
- ANY_OF duplicate normalized options are invalid.
- Paths must be repo-relative under `evidence/`; absolute paths and root-escape are forbidden.
- Directory-style and glob paths are invalid.

### F6) GLOBAL_MANUAL governance

- Allowlist file: `plans/global_manual_allowlist.json`.
- Required fields per entry:
  - `evidence_path`
  - `justification`
  - `owning_story_id`
- In CI mode:
  - stale allowlist entries are schema failures,
  - missing allowlist evidence paths are schema failures.

---

## 3. Rollout Controls

- Burn-in gate mode: run `plans/crossref_gate.sh --ci` in CI.
- Strict promotion: add `plans/crossref_ci_strict` (or set `CROSSREF_STRICT=1`) to enforce `--strict`.
- Promotion criteria are machine-checkable via `plans/crossref_burnin_check.sh`.

---

## 4. Wiring and Artifacts

- Canonical wrapper: `plans/crossref_gate.sh`
- Invariants validator: `plans/validate_crossref_invariants.py`
- Invariant spec + schema:
  - `plans/crossref_execution_invariants.yaml`
  - `plans/schemas/crossref_execution_invariants.schema.json`
- Verify integration:
  - `plans/verify_fork.sh` runs:
    - `contract_profiles`
    - `at_coverage_report`
    - `at_profile_parity`
    - `crossref_invariants`
    - `crossref_gate` (full mode)
- Run-scoped artifact root:
  - `artifacts/verify/<run_id>/crossref/*`

---

## 5. Definition of Done

Complete when all hold:

1. Shared parser + exact map parity are enforced in verify and CI.
2. Profile completeness failures are fatal.
3. Marker grammar is deterministic and fail-closed.
4. Canonical checklist docs contain required evidence markers.
5. CI runs crossref gate in burn-in mode and can promote to strict via sentinel.
6. Workflow harness self-proof tests cover new scripts/files.
7. `./plans/verify.sh full` is green.
