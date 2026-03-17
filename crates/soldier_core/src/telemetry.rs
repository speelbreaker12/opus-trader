//! Internal event sink primitives for graybox gate tests.
//!
//! Keep this crate-private. Public facades continue to expose only
//! stable domain APIs, not observability internals.

pub(crate) trait EventSink<E> {
    fn emit(&mut self, event: E);
}

#[cfg_attr(not(test), allow(dead_code))]
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct NoopEvents;

impl<E> EventSink<E> for NoopEvents {
    fn emit(&mut self, _event: E) {}
}

impl<E> EventSink<E> for Vec<E> {
    fn emit(&mut self, event: E) {
        self.push(event);
    }
}

#[cfg(test)]
mod tests {
    use super::{EventSink, NoopEvents};

    #[derive(Debug, PartialEq, Eq)]
    enum TestEvent {
        First,
        Second,
    }

    #[test]
    fn telemetry_sink_supports_noop_and_vec() {
        let mut noop = NoopEvents;
        noop.emit(TestEvent::First);

        let mut events = Vec::new();
        events.emit(TestEvent::First);
        events.emit(TestEvent::Second);

        assert_eq!(events, vec![TestEvent::First, TestEvent::Second]);
    }
}
