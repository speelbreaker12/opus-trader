# CI Enforcement Runbook

This runbook applies CI governance hardening for `speelbreaker12/opus-trader` fail-closed.

## Preconditions

- `gh` authenticated with repo admin permission.
- Local branch includes:
  - `.github/CODEOWNERS`
  - `.github/workflows/ci.yml` with enabled `prd-story-gate`

## 1) Preflight + Snapshot

```bash
bash scripts/ci_enforcement/preflight_snapshot.sh --repo speelbreaker12/opus-trader --branch main
```

Expected artifacts:
- `artifacts/ci_enforcement_backups/protection-raw-<timestamp>.json`
- `artifacts/ci_enforcement_backups/protection-restore.json`

## 2) Apply Branch-Protection Updates

```bash
bash scripts/ci_enforcement/apply_branch_protection.sh --repo speelbreaker12/opus-trader --branch main
```

## 3) Verify

```bash
bash scripts/ci_enforcement/verify_branch_protection.sh --repo speelbreaker12/opus-trader --branch main
```

## Rollback

Use the snapshot payload generated in step 1:

```bash
gh api repos/speelbreaker12/opus-trader/branches/main/protection \
  --method PUT \
  --input artifacts/ci_enforcement_backups/protection-restore.json
```

If CODEOWNERS must be removed as part of rollback:

```bash
git rm .github/CODEOWNERS
```
