# SKILL: /external-review-generic

Purpose
- Run `codex`, `opus`, `kimi`, and `gemini` generic reviews in parallel through one thin wrapper
- Support PR review, single-commit review, explicit file review, or the current tracked working-tree diff
- Produce one consolidated operator summary with authoritative per-tool exit status

Command
```bash
plans/external_review_generic.sh <target>
```

Supported targets
```bash
plans/external_review_generic.sh PR190
plans/external_review_generic.sh '#190'
plans/external_review_generic.sh 190
plans/external_review_generic.sh --commit HEAD
plans/external_review_generic.sh --base origin/main
plans/external_review_generic.sh --files "path1 path2"
plans/external_review_generic.sh
```

Behavior
- PR mode fetches `pull/<PR>/head` into a temporary detached worktree and reviews it against the resolved `origin/<baseRefName>`
- Commit, base, files, and no-arg modes dispatch directly through `plans/parallel_review.sh`
- Reviewer success or failure comes from the recorded `[done]` / `[FAIL]` dispatch lines, not artifact presence
- The wrapper writes:
  - `artifacts/story/<RUN_ID>/external_review_generic/dispatch_status.json`
  - `artifacts/story/<RUN_ID>/external_review_generic/summary.md`
- The wrapper exits non-zero if any reviewer fails, dispatch capture is inconsistent, or summary generation fails

Notes
- This is a convenience command only. It is not a workflow gate and does not integrate with reconciliation or `passes=true`.
- v1 generic mode does not auto-discover untracked files in no-arg mode. Pass untracked files explicitly via `--files`.
