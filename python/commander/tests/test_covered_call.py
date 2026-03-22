"""Tests for covered call strategy."""

import math

from commander.strategy.covered_call import (
    CandidateEvaluation,
    CoveredCallConfig,
    ExistingShortCall,
    OptionChainEntry,
    SkipReason,
    StrategyOutput,
    UnderlyingPosition,
    evaluate_candidates,
)
from commander.strategy.types import (
    IntentClass,
    L2Level,
    L2Snapshot,
    OptionSpec,
    OptionType,
    Side,
)


def _position(
    coin_qty: float = 1.0,
    spot: float = 60000.0,
) -> UnderlyingPosition:
    return UnderlyingPosition(
        instrument_id="BTC-PERPETUAL",
        coin_qty=coin_qty,
        avg_entry_price=58000.0,
        spot_price=spot,
    )


def _book(
    bid_price: float = 0.020,
    bid_size: float = 5.0,
    ask_price: float = 0.0205,
    ask_size: float = 5.0,
) -> L2Snapshot:
    return L2Snapshot(
        bids=[L2Level(price=bid_price, size=bid_size)],
        asks=[L2Level(price=ask_price, size=ask_size)],
        timestamp_ms=1700000000000,
    )


def _entry(
    strike: float = 70000.0,
    delta: float | None = 0.15,
    days: float = 14.0,
    book: L2Snapshot | None = None,
    option_type: OptionType = OptionType.CALL,
    instrument_id: str = "BTC-25APR26-70000-C",
) -> OptionChainEntry:
    return OptionChainEntry(
        spec=OptionSpec(
            underlying="BTC",
            expiry="2026-04-25",
            strike=strike,
            option_type=option_type,
        ),
        instrument_id=instrument_id,
        delta=delta,
        days_to_expiry=days,
        mark_price=0.02,
        book=book if book is not None else _book(),
    )


# ── Happy path ───────────────────────────────────────────────────────────────


class TestHappyPath:
    def test_generates_sell_intent(self) -> None:
        config = CoveredCallConfig()
        chain = [_entry()]
        result = evaluate_candidates(config, _position(), chain, [])

        assert len(result.intents) == 1
        intent = result.intents[0]
        assert intent.side == Side.SELL
        assert intent.intent_class == IntentClass.OPEN
        assert not intent.reduce_only
        assert intent.strategy_id == config.strategy_id
        assert intent.qty_coin > 0
        assert intent.limit_price > 0

    def test_premium_and_slippage_populated(self) -> None:
        config = CoveredCallConfig()
        result = evaluate_candidates(config, _position(), [_entry()], [])
        intent = result.intents[0]
        assert intent.gross_edge_usd > 0
        assert intent.predicted_slippage_bps_sim >= 0


# ── Fail-closed: no position ────────────────────────────────────────────────


class TestNoPosition:
    def test_zero_position_no_intents(self) -> None:
        result = evaluate_candidates(
            CoveredCallConfig(), _position(coin_qty=0.0), [_entry()], []
        )
        assert result.intents == []
        assert result.reason_if_no_intents == "position_too_small"

    def test_negative_position_no_intents(self) -> None:
        result = evaluate_candidates(
            CoveredCallConfig(), _position(coin_qty=-1.0), [_entry()], []
        )
        assert result.intents == []


# ── Fail-closed: invalid spot ────────────────────────────────────────────────


class TestInvalidSpot:
    def test_nan_spot_no_intents(self) -> None:
        result = evaluate_candidates(
            CoveredCallConfig(),
            _position(spot=float("nan")),
            [_entry()],
            [],
        )
        assert result.intents == []
        assert result.reason_if_no_intents == "invalid_spot_price"

    def test_zero_spot_no_intents(self) -> None:
        result = evaluate_candidates(
            CoveredCallConfig(), _position(spot=0.0), [_entry()], []
        )
        assert result.intents == []


# ── Coverage limits ──────────────────────────────────────────────────────────


