---
status: in-progress
priority: P2
branch: develop
pr:
started: "2026-03-16"
---

## Current State
Iterating on 5 freqtrade paper trading bots to improve signal quality and reduce fee drag.
Regime filter bug fixed (object dtype coercion); all strategies improved significantly.

## Key Files
- `/Users/admin/Desktop/freqtrade/agent-harness/strategies/btc_perp_breakout_15m.py` ← BTC breakout (port 8082)
- `/Users/admin/Desktop/freqtrade/agent-harness/strategies/btc_meanrev_rsi_5m.py` ← BTC RSI meanrev (port 8084)
- `/Users/admin/Desktop/freqtrade/agent-harness/strategies/eth_meanrev_rsi_15m.py` ← ETH RSI 15m (port 8083, new)
- `/Users/admin/Desktop/freqtrade/agent-harness/strategies/_perp_base.py`

## Log

### 2026-03-16 (Session 1)
- Fixed regime filter bug: `~regime_bull_1d` was no-op because merge_informative_pair converts bool→object dtype; `~True` gives -2 (truthy) not False. Fix: `.fillna(False).astype(bool()`.
- BtcPerpBreakout15m: lookback 20→40, VOL_SPIKE 1.5x→2.5x, time_stop 24→16. Result: -63%→-5.46%, 893→346 trades
- BtcPerpMeanrev5m: z_entry default 2.25→2.50. Result: -19%→-2.01%, 155→43 trades
- EthPerpPullback15m: target_r 2.0→1.5, min pullback depth 0.2×ATR. Result: -27%→-11.26%, 921→571 trades

### 2026-03-16 (Session 2)
- BtcPerpBreakout15m: VOL_SPIKE_MULT raised 2.5x→3.5x. Result: -5.46% (346 trades) → **-1.87% (214 trades)**. Near break-even. Deployed to live bot.
- Experiments that FAILED (all made things worse — documented in memory):
  - Longer time stops (16→32 bars): all strategies worse; losers accumulate more loss
  - z-reversal filter for meanrev: too noisy on 5m, reduced trades from 43 to 6
  - 1h trend alignment for breakout: selected overextended entries, hurt (-21.4%)
  - Fail-fast exit: hh column updates each bar, fires incorrectly on all trades
  - Deeper pullback filter/longer pullback EMA for ETH: removed more winners than losers
- Key insight: time-stopped exits are always bad; fix via ENTRY QUALITY not exit timing

### 2026-03-17 (Session 3)
- **BtcPerpBreakout15m: breakout_lookback 40→60. Result: -1.87% (214 trades) → +1.05% (183 trades). FIRST PROFITABLE STRATEGY.** Deployed.
- Cross-validated VOL_SPIKE on 2023: 3.5 better in both years. lookback=60 on 2023: -37.75% (consistently better, not overfit)
- BtcPerpMeanrev5m: hit manual optimization ceiling at -2.01%. Needs hyperopt (optuna installed next session).
- ETH 1h pullback: both 4h (no data) and 1d trend filter (-25.3%) worse than 15m (-11.26%). Fee drag structural.

### 2026-03-17 (Sessions 4-6)
- **BtcPerpBreakout15m: target_atr_mult 2.2→2.6. Result: +1.05% → +4.92%.** Deployed.
- **BtcMeanrevRSI5m (NEW)**: RSI<15 entry instead of z-score. hyperopt → rsi_entry=12 better than 15.
  - 2024: +4.06%, 8 trades | 2023: +1.29%, 20 trades. Deployed to port 8084.
- **BtcPerpBreakout15m: EMA10>EMA30 daily momentum filter added.** 2024: +4.92%→**+6.50%**, 2023: -37.75%→**-24.03%**. Strictly better. Deployed.
- **EthMeanrevRSI15m (NEW)**: RSI<12 on 15m to replace structural -11.26% ETH pullback.
  - 2024: +0.87%, 4 trades | 2023: -0.78%, 7 trades. Deploying to port 8083.
- z-score meanrev confirmed dead: 0 profitable hyperopt epochs at 0.1%/side.
- ETH breakout (-30%), ETH RSI 5m (-0.73%) all worse than ETH RSI 15m.

### 2026-03-17 (Session 9 — target sweep + filter exhaustion)
- **BtcPerpBreakout15m: target_atr_mult 2.6→3.0. Result: +17.47% → +20.21%.** Deployed to port 8082.
  - 2024: 23 target_hits at +1.86%, 40 time_stops at -0.35%
  - 2023: 4 target_hits, 56 time_stops → -11.21% (structural ranging-year loss)
- **Filter exhaustion complete — optimization ceiling reached for BtcPerpBreakout15m**:
  - ALL 6 new filters tested: lookback=80, bar_range>1.5x, regime_bull for longs, ATR expansion, 1d RSI>50, long-only
  - Pattern: every filter that helps 2023 hurts 2024 more. 2023 loss is structural.
  - Short trades in 2023 are marginally helpful; keeping can_short=True.
- BtcMeanrevRSI5m RSI exit=45 tested: worse than exit=50. Ceiling confirmed.

## Debriefs
- [[Freqtrade Paper Bot Strategies 2026-03-17 Restore]]
