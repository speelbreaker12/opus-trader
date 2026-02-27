# S2-003 Step 1 Report

- Step: `preflight/R1`
- Gate: `NO-GO`

## Evidence

- Command: `plans/premortem_ready.sh S2-003`
  - Exit code: `1`
  - Summary:
    - `premortem_gate.sh failed with exit code 1`
    - `STOPLIGHT is YELLOW with 5 unresolved gap(s) not marked DEFERRED or FIX IN STEP 5`
    - `2 AT ownership conflict(s) found`
    - `scope.touch file missing: crates/soldier_core/src/recovery`

- Command: `plans/premortem_ready.sh S2-003 --json`
  - Exit code: `1`
  - Summary fields: `ready=false`, `stoplight=YELLOW`, `yellow_gaps_ok=false`, `context_files_ok=false`, `ownership_conflicts=2`
  - Conflict details:
    - `AT-216`: claiming stories `S2-003`, `S2-002`
    - `AT-217`: claiming stories `S2-003`, `S2-002`

- Command: `plans/premortem_gate.sh S2-003`
  - Exit code: `1`
  - Summary: `FAIL: missing required heading: ## 1) Clause audit (contract → AT traceability)`

## Blocker Sources (files/fields)

1. `reviews/premortems/S2-003_premortem.md`
   - Section-1 heading text mismatch vs required literal:
     - Found: `## 1) Clause audit (contract -> AT traceability)`
     - Required by gate: `## 1) Clause audit (contract → AT traceability)`
   - Section-10 YELLOW-gap heuristic flags unresolved lines (not marked `DEFERRED`/`FIX IN STEP 5`):
     - line `192` (`Debt Register` line)
     - line `197` (PolicyGuard wiring debt row)
     - line `199` (`No RED blockers` line)
     - line `203` (assumptions exit-criteria line)
     - line `210` (debt tracking exit-criteria line)

2. `reviews/premortems/S2-002_premortem.md` and `reviews/premortems/S2-003_premortem.md`
   - AT ownership conflict pair reported by gate:
     - `AT-216` claimed by both stories
     - `AT-217` claimed by both stories

3. `plans/prd.json` (`.items[] | select(.id=="S2-003") | .scope.touch[1]`)
   - Value: `crates/soldier_core/src/recovery`
   - Gate checks `-f` (file only); current path exists as directory, so gate reports missing scope.touch file.

## Friction (top 3)

1. Default gate output is high-level and hides root-cause details (`premortem_gate` failure specifics and AT IDs).
2. YELLOW-gap detection is keyword-based and over-matches non-gap lines in Section 10, producing noisy blocker counts.
3. `scope.touch` validation expects files only (`-f`) while PRD scope entries can be directories, causing false blockers.

## Proposed Process Simplifications

1. Tie to Friction 1: make `plans/premortem_ready.sh` print structured details on failure by default (or auto-print the failing `premortem_gate` reason and AT conflict IDs).
2. Tie to Friction 2: replace Section-10 keyword scanning with a strict parser of the Debt Register rows and explicit status markers (`DEFERRED`/`FIX IN STEP 5` columns).
3. Tie to Friction 3: align contract/schema and gate behavior for `scope.touch` (either enforce file-only entries in PRD lint, or accept existing paths with `-e` plus type checks).
