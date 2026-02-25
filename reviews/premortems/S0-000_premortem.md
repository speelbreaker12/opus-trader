# Story Premortem: S0-000

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S0-000 -- P0-A Launch Policy Baseline
- Contract clause(s): Phase 0, P0-A ("Define explicit constraints on what the system is allowed to do")
- Acceptance tests: None enforcing (`enforcing_contract_ats: []`)
- Touch scope: `docs/launch_policy.md`, `evidence/phase0/policy/launch_policy_snapshot.md`
- **Risk rating**: LOW
  - Pure documentation / policy artifact. No runtime code, no safety gates, no data handling.
  - The risk is not financial loss but **policy omission** -- failing to define constraints that downstream stories (P0-F Machine Policy Loader) depend on.

## 1) Clause audit (contract -> AT traceability)

N/A -- no enforcing ATs. This story has `enforcing_contract_ats: []`.

However, the CONTRACT.md Phase 0 table states:

| ID | Contract section | Clause text (abbreviated) | Type | Testable? |
|----|-----------------|---------------------------|------|-----------|
| P0-A | Phase 0: Operational Prerequisites | "Launch Policy Baseline -- Define explicit constraints on what the system is allowed to do. Evidence Required: `docs/launch_policy.md`" | MUST (Non-Negotiable) | Yes -- file existence + content review |

The lack of formal ATs is itself a concern. The acceptance criteria in the PRD story are review-based ("WHEN reviewed THEN includes X"), not machine-verifiable. This means pass/fail is a human judgment call, not an automated gate.

**What SHOULD be tested even without an AT:**
- File existence at the exact path `docs/launch_policy.md`
- Content includes each of the four required sections (instruments/venues, position/loss limits, order rate/pacing, environments)
- Evidence snapshot is a byte-for-byte copy of the source document

- [ ] Every claimed AT traced to a normative clause -- N/A (no ATs)
- [ ] No informational-only ATs counted as enforcement -- N/A (no ATs)

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | The `docs/` directory exists or will be created as part of this story | Writing to `docs/launch_policy.md` fails if directory is missing | Acceptance criterion 1 (file existence) | Trivial |
| 2 | The `evidence/phase0/policy/` directory exists or will be created | Snapshot file cannot be written | Acceptance criterion 5 (snapshot existence) | Trivial |
| 3 | "Literal copy" means byte-for-byte identical content, not just semantically equivalent | A paraphrased or reformatted snapshot passes review but diverges silently over time | `diff docs/launch_policy.md evidence/phase0/policy/launch_policy_snapshot.md` should exit 0 | Not formally tested |
| 4 | "Allowed instruments/venues" means a concrete enumerated list, not a placeholder like "TBD" or an external link | A document with "TBD" placeholders or "see exchange documentation" passes the existence check but fails the intent of P0-A | Human review of content completeness | Not formally tested |
| 5 | Position limits and daily loss limits are numeric values, not just prose | Prose like "reasonable limits" cannot be machine-loaded by P0-F later | Review for numeric specificity | Not formally tested |
| 6 | The policy document is consumed by later stories (P0-F Machine Policy Loader) and the format/structure must be compatible | If the doc format does not align with what P0-F expects to reference, the loader story becomes harder | P0-F integration | Deferred to P0-F story |
| 7 | Order rate/pacing values are concrete numbers (e.g., "max 10 orders/sec") not vague guidance like "appropriate pacing" | Vague guidance cannot be enforced at runtime by CSP guards | Human review | Not formally tested |
| 8 | The reviewer has domain competence to assess numeric plausibility, not just structural completeness | A reviewer who rubber-stamps a structurally complete but numerically absurd policy (e.g., max position 10,000 BTC for paper trading) is not caught by any automated gate. The entire safety of this story rests on review quality. | Reviewer selection criteria or a second-reviewer requirement for domain judgment | Not formally tested |
| 9 | All numeric constraint values include explicit units (e.g., "0.1 BTC", not just "0.1") | If units are unstated, P0-F's machine loader has to guess. "Max position: 0.1" could mean 0.1 BTC, 0.1 contracts, or 0.1 USD-equivalent. A table with numbers but no unit labels looks structured but is semantically incomplete. This is distinct from Assumption 5 (numeric vs. prose) -- here the number exists but the unit is missing or ambiguous. | Human review: every numeric value in a table must have an explicit unit label in the column header or cell | Not formally tested |
| 10 | The document clarifies whether constraint values are global (one limit for all instruments) or per-instrument | A single set of limits may be conservative for BTC but dangerously large for an illiquid altcoin, or vice versa. If the policy says "max position: 0.1 BTC" but the instrument list also includes a low-liquidity asset, the single limit may not be appropriate. | Human review: the doc must state explicitly whether limits are global or per-instrument, and if global, justify why a single value is safe across all listed instruments | Not formally tested |

