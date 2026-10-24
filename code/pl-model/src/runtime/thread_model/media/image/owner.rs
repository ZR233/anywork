//! One retained image worker per preparation lifetime, including abandoned callers.
use super::{NativeMedia, Projection, cancelled, io::ImageCancellation, project};
use crate::model::ModelInfo;
use pl_core::model::{ModelError, ModelFailureKind};
use std::sync::Arc;
use tokio::{sync::Mutex, task::JoinHandle};
use tokio_util::sync::CancellationToken;

type ImageWorker = JoinHandle<Result<Option<NativeMedia>, ModelError>>;

#[derive(Default)]
struct State {
    cancellation: CancellationToken,
    worker: Mutex<Option<ImageWorker>>,
}

/// Owns request-time image metadata, validation and derivation work for one lifetime.
///
/// Clones share admission and retained joins. Store a host clone before starting a cancellable
/// standalone estimate/compaction. ThreadModel sessions instead create private owners, so closing
/// one session cannot seal its factory or another session. Drop is not an asynchronous close.
#[derive(Clone, Default)]
pub struct ModelPreparationOwner(Arc<State>);

impl std::fmt::Debug for ModelPreparationOwner {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ModelPreparationOwner")
            .finish_non_exhaustive()
    }
}
impl ModelPreparationOwner {
    /// Seals admission, cooperatively cancels work and joins its real blocking task.
    /// Cancelling this wait preserves the same handle for another close.
    ///
    /// # Errors
    /// Reports retained worker/resource failures; cancellation requested by close is expected.
    pub async fn close(&self) -> Result<(), ModelError> {
        self.0.cancellation.cancel();
        let mut worker = self.0.worker.lock().await;
        drain(&mut worker).await
    }

    pub(super) async fn run(
        &self,
        model: ModelInfo,
        media_type: String,
        bytes: Arc<[u8]>,
        projection: Projection,
        request: CancellationToken,
    ) -> Result<Option<NativeMedia>, ModelError> {
        let mut worker = tokio::select! {
            biased;
            () = self.0.cancellation.cancelled() => return Err(cancelled()),
            () = request.cancelled() => return Err(cancelled()),
            worker = self.0.worker.lock() => worker,
        };
        drain(&mut worker).await?;
        if self.0.cancellation.is_cancelled() || request.is_cancelled() {
            return Err(cancelled());
        }
        let cancellation = self.0.cancellation.child_token();
        let _cancel_on_drop = cancellation.clone().drop_guard();
        let control = ImageCancellation {
            owner: cancellation,
            request: request.clone(),
        };
        *worker = Some(tokio::task::spawn_blocking(move || {
            let result = project(&model, &media_type, bytes, projection, &control);
            control.check()?;
            result
        }));
        let Some(task) = worker.as_mut() else {
            return Err(super::invalid("image worker was not registered"));
        };
        let result = tokio::select! {
            biased;
            () = self.0.cancellation.cancelled() => return Err(cancelled()),
            () = request.cancelled() => return Err(cancelled()),
            result = task => result,
        };
        *worker = None;
        if self.0.cancellation.is_cancelled() || request.is_cancelled() {
            return Err(cancelled());
        }
        result.map_err(|error| super::failure(ModelFailureKind::Unavailable, error))?
    }
}

async fn drain(worker: &mut Option<ImageWorker>) -> Result<(), ModelError> {
    let Some(task) = worker.as_mut() else {
        return Ok(());
    };
    let result = task.await;
    *worker = None;
    match result.map_err(|error| super::failure(ModelFailureKind::Unavailable, error))? {
        Ok(_) => Ok(()),
        Err(error) if error.kind == ModelFailureKind::Cancelled => Ok(()),
        Err(error) => Err(error),
    }
}
