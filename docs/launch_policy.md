# Launch Policy (Phase 0)

> **Purpose:** Owner-readable, binding constraints for what the system is allowed to do.
> If something is not explicitly allowed here, it is **forbidden** (fail-closed).

## Metadata
- policy_id: LP-001
- policy_version: 1.1
- contract_version_target: 5.2
- effective_date_utc: 2026-01-27
- owner: [FILL]
- prepared_by: [FILL]
- last_updated_utc: 2026-02-09T00:00:00Z

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
- Product family: Inverse options (BTC/ETH-settled on Deribit)
- Expiries allowed: All standard monthly/quarterly
- Strikes allowed: All listed
- Price/index reference: Deribit USD index + Deribit mark price
- Strike/quote convention: USD

**Perpetual hedge rule (deterministic):**
- Product family: Deribit linear USDC-settled perpetuals (`*_USDC-PERPETUAL`)
- Perpetual orders are allowed only when BOTH hold versus the pre-trade snapshot:
  - `abs(net_delta_after) < abs(net_delta_before)`
  - `gross_notional_after_usd <= gross_notional_before_usd`
- Otherwise: reject intent (fail-closed).

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

### Measurement Definitions (non-negotiable)

- `equity_usd` = cash balance + unrealized PnL, valued at Deribit mark price.
- Daily window = `00:00:00` to `23:59:59` UTC.
- Weekly window = Monday `00:00:00` UTC to Sunday `23:59:59` UTC.
- `max_daily_loss_usd` = `equity_start_of_day_utc - equity_now_utc` (realized + unrealized).
- `max_weekly_loss_usd` = `equity_start_of_week_utc - equity_now_utc` (realized + unrealized).
- `max_drawdown_pct` = `((equity_peak_since_week_start_utc - equity_now_utc) / equity_peak_since_week_start_utc) * 100`.
- `gross_notional_usd` = sum of absolute open-position notional + absolute resting OPEN-order notional, where each leg uses `quantity * contract_multiplier * Deribit_index_price`.

### Global Limits
| Metric | Limit | Action on Breach |
|--------|-------|------------------|
| max_daily_loss_usd | $5,000 | Trigger REDUCE_ONLY (latched) + notify |
| max_weekly_loss_usd | $15,000 | Trigger KILL (latched) + notify |
| max_drawdown_pct | 10% | Trigger REDUCE_ONLY (latched) + notify |
| max_gross_notional_usd | $500,000 | Hard reject |

**Latch rule (capital-supremacy):**
- Daily-loss, weekly-loss, and drawdown mode triggers are latched until manual reset + recorded approval.
- Manual reset requires a recorded artifact under `evidence/phase*/` linked in sign-off notes.

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

Exit from micro-live to full-production limits is allowed only when all are true:
1) At least 14 calendar days elapsed in LIVE.
2) Zero unresolved incidents remain open.
3) Phase-2 status/alerts controls are operational and verified in latest sign-off evidence.

---

## Kill / Stop Rules (owner intent)

- **KILL** means: automated dispatch disabled; no OPEN risk permitted.
  - Allowed: explicit emergency risk-reduction + cancels (reduce-only where supported)
  - Forbidden: any new OPENs, any strategy-driven new positions
- **REDUCE_ONLY** means: automated containment allowed; OPEN forbidden; only risk-reducing orders permitted
- Risk reduction MUST remain possible if exposure exists.
- Any transition into KILL or REDUCE_ONLY is latched until manual reset + recorded approval.

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
