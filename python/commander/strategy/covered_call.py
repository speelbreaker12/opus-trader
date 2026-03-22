"""Covered Call Strategy — generates sell-call intents against spot/perp holdings.

A covered call sells OTM call options against an existing long position in the
underlying. Premium collected = income; risk = capped upside if underlying
rallies past the strike.

This module:
1. Selects eligible strikes/expiries from the options chain
2. Sizes the call sell to stay within the covered portion of the position
3. Produces TradeIntents that flow through the Soldier execution engine
4. Integrates with slippage calibration (§4.5) for predicted_slippage_bps_sim

Design principle: fail-closed. If any input is uncertain (position size, book
data, Greeks), we produce NO intents rather than risk naked exposure.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

from .types import (
    IntentClass,
    L2Level,
    L2Snapshot,
    OptionSpec,
    OptionType,
    Side,
    TradeIntent,
)


# ── Configuration ────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class CoveredCallConfig:
    """Strategy parameters for covered call generation.

    All fields have pessimistic defaults (fail-closed).
    """

    # Strike selection
    min_delta: float = 0.05  # Minimum delta for eligible strikes
    max_delta: float = 0.30  # Maximum delta — higher = more premium but more risk
    min_days_to_expiry: int = 2  # Skip very short-dated (gamma risk)
    max_days_to_expiry: int = 45  # Skip long-dated (capital lock)

    # Sizing — fraction of underlying position to cover
    max_coverage_ratio: float = 0.80  # Never sell calls on >80% of position
    min_position_coin: float = 0.01  # Minimum position to bother with

    # Edge / premium thresholds
    min_annualized_yield_pct: float = 5.0  # Skip low-premium strikes
    min_premium_usd: float = 1.0  # Absolute floor on premium collected
    min_bid_size_coin: float = 0.01  # Skip illiquid option books

    # Risk limits
    max_open_short_calls: int = 3  # Max simultaneous short call positions
    min_spread_bps: float = 0.0  # No spread filter by default
    max_spread_bps: float = 500.0  # Skip if bid-ask > 5%

    # Strategy identity
    strategy_id: str = "covered_call_v1"


# ── Domain types ─────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class OptionChainEntry:
    """A single option from the venue's chain listing."""

    spec: OptionSpec
    instrument_id: str
    delta: Optional[float]  # Greek — None if unavailable
    days_to_expiry: float
    mark_price: Optional[float]  # Venue mark, in coin terms
    book: Optional[L2Snapshot]


@dataclass(frozen=True)
class UnderlyingPosition:
    """Current position in the underlying asset."""

    instrument_id: str  # e.g. "BTC-PERPETUAL"
    coin_qty: float  # Positive = long
    avg_entry_price: float
    spot_price: float  # Current spot/index price


@dataclass(frozen=True)
class ExistingShortCall:
    """An already-open short call position."""

    instrument_id: str
    coin_qty: float  # Positive = number of calls sold
    strike: float
    expiry: str


class SkipReason(Enum):
    """Why a candidate strike was skipped."""

    NO_BOOK = "no_book_data"
    NO_DELTA = "no_delta"
    DELTA_OUT_OF_RANGE = "delta_out_of_range"
    EXPIRY_TOO_SHORT = "expiry_too_short"
    EXPIRY_TOO_LONG = "expiry_too_long"
    ILLIQUID = "illiquid_book"
    SPREAD_TOO_WIDE = "spread_too_wide"
    PREMIUM_TOO_LOW = "premium_too_low"
    YIELD_TOO_LOW = "yield_too_low"


@dataclass
class CandidateEvaluation:
    """Result of evaluating a single option chain entry."""

    entry: OptionChainEntry
    eligible: bool
    skip_reason: Optional[SkipReason] = None
    annualized_yield_pct: Optional[float] = None
    premium_usd: Optional[float] = None
    spread_bps: Optional[float] = None


@dataclass
class StrategyOutput:
    """Complete output from one strategy evaluation cycle."""

    intents: list[TradeIntent]
    candidates_evaluated: int
    candidates_eligible: int
    skipped: list[CandidateEvaluation]
    available_coverage_coin: float
    reason_if_no_intents: Optional[str] = None


