"""Tests for Replay Gatekeeper — CONTRACT.md §5.2."""

import math

from governor.replay_gatekeeper import (
    GatekeeperConfig,
    GatekeeperResult,
    GatekeeperVerdict,
    PatchDelta,
    RejectReason,
    ReplayApplyMode,
    ReplayInput,
    ReplayQuality,
    compute_penalized_pnl,
    derive_apply_mode,
    derive_replay_quality,
    evaluate,
    is_tightening_only,
)


def _good_replay(
    pnl_raw: float = 1000.0,
    slippage: float = 100.0,
    drawdown: float = 200.0,
    naked: int = 0,
    coverage: float = 96.0,
    readable: bool = True,
) -> ReplayInput:
    return ReplayInput(
        replay_net_pnl_raw=pnl_raw,
        replay_slippage_cost_usd=slippage,
        replay_max_drawdown_usd=drawdown,
        replay_atomic_naked_events=naked,
        snapshot_coverage_pct=coverage,
        snapshots_readable=readable,
    )


def _config(dd_limit: float | None = 500.0) -> GatekeeperConfig:
    return GatekeeperConfig(dd_limit=dd_limit)


# ── AT-034: dd_limit missing → HARD FAIL ────────────────────────────────────


class TestAT034DdLimitMissing:
    def test_none_dd_limit_hard_fails(self) -> None:
        result = evaluate(_good_replay(), _config(dd_limit=None), 1.0)
        assert result.verdict == GatekeeperVerdict.HARD_FAIL
        assert RejectReason.DD_LIMIT_MISSING in result.reject_reasons

    def test_nan_dd_limit_hard_fails(self) -> None:
        result = evaluate(_good_replay(), _config(dd_limit=float("nan")), 1.0)
        assert result.verdict == GatekeeperVerdict.HARD_FAIL

    def test_inf_dd_limit_hard_fails(self) -> None:
        result = evaluate(_good_replay(), _config(dd_limit=float("inf")), 1.0)
        assert result.verdict == GatekeeperVerdict.HARD_FAIL


# ── AT-431: atomic_naked_events > 0 → FAIL ──────────────────────────────────


class TestAT431AtomicNaked:
    def test_nonzero_naked_events_rejected(self) -> None:
        result = evaluate(_good_replay(naked=1), _config(), 1.0)
        assert result.verdict == GatekeeperVerdict.REJECT
        assert RejectReason.ATOMIC_NAKED_EVENTS in result.reject_reasons


# ── AT-432: penalized PnL ≤ 0 → FAIL ────────────────────────────────────────


class TestAT432PenalizedPnl:
    def test_zero_penalized_pnl_rejected(self) -> None:
        # pnl_raw=100, slippage=100, penalty=2.0 → penalized = 100 - 100*(2-1) = 0
        result = evaluate(
            _good_replay(pnl_raw=100.0, slippage=100.0), _config(), 2.0
        )
        assert result.verdict == GatekeeperVerdict.REJECT
        assert RejectReason.PENALIZED_PNL_NONPOSITIVE in result.reject_reasons

    def test_negative_penalized_pnl_rejected(self) -> None:
        result = evaluate(
            _good_replay(pnl_raw=50.0, slippage=100.0), _config(), 2.0
        )
        assert result.verdict == GatekeeperVerdict.REJECT
        assert RejectReason.PENALIZED_PNL_NONPOSITIVE in result.reject_reasons


# ── Drawdown gate ────────────────────────────────────────────────────────────


class TestDrawdownGate:
    def test_drawdown_exceeds_dd_limit_rejected(self) -> None:
        result = evaluate(_good_replay(drawdown=600.0), _config(dd_limit=500.0), 1.0)
        assert result.verdict == GatekeeperVerdict.REJECT
        assert RejectReason.DD_LIMIT_EXCEEDED in result.reject_reasons

    def test_drawdown_at_dd_limit_passes(self) -> None:
        result = evaluate(_good_replay(drawdown=500.0), _config(dd_limit=500.0), 1.0)
        assert result.verdict == GatekeeperVerdict.APPROVE


# ── ReplayQuality derivation ────────────────────────────────────────────────


class TestReplayQuality:
    def test_good_at_95(self) -> None:
        assert derive_replay_quality(95.0, True) == ReplayQuality.GOOD

    def test_good_above_95(self) -> None:
        assert derive_replay_quality(99.0, True) == ReplayQuality.GOOD

    def test_degraded_at_80(self) -> None:
        assert derive_replay_quality(80.0, True) == ReplayQuality.DEGRADED

    def test_degraded_at_90(self) -> None:
        assert derive_replay_quality(90.0, True) == ReplayQuality.DEGRADED

    def test_broken_below_80(self) -> None:
        assert derive_replay_quality(79.9, True) == ReplayQuality.BROKEN

    def test_broken_unreadable(self) -> None:
        assert derive_replay_quality(99.0, False) == ReplayQuality.BROKEN

    def test_broken_nan_coverage(self) -> None:
        assert derive_replay_quality(float("nan"), True) == ReplayQuality.BROKEN


# ── AT-002: GOOD → APPLY ────────────────────────────────────────────────────


class TestAT002GoodApply:
    def test_95_coverage_apply(self) -> None:
        result = evaluate(_good_replay(coverage=95.0), _config(), 1.0)
        assert result.replay_quality == ReplayQuality.GOOD
        assert result.apply_mode == ReplayApplyMode.APPLY
        assert result.verdict == GatekeeperVerdict.APPROVE


# ── AT-257: DEGRADED → APPLY_WITH_HAIRCUT ───────────────────────────────────


