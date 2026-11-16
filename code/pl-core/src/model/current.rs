//! A revocable, single-slot request for a producer's complete logical stream state.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::{Notify, oneshot, watch};
use tokio_util::sync::CancellationToken;

use super::{ModelError, ModelFailureKind, ModelStepOutput};
use crate::context::OpaquePayload;
use crate::thread::current::RuntimeEpoch;

/// Final state transferred through the existing execution future, before its accumulator dies.
#[derive(Debug)]
pub struct ModelCallExit {
    pub result: Result<ModelStepOutput, ModelError>,
    pub current: Option<OpaquePayload>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum CurrentCaptureError {
    #[error("current capture cancelled")]
    Cancelled,
    #[error("current capture exceeded its one-second deadline")]
    TimedOut,
    #[error("current capture producer closed")]
    Closed,
    #[error("another current capture already owns the slot")]
    Busy,
}

impl From<CurrentCaptureError> for ModelError {
    fn from(error: CurrentCaptureError) -> Self {
        Self {
            kind: if error == CurrentCaptureError::Cancelled {
                ModelFailureKind::Cancelled
            } else {
                ModelFailureKind::Unavailable
            },
            details: None,
            usage: Box::default(),
            source: Some(Box::new(error)),
        }
    }
}

/// A producer responds at a normalized-event boundary, never by restarting its network future.
#[derive(Debug)]
pub struct ModelCurrentCaptureRequest {
    pub runtime_epoch: RuntimeEpoch,
    pub attempt_id: String,
    pub cancellation: CancellationToken,
    pub reply: oneshot::Sender<Result<OpaquePayload, ModelError>>,
}

#[derive(Debug, Default)]
struct Slot {
    generation: u64,
    occupied: bool,
    closed: bool,
    request: Option<ModelCurrentCaptureRequest>,
}

#[derive(Debug, Default)]
struct Shared {
    slot: Mutex<Slot>,
    ready: Notify,
    closed: CancellationToken,
    dirty: Mutex<Option<watch::Sender<u64>>>,
}

impl Shared {
    fn slot(&self) -> std::sync::MutexGuard<'_, Slot> {
        self.slot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

/// Cloneable requester. Dropping a capture future synchronously revokes its slot and reply.
#[derive(Debug, Clone)]
pub struct CurrentCaptureHandle(Arc<Shared>);

/// Single producer-side endpoint. Dropping it rejects pending and future requests.
#[derive(Debug)]
pub struct CurrentCaptureReceiver(Arc<Shared>);

struct Lease {
    shared: Arc<Shared>,
    generation: u64,
    cancellation: CancellationToken,
}

impl Drop for Lease {
    fn drop(&mut self) {
        self.cancellation.cancel();
        let mut slot = self.shared.slot();
        if slot.generation == self.generation {
            slot.request = None;
            slot.occupied = false;
        }
    }
}

impl CurrentCaptureHandle {
    pub fn channel() -> (Self, CurrentCaptureReceiver) {
        let shared = Arc::new(Shared::default());
        (Self(shared.clone()), CurrentCaptureReceiver(shared))
    }

    /// Binds this producer to the physical owner's coalescing dirty signal before dispatch.
    pub(crate) fn bind_dirty(&self, dirty: watch::Sender<u64>) {
        *self
            .0
            .dirty
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(dirty);
    }

    pub(crate) fn same_endpoint(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
    }

    /// Captures within one second from this request, including producer wait time.
    /// A concurrent request is refused rather than queued. No business lock spans the wait.
    pub async fn capture(
        &self,
        epoch: RuntimeEpoch,
        attempt_id: &str,
        cancellation: CancellationToken,
    ) -> Result<OpaquePayload, ModelError> {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
        if cancellation.is_cancelled() {
            return Err(CurrentCaptureError::Cancelled.into());
        }
        let token = cancellation.child_token();
        let (reply, response) = oneshot::channel();
        let _lease = {
            let mut slot = self.0.slot();
            if slot.closed {
                return Err(CurrentCaptureError::Closed.into());
            }
            if slot.occupied {
                return Err(CurrentCaptureError::Busy.into());
            }
            slot.generation = slot.generation.wrapping_add(1);
            slot.occupied = true;
            slot.request = Some(ModelCurrentCaptureRequest {
                runtime_epoch: epoch,
                attempt_id: attempt_id.into(),
                cancellation: token.clone(),
                reply,
            });
            Lease {
                shared: self.0.clone(),
                generation: slot.generation,
                cancellation: token,
            }
        };
        self.0.ready.notify_one();
        tokio::select! {
            biased;
            () = cancellation.cancelled() => Err(CurrentCaptureError::Cancelled.into()),
            () = self.0.closed.cancelled() => Err(CurrentCaptureError::Closed.into()),
            () = tokio::time::sleep_until(deadline) => Err(CurrentCaptureError::TimedOut.into()),
            result = response => result.unwrap_or_else(|_| Err(CurrentCaptureError::Closed.into())),
        }
    }
}

impl CurrentCaptureReceiver {
    /// Marks a normalized accumulator change without serializing or copying its contents.
    pub fn mark_dirty(&self) {
        let dirty = self
            .0
            .dirty
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(dirty) = dirty {
            dirty.send_modify(|revision| {
                *revision = revision
                    .checked_add(1)
                    .expect("current dirty revision exhausted")
            });
        }
    }

