//! Single-flight latest-state pull shared by directory and account observations.
//!
//! Registration happens before the first read. The signal is marked seen before the owner
//! read, so a mutation during that read stays pending. Closing waits for the in-flight read,
//! then drops the original registration.

use std::future::Future;

use anyhow::Result;
use tokio::sync::{Mutex, watch};
use tokio_util::sync::CancellationToken;

use crate::StudioError;
use crate::studio::product_event_bus::{ProductTopicSignal, ThreadMetadataSignal};

pub(in crate::studio::runtime) trait PullSignal: Send {
    fn changed(&mut self) -> impl Future<Output = Result<(), watch::error::RecvError>> + Send;
    fn mark_current(&mut self);
}

impl PullSignal for ProductTopicSignal {
    fn changed(&mut self) -> impl Future<Output = Result<(), watch::error::RecvError>> + Send {
        ProductTopicSignal::changed(self)
    }

    fn mark_current(&mut self) {
        ProductTopicSignal::mark_current(self);
    }
}

impl PullSignal for ThreadMetadataSignal {
    fn changed(&mut self) -> impl Future<Output = Result<(), watch::error::RecvError>> + Send {
        self.receiver().changed()
    }

    fn mark_current(&mut self) {
        self.receiver().borrow_and_update();
    }
}

pub(in crate::studio::runtime) enum PullStep<T> {
    Deliver(T),
    WaitAgain,
}

pub(in crate::studio::runtime) struct PullObservation<S, M> {
    cancellation: CancellationToken,
    gate: Mutex<PullGate<S, M>>,
}

pub(in crate::studio::runtime) struct PullGate<S, M> {
    pub(in crate::studio::runtime) signal: Option<S>,
    initial: bool,
    pub(in crate::studio::runtime) last: M,
}

impl<S, M> PullObservation<S, M> {
    pub(in crate::studio::runtime) fn open(
        signal: S,
        last: M,
        cancellation: CancellationToken,
    ) -> Self {
        Self {
            cancellation,
            gate: Mutex::new(PullGate {
                signal: Some(signal),
                initial: true,
                last,
            }),
        }
    }

    pub(in crate::studio::runtime) fn request_close(&self) {
        self.cancellation.cancel();
    }

    /// Waits for the admitted read, then drops the registration. `forget` releases retained frames.
    pub(in crate::studio::runtime) async fn release(
        &self,
        forget: impl FnOnce(&mut M),
    ) -> Result<()> {
        self.request_close();
        let mut gate = self.gate.lock().await;
        gate.signal.take();
        forget(&mut gate.last);
        Ok(())
    }

    pub(in crate::studio::runtime) async fn close(&self) -> Result<()> {
        self.release(|_| {}).await
    }

    #[cfg(test)]
    pub(in crate::studio::runtime) async fn lock(
        &self,
    ) -> tokio::sync::MutexGuard<'_, PullGate<S, M>> {
        self.gate.lock().await
    }
}

impl<S: PullSignal, M: Send> PullObservation<S, M> {
    pub(in crate::studio::runtime) async fn next<T>(
        &self,
        busy: StudioError,
        mut step: impl FnMut(&mut M) -> Result<PullStep<T>>,
    ) -> Result<Option<T>> {
        if self.cancellation.is_cancelled() {
            return Ok(None);
        }
        let mut gate = self.gate.try_lock().map_err(|_| busy)?;
        loop {
            if !gate.ready(&self.cancellation).await {
                return Ok(None);
            }
            match step(&mut gate.last)? {
                PullStep::Deliver(frame) => return Ok(Some(frame)),
                PullStep::WaitAgain => continue,
            }
        }
    }
}

impl<S: PullSignal, M> PullGate<S, M> {
    pub(in crate::studio::runtime) async fn ready(
        &mut self,
        cancellation: &CancellationToken,
    ) -> bool {
        if cancellation.is_cancelled() {
            return false;
        }
        if !self.initial {
            let Some(signal) = self.signal.as_mut() else {
                return false;
            };
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => return false,
                changed = signal.changed() => if changed.is_err() { return false; },
            }
        }
        self.initial = false;
        if let Some(signal) = self.signal.as_mut() {
            // Consume before the owner read so a mutation during that read stays pending.
            signal.mark_current();
        }
        true
    }
}
