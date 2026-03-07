Permanent fix proposal (elevate - break the
  constraint):
  Extend plans/contract_check.sh with a deterministic
  consistency check for label-matching semantics so
  canonical s4 exact-match rules cannot coexist with
  canonical fallback wording elsewhere in the contract.

  Smallest increment to validate the elevation:
  Add one check that fails if specs/CONTRACT.md contains
  both “canonical s4 labels MUST NOT use heuristic” and
  the old unconditional canonical fallback algorithm
  wording.

  Validation (proof the constraint got better):
  The final committed text passed git diff --check,
  crossrefs, state machines, invariants, time freshness,
  crash/replay/idempotency, reconciliation matrix, and
  CSP trace validation.

  2) Best next story + upgrade candidates

  Best follow-up story:
  Implement runtime and test alignment for canonical
  label matching and reconnect dedupe in recovery code.
  Smallest increment: update label_match.rs so canonical
  s4 uses exact full identity only, with legacy fallback
  reserved for explicit non-canonical labels.
  Validation: cargo test -p soldier_core --test
  test_label_match plus replay/reconciliation tests stay
  green.

  Upgrade candidates (1-3):

  3. What: Implement amount_semantics in dispatcher
     sizing and outbound amount selection. | Increment:
     normalize venue metadata and route amount selection
     through amount_semantics. | Validation: dispatcher
     sizing tests cover coin-vs-usd instruments and pass.
  4. What: Align pricer code with the contract so Net
     Edge authorizes and Pricer only constructs limits. |
     Increment: remove duplicate profitability gating
     from pricer and add pricer-specific invalid-input
     rejects. | Validation: cargo test -p soldier_core
     --test test_pricer passes with new fail-closed
     cases.
  5. What: Enforce the normative OPEN chokepoint ordering
     in one constructor path. | Increment: add sequence
     tracing around build_order_intent. | Validation:
     cargo test -p soldier_core --test test_gate_ordering
     proves ordering and no pre-RecordedBeforeDispatch
     network side effects.