//! Bounded command submission and independent snapshot/interrupt handles.
use super::*;
mod commands;
mod inputs;
mod operations;
pub(super) use commands::Command;

/// A bounded command handle; mutable Thread state is owned exclusively by its actor.
#[derive(Debug, Clone)]
pub struct ThreadHandle {
    pub(in crate::thread) runtime_epoch: current::RuntimeEpoch,
    pub(in crate::thread) final_current:
        watch::Receiver<Option<Result<current::ThreadCurrent, Arc<current::CurrentError>>>>,
    pub(in crate::thread) current_dirty: watch::Receiver<u64>,
    thread_id: String,
    _lifetime: Arc<HandleLifetime>,
    commands: mpsc::Sender<Command>,
    pub(in crate::thread) mailbox: mpsc::Sender<super::mailbox::MailboxCommand>,
    interrupt: cancellation::InterruptHandle,
    snapshots: watch::Receiver<ThreadSnapshot>,
    effect_window: Arc<EffectWindow>,
}

#[derive(Debug)]
struct HandleLifetime(cancellation::InterruptHandle);
impl Drop for HandleLifetime {
    fn drop(&mut self) {
        self.0.begin_close();
    }
}
