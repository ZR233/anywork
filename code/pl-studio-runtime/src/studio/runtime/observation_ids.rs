//! One allocator injected by the runtime composition root into observation owners.
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

#[derive(Clone)]
pub(super) struct ObservationIds(Arc<Inner>);

struct Inner {
    epoch: String,
    next: AtomicU64,
}

impl ObservationIds {
    pub(super) fn new(epoch: String) -> Self {
        Self(Arc::new(Inner {
            epoch,
            next: AtomicU64::new(1),
        }))
    }

    pub(super) fn epoch(&self) -> &str {
        &self.0.epoch
    }

    pub(super) fn next(&self) -> Result<u64, StudioError> {
        // Only uniqueness is carried by this atomic; each owner's mutex/watch publishes facts.
        self.0
            .next
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |next| {
                next.checked_add(1)
            })
            .map_err(|_| {
                StudioError::new(
                    StudioErrorCode::Overloaded,
                    "Studio observation incarnation space is exhausted",
                    false,
                )
            })
    }
}