    /// Waits independently of network readiness. The caller must select this with its pinned
    /// network operation and cancellation, including during connection and first-byte waits.
    pub async fn recv(&mut self) -> Option<ModelCurrentCaptureRequest> {
        loop {
            let notified = self.0.ready.notified();
            {
                let mut slot = self.0.slot();
                if slot.closed {
                    return None;
                }
                if let Some(request) = slot.request.take() {
                    if !request.cancellation.is_cancelled() && !request.reply.is_closed() {
                        return Some(request);
                    }
                    slot.occupied = false;
                }
            }
            notified.await;
        }
    }
}

impl Drop for CurrentCaptureReceiver {
    fn drop(&mut self) {
        let mut slot = self.0.slot();
        slot.closed = true;
        self.0.closed.cancel();
        if let Some(request) = slot.request.take() {
            request.cancellation.cancel();
        }
        self.0.ready.notify_waiters();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn is_capture_error(error: &ModelError, expected: CurrentCaptureError) -> bool {
        error
            .source
            .as_ref()
            .and_then(|source| source.downcast_ref::<CurrentCaptureError>())
            == Some(&expected)
    }

    #[tokio::test(start_paused = true)]
    async fn deadline_is_one_second_and_late_reply_cannot_occupy_replacement_slot() {
        let (handle, mut producer) = CurrentCaptureHandle::channel();
        let epoch = RuntimeEpoch::new();
        let task = tokio::spawn({
            let handle = handle.clone();
            async move { handle.capture(epoch, "old", CancellationToken::new()).await }
        });
        let old = producer.recv().await.unwrap();
        assert_eq!(old.runtime_epoch, epoch);
        assert_eq!(old.attempt_id, "old");
        assert!(is_capture_error(
            &handle
                .capture(epoch, "busy", CancellationToken::new())
                .await
                .unwrap_err(),
            CurrentCaptureError::Busy
        ));
        tokio::time::advance(Duration::from_millis(999)).await;
        assert!(!task.is_finished());
        tokio::time::advance(Duration::from_millis(1)).await;
        assert!(is_capture_error(
            &task.await.unwrap().unwrap_err(),
            CurrentCaptureError::TimedOut
        ));
        assert!(old.cancellation.is_cancelled());
        assert!(old.reply.send(Ok(OpaquePayload::text("late"))).is_err());
        let next = tokio::spawn({
            let handle = handle.clone();
            async move {
                handle
                    .capture(epoch, "next", CancellationToken::new())
                    .await
            }
        });
        let request = producer.recv().await.unwrap();
        assert_eq!(request.attempt_id, "next");
        request
            .reply
            .send(Ok(OpaquePayload::text("complete")))
            .unwrap();
        assert_eq!(next.await.unwrap().unwrap().content(), "complete");
    }

    #[tokio::test]
    async fn cancellation_and_drop_revoke_unreceived_requests_not_just_reply_waiters() {
        let (handle, mut producer) = CurrentCaptureHandle::channel();
        let epoch = RuntimeEpoch::new();
        let cancellation = CancellationToken::new();
        {
            let capture = handle.capture(epoch, "cancelled", cancellation.clone());
            tokio::pin!(capture);
            assert!(futures::poll!(&mut capture).is_pending());
            cancellation.cancel();
            assert!(is_capture_error(
                &capture.await.unwrap_err(),
                CurrentCaptureError::Cancelled
            ));
        }
        {
            let capture = handle.capture(epoch, "dropped", CancellationToken::new());
            tokio::pin!(capture);
            assert!(futures::poll!(&mut capture).is_pending());
        }
        let capture = handle.capture(epoch, "replacement", CancellationToken::new());
        tokio::pin!(capture);
        assert!(futures::poll!(&mut capture).is_pending());
        let request = producer.recv().await.unwrap();
        assert_eq!(request.attempt_id, "replacement");
        request.reply.send(Ok(OpaquePayload::text("new"))).unwrap();
        assert_eq!(capture.await.unwrap().content(), "new");
    }

    #[tokio::test]
    async fn producer_close_rejects_in_progress_reply_and_future_requests() {
        let (handle, mut producer) = CurrentCaptureHandle::channel();
        let epoch = RuntimeEpoch::new();
        let task = tokio::spawn({
            let handle = handle.clone();
            async move {
                handle
                    .capture(epoch, "active", CancellationToken::new())
                    .await
            }
        });
        let request = producer.recv().await.unwrap();
        drop(producer);
        assert!(is_capture_error(
            &task.await.unwrap().unwrap_err(),
            CurrentCaptureError::Closed
        ));
        assert!(request.cancellation.is_cancelled());
        assert!(
            request
                .reply
                .send(Ok(OpaquePayload::text("too late")))
                .is_err()
        );
        assert!(is_capture_error(
            &handle
                .capture(epoch, "closed", CancellationToken::new())
                .await
                .unwrap_err(),
            CurrentCaptureError::Closed
        ));
    }
}
