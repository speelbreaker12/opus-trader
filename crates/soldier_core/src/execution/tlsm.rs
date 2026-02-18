//! Trade Lifecycle State Machine (TLSM) per CONTRACT.md §2.1.
//!
//! **States:** `Created -> Sent -> Acked -> PartiallyFilled -> Filled | Canceled | Failed`
//!
//! **Hard Rules:**
//! - Never panic on out-of-order WS events.
//! - "Fill-before-Ack" is valid reality: accept fill, log anomaly, reconcile later.
//! - Every transition is appended to WAL immediately.
//! - Pending exposure reservations are settled on terminal state (S6-008).
//!
//! **Cross-crate sync:** `soldier_infra::store::ledger::TlsState::is_valid_successor()`
//! maintains a state-level whitelist derived from this module's `apply()` transitions.
//! When adding new transitions here, update that whitelist to stay in sync.
//!
//! AT-230, AT-210, AT-225, AT-910.

use crate::risk::ReservationId;

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

// ─── Transition sink ────────────────────────────────────────────────────

/// Persistable TLSM transition emitted for WAL append.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PersistedTransition {
    pub event: TlsmEvent,
    pub from: TlsmState,
    pub to: TlsmState,
    pub anomaly: Option<String>,
}

/// Consumer of persisted transitions.
pub trait TlsmTransitionSink {
    fn append_transition(&mut self, transition: PersistedTransition) -> Result<(), String>;
}

/// Default sink used by `Tlsm::apply` when no external sink is provided.
#[derive(Debug, Default)]
pub struct NoopTransitionSink;

impl TlsmTransitionSink for NoopTransitionSink {
    fn append_transition(&mut self, _transition: PersistedTransition) -> Result<(), String> {
        Ok(())
    }
}

/// TLSM apply error.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TlsmError {
    PersistFailed { reason: String },
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
    /// Pending exposure reservation ID, settled on terminal state.
    pending_reservation_id: Option<ReservationId>,
}

impl Tlsm {
    /// Create a new TLSM in the `Created` state.
    pub fn new() -> Self {
        Self {
            state: TlsmState::Created,
            transitions: Vec::new(),
            pending_reservation_id: None,
        }
    }

