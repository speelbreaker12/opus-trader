# Phase 0 CI Links / Build IDs

Phase 0 is mostly MANUAL + recorded artifacts, with deterministic verify gates.

## CI runs
- Local quick verify: PASS (`artifacts/verify/20260209_174607`)
- Local full verify (dirty tree): PASS (`artifacts/verify/20260209_174800`)
- Local full verify (clean detached worktree): PASS (commit `4dc48a2`, log: `/tmp/verify_clean_4dc48a2.log`)
- Local quick verify (machine-policy + health behavior gates): PASS (`artifacts/verify/20260209_190352`)
- Local full verify (machine-policy + health behavior gates): PASS (`artifacts/verify/20260209_190517`)
- PR CI full verify (PR #9): PASS (https://github.com/speelbreaker12/opus-trader/actions/runs/21845864348/job/63041419096)

## Build IDs / hashes used during Phase 0 proof
- build_id: local-4dc48a2
- commit: 4dc48a2
- notes: launch policy seams hardened; machine-policy loader + executable health behavior checks added; evidence refreshed

## MANUAL Gates (Evidence-Based)

| Gate | Evidence | Verified |
|------|----------|----------|
| P0-A | `docs/launch_policy.md` + snapshot | YES |
| P0-B | `docs/env_matrix.md` + snapshot | YES |
| P0-C | `docs/keys_and_secrets.md` + JSON probe | YES |
| P0-D | `docs/break_glass_runbook.md` + drill | YES |
| P0-E | `docs/health_endpoint.md` + AUTO tests | YES |
