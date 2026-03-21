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
| 1.3 | Pre-Trade Liquidity Gate (Do Not Sweep the Book) | 1467 | 1562 |
| 1.4 | Fee-Aware IOC Limit Pricer (No Market Orders) | 1563 | 1607 |
| 1.4.1 | Net Edge Gate (Fees + Expected Slippage) | 1608 | 1650 |
| 1.4.2 | Inventory Skew Gate (Execution Bias vs Current Exposure) | 1651 | 1722 |
| 1.4.2.1 | PendingExposure Reservation (Anti Over‑Fill) | 1723 | 1777 |
| 1.4.2.2 | Global Exposure Budget (Cross‑Instrument, Correlation‑Aware) | 1778 | 1814 |
| 1.4.3 | Margin Headroom Gate (Liquidation Shield) — MUST implement | 1815 | 1897 |
| 1.4.4 | Deribit Order-Type Preflight Guard (Artifact-Backed) | 1898 | 2012 |
| 1.5 | Position-Aware Execution Sequencer (Council D3) | 2013 | 2046 |
| 2 | . State Management: The Panic-Free Soldier | 2047 | 2049 |
| 2.1 | Trade Lifecycle State Machine (TLSM) | 2050 | 2123 |
| 2.2 | PolicyGuard (Single Authoritative TradingMode Resolver) | 2124 | 2173 |
| 2.2.0 | PolicyGuard Input Snapshot Coherency (Atomic Snapshot + Memory Order) | 2174 | 2217 |
| 2.2.1 | Runtime Binding Gate (HARD, runtime enforcement) | 2218 | 2233 |
| 2.2.1.1 | Promotion Certification (non-runtime gate) | 2234 | 2315 |
| 2.2.1.2 | PolicyGuard Critical Input Freshness (Missing/Stale → Fail-Closed for Opens) | 2316 | 2391 |
| 2.2.2 | EvidenceGuard (No Evidence → No Opens) — HARD RUNTIME INVARIANT | 2392 | 2558 |
| 2.2.3 | TradingMode Computation (Axis Resolver v2 + Reason Codes) | 2559 | 2565 |
| 2.2.3.0 | Axis Model (Normative) | 2566 | 2579 |
| 2.2.3.1 | Dual-Impact Allowlist (Explicit) | 2580 | 2591 |
| 2.2.3.1.1 | Capital-Critical Kill Triggers (No Corroboration Required) | 2592 | 2595 |
| 2.2.3.1.2 | Kill Trigger Corroboration (Non‑Capital) | 2596 | 2633 |
| 2.2.3.2 | Axis Computation (Deterministic) | 2634 | 2716 |
| 2.2.3.3 | TradingMode Resolution (Deterministic, Pure Function of Axes) | 2717 | 2787 |
| 2.2.3.4 | Dispatch Authorization (Non-Negotiable) | 2788 | 2796 |
| 2.2.3.4.1 | Non‑Active OPEN Cancellation (CSP, Non‑Negotiable) | 2797 | 2814 |
| 2.2.3.5 | ModeReasonCode Registry (`/status.mode_reasons`) | 2815 | 2875 |
| 2.2.3.6 | Kill Semantics (Capital Supremacy Safe, CSP) | 2876 | 2917 |
| 2.2.3.7 | Acceptance Tests (REQUIRED) | 2918 | 3131 |
| 2.2.4 | Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001 | 3132 | 3289 |
| 2.2.5 | Cancel/Replace Permission Rules (Canonical) | 3290 | 3314 |
| 2.2.6 | RejectReasonCode Registry (Intent-Level Rejections) | 3315 | 3375 |
| 2.3 | Reflexive Cortex (Hot-Loop Safety Override) | 3376 | 3442 |
| 2.3.1 | Exchange Health Monitor (Maintenance Mode Override) — MUST implement | 3443 | 3484 |
| 2.3.2 | Network Jitter Monitor (Bunker Mode Override) | 3485 | 3557 |
| 2.3.3 | Mark/Index/Last Basis Monitor (Liquidation Reality Guard) | 3558 | 3622 |
| 2.4 | Durable Intent Ledger (WAL Truth Source) | 3623 | 3643 |
| 2.4.1 | WAL Writer Isolation (Hot Loop Protection) | 3644 | 3786 |
| 3 | . Safety & Recovery | 3787 | 3789 |
| 3.1 | Deterministic Emergency Close | 3790 | 3927 |
| 3.2 | Smart Watchdog | 3928 | 3958 |
| 3.3 | Local Rate Limit Circuit Breaker (Deribit Credits + 429/10028 Survival) | 3959 | 4048 |
| 3.4 | Continuous 3-Way Reconciliation (Partials + WS Gaps + Zombies) | 4049 | 4093 |
| 3.4.D | Application-Level WS Data Liveness (Zombie Socket Detection) — MUST implement: | 4094 | 4240 |
| 3.5 | Zombie Sweeper (Ghost Orders & Forgotten Intents) | 4241 | 4292 |
| 4 | . Quantitative Logic: The "Truth" Engine | 4293 | 4295 |
| 4.1 | SVI Stability Gates | 4296 | 4332 |
| 4.1.1 | SVI Arb-Guards (No-Arb Validity) | 4333 | 4369 |
| 4.1.2 | Liquidity-Aware Acceptance (Avoid Stale-Fit Paralysis) | 4370 | 4382 |
| 4.2 | Fee-Aware Execution | 4383 | 4495 |
| 4.3 | Time Drift Safety Gate | 4496 | 4538 |
| 4.3.1 | PnL Decomposition Fields (Theta/Delta/Vega/Fee Drag) | 4539 | 4589 |
| 4.3.2 | Truth Capsule (Decision Context Logger) — MUST implement | 4590 | 4728 |
| 4.4 | Fill Simulator (Shadow Mode Book-Walk) | 4729 | 4751 |
| 4.5 | Slippage Calibration (Reality Sync) | 4752 | 4783 |
| 5 | . Self-Improvement: The Closed-Loop Control | 4784 | 4786 |
| 5.1 | The Optimization Cycle (Python) | 4787 | 4805 |
| 5.2 | Replay Gatekeeper (48h Policy Regression Test) | 4806 | 4980 |
| 5.3 | Policy Canary Rollout (Staged Activation) | 4981 | 5070 |
| 6 | . Implementation Roadmap v4.0 | 5071 | 5148 |
| 7 | . External Tools & Ops Cockpit (Lean Trader Stack) | 5149 | 5168 |
| 7.0 | Owner Control Plane Endpoints (Read-Only, Owner-Grade) | 5169 | 5476 |
| 7.1 | Review Loop (Autopilot Reviewer + Minimal Human Touch) | 5477 | 5482 |
| 7.1.1 | What MUST be logged (audit trail) | 5483 | 5502 |
| 7.1.2 | Who reviews (and when) | 5503 | 5524 |
| 7.1.3 | Auto-approval rules (what the system may change without you) | 5525 | 5542 |
| 7.1.4 | Incident-triggered review (automatic “post-mortem”) | 5543 | 5557 |
| 7.1.5 | Acceptance Tests | 5558 | 5601 |
| 7.2 | Data Retention & Disk Watermarks — MUST implement | 5602 | 5691 |
| 8 | . Release Gates (Promotion Certification Checklist — HARD PASS/FAIL) | 5692 | 5700 |
| 8.1 | Measurable Metrics (PASS/FAIL) | 5701 | 5738 |
| 8.2 | Minimum Test Suite (The Torture Chamber) | 5739 | 5837 |
| 8.3 | Canary Rollout Protocol (Hard Gate) | 5838 | 5844 |
| 8.4 | Promotion Certification Artifact (Hard Gate Implementation) | 5845 | 5871 |
| A.CSP | Core Safety Defaults | 5872 | 5889 |
| A.GOP | Governance & Optimization Defaults | 5890 | 5920 |
| A.1 | Atomic Group Execution | 5921 | 5956 |
| A.1.1 | Inventory Skew Gate | 5957 | 5994 |
| A.2 | Reflexive Cortex (Microstructure Collapse) | 5995 | 6139 |
| A.2.1 | Runtime Binding & Critical Inputs | 6140 | 6176 |
| A.3 | Watchdog & Recovery | 6177 | 6459 |
| A.3.1 | Emergency Close & Liquidity Gates | 6460 | 6491 |
| A.4 | Fee Model Staleness | 6492 | 6528 |
| A.5 | SVI Stability Guards | 6529 | 6554 |
| A.6 | Retention & Replay Windows | 6555 | 6611 |
| A.7 | Summary Table | 6612 | 6700 |
| CSP.0 | Scope | 6701 | 6708 |
| CSP.1 | Definitions (Self-Contained) | 6709 | 6753 |
| CSP.2 | Idempotency & Deduplication | 6754 | 6755 |
| CSP.2.1 | Stable Intent Identity | 6756 | 6766 |
| CSP.2.2 | Deduplication Rule | 6767 | 6775 |
| CSP.3 | RecordedBeforeDispatch (WAL) | 6776 | 6777 |
| CSP.3.1 | Mandatory Recording for OPEN | 6778 | 6785 |
| CSP.3.2 | WAL Degradation Semantics | 6786 | 6794 |
| CSP.4 | Restart, Gaps, and Reconciliation | 6795 | 6796 |
| CSP.4.1 | Restart Safety | 6797 | 6804 |
| CSP.4.2 | No Duplicate Sends | 6805 | 6808 |
| CSP.4.3 | WS Gap / Session Termination | 6809 | 6815 |
| CSP.5 | TradingMode Semantics & Enforcement | 6816 | 6817 |
| CSP.5.1 | Modes | 6818 | 6823 |
| CSP.5.2 | Enforcement Rules | 6824 | 6833 |
| CSP.5.3 | Safety-Critical Prerequisite: Runtime Binding Gate | 6834 | 6841 |
| CSP.6 | Capital Supremacy (No Stranded Exposure) | 6842 | 6852 |
| CSP.7 | Deterministic Emergency Containment | 6853 | 6872 |
| CSP.8 | Timebase Authority (Safety-Critical) | 6873 | 6880 |
| CSP.9 | Profile Isolation | 6881 | 6897 |
| CSP.10 | CSP_ONLY Build/Test Mode (Mechanically Enforced) | 6898 | 6911 |
| CSP.11 | Explicit Non-Requirements | 6912 | 6924 |
| CSP.12 | Acceptance Tests | 6925 | 6999 |
