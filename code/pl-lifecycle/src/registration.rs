use std::panic::{AssertUnwindSafe, catch_unwind};

use crate::RegistrationError;

/// An exclusive guard for a synchronous cleanup callback.
pub struct Registration {
    release: Option<Box<dyn FnOnce() + Send + 'static>>,
}

impl Registration {
    pub(crate) fn new(release: impl FnOnce() + Send + 'static) -> Self {
        Self {
            release: Some(Box::new(release)),
        }
    }
}

impl Drop for Registration {
    fn drop(&mut self) {
        if let Some(release) = self.release.take() {
            // Cleanup panics are caught and recorded by the scope itself.
            release();
        }
    }
}

pub(crate) fn reject(cleanup: Box<dyn FnOnce() + Send>) -> Result<Registration, RegistrationError> {
    match catch_unwind(AssertUnwindSafe(cleanup)) {
        Ok(()) => Err(RegistrationError::ScopeClosed),
        Err(_) => Err(RegistrationError::RejectedCleanupPanicked),
    }
}
