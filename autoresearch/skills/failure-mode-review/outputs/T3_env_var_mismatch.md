## Failure Mode Review: run_slice_audit.sh / audit.py

### Triage

Cross-script env var passing (§1 Interface Crossings), external inputs (§3 What-If), §6 Concrete Walkthrough.

### Findings

#### High

- **AUDIT_SLICE_ID set but SLICE_ID read — slice_id always empty** — `run_slice_audit.sh:8` → `audit.py:22`
  - Failure scenario: Shell sets `AUDIT_SLICE_ID="$slice"` but Python reads `os.environ.get("SLICE_ID", "")`. `SLICE_ID` is never set in the environment, so `slice_id` is always `""`.
  - Impact: Every audit runs with an empty slice ID. The `print(f"Auditing {slice_id}")` line outputs `"Auditing "`. Any slice-specific logic downstream receives an empty string silently.
  - Fix: Change shell to `SLICE_ID="$slice"`, OR change `audit.py` to read `AUDIT_SLICE_ID`.

#### High

- **AUDIT_CONFIG set but AUDIT_CFG read — config path always "config.json"** — `run_slice_audit.sh:8` → `audit.py:23`
  - Failure scenario: Shell sets `AUDIT_CONFIG="$CONFIG"` but Python reads `os.environ.get("AUDIT_CFG", "config.json")`. `AUDIT_CFG` is never set, so `config_path` always falls back to `"config.json"`.
  - Impact: The `CONFIG` variable from the shell loop (which could point to any config file) is completely ignored. Python always opens `"config.json"` from CWD regardless of which config the shell meant to use. Config mismatch causes silent wrong-config auditing.
  - Fix: Change shell to `AUDIT_CFG="$CONFIG"`, OR change `audit.py` to read `AUDIT_CONFIG`.

### Interface Crossings Verified

- [ ] `run_slice_audit.sh` → `audit.py`: `AUDIT_SLICE_ID` set, `SLICE_ID` read — **MISMATCH** ✗
- [ ] `run_slice_audit.sh` → `audit.py`: `AUDIT_CONFIG` set, `AUDIT_CFG` read — **MISMATCH** ✗

### Concrete Value Walkthrough

**Scenario: `slice="S1-001"`, `CONFIG="plans/prd_slices.json"`**

Shell executes (run_slice_audit.sh line 8):
```
AUDIT_SLICE_ID="S1-001" AUDIT_CONFIG="plans/prd_slices.json" python3 python/tools/audit.py
```

Python receives (audit.py lines 22-23):
```python
slice_id = os.environ.get("SLICE_ID", "")          # → "" (AUDIT_SLICE_ID ignored)
config_path = os.environ.get("AUDIT_CFG", "config.json")  # → "config.json" (AUDIT_CONFIG ignored)
```

Output: `Auditing ` (empty), opens wrong config file.

Both variables are silently missing. No error raised. Audit produces output for wrong inputs.

### Downstream Errors Traced

- `slice_id = ""` → every slice run produces identical output → results overwrite each other
- `config_path = "config.json"` → wrong config audited → false pass/fail results

### Next Step

Both mismatches are High. Fix env var names before any further testing or deployment of this diff.
