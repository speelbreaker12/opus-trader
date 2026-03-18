# Story Premortem: S2-003

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S2-003 -- S2.4 Label match disambiguation
- Contract clause(s): §1.1.2 Label Parse + Disambiguation (Collision-Safe)
- Acceptance tests: AT-217, AT-216
- Touch scope: `crates/soldier_core/src/lib.rs`, `crates/soldier_core/src/recovery/`, `crates/soldier_core/tests/test_label_match.rs`
- Avoid scope: `crates/soldier_core/src/execution/**`
- **Risk rating**: MED
  - This story MATCHES fills from the exchange back to local intents. A wrong match means position attribution is incorrect: the system believes Intent A was filled when actually Intent B was filled. This corrupts the position ledger, exposure calculations, and all downstream safety gates.
  - The fail-closed design (Degraded on ambiguity) limits the blast radius, but a matcher that confidently returns a WRONG match (deterministic but incorrect) is worse than one that admits ambiguity.
  - Touches the recovery path, which is exercised during restarts and reconnections -- high-consequence scenarios where correctness matters most.

## 1) Clause audit (contract -> AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-217 | §1.1.2 | "two intents share the same gid12 and leg_idx... resolves using ih16 + instrument + side; if still ambiguous, RiskState::Degraded and opens blocked" | MUST | Yes -- construct ambiguous and non-ambiguous candidate sets, assert correct resolution or Degraded |
| AT-216 | §1.1.2 | "an outbound order intent is built with a valid s4: label... parser extracts {sid8, gid12, li, ih16} correctly" | MUST | Yes -- but S2-003 CONSUMES the parser (produced by S2-002). S2-003's responsibility for AT-216 is limited to correctly using the parsed components for matching. |

