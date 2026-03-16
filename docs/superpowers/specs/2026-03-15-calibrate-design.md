# `/calibrate` Skill — V0 Design Spec

**Date:** 2026-03-15
**Status:** Draft

---

## Purpose

`/calibrate` V0 is a manual agent skill that runs the existing internal and external review systems against the same story and collects their outputs in one predictable place for manual inspection.

It is intentionally small. V0 does not compare findings, normalize review content, or patch skills. It only proves that both review systems can be run together from one skill invocation and that their logs and artifact paths can be collected reliably.

---

## Problem Statement

The immediate constraint is not structured finding comparison. The immediate constraint is operational:

- Can the agent run the existing internal review stack and the existing external review wrapper against the same story from one entrypoint?
- Can the outputs be gathered into one session folder without extra manual glue?
- Can failures be preserved clearly enough for a human to inspect what happened?

Until that is proven in real runs, any normalization or comparison layer is premature.

---

## Scope

V0 is a skill, not a launcher script and not a workflow gate.

The skill does only this:

1. Require a story-scoped invocation
2. Create a calibration session folder
3. Start `review-stack` and `plans/external_review_generic.sh`
4. Wait for both to finish
5. Record logs, exit codes, artifact paths, and overall status
6. Exit non-zero if either child run fails

---

## Inputs

Required:

- `STORY_ID`
- PR number
- A story-scoped review target that both child review systems can use consistently

V0 does not support free-form commit/files/no-arg calibration mode. Those modes may be considered later if they prove necessary, but they are out of scope for the first slice.

---

## Operator Flow

1. Invoke `/calibrate` with:
   - `STORY_ID`
   - PR number
   - story-scoped review target
2. `/calibrate` creates:
   - `artifacts/story/<STORY_ID>/calibration/<SESSION_ID>/`
3. `/calibrate` records:
   - `started_at`
   - `head_commit`
   - `review_target`
4. `/calibrate` starts both child review runs in parallel:
   - `review-stack`
   - `plans/external_review_generic.sh`
5. `/calibrate` waits for both child runs to finish
6. After both finish, `/calibrate` records for each child:
   - exit code
   - artifact path if produced
   - log path
7. `/calibrate` writes session metadata and exits

Parallel start is part of the V0 behavior. This is not a runtime optimization feature; it is the behavior being proven.

---

## Artifact Layout

V0 uses exactly one session folder:

```text
artifacts/story/<STORY_ID>/calibration/<SESSION_ID>/
  review_stack.agent.log
  external.stdout.log
  external.stderr.log
  session.json
```

### Log Semantics

- `review_stack.agent.log`
  - the subagent transcript or equivalent single log for the `review-stack` run
- `external.stdout.log`
  - stdout captured from `plans/external_review_generic.sh`
- `external.stderr.log`
  - stderr captured from `plans/external_review_generic.sh`

The internal `review-stack` run does not pretend to have process-style stdout/stderr separation. V0 records it as one agent log because that is the most truthful representation of how the skill executes.

---

## Session Metadata

`session.json` contains only:

- `story_id`
- `session_id`
- `review_target`
- `head_commit`
- `started_at`
- `finished_at`
- `review_stack.exit_code`
- `review_stack.log_path`
- `review_stack.artifact_path`
- `external.exit_code`
- `external.stdout_log_path`
- `external.stderr_log_path`
- `external.artifact_path`
- `overall_status`

### Required Semantics

- `overall_status = "success"` only if both child exit codes are `0`
- otherwise `overall_status = "failed"`
- `artifact_path` may be `null` if a child run failed before producing artifacts

The session record is an index, not a review product. It binds the run together and points the operator to the underlying evidence.

---

## Child Responsibilities

`/calibrate` does not change child workflow semantics.

### Internal Child

The internal child is the existing `review-stack` skill. It remains responsible for:

- its own sequencing
- its own artifact generation
- its own failure behavior
- its own review conclusions

### External Child

The external child is the existing `plans/external_review_generic.sh` wrapper. It remains responsible for:

- dispatching its four external reviewers
- its own stdout/stderr behavior
- its own artifact generation
- its own failure behavior

`/calibrate` only orchestrates and records.

---

## Failure Handling

V0 is fail-closed at the orchestration level.

- If required inputs are missing, `/calibrate` stops before starting child runs
- If one child run fails and the other succeeds, the session is still written and `overall_status` is `failed`
- If a child produces logs but no artifact path, the session records `artifact_path = null`
- If session metadata cannot be written, the skill must surface that as a failure rather than silently succeeding

The operator must always be able to inspect what happened from the session folder even when the run fails.

---

## Success Criteria

V0 is successful if:

- both review systems can be run against the same story from one manual skill entrypoint
- logs and artifact paths are collected in one predictable folder
- failures are explicit and preserved for inspection
- a human can manually compare outputs after the run

---

## Non-Goals

V0 does not do any of the following:

- decide whether findings are the same
- produce a merged report
- normalize findings into a shared schema
- parse markdown review content
- map severities across systems
- dedupe findings
- patch skills
- become a workflow gate
- replace either existing review system
- optimize runtime beyond the basic concurrent execution of both existing systems

---

## Follow-On Phasing

The intended progression after V0 is evidence-driven:

- V0: run both systems together and collect logs plus artifact paths
- V1: add optional wrapper-produced sidecars only if manual comparison proves painful
- V2: add comparison or dedupe only after stable sidecars and recurring comparison needs are demonstrated by real runs

This ordering is deliberate. Standardization should be forced by observed pain, not predicted in advance.