class TestAT257DegradedHaircut:
    def test_degraded_tightening_approved_with_haircut(self) -> None:
        deltas = [PatchDelta("min_edge_usd", 1.0, 2.0)]  # tightening
        result = evaluate(
            _good_replay(coverage=90.0), _config(), 1.0, patch_deltas=deltas
        )
        assert result.replay_quality == ReplayQuality.DEGRADED
        assert result.apply_mode == ReplayApplyMode.APPLY_WITH_HAIRCUT
        assert result.verdict == GatekeeperVerdict.APPROVE_WITH_HAIRCUT


# ── AT-1062: BROKEN → SHADOW_ONLY ───────────────────────────────────────────


class TestAT1062BrokenShadow:
    def test_broken_coverage_shadow_only(self) -> None:
        result = evaluate(_good_replay(coverage=70.0), _config(), 1.0)
        assert result.replay_quality == ReplayQuality.BROKEN
        assert result.apply_mode == ReplayApplyMode.SHADOW_ONLY
        assert result.verdict == GatekeeperVerdict.REJECT


# ── AT-1064: loosening while degraded → REJECT ──────────────────────────────


class TestAT1064LooseningDegraded:
    def test_loosening_patch_degraded_rejected(self) -> None:
        deltas = [PatchDelta("min_edge_usd", 2.0, 1.0)]  # loosening!
        result = evaluate(
            _good_replay(coverage=90.0), _config(), 1.0, patch_deltas=deltas
        )
        assert result.verdict == GatekeeperVerdict.REJECT
        assert RejectReason.LOOSENING_WHILE_DEGRADED in result.reject_reasons

    def test_unknown_parameter_treated_as_loosen(self) -> None:
        deltas = [PatchDelta("unknown_param", 1.0, 2.0)]
        result = evaluate(
            _good_replay(coverage=90.0), _config(), 1.0, patch_deltas=deltas
        )
        assert result.verdict == GatekeeperVerdict.REJECT
        assert RejectReason.LOOSENING_WHILE_DEGRADED in result.reject_reasons


# ── Tightening classifier ───────────────────────────────────────────────────


class TestTighteningClassifier:
    def test_all_tightening(self) -> None:
        deltas = [
            PatchDelta("min_edge_usd", 1.0, 2.0),  # increase = tighten
            PatchDelta("max_order_usd", 100.0, 50.0),  # decrease = tighten
        ]
        assert is_tightening_only(deltas)

    def test_unchanged_is_ok(self) -> None:
        deltas = [PatchDelta("min_edge_usd", 1.0, 1.0)]
        assert is_tightening_only(deltas)

    def test_loosening_detected(self) -> None:
        deltas = [PatchDelta("min_edge_usd", 2.0, 1.0)]  # decrease = loosen
        assert not is_tightening_only(deltas)

    def test_empty_deltas_is_tightening(self) -> None:
        assert is_tightening_only([])


# ── Penalized PnL computation ────────────────────────────────────────────────


class TestPenalizedPnl:
    def test_no_penalty_at_factor_1(self) -> None:
        assert compute_penalized_pnl(1000.0, 100.0, 1.0) == 1000.0

    def test_penalty_at_factor_1_2(self) -> None:
        # 1000 - abs(100) * (1.2 - 1.0) = 1000 - 20 = 980
        assert abs(compute_penalized_pnl(1000.0, 100.0, 1.2) - 980.0) < 0.01

    def test_penalty_uses_abs_slippage(self) -> None:
        # Negative slippage cost should still apply penalty
        result = compute_penalized_pnl(1000.0, -100.0, 1.5)
        assert abs(result - 950.0) < 0.01  # 1000 - 100 * 0.5


# ── Invalid inputs (fail-closed) ────────────────────────────────────────────


class TestInvalidInputsFailClosed:
    def test_nan_pnl_hard_fails(self) -> None:
        result = evaluate(
            _good_replay(pnl_raw=float("nan")), _config(), 1.0
        )
        assert result.verdict == GatekeeperVerdict.HARD_FAIL

    def test_nan_penalty_factor_hard_fails(self) -> None:
        result = evaluate(_good_replay(), _config(), float("nan"))
        assert result.verdict == GatekeeperVerdict.HARD_FAIL

    def test_inf_drawdown_hard_fails(self) -> None:
        result = evaluate(
            _good_replay(drawdown=float("inf")), _config(), 1.0
        )
        assert result.verdict == GatekeeperVerdict.HARD_FAIL


# ── AT-259: PASS + GOOD → approve ───────────────────────────────────────────


class TestAT259PassGood:
    def test_clean_pass_approved(self) -> None:
        result = evaluate(_good_replay(), _config(), 1.0)
        assert result.verdict == GatekeeperVerdict.APPROVE
        assert result.replay_quality == ReplayQuality.GOOD
        assert result.reject_reasons == []
        assert result.replay_net_pnl_penalized is not None
        assert result.replay_net_pnl_penalized > 0


# ── AT-332: penalized profit flips ≤ 0 → FAIL ───────────────────────────────


class TestAT332PenalizedFlip:
    def test_positive_raw_negative_penalized_rejected(self) -> None:
        # pnl_raw=50, slippage=100, factor=2.5 → penalized = 50 - 100*1.5 = -100
        result = evaluate(
            _good_replay(pnl_raw=50.0, slippage=100.0), _config(), 2.5
        )
        assert result.verdict == GatekeeperVerdict.REJECT
        assert RejectReason.PENALIZED_PNL_NONPOSITIVE in result.reject_reasons
