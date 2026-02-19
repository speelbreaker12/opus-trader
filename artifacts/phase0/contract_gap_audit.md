# CONTRACT.md Gap Audit: MUST/NEVER Clauses Without Isolating ATs

**Date**: 2026-02-18
**Contract Version**: 5.2
**Total Gaps Found**: 56 across 37 sections

---

## Critical Gaps (safety-critical, no AT coverage)

| # | Section | Line | Clause | Gap | AT Assigned |
|---|---------|------|--------|-----|-------------|
| 1 | §0.Z.2.2(H) | ~299 | "Clock uncertainty MAY force ReduceOnly, but **MUST NOT force Kill**" | CSP-MAP explicitly notes: *"No dedicated AT yet"* | **AT-1077** (S8-015) |
| 2 | §0.Z.2.2(G) | ~295 | "Emergency containment **MUST be monotonic** w.r.t. exposure (never increases risk)" | AT-235/338 test containment runs but not monotonicity | **AT-1076** (S7-008) |
| 3 | §1.1.1 | ~912 | "qty_q = **round_down**(raw_qty, amount_step) (**never round up** size)" | AT-219 tests price rounding only, not qty direction | **AT-1093** (S7-010) |
| 4 | §2.3 | ~2698 | "If any Cortex producer inputs are missing/stale, its candidate **MUST be ForceReduceOnly**" | No AT for Cortex-specific missing inputs (spread_bps, depth_topN, dvol) | **AT-1078** (S8-016) |
| 5 | §3.3 | ~3199 | "On observed 429: enter **RiskState::Degraded**" | AT-240 covers 10028 only, not standalone 429 | **AT-1083** (S9-006) |
| 6 | §2.3.2 | ~2795 | "**request_timeout_rate > 2%**" as bunker entry condition | No AT isolates this trigger | **AT-1081** (S8-016) |
| 7 | §5.2 | ~4011 | "Missing/out-of-range **open_haircut_mult** => **SHADOW_ONLY**" | No AT tests this fail-closed path | **AT-1088** (S13-007) |
| 8 | §2.2.3 | ~2218 | "**Recovery MUST be slower than degradation**" | Individual cooldowns tested but meta-property is not | **AT-1079** (S8-015) |

## High Gaps (behavioral MUST/NEVER, no isolation)

| # | Section | Line | Clause | Gap | AT Assigned |
|---|---------|------|--------|-----|-------------|
| 9 | Defs | ~82 | Linear Perpetuals **MUST** be treated as `linear_future` for sizing | AT-277 doesn't isolate this reclassification | **AT-1089** (S7-009) |
| 10 | Defs | ~87 | L1TickerSnapshot validity rules (bid>0, ask>0, bid<=ask, staleness) | No isolating AT for L1 validation | **AT-1090** (S8-018) |
| 11 | §1.0.Y | ~678 | Expired instrument venue response **MUST** classify as Terminal + **MUST NOT** panic + instrument-only reconciliation | AT-949 covers cancel only, not place-order | **AT-1091** (S7-009) |
| 12 | §1.1 | ~824 | All outbound orders **MUST** use s4: format | No negative test for non-s4 rejection | **AT-1092** (S7-010) |
| 13 | §1.1 | ~828 | Legacy format **MUST NOT** be sent to exchange | No isolating AT | **AT-1092** (S7-010) |
| 14 | §1.2.2 | ~1136 | Churn breaker: closes/hedges **MUST** remain allowed during blacklist | AT-221 tests rejection only | **AT-1072** (S7-006) |
| 15 | §1.2.3 | ~1177 | Self-Impact cooldown **MUST** block further OPENs for cooldown_s | No AT isolates cooldown duration enforcement | **AT-1073** (S7-006) |
| 16 | §1.4 | ~1302 | Unfilled/partial IOC: **do not chase** | No AT | **AT-1086** (S9-008) |
| 17 | §1.5 | ~1667 | Sequencing rules (close→confirm→hedge ordering) | No AT isolates ordering itself | **AT-1074** (S7-007) |
| 18 | §1.5 | ~1678 | "No step **may increase** exposure while prior step is unresolved" | AT-229 partial, doesn't isolate this | **AT-1075** (S7-007) |
| 19 | §2.1 | ~1707 | "Every TLSM transition **MUST** be WAL-appended immediately" | No isolating AT | **AT-1087** (S10-005) |
| 20 | §2.2.3 | ~2069 | TradingMode **MUST** be recomputed every tick (never stored) | No AT proves "never stored" | **AT-1080** (S8-015) |
| 21 | §2.2.5 | ~2619 | Cancel/replace **MUST NOT** cancel protective reduce-only orders | No AT isolates this rule | **AT-1082** (S8-017) |
| 22 | §2.4 | ~3017 | Trade-ID: WAL append **MUST** precede TLSM/position updates | No AT tests write ordering | **AT-1085** (S9-007) |
| 23 | §3.3 | ~3198 | Token bucket empty: async sleep, **Never panic** | No AT | **AT-1084** (S9-006) |
| 24 | §CSP.5.2 | ~5794 | OPEN needs Active **AND** latch clear **AND** RecordedBeforeDispatch — all three conjunctively | No single AT tests the conjunction | **AT-1094** (S8-018) |

