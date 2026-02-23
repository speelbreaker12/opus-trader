"""29 validation rules for proof graph (18 V1 + 11 V2)."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Optional

from .schema import ProofGraph, SHA_RE
from .enums import (
    AssumptionStatus,
    CausalMechanism,
    DecisionMatch,
    EnforcementStatus,
    LossModeLevel,
    ReconciliationStatus,
    Severity,
    StoplightColor,
    TestKind,
    Verdict,
    WiringStatus,
    WrongImplStatus,
)

PLACEHOLDER_RE = re.compile(r'<FILL>|TBD|TODO|FILL_ME', re.IGNORECASE)


@dataclass(frozen=True)
class Finding:
    severity: Severity
    rule: str
    at_id: Optional[str]
    message: str
    field_path: str = ""


@dataclass
class ValidationContext:
    graph: ProofGraph
    contract_ats: set[str] = field(default_factory=set)
    prd_items: dict[str, Any] = field(default_factory=dict)


def r_001(ctx: ValidationContext) -> list[Finding]:
    """RECONCILED story with BLOCKING ATs."""
    g = ctx.graph
    if g.story_verdict.reconciliation_status != ReconciliationStatus.RECONCILED:
        return []
    findings: list[Finding] = []
    for at in g.ats:
        if at.at_verdict.severity == Severity.BLOCKING:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-001",
                at_id=at.at_id,
                message=f"story is RECONCILED but AT {at.at_id} has BLOCKING severity",
            ))
    return findings


def r_002(ctx: ValidationContext) -> list[Finding]:
    """WEAK_PROOF on safety_critical + MED/HIGH AT."""
    g = ctx.graph
    if not g.story_meta.safety_critical:
        return []
    findings: list[Finding] = []
    for at in g.ats:
        if at.at_verdict.verdict == Verdict.WEAK_PROOF and \
                g.story_meta.loss_mode.level in (
                    LossModeLevel.MED, LossModeLevel.HIGH, LossModeLevel.CRITICAL,
                ):
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-002",
                at_id=at.at_id,
                message=(
                    f"WEAK_PROOF on safety_critical AT {at.at_id} "
                    f"with loss_mode level {g.story_meta.loss_mode.level.value}"
                ),
            ))
    return findings


def r_003(ctx: ValidationContext) -> list[Finding]:
    """NOT_WIRED + PROVEN_INTEGRATED verdict contradiction."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.wiring.status == WiringStatus.NOT_WIRED and \
                at.at_verdict.verdict == Verdict.PROVEN_INTEGRATED:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-003",
                at_id=at.at_id,
                message=(
                    f"AT {at.at_id} claims PROVEN_INTEGRATED but wiring is NOT_WIRED"
                ),
            ))
    return findings


def r_004(ctx: ValidationContext) -> list[Finding]:
    """test ran_at_head_sha != graph head_sha (stale)."""
    head = ctx.graph.head_sha
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        for i, t in enumerate(at.tests):
            if t.execution.ran_at_head_sha != head:
                findings.append(Finding(
                    severity=Severity.BLOCKING,
                    rule="R-004",
                    at_id=at.at_id,
                    message=(
                        f"test '{t.test_name}' ran at {t.execution.ran_at_head_sha} "
                        f"but graph head_sha is {head}"
                    ),
                    field_path=f"ats.{at.at_id}.tests[{i}].execution.ran_at_head_sha",
                ))
    return findings


def r_005(ctx: ValidationContext) -> list[Finding]:
    """Deferred debt with empty target_slice."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.debt and not at.debt.target_slice.strip():
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-005",
                at_id=at.at_id,
                message=f"AT {at.at_id} has debt with empty target_slice",
            ))
    return findings


def r_006(ctx: ValidationContext) -> list[Finding]:
    """Enforcement FOUND but empty evidence[]."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.enforcement.status == EnforcementStatus.FOUND and \
                not at.enforcement.evidence:
            findings.append(Finding(
                severity=Severity.HARDENING,
                rule="R-006",
                at_id=at.at_id,
                message=f"AT {at.at_id} enforcement FOUND but evidence[] is empty",
            ))
    return findings


