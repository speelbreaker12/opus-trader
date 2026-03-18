# ROADMAP

## Phase 1: Foundation
**Requirements:** [REQ-1, REQ-2]
- [ ] All exchange dispatch routes through the single dispatch chokepoint.
- [ ] WAL/intent ledger prevents duplicates across crash/restart/reconnect.
- [ ] Determinism tests pass (hashing/quantization/labels).
- [ ] Illegal orders are rejected before any exchange API call.

**Plans:** 2 plans
Plans:
- [ ] 01-foundation-01-PLAN.md — Dispatch chokepoint and preflight rejections
- [ ] 01-foundation-02-PLAN.md — WAL crash safety and determinism testing