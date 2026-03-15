| section_anchor | title | start_line | end_line |
|---|---|---:|---:|
| 0.0 | Normative Scope (Non-Negotiable) | 240 | 244 |
| 0.X | Repository Layout & Canonical Module Mapping (Non-Negotiable) | 245 | 268 |
| 0.Y | Verification Harness (Non-Negotiable) | 269 | 289 |
| 0.Z | Compliance Profiles (Normative) | 290 | 291 |
| 0.Z.0 | Purpose and Scope | 292 | 306 |
| 0.Z.1 | Compliance Profile Definitions | 307 | 317 |
| 0.Z.2 | Core Safety Profile (CSP) — Minimum Safe to Trade | 318 | 319 |
| 0.Z.2.1 | Definition <!-- CSP-001 --> | 320 | 330 |
| 0.Z.2.2 | CSP Mandatory Invariants (Non-Negotiable) | 331 | 411 |
| 0.Z.2.3 | CSP Explicit Non-Requirements | 412 | 431 |
| 0.Z.2.4 | CSP Acceptance Tests | 432 | 439 |
| 0.Z.2.5 | CSP Compliance Rule (Normative) | 440 | 453 |
| 0.Z.3 | Governance & Optimization Profile (GOP) | 454 | 455 |
| 0.Z.3.1 | Definition | 456 | 467 |
| 0.Z.3.2 | GOP Mandatory Capabilities | 468 | 491 |
| 0.Z.3.3 | GOP Failure Semantics | 492 | 505 |
| 0.Z.3.4 | GOP Acceptance Tests | 506 | 513 |
| 0.Z.4 | Full Compliance Profile (FULL) | 514 | 524 |
| 0.Z.5 | Acceptance Test Profile Tagging (Normative) | 525 | 557 |
| 0.Z.6 | Declaration of Compliance | 558 | 572 |
| 0.Z.7 | Profile Isolation (Normative) | 573 | 575 |
| 0.Z.7.1 | Definitions | 576 | 582 |
| 0.Z.7.2 | Runtime Isolation Rule (Hard) | 583 | 602 |
| 0.Z.7.3 | Compile-Time Isolation Requirement (Hard) | 603 | 615 |
| 0.Z.7.4 | Observability Requirement | 616 | 629 |
| 0.Z.7.5 | Acceptance Tests (New) | 630 | 663 |
| 0.Z.9 | CSP-Only CI Gate (Normative) | 664 | 696 |
| 0.Z.9.1 | Meta-Acceptance Tests for CSP_ONLY CI Gate (REQUIRED) | 697 | 714 |
| 0.Z.10 | Numeric Sanity Guard (Normative) | 715 | 774 |
| 1 | . Execution Architecture: The "Atomic Group" (Real-Time Repair) | 775 | 779 |
| 1.0 | Instrument Units & Notional Invariants (Deribit Quantity Contract) — MUST implement | 780 | 810 |
| 1.0.X | Instrument Metadata Freshness (Instrument Cache TTL) — MUST implement | 811 | 851 |
| 1.0.Y | Instrument Lifecycle & Expiry Safety (Expiry Cliff Guard) — MUST implement | 852 | 1002 |
| 1.1 | Labeling & Idempotency Contract | 1003 | 1029 |
| 1.1.1 | Canonical Quantization (Pre-Hash & Pre-Dispatch) | 1030 | 1107 |
| 1.1.2 | Label Parse + Disambiguation (Collision-Safe) | 1108 | 1184 |
| 1.2 | Atomic Group Executor | 1185 | 1188 |
| 1.2.1 | GroupState Serialization Invariant (Seed “First Fail”) | 1189 | 1349 |
| 1.2.2 | Atomic Churn Circuit Breaker (Flatten Storm Guard) | 1350 | 1368 |
| 1.2.3 | Self-Impact Feedback Loop Guard (Echo Chamber Breaker) | 1369 | 1446 |
| 1.3 | Pre-Trade Liquidity Gate (Do Not Sweep the Book) | 1447 | 1510 |
| 1.4 | Fee-Aware IOC Limit Pricer (No Market Orders) | 1511 | 1548 |
| 1.4.1 | Net Edge Gate (Fees + Expected Slippage) | 1549 | 1591 |
| 1.4.2 | Inventory Skew Gate (Execution Bias vs Current Exposure) | 1592 | 1655 |
| 1.4.2.1 | PendingExposure Reservation (Anti Over‑Fill) | 1656 | 1696 |
| 1.4.2.2 | Global Exposure Budget (Cross‑Instrument, Correlation‑Aware) | 1697 | 1733 |
| 1.4.3 | Margin Headroom Gate (Liquidation Shield) — MUST implement | 1734 | 1793 |
| 1.4.4 | Deribit Order-Type Preflight Guard (Artifact-Backed) | 1794 | 1908 |
| 1.5 | Position-Aware Execution Sequencer (Council D3) | 1909 | 1942 |
| 2 | . State Management: The Panic-Free Soldier | 1943 | 1945 |
| 2.1 | Trade Lifecycle State Machine (TLSM) | 1946 | 2019 |
| 2.2 | PolicyGuard (Single Authoritative TradingMode Resolver) | 2020 | 2062 |
| 2.2.0 | PolicyGuard Input Snapshot Coherency (Atomic Snapshot + Memory Order) | 2063 | 2106 |
| 2.2.1 | Runtime Binding Gate (HARD, runtime enforcement) | 2107 | 2122 |
| 2.2.1.1 | Promotion Certification (non-runtime gate) | 2123 | 2204 |
| 2.2.1.2 | PolicyGuard Critical Input Freshness (Missing/Stale → Fail-Closed for Opens) | 2205 | 2271 |
| 2.2.2 | EvidenceGuard (No Evidence → No Opens) — HARD RUNTIME INVARIANT | 2272 | 2409 |
| 2.2.3 | TradingMode Computation (Axis Resolver v2 + Reason Codes) | 2410 | 2416 |
| 2.2.3.0 | Axis Model (Normative) | 2417 | 2430 |
| 2.2.3.1 | Dual-Impact Allowlist (Explicit) | 2431 | 2440 |
| 2.2.3.1.2 | Kill Trigger Corroboration (Non‑Capital) | 2441 | 2468 |
| 2.2.3.2 | Axis Computation (Deterministic) | 2469 | 2510 |
| 2.2.3.3 | TradingMode Resolution (Deterministic, Pure Function of Axes) | 2511 | 2573 |
| 2.2.3.4 | Dispatch Authorization (Non-Negotiable) | 2574 | 2582 |
| 2.2.3.4.1 | Non‑Active OPEN Cancellation (CSP, Non‑Negotiable) | 2583 | 2591 |
| 2.2.3.5 | ModeReasonCode Registry (`/status.mode_reasons`) | 2592 | 2636 |
| 2.2.3.6 | Kill Semantics (Capital Supremacy Safe, CSP) | 2637 | 2678 |
| 2.2.3.7 | Acceptance Tests (REQUIRED) | 2679 | 2876 |
| 2.2.4 | Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001 | 2877 | 2965 |
| 2.2.5 | Cancel/Replace Permission Rules (Canonical) | 2966 | 2990 |
| 2.2.6 | RejectReasonCode Registry (Intent-Level Rejections) | 2991 | 3049 |
| 2.3 | Reflexive Cortex (Hot-Loop Safety Override) | 3050 | 3116 |
| 2.3.1 | Exchange Health Monitor (Maintenance Mode Override) — MUST implement | 3117 | 3158 |
| 2.3.2 | Network Jitter Monitor (Bunker Mode Override) | 3159 | 3231 |
| 2.3.3 | Mark/Index/Last Basis Monitor (Liquidation Reality Guard) | 3232 | 3296 |
| 2.4 | Durable Intent Ledger (WAL Truth Source) | 3297 | 3317 |
| 2.4.1 | WAL Writer Isolation (Hot Loop Protection) | 3318 | 3460 |
| 3 | . Safety & Recovery | 3461 | 3463 |
| 3.1 | Deterministic Emergency Close | 3464 | 3565 |
| 3.2 | Smart Watchdog | 3566 | 3596 |
| 3.3 | Local Rate Limit Circuit Breaker (Deribit Credits + 429/10028 Survival) | 3597 | 3686 |
| 3.4 | Continuous 3-Way Reconciliation (Partials + WS Gaps + Zombies) | 3687 | 3731 |
| 3.4.D | Application-Level WS Data Liveness (Zombie Socket Detection) — MUST implement: | 3732 | 3878 |
| 3.5 | Zombie Sweeper (Ghost Orders & Forgotten Intents) | 3879 | 3930 |
| 4 | . Quantitative Logic: The "Truth" Engine | 3931 | 3933 |
| 4.1 | SVI Stability Gates | 3934 | 3970 |
| 4.1.1 | SVI Arb-Guards (No-Arb Validity) | 3971 | 4007 |
| 4.1.2 | Liquidity-Aware Acceptance (Avoid Stale-Fit Paralysis) | 4008 | 4020 |
| 4.2 | Fee-Aware Execution | 4021 | 4133 |
| 4.3 | Time Drift Safety Gate | 4134 | 4176 |
| 4.3.1 | PnL Decomposition Fields (Theta/Delta/Vega/Fee Drag) | 4177 | 4227 |
| 4.3.2 | Truth Capsule (Decision Context Logger) — MUST implement | 4228 | 4366 |
| 4.4 | Fill Simulator (Shadow Mode Book-Walk) | 4367 | 4389 |
| 4.5 | Slippage Calibration (Reality Sync) | 4390 | 4421 |
| 5 | . Self-Improvement: The Closed-Loop Control | 4422 | 4424 |
| 5.1 | The Optimization Cycle (Python) | 4425 | 4443 |
| 5.2 | Replay Gatekeeper (48h Policy Regression Test) | 4444 | 4618 |
| 5.3 | Policy Canary Rollout (Staged Activation) | 4619 | 4708 |
| 6 | . Implementation Roadmap v4.0 | 4709 | 4785 |
| 7 | . External Tools & Ops Cockpit (Lean Trader Stack) | 4786 | 4805 |
| 7.0 | Owner Control Plane Endpoints (Read-Only, Owner-Grade) | 4806 | 5101 |
| 7.1 | Review Loop (Autopilot Reviewer + Minimal Human Touch) | 5102 | 5107 |
| 7.1.1 | What MUST be logged (audit trail) | 5108 | 5127 |
| 7.1.2 | Who reviews (and when) | 5128 | 5149 |
| 7.1.3 | Auto-approval rules (what the system may change without you) | 5150 | 5167 |
| 7.1.4 | Incident-triggered review (automatic “post-mortem”) | 5168 | 5182 |
| 7.1.5 | Acceptance Tests | 5183 | 5226 |
| 7.2 | Data Retention & Disk Watermarks — MUST implement | 5227 | 5316 |
| 8 | . Release Gates (Promotion Certification Checklist — HARD PASS/FAIL) | 5317 | 5325 |
| 8.1 | Measurable Metrics (PASS/FAIL) | 5326 | 5363 |
| 8.2 | Minimum Test Suite (The Torture Chamber) | 5364 | 5462 |
| 8.3 | Canary Rollout Protocol (Hard Gate) | 5463 | 5469 |
| 8.4 | Promotion Certification Artifact (Hard Gate Implementation) | 5470 | 5496 |
| A.CSP | Core Safety Defaults | 5497 | 5514 |
| A.GOP | Governance & Optimization Defaults | 5515 | 5545 |
| A.1 | Atomic Group Execution | 5546 | 5581 |
| A.1.1 | Inventory Skew Gate | 5582 | 5619 |
| A.2 | Reflexive Cortex (Microstructure Collapse) | 5620 | 5764 |
| A.2.1 | Runtime Binding & Critical Inputs | 5765 | 5801 |
| A.3 | Watchdog & Recovery | 5802 | 6072 |
| A.3.1 | Emergency Close & Liquidity Gates | 6073 | 6104 |
| A.4 | Fee Model Staleness | 6105 | 6141 |
| A.5 | SVI Stability Guards | 6142 | 6167 |
| A.6 | Retention & Replay Windows | 6168 | 6223 |
| A.7 | Summary Table | 6224 | 6307 |
| CSP.0 | Scope | 6308 | 6315 |
| CSP.1 | Definitions (Self-Contained) | 6316 | 6360 |
| CSP.2 | Idempotency & Deduplication | 6361 | 6362 |
| CSP.2.1 | Stable Intent Identity | 6363 | 6373 |
| CSP.2.2 | Deduplication Rule | 6374 | 6382 |
| CSP.3 | RecordedBeforeDispatch (WAL) | 6383 | 6384 |
| CSP.3.1 | Mandatory Recording for OPEN | 6385 | 6392 |
| CSP.3.2 | WAL Degradation Semantics | 6393 | 6401 |
| CSP.4 | Restart, Gaps, and Reconciliation | 6402 | 6403 |
| CSP.4.1 | Restart Safety | 6404 | 6411 |
| CSP.4.2 | No Duplicate Sends | 6412 | 6415 |
| CSP.4.3 | WS Gap / Session Termination | 6416 | 6422 |
| CSP.5 | TradingMode Semantics & Enforcement | 6423 | 6424 |
| CSP.5.1 | Modes | 6425 | 6430 |
| CSP.5.2 | Enforcement Rules | 6431 | 6440 |
| CSP.5.3 | Safety-Critical Prerequisite: Runtime Binding Gate | 6441 | 6448 |
| CSP.6 | Capital Supremacy (No Stranded Exposure) | 6449 | 6459 |
| CSP.7 | Deterministic Emergency Containment | 6460 | 6479 |
| CSP.8 | Timebase Authority (Safety-Critical) | 6480 | 6487 |
| CSP.9 | Profile Isolation | 6488 | 6504 |
| CSP.10 | CSP_ONLY Build/Test Mode (Mechanically Enforced) | 6505 | 6518 |
| CSP.11 | Explicit Non-Requirements | 6519 | 6531 |
| CSP.12 | Acceptance Tests | 6532 | 6598 |