def r_007(ctx: ValidationContext) -> list[Finding]:
    """AT ID not in CONTRACT.md."""
    if not ctx.contract_ats:
        return []
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.at_id not in ctx.contract_ats:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-007",
                at_id=at.at_id,
                message=f"AT {at.at_id} not found in CONTRACT.md",
            ))
    return findings


def r_008(ctx: ValidationContext) -> list[Finding]:
    """TBD/TODO/FILL_ME in critical string fields."""
    findings: list[Finding] = []
    g = ctx.graph

    def _check(value: str, path: str, at_id: Optional[str] = None) -> None:
        if PLACEHOLDER_RE.search(value):
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-008",
                at_id=at_id,
                message=f"placeholder found in {path}: {value!r}",
                field_path=path,
            ))

    _check(g.story_verdict.summary, "story_verdict.summary")
    for at in g.ats:
        _check(at.at_verdict.rationale, f"ats.{at.at_id}.at_verdict.rationale", at.at_id)
        for i, t in enumerate(at.tests):
            _check(t.test_name, f"ats.{at.at_id}.tests[{i}].test_name", at.at_id)
            _check(
                t.causal_proof.mechanism,
                f"ats.{at.at_id}.tests[{i}].causal_proof.mechanism",
                at.at_id,
            )
        _check(
            at.enforcement.status.value,
            f"ats.{at.at_id}.enforcement.status",
            at.at_id,
        )
        for ev in at.enforcement.evidence:
            _check(ev, f"ats.{at.at_id}.enforcement.evidence", at.at_id)
        _check(at.wiring.evidence, f"ats.{at.at_id}.wiring.evidence", at.at_id)
        _check(at.observability.metric, f"ats.{at.at_id}.observability.metric", at.at_id)
        _check(at.observability.alert, f"ats.{at.at_id}.observability.alert", at.at_id)
    return findings


def r_009(ctx: ValidationContext) -> list[Finding]:
    """blocking_count doesn't match actual BLOCKING ATs."""
    actual = sum(
        1 for at in ctx.graph.ats
        if at.at_verdict.severity == Severity.BLOCKING
    )
    claimed = ctx.graph.story_verdict.blocking_count
    if actual != claimed:
        return [Finding(
            severity=Severity.BLOCKING,
            rule="R-009",
            at_id=None,
            message=(
                f"blocking_count={claimed} but actual BLOCKING ATs={actual}"
            ),
        )]
    return []


def r_010(ctx: ValidationContext) -> list[Finding]:
    """hardening_count doesn't match actual HARDENING ATs."""
    actual = sum(
        1 for at in ctx.graph.ats
        if at.at_verdict.severity == Severity.HARDENING
    )
    claimed = ctx.graph.story_verdict.hardening_count
    if actual != claimed:
        return [Finding(
            severity=Severity.BLOCKING,
            rule="R-010",
            at_id=None,
            message=(
                f"hardening_count={claimed} but actual HARDENING ATs={actual}"
            ),
        )]
    return []


def r_011(ctx: ValidationContext) -> list[Finding]:
    """AT with debt but no matching debt_register entry."""
    registered_ids = {e.at_id for e in ctx.graph.debt_register}
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.debt and at.at_id not in registered_ids:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-011",
                at_id=at.at_id,
                message=(
                    f"AT {at.at_id} has debt but no matching debt_register entry"
                ),
            ))
    return findings


