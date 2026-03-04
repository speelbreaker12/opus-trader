import sys

filepath = ".worktrees/pr1-task1-drift-closure/plans/verify_fork.sh"
with open(filepath, "r") as f:
    content = f.read()

old_str = """if [[ -x "$ROOT/plans/check_contract_change_ledger.sh" ]]; then
  log "02a) contract change ledger"
  run_logged_or_exit "contract_change_ledger" "$CONTRACT_KERNEL_TIMEOUT" \\
    "$ROOT/plans/check_contract_change_ledger.sh" --base-ref "$VERIFY_BASE_REF" --contract specs/CONTRACT.md
else
  warn "contract_change_ledger skipped (missing plans/check_contract_change_ledger.sh)"
fi"""

new_str = """if [[ ! -x "$ROOT/plans/check_contract_change_ledger.sh" ]]; then
  fail "contract_change_ledger gate missing or not executable: $ROOT/plans/check_contract_change_ledger.sh"
fi

log "02a) contract change ledger"
run_logged_or_exit "contract_change_ledger" "$CONTRACT_KERNEL_TIMEOUT" \\
  "$ROOT/plans/check_contract_change_ledger.sh" --base-ref "$VERIFY_BASE_REF" --contract specs/CONTRACT.md"""

if old_str in content:
    with open(filepath, "w") as f:
        f.write(content.replace(old_str, new_str))
    print("verify_fork.sh updated")
else:
    print("old_str not found in verify_fork.sh")
