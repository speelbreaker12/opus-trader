# ENTRYPOINTS.md — Repository Entry Points

Generated: 2026-02-08

---

## 1. CI Entrypoints

### `.github/workflows/ci.yml`
**Triggers:** `pull_request`, `push: [main]`, `schedule (daily 01:00 UTC = 19:00 America/Managua)`

**Call Chain:**
```
ci.yml
├── bash plans/ssot_lint.sh                    # SSOT enforcement
├── python tools/ci/check_contract_profiles.py  # Profile tag check
├── python scripts/check_csp_trace.py          # CSP trace validation
├── python scripts/generate_impact_report.py   # Impact report
└── ./plans/verify.sh full                     # Wrapper (execs verify_fork.sh)
    └── ./plans/verify_fork.sh                 # Canonical verification
        ├── preflight (plans/preflight.sh)
        ├── contract_coverage_matrix (plans/contract_coverage_matrix.py)
        ├── spec integrity (9 validators, parallel)
        │   ├── check_contract_crossrefs.py
        │   ├── check_arch_flows.py
        │   ├── check_state_machines.py
        │   ├── check_global_invariants.py
        │   ├── check_time_freshness.py
        │   ├── check_crash_matrix.py
        │   ├── check_crash_replay_idempotency.py
        │   ├── check_reconciliation_matrix.py
        │   └── check_csp_trace.py
        ├── status validation (fixtures, parallel)
        ├── endpoint gate (warn-default)
        ├── vendor docs lint
        ├── stack gates (rust/python/node by mode)
        ├── optional: integration smoke, e2e
        └── workflow acceptance: SKIPPED (fork contract)
```

---

## 2. Human CLI Entrypoints

### `./ralph [max_iters]`
**Purpose:** Run the Ralph iteration loop
**Canonical:** `plans/ralph.sh`

```
ralph (root)
└── exec ./plans/ralph.sh "$@"
    └── (full orchestrator logic)
```

### `./verify.sh [quick|full|promotion]`
**Purpose:** Run verification gates
**Canonical:** `plans/verify.sh` (wrapper) → `plans/verify_fork.sh` (implementation)

```
verify.sh (root)
└── exec "$ROOT/plans/verify.sh" "$@"
    └── exec "$ROOT/plans/verify_fork.sh" "$@"
```

### `./plans/verify_day.sh [args]`
**Purpose:** Daytime quick verify wrapper
**Canonical:** `plans/verify_day.sh`

```
verify_day.sh
└── exec ./plans/verify.sh quick "$@"
```

### `./plans/ralph_day.sh [max_iters]`
**Purpose:** Daytime Ralph loop (quick verify, no pass flips)
**Canonical:** `plans/ralph_day.sh`

```
ralph_day.sh
└── exec ./plans/ralph.sh with RPH_VERIFY_MODE=quick, RPH_FINAL_VERIFY_MODE=quick, RPH_FORBID_MARK_PASS=1
```

### `./sync`
**Purpose:** Pull latest from main
**Self-contained:** git fetch + pull --ff-only

---

## 3. Ambiguous Duplicates (RESOLVED)

### verify.sh Duplication

| Path | Type | Verdict |
|------|------|---------|
| `verify.sh` (root) | **Redirect stub** | CANONICAL ENTRY (delegates) |
| `plans/verify.sh` | **Implementation** | CANONICAL IMPLEMENTATION |

**Evidence:**
- Root `verify.sh` line 5: `exec "$ROOT/plans/verify.sh" "$@"`
- `AGENTS.md` line 82-84: "There is also a `./verify.sh` at repo root. **DO NOT edit or reference it**... All workflow gating must target **`plans/verify.sh`**."

**Decision:** Both files are correct. Root is convenience entry, `plans/` is canonical.

### CONTRACT.md Duplication

| Path | Type | Verdict |
|------|------|---------|
| `CONTRACT.md` (root) | **DELETED** | Correctly absent |
| `specs/CONTRACT.md` | **Implementation** | CANONICAL |

**Evidence:**
- `ssot_lint.sh` line 44: `[[ -f "CONTRACT.md" ]] && fail "Root CONTRACT.md is forbidden"`
- `ssot_lint.sh` line 69-70: `CONTRACT.md must exist only at specs/CONTRACT.md`
- `specs/CONTRACT.md` line 1: `This is the canonical contract path. Do not edit other copies.`

**Decision:** Single source of truth correctly at `specs/CONTRACT.md`.

### IMPLEMENTATION_PLAN.md Duplication

| Path | Type | Verdict |
|------|------|---------|
| `IMPLEMENTATION_PLAN.md` (root) | **MISSING** | Should be redirect stub |
| `specs/IMPLEMENTATION_PLAN.md` | **Implementation** | CANONICAL |

**Evidence:**
- `ssot_lint.sh` line 42: `check_stub "IMPLEMENTATION_PLAN.md" "specs/IMPLEMENTATION_PLAN.md"`

**Decision:** Root file MISSING. Should create redirect stub.

---

## 4. Entry Point Summary Table

| Entry Point | Type | Canonical Path | CI? | Human? |
|-------------|------|----------------|-----|--------|
| `./ralph` | Orchestrator | `plans/ralph.sh` | No | Yes |
| `./verify.sh` | Verification | `plans/verify.sh` | Yes | Yes |
| `./sync` | Git sync | Self-contained | No | Yes |
| `./plans/init.sh` | Initialization | Self-contained | No | Yes |
| `.github/workflows/ci.yml` | CI Pipeline | N/A | Yes | No |

---

## 5. Scripts Never Called Directly

These scripts are **library scripts** called by other scripts, not entry points:

- `plans/build_markdown_digest.sh` — called by `build_contract_digest.sh`, `build_plan_digest.sh`
- `plans/prd_lint.sh` — called by `prd_gate.sh`
- `plans/contract_review_validate.sh` — called by `contract_check.sh`, `ralph.sh`
- `scripts/contract_kernel_lib.py` — imported by `check_contract_kernel.py`, `build_contract_kernel.py`
- `scripts/utils/*.py` — imported by other scripts

---

## 6. Dead Entry Points (no callers found)

| Path | Refs Found | Verdict |
|------|------------|---------|
| `plans/cut_prd.sh` | 0 | QUARANTINE |
| `scripts/suggest_downstream_patches.py` | 0 | QUARANTINE |
| `scripts/verify_local.sh` | 0 | QUARANTINE |
| `prompts/architect_advisor.md` | 0 | QUARANTINE |
| `prompts/contact_arbiter.md` | 0 | QUARANTINE |
| `prompts/workflow_121.md` | 0 | QUARANTINE |
