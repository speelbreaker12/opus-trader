"""Shared domain types for Commander strategies."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class Side(Enum):
    BUY = "buy"
    SELL = "sell"


class OptionType(Enum):
    CALL = "call"
    PUT = "put"


class IntentClass(Enum):
    """Intent classification per CONTRACT.md.

    Fail-closed: if uncertain, treat as OPEN (most restrictive).
    """

    OPEN = "open"
    CLOSE = "close"


@dataclass(frozen=True)
class OptionSpec:
    """Describes a specific option contract."""

    underlying: str  # e.g. "BTC"
    expiry: str  # ISO date string e.g. "2026-04-25"
    strike: float
    option_type: OptionType


@dataclass(frozen=True)
class L2Level:
    """Single price/size level from the order book."""

    price: float
    size: float


@dataclass(frozen=True)
class L2Snapshot:
    """Top-of-book snapshot for an instrument."""

    bids: list[L2Level]
    asks: list[L2Level]
    timestamp_ms: int

    @property
    def best_bid(self) -> Optional[float]:
        return self.bids[0].price if self.bids else None

    @property
    def best_ask(self) -> Optional[float]:
        return self.asks[0].price if self.asks else None

    @property
    def mid_price(self) -> Optional[float]:
        bb = self.best_bid
        ba = self.best_ask
        if bb is not None and ba is not None:
            return (bb + ba) / 2.0
        return None


@dataclass(frozen=True)
class TradeIntent:
    """A trading intent to be dispatched to the Soldier execution engine."""

    instrument_id: str
    side: Side
    qty_coin: float
    limit_price: float
    intent_class: IntentClass
    reduce_only: bool
    strategy_id: str
    gross_edge_usd: float
    predicted_slippage_bps_sim: float
    decision_snapshot_id: Optional[str] = None
