---
phase: 01
slug: foundation
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-03-04
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust `cargo test` + workflow harness gates |
| **Config file** | `Cargo.toml`, `plans/verify_fork.sh` |
| **Quick run command** | `./plans/verify.sh quick` |
| **Full suite command** | `./plans/verify.sh full` |
| **Estimated runtime** | ~300 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./plans/verify.sh quick`
- **After every plan wave:** Run `./plans/verify.sh full`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 300 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | REQ-1 | unit/integration | `cargo test --package soldier_core test_dispatch_map` | ✅ | ⬜ pending |
| 01-01-02 | 01 | 1 | REQ-1 | unit/integration | `cargo test --package soldier_core test_preflight_invalid` | ✅ | ⬜ pending |
| 01-02-01 | 02 | 1 | REQ-2 | integration | `cargo test --package soldier_infra test_dispatch_durability` | ✅ | ⬜ pending |
| 01-02-02 | 02 | 1 | REQ-2 | unit | `cargo test --package soldier_core test_idempotency` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 300s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
