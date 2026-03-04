---
quick_task: 2
slug: execute-ci-enforcement-hardening-from-us
type: quick
autonomous: false
files_modified:
  - .github/workflows/ci.yml
  - .github/CODEOWNERS
  - scripts/ci_enforcement/preflight_snapshot.sh
  - scripts/ci_enforcement/apply_branch_protection.sh
  - scripts/ci_enforcement/verify_branch_protection.sh
  - docs/runbooks/ci_enforcement.md
requirements:
  - REQ-CI-ENFORCEMENT
must_haves:
  truths:
    - "`prd-story-gate` is enabled in CI without `false &&` suppression."
    - "CODEOWNERS exists with verified critical-path ownership rules."
    - "`crossref-gate` is configured as a required status check with GitHub Actions app_id 15368."
    - "Branch protection restore payload is artifact-backed and null-validated."
  artifacts:
    - path: "scripts/ci_enforcement/preflight_snapshot.sh"
      provides: "Fail-closed preflight + snapshot + restore payload generation"
    - path: "scripts/ci_enforcement/apply_branch_protection.sh"
      provides: "Deterministic branch-protection patch application"
    - path: "docs/runbooks/ci_enforcement.md"
      provides: "Operator-safe execution and rollback instructions"
  key_links:
    - from: "scripts/ci_enforcement/preflight_snapshot.sh"
      to: "scripts/ci_enforcement/apply_branch_protection.sh"
      via: "Snapshot-before-mutation workflow"
    - from: ".github/workflows/ci.yml"
      to: "scripts/ci_enforcement/verify_branch_protection.sh"
      via: "crossref-gate job name consistency check"
---

<objective>
Execute CI enforcement hardening from `/Users/admin/.claude/plans/witty-juggling-dongarra.md` with fail-closed safeguards.
</objective>

<context>
@/Users/admin/.claude/plans/witty-juggling-dongarra.md
@.planning/STATE.md
@.github/workflows/ci.yml
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add fail-closed preflight + snapshot automation</name>
  <files>scripts/ci_enforcement/preflight_snapshot.sh, docs/runbooks/ci_enforcement.md</files>
  <action>Create a deterministic preflight script that validates gh auth/admin rights, main branch existence, ruleset compatibility guard, crossref-gate naming, burn-in evidence, and generates `artifacts/ci_enforcement_backups/protection-raw-*.json` plus `protection-restore.json` with null-depth validation.</action>
  <verify>
    <automated>bash scripts/ci_enforcement/preflight_snapshot.sh --dry-run</automated>
  </verify>
  <done>Preflight script and runbook exist with fail-closed exits and artifact paths.</done>
</task>

<task type="auto">
  <name>Task 2: Apply repository hardening edits (CODEOWNERS + CI gate enablement)</name>
  <files>.github/CODEOWNERS, .github/workflows/ci.yml</files>
  <action>Create CODEOWNERS with verified repo paths/owner mapping and enable `prd-story-gate` by removing suppression in ci.yml while preserving condition semantics. Add deterministic post-edit checks for owner rule count, key paths, and YAML parse validity.</action>
  <verify>
    <automated>python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML syntax OK')" &amp;&amp; ! rg -n 'false &&' .github/workflows/ci.yml &amp;&amp; bash -lc 'count=$(grep -c "@speelbreaker" .github/CODEOWNERS); [[ "$count" -eq 14 ]]'</automated>
  </verify>
  <done>CI workflow and CODEOWNERS satisfy validation checks.</done>
</task>

<task type="auto">
  <name>Task 3: Apply and verify branch-protection enforcement</name>
  <files>scripts/ci_enforcement/apply_branch_protection.sh, scripts/ci_enforcement/verify_branch_protection.sh, docs/runbooks/ci_enforcement.md</files>
  <action>Add application and verification scripts that patch required status checks (`verify`, `crossref-gate` app_id 15368), enforce code owner reviews, and enable admin enforcement. Verify results via GitHub API and provide rollback command using saved restore payload.</action>
  <verify>
    <automated>bash scripts/ci_enforcement/apply_branch_protection.sh --repo speelbreaker12/opus-trader --branch main --check-only &amp;&amp; bash scripts/ci_enforcement/verify_branch_protection.sh --repo speelbreaker12/opus-trader --branch main</automated>
  </verify>
  <done>Branch protection is verified against expected policy, with rollback path documented.</done>
</task>

</tasks>

<verification>
Run `./plans/verify.sh quick` after file changes.
</verification>

<output>
Create `.planning/quick/2-execute-ci-enforcement-hardening-from-us/2-SUMMARY.md` with evidence and any blocking conditions.
</output>
