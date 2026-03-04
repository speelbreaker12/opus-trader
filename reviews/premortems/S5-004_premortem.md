# Story Premortem: S5-004

## 0) What we're building
- Story: Enforce premortem-first workflow progression for story S5-004 and validate receipt generation path.
- Contract clause: specs/WORKFLOW_CONTRACT.md premortem-before-implementation policy and deterministic fail-closed diagnostics.
- Acceptance tests: AT-WF-PREMORTEM-FIRST-001

## 1) Clause audit (contract → AT traceability)
| Contract Clause | Risk if missed | AT | Evidence to collect |
|---|---|---|---|
| Premortem must exist before workflow progression | Story advances without risk analysis | AT-WF-PREMORTEM-FIRST-001 | `plans/premortem_gate.sh S5-004` returns 0 |

## 2) Assumptions (each must become a test or get killed)
- `plans/premortem_gate.sh` is the authoritative structural validator for premortems in this repo.
- `WF_RECON_MODE=1 bash plans/wf_step.sh` enforces premortem readiness before progression.
- Full verify may fail for unrelated reasons; we only need proof that premortem gate blocker is removed.

## 3) Top 5 failure modes
| Failure mode | Trigger | Detection | Prevention |
|---|---|---|---|
| Missing required section heading | Handwritten premortem misses canonical heading text | premortem_gate exits 1 with missing heading message | Copy required section titles 0..10 exactly |
| Placeholder leakage (draft marker) | Draft not fully filled | premortem_gate exits 1 on placeholder marker | Fill all fields with concrete values before gate |
| Insufficient AT tables | Tables present but missing data rows | premortem_gate row-count checks fail in sections 1/5/6 | Add at least one AT row per required section |
| STOPLIGHT not valid | STOPLIGHT absent or non-enum value | premortem_gate STOPLIGHT regex fails | Set `**STOPLIGHT**: GREEN` explicitly |
| Workflow still blocked after premortem | Different preflight gate fails first | `wf_step --status` shows next blocker | Capture first blocker and receipts for handoff |

## 4) Open decisions (resolve before coding)
- None for this story test; the objective is gate conformance and workflow state evidence.

## 5) Wrong implementation gate
| Wrong approach | Why wrong | AT that catches it | Required correction |
|---|---|---|---|
| Running wf_step before writing premortem | Violates premortem-first requirement and causes deterministic block | AT-WF-PREMORTEM-FIRST-001 | Create valid premortem first, then rerun wf_step |

## 6) Proof plan (AT → enforcement → tests)
| AT | Enforcement point | Command | Expected proof |
|---|---|---|---|
| AT-WF-PREMORTEM-FIRST-001 | `plans/premortem_gate.sh` + `plans/wf_step.sh` preflight | `plans/premortem_gate.sh S5-004` then `WF_RECON_MODE=1 bash plans/wf_step.sh S5-004 preflight --run-sequence` | Premortem gate passes and first blocker shifts away from premortem |

## 7) Economic risk (loss_mode)
- worst financial outcome: Engineer time loss from repeated blocked workflow attempts and misleading failure triage.
- Fail-closed cap: hard block at premortem and preflight gates prevents unsafe story progression and limits rework.

## 8) Conflict scan & hot zones
- Hot zone: workflow state machine transitions in `plans/wf_step.sh` under recon mode.
- Hot zone: premortem schema/heading strictness in `plans/premortem_gate.sh`.
- Conflict risk: other verify gates may fail after premortem is accepted; must distinguish blocker ordering.

## 9) Constraint I expect to hit
- Constraint: verification feedback loop latency in `./plans/verify.sh full`.
- Exploit: run targeted premortem and wf_step commands first to isolate blocker transition before full verify.
Prior Postmortem: NONE
Reused Guardrail: NONE

## 10) STOPLIGHT + Exit criteria
**STOPLIGHT**: GREEN

- [x] Premortem artifact exists at `reviews/premortems/S5-004_premortem.md`.
- [x] Sections `0..10` are present with required canonical headings.
- [x] Sections 1, 5, and 6 each include at least one AT table row.
- [x] Section 3 includes at least three failure mode rows.
- [x] `plans/premortem_gate.sh S5-004` passes.
- [x] Workflow status and receipts are captured after preflight sequence run.
