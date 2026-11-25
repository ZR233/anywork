//! Independent immutable History handoff and the existing reliable-output resource boundary.
//! The sink never receives a checkpoint and cannot acknowledge a Current save.

use super::cold::{ColdStoreError, DurableToolTask, StorageIdleStatus, StoragePressure};
use super::{HistoryExport, ThreadEffectBatch, UsageSummary};
use futures::future::BoxFuture;
use std::{fmt, future::Future, sync::Arc};

/// Host-owned reliable archive admission. Resource operations are synchronous and share the
/// producer's original output budget; asynchronous IO belongs to the host's writer.
pub trait HistorySink: Send + Sync + fmt::Debug + 'static {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &ThreadEffectBatch);
    fn reserve_observed_item(
        &self,
        thread_id: &str,
        attempt_id: &str,
        item_id: &str,
    ) -> Result<(), ColdStoreError>;
    fn reserve_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        max_bytes: u64,
    ) -> Result<u64, ColdStoreError>;
    fn charge_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        accepted_bytes: u64,
    ) -> Result<(), ColdStoreError>;
    fn release_operation_output(&self, thread_id: &str, operation_id: &str);
    fn pressure(&self, thread_id: &str) -> StoragePressure;
    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus;
    fn subscribe_pressure(&self, thread_id: &str) -> Option<tokio::sync::watch::Receiver<()>>;
    fn admit(&self, thread_id: &str, export: Arc<HistoryExport>) -> Result<(), ColdStoreError>;
    /// Reads only the committed original of an already retired settlement identity.
    fn read_saved_model_settlement(
        &self,
        thread_id: &str,
        settlement: &crate::model::ModelSubAttemptSettlement,
    ) -> impl Future<
        Output = Result<Option<crate::model::ModelSubAttemptSettlement>, ColdStoreError>,
    > + Send;
    /// Waits for the writer to commit the ordered effect containing this settlement.
    fn confirm_model_settlement(
        &self,
        thread_id: &str,
        effect_sequence: u64,
    ) -> impl Future<Output = Result<(), ColdStoreError>> + Send;
    fn read_tool_task(
        &self,
        thread_id: &str,
        task_id: &str,
    ) -> impl Future<Output = Result<Option<DurableToolTask>, ColdStoreError>> + Send;
}

#[derive(Debug, Clone)]
pub struct HistorySinkHandle(super::cold::StorageHandle);

impl HistorySinkHandle {
    pub fn new(sink: impl HistorySink) -> Self {
        Self(super::cold::StorageHandle(Arc::new(ErasedHistorySink(
            sink,
        ))))
    }

    pub(super) fn into_storage(self) -> super::cold::StorageHandle {
        self.0
    }
}

#[derive(Debug)]
struct ErasedHistorySink<T>(T);

fn checkpoint_port_error() -> ColdStoreError {
    ColdStoreError {
        source: Box::new(std::io::Error::other(
            "independent History has no checkpoint or Current durability fence",
        )),
    }
}

impl<T: HistorySink> super::cold::ErasedStorage for ErasedHistorySink<T> {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &ThreadEffectBatch) {
        self.0.fold_usage(summary, effect);
    }
    fn reserve_observed_item(
        &self,
        thread: &str,
        attempt: &str,
        item: &str,
    ) -> Result<(), ColdStoreError> {
        self.0.reserve_observed_item(thread, attempt, item)
    }
    fn reserve_operation_output(
        &self,
        thread: &str,
        operation: &str,
        max: u64,
    ) -> Result<u64, ColdStoreError> {
        self.0.reserve_operation_output(thread, operation, max)
    }
    fn charge_operation_output(
        &self,
        thread: &str,
        operation: &str,
        bytes: u64,
    ) -> Result<(), ColdStoreError> {
        self.0.charge_operation_output(thread, operation, bytes)
    }
    fn release_operation_output(&self, thread: &str, operation: &str) {
        self.0.release_operation_output(thread, operation);
    }
    fn pressure(&self, thread: &str) -> StoragePressure {
        self.0.pressure(thread)
    }
    fn idle_status(&self, thread: &str) -> StorageIdleStatus {
        self.0.idle_status(thread)
    }
    fn subscribe_pressure(&self, thread: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        self.0.subscribe_pressure(thread)
    }
    fn is_history(&self) -> bool {
        true
    }
    fn admit(&self, _: &str, _: super::cold::ThreadWrite) -> Result<(), ColdStoreError> {
        Err(checkpoint_port_error())
    }
    fn admit_history(
        &self,
        thread: &str,
        export: Arc<HistoryExport>,
    ) -> Result<(), ColdStoreError> {
        self.0.admit(thread, export)
    }
    fn flush<'a>(&'a self, _: &'a str, _: u64) -> BoxFuture<'a, Result<(), ColdStoreError>> {
        Box::pin(async { Err(checkpoint_port_error()) })
    }
    fn read_saved_model_settlement<'a>(
        &'a self,
        thread: &'a str,
        settlement: &'a crate::model::ModelSubAttemptSettlement,
    ) -> BoxFuture<'a, Result<Option<crate::model::ModelSubAttemptSettlement>, ColdStoreError>>
    {
        Box::pin(self.0.read_saved_model_settlement(thread, settlement))
    }
    fn confirm_model_settlement<'a>(
        &'a self,
        thread: &'a str,
        sequence: u64,
    ) -> BoxFuture<'a, Result<(), ColdStoreError>> {
        Box::pin(self.0.confirm_model_settlement(thread, sequence))
    }
    fn read_tool_task<'a>(
        &'a self,
        thread: &'a str,
        task: &'a str,
    ) -> BoxFuture<'a, Result<Option<DurableToolTask>, ColdStoreError>> {
        Box::pin(self.0.read_tool_task(thread, task))
    }
}