# ── Core strategy ────────────────────────────────────────────────────────────


def evaluate_candidates(
    config: CoveredCallConfig,
    position: UnderlyingPosition,
    chain: list[OptionChainEntry],
    existing_shorts: list[ExistingShortCall],
) -> StrategyOutput:
    """Evaluate the options chain and generate covered call intents.

    Fail-closed: returns empty intents if any precondition fails.
    """
    # ── Precondition: must have a long underlying position ────────────────
    if position.coin_qty < config.min_position_coin:
        return StrategyOutput(
            intents=[],
            candidates_evaluated=0,
            candidates_eligible=0,
            skipped=[],
            available_coverage_coin=0.0,
            reason_if_no_intents="position_too_small",
        )

    if not math.isfinite(position.spot_price) or position.spot_price <= 0:
        return StrategyOutput(
            intents=[],
            candidates_evaluated=0,
            candidates_eligible=0,
            skipped=[],
            available_coverage_coin=0.0,
            reason_if_no_intents="invalid_spot_price",
        )

    # ── Compute available coverage ───────────────────────────────────────
    already_covered = sum(s.coin_qty for s in existing_shorts)
    max_coverable = position.coin_qty * config.max_coverage_ratio
    available_coin = max(0.0, max_coverable - already_covered)

    if available_coin < config.min_position_coin:
        return StrategyOutput(
            intents=[],
            candidates_evaluated=0,
            candidates_eligible=0,
            skipped=[],
            available_coverage_coin=available_coin,
            reason_if_no_intents="fully_covered",
        )

    # ── Check max open short calls ───────────────────────────────────────
    if len(existing_shorts) >= config.max_open_short_calls:
        return StrategyOutput(
            intents=[],
            candidates_evaluated=0,
            candidates_eligible=0,
            skipped=[],
            available_coverage_coin=available_coin,
            reason_if_no_intents="max_short_calls_reached",
        )

    # ── Filter to CALL options only ──────────────────────────────────────
    calls = [e for e in chain if e.spec.option_type == OptionType.CALL]

    # ── Evaluate each candidate ──────────────────────────────────────────
    evaluations: list[CandidateEvaluation] = []
    eligible: list[CandidateEvaluation] = []

    for entry in calls:
        ev = _evaluate_single(config, entry, position.spot_price)
        evaluations.append(ev)
        if ev.eligible:
            eligible.append(ev)

    if not eligible:
        return StrategyOutput(
            intents=[],
            candidates_evaluated=len(evaluations),
            candidates_eligible=0,
            skipped=[e for e in evaluations if not e.eligible],
            available_coverage_coin=available_coin,
            reason_if_no_intents="no_eligible_strikes",
        )

    # ── Rank by annualized yield (highest first) ─────────────────────────
    eligible.sort(
        key=lambda e: e.annualized_yield_pct if e.annualized_yield_pct else 0.0,
        reverse=True,
    )

    # ── Generate intent for best candidate ───────────────────────────────
    best = eligible[0]
    entry = best.entry

    # Size: min(available_coin, best bid size) — don't exceed what the book offers
    bid_size = _best_bid_size(entry.book) or 0.0
    intent_qty = min(available_coin, bid_size) if bid_size > 0 else 0.0

    if intent_qty < config.min_position_coin:
        return StrategyOutput(
            intents=[],
            candidates_evaluated=len(evaluations),
            candidates_eligible=len(eligible),
            skipped=[e for e in evaluations if not e.eligible],
            available_coverage_coin=available_coin,
            reason_if_no_intents="insufficient_book_depth",
        )

    # Limit price = best bid (selling into the bid for covered call)
    limit_price = entry.book.best_bid if entry.book else None
    if limit_price is None or not math.isfinite(limit_price) or limit_price <= 0:
        return StrategyOutput(
            intents=[],
            candidates_evaluated=len(evaluations),
            candidates_eligible=len(eligible),
            skipped=[e for e in evaluations if not e.eligible],
            available_coverage_coin=available_coin,
            reason_if_no_intents="no_valid_bid",
        )

    premium_usd = best.premium_usd or 0.0
    # predicted slippage: estimate from spread
    spread_bps = best.spread_bps or 0.0
    predicted_slippage_bps = spread_bps * 0.5  # Half-spread as baseline estimate

    intent = TradeIntent(
        instrument_id=entry.instrument_id,
        side=Side.SELL,
        qty_coin=intent_qty,
        limit_price=limit_price,
        intent_class=IntentClass.OPEN,  # Opening a short call position
        reduce_only=False,
        strategy_id=config.strategy_id,
        gross_edge_usd=premium_usd,
        predicted_slippage_bps_sim=predicted_slippage_bps,
    )

    return StrategyOutput(
        intents=[intent],
        candidates_evaluated=len(evaluations),
        candidates_eligible=len(eligible),
        skipped=[e for e in evaluations if not e.eligible],
        available_coverage_coin=available_coin,
    )