## Moderate Gaps (operational, cadence, format, CI)

| # | Section | Line | Clause | AT Assigned |
|---|---------|------|--------|-------------|
| 25 | §0.Z.2.2 | ~243 | Idempotency keys **MUST NOT** depend on RNG or process-local counters (wall-clock covered) | **AT-1095** (S9-009) |
| 26 | §0.Z.2.2(B) | ~253 | WAL **MUST** be append-only and crash-safe (no AT for property) | **AT-1096** (S9-009) |
| 27 | §0.Z.2.3 | ~313 | Implemented GOP subsystem **MUST NOT** negate CSP guarantees | **AT-1119** (S14-001) |
| 28 | §0.Z.5 | ~413 | Every AT **MUST** be tagged to exactly one profile | **AT-1120** (S14-002) |
| 29 | §0.Z.5 | ~426 | CI: GOP test failure → features disabled (not tested) | **AT-1121** (S14-002) |
| 30 | §0.Z.6 | ~430 | Deployment **MUST** declare + enforce its profile | **AT-1122** (S14-001) |
| 31 | §0.Z.7.4 | ~483 | /status **MUST NOT** claim GOP enforcement when CSP-only | **AT-1115** (S8-019) |
| 32 | §1.0 | ~610 | **Never mix** coin sizing and USD sizing in one intent | **AT-1097** (S7-011) |
| 33 | §1.1.1 | ~962 | Every fill **MUST** map to group_id + leg_idx | **AT-1098** (S9-010) |
| 34 | §1.4.4 | ~1578 | Missing ENABLE_LINKED_ORDERS **MUST** default false (fail-closed) | **AT-1099** (S7-011) |
| 35 | §2.2.0 | ~1772 | Relaxed loads/stores for safety-critical publication is non-compliant | **AT-1118** (S10-008) |
| 36 | §2.2.3.5 | ~2249 | mode_reasons computed **every tick** (cadence not tested) | Already AT-1080 |
| 37 | §2.2.4 | ~2553 | Missing trades within lookback **MUST** prevent reconciliation success | **AT-1100** (S9-010) |
| 38 | §2.2.6 | ~2644 | RejectReasonCode registry **MUST** be complete w.r.t. contract | **AT-1101** (S9-011) |
| 39 | §2.3.1 | ~2753 | Poll /get_announcements **every 60s** | **AT-1111** (S10-007) |
| 40 | §2.4 | ~2927 | Write every TLSM transition immediately (WAL append-only) | Already AT-1087 |
| 41 | §3.1 | ~3056 | AtomicNakedEvent `cause` field **MUST** be non-empty | **AT-1102** (S9-011) |
| 42 | §3.2 | ~3121 | Watchdog triggers on silence **> 5s** | Already AT-297 |
| 43 | §3.4 | ~3389 | Reconciliation timer **every 5-10s** | **AT-1112** (S9-012) |
| 44 | §3.4 | ~3395 | Corrective actions **MUST** enumerate all four types | **AT-1103** (S9-012) |
| 45 | §3.5 | ~3417 | Zombie sweeper cadence **every 10s** | **AT-1113** (S9-012) |
| 46 | §4.1 | ~3477 | Single-tick drift rejection (hold previous SVI params) | **AT-1104** (S11-003) |
| 47 | §4.1.1 | ~3500 | Calendar monotonicity + negative density guards (only butterfly convexity has AT) | **AT-1105** (S11-003) |
| 48 | §4.2 | ~3550 | Fee model polling **every 60s** | **AT-1114** (S10-006) |
| 49 | §4.2 | ~3552 | fee_model_cached_at_ts **MUST** be epoch ms (not monotonic) | **AT-1106** (S10-006) |
| 50 | §4.3 | ~3635 | chrony/NTP **MUST** be an operational prerequisite | **AT-1123** (S10-007) |
| 51 | §5.3 | ~4112 | Canary Stage 0 minimum duration + no live orders | **AT-1107** (S13-008) |
| 52 | §7.0 | ~4288 | /status GOP keys **MUST** be omitted or NOT_ENFORCED under CSP | **AT-1116** (S8-019) |
| 53 | §7.0 | ~4297 | 429_count / 10028_count (non-5m) **MUST NOT** be used | **AT-1117** (S9-013) |
| 54 | §7.1 | ~4498 | Lifecycle events + policy events **MUST** be persisted | **AT-1108** (S12-002) |
| 55 | §7.1 | ~4533 | Auto-apply blocked when incident triggers in last 24h | **AT-1109** (S12-002) |
| 56 | §7.2 | ~4614 | Decision Snapshots **MUST** be day/hour partitioned | **AT-1110** (S13-008) |

