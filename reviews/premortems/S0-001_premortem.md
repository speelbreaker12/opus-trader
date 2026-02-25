# Story Premortem: S0-001

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S0-001 — P0-B Environment Isolation
- Contract clause(s): §Phase 0, P0-B (Environment Isolation)
- Acceptance tests: None (no `enforcing_contract_ats` claimed)
- Touch scope: `docs/env_matrix.md`, `evidence/phase0/env/env_matrix_snapshot.md`
- **Risk rating**: LOW
  - Documentation-only story. No runtime code, no trading logic, no safety gates.
  - However, completeness matters: a misleading or incomplete env matrix could cause an operator to misconfigure environments, leading to cross-env leakage (e.g., LIVE keys used in DEV).

## 1) Clause audit (contract -> AT traceability)

N/A -- no enforcing ATs. The story's `enforcing_contract_ats` is an empty list.

The relevant CONTRACT.md clause is the Phase 0 table entry for P0-B:

| Clause | Contract section | Clause text (abbreviated) | Type | Testable? |
|--------|-----------------|---------------------------|------|-----------|
| P0-B | Phase 0: Operational Prerequisites | "Environment Isolation -- Document environment separation (DEV/STAGING/PAPER/LIVE). Evidence Required: `docs/env_matrix.md`" | MUST (Non-Negotiable, Phase 0) | Structurally: file exists and covers the four environments. But no formal AT anchor exists in CONTRACT.md for this. |

**What SHOULD be tested (even though no AT is claimed):**
- The env_matrix document should list all four environments (DEV, STAGING, PAPER, LIVE).
- Each environment should have its own exchange account (no shared accounts across environments that handle real funds).
- Key permissions should be documented per environment (read-only for DEV, trade-only for PAPER, etc.).
- Secrets storage location should be specified (not committed to git, not shared across envs).
- The evidence snapshot should be a faithful copy of the canonical document.

- [x] Every claimed AT traced to a normative clause -- N/A (no ATs claimed)
- [x] No informational-only ATs counted as enforcement -- N/A

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Four environments exist: DEV, STAGING, PAPER, LIVE | If the actual infrastructure uses different names (e.g., "TEST" instead of "STAGING", or "SANDBOX" instead of "PAPER"), the document misrepresents reality | Manual review: compare env_matrix against actual infrastructure config | Not yet |
| 2 | Each environment has a separate exchange account | If two environments share an account (e.g., DEV and STAGING share the same API key set), cross-env leakage is possible | Verify account IDs are distinct per environment row in the matrix | Not yet |
| 3 | The evidence snapshot is a literal copy of the canonical doc | If the snapshot diverges from `docs/env_matrix.md` (e.g., snapshot was taken from an earlier draft), the evidence is stale | `diff docs/env_matrix.md evidence/phase0/env/env_matrix_snapshot.md` should show zero differences, or snapshot should clearly state its capture date and match | Not yet |
| 4 | Key permissions are actually enforced at the exchange level | The document says "read-only" for DEV keys, but if the exchange API key actually has trade permissions, the doc is aspirational not factual | Verify against exchange key management UI or API key metadata export | Not yet |
| 5 | Secrets are not committed to the repository | If `.env` files, API keys, or secrets appear in git history, the "secrets stored in X" claim is incomplete | `git log --all -p -- '*.env' 'secrets*' '*.key'` should return empty; `.gitignore` should exclude secret files | Not yet |
| 6 | Environments are already provisioned (not aspirational) | If some environments (e.g., STAGING, PAPER) do not yet exist, the matrix documents intent rather than reality. Reviewers may treat aspirational rows as verified, leading to false confidence in isolation. | Each environment row must be marked VERIFIED or PLANNED. PLANNED rows must include a provisioning timeline or ticket. Review rejects any row that lacks this designation. | Not yet |

