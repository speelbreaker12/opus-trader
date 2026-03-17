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
| 1.3 | Pre-Trade Liquidity Gate (Do Not Sweep the Book) | 1469 | 1548 |
| 1.4 | Fee-Aware IOC Limit Pricer (No Market Orders) | 1549 | 1586 |
| 1.4.1 | Net Edge Gate (Fees + Expected Slippage) | 1587 | 1629 |
| 1.4.2 | Inventory Skew Gate (Execution Bias vs Current Exposure) | 1630 | 1693 |
| 1.4.2.1 | PendingExposure Reservation (Anti Over‑Fill) | 1694 | 1734 |
| 1.4.2.2 | Global Exposure Budget (Cross‑Instrument, Correlation‑Aware) | 1735 | 1771 |
| 1.4.3 | Margin Headroom Gate (Liquidation Shield) — MUST implement | 1772 | 1831 |
| 1.4.4 | Deribit Order-Type Preflight Guard (Artifact-Backed) | 1832 | 1946 |
| 1.5 | Position-Aware Execution Sequencer (Council D3) | 1947 | 1980 |
| 2 | . State Management: The Panic-Free Soldier | 1981 | 1983 |
| 2.1 | Trade Lifecycle State Machine (TLSM) | 1984 | 2057 |
| 2.2 | PolicyGuard (Single Authoritative TradingMode Resolver) | 2058 | 2100 |
| 2.2.0 | PolicyGuard Input Snapshot Coherency (Atomic Snapshot + Memory Order) | 2101 | 2144 |
| 2.2.1 | Runtime Binding Gate (HARD, runtime enforcement) | 2145 | 2160 |
| 2.2.1.1 | Promotion Certification (non-runtime gate) | 2161 | 2242 |
| 2.2.1.2 | PolicyGuard Critical Input Freshness (Missing/Stale → Fail-Closed for Opens) | 2243 | 2309 |
| 2.2.2 | EvidenceGuard (No Evidence → No Opens) — HARD RUNTIME INVARIANT | 2310 | 2459 |
| 2.2.3 | TradingMode Computation (Axis Resolver v2 + Reason Codes) | 2460 | 2466 |
| 2.2.3.0 | Axis Model (Normative) | 2467 | 2480 |
| 2.2.3.1 | Dual-Impact Allowlist (Explicit) | 2481 | 2492 |
| 2.2.3.1.1 | Capital-Critical Kill Triggers (No Corroboration Required) | 2493 | 2496 |
| 2.2.3.1.2 | Kill Trigger Corroboration (Non‑Capital) | 2497 | 2524 |
| 2.2.3.2 | Axis Computation (Deterministic) | 2525 | 2567 |
| 2.2.3.3 | TradingMode Resolution (Deterministic, Pure Function of Axes) | 2568 | 2630 |
| 2.2.3.4 | Dispatch Authorization (Non-Negotiable) | 2631 | 2639 |
| 2.2.3.4.1 | Non‑Active OPEN Cancellation (CSP, Non‑Negotiable) | 2640 | 2657 |
| 2.2.3.5 | ModeReasonCode Registry (`/status.mode_reasons`) | 2658 | 2711 |
| 2.2.3.6 | Kill Semantics (Capital Supremacy Safe, CSP) | 2712 | 2753 |
| 2.2.3.7 | Acceptance Tests (REQUIRED) | 2754 | 2974 |
| 2.2.4 | Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001 | 2975 | 3101 |
| 2.2.5 | Cancel/Replace Permission Rules (Canonical) | 3102 | 3126 |
| 2.2.6 | RejectReasonCode Registry (Intent-Level Rejections) | 3127 | 3185 |
| 2.3 | Reflexive Cortex (Hot-Loop Safety Override) | 3186 | 3252 |
| 2.3.1 | Exchange Health Monitor (Maintenance Mode Override) — MUST implement | 3253 | 3294 |
| 2.3.2 | Network Jitter Monitor (Bunker Mode Override) | 3295 | 3367 |
| 2.3.3 | Mark/Index/Last Basis Monitor (Liquidation Reality Guard) | 3368 | 3432 |
| 2.4 | Durable Intent Ledger (WAL Truth Source) | 3433 | 3453 |
| 2.4.1 | WAL Writer Isolation (Hot Loop Protection) | 3454 | 3596 |
| 3 | . Safety & Recovery | 3597 | 3599 |
| 3.1 | Deterministic Emergency Close | 3600 | 3718 |
| 3.2 | Smart Watchdog | 3719 | 3749 |
| 3.3 | Local Rate Limit Circuit Breaker (Deribit Credits + 429/10028 Survival) | 3750 | 3839 |
| 3.4 | Continuous 3-Way Reconciliation (Partials + WS Gaps + Zombies) | 3840 | 3884 |
| 3.4.D | Application-Level WS Data Liveness (Zombie Socket Detection) — MUST implement: | 3885 | 4031 |
| 3.5 | Zombie Sweeper (Ghost Orders & Forgotten Intents) | 4032 | 4083 |
| 4 | . Quantitative Logic: The "Truth" Engine | 4084 | 4086 |
| 4.1 | SVI Stability Gates | 4087 | 4123 |
| 4.1.1 | SVI Arb-Guards (No-Arb Validity) | 4124 | 4160 |
| 4.1.2 | Liquidity-Aware Acceptance (Avoid Stale-Fit Paralysis) | 4161 | 4173 |
| 4.2 | Fee-Aware Execution | 4174 | 4286 |
| 4.3 | Time Drift Safety Gate | 4287 | 4329 |
| 4.3.1 | PnL Decomposition Fields (Theta/Delta/Vega/Fee Drag) | 4330 | 4380 |
| 4.3.2 | Truth Capsule (Decision Context Logger) — MUST implement | 4381 | 4519 |
| 4.4 | Fill Simulator (Shadow Mode Book-Walk) | 4520 | 4542 |
| 4.5 | Slippage Calibration (Reality Sync) | 4543 | 4574 |
| 5 | . Self-Improvement: The Closed-Loop Control | 4575 | 4577 |
| 5.1 | The Optimization Cycle (Python) | 4578 | 4596 |
| 5.2 | Replay Gatekeeper (48h Policy Regression Test) | 4597 | 4771 |
| 5.3 | Policy Canary Rollout (Staged Activation) | 4772 | 4861 |
| 6 | . Implementation Roadmap v4.0 | 4862 | 4939 |
| 7 | . External Tools & Ops Cockpit (Lean Trader Stack) | 4940 | 4959 |
| 7.0 | Owner Control Plane Endpoints (Read-Only, Owner-Grade) | 4960 | 5267 |
| 7.1 | Review Loop (Autopilot Reviewer + Minimal Human Touch) | 5268 | 5273 |
| 7.1.1 | What MUST be logged (audit trail) | 5274 | 5293 |
| 7.1.2 | Who reviews (and when) | 5294 | 5315 |
| 7.1.3 | Auto-approval rules (what the system may change without you) | 5316 | 5333 |
| 7.1.4 | Incident-triggered review (automatic “post-mortem”) | 5334 | 5348 |
| 7.1.5 | Acceptance Tests | 5349 | 5392 |
| 7.2 | Data Retention & Disk Watermarks — MUST implement | 5393 | 5482 |
| 8 | . Release Gates (Promotion Certification Checklist — HARD PASS/FAIL) | 5483 | 5491 |
| 8.1 | Measurable Metrics (PASS/FAIL) | 5492 | 5529 |
| 8.2 | Minimum Test Suite (The Torture Chamber) | 5530 | 5628 |
| 8.3 | Canary Rollout Protocol (Hard Gate) | 5629 | 5635 |
| 8.4 | Promotion Certification Artifact (Hard Gate Implementation) | 5636 | 5662 |
| A.CSP | Core Safety Defaults | 5663 | 5680 |
| A.GOP | Governance & Optimization Defaults | 5681 | 5711 |
| A.1 | Atomic Group Execution | 5712 | 5747 |
| A.1.1 | Inventory Skew Gate | 5748 | 5785 |
| A.2 | Reflexive Cortex (Microstructure Collapse) | 5786 | 5930 |
| A.2.1 | Runtime Binding & Critical Inputs | 5931 | 5967 |
| A.3 | Watchdog & Recovery | 5968 | 6250 |
| A.3.1 | Emergency Close & Liquidity Gates | 6251 | 6282 |
| A.4 | Fee Model Staleness | 6283 | 6319 |
| A.5 | SVI Stability Guards | 6320 | 6345 |
| A.6 | Retention & Replay Windows | 6346 | 6402 |
| A.7 | Summary Table | 6403 | 6488 |
| CSP.0 | Scope | 6489 | 6496 |
| CSP.1 | Definitions (Self-Contained) | 6497 | 6541 |
| CSP.2 | Idempotency & Deduplication | 6542 | 6543 |
| CSP.2.1 | Stable Intent Identity | 6544 | 6554 |
| CSP.2.2 | Deduplication Rule | 6555 | 6563 |
| CSP.3 | RecordedBeforeDispatch (WAL) | 6564 | 6565 |
| CSP.3.1 | Mandatory Recording for OPEN | 6566 | 6573 |
| CSP.3.2 | WAL Degradation Semantics | 6574 | 6582 |
| CSP.4 | Restart, Gaps, and Reconciliation | 6583 | 6584 |
| CSP.4.1 | Restart Safety | 6585 | 6592 |
| CSP.4.2 | No Duplicate Sends | 6593 | 6596 |
| CSP.4.3 | WS Gap / Session Termination | 6597 | 6603 |
| CSP.5 | TradingMode Semantics & Enforcement | 6604 | 6605 |
| CSP.5.1 | Modes | 6606 | 6611 |
| CSP.5.2 | Enforcement Rules | 6612 | 6621 |
| CSP.5.3 | Safety-Critical Prerequisite: Runtime Binding Gate | 6622 | 6629 |
| CSP.6 | Capital Supremacy (No Stranded Exposure) | 6630 | 6640 |
| CSP.7 | Deterministic Emergency Containment | 6641 | 6660 |
| CSP.8 | Timebase Authority (Safety-Critical) | 6661 | 6668 |
| CSP.9 | Profile Isolation | 6669 | 6685 |
| CSP.10 | CSP_ONLY Build/Test Mode (Mechanically Enforced) | 6686 | 6699 |
| CSP.11 | Explicit Non-Requirements | 6700 | 6712 |
| CSP.12 | Acceptance Tests | 6713 | 6785 |
