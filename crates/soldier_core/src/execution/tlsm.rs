//! Trade Lifecycle State Machine (TLSM) per CONTRACT.md §2.1.
//!
//! **States:** `Created -> Sent -> Acked -> PartiallyFilled -> Filled | Canceled | Failed`
//!
//! **Hard Rules:**
//! - Never panic on out-of-order WS events.
//! - "Fill-before-Ack" is valid reality: accept fill, log anomaly, reconcile later.
//! - Every transition is appended to WAL immediately.
//!
//! **Cross-crate sync:** `soldier_infra::store::ledger::TlsState::is_valid_successor()`
//! maintains a state-level whitelist derived from this module's `apply()` transitions.
//! When adding new transitions here, update that whitelist to stay in sync.
//!
//! AT-230, AT-210.

// ─── States ─────────────────────────────────────────────────────────────

/// TLSM states per CONTRACT.md §2.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TlsmState {
    Created,
    Sent,
    Acked,
    PartiallyFilled,
    Filled,
    Cancelled,
    Failed,
}

impl TlsmState {
    /// Whether this state is terminal (no further transitions expected).
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            TlsmState::Filled | TlsmState::Cancelled | TlsmState::Failed
        )
    }
}

// ─── Events ─────────────────────────────────────────────────────────────

/// Events that can drive TLSM transitions.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TlsmEvent {
    /// Order sent to exchange.
    Sent,
    /// Exchange acknowledged the order.
    Acked,
    /// Partial fill received.
    PartialFill,
    /// Full fill received.
    Filled,
    /// Order cancelled.
    Cancelled,
    /// Order rejected by exchange.
    Rejected,
    /// Internal failure.
    Failed,
}

// ─── Transition result ──────────────────────────────────────────────────

/// Result of applying an event to the TLSM.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransitionResult {
    /// Normal transition — state changed as expected.
    Transitioned { from: TlsmState, to: TlsmState },
    /// Out-of-order event accepted — state changed but order was unexpected.
    /// CONTRACT.md: "Fill-before-Ack is valid reality: accept fill, log anomaly."
    OutOfOrder {
        from: TlsmState,
        to: TlsmState,
        anomaly: String,
    },
    /// Event ignored — already in terminal state or no-op.
    Ignored {
        current: TlsmState,
        event: TlsmEvent,
        reason: String,
    },
}

// ─── TLSM instance ─────────────────────────────────────────────────────

/// A single TLSM instance tracking one order's lifecycle.
///
/// **Never panics** — all out-of-order events are handled gracefully.
#[derive(Debug, Clone)]
pub struct Tlsm {
    state: TlsmState,
    /// History of transitions for WAL append.
    transitions: Vec<(TlsmEvent, TlsmState, TlsmState)>,
}

impl Tlsm {
    /// Create a new TLSM in the `Created` state.
    pub fn new() -> Self {
        Self {
            state: TlsmState::Created,
            transitions: Vec::new(),
        }
    }

    /// Current state.
    pub fn state(&self) -> TlsmState {
        self.state
    }

    /// Number of transitions recorded.
    pub fn transition_count(&self) -> usize {
        self.transitions.len()
    }

    /// Apply an event to the TLSM.
    ///
    /// CONTRACT.md §2.1: "Never panic on out-of-order WS events."
    /// Returns the transition result — never panics.
    pub fn apply(&mut self, event: TlsmEvent) -> TransitionResult {
        let from = self.state;

        // Terminal states: ignore all further events.
        if from.is_terminal() {
            return TransitionResult::Ignored {
                current: from,
                event,
                reason: "already in terminal state".to_string(),
            };
        }

        match (&from, &event) {
            // ─── Normal transitions ─────────────────────────────────
            (TlsmState::Created, TlsmEvent::Sent) => self.transition(from, TlsmState::Sent, event),

            (TlsmState::Sent, TlsmEvent::Acked) => self.transition(from, TlsmState::Acked, event),

            (TlsmState::Acked, TlsmEvent::PartialFill) => {
                self.transition(from, TlsmState::PartiallyFilled, event)
            }

            (TlsmState::Acked, TlsmEvent::Filled) => {
                self.transition(from, TlsmState::Filled, event)
            }

            (TlsmState::PartiallyFilled, TlsmEvent::PartialFill) => {
                self.transition(from, TlsmState::PartiallyFilled, event)
            }

            (TlsmState::PartiallyFilled, TlsmEvent::Filled) => {
                self.transition(from, TlsmState::Filled, event)
            }

            // Cancel from any non-terminal state
            (_, TlsmEvent::Cancelled) => self.transition(from, TlsmState::Cancelled, event),

            // Reject from Sent or Created
            (TlsmState::Created | TlsmState::Sent, TlsmEvent::Rejected) => {
                // Rejected maps to Failed state
                self.transition(from, TlsmState::Failed, event)
            }

            // Failed from any non-terminal state
            (_, TlsmEvent::Failed) => self.transition(from, TlsmState::Failed, event),

            // ─── Out-of-order: Fill before Ack (AT-230) ─────────────
            (TlsmState::Sent, TlsmEvent::Filled) => {
                self.out_of_order(from, TlsmState::Filled, event, "fill-before-ack")
            }

            (TlsmState::Sent, TlsmEvent::PartialFill) => self.out_of_order(
                from,
                TlsmState::PartiallyFilled,
                event,
                "partial-fill-before-ack",
            ),

            // ─── Out-of-order: Fill from Created (AT-210) ───────────
            (TlsmState::Created, TlsmEvent::Filled) => self.out_of_order(
                from,
                TlsmState::Filled,
                event,
                "fill-before-send (orphan fill)",
            ),

            (TlsmState::Created, TlsmEvent::PartialFill) => self.out_of_order(
                from,
                TlsmState::PartiallyFilled,
                event,
                "partial-fill-before-send",
            ),

            (TlsmState::Created, TlsmEvent::Acked) => {
                self.out_of_order(from, TlsmState::Acked, event, "ack-before-send")
            }

            // ─── Out-of-order: Ack after fills ──────────────────────
            (TlsmState::PartiallyFilled, TlsmEvent::Acked) => {
                // Already partially filled, ack arrives late — ignore
                // (state is already past Acked)
                TransitionResult::Ignored {
                    current: from,
                    event,
                    reason: "ack after partial fill — already past Acked".to_string(),
                }
            }

            // ─── Anything else: ignore ──────────────────────────────
            _ => TransitionResult::Ignored {
                current: from,
                event,
                reason: "no valid transition".to_string(),
            },
        }
    }

    /// Record a normal transition.
    fn transition(&mut self, from: TlsmState, to: TlsmState, event: TlsmEvent) -> TransitionResult {
        self.state = to;
        self.transitions.push((event, from, to));
        TransitionResult::Transitioned { from, to }
    }

    /// Record an out-of-order transition.
    fn out_of_order(
        &mut self,
        from: TlsmState,
        to: TlsmState,
        event: TlsmEvent,
        anomaly: &str,
    ) -> TransitionResult {
        self.state = to;
        self.transitions.push((event, from, to));
        TransitionResult::OutOfOrder {
            from,
            to,
            anomaly: anomaly.to_string(),
        }
    }
}

impl Default for Tlsm {
    fn default() -> Self {
        Self::new()
    }
}
