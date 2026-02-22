"""Proof graph dataclasses with from_dict() and deny-unknown-fields."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Optional

from .enums import (
    EnforcementStatus,
    LossModeLevel,
    ReconciliationStatus,
    Severity,
    StoplightColor,
    TestKind,
    Verdict,
    WiringStatus,
)

SHA_RE = re.compile(r'^[0-9a-f]{40}$')

SCHEMA_VERSION = 1


class ProofGraphParseError(Exception):
    """Raised when proof_graph.json fails to parse."""

    def __init__(self, message: str, path: Optional[list[str]] = None):
        self.path = path or []
        full = ".".join(self.path)
        super().__init__(f"{full}: {message}" if full else message)


def _deny_unknown(d: dict[str, Any], known: set[str], path: list[str]) -> None:
    unknown = set(d.keys()) - known
    if unknown:
        loc = ".".join(path) if path else "<root>"
        raise ProofGraphParseError(
            f"unknown fields {sorted(unknown)} at {loc}", path=path
        )


def _require(d: dict[str, Any], key: str, path: list[str]) -> Any:
    if key not in d:
        raise ProofGraphParseError(f"missing required field '{key}'", path=path)
    return d[key]


def _enum(cls: type, value: str, path: list[str]) -> Any:
    try:
        return cls(value)
    except ValueError:
        raise ProofGraphParseError(
            f"invalid {cls.__name__} value: {value!r}", path=path
        )


# ── Leaf dataclasses ──────────────────────────────────────────────────


@dataclass(frozen=True)
class LossMode:
    worst_case: str
    fail_closed_cap: str
    drift_metric: str
    level: LossModeLevel

    _KNOWN = {"worst_case", "fail_closed_cap", "drift_metric", "level"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> LossMode:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            worst_case=_require(d, "worst_case", path),
            fail_closed_cap=_require(d, "fail_closed_cap", path),
            drift_metric=_require(d, "drift_metric", path),
            level=_enum(LossModeLevel, _require(d, "level", path), path + ["level"]),
        )


@dataclass(frozen=True)
class StoryMeta:
    story_id: str
    category: str
    enforcement_point: str
    loss_mode: LossMode
    safety_critical: bool
    scope_touch: list[str]

    _KNOWN = {
        "story_id", "category", "enforcement_point",
        "loss_mode", "safety_critical", "scope_touch",
    }

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> StoryMeta:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            story_id=_require(d, "story_id", path),
            category=_require(d, "category", path),
            enforcement_point=_require(d, "enforcement_point", path),
            loss_mode=LossMode.from_dict(
                _require(d, "loss_mode", path), path + ["loss_mode"]
            ),
            safety_critical=_require(d, "safety_critical", path),
            scope_touch=_require(d, "scope_touch", path),
        )


@dataclass(frozen=True)
class CausalProof:
    mechanism: str
    dispatch_count_assert: Optional[str] = None
    reject_reason_assert: Optional[str] = None
    latch_reason_assert: Optional[str] = None

    _KNOWN = {
        "mechanism", "dispatch_count_assert",
        "reject_reason_assert", "latch_reason_assert",
    }

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> CausalProof:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            mechanism=_require(d, "mechanism", path),
            dispatch_count_assert=d.get("dispatch_count_assert"),
            reject_reason_assert=d.get("reject_reason_assert"),
            latch_reason_assert=d.get("latch_reason_assert"),
        )


@dataclass(frozen=True)
class TestExecution:
    ran_at_head_sha: str
    pass_result: bool

    _KNOWN = {"ran_at_head_sha", "pass_result"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> TestExecution:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            ran_at_head_sha=_require(d, "ran_at_head_sha", path),
            pass_result=_require(d, "pass_result", path),
        )


@dataclass(frozen=True)
class TestEntry:
    test_name: str
    kind: TestKind
    causal_proof: CausalProof
    execution: TestExecution

    _KNOWN = {"test_name", "kind", "causal_proof", "execution"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> TestEntry:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            test_name=_require(d, "test_name", path),
            kind=_enum(TestKind, _require(d, "kind", path), path + ["kind"]),
            causal_proof=CausalProof.from_dict(
                _require(d, "causal_proof", path), path + ["causal_proof"]
            ),
            execution=TestExecution.from_dict(
                _require(d, "execution", path), path + ["execution"]
            ),
        )


@dataclass(frozen=True)
class Enforcement:
    status: EnforcementStatus
    evidence: list[str]

    _KNOWN = {"status", "evidence"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> Enforcement:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            status=_enum(
                EnforcementStatus, _require(d, "status", path), path + ["status"]
            ),
            evidence=_require(d, "evidence", path),
        )


@dataclass(frozen=True)
class Wiring:
    status: WiringStatus
    evidence: str

    _KNOWN = {"status", "evidence"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> Wiring:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            status=_enum(
                WiringStatus, _require(d, "status", path), path + ["status"]
            ),
            evidence=_require(d, "evidence", path),
        )


@dataclass(frozen=True)
class Observability:
    metric: str
    alert: str

    _KNOWN = {"metric", "alert"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> Observability:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            metric=_require(d, "metric", path),
            alert=_require(d, "alert", path),
        )


@dataclass(frozen=True)
class PremortemChecks:
    stoplight: StoplightColor
    sections_filled: int

    _KNOWN = {"stoplight", "sections_filled"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> PremortemChecks:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            stoplight=_enum(
                StoplightColor, _require(d, "stoplight", path), path + ["stoplight"]
            ),
            sections_filled=_require(d, "sections_filled", path),
        )


@dataclass(frozen=True)
class ATVerdict:
    verdict: Verdict
    severity: Severity
    rationale: str

    _KNOWN = {"verdict", "severity", "rationale"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> ATVerdict:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            verdict=_enum(Verdict, _require(d, "verdict", path), path + ["verdict"]),
            severity=_enum(
                Severity, _require(d, "severity", path), path + ["severity"]
            ),
            rationale=_require(d, "rationale", path),
        )


@dataclass(frozen=True)
class EquivalentMutant:
    mutant_description: str
    killed_by: str

    _KNOWN = {"mutant_description", "killed_by"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> EquivalentMutant:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            mutant_description=_require(d, "mutant_description", path),
            killed_by=_require(d, "killed_by", path),
        )


@dataclass(frozen=True)
class DebtEntry:
    description: str
    target_slice: str

    _KNOWN = {"description", "target_slice"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> DebtEntry:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            description=_require(d, "description", path),
            target_slice=_require(d, "target_slice", path),
        )


# ── AT Entry ──────────────────────────────────────────────────────────


@dataclass(frozen=True)
class ATEntry:
    at_id: str
    enforcement: Enforcement
    tests: list[TestEntry]
    wiring: Wiring
    observability: Observability
    premortem_checks: PremortemChecks
    at_verdict: ATVerdict
    equivalent_mutants: list[EquivalentMutant] = field(default_factory=list)
    debt: Optional[DebtEntry] = None

    _KNOWN = {
        "at_id", "enforcement", "tests", "wiring", "observability",
        "premortem_checks", "at_verdict", "equivalent_mutants", "debt",
    }

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> ATEntry:
        _deny_unknown(d, cls._KNOWN, path)
        tests_raw = _require(d, "tests", path)
        tests = [
            TestEntry.from_dict(t, path + [f"tests[{i}]"])
            for i, t in enumerate(tests_raw)
        ]
        mutants_raw = d.get("equivalent_mutants", [])
        mutants = [
            EquivalentMutant.from_dict(m, path + [f"equivalent_mutants[{i}]"])
            for i, m in enumerate(mutants_raw)
        ]
        debt_raw = d.get("debt")
        debt = DebtEntry.from_dict(debt_raw, path + ["debt"]) if debt_raw else None

        return cls(
            at_id=_require(d, "at_id", path),
            enforcement=Enforcement.from_dict(
                _require(d, "enforcement", path), path + ["enforcement"]
            ),
            tests=tests,
            wiring=Wiring.from_dict(
                _require(d, "wiring", path), path + ["wiring"]
            ),
            observability=Observability.from_dict(
                _require(d, "observability", path), path + ["observability"]
            ),
            premortem_checks=PremortemChecks.from_dict(
                _require(d, "premortem_checks", path), path + ["premortem_checks"]
            ),
            at_verdict=ATVerdict.from_dict(
                _require(d, "at_verdict", path), path + ["at_verdict"]
            ),
            equivalent_mutants=mutants,
            debt=debt,
        )


# ── Story Verdict ─────────────────────────────────────────────────────


@dataclass(frozen=True)
class DebtRegisterEntry:
    at_id: str
    description: str
    target_slice: str

    _KNOWN = {"at_id", "description", "target_slice"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> DebtRegisterEntry:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            at_id=_require(d, "at_id", path),
            description=_require(d, "description", path),
            target_slice=_require(d, "target_slice", path),
        )


@dataclass(frozen=True)
class StoryVerdict:
    reconciliation_status: ReconciliationStatus
    blocking_count: int
    hardening_count: int
    summary: str

    _KNOWN = {
        "reconciliation_status", "blocking_count", "hardening_count", "summary",
    }

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> StoryVerdict:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            reconciliation_status=_enum(
                ReconciliationStatus,
                _require(d, "reconciliation_status", path),
                path + ["reconciliation_status"],
            ),
            blocking_count=_require(d, "blocking_count", path),
            hardening_count=_require(d, "hardening_count", path),
            summary=_require(d, "summary", path),
        )


# ── Top-Level ProofGraph ─────────────────────────────────────────────


@dataclass(frozen=True)
class ProofGraph:
    schema_version: int
    head_sha: str
    generated_at: str
    story_meta: StoryMeta
    ats: list[ATEntry]
    story_verdict: StoryVerdict
    debt_register: list[DebtRegisterEntry] = field(default_factory=list)

    _KNOWN = {
        "schema_version", "head_sha", "generated_at",
        "story_meta", "ats", "story_verdict", "debt_register",
    }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> ProofGraph:
        path: list[str] = []
        _deny_unknown(d, cls._KNOWN, path)

        version = _require(d, "schema_version", path)
        if version != SCHEMA_VERSION:
            raise ProofGraphParseError(
                f"unsupported schema_version {version} (expected {SCHEMA_VERSION}). "
                f"Upgrade your proof_graph tooling.",
                path=["schema_version"],
            )

        ats_raw = _require(d, "ats", path)
        ats = [
            ATEntry.from_dict(a, [f"ats[{i}]"])
            for i, a in enumerate(ats_raw)
        ]
        dr_raw = d.get("debt_register", [])
        debt_register = [
            DebtRegisterEntry.from_dict(e, [f"debt_register[{i}]"])
            for i, e in enumerate(dr_raw)
        ]

        return cls(
            schema_version=version,
            head_sha=_require(d, "head_sha", path),
            generated_at=_require(d, "generated_at", path),
            story_meta=StoryMeta.from_dict(
                _require(d, "story_meta", path), ["story_meta"]
            ),
            ats=ats,
            story_verdict=StoryVerdict.from_dict(
                _require(d, "story_verdict", path), ["story_verdict"]
            ),
            debt_register=debt_register,
        )
