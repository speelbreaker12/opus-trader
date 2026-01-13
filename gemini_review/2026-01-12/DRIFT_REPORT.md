# Drift Report

## Summary
The implementation (`plans/ralph.sh`) is largely aligned with the contract (`specs/WORKFLOW_CONTRACT.md`). However, several key fail-closed gates defined in the contract lack explicit acceptance tests, meaning regression could go unnoticed.

## Missing Verification (Gaps)

### 1. Cheating Detection ([WF-2.5])
- **Contract**: "No cheating. Do not delete/disable tests..."
- **Implementation**: `ralph.sh` has `detect_cheating` function.
- **Verification**: No test in `workflow_acceptance.sh` triggers this logic.

### 2. Human Decision Stop ([WF-5.4])
- **Contract**: "If selected story has needs_human_decision=true: Ralph MUST stop immediately"
- **Implementation**: `ralph.sh` checks `needs_human_decision` and blocks.
- **Verification**: No test verifies this behavior explicitly.

### 3. Self-Heal ([WF-5.7])
- **Contract**: "If RPH_SELF_HEAL=1... Ralph SHOULD reset hard..."
- **Implementation**: `ralph.sh` has logic for `revert_to_last_good`.
- **Verification**: All current acceptance tests run with `RPH_SELF_HEAL=0`.

### 4. Anti-spin / Max Iters ([WF-5.9])
- **Contract**: "Ralph MUST support RPH_MAX_ITERS... and MUST stop... when exceeded."
- **Implementation**: `ralph.sh` loop uses `MAX_ITERS`.
- **Verification**: No test checks the loop termination and artifact generation.

## Recommendations
Update `plans/workflow_acceptance.sh` to include 4 new tests covering these gaps.
