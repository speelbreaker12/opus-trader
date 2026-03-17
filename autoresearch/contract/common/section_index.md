| section_anchor | title | start_line | end_line |
|---|---|---:|---:|
| 0.0 | Normative Scope (Non-Negotiable) | 242 | 246 |
| 0.X | Repository Layout & Canonical Module Mapping (Non-Negotiable) | 247 | 270 |
| 0.Y | Verification Harness (Non-Negotiable) | 271 | 291 |
| 0.Z | Compliance Profiles (Normative) | 292 | 293 |
| 0.Z.0 | Purpose and Scope | 294 | 308 |
| 0.Z.1 | Compliance Profile Definitions | 309 | 319 |
| 0.Z.2 | Core Safety Profile (CSP) — Minimum Safe to Trade | 320 | 321 |
| 0.Z.2.1 | Definition <!-- CSP-001 --> | 322 | 332 |
| 0.Z.2.2 | CSP Mandatory Invariants (Non-Negotiable) | 333 | 413 |
| 0.Z.2.3 | CSP Explicit Non-Requirements | 414 | 433 |
| 0.Z.2.4 | CSP Acceptance Tests | 434 | 441 |
| 0.Z.2.5 | CSP Compliance Rule (Normative) | 442 | 455 |
| 0.Z.3 | Governance & Optimization Profile (GOP) | 456 | 457 |
| 0.Z.3.1 | Definition | 458 | 469 |
| 0.Z.3.2 | GOP Mandatory Capabilities | 470 | 493 |
| 0.Z.3.3 | GOP Failure Semantics | 494 | 507 |
| 0.Z.3.4 | GOP Acceptance Tests | 508 | 515 |
| 0.Z.4 | Full Compliance Profile (FULL) | 516 | 526 |
| 0.Z.5 | Acceptance Test Profile Tagging (Normative) | 527 | 559 |
| 0.Z.6 | Declaration of Compliance | 560 | 574 |
| 0.Z.7 | Profile Isolation (Normative) | 575 | 577 |
| 0.Z.7.1 | Definitions | 578 | 584 |
| 0.Z.7.2 | Runtime Isolation Rule (Hard) | 585 | 604 |
| 0.Z.7.3 | Compile-Time Isolation Requirement (Hard) | 605 | 617 |
| 0.Z.7.4 | Observability Requirement | 618 | 631 |
| 0.Z.7.5 | Acceptance Tests (New) | 632 | 665 |
| 0.Z.9 | CSP-Only CI Gate (Normative) | 666 | 698 |
| 0.Z.9.1 | Meta-Acceptance Tests for CSP_ONLY CI Gate (REQUIRED) | 699 | 716 |
| 0.Z.10 | Numeric Sanity Guard (Normative) | 717 | 776 |
| 1 | . Execution Architecture: The "Atomic Group" (Real-Time Repair) | 777 | 781 |
| 1.0 | Instrument Units & Notional Invariants (Deribit Quantity Contract) — MUST implement | 782 | 812 |
| 1.0.X | Instrument Metadata Freshness (Instrument Cache TTL) — MUST implement | 813 | 853 |
| 1.0.Y | Instrument Lifecycle & Expiry Safety (Expiry Cliff Guard) — MUST implement | 854 | 1004 |
| 1.1 | Labeling & Idempotency Contract | 1005 | 1031 |
| 1.1.1 | Canonical Quantization (Pre-Hash & Pre-Dispatch) | 1032 | 1109 |
| 1.1.2 | Label Parse + Disambiguation (Collision-Safe) | 1110 | 1186 |
| 1.2 | Atomic Group Executor | 1187 | 1190 |
| 1.2.1 | GroupState Serialization Invariant (Seed “First Fail”) | 1191 | 1351 |
| 1.2.2 | Atomic Churn Circuit Breaker (Flatten Storm Guard) | 1352 | 1390 |
| 1.2.3 | Self-Impact Feedback Loop Guard (Echo Chamber Breaker) | 1391 | 1468 |
| 1.3 | Pre-Trade Liquidity Gate (Do Not Sweep the Book) | 1469 | 1541 |
| 1.4 | Fee-Aware IOC Limit Pricer (No Market Orders) | 1542 | 1579 |
| 1.4.1 | Net Edge Gate (Fees + Expected Slippage) | 1580 | 1622 |
| 1.4.2 | Inventory Skew Gate (Execution Bias vs Current Exposure) | 1623 | 1686 |
| 1.4.2.1 | PendingExposure Reservation (Anti Over‑Fill) | 1687 | 1727 |
| 1.4.2.2 | Global Exposure Budget (Cross‑Instrument, Correlation‑Aware) | 1728 | 1764 |
| 1.4.3 | Margin Headroom Gate (Liquidation Shield) — MUST implement | 1765 | 1824 |
| 1.4.4 | Deribit Order-Type Preflight Guard (Artifact-Backed) | 1825 | 1939 |
| 1.5 | Position-Aware Execution Sequencer (Council D3) | 1940 | 1973 |
| 2 | . State Management: The Panic-Free Soldier | 1974 | 1976 |
| 2.1 | Trade Lifecycle State Machine (TLSM) | 1977 | 2050 |
| 2.2 | PolicyGuard (Single Authoritative TradingMode Resolver) | 2051 | 2093 |
| 2.2.0 | PolicyGuard Input Snapshot Coherency (Atomic Snapshot + Memory Order) | 2094 | 2137 |
| 2.2.1 | Runtime Binding Gate (HARD, runtime enforcement) | 2138 | 2153 |
| 2.2.1.1 | Promotion Certification (non-runtime gate) | 2154 | 2235 |
| 2.2.1.2 | PolicyGuard Critical Input Freshness (Missing/Stale → Fail-Closed for Opens) | 2236 | 2302 |
| 2.2.2 | EvidenceGuard (No Evidence → No Opens) — HARD RUNTIME INVARIANT | 2303 | 2442 |
| 2.2.3 | TradingMode Computation (Axis Resolver v2 + Reason Codes) | 2443 | 2449 |
| 2.2.3.0 | Axis Model (Normative) | 2450 | 2463 |
| 2.2.3.1 | Dual-Impact Allowlist (Explicit) | 2464 | 2475 |
| 2.2.3.1.1 | Capital-Critical Kill Triggers (No Corroboration Required) | 2476 | 2479 |
| 2.2.3.1.2 | Kill Trigger Corroboration (Non‑Capital) | 2480 | 2507 |
| 2.2.3.2 | Axis Computation (Deterministic) | 2508 | 2549 |
| 2.2.3.3 | TradingMode Resolution (Deterministic, Pure Function of Axes) | 2550 | 2612 |
| 2.2.3.4 | Dispatch Authorization (Non-Negotiable) | 2613 | 2621 |
| 2.2.3.4.1 | Non‑Active OPEN Cancellation (CSP, Non‑Negotiable) | 2622 | 2639 |
| 2.2.3.5 | ModeReasonCode Registry (`/status.mode_reasons`) | 2640 | 2693 |
| 2.2.3.6 | Kill Semantics (Capital Supremacy Safe, CSP) | 2694 | 2735 |
| 2.2.3.7 | Acceptance Tests (REQUIRED) | 2736 | 2949 |
| 2.2.4 | Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001 | 2950 | 3069 |
| 2.2.5 | Cancel/Replace Permission Rules (Canonical) | 3070 | 3094 |
| 2.2.6 | RejectReasonCode Registry (Intent-Level Rejections) | 3095 | 3153 |
| 2.3 | Reflexive Cortex (Hot-Loop Safety Override) | 3154 | 3220 |
| 2.3.1 | Exchange Health Monitor (Maintenance Mode Override) — MUST implement | 3221 | 3262 |
| 2.3.2 | Network Jitter Monitor (Bunker Mode Override) | 3263 | 3335 |
| 2.3.3 | Mark/Index/Last Basis Monitor (Liquidation Reality Guard) | 3336 | 3400 |
| 2.4 | Durable Intent Ledger (WAL Truth Source) | 3401 | 3421 |
| 2.4.1 | WAL Writer Isolation (Hot Loop Protection) | 3422 | 3564 |
| 3 | . Safety & Recovery | 3565 | 3567 |
| 3.1 | Deterministic Emergency Close | 3568 | 3670 |
| 3.2 | Smart Watchdog | 3671 | 3701 |
| 3.3 | Local Rate Limit Circuit Breaker (Deribit Credits + 429/10028 Survival) | 3702 | 3791 |
| 3.4 | Continuous 3-Way Reconciliation (Partials + WS Gaps + Zombies) | 3792 | 3836 |
| 3.4.D | Application-Level WS Data Liveness (Zombie Socket Detection) — MUST implement: | 3837 | 3983 |
| 3.5 | Zombie Sweeper (Ghost Orders & Forgotten Intents) | 3984 | 4035 |
| 4 | . Quantitative Logic: The "Truth" Engine | 4036 | 4038 |
| 4.1 | SVI Stability Gates | 4039 | 4075 |
| 4.1.1 | SVI Arb-Guards (No-Arb Validity) | 4076 | 4112 |
| 4.1.2 | Liquidity-Aware Acceptance (Avoid Stale-Fit Paralysis) | 4113 | 4125 |
| 4.2 | Fee-Aware Execution | 4126 | 4238 |
| 4.3 | Time Drift Safety Gate | 4239 | 4281 |
| 4.3.1 | PnL Decomposition Fields (Theta/Delta/Vega/Fee Drag) | 4282 | 4332 |
| 4.3.2 | Truth Capsule (Decision Context Logger) — MUST implement | 4333 | 4471 |
| 4.4 | Fill Simulator (Shadow Mode Book-Walk) | 4472 | 4494 |
| 4.5 | Slippage Calibration (Reality Sync) | 4495 | 4526 |
| 5 | . Self-Improvement: The Closed-Loop Control | 4527 | 4529 |
| 5.1 | The Optimization Cycle (Python) | 4530 | 4548 |
| 5.2 | Replay Gatekeeper (48h Policy Regression Test) | 4549 | 4723 |
| 5.3 | Policy Canary Rollout (Staged Activation) | 4724 | 4813 |
| 6 | . Implementation Roadmap v4.0 | 4814 | 4891 |
| 7 | . External Tools & Ops Cockpit (Lean Trader Stack) | 4892 | 4911 |
| 7.0 | Owner Control Plane Endpoints (Read-Only, Owner-Grade) | 4912 | 5219 |
| 7.1 | Review Loop (Autopilot Reviewer + Minimal Human Touch) | 5220 | 5225 |
| 7.1.1 | What MUST be logged (audit trail) | 5226 | 5245 |
| 7.1.2 | Who reviews (and when) | 5246 | 5267 |
| 7.1.3 | Auto-approval rules (what the system may change without you) | 5268 | 5285 |
| 7.1.4 | Incident-triggered review (automatic “post-mortem”) | 5286 | 5300 |
| 7.1.5 | Acceptance Tests | 5301 | 5344 |
| 7.2 | Data Retention & Disk Watermarks — MUST implement | 5345 | 5434 |
| 8 | . Release Gates (Promotion Certification Checklist — HARD PASS/FAIL) | 5435 | 5443 |
| 8.1 | Measurable Metrics (PASS/FAIL) | 5444 | 5481 |
| 8.2 | Minimum Test Suite (The Torture Chamber) | 5482 | 5580 |
| 8.3 | Canary Rollout Protocol (Hard Gate) | 5581 | 5587 |
| 8.4 | Promotion Certification Artifact (Hard Gate Implementation) | 5588 | 5614 |
| A.CSP | Core Safety Defaults | 5615 | 5632 |
| A.GOP | Governance & Optimization Defaults | 5633 | 5663 |
| A.1 | Atomic Group Execution | 5664 | 5699 |
| A.1.1 | Inventory Skew Gate | 5700 | 5737 |
| A.2 | Reflexive Cortex (Microstructure Collapse) | 5738 | 5882 |
| A.2.1 | Runtime Binding & Critical Inputs | 5883 | 5919 |
| A.3 | Watchdog & Recovery | 5920 | 6202 |
| A.3.1 | Emergency Close & Liquidity Gates | 6203 | 6234 |
| A.4 | Fee Model Staleness | 6235 | 6271 |
| A.5 | SVI Stability Guards | 6272 | 6297 |
| A.6 | Retention & Replay Windows | 6298 | 6354 |
| A.7 | Summary Table | 6355 | 6440 |
| CSP.0 | Scope | 6441 | 6448 |
| CSP.1 | Definitions (Self-Contained) | 6449 | 6493 |
| CSP.2 | Idempotency & Deduplication | 6494 | 6495 |
| CSP.2.1 | Stable Intent Identity | 6496 | 6506 |
| CSP.2.2 | Deduplication Rule | 6507 | 6515 |
| CSP.3 | RecordedBeforeDispatch (WAL) | 6516 | 6517 |
| CSP.3.1 | Mandatory Recording for OPEN | 6518 | 6525 |
| CSP.3.2 | WAL Degradation Semantics | 6526 | 6534 |
| CSP.4 | Restart, Gaps, and Reconciliation | 6535 | 6536 |
| CSP.4.1 | Restart Safety | 6537 | 6544 |
| CSP.4.2 | No Duplicate Sends | 6545 | 6548 |
| CSP.4.3 | WS Gap / Session Termination | 6549 | 6555 |
| CSP.5 | TradingMode Semantics & Enforcement | 6556 | 6557 |
| CSP.5.1 | Modes | 6558 | 6563 |
| CSP.5.2 | Enforcement Rules | 6564 | 6573 |
| CSP.5.3 | Safety-Critical Prerequisite: Runtime Binding Gate | 6574 | 6581 |
| CSP.6 | Capital Supremacy (No Stranded Exposure) | 6582 | 6592 |
| CSP.7 | Deterministic Emergency Containment | 6593 | 6612 |
| CSP.8 | Timebase Authority (Safety-Critical) | 6613 | 6620 |
| CSP.9 | Profile Isolation | 6621 | 6637 |
| CSP.10 | CSP_ONLY Build/Test Mode (Mechanically Enforced) | 6638 | 6651 |
| CSP.11 | Explicit Non-Requirements | 6652 | 6664 |
| CSP.12 | Acceptance Tests | 6665 | 6736 |
