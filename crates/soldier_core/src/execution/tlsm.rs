//! Trade Lifecycle State Machine (TLSM) per CONTRACT.md section 2.1.
//!
//! States: `Created -> Sent -> Acked -> PartiallyFilled -> Filled | Cancelled | Failed`
//!
//! Hard Rules:
//! - Never panic on out-of-order WS events.
//! - "Fill-before-Ack" is valid reality: accept fill, log anomaly, reconcile later.
//! - Every transition is emitted to a transition sink for WAL append wiring.

// --- States -------------------------------------------------------------

/// TLSM states per CONTRACT.md section 2.1.
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

// --- Events -------------------------------------------------------------

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

// --- Transition sink ----------------------------------------------------

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

// --- Transition result --------------------------------------------------

/// Result of applying an event to the TLSM.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransitionResult {
    /// Normal transition — state changed as expected.
    Transitioned { from: TlsmState, to: TlsmState },
    /// Out-of-order event accepted — state changed but order was unexpected.
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

// --- TLSM instance ------------------------------------------------------

/// A single TLSM instance tracking one order's lifecycle.
#[derive(Debug, Clone)]
pub struct Tlsm {
    state: TlsmState,
    /// Transition history for test/debug visibility.
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

    /// Number of transitions recorded in local history.
    pub fn transition_count(&self) -> usize {
        self.transitions.len()
    }

    /// Apply an event with the default no-op persistence sink.
    pub fn apply(&mut self, event: TlsmEvent) -> TransitionResult {
        let mut sink = NoopTransitionSink;
        self.apply_with_sink(event, &mut sink)
            .expect("noop transition sink should never fail")
    }

    /// Apply an event and emit accepted transitions to `sink`.
    pub fn apply_with_sink(
        &mut self,
        event: TlsmEvent,
        sink: &mut dyn TlsmTransitionSink,
    ) -> Result<TransitionResult, TlsmError> {
        let from = self.state;

        if from.is_terminal() {
            return Ok(TransitionResult::Ignored {
                current: from,
                event,
                reason: "already in terminal state".to_string(),
            });
        }

        match (&from, &event) {
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
            (_, TlsmEvent::Cancelled) => self.transition(from, TlsmState::Cancelled, event, sink),
            (TlsmState::Created | TlsmState::Sent, TlsmEvent::Rejected) => {
                self.transition(from, TlsmState::Failed, event, sink)
            }
            (_, TlsmEvent::Failed) => self.transition(from, TlsmState::Failed, event, sink),
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
            (TlsmState::PartiallyFilled, TlsmEvent::Acked) => Ok(TransitionResult::Ignored {
                current: from,
                event,
                reason: "ack after partial fill — already past Acked".to_string(),
            }),
            _ => Ok(TransitionResult::Ignored {
                current: from,
                event,
                reason: "no valid transition".to_string(),
            }),
        }
    }

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