def r_012(ctx: ValidationContext) -> list[Finding]:
    """Enforcement FOUND but zero tests."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.enforcement.status == EnforcementStatus.FOUND and not at.tests:
            findings.append(Finding(
                severity=Severity.HARDENING,
                rule="R-012",
                at_id=at.at_id,
                message=f"AT {at.at_id} enforcement FOUND but has zero tests",
            ))
    return findings


def r_013(ctx: ValidationContext) -> list[Finding]:
    """head_sha not 40-char lowercase hex."""
    sha = ctx.graph.head_sha
    if not SHA_RE.match(sha):
        return [Finding(
            severity=Severity.BLOCKING,
            rule="R-013",
            at_id=None,
            message=f"head_sha is not valid 40-char lowercase hex: {sha!r}",
            field_path="head_sha",
        )]
    return []


def r_014(ctx: ValidationContext) -> list[Finding]:
    """story_id not in prd.json."""
    if not ctx.prd_items:
        return []
    sid = ctx.graph.story_meta.story_id
    if sid not in ctx.prd_items:
        return [Finding(
            severity=Severity.HARDENING,
            rule="R-014",
            at_id=None,
            message=f"story_id {sid!r} not found in prd.json",
        )]
    return []


def r_015(ctx: ValidationContext) -> list[Finding]:
    """FAIL_OPEN_RISK verdict on any AT."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.at_verdict.verdict == Verdict.FAIL_OPEN_RISK:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-015",
                at_id=at.at_id,
                message=f"AT {at.at_id} has FAIL_OPEN_RISK verdict",
            ))
    return findings


