"""18 validation rules for proof graph."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Optional

from .schema import ProofGraph, SHA_RE
from .enums import (
    EnforcementStatus,
    LossModeLevel,
    ReconciliationStatus,
    Severity,
    TestKind,
    Verdict,
    WiringStatus,
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
                g.story_meta.loss_mode.level in (LossModeLevel.MED, LossModeLevel.HIGH):
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
    if g.story_meta.loss_mode.level not in (LossModeLevel.MED, LossModeLevel.HIGH):
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


ALL_RULES = [
    r_001, r_002, r_003, r_004, r_005, r_006, r_007, r_008,
    r_009, r_010, r_011, r_012, r_013, r_014, r_015, r_016,
    r_016b, r_017,
]


def validate(ctx: ValidationContext) -> list[Finding]:
    """Run all rules and return findings."""
    findings: list[Finding] = []
    for rule_fn in ALL_RULES:
        findings.extend(rule_fn(ctx))
    return findings
