"""Replay Gatekeeper — CONTRACT.md §5.2.

48-hour policy regression test. No policy patch may be applied unless:
1. ReplayQuality is GOOD or DEGRADED (with tightening-only constraint)
2. replay_atomic_naked_events == 0
3. replay_max_drawdown_usd <= dd_limit
4. replay_net_pnl_penalized > 0 (after realism penalty from §4.5)

dd_limit MUST be explicitly configured — if missing/unparseable the gate
HARD FAILs (fail-closed).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Optional


# ── Enums ────────────────────────────────────────────────────────────────────


class ReplayQuality(Enum):
    GOOD = "GOOD"
    DEGRADED = "DEGRADED"
    BROKEN = "BROKEN"


class ReplayApplyMode(Enum):
    APPLY = "APPLY"
    APPLY_WITH_HAIRCUT = "APPLY_WITH_HAIRCUT"
    SHADOW_ONLY = "SHADOW_ONLY"


class GatekeeperVerdict(Enum):
    APPROVE = "APPROVE"
    APPROVE_WITH_HAIRCUT = "APPROVE_WITH_HAIRCUT"
    REJECT = "REJECT"
    HARD_FAIL = "HARD_FAIL"


class RejectReason(Enum):
    DD_LIMIT_MISSING = "dd_limit_missing_or_unparseable"
    DD_LIMIT_EXCEEDED = "replay_max_drawdown_usd_exceeds_dd_limit"
    ATOMIC_NAKED_EVENTS = "replay_atomic_naked_events_nonzero"
    PENALIZED_PNL_NONPOSITIVE = "replay_net_pnl_penalized_not_positive"
    REPLAY_BROKEN = "replay_quality_broken"
    LOOSENING_WHILE_DEGRADED = "loosening_patch_while_degraded"
    INVALID_INPUT = "invalid_input"


# ── Tightening classifier ───────────────────────────────────────────────────

# CONTRACT §5.2 Tightening Table (Authoritative)
# Parameter -> tighten direction is "increase" or "decrease"
TIGHTENING_TABLE: dict[str, str] = {
    "min_edge_usd": "increase",
    "limit_distance_bps": "decrease",
    "max_order_usd": "decrease",
    "inventory_skew_k": "increase",
}


@dataclass(frozen=True)
class PatchDelta:
    """A single parameter change in a policy patch."""

    parameter: str
    old_value: float
    new_value: float


def is_tightening_only(deltas: list[PatchDelta]) -> bool:
    """Return True iff every delta is tightening or unchanged.

    Any parameter NOT in the tightening table is treated as LOOSEN (fail-closed).
    """
    for delta in deltas:
        if delta.old_value == delta.new_value:
            continue  # unchanged is always OK

        direction = TIGHTENING_TABLE.get(delta.parameter)
        if direction is None:
            return False  # unknown parameter = LOOSEN

        if direction == "increase" and delta.new_value < delta.old_value:
            return False
        if direction == "decrease" and delta.new_value > delta.old_value:
            return False

    return True


# ── Inputs / Outputs ─────────────────────────────────────────────────────────


@dataclass(frozen=True)
class ReplayInput:
    """Metrics from a 48h replay run."""

    replay_net_pnl_raw: float
    replay_slippage_cost_usd: float
    replay_max_drawdown_usd: float
    replay_atomic_naked_events: int
    snapshot_coverage_pct: float
    snapshots_readable: bool


@dataclass(frozen=True)
class GatekeeperConfig:
    """Configuration for the Replay Gatekeeper.

    dd_limit: maximum allowable replay_max_drawdown_usd.
              MUST be explicitly provided — None means HARD FAIL.
    open_haircut_mult: multiplier for OPEN dispatch under DEGRADED (default 0.50).
    """

    dd_limit: Optional[float]
    open_haircut_mult: float = 0.50


@dataclass(frozen=True)
class GatekeeperResult:
    verdict: GatekeeperVerdict
    reject_reasons: list[RejectReason]
    replay_quality: ReplayQuality
    apply_mode: ReplayApplyMode
    replay_net_pnl_penalized: Optional[float]
    realism_penalty_factor: float


# ── Core gate ────────────────────────────────────────────────────────────────


def derive_replay_quality(
    snapshot_coverage_pct: float,
    snapshots_readable: bool,
) -> ReplayQuality:
    """Derive ReplayQuality from snapshot coverage per CONTRACT §5.2."""
    if not snapshots_readable:
        return ReplayQuality.BROKEN
    if not math.isfinite(snapshot_coverage_pct):
        return ReplayQuality.BROKEN
    if snapshot_coverage_pct >= 95.0:
        return ReplayQuality.GOOD
    if snapshot_coverage_pct >= 80.0:
        return ReplayQuality.DEGRADED
    return ReplayQuality.BROKEN


def derive_apply_mode(quality: ReplayQuality) -> ReplayApplyMode:
    """Map ReplayQuality -> ReplayApplyMode per CONTRACT §5.2."""
    if quality == ReplayQuality.GOOD:
        return ReplayApplyMode.APPLY
    if quality == ReplayQuality.DEGRADED:
        return ReplayApplyMode.APPLY_WITH_HAIRCUT
    return ReplayApplyMode.SHADOW_ONLY


def compute_penalized_pnl(
    replay_net_pnl_raw: float,
    replay_slippage_cost_usd: float,
    realism_penalty_factor: float,
) -> float:
    """Apply realism penalty to replay PnL per CONTRACT §5.2 Option B.

    replay_net_pnl_penalized = replay_net_pnl_raw
        - abs(replay_slippage_cost_usd) * (realism_penalty_factor - 1.0)
    """
    penalty_adjustment = abs(replay_slippage_cost_usd) * (
        realism_penalty_factor - 1.0
    )
    return replay_net_pnl_raw - penalty_adjustment


def evaluate(
    replay: ReplayInput,
    config: GatekeeperConfig,
    realism_penalty_factor: float,
    patch_deltas: Optional[list[PatchDelta]] = None,
) -> GatekeeperResult:
    """Run the Replay Gatekeeper evaluation.

    Returns a GatekeeperResult with verdict and all reject reasons.
    Fail-closed: any invalid/missing input produces HARD_FAIL or REJECT.
    """
    reject_reasons: list[RejectReason] = []

    # ── 0. dd_limit must be present and valid (AT-034) ───────────────────
    if config.dd_limit is None or not math.isfinite(config.dd_limit):
        return GatekeeperResult(
            verdict=GatekeeperVerdict.HARD_FAIL,
            reject_reasons=[RejectReason.DD_LIMIT_MISSING],
            replay_quality=ReplayQuality.BROKEN,
            apply_mode=ReplayApplyMode.SHADOW_ONLY,
            replay_net_pnl_penalized=None,
            realism_penalty_factor=realism_penalty_factor,
        )

    # ── 1. Validate inputs are finite ────────────────────────────────────
    if not all(
        math.isfinite(v)
        for v in (
            replay.replay_net_pnl_raw,
            replay.replay_slippage_cost_usd,
            replay.replay_max_drawdown_usd,
            replay.snapshot_coverage_pct,
            realism_penalty_factor,
        )
    ):
        return GatekeeperResult(
            verdict=GatekeeperVerdict.HARD_FAIL,
            reject_reasons=[RejectReason.INVALID_INPUT],
            replay_quality=ReplayQuality.BROKEN,
            apply_mode=ReplayApplyMode.SHADOW_ONLY,
            replay_net_pnl_penalized=None,
            realism_penalty_factor=realism_penalty_factor,
        )

    # ── 2. Derive quality and apply mode ─────────────────────────────────
    quality = derive_replay_quality(
        replay.snapshot_coverage_pct, replay.snapshots_readable
    )
    apply_mode = derive_apply_mode(quality)

    # ── 3. Compute penalized PnL ─────────────────────────────────────────
    penalized_pnl = compute_penalized_pnl(
        replay.replay_net_pnl_raw,
        replay.replay_slippage_cost_usd,
        realism_penalty_factor,
    )

    # ── 4. BROKEN → SHADOW_ONLY, no patch apply ─────────────────────────
    if quality == ReplayQuality.BROKEN:
        return GatekeeperResult(
            verdict=GatekeeperVerdict.REJECT,
            reject_reasons=[RejectReason.REPLAY_BROKEN],
            replay_quality=quality,
            apply_mode=apply_mode,
            replay_net_pnl_penalized=penalized_pnl,
            realism_penalty_factor=realism_penalty_factor,
        )

    # ── 5. Hard gates (AT-431, AT-432) ───────────────────────────────────
    if replay.replay_atomic_naked_events > 0:
        reject_reasons.append(RejectReason.ATOMIC_NAKED_EVENTS)

    if replay.replay_max_drawdown_usd > config.dd_limit:
        reject_reasons.append(RejectReason.DD_LIMIT_EXCEEDED)

    if penalized_pnl <= 0:
        reject_reasons.append(RejectReason.PENALIZED_PNL_NONPOSITIVE)

    # ── 6. DEGRADED tightening-only check (AT-1064) ──────────────────────
    if quality == ReplayQuality.DEGRADED and patch_deltas is not None:
        if not is_tightening_only(patch_deltas):
            reject_reasons.append(RejectReason.LOOSENING_WHILE_DEGRADED)

    # ── 7. Final verdict ─────────────────────────────────────────────────
    if reject_reasons:
        verdict = GatekeeperVerdict.REJECT
    elif quality == ReplayQuality.DEGRADED:
        verdict = GatekeeperVerdict.APPROVE_WITH_HAIRCUT
    else:
        verdict = GatekeeperVerdict.APPROVE

    return GatekeeperResult(
        verdict=verdict,
        reject_reasons=reject_reasons,
        replay_quality=quality,
        apply_mode=apply_mode,
        replay_net_pnl_penalized=penalized_pnl,
        realism_penalty_factor=realism_penalty_factor,
    )
