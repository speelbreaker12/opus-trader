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
| 2 | Reconciliation process docs can regrow beyond operator-friendly size | Keep process guidance concentrated in canonical docs and link to references instead of duplicating sections | Enforce a deterministic process-doc budget gate (`plans/recon_doc_budget.sh`) in verify with controlled local-only override governance | Keep canonical recon docs under 650 lines total; if temporary override is required, log owner/rationale/expiry in `plans/progress.txt` before running verify | maintainer | `recon_doc_budget` gate artifact under `artifacts/verify/<run_id>/` |
| 3 | Dirty-tree local verify ambiguity | Prefer CI clean-checkout full verify when local tree is dirty | Add helper that prints dirty-file summary + recommended options before verify | Add a small pre-verify diagnostic script and wire it into docs/workflow | maintainer | diagnostics shown before verify when dirty |

## Resolved
| Date resolved | Constraint | Resolution | Evidence |
|---|---|---|---|
| 2026-02-08 | Legacy Ralph/workflow acceptance ambiguity | Removed legacy scripts from `plans/`; CI and docs now point to verify-only flow | `plans/preflight.sh`, `.github/workflows/ci.yml`, `README.md` |