def r_016(ctx: ValidationContext) -> list[Finding]:
    """Enforcement FOUND but zero TRIP tests (WARN)."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.enforcement.status != EnforcementStatus.FOUND:
            continue
        trip_count = sum(1 for t in at.tests if t.kind == TestKind.TRIP)
        if trip_count == 0:
            findings.append(Finding(
                severity=Severity.HARDENING,
                rule="R-016",
                at_id=at.at_id,
                message=(
                    f"AT {at.at_id} enforcement FOUND but has zero TRIP tests"
                ),
            ))
    return findings


def r_016b(ctx: ValidationContext) -> list[Finding]:
    """safety_critical + MED/HIGH + enforcement FOUND + zero TRIP tests (ERROR)."""
    g = ctx.graph
    if not g.story_meta.safety_critical:
        return []
    if g.story_meta.loss_mode.level not in (
        LossModeLevel.MED, LossModeLevel.HIGH, LossModeLevel.CRITICAL,
    ):
        return []
    findings: list[Finding] = []
    for at in g.ats:
        if at.enforcement.status != EnforcementStatus.FOUND:
            continue
        trip_count = sum(1 for t in at.tests if t.kind == TestKind.TRIP)
        if trip_count == 0:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-016b",
                at_id=at.at_id,
                message=(
                    f"safety_critical + {g.story_meta.loss_mode.level.value}: "
                    f"AT {at.at_id} enforcement FOUND but zero TRIP tests"
                ),
            ))
    return findings


def r_017(ctx: ValidationContext) -> list[Finding]:
    """Non-exempt story with empty ats[]."""
    g = ctx.graph
    if g.story_meta.category in ("policy", "certification"):
        return []
    if not g.ats:
        return [Finding(
            severity=Severity.HARDENING,
            rule="R-017",
            at_id=None,
            message=(
                f"story {g.story_meta.story_id} (category={g.story_meta.category}) "
                f"has empty ats[]"
            ),
        )]
    return []


# ── V2 Rules ─────────────────────────────────────────────────────────


def _is_v2(ctx: ValidationContext) -> bool:
    return ctx.graph.schema_version >= 2


def should_trigger_trading_halt(
    safety_critical: bool, loss_level: str, verdicts: list[str]
) -> bool:
    """Core trading halt logic (raw types, usable from aggregate.py).

    Trading halt is a higher threshold than validation: only HIGH/CRITICAL
    trigger a halt, whereas validation rules R-002/R-016b fire at MED/HIGH.
    This is intentional — MED-level stories get BLOCKING validation findings
    but do NOT trigger the pipeline-halting exit-20 signal.

    Args:
        safety_critical: Whether the story is safety-critical.
        loss_level: Loss mode level string (e.g. "HIGH", "CRITICAL").
        verdicts: List of AT verdict strings.
    """
    if not safety_critical:
        return False
    if loss_level not in (LossModeLevel.HIGH.value, LossModeLevel.CRITICAL.value):
        return False
    halt_verdicts = (Verdict.FAIL_OPEN_RISK.value, Verdict.WRONG_IMPL_UNBLOCKED.value)
    return any(v in halt_verdicts for v in verdicts)


def compute_trading_halt(ctx: ValidationContext) -> bool:
    """Recompute trading halt condition from graph data (authoritative)."""
    g = ctx.graph
    return should_trigger_trading_halt(
        safety_critical=g.story_meta.safety_critical,
        loss_level=g.story_meta.loss_mode.level,
        verdicts=[at.at_verdict.verdict for at in g.ats],
    )


def r_006b(ctx: ValidationContext) -> list[Finding]:
    """V2: Enforcement FOUND but empty evidence_entries (structured citations)."""
    if not _is_v2(ctx):
        return []
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.enforcement.status == EnforcementStatus.FOUND and \
                not at.enforcement.evidence_entries:
            findings.append(Finding(
                severity=Severity.HARDENING,
                rule="R-006b",
                at_id=at.at_id,
                message=(
                    f"V2: AT {at.at_id} enforcement FOUND but "
                    f"evidence_entries[] is empty (no structured citations)"
                ),
            ))
    return findings


def r_018(ctx: ValidationContext) -> list[Finding]:
    """V2: Invalid structured evidence citation."""
    if not _is_v2(ctx):
        return []
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        for i, ee in enumerate(at.enforcement.evidence_entries):
            path = f"ats.{at.at_id}.enforcement.evidence_entries[{i}]"
            if not ee.file.strip():
                findings.append(Finding(
                    severity=Severity.BLOCKING,
                    rule="R-018",
                    at_id=at.at_id,
                    message=f"evidence_entry has empty file",
                    field_path=f"{path}.file",
                ))
            if ee.line_start < 1:
                findings.append(Finding(
                    severity=Severity.BLOCKING,
                    rule="R-018",
                    at_id=at.at_id,
                    message=f"evidence_entry line_start < 1: {ee.line_start}",
                    field_path=f"{path}.line_start",
                ))
            if ee.line_end < ee.line_start:
                findings.append(Finding(
                    severity=Severity.BLOCKING,
                    rule="R-018",
                    at_id=at.at_id,
                    message=(
                        f"evidence_entry line_end ({ee.line_end}) < "
                        f"line_start ({ee.line_start})"
                    ),
                    field_path=f"{path}.line_end",
                ))
            if not ee.symbol.strip():
                findings.append(Finding(
                    severity=Severity.BLOCKING,
                    rule="R-018",
                    at_id=at.at_id,
                    message=f"evidence_entry has empty symbol",
                    field_path=f"{path}.symbol",
                ))
    return findings


def r_019(ctx: ValidationContext) -> list[Finding]:
    """V1+V2: WRONG_IMPL_UNBLOCKED on safety_critical AT."""
    g = ctx.graph
    if not g.story_meta.safety_critical:
        return []
    findings: list[Finding] = []
    for at in g.ats:
        if at.at_verdict.verdict == Verdict.WRONG_IMPL_UNBLOCKED:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-019",
                at_id=at.at_id,
                message=(
                    f"safety_critical AT {at.at_id} has "
                    f"WRONG_IMPL_UNBLOCKED verdict"
                ),
            ))
    return findings


def r_020(ctx: ValidationContext) -> list[Finding]:
    """V2: PROVEN_INTEGRATED wiring but empty caller_chain."""
    if not _is_v2(ctx):
        return []
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.wiring.status == WiringStatus.PROVEN_INTEGRATED:
            chain = at.wiring.caller_chain
            if not chain or not any(s.strip() for s in chain):
                findings.append(Finding(
                    severity=Severity.HARDENING,
                    rule="R-020",
                    at_id=at.at_id,
                    message=(
                        f"AT {at.at_id} wiring is PROVEN_INTEGRATED but "
                        f"caller_chain is empty or all-blank"
                    ),
                ))
    return findings


def r_021(ctx: ValidationContext) -> list[Finding]:
    """V2: safety_critical + section5_wrong_impl_blocked == NONE."""
    if not _is_v2(ctx):
        return []
    g = ctx.graph
    if not g.story_meta.safety_critical:
        return []
    findings: list[Finding] = []
    for at in g.ats:
        s5 = at.premortem_checks.section5_wrong_impl_blocked
        if s5 == WrongImplStatus.NONE:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-021",
                at_id=at.at_id,
                message=(
                    f"safety_critical AT {at.at_id}: "
                    f"premortem §5 wrong_impl_blocked is NONE"
                ),
            ))
    return findings


def r_022(ctx: ValidationContext) -> list[Finding]:
    """V2: section4_decision_match == NO."""
    if not _is_v2(ctx):
        return []
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        s4 = at.premortem_checks.section4_decision_match
        if s4 == DecisionMatch.NO:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-022",
                at_id=at.at_id,
                message=(
                    f"AT {at.at_id}: implementation does not match "
                    f"premortem §4 decision (section4_decision_match=NO)"
                ),
            ))
    return findings


def r_023(ctx: ValidationContext) -> list[Finding]:
    """V1+V2: INVALID_REF verdict on any AT."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.at_verdict.verdict == Verdict.INVALID_REF:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-023",
                at_id=at.at_id,
                message=f"AT {at.at_id} has INVALID_REF verdict",
            ))
    return findings