# ── Single candidate evaluation ──────────────────────────────────────────────


def _evaluate_single(
    config: CoveredCallConfig,
    entry: OptionChainEntry,
    spot_price: float,
) -> CandidateEvaluation:
    """Evaluate one option chain entry against strategy filters."""

    # Must have book data
    if entry.book is None:
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.NO_BOOK
        )

    # Must have delta
    if entry.delta is None or not math.isfinite(entry.delta):
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.NO_DELTA
        )

    # Delta range (absolute value for calls)
    abs_delta = abs(entry.delta)
    if abs_delta < config.min_delta or abs_delta > config.max_delta:
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.DELTA_OUT_OF_RANGE
        )

    # Expiry range
    if entry.days_to_expiry < config.min_days_to_expiry:
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.EXPIRY_TOO_SHORT
        )
    if entry.days_to_expiry > config.max_days_to_expiry:
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.EXPIRY_TOO_LONG
        )

    # Liquidity: best bid must exist and meet min size
    best_bid = entry.book.best_bid
    bid_size = _best_bid_size(entry.book)
    if best_bid is None or bid_size is None:
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.ILLIQUID
        )
    if bid_size < config.min_bid_size_coin:
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.ILLIQUID
        )

    # Spread check
    best_ask = entry.book.best_ask
    if best_ask is not None and best_bid > 0:
        spread_bps = ((best_ask - best_bid) / best_bid) * 10_000
    else:
        spread_bps = float("inf")

    if spread_bps > config.max_spread_bps:
        return CandidateEvaluation(
            entry=entry, eligible=False, skip_reason=SkipReason.SPREAD_TOO_WIDE
        )

    # Premium in USD (bid price * spot for coin-denominated options like Deribit)
    premium_usd = best_bid * spot_price
    if premium_usd < config.min_premium_usd:
        return CandidateEvaluation(
            entry=entry,
            eligible=False,
            skip_reason=SkipReason.PREMIUM_TOO_LOW,
            premium_usd=premium_usd,
        )

    # Annualized yield
    days = max(entry.days_to_expiry, 0.5)  # Floor to avoid div-by-zero
    annualized_yield_pct = (premium_usd / spot_price) * (365.0 / days) * 100.0

    if annualized_yield_pct < config.min_annualized_yield_pct:
        return CandidateEvaluation(
            entry=entry,
            eligible=False,
            skip_reason=SkipReason.YIELD_TOO_LOW,
            annualized_yield_pct=annualized_yield_pct,
            premium_usd=premium_usd,
            spread_bps=spread_bps,
        )

    return CandidateEvaluation(
        entry=entry,
        eligible=True,
        annualized_yield_pct=annualized_yield_pct,
        premium_usd=premium_usd,
        spread_bps=spread_bps,
    )


# ── Helpers ──────────────────────────────────────────────────────────────────


def _best_bid_size(book: Optional[L2Snapshot]) -> Optional[float]:
    """Return the size at best bid, or None."""
    if book is None or not book.bids:
        return None
    return book.bids[0].size