class TestCoverageLimits:
    def test_fully_covered_no_intents(self) -> None:
        config = CoveredCallConfig(max_coverage_ratio=0.80)
        shorts = [ExistingShortCall("X", 0.85, 70000.0, "2026-04-25")]
        result = evaluate_candidates(
            config, _position(coin_qty=1.0), [_entry()], shorts
        )
        assert result.intents == []
        assert result.reason_if_no_intents == "fully_covered"

    def test_partial_coverage_sizes_correctly(self) -> None:
        config = CoveredCallConfig(max_coverage_ratio=0.80)
        shorts = [ExistingShortCall("X", 0.50, 70000.0, "2026-04-25")]
        result = evaluate_candidates(
            config, _position(coin_qty=1.0), [_entry()], shorts
        )
        if result.intents:
            # Available = 1.0 * 0.8 - 0.5 = 0.3
            assert result.intents[0].qty_coin <= 0.3 + 1e-9

    def test_max_short_calls_reached(self) -> None:
        config = CoveredCallConfig(max_open_short_calls=2)
        shorts = [
            ExistingShortCall("X1", 0.1, 70000.0, "2026-04-25"),
            ExistingShortCall("X2", 0.1, 75000.0, "2026-04-25"),
        ]
        result = evaluate_candidates(
            config, _position(), [_entry()], shorts
        )
        assert result.intents == []
        assert result.reason_if_no_intents == "max_short_calls_reached"


# ── Strike filtering ────────────────────────────────────────────────────────


class TestStrikeFiltering:
    def test_put_options_skipped(self) -> None:
        put = _entry(option_type=OptionType.PUT)
        result = evaluate_candidates(
            CoveredCallConfig(), _position(), [put], []
        )
        assert result.intents == []

    def test_no_book_skipped(self) -> None:
        entry = OptionChainEntry(
            spec=OptionSpec("BTC", "2026-04-25", 70000.0, OptionType.CALL),
            instrument_id="X",
            delta=0.15,
            days_to_expiry=14.0,
            mark_price=0.02,
            book=None,
        )
        result = evaluate_candidates(
            CoveredCallConfig(), _position(), [entry], []
        )
        assert result.intents == []

    def test_no_delta_skipped(self) -> None:
        entry = _entry(delta=None)
        result = evaluate_candidates(
            CoveredCallConfig(), _position(), [entry], []
        )
        assert result.intents == []

    def test_delta_too_low_skipped(self) -> None:
        entry = _entry(delta=0.02)
        result = evaluate_candidates(
            CoveredCallConfig(min_delta=0.05), _position(), [entry], []
        )
        assert result.intents == []

    def test_delta_too_high_skipped(self) -> None:
        entry = _entry(delta=0.50)
        result = evaluate_candidates(
            CoveredCallConfig(max_delta=0.30), _position(), [entry], []
        )
        assert result.intents == []

    def test_expiry_too_short_skipped(self) -> None:
        entry = _entry(days=1.0)
        result = evaluate_candidates(
            CoveredCallConfig(min_days_to_expiry=2), _position(), [entry], []
        )
        assert result.intents == []

    def test_expiry_too_long_skipped(self) -> None:
        entry = _entry(days=60.0)
        result = evaluate_candidates(
            CoveredCallConfig(max_days_to_expiry=45), _position(), [entry], []
        )
        assert result.intents == []


# ── Liquidity filtering ─────────────────────────────────────────────────────


class TestLiquidityFiltering:
    def test_wide_spread_skipped(self) -> None:
        wide_book = _book(bid_price=0.01, ask_price=0.02)  # 100% spread
        entry = _entry(book=wide_book)
        result = evaluate_candidates(
            CoveredCallConfig(max_spread_bps=500.0), _position(), [entry], []
        )
        assert result.intents == []

    def test_illiquid_bid_skipped(self) -> None:
        thin_book = _book(bid_size=0.001)
        entry = _entry(book=thin_book)
        result = evaluate_candidates(
            CoveredCallConfig(min_bid_size_coin=0.01), _position(), [entry], []
        )
        assert result.intents == []


# ── Yield filtering ──────────────────────────────────────────────────────────


class TestYieldFiltering:
    def test_low_premium_skipped(self) -> None:
        # Very low bid = low premium
        low_book = _book(bid_price=0.000001)
        entry = _entry(book=low_book)
        result = evaluate_candidates(
            CoveredCallConfig(min_premium_usd=1.0), _position(), [entry], []
        )
        assert result.intents == []


# ── Ranking ──────────────────────────────────────────────────────────────────


class TestRanking:
    def test_best_yield_selected(self) -> None:
        # Two candidates: one with higher premium
        high_book = _book(bid_price=0.04, ask_price=0.0408)
        low_book = _book(bid_price=0.01, ask_price=0.0102)
        high_entry = _entry(
            strike=65000.0,
            book=high_book,
            instrument_id="HIGH",
        )
        low_entry = _entry(
            strike=80000.0,
            book=low_book,
            instrument_id="LOW",
        )

        result = evaluate_candidates(
            CoveredCallConfig(), _position(), [high_entry, low_entry], []
        )
        assert len(result.intents) == 1
        assert result.intents[0].instrument_id == "HIGH"
