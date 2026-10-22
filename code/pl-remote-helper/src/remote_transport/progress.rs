//! Observed physical byte progress of one connection.

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use tokio::time::Instant;

/// Monotonic timestamp of the last real byte moved by the underlying channel.
///
/// Heartbeats and inbound leases must not mistake a stalled operation for a dead
/// connection, or a large transfer for a lost peer, so the timestamp is updated by the
/// transport adapter on actual reads and writes only.
#[derive(Debug)]
pub(crate) struct Progress {
    started: Instant,
    last_nanos: AtomicU64,
}

impl Progress {
    pub(crate) fn new() -> Self {
        Self {
            started: Instant::now(),
            last_nanos: AtomicU64::new(0),
        }
    }

    /// Records that the channel moved bytes at the current instant.
    pub(crate) fn touch(&self) {
        let nanos = self.started.elapsed().as_nanos().min(u128::from(u64::MAX)) as u64;
        self.last_nanos.store(nanos, Ordering::Relaxed);
    }

    /// Instant of the last observed progress, or the connection start.
    pub(crate) fn now(&self) -> Instant {
        self.started + Duration::from_nanos(self.last_nanos.load(Ordering::Relaxed))
    }
}