## 3) Top 6 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | env_matrix.md lists environments but omits one (e.g., PAPER missing) | Manual review against PRD acceptance criteria which explicitly lists DEV/STAGING/PAPER/LIVE | Acceptance criterion #1 requires all four environments be listed | None (manual review) |
| 2 | Document claims separate accounts but reality is shared accounts (aspirational documentation) | Only detectable by cross-referencing exchange account settings | **Self-contained**: Each environment row in the matrix must be marked **VERIFIED** (confirmed against exchange admin) or **PLANNED** (not yet provisioned), so reviewers can distinguish documented reality from documented intent. Rows marked PLANNED must include a provisioning ticket or timeline. **Cross-story**: P0-C (Keys & Secrets Baseline) should independently verify account separation for VERIFIED rows. | None (manual review; VERIFIED/PLANNED tagging is the self-contained gate) |
| 3 | Key permissions column is vague or missing (e.g., "see admin console" instead of listing actual permissions) | Review of acceptance criterion #3 which requires permissions per env | Reviewer must reject vague entries | None (manual review) |
| 4 | Secrets storage location says "environment variables" but does not specify which secret manager or how they are injected | Acceptance criterion #4 requires specifying WHERE secrets are stored | Vague answers should be rejected at review | None (manual review) |
| 5 | Evidence snapshot is created but later the canonical doc is updated, leaving the snapshot stale | `diff` between the two files diverges over time | Could add a CI check or a note in env_matrix.md to update evidence on change; but this is documentation-only so no automated gate | None (process discipline) |
| 6 | **Information leakage: real exchange account IDs or sensitive identifiers committed to git in `docs/env_matrix.md`** | The env matrix is committed to a git repository. If it includes real exchange account IDs, API key prefixes, IP allowlists, or server hostnames, it becomes a reconnaissance target for an attacker with repo access. | Review the matrix before merge: account references should use opaque labels (e.g., "DEV-account-1") or partial identifiers (last 4 chars), never full account IDs. If full IDs are needed for operational use, store them in a non-git-committed operational doc and reference it from the matrix. | None (manual review at merge time) |

## 4) Open decisions (resolve before coding)

### Decision: What constitutes "where secrets are stored"
- **What is ambiguous / missing**: The acceptance criteria say the matrix should show "where secrets are stored" but do not define granularity. Is it enough to say "1Password" or must it specify vault name, item name, injection mechanism?
- **Evidence**: PRD acceptance criteria #4: "GIVEN docs/env_matrix.md exists WHEN reviewed THEN shows where secrets are stored." CONTRACT.md P0-B: "Document environment separation (DEV/STAGING/PAPER/LIVE)."
- **Options**:
  1. Option A -- Specify storage system only (e.g., "1Password", "AWS Secrets Manager", "env vars on deploy host"). Minimal but sufficient for the isolation claim. Verification: reviewer can confirm the system exists.
  2. Option B -- Specify storage system plus injection path (e.g., "1Password vault 'Trading-DEV', injected via `op run` in deploy script"). More actionable for incident response. Verification: reviewer can trace the full path.
- **Chosen**: A -- The story scope is "document environment isolation," not "fully trace secret injection pipelines." Option B is better but exceeds the story's purpose.
- **Why not others**: Option B risks scope creep into P0-C (Keys & Secrets Baseline) territory.
- **Scope control**:
  - What we're NOT doing yet: secret rotation procedures, injection mechanism details (P0-C scope).
  - What unblocks us if this choice is wrong: the matrix can be extended with a "injection method" column later.

### Decision: Evidence snapshot format
- **What is ambiguous / missing**: PRD says evidence is a "literal copy of docs." Should it be a symlink, a git-tracked copy, or a generated artifact?
- **Evidence**: PRD acceptance criteria #5: "GIVEN evidence/phase0/env/env_matrix_snapshot.md exists WHEN reviewed THEN is literal copy of docs."
- **Options**:
  1. Option A -- Manually copy the file content into the evidence path. Simple; reviewable via diff.
  2. Option B -- Symlink to the canonical doc. Always in sync but not truly "evidence" (it is the live doc, not a point-in-time snapshot).
  3. Option C -- Script that copies and timestamps. Automated but adds tooling overhead for a doc-only story.
- **Chosen**: A -- A literal file copy is the most honest "evidence" -- it captures the state at the time of review. A symlink (B) defeats the purpose of evidence (point-in-time capture). A script (C) is overengineering for one file.
- **Why not others**: B is not a snapshot (it is a live reference). C is premature automation.
- **Scope control**:
  - What we're NOT doing yet: automated evidence collection scripts.
  - What unblocks us if this choice is wrong: can replace manual copy with automation in a future story.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

N/A -- no enforcing ATs. The story claims no `enforcing_contract_ats`.

