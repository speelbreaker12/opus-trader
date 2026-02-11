# LIVE Key Cutover Drill Record (Phase 0)

- date_utc: 2026-02-11T21:56:00Z
- env: LIVE
- operator: phase0_operator
- witness: safety_witness
- status: BLOCKED

## Objective

Execute one full LIVE key cutover drill in maintenance conditions:
1. create new LIVE trade key (withdraw disabled),
2. deploy/swap runtime secret reference to new key,
3. verify identity + scope probe against new key,
4. revoke old LIVE trade key,
5. verify revoked key cannot trade.

## Preconditions Check (this workspace)

Expected from `docs/env_matrix.md` and `docs/keys_and_secrets.md`:
- LIVE secret source: Vault (prod IAM only)
- Exchange operator/admin access for key create/revoke

Observed at execution time:
- No Vault/prod IAM environment bindings detected in this shell session.
- No exchange key-management automation command exists in `stoic-cli` (validation-only `keys-check` is available).

## Blocker

The full LIVE cutover cannot be executed from this workspace/session because required production authority is unavailable (Vault + exchange admin path).

## Commands Executed (validation path)

```bash
./stoic-cli keys-check --probe evidence/phase0/keys/key_scope_probe.json --env LIVE --format json > evidence/phase0/keys/rotation_check_live.json
```

Result:
- `rotation_check_live.json` reports `ok: true` for current LIVE probe validation.

## Required Steps To Complete In Maintenance Window

1. Create `key_live_trade_002` on exchange with `read_account, trade`; confirm `withdraw=false`, `transfer=false`.
2. Store new key in Vault at production path; keep old key active during overlap.
3. Roll runtime to use new key reference and restart.
4. Regenerate and archive a post-swap probe showing new key id redacted (`key_live_trade_002` lineage).
5. Run `./stoic-cli keys-check --probe <post_swap_probe> --env LIVE --format json` and archive output.
6. Revoke old key (`key_live_trade_001`) on exchange.
7. Capture explicit revoked-key trade rejection proof in probe results.
8. Remove old secret from Vault and close maintenance window.

## Completion Criteria (for status=PASSED)

- Post-swap LIVE probe shows expected scope and identity on new key.
- Revoked old key proof is present and explicit (trade rejected).
- Vault secret swap + old-secret removal are both recorded.
- Evidence paths are linked in `evidence/phase0/README.md`.
