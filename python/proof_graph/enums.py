"""Enum types for proof graph schema."""
from enum import Enum


class Verdict(str, Enum):
    PROVEN_INTEGRATED = "PROVEN_INTEGRATED"
    PROVEN_UNIT = "PROVEN_UNIT"
    WEAK_PROOF = "WEAK_PROOF"
    CLAIMED_NOT_PROVEN = "CLAIMED_NOT_PROVEN"
    UNTESTED_ENFORCEMENT = "UNTESTED_ENFORCEMENT"
    WRONG_IMPL_UNBLOCKED = "WRONG_IMPL_UNBLOCKED"
    MISSING = "MISSING"
    FAIL_OPEN_RISK = "FAIL_OPEN_RISK"
    DEFERRED = "DEFERRED"
    INVALID_REF = "INVALID_REF"  # V2: contract reference invalid


class Severity(str, Enum):
    BLOCKING = "BLOCKING"
    HARDENING = "HARDENING"
    INFO = "INFO"


class WiringStatus(str, Enum):
    PROVEN_INTEGRATED = "PROVEN_INTEGRATED"
    PROVEN_UNIT = "PROVEN_UNIT"
    NOT_WIRED = "NOT_WIRED"


class EnforcementStatus(str, Enum):
    FOUND = "FOUND"
    NOT_FOUND = "NOT_FOUND"
    PARTIAL = "PARTIAL"


class TestKind(str, Enum):
    TRIP = "TRIP"
    NON_TRIP = "NON-TRIP"


class LossModeLevel(str, Enum):
    NONE = "NONE"
    LOW = "LOW"
    MED = "MED"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class StoplightColor(str, Enum):
    GREEN = "GREEN"
    YELLOW = "YELLOW"
    RED = "RED"


class ReconciliationStatus(str, Enum):
    RECONCILED = "RECONCILED"
    RECONCILED_WITH_DEBT = "RECONCILED_WITH_DEBT"
    NOT_RECONCILED = "NOT_RECONCILED"
    RECONCILED_UNIT_ONLY = "RECONCILED_UNIT_ONLY"  # V2
    BLOCKED_TRADING_HALT = "BLOCKED_TRADING_HALT"  # V2


class CausalMechanism(str, Enum):
    """Known causal proof mechanisms (V2)."""
    DISPATCH_COUNT = "dispatch_count"
    REJECT_REASON = "reject_reason"
    LATCH_REASON = "latch_reason"
    MODE_TRANSITION = "mode_transition"
    REASON_CODE = "reason_code"
    CORTEX_OVERRIDE = "cortex_override"


class WrongImplStatus(str, Enum):
    """Premortem §5 wrong-impl blocked status (V2)."""
    ALL = "ALL"
    PARTIAL = "PARTIAL"
    NONE = "NONE"


class DecisionMatch(str, Enum):
    """Premortem §4 decision match status (V2)."""
    YES = "YES"
    NO = "NO"
    PARTIAL = "PARTIAL"


class AssumptionStatus(str, Enum):
    """Premortem §2 assumption validation status (V2)."""
    ALL_VALIDATED = "ALL_VALIDATED"
    PARTIAL = "PARTIAL"
    NONE = "NONE"