However, reasoning about what wrong implementations could pass the acceptance criteria as written:

| Acceptance criterion | Wrong impl that passes | Why it's wrong | Tightening needed |
|---------------------|----------------------|----------------|-------------------|
| "lists each environment (DEV/STAGING/PAPER/LIVE)" | Document contains the four words as a list but with no actual data in each row (empty table with headers only) | Existence of names is not the same as documenting isolation | Criterion should require non-empty values in each cell per environment |
| "shows which exchange account per env" | Document says "TBD" or "see admin" for each account | Satisfies "shows" literally but provides no actual information | Criterion should require concrete account identifiers or explicit "not yet provisioned" with a follow-up ticket |
| "shows key permissions per env" | Lists "full permissions" for all environments including DEV | Technically lists permissions, but "full permissions on DEV" violates isolation intent | Criterion should require least-privilege justification or flag full-permission entries |
| "shows where secrets are stored" | Says "stored securely" without naming a system | Technically answers "where" but is not actionable | Criterion should require naming a specific storage system |
| "evidence is literal copy of docs" | Evidence file exists but was copied from a different version of the doc (e.g., draft without LIVE row) | Evidence exists but does not match the canonical doc | Add a `diff` check between the two files as part of verification |

- [x] Every AT has at least one wrong impl identified -- N/A (no formal ATs), but wrong impls analyzed against acceptance criteria
- [x] Every wrong impl is blocked by a tightened AT or new test -- tightenings identified above as recommendations
- [x] No AT remains where a wrong impl is easier than the correct one -- N/A

## 6) Proof plan (AT -> enforcement -> tests)

N/A -- no enforcing ATs. There is no enforcement point (no runtime gate, no code path). This is a documentation/policy story.

**What SHOULD exist for a complete proof chain:**

| Check | Method | Automated? |
|-------|--------|------------|
| `docs/env_matrix.md` exists | `test -f docs/env_matrix.md` | Could be (CI file-existence check) |
| Document lists all four environments | `grep -c 'DEV\|STAGING\|PAPER\|LIVE' docs/env_matrix.md` >= 4 | Could be (fragile but better than nothing) |
| Evidence snapshot matches canonical doc | `diff docs/env_matrix.md evidence/phase0/env/env_matrix_snapshot.md` | Could be (CI diff check) |
| Each environment row has non-empty values for account, permissions, secrets | Manual review | No -- content quality requires human judgment |

None of these are currently wired as ATs in CONTRACT.md. This is a gap but is consistent with the story's `enforcing_contract_ats: []` declaration.

- [x] Every safety-critical AT has TRIP + NON-TRIP -- N/A (no safety-critical ATs; documentation story)
- [x] Every test proves causality (not just existence) -- N/A
- [x] Each AT isolates one clause -- N/A
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix -- N/A

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Indirect risk only. If the environment matrix is wrong or incomplete, an operator could misconfigure environments (e.g., point a DEV instance at LIVE keys). This could cause unintended trades on the live exchange. However, the matrix itself is documentation -- it does not enforce isolation at runtime.
- **Fail-closed cap on loss**: N/A -- this is a policy/documentation story. Runtime isolation is enforced by separate API keys and configs, not by this document. The document records what should already be true.
- **Drift metric**: N/A -- no runtime behavior to monitor. The drift risk is that the document becomes stale as infrastructure evolves. Could mitigate by adding a "last-verified" date to the matrix.
- **Loss boundary**: N/A.
- **Rollback plan**: `git revert` the commit adding/modifying `docs/env_matrix.md` and `evidence/phase0/env/env_matrix_snapshot.md`. No runtime impact.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None. This story creates documentation only. No runtime invariants or gates are touched.
- **If conflict with CONTRACT.md**: No conflict. P0-B explicitly requires `docs/env_matrix.md` as evidence. This story fulfills that requirement.
- Files with recent churn or shared ownership: `docs/env_matrix.md` is net-new (created by this story). `evidence/phase0/env/` directory may not yet exist.
- Struct fields I'm assuming exist: None (no code).
- State machine transitions affected: None.

**Potential conflict with P0-C**: The keys & secrets baseline (P0-C) may overlap with the "key permissions" and "secrets storage" columns in the env matrix. The boundary is: S0-001 documents WHAT exists per environment; P0-C documents HOW keys are managed (rotation, least-privilege proof). Overlap in key permissions column should be kept to summary level in env_matrix, with P0-C providing the detailed treatment.

