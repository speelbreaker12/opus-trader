"""Slippage Calibration (Reality Sync) — CONTRACT.md §4.5.

Continuously measures Sim vs Live slippage and produces a realism_penalty_factor
that the Replay Gatekeeper uses to penalize simulation optimism.

Formula:
    realism_penalty_factor = clamp(
        p50(realized_slippage_bps_live / max(predicted_slippage_bps_sim, eps)),
        1.0,
        2.5,
    )

Window: last N fills (default N=200), bucketed by (strategy_id, instrument_type,
liquidity_bucket).

Fail-safe: if missing or uninitialized, default factor = 1.3 (CONTRACT AT-255).
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


# ── Constants ────────────────────────────────────────────────────────────────

DEFAULT_WINDOW_SIZE: int = 200
DEFAULT_PENALTY_FACTOR: float = 1.3  # AT-255: fail-safe when missing/uninitialized
PENALTY_FLOOR: float = 1.0
PENALTY_CEILING: float = 2.5
EPS: float = 1e-9  # Avoid division by zero


# ── Domain types ─────────────────────────────────────────────────────────────


class LiquidityBucket(Enum):
    """Liquidity Gate depth buckets per CONTRACT.md."""

    THIN = "thin"
    MEDIUM = "medium"
    THICK = "thick"


@dataclass(frozen=True)
class CalibrationBucketKey:
    """Composite key for bucketed penalty factors."""

    strategy_id: str
    instrument_type: str
    liquidity_bucket: LiquidityBucket


@dataclass(frozen=True)
class FillRecord:
    """Single fill observation for calibration.

    Both values are in basis points.
    """

    predicted_slippage_bps_sim: float
    realized_slippage_bps_live: float
    bucket_key: CalibrationBucketKey


@dataclass
class CalibrationResult:
    """Output of a calibration run for one bucket."""

    bucket_key: CalibrationBucketKey
    realism_penalty_factor: float
    sample_count: int
    is_default: bool  # True when factor came from fail-safe default


# ── Core calibrator ──────────────────────────────────────────────────────────


@dataclass
class SlippageCalibrator:
    """Maintains rolling slippage ratios and computes penalty factors.

    Thread-safety: NOT thread-safe. Callers must synchronize externally if
    shared across threads.
    """

    window_size: int = DEFAULT_WINDOW_SIZE
    _buckets: dict[CalibrationBucketKey, list[float]] = field(
        default_factory=dict
    )

    def record_fill(self, fill: FillRecord) -> None:
        """Ingest a single fill observation.

        Silently drops records with non-finite or negative values (fail-closed:
        bad data must not corrupt the penalty factor).
        """
        if not _is_valid_fill(fill):
            return

        ratio = fill.realized_slippage_bps_live / max(
            fill.predicted_slippage_bps_sim, EPS
        )

        bucket = self._buckets.setdefault(fill.bucket_key, [])
        bucket.append(ratio)

        # Trim to rolling window
        if len(bucket) > self.window_size:
            del bucket[: len(bucket) - self.window_size]

    def get_penalty_factor(
        self, bucket_key: CalibrationBucketKey
    ) -> CalibrationResult:
        """Return the current realism_penalty_factor for a bucket.

        Returns the fail-safe default (1.3) if no data or insufficient data.
        """
        ratios = self._buckets.get(bucket_key)

        if not ratios:
            return CalibrationResult(
                bucket_key=bucket_key,
                realism_penalty_factor=DEFAULT_PENALTY_FACTOR,
                sample_count=0,
                is_default=True,
            )

        median = statistics.median(ratios)
        clamped = _clamp(median, PENALTY_FLOOR, PENALTY_CEILING)

        return CalibrationResult(
            bucket_key=bucket_key,
            realism_penalty_factor=clamped,
            sample_count=len(ratios),
            is_default=False,
        )

    def get_global_penalty_factor(self) -> float:
        """Convenience: return worst (highest) penalty across all buckets.

        Fail-closed: if no buckets exist, return the fail-safe default.
        """
        if not self._buckets:
            return DEFAULT_PENALTY_FACTOR

        worst = DEFAULT_PENALTY_FACTOR
        for key in self._buckets:
            result = self.get_penalty_factor(key)
            if result.realism_penalty_factor > worst:
                worst = result.realism_penalty_factor
        return worst

    def bucket_count(self) -> int:
        return len(self._buckets)

    def fill_count(self, bucket_key: CalibrationBucketKey) -> int:
        ratios = self._buckets.get(bucket_key)
        return len(ratios) if ratios else 0


# ── Helpers ──────────────────────────────────────────────────────────────────


def _clamp(value: float, floor: float, ceiling: float) -> float:
    if value < floor:
        return floor
    if value > ceiling:
        return ceiling
    return value


def _is_valid_fill(fill: FillRecord) -> bool:
    """Validate fill record fields are finite and non-negative."""
    import math

    for v in (fill.predicted_slippage_bps_sim, fill.realized_slippage_bps_live):
        if not math.isfinite(v) or v < 0.0:
            return False
    return True