## 3) Top 7 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Document exists but contains placeholder values ("TBD", "TODO", "to be determined") instead of real constraints | Human review; grep for TBD/TODO in the file | Reviewer must reject documents with unfilled placeholders; add a CI grep check | None (review-gated only) |
| 2 | Snapshot file diverges from source document (copy made at creation time, then source updated without re-copying) | `diff` between the two files at review time | Run `diff` as part of pass-flip verification | None (no automated check) |
| 3 | Document omits one of the four required sections (instruments/venues, position/loss limits, order rate/pacing, environments) | Acceptance criteria review against the four required topics | Checklist-based review; each acceptance criterion maps to one section | None (review-gated only) |
| 4 | Policy values are internally inconsistent (e.g., daily loss limit exceeds total account, rate limit in incompatible units, position limit contradicts instrument list) | Domain expert review | Cross-reference values against exchange/account constraints | None |
| 5 | Document is prose-only with no structured data (tables, concrete numbers), making P0-F (Machine Policy Loader) unable to derive `config/policy.json` from it | P0-F implementation fails or requires guesswork | Ensure the doc includes clearly labeled tables with numeric values that P0-F can reference | None (deferred to P0-F) |
| 6 | Numeric values present but units missing or ambiguous (e.g., "max position: 0.1" without specifying BTC vs. USD vs. contracts; "max order rate: 10" without specifying per-second vs. per-minute) | Human review of each numeric cell for unit labels. P0-F loader may misinterpret if units are unstated. | Reviewer must verify every numeric constraint has an explicit unit. Table column headers or cell values must include the unit (e.g., "BTC", "USD", "/sec"). Reject tables where units are implied or absent. | None (review-gated only) |
| 7 | Constraint values are set globally but the instrument list includes assets with vastly different characteristics (e.g., a 0.1 position limit is conservative for BTC but could represent significant exposure for an illiquid altcoin). A single set of limits applied uniformly across all instruments may be unsafe for some subset. | Domain expert review; cross-reference each limit against each listed instrument's market characteristics | The doc must explicitly state whether limits are global or per-instrument. If global, it must include a justification that the single value is conservative enough for the highest-risk instrument on the list. If per-instrument limits are needed, the table must break them out. | None (review-gated only) |

## 4) Open decisions (resolve before coding)

### Decision: Document format -- pure Markdown prose vs. structured data
- **What is ambiguous / missing**: The PRD says "Create launch policy doc" and the CONTRACT evidence is `docs/launch_policy.md`. It does not specify whether the doc must be machine-parseable or purely human-readable. However, P0-F ("Bind a machine-readable policy path + strict loader") will later need to derive values from somewhere.
- **Evidence**: CONTRACT.md Phase 0 table: P0-A says "Define explicit constraints"; P0-F says "Bind a machine-readable policy path + strict loader so runtime checks are not doc-only." Evidence files: `config/policy.json`, `tools/policy_loader.py`.
- **Options**:
  1. Option A -- Pure Markdown prose with tables for values. Human-readable, simple. P0-F must create `config/policy.json` separately, referencing this doc as the source of truth.
  2. Option B -- Markdown with an embedded YAML/JSON block. More complex for S0-000 but P0-F can extract directly.
- **Chosen**: A -- Pure Markdown prose with clearly structured tables containing numeric values. P0-F explicitly creates its own `config/policy.json`, so this doc serves as the human-readable authority.
- **Why not others**: Option B adds scope to S0-000 and pre-commits to a machine format before P0-F defines its schema requirements. The PRD touch scope lists only `.md` files.
- **Scope control**:
  - What we're NOT doing yet: machine-readable policy format (P0-F's responsibility).
  - What unblocks us if this choice is wrong: P0-F can parse the Markdown tables or reference the doc as authoritative source; no format lock-in.