**Overlap with S0-002 on secrets storage** *(added from cross-review)*: S0-001 has acceptance criterion "shows where secrets are stored" and S0-002 (P0-C Keys & Secrets Baseline) is entirely about key management including secret storage. If S0-001 says secrets are in "1Password" and S0-002 says "AWS Secrets Manager" (or provides more granular detail implying a different system), the two documents contradict each other. **Resolution**: S0-001's "where secrets are stored" column must be a summary-level reference that is consistent with S0-002's authoritative detail. If S0-002 has already been implemented, S0-001 should reference S0-002's document directly (e.g., "See `docs/keys_and_secrets.md` for details; summary: 1Password"). If S0-001 is implemented first, S0-002 must treat S0-001's summary as a constraint to align with or explicitly supersede with a documented rationale. Neither document should independently assert secrets storage location without cross-referencing the other.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (this is S0-001, no prior story postmortem to reference)
Reused Guardrail: NONE

- Carry-forward from prior postmortem: N/A
- What will slow me down: Gathering accurate information about actual exchange accounts, key permissions, and secrets storage for each environment. This requires access to infrastructure configuration or operator knowledge -- it cannot be fabricated.
- Exploit: If real infrastructure details are not yet available (e.g., STAGING and PAPER environments not yet provisioned), document what IS provisioned and mark unprovisioned environments as "PLANNED" with clear placeholders. Use the VERIFIED/PLANNED convention from FM-2 and Assumption 6.
- Smallest fix that prevents it next time: Establish a convention that environment matrix rows must be marked "VERIFIED" (confirmed against exchange admin) or "PLANNED" (not yet provisioned) so reviewers can distinguish documented reality from documented intent.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- Not GREEN because: (1) no enforcing ATs exist in CONTRACT.md for P0-B, meaning there is no automated gate to prevent a vacuous or incomplete document from passing; (2) the acceptance criteria as written can be satisfied by low-quality documentation (see wrong impl analysis in section 5).
- Not RED because: (1) this is a LOW-risk documentation story with no runtime impact; (2) the wrong impls are catchable by human review; (3) the absence of formal ATs is consistent with the story's design (policy/documentation, not enforcement).

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| No formal AT in CONTRACT.md for P0-B env matrix completeness | Low | P0-B is a documentation prerequisite, not a runtime gate; adding an AT anchor would be appropriate but is out of scope for this story | S0-001 author | Future P0 hardening slice | AT checking: file exists, lists 4 envs, each row has non-empty account/permissions/secrets columns |
| Acceptance criteria accept vacuous docs | Low | Criteria use "shows" and "lists" which can be satisfied by placeholder text; tightening requires PRD amendment | S0-001 author | PRD amendment | Amend criteria to require non-empty, concrete values per cell |
| Evidence snapshot can drift from canonical doc | Low | No automated check that snapshot matches source doc | S0-001 author | CI/verify.sh enhancement | Add `diff` check between `docs/env_matrix.md` and `evidence/phase0/env/env_matrix_snapshot.md` to verify.sh |

YELLOW with untracked debt (no target slice) = RED. All debt items above have target slices.

**Exit criteria (definition of done, before I start):**
- [x] S1 clause audit: every AT traced to normative clause -- N/A (no ATs); P0-B clause identified
- [x] S2 all assumptions validated or killed -- 6 assumptions documented with validation methods
- [x] S3 all failure modes have detection + mitigation -- 6 failure modes with detection paths
- [x] S4 all decisions resolved, grounded in evidence -- 2 decisions resolved
- [x] S5 wrong impl gate: every AT tightened, no easy wrong impl survives -- N/A (no ATs); wrong impls analyzed against acceptance criteria with tightening recommendations
- [x] S6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN -- N/A (no safety-critical ATs)
- [x] S7 loss_mode documented with fail-closed boundary + rollback plan -- documented (N/A for policy story)
- [x] S8 conflict scan clean (no CONTRACT.md conflicts) -- clean, P0-C boundary noted, S0-002 secrets-storage overlap documented with reconciliation mechanism
- [x] No new debt without owner + target slice -- 3 debt items, all tracked