    /// Create a new TLSM with a pending exposure reservation (S6-008).
    pub fn with_pending_reservation(reservation_id: ReservationId) -> Self {
        Self {
            state: TlsmState::Created,
            transitions: Vec::new(),
            pending_reservation_id: Some(reservation_id),
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

    /// Get and clear the pending reservation ID if reaching terminal state.
    /// Returns Some(reservation_id) when transitioning to terminal state, None otherwise.
    pub fn take_pending_reservation_on_terminal(&mut self) -> Option<ReservationId> {
        if self.state.is_terminal() {
            self.pending_reservation_id.take()
        } else {
            None
        }
    }

    /// Apply an event with the default no-op persistence sink.
    ///
    /// CONTRACT.md §2.1: "Never panic on out-of-order WS events."
    /// Returns the transition result — structurally cannot panic.
    pub fn apply(&mut self, event: TlsmEvent) -> TransitionResult {
        let mut sink = NoopTransitionSink;
        let fallback_event = event.clone();
        let fallback_state = self.state;
        match self.apply_with_sink(event, &mut sink) {
            Ok(result) => result,
            Err(_) => {
                // NoopTransitionSink always returns Ok(()). If this branch
                // ever executes, something is deeply wrong. We log and
                // debug_assert to catch it in testing, but maintain the
                // structural no-panic guarantee per CONTRACT.md §2.1.
                debug_assert!(false, "unreachable: NoopTransitionSink returned Err");
                tracing::error!(
                    "BUG: NoopTransitionSink returned Err — this should be unreachable"
                );
                TransitionResult::Ignored {
                    current: fallback_state,
                    event: fallback_event,
                    reason: "unreachable: noop sink failure".to_string(),
                }
            }
        }
    }

    /// Apply an event and emit accepted transitions to `sink`.
    ///
    /// If the sink returns an error, the TLSM state is **not** mutated
    /// (persist-before-state-change atomicity).
    pub fn apply_with_sink(
        &mut self,
        event: TlsmEvent,
        sink: &mut dyn TlsmTransitionSink,
    ) -> Result<TransitionResult, TlsmError> {
        let from = self.state;

        // Terminal states: ignore all further events.
        if from.is_terminal() {
            return Ok(TransitionResult::Ignored {
                current: from,
                event,
                reason: "already in terminal state".to_string(),
            });
        }

        match (&from, &event) {
            // ─── Normal transitions ─────────────────────────────────
            (TlsmState::Created, TlsmEvent::Sent) => {
                self.transition(from, TlsmState::Sent, event, sink)
            }

            (TlsmState::Sent, TlsmEvent::Acked) => {
                self.transition(from, TlsmState::Acked, event, sink)
            }

            (TlsmState::Acked, TlsmEvent::PartialFill) => {
                self.transition(from, TlsmState::PartiallyFilled, event, sink)
            }

            (TlsmState::Acked, TlsmEvent::Filled) => {
                self.transition(from, TlsmState::Filled, event, sink)
            }

            (TlsmState::PartiallyFilled, TlsmEvent::PartialFill) => {
                self.transition(from, TlsmState::PartiallyFilled, event, sink)
            }

            (TlsmState::PartiallyFilled, TlsmEvent::Filled) => {
                self.transition(from, TlsmState::Filled, event, sink)
            }

            // Cancel from any non-terminal state
            (_, TlsmEvent::Cancelled) => self.transition(from, TlsmState::Cancelled, event, sink),

            // Reject from Sent or Created
            (TlsmState::Created | TlsmState::Sent, TlsmEvent::Rejected) => {
                self.transition(from, TlsmState::Failed, event, sink)
            }

            // Failed from any non-terminal state
            (_, TlsmEvent::Failed) => self.transition(from, TlsmState::Failed, event, sink),

            // ─── Out-of-order: Fill before Ack (AT-230) ─────────────
            (TlsmState::Sent, TlsmEvent::Filled) => {
                self.out_of_order(from, TlsmState::Filled, event, "fill-before-ack", sink)
            }

            (TlsmState::Sent, TlsmEvent::PartialFill) => self.out_of_order(
                from,
                TlsmState::PartiallyFilled,
                event,
                "partial-fill-before-ack",
                sink,
            ),

            // ─── Out-of-order: Fill from Created (AT-210) ───────────
            (TlsmState::Created, TlsmEvent::Filled) => self.out_of_order(
                from,
                TlsmState::Filled,
                event,
                "fill-before-send (orphan fill)",
                sink,
            ),

            (TlsmState::Created, TlsmEvent::PartialFill) => self.out_of_order(
                from,
                TlsmState::PartiallyFilled,
                event,
                "partial-fill-before-send",
                sink,
            ),

            (TlsmState::Created, TlsmEvent::Acked) => {
                self.out_of_order(from, TlsmState::Acked, event, "ack-before-send", sink)
            }

            // ─── Out-of-order: Ack after fills ──────────────────────
            (TlsmState::PartiallyFilled, TlsmEvent::Acked) => {
                // Already partially filled, ack arrives late — ignore
                Ok(TransitionResult::Ignored {
                    current: from,
                    event,
                    reason: "ack after partial fill — already past Acked".to_string(),
                })
            }

            // ─── Anything else: ignore ──────────────────────────────
            _ => Ok(TransitionResult::Ignored {
                current: from,
                event,
                reason: "no valid transition".to_string(),
            }),
        }
    }

    /// Record a normal transition. Persist via sink BEFORE mutating state.
    fn transition(
        &mut self,
        from: TlsmState,
        to: TlsmState,
        event: TlsmEvent,
        sink: &mut dyn TlsmTransitionSink,
    ) -> Result<TransitionResult, TlsmError> {
        sink.append_transition(PersistedTransition {
            event: event.clone(),
            from,
            to,
            anomaly: None,
        })
        .map_err(|reason| TlsmError::PersistFailed { reason })?;
        self.state = to;
        self.transitions.push((event, from, to));
        Ok(TransitionResult::Transitioned { from, to })
    }

    /// Record an out-of-order transition. Persist via sink BEFORE mutating state.
    fn out_of_order(
        &mut self,
        from: TlsmState,
        to: TlsmState,
        event: TlsmEvent,
        anomaly: &str,
        sink: &mut dyn TlsmTransitionSink,
    ) -> Result<TransitionResult, TlsmError> {
        sink.append_transition(PersistedTransition {
            event: event.clone(),
            from,
            to,
            anomaly: Some(anomaly.to_string()),
        })
        .map_err(|reason| TlsmError::PersistFailed { reason })?;
        self.state = to;
        self.transitions.push((event, from, to));
        Ok(TransitionResult::OutOfOrder {
            from,
            to,
            anomaly: anomaly.to_string(),
        })
    }
}

impl Default for Tlsm {
    fn default() -> Self {
        Self::new()
    }
}
