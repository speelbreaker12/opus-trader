"""Tests for slippage calibration — CONTRACT.md §4.5, AT-255."""

import math

from commander.analytics.slippage_calibration import (
    DEFAULT_PENALTY_FACTOR,
    EPS,
    PENALTY_CEILING,
    PENALTY_FLOOR,
    CalibrationBucketKey,
    CalibrationResult,
    FillRecord,
    LiquidityBucket,
    SlippageCalibrator,
)


def _key(
    strategy: str = "cc_v1",
    instrument: str = "option",
    bucket: LiquidityBucket = LiquidityBucket.MEDIUM,
) -> CalibrationBucketKey:
    return CalibrationBucketKey(strategy, instrument, bucket)


def _fill(
    predicted: float = 5.0,
    realized: float = 6.0,
    key: CalibrationBucketKey | None = None,
) -> FillRecord:
    return FillRecord(
        predicted_slippage_bps_sim=predicted,
        realized_slippage_bps_live=realized,
        bucket_key=key or _key(),
    )


# ── AT-255: Core convergence test ────────────────────────────────────────────


class TestAT255Convergence:
    """AT-255: 50 synthetic fills where realized = sim * 1.2 → factor ~1.2."""

    def test_factor_converges_to_1_2(self) -> None:
        cal = SlippageCalibrator(window_size=200)

        for _ in range(50):
            cal.record_fill(_fill(predicted=10.0, realized=12.0))

        result = cal.get_penalty_factor(_key())
        assert not result.is_default
        assert result.sample_count == 50
        assert abs(result.realism_penalty_factor - 1.2) < 0.05  # ±0.05

    def test_factor_stable_after_convergence(self) -> None:
        cal = SlippageCalibrator(window_size=200)

        for _ in range(200):
            cal.record_fill(_fill(predicted=10.0, realized=12.0))

        r1 = cal.get_penalty_factor(_key())

        # Add 10 more — should stay stable
        for _ in range(10):
            cal.record_fill(_fill(predicted=10.0, realized=12.0))

        r2 = cal.get_penalty_factor(_key())
        assert abs(r1.realism_penalty_factor - r2.realism_penalty_factor) < 0.01


# ── AT-255: Fail-safe default ────────────────────────────────────────────────


class TestAT255FailSafeDefault:
    """AT-255: if missing/uninitialized, default factor = 1.3."""

    def test_missing_bucket_returns_default(self) -> None:
        cal = SlippageCalibrator()
        result = cal.get_penalty_factor(_key())
        assert result.is_default
        assert result.realism_penalty_factor == DEFAULT_PENALTY_FACTOR
        assert result.sample_count == 0

    def test_global_penalty_empty_returns_default(self) -> None:
        cal = SlippageCalibrator()
        assert cal.get_global_penalty_factor() == DEFAULT_PENALTY_FACTOR


# ── Clamping ─────────────────────────────────────────────────────────────────


class TestClamping:
    def test_floor_clamp(self) -> None:
        """Factor cannot go below 1.0 even if realized < predicted."""
        cal = SlippageCalibrator()
        for _ in range(50):
            cal.record_fill(_fill(predicted=10.0, realized=5.0))

        result = cal.get_penalty_factor(_key())
        assert result.realism_penalty_factor == PENALTY_FLOOR

    def test_ceiling_clamp(self) -> None:
        """Factor cannot exceed 2.5 even with extreme slippage."""
        cal = SlippageCalibrator()
        for _ in range(50):
            cal.record_fill(_fill(predicted=1.0, realized=100.0))

        result = cal.get_penalty_factor(_key())
        assert result.realism_penalty_factor == PENALTY_CEILING


# ── Rolling window ───────────────────────────────────────────────────────────


class TestRollingWindow:
    def test_window_trims_old_data(self) -> None:
        cal = SlippageCalibrator(window_size=10)

        # Fill with 10 high-ratio observations
        for _ in range(10):
            cal.record_fill(_fill(predicted=10.0, realized=20.0))

        # Now fill with 10 low-ratio observations
        for _ in range(10):
            cal.record_fill(_fill(predicted=10.0, realized=10.0))

        result = cal.get_penalty_factor(_key())
        # Should reflect only the latest 10 (ratio = 1.0)
        assert result.realism_penalty_factor == PENALTY_FLOOR
        assert result.sample_count == 10


# ── Bucketing ────────────────────────────────────────────────────────────────


class TestBucketing:
    def test_independent_buckets(self) -> None:
        cal = SlippageCalibrator()
        key_a = _key(strategy="strat_a")
        key_b = _key(strategy="strat_b")

        for _ in range(50):
            cal.record_fill(_fill(predicted=10.0, realized=12.0, key=key_a))
            cal.record_fill(_fill(predicted=10.0, realized=20.0, key=key_b))

        result_a = cal.get_penalty_factor(key_a)
        result_b = cal.get_penalty_factor(key_b)

        assert abs(result_a.realism_penalty_factor - 1.2) < 0.05
        assert result_b.realism_penalty_factor == 2.0

    def test_global_penalty_returns_worst(self) -> None:
        cal = SlippageCalibrator()
        key_a = _key(strategy="strat_a")
        key_b = _key(strategy="strat_b")

        for _ in range(50):
            cal.record_fill(_fill(predicted=10.0, realized=12.0, key=key_a))
            cal.record_fill(_fill(predicted=10.0, realized=20.0, key=key_b))

        global_factor = cal.get_global_penalty_factor()
        assert global_factor == 2.0


# ── Invalid data (fail-closed) ───────────────────────────────────────────────


class TestInvalidDataFailClosed:
    def test_nan_predicted_dropped(self) -> None:
        cal = SlippageCalibrator()
        cal.record_fill(_fill(predicted=float("nan"), realized=10.0))
        assert cal.fill_count(_key()) == 0

    def test_inf_realized_dropped(self) -> None:
        cal = SlippageCalibrator()
        cal.record_fill(_fill(predicted=10.0, realized=float("inf")))
        assert cal.fill_count(_key()) == 0

    def test_negative_predicted_dropped(self) -> None:
        cal = SlippageCalibrator()
        cal.record_fill(_fill(predicted=-1.0, realized=10.0))
        assert cal.fill_count(_key()) == 0

    def test_negative_realized_dropped(self) -> None:
        cal = SlippageCalibrator()
        cal.record_fill(_fill(predicted=10.0, realized=-1.0))
        assert cal.fill_count(_key()) == 0

    def test_zero_predicted_uses_eps(self) -> None:
        """Zero predicted should not crash — uses max(predicted, eps)."""
        cal = SlippageCalibrator()
        cal.record_fill(_fill(predicted=0.0, realized=10.0))
        assert cal.fill_count(_key()) == 1
        result = cal.get_penalty_factor(_key())
        # ratio = 10.0 / eps → clamped to 2.5
        assert result.realism_penalty_factor == PENALTY_CEILING
