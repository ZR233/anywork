//! Bounded priority command submission and independent snapshot/event/interrupt handles.
use super::*;
use tokio::sync::broadcast;

mod commands;
mod inputs;
mod operations;
pub(super) use commands::{LoopEvent, UserCommand};

/// A bounded command handle; mutable Thread state is owned exclusively by its actor.
#[derive(Debug, Clone)]
pub struct ThreadHandle {
    pub(in crate::thread) runtime_epoch: current::RuntimeEpoch,
    pub(in crate::thread) final_current:
        watch::Receiver<Option<Result<current::ThreadCurrent, Arc<current::CurrentError>>>>,
    pub(in crate::thread) current_dirty: watch::Receiver<u64>,
    _lifetime: Arc<HandleLifetime>,
    pub(in crate::thread) user_commands: mpsc::Sender<UserCommand>,
    pub(in crate::thread) events: mpsc::Sender<LoopEvent>,
    pub(in crate::thread) core_events: broadcast::Sender<super::events::CoreEvent>,
    interrupt: cancellation::InterruptHandle,
    snapshots: watch::Receiver<super::subscription::OwnerPublication>,
    authorization_dirty: Arc<std::sync::atomic::AtomicBool>,
    effect_window: Arc<EffectWindow>,
}

#[derive(Debug)]
struct HandleLifetime(cancellation::InterruptHandle);
impl Drop for HandleLifetime {
    fn drop(&mut self) {
        self.0.begin_close();
    }
}