### Decision: How specific must constraint values be?
- **What is ambiguous / missing**: The PRD says "explicit constraints" and CONTRACT says "Define explicit constraints on what the system is allowed to do." The word "explicit" is key but undefined -- does "max 5 BTC" suffice, or is "conservative limits" acceptable?
- **Evidence**: CONTRACT.md P0-A: "Define explicit constraints on what the system is allowed to do."
- **Options**:
  1. Option A -- Concrete numeric values for every constraint (e.g., "max position: 0.1 BTC", "daily loss limit: $500", "max order rate: 5/sec").
  2. Option B -- Qualitative descriptions with intent to refine later (e.g., "conservative limits appropriate for paper trading phase").
- **Chosen**: A -- Concrete numeric values. "Explicit" in CONTRACT.md means unambiguous and verifiable. P0-F needs actual numbers to enforce programmatically.
- **Why not others**: Option B defers the hard decisions and makes P0-F impossible to implement correctly. It also violates the spirit of "explicit."
- **Scope control**:
  - What we're NOT doing yet: per-environment differentiation of values (the doc notes which environments exist but uses a single set of limits initially).
  - What unblocks us if this choice is wrong: values are easy to revise; the document structure and completeness are what matter for downstream stories.

### Decision: What constitutes a "literal copy" for the snapshot?
- **What is ambiguous / missing**: The PRD says the snapshot "is literal copy of docs." Does "literal" mean byte-for-byte identical, or content-equivalent (e.g., with an added timestamp header)?
- **Evidence**: PRD acceptance criterion 5: "GIVEN evidence/phase0/policy/launch_policy_snapshot.md exists WHEN reviewed THEN is literal copy of docs."
- **Options**:
  1. Option A -- Byte-for-byte identical via `cp` command.
  2. Option B -- Content-equivalent, possibly with metadata annotation (date, commit hash).
- **Chosen**: A -- Byte-for-byte identical via file copy. "Literal copy" means literally identical content.
- **Why not others**: Option B introduces ambiguity about what "literal" means and makes `diff`-based verification unreliable.
- **Scope control**:
  - What we're NOT doing yet: automated CI enforcement of snapshot freshness.
  - What unblocks us if this choice is wrong: re-copy at any time; no downstream dependency on the snapshot's format or metadata.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

N/A -- no enforcing ATs. `enforcing_contract_ats: []`.

However, the PRD acceptance criteria are review-based, so the wrong-implementation analysis targets those criteria instead:

| Acceptance Criterion | Wrong impl that passes review | Why it's wrong | Tightening needed |
|---------------------|------------------------------|----------------|-------------------|
| "includes allowed instruments/venues" | Doc says "instruments: see exchange documentation for current list" with an external link | Delegates the constraint externally; the policy doc itself defines nothing. If the external link changes, the policy is silently void. | Reviewer must verify the doc contains an inline enumerated list of specific instruments, not external references |
| "includes max position/daily loss" | Doc says "max position: TBD pending risk review" | Satisfies "includes" literally (the topic is mentioned) but has no actionable value. P0-F cannot bind to "TBD". | Reviewer must verify numeric values are present, not placeholders. Grep for TBD/TODO before pass-flip. |
| "includes max order rate/pacing" | Doc includes a section header "Order Rate and Pacing" with a single sentence: "Orders will be paced appropriately." | Section exists; no actionable constraint is defined. | Reviewer must verify each section has at least one concrete numeric limit. |
| "includes environments (DEV/STAGING/PAPER/LIVE)" | Doc lists only "LIVE" and "DEV" | Technically includes "environments" but misses STAGING and PAPER, which are explicitly required by the story description. | Reviewer must verify all four environments named in the story description appear. |
| "is literal copy of docs" | Snapshot was copied at creation time, then source doc was updated without re-copying | At time of creation it was literal; at time of review/pass-flip it is stale. The staleness is invisible without an explicit diff. | Run `diff` between source and snapshot at pass-flip time, not just at creation time. |

- [ ] Every AT has at least one wrong impl identified -- N/A (no formal ATs), but all 5 acceptance criteria analyzed above
- [ ] Every wrong impl is blocked by a tightened AT or new test -- YELLOW: no machine gate exists, only review discipline
- [ ] No AT remains where a wrong impl is easier than the correct one -- N/A

## 6) Proof plan (AT -> enforcement -> tests)

N/A -- no enforcing ATs. `enforcing_contract_ats: []`, `enforcement_point: ""`, `implementation_tests: []`.

There is no runtime enforcement point and no automated test suite for this story. The "proof" is entirely review-based:

