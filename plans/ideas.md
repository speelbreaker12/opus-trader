# Deferred Ideas (append-only)

- Use this log for non-PRD ideas, follow-ups, or enhancements.
- Keep entries short and timestamped.
- Do not remove items; mark resolved by appending a note.

## Entries

- [YYYY-MM-DD] TBD
- [2026-02-09] Backfill runtime implementation ticket: enforce startup identity probe fail-closed account/subaccount matching against `docs/env_matrix.md` for every environment with private credentials (mismatch => no dispatch).
- [2026-02-06] Drafted deferred proposal for CI lint of required PR template sections in `plans/proposals/2026-02-06_pr-template-ci-lint.md`.
- [2026-02-05] Drafted proposal for a Ralph bootstrap mode (missing workspace baseline) in `plans/proposals/2026-02-05_bootstrap_ralph_baseline.md`.
- [2026-01-13] Consider an unattended profile that sets approval_mode=never; requires explicit policy decision vs AGENTS.md "Never use skip-permissions" plus extra guardrails.
- [2026-02-24] Add a status policy-loader fallback strategy for dashboard publisher: keep Python publisher and Convex publish logic reading thresholds from
  canonical contract artifacts in order `config/csp_thresholds.json` (if present), otherwise
  `crates/soldier_infra/src/config.rs` defaults, and finally `plans/prd.json` policy anchors; fail closed if all three are unavailable.
  Concrete mapping: mm_util thresholds map to `mm_util_reject_opens`, `mm_util_reduceonly`, `mm_util_kill`;
  disk thresholds map to `disk_pause_archives_pct`, `disk_degraded_pct`, `disk_kill_pct`;
  WAL/network thresholds map to `parquet_queue_trip_pct`, `parquet_queue_clear_pct`, `rate_limit_kill_min_10028`.
