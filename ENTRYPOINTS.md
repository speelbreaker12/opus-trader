# ENTRYPOINTS

Generated: 2026-02-08

## Canonical Verification Path

```text
./plans/verify.sh [quick|full]
  -> ./plans/verify_fork.sh [quick|full]
     -> artifacts/verify/<run_id>/*
```

Root `./verify.sh` is a thin wrapper to `./plans/verify.sh` and exists for compatibility.

## CI Entrypoint

`/.github/workflows/ci.yml`:

1. Setup toolchains.
2. Run `./plans/verify.sh full`.
3. Upload verify log artifact.

## Human Workflow Entrypoints

- `./plans/verify.sh quick`
- `./plans/verify.sh full`
- `./plans/workflow_verify.sh`
- `./plans/prd_set_pass.sh`
- `./plans/codex_review_let_pass.sh`
- `./sync`
