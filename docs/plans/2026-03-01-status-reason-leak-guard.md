# Status Reason Leak Guard (PR 2) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a lightweight guardrail that fails CI if `/status` mode/open-permission reason codes are hardcoded as Rust string literals under `crates/**/*.rs`.

**Architecture:** Add one Python checker script that loads the status manifest, builds a forbidden code set (`ModeReasonCode` + `OpenPermissionReasonCode` only), scans Rust files for exact string literal matches, and fails with deterministic `file:line:code` diagnostics. Wire it as an always-on gate in `plans/verify_fork.sh`.

**Tech Stack:** Python 3 (stdlib only), Bash verify harness (`plans/verify_fork.sh`), existing verify gate utilities.

---

## Useful caveat

This is a tripwire, not a proof system.

It is intended to catch accidental leakage:
- copy-paste of `KILL_*` / `REDUCEONLY_*` codes into Rust
- one-off hardcoded literals
- helper code that starts matching `/status` mode/open-permission codes directly

It does not attempt full static proof against deliberate dynamic string reconstruction. That is acceptable for V1.

## Scope and constraints

In scope:
- Add `tools/check_status_reason_string_leaks.py`
- Add verify wiring in `plans/verify_fork.sh`
- Add tests for script behavior and gate wiring
- Keep the PR single-purpose (no status schema, codegen, or unrelated refactors)

Out of scope:
- AST parsing / compiler plugins
- workspace graph analysis
- generated allowlists
- mixed-language scanning
- `RejectReasonCode` parity enforcement (handled by PR 1)

## Contract-aligned decision points (locked)

1. Forbidden set sources:
- `registries.ModeReasonCode.Kill[*].code`
- `registries.ModeReasonCode.ReduceOnly[*].code`
- `registries.OpenPermissionReasonCode.values[*].code`

2. Explicit exclusion:
- `RejectReasonCode` is excluded by design.

3. Scan scope:
- `crates/**/*.rs`
- Policy is explicit in both checker help text and verify wiring: `--scan-root crates`.

4. Match policy:
- Match exact Rust string literal values only.
- Do not fail on comment text or generic substrings.

5. Initial allowlist policy:
- Owner-first default exception for canonical generated status module:
  - `crates/soldier_core/src/status_codes_generated.rs` (when present)
- No additional allowlist entries unless a real, justified Rust exception is found.

## PR 2 review checklist (approval gate)

### Scope
- Adds exactly one new checker script: `tools/check_status_reason_string_leaks.py`
- Wires checker into `plans/verify_fork.sh`
- Does not mix in unrelated refactors, codegen, or status-schema edits

### Manifest handling
- Loads `specs/status/status_reason_registries_manifest.json`
- Reads only:
  - `registries.ModeReasonCode.Kill[*].code`
  - `registries.ModeReasonCode.ReduceOnly[*].code`
  - `registries.OpenPermissionReasonCode.values[*].code`
- Explicitly excludes `registries.RejectReasonCode.values`

### Scan scope
- Scans only `crates/**/*.rs`
- Does not scan the entire repo
- Does not scan Python/TypeScript/fixture files

### Failure behavior
- Exit `0` on success
- Exit `1` on leak found
- Exit `2` on setup/manifest/path errors
- Prints deterministic `file:line:code` failures
- Emits top-level error:
  - `FAIL: /status mode/open-permission reason code literals leaked into Rust source`

### Verify integration
- Added to `plans/verify_fork.sh`
- Runs in both `quick` and `full`
- Hooked after `13) status fixtures` and before heavier later gates
- Uses `run_logged_or_exit` with `SPEC_LINT_TIMEOUT`

### First-version discipline
- No AST parsing
- No Rust compiler integration
- No generated allowlist
- No blanket repo-wide duplicate-string policy
- Owner-first generated-module allow path only; no additional allowlist unless a real existing false positive is proven under `crates/**/*.rs`

## Review blockers (request changes)

Block the PR if any of these occur:
- Checker forbids `RejectReasonCode` values.
- Checker scans outside Rust scope (`crates/**/*.rs`).
- Gate is wired only to full-mode verification.
- Checker silently tolerates malformed/shifted manifest structure.
- Checker uses raw substring matching (for example `if code in line`) instead of literal-aware matching.

Do not block on:
- Exact gate label numbering (`13b` preferred, but naming token itself is not critical).
- Presence of optional `--allow-path`, as long as default behavior is strict and only the owner-first generated-module path is preloaded.

## Task 1: Implement the checker

**Files:**
- Create: `tools/check_status_reason_string_leaks.py`

### Step 1: CLI and setup
- Add args:
  - `--manifest` (default `specs/status/status_reason_registries_manifest.json`)
  - `--scan-root` (default `crates`)
  - optional `--allow-path` (repeatable, repo-relative; owner default path may be injected by verify wiring when present)
- `--allow-path` semantics (strict, fail-closed):
  - path must be repo-relative and normalize under `--scan-root`
  - absolute paths or `..` escapes are rejected with setup error (`exit 2`)
  - non-existent allowlist paths are rejected with setup error (`exit 2`)
- Empty forbidden-set extraction is a setup error (`exit 2`) to fail loud on manifest drift.
- Validate manifest and scan-root existence.
- Exit `2` for setup errors with deterministic stderr diagnostics prefixed as:
  - `FAIL: SETUP ERROR: ...`

