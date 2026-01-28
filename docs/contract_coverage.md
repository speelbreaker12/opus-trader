# Contract Coverage Matrix

Generated: 2026-01-27 16:47:18Z

## Anchors

- ✅ **Anchor-001** — PolicyGuard Mode Precedence → S1-001
- ✅ **Anchor-002** — Runtime F1 Certification Gate → S1-000
- ✅ **Anchor-003** — EvidenceGuard Blocks Opens on Evidence Chain Failure → S4-003
- ✅ **Anchor-004** — TruthCapsule Timing (RecordedBeforeDispatch) → S4-003
- ✅ **Anchor-005** — Decision Snapshots Required for Replay → S4-003
- ✅ **Anchor-006** — WAL Durability (Record Before Dispatch) → S4-000
- ✅ **Anchor-007** — Trade-ID Registry Deduplication → S4-002
- ✅ **Anchor-008** — Disk Watermark Actions → S1-010
- ✅ **Anchor-009** — AGGRESSIVE Patches Require Human Approval → S1-000
- ✅ **Anchor-010** — Bunker Mode on Network Jitter → S1-004
- ✅ **Anchor-011** — TLSM Never Panics on Out-of-Order Events → S1-003
- ✅ **Anchor-012** — Canary Rollout Abort Triggers Rollback → S1-004
- ✅ **Anchor-013** — No Market Orders Policy → S3-000
- ✅ **Anchor-014** — Emergency Close Has Hedge Fallback → S4-000
- ✅ **Anchor-015** — Watchdog Triggers ReduceOnly via POST Endpoint → S1-002
- ✅ **Anchor-016** — Exchange Health Monitor Blocks Opens Before Maintenance → S1-003
- ✅ **Anchor-017** — Atomic Churn Circuit Breaker Prevents Fee Death-Spiral → S1-004
- ✅ **Anchor-018** — Pending Exposure Reservation Prevents Double-Spend → S1-004
- ✅ **Anchor-019** — WS Continuity Breaks Trigger Degraded + Snapshot Rebuild → S1-006
- ✅ **Anchor-020** — Rate Limit Session Kill Triggers Immediate Kill Mode → S2-001, S2-002
- ✅ **Anchor-021** — Status Endpoint Required Fields → S2-000
- ✅ **Anchor-022** — Cortex WS Gap Blocks Risk-Increasing Actions → S2-003
- ✅ **Anchor-023** — Order-Type Preflight Guards (Artifact-Backed) → S3-000

## Validation Rules

- ✅ **VR-001** — F1 Certification Gate → S1-000
- ✅ **VR-002** — EvidenceGuard Gate → S4-003
- ✅ **VR-003** — Policy Staleness Gate → S1-010
- ✅ **VR-004a** — Watchdog Heartbeat Kill Gate → S1-002
- ✅ **VR-004b** — Watchdog Silence ReduceOnly Trigger → S1-002
- ✅ **VR-005** — Bunker Mode (Network Jitter) Gate → S1-002
- ✅ **VR-006** — Disk Watermark Gates → S1-010
- ✅ **VR-007** — Fee Model Staleness Gate → S1-010
- ✅ **VR-008** — Cortex Override Gate → S1-002
- ✅ **VR-009** — Margin Headroom Gate → S1-010
- ✅ **VR-010** — Replay Gatekeeper Coverage Gate → S1-004
- ✅ **VR-011** — Liquidity Gate → S1-003
- ✅ **VR-012** — Net Edge Gate → S1-004
- ✅ **VR-013** — Instrument Cache Staleness Gate → S1-003
- ✅ **VR-014** — WAL Record-Before-Dispatch Gate → S4-000
- ✅ **VR-015** — AGGRESSIVE Patch Human Approval Gate → S1-000
- ✅ **VR-016** — Exchange Health Monitor Gate → S1-003
- ✅ **VR-017** — Atomic Churn Circuit Breaker → S1-004
- ✅ **VR-018** — Pending Exposure Reservation Gate → S1-004
- ✅ **VR-019** — Global Exposure Budget Gate → S1-004
- ✅ **VR-020** — Inventory Skew Gate → S2-000, S2-001
- ✅ **VR-021** — Orderbook Continuity Gate → S2-002
- ✅ **VR-022** — Trades Continuity Gate → S2-003
- ✅ **VR-023** — Rate Limit Brownout Gate → S1-002
- ✅ **VR-024** — Status Endpoint Response Gate → S1-006
- ✅ **VR-025** — No Market Orders Gate → S3-000
- ✅ **VR-026** — Options Stop Orders Forbidden Gate → S3-000
- ✅ **VR-027** — Stop Orders Require Trigger Gate → S3-000
- ✅ **VR-028** — Linked/OCO Orders Gate → S3-002

## Unregistered IDs Referenced in PRD

- ⚠️ **Anchor-030** → S3-000, S3-001
- ⚠️ **Anchor-031** → S3-002
- ⚠️ **Anchor-040** → S4-001
- ⚠️ **Anchor-041** → S4-000
- ⚠️ **Anchor-042** → S4-000, S4-003
- ⚠️ **Anchor-043** → S4-002
- ⚠️ **VR-030** → S3-000, S3-001, S3-002
- ⚠️ **VR-040** → S4-000, S4-003
- ⚠️ **VR-041** → S4-000
- ⚠️ **VR-042** → S4-002
