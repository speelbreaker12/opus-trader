# Fix / Patch Plan

## Objective
Solidify the optional parts of the workflow to ensure agent prompts are always valid and artifacts are predictable.

## 1. Update `plans/init.sh`
Ensure optional documentation files exist so the agent doesn't have to guess or fail when appending.

**Patch**:
```bash
# Append to plans/init.sh

# --- Ensure optional logs exist
if [[ ! -f "plans/ideas.md" ]]; then
  echo "# Ideas & Deferred Items" > "plans/ideas.md"
  echo "[init] created plans/ideas.md"
fi

if [[ ! -f "plans/pause.md" ]]; then
  echo "# Pause / Handoff Notes" > "plans/pause.md"
  echo "[init] created plans/pause.md"
fi
```

## 2. Verify `plans/contract_check.sh` Permissions
Ensure the contract check scripts are executable (they should be, but `init.sh` only optionally checks `CONTRACT_CHECK_SH`).

**Patch**:
```bash
# In plans/init.sh (already present but verify it covers review_validate)

if [[ -f "plans/contract_review_validate.sh" ]]; then
  chmod +x "plans/contract_review_validate.sh" || true
fi
```

## 3. Test `plans/verify.sh` in CI mode locally
Run `CI=1 ./plans/verify.sh` to ensure it behaves as expected in a CI-like environment (fail-closed on missing tools).

## 4. Acceptance Test
Run `./plans/workflow_acceptance.sh` to confirm the harness is behaving correctly with the current configuration.

## 5. Directory Structure
Ensure `docs/codebase` is preserved (gitkeeps) if it's empty, though currently it seems populated.
