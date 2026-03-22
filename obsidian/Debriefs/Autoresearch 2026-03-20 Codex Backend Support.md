---
project: "[[Autoresearch]]"
date: "2026-03-20"
---

## Commits
- `pending`
- `a92bced4`
- `52cf1b15`

## 0) What shipped
- Feature/behavior: Added tracked repo support for Codex-backed contract autoresearch via `harness.sh contract ... --backend codex`, hardened the wrapper with a persistent isolated Codex home plus transient retry/backoff, reran live contract batches on Codex `gpt-5.4` with `xhigh`, then manually reviewed the five hardened Phase 2 proposal packages and rendered accepted-only patch artifacts.
- Value (what problem it solves): Removes the fragile `/tmp`-only wrapper dependency, reduces wasted live runs from transient Codex transport failures, and turns the new Codex-backed Phase 2 slice outputs into actionable accepted/pending/rejected contract patch sets.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms):
  - Large inline contract prompts caused Codex websocket idle reconnects and dead-sleep runs with no `last.txt`.
  - The first real Phase 1 batch stalled on `trading_mode_computation` for >20 minutes with no new artifacts.
  - Default `~/.codex` state polluted one-shot JSON requests with unrelated skill/tool behavior.
- Time/token drain it caused:
  - Burned multiple live batch attempts and long waits without outputs, shifting effort from contract analysis into transport debugging.
- Workaround I used this session (exploit):
  - Moved Codex to an isolated persistent home, rewrote contract prompts into short file-reading prompts, and retried transient `500`/`503`/websocket-class failures before surfacing them.
- Next-agent default behavior (subordinate):
  - For contract autoresearch on Codex, use `harness.sh contract ... --backend codex --model gpt-5.4` instead of ad-hoc `CLAUDE_BIN=/tmp/...`.
- Permanent fix proposal (elevate):
  - Keep the tracked wrapper as the canonical Codex backend for contract phase runs, with persistent state and retry controls documented as part of the lane contract.
- Smallest increment:
  - `autoresearch/contract/codex_wrapper.py`, explicit `--backend codex` harness wiring, one prompt-rewrite regression, one persistent-home/retry regression, and one live per-section Phase 2 batch through the tracked path.
- Validation (proof it got better):
  - New regressions `test_contract_phase2_run_supports_codex_backend_with_short_prompt_wrapper` and `test_contract_phase2_run_retries_transient_codex_failure_with_persistent_home` pass.
  - `python3 -m unittest autoresearch.tests.test_contract_phase_runs` passed (`19` tests).
  - `python3 -m unittest autoresearch.tests.test_contract_harness_cli` passed.
  - `bash -n autoresearch/skills/harness.sh` passed.
  - Live runs passed: `phase1-mar20-20260320_191211-5ccf6c48` (`12/12`, `1.000`), tracked-backend `phase1-mar20codex-20260320_195735-903f0acd` (`12/12`, `1.000`), `phase2-mar20-20260320_193507-66196f79` (`8/8`, `1.000`), tracked-backend smoke `phase2-mar20codex-20260320_194341-e183cb6b` (`8/8`, `1.000`), and hardened per-section Phase 2 slices: OPL `phase2-mar20codexhardened-opl-20260320_210643-d8538cc4` (`2` proposals), LG `phase2-mar20codexhardened-lg-20260320_211226-33896e77` (`2` proposals), EG `phase2-mar20codexhardened-eg-20260320_211637-c80be6bb` (`3` proposals), TMC `phase2-mar20codexhardened-tmc-20260320_212316-3d06f6e7` (`3` proposals), and EC `phase2-mar20codexhardened-ec-20260320_212954-8cae5620` (`4` proposals), each with `checks=8/8` and `score=1.000`.
  - Manual review is complete for those five hardened runs: `6` accepted, `7` pending scope, `1` rejected, with accepted-only patch artifacts rendered for every run.
  - PR #224 is open against `main`, and the tracked backend now has both test coverage and live evidence beyond the original smoke run.

## 2) Best follow-up
- Single best next step: Apply or further consolidate the accepted-only Phase 2 patches (`LG`, `EG`, `TMC`, `EC`) into the next contract patch batch, while separately deciding whether the `pending_scope_review` items should be rewritten or dropped.
- 1-3 upgrades worth considering:
  - Add an explicit Codex subprocess timeout so silent hangs can recycle through the same retry path as transient `500`/`503` failures.
  - Add a helper command for the per-section Phase 2 live slices so agents do not need to remember five separate `eval_*.json` entrypoints.
  - Consider an environment default for contract lanes that standardizes the Codex backend without repeating `--backend codex`.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- If contract autoresearch uses Codex, invoke it via `harness.sh contract ... --backend codex`; do not depend on one-off `/tmp` wrappers.
- Codex contract prompts must stay in short file-reading form, not inline fixture dumps; enforce with `autoresearch/tests/test_contract_phase_runs.py`.
- If a Codex contract run depends on isolated state, keep it on the wrapper-owned persistent home and use retry controls instead of ad-hoc local shims.
- Before any commit on this lane, keep `obsidian/Projects/Autoresearch.md` branch/base/pr/scope metadata aligned with the active worktree and branch.
