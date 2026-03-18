# SKILL: /verify (Run Verification and Explain Failures)

Purpose
- Run `plans/verify.sh` and interpret failures against `specs/CONTRACT.md` and `specs/WORKFLOW_CONTRACT.md`.

When to use
- Before flipping `passes=true`.
- After changing `plans/*`, `specs/*`, or validators.
- When CI verify fails.

## Workflow

### 1) Run verification
```bash
# Quick iteration gate
./plans/verify.sh quick

# Full completion gate
./plans/verify.sh full
```

### 2) Interpret result
- Exit `0`: all executed gates passed.
- Exit non-zero: at least one gate failed; inspect `artifacts/verify/<run_id>/FAILED_GATE` and matching `<gate>.log`.

### 3) Common failure classes
- Contract/spec validator failures (`contract_crossrefs`, `arch_flows`, `state_machines`, etc.).
- Language gate failures (`rust_*`, `python_*`, `node_*`).
- Preflight fail-closed checks.

### 4) Deep-dive commands
```bash
python3 scripts/check_contract_crossrefs.py --contract specs/CONTRACT.md --strict --check-at --include-bare-section-refs
python3 scripts/check_arch_flows.py --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml --strict
python3 scripts/check_state_machines.py --dir specs/state_machines --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml --invariants specs/invariants/GLOBAL_INVARIANTS.md --strict
python3 scripts/check_global_invariants.py --file specs/invariants/GLOBAL_INVARIANTS.md --contract specs/CONTRACT.md
```

## Output
- Verification result.
- Failed gate(s) + relevant contract/workflow refs.
- Minimal fix path + re-verify command.
