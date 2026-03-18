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
| 1.1.1 | Canonical Quantization (Pre-Hash & Pre-Dispatch) | 1032 | 1107 |
| 1.1.2 | Label Parse + Disambiguation (Collision-Safe) | 1108 | 1184 |
| 1.2 | Atomic Group Executor | 1185 | 1188 |
| 1.2.1 | GroupState Serialization Invariant (Seed “First Fail”) | 1189 | 1349 |
| 1.2.2 | Atomic Churn Circuit Breaker (Flatten Storm Guard) | 1350 | 1388 |
| 1.2.3 | Self-Impact Feedback Loop Guard (Echo Chamber Breaker) | 1389 | 1466 |
| 1.3 | Pre-Trade Liquidity Gate (Do Not Sweep the Book) | 1467 | 1539 |
| 1.4 | Fee-Aware IOC Limit Pricer (No Market Orders) | 1540 | 1584 |
| 1.4.1 | Net Edge Gate (Fees + Expected Slippage) | 1585 | 1627 |
| 1.4.2 | Inventory Skew Gate (Execution Bias vs Current Exposure) | 1628 | 1699 |
| 1.4.2.1 | PendingExposure Reservation (Anti Over‑Fill) | 1700 | 1754 |
| 1.4.2.2 | Global Exposure Budget (Cross‑Instrument, Correlation‑Aware) | 1755 | 1791 |
| 1.4.3 | Margin Headroom Gate (Liquidation Shield) — MUST implement | 1792 | 1874 |
| 1.4.4 | Deribit Order-Type Preflight Guard (Artifact-Backed) | 1875 | 1989 |
| 1.5 | Position-Aware Execution Sequencer (Council D3) | 1990 | 2023 |
| 2 | . State Management: The Panic-Free Soldier | 2024 | 2026 |
| 2.1 | Trade Lifecycle State Machine (TLSM) | 2027 | 2100 |
| 2.2 | PolicyGuard (Single Authoritative TradingMode Resolver) | 2101 | 2150 |
| 2.2.0 | PolicyGuard Input Snapshot Coherency (Atomic Snapshot + Memory Order) | 2151 | 2194 |
| 2.2.1 | Runtime Binding Gate (HARD, runtime enforcement) | 2195 | 2210 |
| 2.2.1.1 | Promotion Certification (non-runtime gate) | 2211 | 2292 |
| 2.2.1.2 | PolicyGuard Critical Input Freshness (Missing/Stale → Fail-Closed for Opens) | 2293 | 2368 |
| 2.2.2 | EvidenceGuard (No Evidence → No Opens) — HARD RUNTIME INVARIANT | 2369 | 2508 |
| 2.2.3 | TradingMode Computation (Axis Resolver v2 + Reason Codes) | 2509 | 2515 |
| 2.2.3.0 | Axis Model (Normative) | 2516 | 2529 |
| 2.2.3.1 | Dual-Impact Allowlist (Explicit) | 2530 | 2541 |
| 2.2.3.1.1 | Capital-Critical Kill Triggers (No Corroboration Required) | 2542 | 2545 |
| 2.2.3.1.2 | Kill Trigger Corroboration (Non‑Capital) | 2546 | 2573 |
| 2.2.3.2 | Axis Computation (Deterministic) | 2574 | 2621 |
| 2.2.3.3 | TradingMode Resolution (Deterministic, Pure Function of Axes) | 2622 | 2692 |
| 2.2.3.4 | Dispatch Authorization (Non-Negotiable) | 2693 | 2701 |
| 2.2.3.4.1 | Non‑Active OPEN Cancellation (CSP, Non‑Negotiable) | 2702 | 2719 |
| 2.2.3.5 | ModeReasonCode Registry (`/status.mode_reasons`) | 2720 | 2773 |
| 2.2.3.6 | Kill Semantics (Capital Supremacy Safe, CSP) | 2774 | 2815 |
| 2.2.3.7 | Acceptance Tests (REQUIRED) | 2816 | 3029 |
| 2.2.4 | Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001 | 3030 | 3155 |
| 2.2.5 | Cancel/Replace Permission Rules (Canonical) | 3156 | 3180 |
| 2.2.6 | RejectReasonCode Registry (Intent-Level Rejections) | 3181 | 3241 |
| 2.3 | Reflexive Cortex (Hot-Loop Safety Override) | 3242 | 3308 |
| 2.3.1 | Exchange Health Monitor (Maintenance Mode Override) — MUST implement | 3309 | 3350 |
| 2.3.2 | Network Jitter Monitor (Bunker Mode Override) | 3351 | 3423 |
| 2.3.3 | Mark/Index/Last Basis Monitor (Liquidation Reality Guard) | 3424 | 3488 |
| 2.4 | Durable Intent Ledger (WAL Truth Source) | 3489 | 3509 |
| 2.4.1 | WAL Writer Isolation (Hot Loop Protection) | 3510 | 3652 |
| 3 | . Safety & Recovery | 3653 | 3655 |
| 3.1 | Deterministic Emergency Close | 3656 | 3772 |
| 3.2 | Smart Watchdog | 3773 | 3803 |
| 3.3 | Local Rate Limit Circuit Breaker (Deribit Credits + 429/10028 Survival) | 3804 | 3893 |
| 3.4 | Continuous 3-Way Reconciliation (Partials + WS Gaps + Zombies) | 3894 | 3938 |
| 3.4.D | Application-Level WS Data Liveness (Zombie Socket Detection) — MUST implement: | 3939 | 4085 |
| 3.5 | Zombie Sweeper (Ghost Orders & Forgotten Intents) | 4086 | 4137 |
| 4 | . Quantitative Logic: The "Truth" Engine | 4138 | 4140 |
| 4.1 | SVI Stability Gates | 4141 | 4177 |
| 4.1.1 | SVI Arb-Guards (No-Arb Validity) | 4178 | 4214 |
| 4.1.2 | Liquidity-Aware Acceptance (Avoid Stale-Fit Paralysis) | 4215 | 4227 |
| 4.2 | Fee-Aware Execution | 4228 | 4340 |
| 4.3 | Time Drift Safety Gate | 4341 | 4383 |
| 4.3.1 | PnL Decomposition Fields (Theta/Delta/Vega/Fee Drag) | 4384 | 4434 |
| 4.3.2 | Truth Capsule (Decision Context Logger) — MUST implement | 4435 | 4573 |
| 4.4 | Fill Simulator (Shadow Mode Book-Walk) | 4574 | 4596 |
| 4.5 | Slippage Calibration (Reality Sync) | 4597 | 4628 |
| 5 | . Self-Improvement: The Closed-Loop Control | 4629 | 4631 |
| 5.1 | The Optimization Cycle (Python) | 4632 | 4650 |
| 5.2 | Replay Gatekeeper (48h Policy Regression Test) | 4651 | 4825 |
| 5.3 | Policy Canary Rollout (Staged Activation) | 4826 | 4915 |
| 6 | . Implementation Roadmap v4.0 | 4916 | 4993 |
| 7 | . External Tools & Ops Cockpit (Lean Trader Stack) | 4994 | 5013 |
| 7.0 | Owner Control Plane Endpoints (Read-Only, Owner-Grade) | 5014 | 5321 |
| 7.1 | Review Loop (Autopilot Reviewer + Minimal Human Touch) | 5322 | 5327 |
| 7.1.1 | What MUST be logged (audit trail) | 5328 | 5347 |
| 7.1.2 | Who reviews (and when) | 5348 | 5369 |
| 7.1.3 | Auto-approval rules (what the system may change without you) | 5370 | 5387 |
| 7.1.4 | Incident-triggered review (automatic “post-mortem”) | 5388 | 5402 |
| 7.1.5 | Acceptance Tests | 5403 | 5446 |
| 7.2 | Data Retention & Disk Watermarks — MUST implement | 5447 | 5536 |
| 8 | . Release Gates (Promotion Certification Checklist — HARD PASS/FAIL) | 5537 | 5545 |
| 8.1 | Measurable Metrics (PASS/FAIL) | 5546 | 5583 |
| 8.2 | Minimum Test Suite (The Torture Chamber) | 5584 | 5682 |
| 8.3 | Canary Rollout Protocol (Hard Gate) | 5683 | 5689 |
| 8.4 | Promotion Certification Artifact (Hard Gate Implementation) | 5690 | 5716 |
| A.CSP | Core Safety Defaults | 5717 | 5734 |
| A.GOP | Governance & Optimization Defaults | 5735 | 5765 |
| A.1 | Atomic Group Execution | 5766 | 5801 |
| A.1.1 | Inventory Skew Gate | 5802 | 5839 |
| A.2 | Reflexive Cortex (Microstructure Collapse) | 5840 | 5984 |
| A.2.1 | Runtime Binding & Critical Inputs | 5985 | 6021 |
| A.3 | Watchdog & Recovery | 6022 | 6304 |
| A.3.1 | Emergency Close & Liquidity Gates | 6305 | 6336 |
| A.4 | Fee Model Staleness | 6337 | 6373 |
| A.5 | SVI Stability Guards | 6374 | 6399 |
| A.6 | Retention & Replay Windows | 6400 | 6456 |
| A.7 | Summary Table | 6457 | 6545 |
| CSP.0 | Scope | 6546 | 6553 |
| CSP.1 | Definitions (Self-Contained) | 6554 | 6598 |
| CSP.2 | Idempotency & Deduplication | 6599 | 6600 |
| CSP.2.1 | Stable Intent Identity | 6601 | 6611 |
| CSP.2.2 | Deduplication Rule | 6612 | 6620 |
| CSP.3 | RecordedBeforeDispatch (WAL) | 6621 | 6622 |
| CSP.3.1 | Mandatory Recording for OPEN | 6623 | 6630 |
| CSP.3.2 | WAL Degradation Semantics | 6631 | 6639 |
| CSP.4 | Restart, Gaps, and Reconciliation | 6640 | 6641 |
| CSP.4.1 | Restart Safety | 6642 | 6649 |
| CSP.4.2 | No Duplicate Sends | 6650 | 6653 |
| CSP.4.3 | WS Gap / Session Termination | 6654 | 6660 |
| CSP.5 | TradingMode Semantics & Enforcement | 6661 | 6662 |
| CSP.5.1 | Modes | 6663 | 6668 |
| CSP.5.2 | Enforcement Rules | 6669 | 6678 |
| CSP.5.3 | Safety-Critical Prerequisite: Runtime Binding Gate | 6679 | 6686 |
| CSP.6 | Capital Supremacy (No Stranded Exposure) | 6687 | 6697 |
| CSP.7 | Deterministic Emergency Containment | 6698 | 6717 |
| CSP.8 | Timebase Authority (Safety-Critical) | 6718 | 6725 |
| CSP.9 | Profile Isolation | 6726 | 6742 |
| CSP.10 | CSP_ONLY Build/Test Mode (Mechanically Enforced) | 6743 | 6756 |
| CSP.11 | Explicit Non-Requirements | 6757 | 6769 |
| CSP.12 | Acceptance Tests | 6770 | 6842 |