### Step 2: Manifest loading
- Parse JSON.
- Read these manifest paths explicitly (no generic coercion/parsing helpers):
  - `ModeReasonCode.Kill`
  - `ModeReasonCode.ReduceOnly`
  - `OpenPermissionReasonCode.values`
- Validate each list entry is an object with a non-empty string `code`.
- On any missing key/wrong type/invalid entry, print details using the same prefix:
  - `FAIL: SETUP ERROR: ...`
  - exit `2`
- Explicitly do not read from `RejectReasonCode`.
- Return sorted unique codes for deterministic output.

### Step 3: Rust literal scanner (simple lexical scan, no AST)
- Walk `crates/**/*.rs`.
- Extract string literals and their starting line numbers:
  - standard strings (`"..."`) with escapes
  - raw strings (`r"..."`, `r#"..."#`, ...)
- Skip comments (`//...`, `/*...*/`) so prose mentions do not trigger.
- Do not use raw line substring matching (`if code in line`) for detection.
- For each literal exactly matching a forbidden code, record hit:
  - `path:line:code`

### Step 4: Failure and success behavior
- On hits:
  - print this summary header to stderr:
    - `FAIL: /status mode/open-permission reason code literals leaked into Rust source`
  - print sorted `file:line:code` entries
  - exit `1`
- On clean scan:
  - print success message
  - exit `0`

## Task 2: Wire into verify

**Files:**
- Modify: `plans/verify_fork.sh`

### Step 1: Add always-on gate
- Place right after status fixture validation block (`13) status fixtures`).
- Keep placement before later heavier gates (vendor/meta/rust workflow phases).
- Add:

```bash
log "13b) status reason leak guard"
status_reason_leak_cmd=(
  "$PYTHON_BIN" tools/check_status_reason_string_leaks.py
  --manifest specs/status/status_reason_registries_manifest.json
  --scan-root crates
)
status_reason_owner_allow_path="crates/soldier_core/src/status_codes_generated.rs"
if [[ -f "$status_reason_owner_allow_path" ]]; then
  status_reason_leak_cmd+=(--allow-path "$status_reason_owner_allow_path")
fi
run_logged_or_exit "status_reason_leak_guard" "$SPEC_LINT_TIMEOUT" \
  "${status_reason_leak_cmd[@]}"
```

### Step 2: Preserve gate behavior
- Ensure gate runs in both quick and full modes.
- Keep deterministic gate naming and artifact behavior via `run_logged_or_exit`.

## Task 3: Add checker tests

**Files:**
- Create: `tools/tests/test_status_reason_string_leaks.py`

### Step 1: Add core test scenarios
- Passes with no forbidden literals.
- Fails when forbidden literal appears in Rust string literal.
- Fails when forbidden literal appears in a Rust raw string literal (`r"..."`, `r#"..."#"`).
- Ignores forbidden code in comments.
- Does not fail when forbidden code appears only as a substring inside a longer string literal.
- Returns `2` when manifest is missing or malformed.
- Returns `2` for invalid `--allow-path` (absolute path, traversal, non-existent path).
- Excludes `RejectReasonCode` values from forbidden set.
- Emits deterministic sorted `file:line:code` output.

### Step 2: Run tests directly
- `python3 -m unittest tools/tests/test_status_reason_string_leaks.py`

## Task 4: Add verify guardrail test update

**Files:**
- Modify: `plans/tests/test_verify_fork_guardrails.sh`

### Step 1: Assert gate wiring exists
- Add line-level token checks for:
  - `log "13b) status reason leak guard"`
  - `run_logged_or_exit "status_reason_leak_guard"`
  - `tools/check_status_reason_string_leaks.py`

## Acceptance criteria

1. Fails if any `ModeReasonCode` or `OpenPermissionReasonCode` string literal appears under `crates/**/*.rs`.
2. Does not include `RejectReasonCode` in forbidden set.
3. Runs in both quick and full verify modes.
4. Prints `file:line:code` on failure.
5. Fails closed (`exit 2`) if manifest shape is missing/invalid/unexpected.
6. Starts with owner-first generated-module allow path only; no additional allowlist unless the repo reveals a real Rust exception.
7. Lands as a single-purpose guardrail PR.

## Verification commands

```bash
python3 tools/check_status_reason_string_leaks.py \
  --manifest specs/status/status_reason_registries_manifest.json \
  --scan-root crates

python3 -m unittest tools/tests/test_status_reason_string_leaks.py

./plans/verify.sh quick
```

Negative smoke-test evidence (required in PR body):
1. Temporarily add `"KILL_WATCHDOG_HEARTBEAT_STALE"` to any Rust file under `crates/`.
2. Run checker and confirm it fails with `FAIL: /status mode/open-permission reason code literals leaked into Rust source`.
3. Revert temporary change.
4. Rerun `./plans/verify.sh quick` and confirm baseline passes.

Before merge:

```bash
./plans/verify.sh full
```

## Assumptions

- Python 3 is available in verify environments.
- Manifest key layout remains compatible with the documented registry shape.
- V1 enforcement prioritizes accidental-leak prevention over exhaustive static guarantees.
