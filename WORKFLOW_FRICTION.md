# WORKFLOW_FRICTION

Purpose
- Rolling list of top workflow constraints.
- Each recurring item must name an elevation action.

How to use
- Keep Active list to top 3 constraints.
- Rank by TOC impact (1 = highest).
- Each entry includes Constraint, Exploit, Elevate, and Next action.

## Active (Top 3)
| Rank | Constraint | Exploit (what we do now) | Elevate (permanent fix) | Next action | Owner | Proof target |
|---|---|---|---|---|---|---|
| 1 | Full verify runtime slows story completion | Keep changes scoped; run quick early and often; run one full verify per story-ready branch | Add deterministic per-gate timing trend report from verify artifacts | Add a tiny script to summarize `artifacts/verify/*/*.time` deltas | maintainer | timing trend report generated in CI artifact |
| 2 | Drift risk between docs and verify behavior | Treat `plans/verify_fork.sh` as SSOT; update docs in same PR as gate changes | Add doc-vs-gate check for key semantics (quick/full gate membership) | Add a script in `plans/` that asserts documented quick/full gates match `verify_fork.sh` | maintainer | script fails on intentional mismatch |
| 3 | Dirty-tree local verify ambiguity | Prefer CI clean-checkout full verify when local tree is dirty | Add helper that prints dirty-file summary + recommended options before verify | Add a small pre-verify diagnostic script and wire it into docs/workflow | maintainer | diagnostics shown before verify when dirty |

## Resolved
| Date resolved | Constraint | Resolution | Evidence |
|---|---|---|---|
| 2026-02-08 | Legacy Ralph/workflow acceptance ambiguity | Removed legacy scripts from `plans/`; CI and docs now point to verify-only flow | `plans/preflight.sh`, `.github/workflows/ci.yml`, `README.md` |
