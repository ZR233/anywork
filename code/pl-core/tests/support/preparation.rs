use pl_core::thread::{
    ThreadHandle,
    context_preparation::{
        ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
    },
};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use tokio::sync::Notify;

/// Holds the first request before it is admitted and releases it cooperatively on stop.
#[derive(Clone, Debug, Default)]
pub struct HoldPreparation {
    started: Arc<Notify>,
    used: Arc<AtomicBool>,
}

impl HoldPreparation {
    pub async fn install(thread: &ThreadHandle) -> Self {
        let hold = Self::default();
        thread
            .set_context_preparation(Some(ContextPreparer::new(hold.clone())))
            .await
            .unwrap();
        hold
    }

    pub async fn entered(&self) {
        tokio::time::timeout(std::time::Duration::from_secs(5), self.started.notified())
            .await
            .expect("context preparation starts");
    }
}

impl ContextPreparationHook for HoldPreparation {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        if !self.used.swap(true, Ordering::Relaxed) {
            self.started.notify_one();
            request.model.cancellation.cancelled().await;
        }
        ContextPreparation::Unchanged
    }
}