def r_024(ctx: ValidationContext) -> list[Finding]:
    """V2: safety_critical + test with empty why_causal."""
    if not _is_v2(ctx):
        return []
    g = ctx.graph
    if not g.story_meta.safety_critical:
        return []
    findings: list[Finding] = []
    for at in g.ats:
        for i, t in enumerate(at.tests):
            if not t.causal_proof.why_causal.strip():
                findings.append(Finding(
                    severity=Severity.HARDENING,
                    rule="R-024",
                    at_id=at.at_id,
                    message=(
                        f"safety_critical AT {at.at_id}: "
                        f"test '{t.test_name}' has empty why_causal"
                    ),
                    field_path=f"ats.{at.at_id}.tests[{i}].causal_proof.why_causal",
                ))
    return findings


def r_024b(ctx: ValidationContext) -> list[Finding]:
    """V2: mechanism value not in CausalMechanism enum."""
    if not _is_v2(ctx):
        return []
    valid_values = {m.value for m in CausalMechanism}
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        for i, t in enumerate(at.tests):
            if t.causal_proof.mechanism not in valid_values:
                findings.append(Finding(
                    severity=Severity.HARDENING,
                    rule="R-024b",
                    at_id=at.at_id,
                    message=(
                        f"AT {at.at_id} test '{t.test_name}': "
                        f"mechanism {t.causal_proof.mechanism!r} not in "
                        f"CausalMechanism enum"
                    ),
                    field_path=f"ats.{at.at_id}.tests[{i}].causal_proof.mechanism",
                ))
    return findings


def r_025(ctx: ValidationContext) -> list[Finding]:
    """V2: Recomputed halt != stored trading_halt_trigger (consistency check)."""
    if not _is_v2(ctx):
        return []
    recomputed = compute_trading_halt(ctx)
    stored = ctx.graph.story_verdict.trading_halt_trigger
    if recomputed and not stored:
        return [Finding(
            severity=Severity.BLOCKING,
            rule="R-025",
            at_id=None,
            message=(
                "trading halt condition is true (recomputed) but "
                "trading_halt_trigger is false in graph"
            ),
        )]
    if stored and not recomputed:
        return [Finding(
            severity=Severity.INFO,
            rule="R-025",
            at_id=None,
            message=(
                "trading_halt_trigger is true in graph but recomputed "
                "condition is false (conservative, not blocking)"
            ),
        )]
    return []


def r_026(ctx: ValidationContext) -> list[Finding]:
    """V2: Graph has zero V2 enrichment (all V2 fields empty)."""
    if not _is_v2(ctx):
        return []
    has_evidence_entries = False
    has_caller_chain = False
    has_why_causal = False
    for at in ctx.graph.ats:
        if at.enforcement.evidence_entries:
            has_evidence_entries = True
        if at.wiring.caller_chain and any(s.strip() for s in at.wiring.caller_chain):
            has_caller_chain = True
        for t in at.tests:
            if t.causal_proof.why_causal.strip():
                has_why_causal = True
    if not has_evidence_entries and not has_caller_chain and not has_why_causal:
        return [Finding(
            severity=Severity.HARDENING,
            rule="R-026",
            at_id=None,
            message=(
                "V2 schema claimed but no V2 data populated "
                "(all evidence_entries empty, all caller_chain empty, "
                "all why_causal empty)"
            ),
        )]
    return []