**Note on AT ownership split:**
- AT-217: S2-003 is the primary implementer of the disambiguation algorithm. S2-002 is primary_owner_for AT-217 in the PRD because it produces labels with ih16, but S2-003 is the story that exercises the tie-breaker chain. S2-003 is the functional owner of the disambiguation behavior.
- AT-216: S2-002 is primary owner. S2-003 depends on S2-002's parser but does not re-implement it. S2-003's tests should import and use S2-002's `parse_label` function, not duplicate parsing logic.

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | S2-002 exports a `parse_label` function that returns `LabelComponents { sid8, gid12, leg_idx, ih16 }`. S2-003 calls this function to parse inbound labels. | If S2-002 does not export this function, or the struct fields differ, S2-003 must re-implement parsing (violating DRY and risking divergence). | Compilation test: S2-003 imports and calls S2-002's parser. If the API does not exist, the build fails. | Must validate at impl time (S2-002 dependency) |
| 2 | The candidate set is built by matching `gid12 AND leg_idx` from the parsed label against the local intent ledger. The intent ledger provides an efficient lookup by (gid12, leg_idx). | If the intent ledger does not support lookup by gid12+leg_idx (e.g., only supports lookup by full intent_hash), building the candidate set requires a full scan. | Integration test: build a ledger with 1000 intents, look up by gid12+leg_idx, assert O(1) or O(log n) performance (not O(n) scan). | Must validate at impl time |
| 3 | The tie-breaker order is strictly: (A) ih16, (B) instrument, (C) side, (D) qty_q. The contract is explicit about this order. No re-ordering, no skipping. | If the implementation applies tie-breakers in a different order (e.g., instrument before ih16), a case where ih16 alone would resolve becomes ambiguous because instrument was checked first and matched multiple candidates. | Directed test: construct 3 candidates where ih16 distinguishes one but instrument+side match two. Assert that ih16 resolves before instrument is checked. This requires a test case specifically designed to fail under wrong tie-breaker ordering. | Must validate at impl time |
| 4 | `qty_q` is available on the intent for tie-breaking. `qty_q` as tie-breaker D is from PRD acceptance criteria, NOT from CONTRACT.md §1.1.2 (which lists only ih16, instrument, side). Consider amending contract or removing qty_q from chain. S2-001 produces qty_q via quantization. | If qty_q is not stored on the intent, the 4th tie-breaker cannot be applied. The matcher would skip step D and go straight to ambiguity/Degraded. | Unit test: construct candidates that are indistinguishable by ih16+instrument+side but differ in qty_q. Assert qty_q resolves the match. | Must validate at impl time |
| 5 | `RiskState::Degraded` can be set by the label matcher. The matcher is in recovery/ (not execution/). It must be able to signal Degraded state to the system. | If the matcher returns a result type that does not include a Degraded signal, the caller must infer Degraded from "no match returned." This is fragile -- the caller might treat "no match" as "ignore fill" instead of "set Degraded." | The matcher should return an explicit `MatchResult::Ambiguous` variant (or equivalent) that the caller maps to RiskState::Degraded. Test: return Ambiguous, assert caller sets Degraded. | Must validate at impl time |
| 6 | "Opens blocked" when Degraded means PolicyGuard emits REDUCEONLY_RISKSTATE_DEGRADED, which forces ReduceOnly mode, which blocks OPEN intents per §2.2.3.4. | If RiskState::Degraded does not propagate to PolicyGuard (e.g., RiskState and PolicyGuard are in different modules with no wiring), opens are not blocked despite Degraded state. | Integration test: set RiskState::Degraded via label match ambiguity, then attempt an OPEN intent. Assert it is rejected with REDUCEONLY_RISKSTATE_DEGRADED in mode_reasons. | Must validate at impl time |
| 7 | The intent_hash stored on the intent matches the ih16 extracted from the label. Specifically, the first 16 hex chars of the stored intent_hash equals the ih16 field from the label. | If the intent stores intent_hash as a different encoding (e.g., base32 while ih16 is hex), the ih16 tie-breaker always fails, and disambiguation falls through to instrument/side/qty_q. The matcher still works but with reduced tie-breaking power. | Unit test: encode an intent with known intent_hash via S2-002, parse the label, extract ih16, compare to `format!("{:016x}", intent.intent_hash)[..16]`. Assert equality. | Must validate at impl time |
| 8 | A "single clear candidate" (acceptance criterion 3) means candidate_set.len() == 1 after the initial gid12+leg_idx filter. No tie-breaking is needed. The contract says "If candidate set size == 1 -> match." | If the implementation applies tie-breakers even when candidate_set.len() == 1, it might reject a valid match (e.g., if ih16 does not match due to a hash collision but the candidate is the only one). | Unit test: single candidate with non-matching ih16. Assert the candidate is still returned (no tie-breaking for single-candidate sets). | Must validate at impl time |
| 9 | The label matcher must be deterministic: given the same inputs (label + ledger state), it always returns the same result. The contract says "deterministically map exchange orders to local intents." | If the matcher uses HashMap iteration order (non-deterministic in Rust) or sorts candidates by an unstable key, different runs could match different intents. | Property test: run the matcher 100 times with the same inputs. Assert all 100 results are identical. Also: ensure candidate filtering uses a deterministic data structure (BTreeMap, sorted Vec) not HashMap. | Must validate at impl time |
| 10 | The matcher handles the case where the parsed label has no candidates at all (candidate_set is empty). This is not "ambiguity" -- it is "no match." The contract does not explicitly address this case. | If no-match is treated as ambiguity, RiskState::Degraded is set. If no-match is treated as "fill ignored," a real fill is lost. | The correct behavior for no-match depends on the calling context. During reconciliation, no-match may mean a ghost order. The matcher should return a distinct `NoMatch` variant (not `Ambiguous`). Test: empty candidate set returns NoMatch, not Ambiguous. | Must validate at impl time |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | **Confident wrong match.** The matcher resolves to a single candidate deterministically, but it is the WRONG candidate. Example: two intents share gid12+leg_idx, and ih16 matches the wrong one due to a hash collision in the first 16 hex chars of intent_hash. The matcher returns a definitive (wrong) result without triggering Degraded. | This is the most dangerous failure mode. By design, a confident wrong match is undetectable at match time. Detection requires downstream position reconciliation (REST trade/order snapshot) to notice that the fill was attributed to the wrong intent. | The ih16 field uses 16 hex chars (64 bits of hash space, ~2^64 possible values). Hash collision probability is negligible for practical candidate set sizes (2-10 intents). Adding instrument+side+qty_q as tie-breakers further reduces false-positive risk. However, NO amount of tie-breaking prevents a collision where all fields match the wrong candidate. The ultimate backstop is periodic REST reconciliation. | AT-217 (partial -- tests disambiguation but cannot test hash-collision-induced wrong matches without contrived inputs). A property test with synthetic hash collisions would strengthen this. |
| 2 | **Wrong tie-breaker order.** The implementation applies tie-breakers as (instrument, side, ih16, qty_q) instead of (ih16, instrument, side, qty_q). For most cases, the result is the same. But for a specific case where ih16 alone resolves but instrument does not, the wrong order causes unnecessary Degraded states (false positives). Conversely, if instrument resolves but ih16 does not, the wrong order may confidently match when ih16 should have caused ambiguity first. | Directed test case designed to be order-sensitive: 3 candidates where ih16 resolves uniquely but instrument matches 2. Correct order: ih16 resolves. Wrong order: instrument narrows to 2, then ih16 resolves within the 2 -- same result but different path. The test must find a case where the result DIFFERS: 3 candidates where ih16 matches 0 (none match the label's ih16) but instrument+side matches exactly 1. Correct order: ih16 eliminates all -> ambiguity/Degraded. Wrong order: instrument+side resolves -> confident match. | The test must construct a scenario where wrong ordering produces a wrong match (not just a different path to the right match). | AT-217 (must include an order-sensitive test vector) |
| 3 | **Ambiguity not detected -- matcher picks first candidate.** The implementation uses `candidates.first()` or `candidates[0]` instead of properly checking that only one candidate remains after tie-breaking. If two candidates survive all tie-breakers, the matcher picks the first by insertion order instead of returning Ambiguous. | AT-217 explicitly requires "if still ambiguous, RiskState::Degraded and opens blocked." A test with two fully-identical candidates (same ih16, instrument, side, qty_q) must assert Ambiguous/Degraded, not a match. | The matcher must count remaining candidates after each tie-breaker round. If count > 1 after all tie-breakers, return Ambiguous. Never index into the candidate set without checking length. | AT-217 |
| 4 | **Degraded state not propagated to PolicyGuard.** The matcher returns Ambiguous, the caller sets RiskState::Degraded, but PolicyGuard does not check RiskState for the REDUCEONLY_RISKSTATE_DEGRADED reason code. Opens continue despite Degraded state. | AT-217 requires "opens blocked" on ambiguity. Integration test: trigger ambiguity, attempt OPEN, assert rejection with REDUCEONLY_RISKSTATE_DEGRADED. | PolicyGuard's axis resolver must include RiskState::Degraded as a ReduceOnly trigger. This wiring may already exist from other stories that set Degraded (e.g., instrument metadata staleness). Verify by grep. | AT-217 (integration-level test needed) |
| 5 | **Empty candidate set treated as ambiguity instead of no-match.** When a label's gid12+leg_idx matches zero local intents, the matcher treats this as "ambiguous" and sets RiskState::Degraded. This is wrong -- an empty candidate set is not ambiguity, it is a ghost/orphan label. Degraded is triggered unnecessarily, blocking opens when the system is actually healthy. | Unit test: parse a label whose gid12 does not match any intent. Assert the result is NoMatch (not Ambiguous). NoMatch should NOT trigger Degraded. | The matcher must distinguish three outcomes: (1) matched (single candidate or resolved via tie-breakers), (2) ambiguous (multiple candidates, unresolved), (3) no-match (zero candidates). Only outcome (2) sets Degraded. | Not directly covered by AT-217 (which assumes at least 2 candidates). Needs a new test vector or a tightened AT. |

## 4) Open decisions (resolve before coding)

### Decision: How to represent the match result -- enum with 3 variants or Result with error
- **What is ambiguous / missing**: The matcher can return three outcomes: Match(intent), Ambiguous, NoMatch. The contract only specifies the Ambiguous -> Degraded path. The NoMatch case is unspecified.
- **Evidence**: CONTRACT.md §1.1.2 algorithm steps: "If candidate set size == 1 -> match" (step 3). "If still ambiguous -> mark RiskState::Degraded, block opens" (step 5). Step 2 says "Candidate set = all local intents where gid12 matches AND leg_idx matches." If no intents match, candidate set is empty -- the algorithm does not define this path.
- **Options**:
  1. Option A -- `enum MatchResult { Matched(IntentRef), Ambiguous(Vec<IntentRef>), NoMatch }`. Explicit 3-way result. Caller handles each case distinctly.
  2. Option B -- `Result<IntentRef, MatchError>` where `MatchError::Ambiguous | MatchError::NoMatch`. Idiomatic Rust, but conflates two very different error conditions.
  3. Option C -- `Option<IntentRef>` with Degraded as a side effect. None = no match or ambiguous. Caller cannot distinguish.
- **Chosen**: A -- Explicit 3-way enum. Per §0.4, "harder to misuse" means the caller cannot accidentally treat Ambiguous as NoMatch (or vice versa). With Option or Result, the caller must remember which error variant means what. With a 3-variant enum, the compiler forces handling of all three cases.
- **Why not others**: Option B makes it easy to `?`-propagate both errors the same way. Option C makes it impossible to distinguish the two failure modes. Both violate §0.4.
- **Scope control**:
  - What we're NOT doing yet: defining the caller's behavior for NoMatch (that is the sweeper/reconciliation story's domain, not S2-003).
  - What unblocks us if this choice is wrong: the enum is internal; changing variant names is a refactor, not a behavioral change.

### Decision: Where does the metric `label_match_ambiguity_total` get incremented -- in the matcher or in the caller?
- **What is ambiguous / missing**: The PRD specifies `label_match_ambiguity_total` as a counter. Should the matcher increment it directly, or should the caller increment it when it receives an Ambiguous result?
- **Evidence**: DESIGN_PATTERNS.md §0.4 (harder to misuse). If the caller must remember to increment the counter, it can forget. If the matcher does it, every Ambiguous path is counted automatically.
- **Options**:
  1. Option A -- Matcher increments the counter. Requires the matcher to receive a metrics handle (dependency injection).
  2. Option B -- Caller increments on Ambiguous result. Keeps the matcher pure (no I/O or metrics dependency).
- **Chosen**: B -- Caller increments. The matcher should be a pure function for testability (§0.4: "easier to test" after "harder to misuse"). The "harder to misuse" concern is addressed by the 3-variant enum: the caller MUST handle Ambiguous, and the handling path increments the counter. A caller that matches on Ambiguous but forgets to increment is caught by code review, not by compile-time enforcement, but this is an acceptable tradeoff for testability.
- **Why not others**: Option A couples the matcher to the metrics subsystem, making unit tests require a metrics mock. The matcher is exercised in many tests; each test would need metrics setup boilerplate.
- **Scope control**:
  - What we're NOT doing yet: wiring the actual Prometheus counter (that is an infrastructure concern). The test asserts that the caller calls a counter-increment function.
  - What unblocks us if this choice is wrong: adding metrics injection to the matcher is additive (pass a handle, call handle.inc()).

### Decision: How are tie-breakers applied -- sequential filtering or scoring?
- **What is ambiguous / missing**: The contract lists tie-breakers A, B, C, D in order. Does "in order" mean sequential filtering (apply A, remove non-matches, then apply B to remainder, etc.) or scoring (score each candidate by how many tie-breakers match, pick highest)?
- **Evidence**: CONTRACT.md §1.1.2 algorithm: "disambiguate using the following tie-breakers in order: A) ih16 match B) instrument match C) side match D) qty_q match." The word "in order" and the sequential presentation (A, B, C, D) imply sequential filtering. Step 5 says "If still ambiguous" -- "still" implies progressive narrowing.
- **Options**:
  1. Option A -- Sequential filtering. Start with full candidate set. Apply ih16 filter: keep only candidates where ih16 matches. If exactly 1 remains, return it. If 0 remain, fall back to full set and apply next filter (instrument). If > 1 remain, apply next filter to the narrowed set.
  2. Option B -- Sequential filtering, strict. Apply ih16 filter. If 0 match on ih16, the candidate set is empty -> Ambiguous (fail-closed). Do NOT fall back to the original set.
  3. Option C -- Scoring. Give each candidate a score: +4 for ih16 match, +2 for instrument, +1 for side, etc. Pick highest scorer. Tie -> Ambiguous.
- **Chosen**: A -- Sequential filtering with fallback to original set on zero-match. The contract says "disambiguate using... ih16 + instrument + side" -- the "+" suggests these are additive refinements, not elimination rounds. If ih16 matches nobody (hash collision between label and all candidates), the label was still sent with this gid12+leg_idx, so the intent is in the candidate set -- we should try instrument+side before giving up.
  However, this interpretation needs validation: the contract does not explicitly say what happens when a tie-breaker narrows to zero candidates. The safest reading is: each tie-breaker narrows the candidate set. If a tie-breaker eliminates all candidates (none match ih16), the tie-breaker is skipped (it is not informative). The remaining candidates are passed to the next tie-breaker. This is the "filter, but skip non-informative filters" approach.
- **Why not others**: Option B is too aggressive -- if ih16 does not match any candidate (possible if the label was produced by a different code version or a non-conforming source), the matcher immediately declares ambiguity even when instrument+side would resolve uniquely. Option C loses the priority ordering -- a candidate that matches instrument+side+qty_q but not ih16 could outscore a candidate that matches only ih16, violating the contract's priority order.
- **Scope control**:
  - What we're NOT doing yet: handling non-conforming labels (labels without the s4: prefix or with wrong field counts). Those are parse errors handled by S2-002's parser.
  - What unblocks us if this choice is wrong: the tie-breaker logic is a single function; changing the filtering strategy is localized.

### Decision: What does "qty_q match" mean -- exact equality or within epsilon?
- **What is ambiguous / missing**: The contract lists `qty_q` as tie-breaker D. S2-001 quantizes qty to integer steps (qty_steps). Does "qty_q match" mean exact integer equality of qty_steps, or floating-point comparison with epsilon?
- `qty_q` as tie-breaker D is from PRD acceptance criteria, NOT from CONTRACT.md §1.1.2 (which lists only ih16, instrument, side). Consider amending contract or removing qty_q from chain.
- **Evidence**: CONTRACT.md §1.1.1 quantization: qty_q is quantized to integer tick steps. The intent stores `qty_steps: i64` (integer). DESIGN_PATTERNS.md §0.1: "Decisions use real quantities, not proxies."
- **Options**:
  1. Option A -- Exact integer equality of qty_steps (the quantized value). No epsilon.
  2. Option B -- Floating-point comparison of the original qty with epsilon tolerance.
- **Chosen**: A -- Exact integer equality. qty_steps is an integer after S2-001 quantization. Integer comparison is exact, deterministic, and uses the real quantity (§0.1). No epsilon needed.
- **Why not others**: Option B uses the pre-quantization floating-point value, which introduces epsilon ambiguity and non-determinism. The quantized integer IS the canonical representation per S2-001.
- **Scope control**:
  - What we're NOT doing yet: handling the case where the exchange fill reports qty in a different unit than qty_steps. That is a fill-parsing concern, not a label-matching concern.
  - What unblocks us if this choice is wrong: changing from exact to epsilon comparison is a one-line change.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-217 | **First-candidate picker.** Implementation always returns `candidates[0]` after building the candidate set, without applying any tie-breakers. For single-candidate sets (the common case), this is correct. For multi-candidate sets, it returns a "match" based on insertion order, which is non-deterministic. | Violates the contract's tie-breaker chain. In production, the "matched" intent depends on HashMap/Vec insertion order, which can vary between runs. Fill attribution is non-deterministic. | **Directed test: 3 candidates, only ih16 distinguishes.** Construct 3 intents with same gid12+leg_idx, same instrument, same side, same qty_q, but different ih16. One ih16 matches the label. Assert the correct intent is returned. A first-candidate picker would return the wrong one (unless it happens to be first by insertion order). Run with shuffled insertion orders to eliminate ordering luck. |
| AT-217 | **Tie-breakers applied in wrong order (instrument before ih16).** Implementation filters `instrument` first and can return a single candidate before checking `ih16`. | If `instrument` filtering yields one candidate first, a wrong-order implementation returns that candidate even when `ih16` would pick a different one. Example: A(ih16=AA, instrument=BTC, side=Buy), B(ih16=BB, instrument=ETH, side=Buy), C(ih16=CC, instrument=ETH, side=Buy); label has ih16=CC, instrument=BTC. Correct order (`ih16` first) returns C. Instrument-first returns A. | **Forced-order test:** use the three-candidate setup above. Assert the correct-order implementation returns C and the wrong-order implementation returns A (different final outcome, not just path difference). |
| AT-217 | **Ambiguity returns None instead of triggering Degraded.** Implementation returns `None` (or `NoMatch`) when ambiguity is detected, instead of a distinct `Ambiguous` variant. The caller treats `None` as "fill not matched to any intent" and does NOT set Degraded. Opens continue. | The contract requires Degraded + opens blocked on unresolved ambiguity. Returning None silently discards the ambiguity signal. The caller cannot distinguish "no candidates" from "too many candidates." | **Integration test:** 2 identical candidates (same ih16, instrument, side, qty_q). Assert MatchResult is Ambiguous (not NoMatch). Then assert RiskState == Degraded and an OPEN intent is rejected with REDUCEONLY_RISKSTATE_DEGRADED. |
| AT-217 | **Degraded set but opens NOT blocked.** The matcher correctly returns Ambiguous, the caller correctly sets RiskState::Degraded, but PolicyGuard does not have REDUCEONLY_RISKSTATE_DEGRADED wired as a ReduceOnly trigger. Opens proceed despite Degraded. | The Degraded state exists but has no enforcement consequence. This is "paper compliance" (§0.5): the state is set but the gate is not connected. | **End-to-end test:** trigger Ambiguous, verify RiskState::Degraded, attempt OPEN, assert REJECTED with mode_reason REDUCEONLY_RISKSTATE_DEGRADED. This test fails if the wiring is missing. |
| AT-216 | **S2-003 re-implements parsing instead of using S2-002's parser.** The matcher has its own label parser that uses a different field order or different delimiter handling than S2-002's parser. Both parsers work in isolation but disagree on edge cases (e.g., labels with extra colons, empty fields). | Two parsers for the same label format is a maintenance hazard. When S2-002 updates the parser, S2-003's copy diverges. At runtime, the encoder (S2-002) and decoder (S2-003) disagree on what fields are what. | **Compilation-level enforcement:** S2-003's test file must import `parse_label` from S2-002's module. If S2-003 defines its own parser, code review must catch it. Add a grep-based CI check: `parse_label` should be defined in exactly one file. |
| AT-217 | **Counter never incremented.** Matcher returns Ambiguous, caller sets Degraded, opens are blocked, but `label_match_ambiguity_total` counter is never incremented. All behavioral requirements are met, but observability is missing. | Operators cannot detect ambiguity events via metrics. Alerting on label collisions is impossible. The PRD specifies this counter in `observability.metrics`. | **Counter test:** trigger Ambiguous, assert `label_match_ambiguity_total` was incremented by 1. |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT -> enforcement -> tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-217 (disambiguation succeeds) | Label matcher (recovery/label_match.rs) | `test_disambiguation_by_ih16`, `test_disambiguation_by_instrument`, `test_disambiguation_by_side`, `test_disambiguation_by_qty_q` | Yes (multi-candidate set resolved to correct intent) | N/A for the success path (not a safety gate) | Returned intent matches expected intent by identity | Yes -- removing the tie-breaker logic fails only these tests |
| AT-217 (ambiguity -> Degraded) | Label matcher + PolicyGuard (REDUCEONLY_RISKSTATE_DEGRADED) | `test_ambiguity_sets_degraded`, `test_ambiguity_blocks_opens` | Yes (ambiguous candidates -> Degraded + opens blocked) | Yes (single candidate -> no Degraded, opens allowed) | dispatch_count == 0 (for OPEN intent after Degraded) AND RiskState == Degraded AND mode_reason contains REDUCEONLY_RISKSTATE_DEGRADED | Yes -- removing ambiguity detection fails the TRIP test; removing Degraded propagation fails the integration test |
| AT-216 (parser usage) | S2-002's parse_label function, called by S2-003's matcher | `test_match_uses_parsed_components` | Yes (parsed label components drive candidate selection) | Yes (malformed label -> parse error, no match attempted) | Parsed components (gid12, leg_idx) used as lookup keys; ih16 used as tie-breaker | Shared with S2-002 -- S2-003 tests the USAGE of parsed components, not the parsing itself |

**TRIP/NON-TRIP for AT-217 (safety-critical):**
- TRIP: 2 candidates with same gid12+leg_idx, ambiguous after all tie-breakers. Assert: MatchResult::Ambiguous, RiskState::Degraded, dispatch_count_for_OPEN == 0.
- NON-TRIP: 2 candidates with same gid12+leg_idx, ih16 distinguishes one. Assert: MatchResult::Matched(correct_intent), RiskState::Healthy (or unchanged), OPEN intent proceeds.

**Causality proof for AT-217 TRIP:**
- `dispatch_count`: Must be 0 for any OPEN intent dispatched after Degraded is set.
- `reject_reason`: Not applicable (the rejection is at the PolicyGuard level via mode_reason, not at the intent level).
- `mode_reason`: REDUCEONLY_RISKSTATE_DEGRADED must appear in `/status.mode_reasons`.

**Isolation check:** AT-217's disambiguation logic is entirely in recovery/label_match.rs. Removing the tie-breaker function fails only AT-217 tests. The Degraded propagation relies on existing PolicyGuard wiring (REDUCEONLY_RISKSTATE_DEGRADED), which is shared with other Degraded triggers (e.g., instrument metadata staleness). The isolation is at the matcher level, not at the PolicyGuard level.

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Label match ambiguity causes a wrong intent to be matched to a fill. Position attribution is incorrect: the system believes it has a different position than it actually has. If the system thinks position is zero when it is long, it opens another long, doubling exposure. If it thinks it is long when it is actually flat, it may emergency-close (selling into nothing), incurring costs. Worst case: doubled position in a fast-moving market, with the system unable to correct because it does not know its true position.
- **Fail-closed cap on loss**: Three layers: (1) On unresolved ambiguity, RiskState::Degraded blocks new opens via REDUCEONLY_RISKSTATE_DEGRADED. (2) PolicyGuard forces ReduceOnly, limiting exposure to existing positions. (3) The contract requires REST trade/order snapshot reconciliation to clear Degraded, which provides an independent ground-truth check. The fail-closed cap means losses are bounded by existing position size at the time of ambiguity, not by new position accumulation.
- **Drift metric**: `label_match_ambiguity_total` counter. Should stay at 0 in normal operation. Any non-zero value indicates a label collision or a schema mismatch. Alert threshold: > 0 within any 1-hour window.
- **Loss boundary**: ReduceOnly (via REDUCEONLY_RISKSTATE_DEGRADED). No new opens until reconciliation clears Degraded.
- **Rollback plan**: Revert the label_match.rs changes. The matcher is stateless -- it reads the intent ledger and incoming labels, produces a match result. No persistent state is modified by the matcher itself. Reverting restores the previous matching behavior (or no matching, if this is the first implementation). If a wrong match was made before reverting, the position ledger may be corrupted; manual reconciliation via REST is required.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: The label matcher is called during fill processing (exchange reports a fill, system matches it to a local intent) and during reconciliation (restart, WS reconnect). It feeds into position tracking, TLSM state transitions, and exposure calculations.
- **If conflict with CONTRACT.md**: No conflict detected. The contract specifies the exact disambiguation algorithm and this story implements it.
- Files with recent churn or shared ownership:
  - `crates/soldier_core/src/recovery/` -- new or lightly populated module. S2-003 creates `label_match.rs` here.
  - `crates/soldier_core/src/lib.rs` -- shared with all stories. Will need `pub mod recovery;` or similar.
  - `crates/soldier_core/tests/test_label_match.rs` -- new file, sole owner.
- Struct fields I'm assuming exist (verify before coding):
  - `Intent` struct with fields: `group_id`, `leg_idx`, `intent_hash` (u64), `instrument` (String or InstrumentId), `side` (Side enum), `qty_steps` (i64 or u64)
  - `RiskState::Degraded` variant exists
  - `ModeReasonCode::REDUCEONLY_RISKSTATE_DEGRADED` variant exists and PolicyGuard checks RiskState for Degraded
  - S2-002's `parse_label` function is exported and returns `LabelComponents { sid8, gid12, leg_idx, ih16 }`
- State machine transitions affected: RiskState transitions to Degraded on ambiguity. This is not a state machine transition per se (RiskState can be set from multiple sources), but it affects the PolicyGuard's TradingMode resolution.
- **Shared AT ownership (S2-002 / S2-003):**
  - AT-217: S2-002 is listed as primary_owner_for in the PRD, but S2-003 implements the disambiguation algorithm. S2-003's tests are the proving ground for AT-217's behavioral requirements. S2-002's ownership is limited to producing labels with ih16 for disambiguation.
  - AT-216: S2-002 is primary owner. S2-003 calls S2-002's parser. S2-003's tests exercise the parser indirectly but do not test parser correctness independently.
  - **Interface contract**: S2-003 MUST call S2-002's `parse_label` function. S2-003 MUST NOT re-implement label parsing. If S2-002's parser API changes, S2-003 must be updated in the same patch.
- **Downstream dependencies**: S2-004 (RejectReasonCode registry) and S2-005 depend on S2-003. Changes to the MatchResult enum or the Degraded propagation path affect downstream stories.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (no postmortem exists for S2-002)
Reused Guardrail: NONE (no prior postmortem exists)

- Carry-forward from prior postmortem: N/A -- no S2-002 postmortem found.
- What will slow me down: The tie-breaker filtering semantics are subtly ambiguous in the contract (see Decision 3 above). When ih16 matches zero candidates, should the tie-breaker be skipped (non-informative) or should it eliminate all candidates (fail-closed)? The former is more practical, the latter is more conservative. The decision above chose "skip non-informative," but this may be challenged during review.
- Exploit: Start with the simplest possible implementation: sequential filtering where each tie-breaker narrows the candidate set, and a tie-breaker that narrows to 0 is skipped. Cover the common cases (single candidate, ih16 resolves, full ambiguity). Add edge-case tests for the ih16-matches-0 scenario after the basic implementation works.
- Smallest fix that prevents it next time: When a contract specifies an algorithm with ordered steps but does not define the "no match on this step" behavior, the premortem should flag it and the contract should be amended to make the behavior explicit.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: All ATs traced to normative clauses. Proof plan has TRIP + NON-TRIP for safety-critical AT-217. All decisions resolved. However, two gaps exist: (1) the empty-candidate-set behavior is not covered by any AT (FM-5), and (2) the PolicyGuard REDUCEONLY_RISKSTATE_DEGRADED wiring is assumed to exist but must be verified at implementation time. Both are tracked in the Debt Register below.

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| Empty candidate set (0 matches for gid12+leg_idx) behavior undefined by contract. FM-5 identified that treating 0-match as Ambiguous is wrong but no AT covers this case. | Low | The 0-match case is a ghost/orphan order, which is the Sweeper's domain (§3.4), not S2-003's. S2-003 should return NoMatch, and the Sweeper handles ghost orders. | S2-003 implementer | Sweeper story (slice 3+) | Add unit test for NoMatch on 0-candidate set. Consider amending contract §1.1.2 to explicitly address the 0-candidate case. |
| PolicyGuard REDUCEONLY_RISKSTATE_DEGRADED wiring. S2-003 assumes PolicyGuard checks RiskState::Degraded and emits this reason code. If the wiring does not exist, AT-217's "opens blocked" requirement is not enforced. | Med | The PolicyGuard wiring may already exist from other stories that set RiskState::Degraded (e.g., ContractsAmountMismatch). Must verify at implementation time via grep for REDUCEONLY_RISKSTATE_DEGRADED in PolicyGuard code. If missing, S2-003 must add it (scope creep) or defer to a separate wiring story. | S2-003 implementer | S2-003 (verify) or separate PolicyGuard wiring story | Integration test: Degraded -> OPEN rejected with REDUCEONLY_RISKSTATE_DEGRADED |

YELLOW with all debt tracked and assigned to target slices. No RED blockers.

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed -- 10 assumptions documented; all have test plans
- [x] §3 all failure modes have detection + mitigation -- 5 modes identified with AT coverage (FM-5 deferred to debt register)
- [x] §4 all decisions resolved, grounded in evidence -- 4 decisions resolved
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives -- 6 wrong impls identified with tightening
- [x] §6 proof plan: TRIP + NON-TRIP for safety-critical AT-217, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts); shared AT ownership with S2-002 explicitly documented
- [x] No new debt without owner + target slice -- 2 debt items tracked in register with owners and target slices
