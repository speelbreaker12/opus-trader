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