| Acceptance Criterion | Enforcement | Proving evidence | Automated? |
|---------------------|-------------|-----------------|------------|
| File exists at `docs/launch_policy.md` | File system | `ls docs/launch_policy.md` exits 0 | Could be, but is not |
| Contains instruments/venues section | Human review | Reading the document | No |
| Contains position/loss limits section | Human review | Reading the document | No |
| Contains order rate/pacing section | Human review | Reading the document | No |
| Contains environments section | Human review | Reading the document | No |
| Snapshot is literal copy | diff check | `diff docs/launch_policy.md evidence/phase0/policy/launch_policy_snapshot.md` exits 0 | Could be, but is not |

**What SHOULD exist but does not:**
- A script in `plans/` that verifies file existence and runs `diff` on the snapshot
- A grep-based check for required section headers (instruments, position, order rate, environments)
- These would elevate the story from a pure review-gate to semi-automated verification

- [ ] Every safety-critical AT has TRIP + NON-TRIP -- N/A (no safety-critical ATs, no runtime behavior)
- [ ] Every test proves causality (not just existence) -- N/A (no tests)
- [ ] Each AT isolates one clause -- N/A (no ATs)
- [ ] No CLAIMED-NOT-PROVEN entries without a plan to fix -- N/A

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: None directly. This is a policy document with no runtime behavior. However, if the policy document has incorrect, missing, or vague constraints, later stories (P0-F Machine Policy Loader, CSP PolicyGuard) may be misconfigured. The blast radius is indirect and deferred -- a bad policy doc does not lose money today but may cause incorrect limits at runtime when downstream stories consume it.
- **Fail-closed cap on loss**: N/A -- no trading logic exists at this stage. The fail-closed cap comes from downstream consumers of this policy (P0-F, PolicyGuard) which have their own independent fail-closed behavior. Even if this doc is wrong, those systems default to ReduceOnly.
- **Drift metric**: N/A -- static document. The drift risk is that the document becomes stale relative to actual system configuration over time, but this is a process/governance concern, not a runtime metric.
- **Loss boundary**: N/A.
- **Rollback plan**: `git revert` the commit that adds the policy documents. No downstream runtime behavior depends directly on `docs/launch_policy.md` (P0-F creates its own `config/policy.json`).

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None. This creates a documentation artifact; no code gates reference `docs/launch_policy.md` at runtime.
- **If conflict with CONTRACT.md**: No conflict. P0-A explicitly requires this document to exist with the specified content.
- Files with recent churn or shared ownership: The `docs/` directory may be populated by other P0-* stories concurrently (P0-B `env_matrix.md`, P0-C `keys_and_secrets.md`, P0-D `break_glass_runbook.md`). No conflict expected since each story writes to a distinct file path.
- Struct fields I'm assuming exist: None (no code changes in this story).
- State machine transitions affected: None.
- **Cross-story dependency note**: P0-F (Machine Policy Loader, story S0-005) consumes the policy values defined here. If the values in `docs/launch_policy.md` are vague, use non-standard units, or are structured in a way that cannot be referenced, P0-F implementation becomes harder. This is the primary interface risk.
- **S0-005 interface contract (explicit)**: S0-000 produces `docs/launch_policy.md` as pure Markdown prose with tables (Decision 1 above). S0-005 validates and loads `config/policy.json`. The gap between these two artifacts is critical: no story currently owns the transformation from Markdown tables to JSON. If `config/policy.json` is hand-created with values that disagree with `docs/launch_policy.md`, S0-005's strict loader will happily validate a policy file that contradicts the launch policy doc. To reduce this risk, this document must use:
  - Consistent, unambiguous table column names that S0-005 can reference as the source of truth (e.g., `max_position_btc`, `daily_loss_limit_usd`, `max_order_rate_per_sec`)
  - Explicit units in every numeric cell (see Assumption 9, FM-6)
  - A clear statement of whether limits are global or per-instrument (see Assumption 10, FM-7)
  - S0-005's premortem should include a "debt intake" section that picks up these interface requirements and verifies the transformation from this doc to `config/policy.json` preserves all values faithfully.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (S0-000 is the first story in the sequence)
Reused Guardrail: NONE (no prior postmortem exists)

