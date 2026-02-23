"""Proof graph dataclasses with from_dict() and deny-unknown-fields."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Optional

from .enums import (
    AssumptionStatus,
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

SHA_RE = re.compile(r'^[0-9a-f]{40}$')

SCHEMA_VERSION_MIN = 1
SCHEMA_VERSION_MAX = 2


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


# ── V2 Evidence Entry ────────────────────────────────────────────────


@dataclass(frozen=True)
class EvidenceEntry:
    """Structured file/line/symbol citation (V2)."""
    file: str
    line_start: int
    line_end: int
    symbol: str
    snippet: str = ""

    _KNOWN = {"file", "line_start", "line_end", "symbol", "snippet"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str]) -> EvidenceEntry:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            file=_require(d, "file", path),
            line_start=_require(d, "line_start", path),
            line_end=_require(d, "line_end", path),
            symbol=_require(d, "symbol", path),
            snippet=d.get("snippet", ""),
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
    why_causal: str = ""  # V2: explanation of causal mechanism

    _KNOWN = {
        "mechanism", "dispatch_count_assert",
        "reject_reason_assert", "latch_reason_assert",
    }
    _KNOWN_V2 = _KNOWN | {"why_causal"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str],
                  version: int = 1) -> CausalProof:
        known = cls._KNOWN_V2 if version >= 2 else cls._KNOWN
        _deny_unknown(d, known, path)
        return cls(
            mechanism=_require(d, "mechanism", path),
            dispatch_count_assert=d.get("dispatch_count_assert"),
            reject_reason_assert=d.get("reject_reason_assert"),
            latch_reason_assert=d.get("latch_reason_assert"),
            why_causal=d.get("why_causal", ""),
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
    def from_dict(cls, d: dict[str, Any], path: list[str],
                  version: int = 1) -> TestEntry:
        _deny_unknown(d, cls._KNOWN, path)
        return cls(
            test_name=_require(d, "test_name", path),
            kind=_enum(TestKind, _require(d, "kind", path), path + ["kind"]),
            causal_proof=CausalProof.from_dict(
                _require(d, "causal_proof", path), path + ["causal_proof"],
                version=version,
            ),
            execution=TestExecution.from_dict(
                _require(d, "execution", path), path + ["execution"]
            ),
        )


@dataclass(frozen=True)
class Enforcement:
    status: EnforcementStatus
    evidence: list[str]
    evidence_entries: list[EvidenceEntry] = field(default_factory=list)  # V2

    _KNOWN = {"status", "evidence"}
    _KNOWN_V2 = _KNOWN | {"evidence_entries"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str],
                  version: int = 1) -> Enforcement:
        known = cls._KNOWN_V2 if version >= 2 else cls._KNOWN
        _deny_unknown(d, known, path)
        entries_raw = d.get("evidence_entries", [])
        entries = [
            EvidenceEntry.from_dict(e, path + [f"evidence_entries[{i}]"])
            for i, e in enumerate(entries_raw)
        ]
        return cls(
            status=_enum(
                EnforcementStatus, _require(d, "status", path), path + ["status"]
            ),
            evidence=_require(d, "evidence", path),
            evidence_entries=entries,
        )


@dataclass(frozen=True)
class Wiring:
    status: WiringStatus
    evidence: str
    caller_chain: list[str] = field(default_factory=list)  # V2
    entrypoint: str = ""  # V2
    proof_type: str = ""  # V2

    _KNOWN = {"status", "evidence"}
    _KNOWN_V2 = _KNOWN | {"caller_chain", "entrypoint", "proof_type"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str],
                  version: int = 1) -> Wiring:
        known = cls._KNOWN_V2 if version >= 2 else cls._KNOWN
        _deny_unknown(d, known, path)
        return cls(
            status=_enum(
                WiringStatus, _require(d, "status", path), path + ["status"]
            ),
            evidence=_require(d, "evidence", path),
            caller_chain=d.get("caller_chain", []),
            entrypoint=d.get("entrypoint", ""),
            proof_type=d.get("proof_type", ""),
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
    section5_wrong_impl_blocked: Optional[WrongImplStatus] = None  # V2
    section4_decision_match: Optional[DecisionMatch] = None  # V2
    section2_assumptions: Optional[AssumptionStatus] = None  # V2

    _KNOWN = {"stoplight", "sections_filled"}
    _KNOWN_V2 = _KNOWN | {
        "section5_wrong_impl_blocked", "section4_decision_match",
        "section2_assumptions",
    }

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str],
                  version: int = 1) -> PremortemChecks:
        known = cls._KNOWN_V2 if version >= 2 else cls._KNOWN
        _deny_unknown(d, known, path)
        s5 = None
        if "section5_wrong_impl_blocked" in d:
            s5 = _enum(WrongImplStatus, d["section5_wrong_impl_blocked"],
                       path + ["section5_wrong_impl_blocked"])
        s4 = None
        if "section4_decision_match" in d:
            s4 = _enum(DecisionMatch, d["section4_decision_match"],
                       path + ["section4_decision_match"])
        s2 = None
        if "section2_assumptions" in d:
            s2 = _enum(AssumptionStatus, d["section2_assumptions"],
                       path + ["section2_assumptions"])
        return cls(
            stoplight=_enum(
                StoplightColor, _require(d, "stoplight", path), path + ["stoplight"]
            ),
            sections_filled=_require(d, "sections_filled", path),
            section5_wrong_impl_blocked=s5,
            section4_decision_match=s4,
            section2_assumptions=s2,
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
    extra_discovered: bool = False  # V2

    _KNOWN = {
        "at_id", "enforcement", "tests", "wiring", "observability",
        "premortem_checks", "at_verdict", "equivalent_mutants", "debt",
    }
    _KNOWN_V2 = _KNOWN | {"extra_discovered"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str],
                  version: int = 1) -> ATEntry:
        known = cls._KNOWN_V2 if version >= 2 else cls._KNOWN
        _deny_unknown(d, known, path)
        tests_raw = _require(d, "tests", path)
        tests = [
            TestEntry.from_dict(t, path + [f"tests[{i}]"], version=version)
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
                _require(d, "enforcement", path), path + ["enforcement"],
                version=version,
            ),
            tests=tests,
            wiring=Wiring.from_dict(
                _require(d, "wiring", path), path + ["wiring"],
                version=version,
            ),
            observability=Observability.from_dict(
                _require(d, "observability", path), path + ["observability"]
            ),
            premortem_checks=PremortemChecks.from_dict(
                _require(d, "premortem_checks", path), path + ["premortem_checks"],
                version=version,
            ),
            at_verdict=ATVerdict.from_dict(
                _require(d, "at_verdict", path), path + ["at_verdict"]
            ),
            equivalent_mutants=mutants,
            debt=debt,
            extra_discovered=d.get("extra_discovered", False),
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
    trading_halt_trigger: bool = False  # V2

    _KNOWN = {
        "reconciliation_status", "blocking_count", "hardening_count", "summary",
    }
    _KNOWN_V2 = _KNOWN | {"trading_halt_trigger"}

    @classmethod
    def from_dict(cls, d: dict[str, Any], path: list[str],
                  version: int = 1) -> StoryVerdict:
        known = cls._KNOWN_V2 if version >= 2 else cls._KNOWN
        _deny_unknown(d, known, path)
        return cls(
            reconciliation_status=_enum(
                ReconciliationStatus,
                _require(d, "reconciliation_status", path),
                path + ["reconciliation_status"],
            ),
            blocking_count=_require(d, "blocking_count", path),
            hardening_count=_require(d, "hardening_count", path),
            summary=_require(d, "summary", path),
            trading_halt_trigger=d.get("trading_halt_trigger", False),
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
    meta: dict[str, Any] = field(default_factory=dict)  # V2: opaque extensibility

    _KNOWN = {
        "schema_version", "head_sha", "generated_at",
        "story_meta", "ats", "story_verdict", "debt_register",
    }
    _KNOWN_V2 = _KNOWN | {"meta"}

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> ProofGraph:
        path: list[str] = []

        version = _require(d, "schema_version", path)
        if not isinstance(version, int) or \
                version < SCHEMA_VERSION_MIN or version > SCHEMA_VERSION_MAX:
            raise ProofGraphParseError(
                f"unsupported schema_version {version} "
                f"(expected {SCHEMA_VERSION_MIN}-{SCHEMA_VERSION_MAX}). "
                f"Upgrade your proof_graph tooling.",
                path=["schema_version"],
            )

        known = cls._KNOWN_V2 if version >= 2 else cls._KNOWN
        _deny_unknown(d, known, path)

        ats_raw = _require(d, "ats", path)
        ats = [
            ATEntry.from_dict(a, [f"ats[{i}]"], version=version)
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
                _require(d, "story_verdict", path), ["story_verdict"],
                version=version,
            ),
            debt_register=debt_register,
            meta=d.get("meta", {}),
        )
