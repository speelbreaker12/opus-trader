---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: Upgrade 2 graybox telemetry completion is now keyed to `docs/codebase/upgrade2_graybox_telemetry_checklist.md`, and the upgrade status note explicitly defers closure to that checklist.
- Value (what problem it solves): This keeps Upgrade 2 scope and pass/fail state mechanical, so future agents cannot close or resize the upgrade from summary prose.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The checklist existed but only the project note treated it as canonical; the upgrade status note still read like narrative status was authoritative; scope could drift because the checklist rows were not explicitly declared as the source of truth.
- Time/token drain it caused: I had to search across project notes, upgrade notes, and repo docs to confirm where Upgrade 2 acceptance really lived instead of finding one mechanical gate immediately.
- Workaround I used this session (exploit): I tightened the checklist with an explicit scope rule and linked the Upgrade status note back to that single artifact as the only closure gate.
- Next-agent default behavior (subordinate): Treat the checklist rows as the sole Upgrade 2 scope ledger and update the status note only to point back to the checklist, not to redefine completion.
- Permanent fix proposal (elevate): Add a lightweight workflow/doc lint that asserts Upgrade 2 status docs reference `docs/codebase/upgrade2_graybox_telemetry_checklist.md` and that closure text uses the checklist as the gate.
- Smallest increment: Add one grep-based workflow check that fails if the Upgrade status note stops mentioning the canonical checklist path.
- Validation (proof it got better): The checklist now says it is the Upgrade 2 acceptance gate and defines scope mechanically; the Upgrade status note links to it as the only closure gate; relative-link checks pass.

## 2) Best follow-up
- Single best next step: Convert the next highest-value FAIL row in the checklist into a sink seam plus graybox/parity coverage, then flip only that row when the proof exists.
- 1-3 upgrades worth considering:
- What: Add a tiny doc guard for the Upgrade 2 gate wording. | Increment: one shell test in workflow verification that greps the status note for the checklist path. | Validation: the gate fails if a later edit drops the canonical link.
- What: Record explicit rationale for the conditional rows (`group`, `WAL-nonblocking`) directly in the checklist. | Increment: add one note per conditional row stating the inclusion rule. | Validation: future agents can decide scope from the checklist without rereading prior project notes.
- What: Add a checklist refresh command snippet beside the census query. | Increment: document the repo search commands used to confirm PASS/FAIL evidence. | Validation: the next audit can be rerun mechanically from the checklist alone.

## 3) Enforceable rules
- rule: Upgrade 2 closure text must point to the checklist instead of declaring completion from narrative summaries.
  trigger: Any edit to Upgrade 2 status or project-tracking notes.
  prevents: Scope drift where prose claims closure despite red checklist rows.
  enforce: `obsidian/Upgrades for AI/1/Status 2026-03-05.md`
- rule: Upgrade 2 scope changes must be expressed by editing checklist rows and evidence, not by adding prose exceptions elsewhere.
  trigger: Any decision to add, remove, or defer an Upgrade 2 module.
  prevents: Hidden scope changes spread across project notes and chat summaries.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
- rule: When a checklist row flips, record the supporting evidence path in the checklist before describing the milestone as complete anywhere else.
  trigger: Any Upgrade 2 implementation PR or follow-up doc change.
  prevents: PASS claims without a mechanical evidence trail.
  enforce: `docs/codebase/upgrade2_graybox_telemetry_checklist.md`
