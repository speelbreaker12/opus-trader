# Reconciliation Run Card

## Run Metadata

- Run ID: __RUN_ID__
- Story ID: __STORY_ID__
- Slice ID: __SLICE_ID__
- Started (UTC): __STARTED_AT__
- Base branch: __BASE_BRANCH__
- Head commit: __HEAD_COMMIT__

## Current Pointer (resume-safe)

- Current story: __STORY_ID__
- Current step: preflight
- Last validated receipt: none
- Blocked reason: none

## Authority Split

- Operator:
  - orchestration, gates, validation, logs, GO/NO-GO
  - external reviews (`codex`, `sonnet`, `kimi`, `gemini`)
- Executor:
  - step execution + artifacts
  - mandatory step closeout report
- External reviewers:
  - independent C1/C2 artifacts only

## Prerequisite Gate Checklist

- [ ] `plans/premortem_ready.sh __STORY_ID__` passes
- [ ] premortem exists and STOPLIGHT is not RED
- [ ] no AT ownership conflicts
- [ ] required context files exist

## Reviewer Matrix

| Cycle | Tool | Command | Artifact Path | Exit |
|---|---|---|---|---:|
| C1 | codex | pending | pending | |
| C1 | sonnet | pending | pending | |
| C1 | kimi | pending | pending | |
| C1 | gemini | pending | pending | |
| C2 | codex | pending | pending | |
| C2 | sonnet | pending | pending | |
| C2 | kimi | pending | pending | |
| C2 | gemini | pending | pending | |

## Mandatory Step Closeout Prompts

1. What exact commands did you run? (copy/paste)
2. What files did you create/modify? (paths)
3. What is the strongest evidence you produced this step? (1 item)
4. What did you not do that the step asked for? (forced admission)

If any answer is empty/hand-wavy, step is FAILED.