_PROVEN_VERDICTS = {Verdict.PROVEN_INTEGRATED, Verdict.PROVEN_UNIT}

# Mechanism → required assertion field attribute name
_MECHANISM_ASSERT_MAP: dict[str, str] = {
    CausalMechanism.DISPATCH_COUNT.value: "dispatch_count_assert",
    CausalMechanism.REJECT_REASON.value: "reject_reason_assert",
    CausalMechanism.LATCH_REASON.value: "latch_reason_assert",
}

# Known enforcement_point values (from CLAUDE.md / CONTRACT.md)
_KNOWN_ENFORCEMENT_POINTS = {
    "PolicyGuard", "EvidenceGuard", "DispatcherChokepoint",
    "WAL", "AtomicGroupExecutor", "StatusEndpoint",
}


def r_027(ctx: ValidationContext) -> list[Finding]:
    """PROVEN verdict but tests have pass_result=false."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.at_verdict.verdict not in _PROVEN_VERDICTS:
            continue
        if not at.tests:
            continue
        failing = [t for t in at.tests if not t.execution.pass_result]
        if failing:
            names = ", ".join(t.test_name for t in failing[:3])
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-027",
                at_id=at.at_id,
                message=(
                    f"AT {at.at_id} verdict is {at.at_verdict.verdict.value} "
                    f"but {len(failing)} test(s) have pass_result=false: {names}"
                ),
            ))
    return findings


def r_028(ctx: ValidationContext) -> list[Finding]:
    """Mechanism-specific causal assertion missing."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        for i, t in enumerate(at.tests):
            mech = t.causal_proof.mechanism
            assert_attr = _MECHANISM_ASSERT_MAP.get(mech)
            if assert_attr is None:
                continue
            value = getattr(t.causal_proof, assert_attr, None)
            if not value or not value.strip():
                findings.append(Finding(
                    severity=Severity.BLOCKING,
                    rule="R-028",
                    at_id=at.at_id,
                    message=(
                        f"test '{t.test_name}' mechanism={mech} "
                        f"but {assert_attr} is empty/null"
                    ),
                    field_path=(
                        f"ats.{at.at_id}.tests[{i}]"
                        f".causal_proof.{assert_attr}"
                    ),
                ))
    return findings


def r_029(ctx: ValidationContext) -> list[Finding]:
    """V2: safety_critical + stoplight RED + PROVEN verdict."""
    if not _is_v2(ctx):
        return []
    g = ctx.graph
    if not g.story_meta.safety_critical:
        return []
    findings: list[Finding] = []
    for at in g.ats:
        if at.premortem_checks.stoplight == StoplightColor.RED and \
                at.at_verdict.verdict in _PROVEN_VERDICTS:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-029",
                at_id=at.at_id,
                message=(
                    f"safety_critical AT {at.at_id}: stoplight is RED "
                    f"but verdict is {at.at_verdict.verdict.value}"
                ),
            ))
    return findings


def r_030(ctx: ValidationContext) -> list[Finding]:
    """V2: safety_critical + section2_assumptions == NONE."""
    if not _is_v2(ctx):
        return []
    g = ctx.graph
    if not g.story_meta.safety_critical:
        return []
    findings: list[Finding] = []
    for at in g.ats:
        s2 = at.premortem_checks.section2_assumptions
        if s2 == AssumptionStatus.NONE:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-030",
                at_id=at.at_id,
                message=(
                    f"safety_critical AT {at.at_id}: "
                    f"premortem §2 assumptions status is NONE"
                ),
            ))
    return findings


def r_031(ctx: ValidationContext) -> list[Finding]:
    """RECONCILED_WITH_DEBT but empty debt_register."""
    g = ctx.graph
    if g.story_verdict.reconciliation_status != \
            ReconciliationStatus.RECONCILED_WITH_DEBT:
        return []
    if not g.debt_register:
        return [Finding(
            severity=Severity.BLOCKING,
            rule="R-031",
            at_id=None,
            message=(
                "reconciliation_status is RECONCILED_WITH_DEBT "
                "but debt_register is empty"
            ),
        )]
    return []


