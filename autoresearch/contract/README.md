# Contract Autoresearch

Manual-promotion-oriented contract autoresearch scaffold.

This tree is intentionally conservative in v1:

- The harness may generate fixture-local proposals and review artifacts.
- The harness must not write `specs/CONTRACT.md`.
- Human review decisions are recorded in `phase2/review/REVIEW_DECISIONS_<run_id>.json`.
- Accepted-only patch rendering is fail-closed and requires explicit review decisions.

The initial executable slice in this repository provides:

- tracked schemas for findings, proposals, and review decisions
- tracked phase directories and results headers
- contract harness commands for `scaffold`, `status`, `phase1 run|baseline|eval`, `phase2 run|baseline|eval`, `refresh-common|refresh-fixtures|refresh-all`, and `render-review`
- explicit backend selection for contract runs via `--backend claude|codex`
- fail-closed Phase 2 validation for cross-file integrity, weak-normative evidence presence, mechanical span resolution, contradiction heuristics, and review-package rendering
- deterministic refresh of shared context, live Phase 1 fixtures, snapshot fixtures, and manifest hashes
- `results.tsv` records execution-check rows for `run` and scored rows for `baseline`; `eval` scores existing output directories without mutating results history

## Codex Backend

Use the tracked Codex path when Claude is unavailable or when the default Claude CLI transport is unreliable for large contract fixtures:

```bash
bash autoresearch/skills/harness.sh contract phase1 run --backend codex --model gpt-5.4
bash autoresearch/skills/harness.sh contract phase2 run --backend codex --model gpt-5.4
```

Notes:

- `--backend codex` routes `run_phase.py` through `autoresearch/contract/codex_wrapper.py` while preserving the existing `CLAUDE_BIN --model ... -p ...` subprocess contract.
- The wrapper rewrites contract prompts into short file-reading prompts before calling `codex exec`; this avoids the large inline-fixture payloads that previously caused stalled runs.
- Auth defaults to `~/.codex/auth.json`. Override with `CONTRACT_CODEX_AUTH_JSON=/path/to/auth.json` if the session should use a different Codex profile or token source.
- Model defaults still map `sonnet` to `gpt-5.4` inside the wrapper; pass `--model` explicitly if you want a different Codex model.

Deferred automation remains deferred:

- richer structural scoring beyond the current contract-specific evaluator rules
- auto-apply / promotion-state management
- live contract writes
