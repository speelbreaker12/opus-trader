# Snapshot — docs/launch_policy.md (Phase 0)

Snapshot taken at sign-off.
- date_utc: 2026-01-27T14:00:00Z
- source_path: docs/launch_policy.md
- policy_version: 1.0

---

# Launch Policy (Phase 0)

> **Purpose:** Owner-readable, binding constraints for what the system is allowed to do.
> If something is not explicitly allowed here, it is **forbidden** (fail-closed).

## Metadata
- policy_id: LP-001
- policy_version: 1.0
- contract_version_target: 5.2
- effective_date_utc: 2026-01-27
- owner: [FILL]
- prepared_by: [FILL]
- last_updated_utc: 2026-01-27T14:00:00Z

---

## Allowed Environments (authoritative)

Environment names are canonical:

| Environment | Purpose | Real Money | Exchange Account |
|-------------|---------|------------|------------------|
| DEV | Local development, unit tests | No | None (mocked) |
| STAGING | Integration tests, CI | No | Testnet |
| PAPER | Paper trading with real data | No | Paper account |
| LIVE | Production trading | Yes | Production account |

**Hard rule:** LIVE keys/accounts MUST NOT be reachable from DEV/STAGING/PAPER.

---

## Allowed Venues / Exchanges

| Venue | Account/Subaccount | Region | Notes |
|-------|-------------------|--------|-------|
| Deribit | testnet_acct_001 | Global | STAGING |
| Deribit | paper_acct_001 | Global | PAPER |
| Deribit | prod_acct_001 | Global | LIVE |

---

## Allowed Instruments (Scope)

If an instrument is not in-scope, it MUST be rejected.

**Underlyings allowed:**
- BTC
- ETH

**Product types allowed:**
- Options (European style)
- Perpetuals (hedging only)

**Options scope:**
- Option style: European
- Expiries allowed: All standard monthly/quarterly
- Strikes allowed: All listed
- Quote currency: USD

**Explicitly forbidden:**
- [x] Spot markets
- [x] Perpetuals for speculation (hedging only)
- [x] Other underlyings (SOL, etc.)
- [x] Unknown new listings (must be explicitly added)

---

## Allowed Order Types

**Allowed:**
| Order Type | Allowed | Notes |
|------------|---------|-------|
| LIMIT | Yes | Primary order type |
| Post-only | Yes | For passive fills |
| Reduce-only | Yes | Required for risk reduction |

**Forbidden (fail-closed):**
- [x] MARKET orders
- [x] Stop/trigger orders
- [x] Hidden/iceberg orders
- [x] Any order type not listed above

---

## Risk Limits (binding)

### Global Limits
| Metric | Limit | Action on Breach |
|--------|-------|------------------|
| max_daily_loss_usd | $5,000 | Trigger REDUCE_ONLY |
| max_weekly_loss_usd | $15,000 | Trigger KILL + notify |
| max_drawdown_pct | 10% | Trigger REDUCE_ONLY |
| max_gross_notional_usd | $500,000 | Hard reject |

### Per-Underlying Limits
| Underlying | max_delta_abs | max_position_notional_usd |
|------------|---------------|---------------------------|
| BTC | 5.0 BTC | $250,000 |
| ETH | 50.0 ETH | $250,000 |

### Per-Order Limits
| Metric | Limit |
|--------|-------|
| max_order_size_contracts | 10 |
| max_orders_per_second | 5 |
| max_orders_per_minute | 100 |
| min_order_interval_ms | 200 |

### Greeks Limits
| Greek | Limit |
|-------|-------|
| max_gamma_btc_equiv | 1.0 |
| max_vega_usd | $10,000 |

---

## Micro-Live Caps (Initial Production)

When first entering LIVE, these additional caps apply for minimum 14 calendar days:

| Metric | Micro-Live Limit | Full Production |
|--------|------------------|-----------------|
| max_daily_volume_usd | $10,000 | $100,000 |
| max_open_positions | 5 | 50 |
| max_single_order_contracts | 1 | 10 |

---

## Kill / Stop Rules (owner intent)

- **KILL** means: no new OPEN risk, no new orders of any kind
- **REDUCE_ONLY** means: only risk-reducing actions permitted
- Risk reduction MUST remain possible if exposure exists

---

## Prohibited Actions (always forbidden)

- [x] Withdrawals enabled on any key
- [x] Transfers enabled on any key
- [x] Using LIVE keys outside LIVE env
- [x] Manual hotfix "temporary bypass" of risk gates
- [x] Deploying without passing verify.sh

---

## Fail-Closed Defaults (non-negotiable)

| Condition | Action |
|-----------|--------|
| Missing config key | Reject intent (no dispatch) |
| Unknown instrument | Reject intent |
| Unknown order type | Reject intent |
| Stale market data | Reject intent |
| Any ambiguity | Treat as OPEN risk → reject |

---

## Owner Sign-Off

- [ ] All limits reviewed and approved
- [ ] Fail-closed behavior understood
- [ ] Micro-live caps acceptable for initial LIVE

**owner_signature:** ______________________
**date_utc:** ______________________