def r_032(ctx: ValidationContext) -> list[Finding]:
    """V2: BLOCKED_TRADING_HALT but trading_halt_trigger is false."""
    if not _is_v2(ctx):
        return []
    g = ctx.graph
    if g.story_verdict.reconciliation_status != \
            ReconciliationStatus.BLOCKED_TRADING_HALT:
        return []
    if not g.story_verdict.trading_halt_trigger:
        return [Finding(
            severity=Severity.BLOCKING,
            rule="R-032",
            at_id=None,
            message=(
                "reconciliation_status is BLOCKED_TRADING_HALT "
                "but trading_halt_trigger is false"
            ),
        )]
    return []


def r_033(ctx: ValidationContext) -> list[Finding]:
    """Enforcement NOT_FOUND + PROVEN_INTEGRATED verdict contradiction."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if at.enforcement.status == EnforcementStatus.NOT_FOUND and \
                at.at_verdict.verdict == Verdict.PROVEN_INTEGRATED:
            findings.append(Finding(
                severity=Severity.BLOCKING,
                rule="R-033",
                at_id=at.at_id,
                message=(
                    f"AT {at.at_id} claims PROVEN_INTEGRATED "
                    f"but enforcement is NOT_FOUND"
                ),
            ))
    return findings


def r_034(ctx: ValidationContext) -> list[Finding]:
    """loss_mode sub-fields empty on non-exempt story."""
    g = ctx.graph
    if g.story_meta.category in ("policy", "certification"):
        return []
    findings: list[Finding] = []
    lm = g.story_meta.loss_mode
    for field_name, value in [
        ("worst_case", lm.worst_case),
        ("fail_closed_cap", lm.fail_closed_cap),
        ("drift_metric", lm.drift_metric),
    ]:
        if not value.strip():
            findings.append(Finding(
                severity=Severity.HARDENING,
                rule="R-034",
                at_id=None,
                message=f"loss_mode.{field_name} is empty",
                field_path=f"story_meta.loss_mode.{field_name}",
            ))
    return findings


def r_035(ctx: ValidationContext) -> list[Finding]:
    """enforcement_point not in known set."""
    ep = ctx.graph.story_meta.enforcement_point
    if ep not in _KNOWN_ENFORCEMENT_POINTS:
        return [Finding(
            severity=Severity.HARDENING,
            rule="R-035",
            at_id=None,
            message=(
                f"enforcement_point {ep!r} not in known set: "
                f"{sorted(_KNOWN_ENFORCEMENT_POINTS)}"
            ),
            field_path="story_meta.enforcement_point",
        )]
    return []


def r_036(ctx: ValidationContext) -> list[Finding]:
    """Observability metric/alert empty string (beyond placeholder check)."""
    findings: list[Finding] = []
    for at in ctx.graph.ats:
        if not at.observability.metric.strip():
            findings.append(Finding(
                severity=Severity.HARDENING,
                rule="R-036",
                at_id=at.at_id,
                message=f"AT {at.at_id} observability.metric is empty",
                field_path=f"ats.{at.at_id}.observability.metric",
            ))
        if not at.observability.alert.strip():
            findings.append(Finding(
                severity=Severity.HARDENING,
                rule="R-036",
                at_id=at.at_id,
                message=f"AT {at.at_id} observability.alert is empty",
                field_path=f"ats.{at.at_id}.observability.alert",
            ))
    return findings


ALL_RULES = [
    r_001, r_002, r_003, r_004, r_005, r_006, r_007, r_008,
    r_009, r_010, r_011, r_012, r_013, r_014, r_015, r_016,
    r_016b, r_017,
    # V2 rules
    r_006b, r_018, r_019, r_020, r_021, r_022, r_023, r_024,
    r_024b, r_025, r_026,
    # V3 rules (validator-audit findings)
    r_027, r_028, r_029, r_030, r_031, r_032, r_033, r_034,
    r_035, r_036,
]


def validate(ctx: ValidationContext) -> list[Finding]:
    """Run all rules and return findings."""
    findings: list[Finding] = []
    for rule_fn in ALL_RULES:
        findings.extend(rule_fn(ctx))
    return findings
