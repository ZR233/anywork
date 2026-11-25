//! One invocation's capture endpoint. It owns no network future and never restarts one.
use std::future::Future;
use std::sync::{Arc, Mutex};

use pl_core::{
    context::OpaquePayload,
    model::{CurrentCaptureHandle, CurrentCaptureReceiver, ModelError, ModelFailureKind},
};

use crate::completion::{ModelStreamCurrent, ModelStreamCurrentState};
use crate::stream::StreamCompletionAccumulator;

#[derive(Debug, Clone)]
pub(crate) struct CurrentInvocation(Arc<Mutex<Exchange>>);

#[derive(Debug)]
struct Exchange {
    producer: Option<CurrentProducer>,
    final_current: Option<OpaquePayload>,
}

impl CurrentInvocation {
    pub(crate) fn channel(attempt_id: &str) -> (CurrentCaptureHandle, Self) {
        let (handle, receiver) = CurrentCaptureHandle::channel();
        let empty = StreamCompletionAccumulator::new(None).current(attempt_id, 0);
        (
            handle,
            Self(Arc::new(Mutex::new(Exchange {
                producer: Some(CurrentProducer {
                    receiver,
                    last: empty,
                    previous: Vec::new(),
                    started: false,
                    closed: false,
                }),
                final_current: None,
            }))),
        )
    }

    pub(crate) fn take_producer(&self) -> Option<CurrentProducer> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .producer
            .take()
    }

    pub(crate) fn handoff(&self, payload: OpaquePayload) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .final_current = Some(payload);
    }

    pub(crate) fn take_final(&self) -> Option<OpaquePayload> {
        let mut exchange = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        exchange.final_current.take().or_else(|| {
            exchange.producer.take().and_then(|mut producer| {
                producer
                    .finish(Some("invocation failed before dispatch".into()))
                    .ok()
            })
        })
    }
}

#[derive(Debug)]
pub(crate) struct CurrentProducer {
    receiver: CurrentCaptureReceiver,
    last: ModelStreamCurrent,
    previous: Vec<ModelStreamCurrent>,
    started: bool,
    closed: bool,
}

impl CurrentProducer {
    pub(crate) fn begin_generation(&mut self, generation: u32) {
        if self.started {
            let empty =
                StreamCompletionAccumulator::new(None).current(&self.last.attempt_id, generation);
            self.previous.push(std::mem::replace(&mut self.last, empty));
        } else {
            self.last.generation = generation;
            self.started = true;
        }
        self.mark_dirty();
    }

    pub(crate) fn mark_dirty(&self) {
        self.receiver.mark_dirty();
    }

    pub(crate) fn freeze(&mut self, accumulator: &StreamCompletionAccumulator) {
        self.last = accumulator.current(&self.last.attempt_id, self.last.generation);
        self.mark_dirty();
    }

    pub(crate) fn settle(&mut self, settlement: OpaquePayload) {
        self.last.settlement = Some(settlement);
        self.mark_dirty();
    }

    pub(crate) fn fail_snapshot(&mut self, message: String) {
        self.last.state = ModelStreamCurrentState::Failed { message };
        self.mark_dirty();
    }

    fn snapshot(&self, accumulator: Option<&StreamCompletionAccumulator>) -> ModelStreamCurrent {
        let mut current = accumulator.map_or_else(
            || self.last.clone(),
            |acc| acc.current(&self.last.attempt_id, self.last.generation),
        );
        current.previous_generations = self.previous.clone();
        current
    }

    pub(crate) fn finish(&mut self, failure: Option<String>) -> Result<OpaquePayload, ModelError> {
        if matches!(self.last.state, ModelStreamCurrentState::Open) {
            self.fail_snapshot(
                failure.unwrap_or_else(|| "producer exited without a terminal response".into()),
            );
        }
        self.snapshot(None)
            .encode()
            .map_err(|error| super::thread_model::failure(ModelFailureKind::InvalidResponse, error))
    }

    /// The operation is pinned once. A capture cannot reset its timeout or drop a reliable member
    /// admission future. Only capture requests clone/encode a view; token handling only marks dirty.
    pub(crate) async fn wait<F: Future>(
        &mut self,
        operation: F,
        accumulator: Option<&StreamCompletionAccumulator>,
    ) -> F::Output {
        tokio::pin!(operation);
        loop {
            if self.closed {
                return operation.await;
            }
            tokio::select! {
                result = &mut operation => return result,
                request = self.receiver.recv() => {
                    let Some(request) = request else { self.closed = true; continue; };
                    if request.cancellation.is_cancelled() || request.reply.is_closed() { continue; }
                    // Epoch acceptance belongs to Core, which owns this per-call handle and checks
                    // epoch/attempt/phase again after capture. Model owns only the supplied attempt.
                    let result = if request.attempt_id != self.last.attempt_id {
                        Err(super::thread_model::failure(ModelFailureKind::InvalidResponse,
                            std::io::Error::other("capture targets another model attempt")))
                    } else {
                        self.snapshot(accumulator).encode().map_err(|error|
                            super::thread_model::failure(ModelFailureKind::InvalidResponse, error))
                    };
                    if !request.cancellation.is_cancelled() && !request.reply.is_closed() {
                        let _ = request.reply.send(result);
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_core::thread::current::RuntimeEpoch;
    use std::{
        sync::atomic::{AtomicUsize, Ordering},
        time::Duration,
    };
    use tokio_util::sync::CancellationToken;

    #[tokio::test(start_paused = true)]
    async fn captures_do_not_restart_a_member_wait_or_its_idle_deadline() {
        struct Guard(Arc<AtomicUsize>);
        impl Drop for Guard {
            fn drop(&mut self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let (handle, link) = CurrentInvocation::channel("attempt");
        let mut producer = link.take_producer().unwrap();
        let drops = Arc::new(AtomicUsize::new(0));
        let guard = Guard(drops.clone());
        let deadline = tokio::time::Instant::now() + Duration::from_secs(1);
        let task = tokio::spawn(async move {
            let wait = async move {
                let _guard = guard;
                std::future::pending::<()>().await
            };
            producer
                .wait(tokio::time::timeout_at(deadline, wait), None)
                .await
        });
        tokio::time::advance(Duration::from_millis(400)).await;
        let epoch = RuntimeEpoch::new();
        handle
            .capture(epoch, "attempt", CancellationToken::new())
            .await
            .unwrap();
        assert_eq!(drops.load(Ordering::SeqCst), 0);
        tokio::time::advance(Duration::from_millis(400)).await;
        handle
            .capture(epoch, "attempt", CancellationToken::new())
            .await
            .unwrap();
        assert_eq!(drops.load(Ordering::SeqCst), 0);
        tokio::time::advance(Duration::from_millis(200)).await;
        assert!(
            task.await.unwrap().is_err(),
            "captures cannot extend the original one-second operation deadline"
        );
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }
}
