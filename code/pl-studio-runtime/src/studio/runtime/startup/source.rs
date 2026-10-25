use pl_protocol::products::{identity::ProductReadOrigin, read::startup::*};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::sync::{Arc, Mutex};

const STAGE_CAPACITY: usize = 64;
struct ProgressState {
    stages: Vec<StartupStage>,
    terminal: Option<Result<StartupCloseReason, StudioError>>,
}
/// The existing bridge attempt coordinator owns this native source before runtime installation.
/// Its callbacks publish synchronously, so watch coalescing cannot erase an intermediate stage.
pub struct StartupProgressSource {
    attempt_id: u64,
    feed_epoch: String,
    state: Mutex<ProgressState>,
    updates: tokio::sync::watch::Sender<()>,
    stopped: tokio_util::sync::CancellationToken,
}
impl StartupProgressSource {
    pub fn new(attempt_id: u64) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            attempt_id,
            feed_epoch: crate::studio::new_id("startup-attempt"),
            state: Mutex::new(ProgressState {
                stages: vec![StartupStage::Preparing],
                terminal: None,
            }),
            updates,
            stopped: tokio_util::sync::CancellationToken::new(),
        })
    }
    pub fn attempt_id(&self) -> u64 {
        self.attempt_id
    }
    pub fn feed_epoch(&self) -> &str {
        &self.feed_epoch
    }
    /// Ready is published by finish_start only after the original installation/exit check.
    pub fn publish(&self, stage: crate::StudioStartupStage) {
        let stage = match stage {
            crate::StudioStartupStage::Preparing => StartupStage::Preparing,
            crate::StudioStartupStage::WaitingForSteps => StartupStage::WaitingForSteps,
            crate::StudioStartupStage::ClosingResources => StartupStage::ClosingResources,
            crate::StudioStartupStage::BackingUp => StartupStage::BackingUp,
            crate::StudioStartupStage::Resetting => StartupStage::Resetting,
            crate::StudioStartupStage::StartingServices => StartupStage::StartingServices,
            crate::StudioStartupStage::OpeningStorage => StartupStage::OpeningStorage,
            crate::StudioStartupStage::LoadingConfiguration => StartupStage::LoadingConfiguration,
            crate::StudioStartupStage::ReadingProjects => StartupStage::ReadingProjects,
            crate::StudioStartupStage::PreparingResources => StartupStage::PreparingResources,
            crate::StudioStartupStage::Ready | crate::StudioStartupStage::Failed => return,
        };
        self.push(stage);
    }
    fn push(&self, stage: StartupStage) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return;
        }
        if state.stages.len() == STAGE_CAPACITY {
            state.terminal = Some(Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Startup reliable stage queue is full",
                false,
            )));
        } else {
            state.stages.push(stage);
        }
        drop(state);
        self.updates.send_replace(());
    }
    pub fn complete(&self) {
        self.push(StartupStage::Ready);
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_none() {
            state.terminal = Some(Ok(StartupCloseReason::Completed));
        }
        drop(state);
        self.updates.send_replace(());
    }
    pub fn fail(&self, error: StudioError) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_none() {
            if state.stages.len() < STAGE_CAPACITY {
                state.stages.push(StartupStage::Failed);
            }
            state.terminal = Some(Err(error));
        }
        drop(state);
        self.updates.send_replace(());
    }
    pub fn replaced(&self) {
        self.stop(StartupCloseReason::AttemptReplaced);
    }
    pub fn runtime_stopped(&self) {
        self.stop(StartupCloseReason::RuntimeStopped);
    }
    fn stop(&self, reason: StartupCloseReason) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Exit/replacement wins over an unread Ready completion; no stale success is delivered.
        state.terminal = Some(Ok(reason));
        state.stages.clear();
        drop(state);
        self.stopped.cancel();
        self.updates.send_replace(());
    }
    pub(super) fn stop_token(&self) -> tokio_util::sync::CancellationToken {
        self.stopped.clone()
    }
    pub(super) fn close_reason(&self) -> StartupCloseReason {
        match &self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .terminal
        {
            Some(Ok(StartupCloseReason::AttemptReplaced)) => StartupCloseReason::AttemptReplaced,
            Some(Ok(StartupCloseReason::RuntimeStopped)) => StartupCloseReason::RuntimeStopped,
            _ => StartupCloseReason::Requested,
        }
    }
    pub fn open_startup_progress(
        self: &Arc<Self>,
        attempt_id: u64,
    ) -> Result<super::StudioStartupProgress, StudioError> {
        if self.attempt_id != attempt_id {
            return Err(StudioError::invalid_argument(
                "Unknown or expired startup attempt",
            ));
        }
        Ok(super::feed::StudioStartupProgress::new(
            self.clone(),
            self.updates.subscribe(),
        ))
    }
    /// Actual sends and attempt invalidation share this guard. A stale Ready cannot escape after
    /// stop/replacement won. Callback is synchronous, bounded and must not reenter the source.
    pub(super) fn with_next<T>(
        &self,
        index: usize,
        send: impl FnOnce(
            Option<StartupStage>,
            Option<Result<StartupCloseReason, StudioError>>,
        ) -> Result<T, StudioError>,
    ) -> Result<T, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        send(
            state.stages.get(index).copied(),
            if index >= state.stages.len() {
                state.terminal.clone()
            } else {
                None
            },
        )
    }
}

pub(super) struct StartupSnapshot {
    pub attempt_id: u64,
    pub reference: RuntimeStartupReadRef,
    pub value: crate::StudioRuntimeSnapshot,
}
struct ReadState {
    sealed: bool,
    current: Option<Arc<StartupSnapshot>>,
}
pub(in crate::studio) struct StartupSource {
    origin: ProductReadOrigin,
    state: Mutex<ReadState>,
}
impl StartupSource {
    pub(in crate::studio) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        Arc::new(Self {
            origin,
            state: Mutex::new(ReadState {
                sealed: false,
                current: None,
            }),
        })
    }
    pub(super) fn origin(&self) -> ProductReadOrigin {
        self.origin.clone()
    }
    pub(super) fn ready(
        &self,
        attempt_id: u64,
        value: crate::StudioRuntimeSnapshot,
    ) -> Result<RuntimeReady, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        if !value.state.is_ready() {
            return Err(StudioError::new(
                StudioErrorCode::Unavailable,
                "Runtime has not reached Ready",
                true,
            ));
        }
        if let Some(current) = &state.current {
            if current.attempt_id != attempt_id {
                return Err(StudioError::invalid_argument(
                    "Runtime belongs to another startup attempt",
                ));
            }
            return Ok(RuntimeReady {
                revision: current.value.revision,
                ready_at: current.value.state.updated_at(),
                details: current.reference,
            });
        }
        let reference = RuntimeStartupReadRef {
            entry: 1,
            revision: value.revision,
        };
        let ready = RuntimeReady {
            revision: value.revision,
            ready_at: value.state.updated_at(),
            details: reference,
        };
        state.current = Some(Arc::new(StartupSnapshot {
            attempt_id,
            reference,
            value,
        }));
        Ok(ready)
    }
    pub(super) fn pin(
        &self,
        reference: RuntimeStartupReadRef,
    ) -> Result<Arc<StartupSnapshot>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        state
            .current
            .as_ref()
            .filter(|value| value.reference == reference)
            .cloned()
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Superseded,
                    "The original startup read reference is not available",
                    false,
                )
            })
    }
    pub(in crate::studio) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
    }
    pub(in crate::studio) fn finish_close(&self) {
        self.seal();
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .current
            .take();
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Startup reads are closing",
        false,
    )
}
