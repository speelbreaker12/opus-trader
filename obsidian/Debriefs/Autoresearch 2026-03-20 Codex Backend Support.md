---
project: "[[Autoresearch]]"
date: "2026-03-20"
---

## Commits
- `52cf1b15`

## 0) What shipped
- Feature/behavior: Added tracked repo support for Codex-backed contract autoresearch via `harness.sh contract ... --backend codex` and `autoresearch/contract/codex_wrapper.py`, documented it in `autoresearch/contract/README.md`, and reran live Phase 1 and Phase 2 on Codex `gpt-5.4` with `xhigh`.
- Value (what problem it solves): Removes the fragile `/tmp`-only wrapper dependency and gives the repo an owned, test-backed path for running contract autoresearch when Claude is unavailable.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms):
  - Large inline contract prompts caused Codex websocket idle reconnects and dead-sleep runs with no `last.txt`.
  - The first real Phase 1 batch stalled on `trading_mode_computation` for >20 minutes with no new artifacts.
  - Default `~/.codex` state polluted one-shot JSON requests with unrelated skill/tool behavior.
- Time/token drain it caused:
  - Burned multiple live batch attempts and long waits without outputs, shifting effort from contract analysis into transport debugging.
- Workaround I used this session (exploit):
  - Moved Codex to an isolated clean home and rewrote contract prompts into short file-reading prompts before invoking `codex exec`.
- Next-agent default behavior (subordinate):
  - For contract autoresearch on Codex, use `harness.sh contract ... --backend codex --model gpt-5.4` instead of ad-hoc `CLAUDE_BIN=/tmp/...`.
- Permanent fix proposal (elevate):
  - Keep the tracked wrapper as the canonical Codex backend for contract phase runs and document the auth/runtime expectations.
- Smallest increment:
  - `autoresearch/contract/codex_wrapper.py`, explicit `--backend codex` harness wiring, one end-to-end regression, and one live Phase 2 smoke through the tracked path.
- Validation (proof it got better):
  - New regression `test_contract_phase2_run_supports_codex_backend_with_short_prompt_wrapper` passes.
  - `python3 -m unittest autoresearch.tests.test_contract_phase_runs ...` passed for 3 targeted phase-run tests.
  - `python3 -m unittest autoresearch.tests.test_contract_harness_cli` passed.
  - `bash -n autoresearch/skills/harness.sh` passed.
  - Live runs passed: `phase1-mar20-20260320_191211-5ccf6c48` (`12/12`, `1.000`), tracked-backend `phase1-mar20codex-20260320_195735-903f0acd` (`12/12`, `1.000`), `phase2-mar20-20260320_193507-66196f79` (`8/8`, `1.000`), and tracked-backend smoke `phase2-mar20codex-20260320_194341-e183cb6b` (`8/8`, `1.000`).
  - PR #224 is open against `main`; subsequent full live Phase 2 attempts on `eval_live.json` were blocked by upstream Codex service errors rather than repo-side validation or wrapper failures.

## 2) Best follow-up
- Single best next step: Re-run the full live Phase 2 `eval_live.json` batch on PR #224 when Codex service availability recovers, using the committed `--backend codex` path already proven by the smaller live runs.
- 1-3 upgrades worth considering:
  - Add a short contract-autoresearch README note for `--backend codex`, auth sourcing, and the `gpt-5.4`/`xhigh` default.
  - Add one phase1 live-codex smoke to complement the phase2 regression if runtime cost stays acceptable.
  - Consider an environment default for contract lanes that standardizes the Codex backend without repeating `--backend codex`.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- If contract autoresearch uses Codex, invoke it via `harness.sh contract ... --backend codex`; do not depend on one-off `/tmp` wrappers.
- Codex contract prompts must stay in short file-reading form, not inline fixture dumps; enforce with `autoresearch/tests/test_contract_phase_runs.py`.
- Before any commit on this lane, keep `obsidian/Projects/Autoresearch.md` branch/base/pr/scope metadata aligned with the active worktree and branch.