- Carry-forward from prior postmortem: N/A -- first story, no prior postmortem.
- What will slow me down: Deciding on concrete numeric values for position limits, daily loss limits, and order rate caps. These require domain judgment about what is "safe enough for paper trading" -- the temptation is to punt with placeholder values, which violates "explicit."
- Exploit: Use deliberately conservative (overly restrictive) values for the initial policy. Being too tight is safe and can be relaxed later; being too loose is dangerous. Example: tiny position limits (0.01 BTC), aggressive rate limits (1 order/sec), low daily loss ($100). These are safe defaults that satisfy "explicit" without requiring deep domain analysis.
- Smallest fix that prevents it next time: Establish a policy review cadence documented in the policy doc itself (e.g., "review and update policy values at each phase gate transition") so stale or overly conservative values get revisited.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: The story itself is low-risk and well-scoped, but there are no automated gates -- all acceptance criteria are review-based ("WHEN reviewed THEN includes X"). The lack of enforcing ATs means wrong implementations (placeholder values, stale snapshots, missing sections) can only be caught by human diligence during review, not by CI. All gaps are explicitly deferred with owners and target slices below.

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| No automated file-existence check for `docs/launch_policy.md` | Low | Pure doc story; automation overhead not justified for one-time file creation | S0-000 reviewer | P0-F (S0-005, when loader needs to find the file) | Script that verifies `docs/launch_policy.md` exists and is non-empty |
| No automated diff check for snapshot freshness | Low | Snapshot is created once and rarely updated; manual diff at review time is sufficient for now. **Cross-cutting note**: this same gap exists in S0-001 (FM-5) and all other Phase 0 doc stories. A single CI script that diffs all `docs/*.md` against their corresponding `evidence/phase0/*/` snapshots would close this systemically. No such script exists today; elevated to cross-cutting debt. | S0-000 reviewer | Cross-cutting CI hardening story (not owned by any single S0 story) | CI step that iterates all Phase 0 evidence snapshots and runs `diff` against canonical docs |
| No machine-verifiable check for required sections | Low | Content completeness is inherently a human judgment call; section-header grep is fragile and easy to game | S0-000 reviewer | P0-F (S0-005, structured policy) | P0-F's loader validates required fields exist in `config/policy.json`, which back-pressures completeness onto this doc |
| Acceptance criteria use "reviewed" (human gate) not "validated" (machine gate) | Low | By design for a policy/documentation story; P0-F adds the machine gate for runtime enforcement | PRD design | P0-F (S0-005) | P0-F loader tests serve as the machine gate for policy completeness |
| Unit ambiguity in constraint values not machine-checked | Low | Units are a review-time concern; the doc format (Markdown tables) does not enforce unit presence. FM-6 detection is purely human. | S0-000 reviewer | P0-F (S0-005, loader schema should require unit-tagged fields) | P0-F schema validation rejects values without explicit units; back-pressures unit clarity onto this doc |
| Per-instrument vs. global limit applicability not enforced | Low | Decision on global vs. per-instrument is a policy choice, not a structural property that can be machine-verified at the doc level. | S0-000 reviewer | P0-F (S0-005, loader can validate per-instrument overrides if present) | P0-F schema supports both global and per-instrument limits; validation rejects ambiguous scope |

YELLOW with all debt tracked and assigned to target slices. No RED blockers.

**Exit criteria (definition of done, before I start):**
- [x] S1 clause audit: every AT traced to normative clause -- N/A (no ATs), P0-A clause identified and quoted
- [x] S2 all assumptions validated or killed -- 10 assumptions documented; 3 deferred to P0-F with explicit rationale; 3 added per cross-review (reviewer competence, unit clarity, per-instrument applicability)
- [x] S3 all failure modes have detection + mitigation -- 7 modes identified, all have detection path (review or diff); 2 added per cross-review (unit ambiguity FM-6, per-instrument scope FM-7)
- [x] S4 all decisions resolved, grounded in evidence -- 3 decisions resolved with CONTRACT.md references
- [x] S5 wrong impl gate: every AT tightened -- N/A (no ATs); 5 wrong impls identified for acceptance criteria with tightening notes
- [x] S6 proof plan: TRIP + NON-TRIP for all safety-critical ATs -- N/A (no safety-critical ATs, no runtime behavior)
- [x] S7 loss_mode documented with fail-closed boundary + rollback plan -- documented as N/A for policy story; rollback is git revert
- [x] S8 conflict scan clean (no CONTRACT.md conflicts) -- clean; cross-story dependency on P0-F noted; S0-005 interface contract made explicit per cross-review
- [x] No new debt without owner + target slice -- 6 debt items tracked in register with owners and target slices (2 added per cross-review)
