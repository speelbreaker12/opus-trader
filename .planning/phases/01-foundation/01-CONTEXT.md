# Phase 01: Foundation - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning
**Source:** User-provided context (`~/.claude/plans/witty-juggling-dongarra.md`)

<domain>
## Phase Boundary

Deliver a safe, fail-closed CI enforcement uplift that closes current governance gaps in branch protection and workflow gating:
- make `crossref-gate` enforceable with proven burn-in
- enable `prd-story-gate` in CI
- add and verify `.github/CODEOWNERS`
- tighten branch protection and rollback safety with deterministic checks and artifacts

Scope includes preflight checks, staged rollout, verification, and rollback safeguards.

</domain>

<decisions>
## Implementation Decisions

### Repository Safety + Preflight (Locked)
- Require authenticated admin permission before mutation (`permissions.admin == true`).
- Fail closed if `main` branch is missing.
- Fail closed on conflicting repository rulesets unless explicit override (`ALLOW_RULESET_COMPAT=1`) is accepted.
- Require `crossref-gate` job name consistency against `.github/workflows/ci.yml` before enforcing checks.
- Require burn-in evidence before promoting `crossref-gate` to required status checks.

### Branch Protection Snapshot + Rollback (Locked)
- Capture raw branch protection snapshot before changes.
- Build normalized restore payload including `restrictions`, review settings, admin enforcement, force-push/delete flags, linear history, conversation resolution, lock/create/fork-sync flags.
- Deep-validate restore payload for unexpected nulls.
- Store artifacts under persistent repo path (`artifacts/ci_enforcement_backups/`), not temporary paths.

### Required Status Checks (Locked)
- Merge existing status checks with explicit `crossref-gate` entry.
- Pin `crossref-gate` to GitHub Actions app (`app_id: 15368`).
- Preserve existing required checks while adding new requirement.

### CODEOWNERS (Locked)
- Create `.github/CODEOWNERS` from verified, existing repo paths.
- Require deterministic post-creation assertions (owner rule count + key path checks).
- Require CODEOWNERS file existence on `main` before enabling code-owner review gate.

### CI Workflow Gate Enablement (Locked)
- Remove `false &&` suppression in `prd-story-gate` condition.
- Validate YAML syntax explicitly after edit.
- Run repo quick verification after CI workflow edit.

### Operational Safety / Freeze Avoidance (Locked)
- Address reviewer/admin deadlock risk with explicit break-glass guidance and rollback readiness.
- Use atomic completion verification at end of rollout.

### Claude's Discretion
- Exact script/module placement for helper automation.
- Whether to stage changes across one or multiple PRs.
- Formatting details in docs/artifacts as long as checks remain deterministic and fail-closed.

</decisions>

<specifics>
## Specific Ideas

- Team split for execution:
  - `gate-enabler`: required status checks merge/update
  - `codeowners-writer`: CODEOWNERS authoring + assertions
  - `ci-fixer`: `prd-story-gate` activation + YAML/verify checks
- Preflight should include collaborator permission endpoint validation for owner handle.
- Burn-in criteria should require at least 3 successful recent `crossref-gate` runs and zero non-skipped failures in the observed window.
- Verification must include endpoint-level checks for both status checks and PR review configuration.

</specifics>

<deferred>
## Deferred Ideas

- Broader governance hardening beyond current CI/CODEOWNERS branch-protection package.
- Non-essential process automation that does not reduce current enforcement risk.

</deferred>

---

*Phase: 01-foundation*
*Context gathered: 2026-03-04 from user-provided planning document*