---

## Summary

| Severity | Count | AT Assigned | Description |
|----------|-------|-------------|-------------|
| Critical | 8 | 8/8 | Safety-critical clauses that could allow unsafe state if unmet |
| High | 16 | 16/16 | Behavioral MUST/NEVER requirements with no isolating AT |
| Moderate | 32 | 32/32 (3 already covered) | Operational, cadence, format, and CI requirements |
| **Total** | **56** | **56/56** | All gaps now have AT assignments |

### Most Urgent (recommended first batch)

1. **Wall-clock MUST NOT trigger Kill** (§0.Z.2.2(H)) — contract itself acknowledges this gap in CSP-MAP
2. **Emergency containment monotonicity** (§0.Z.2.2(G)) — core CSP safety invariant
3. **Quantity rounding direction** (§1.1.1) — wrong direction = over-sized orders
4. **Cortex missing inputs → ForceReduceOnly** (§2.3) — fail-open hazard
5. **429 → RiskState::Degraded** (§3.3) — venue rate limit survival
6. **request_timeout_rate bunker entry** (§2.3.2) — network degradation detection
7. **open_haircut_mult missing → SHADOW_ONLY** (§5.2) — replay safety
8. **Recovery slower than degradation** (§2.2.3) — prevents oscillation

### Methodology

- Read all ~5900 lines of CONTRACT.md
- Identified normative clauses containing MUST, NEVER, SHALL, SHALL NOT, or "per" frequency requirements
- Cross-referenced each clause against AT-xxx acceptance tests in the same section
- A clause is "covered" only if an AT specifically isolates that requirement
- Skipped non-normative sections (Patch Summaries, §6 roadmap, Appendix A threshold-only values)
