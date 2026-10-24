//! One retained blocking inspection per draft owner, including abandoned callers.
use anyhow::{Context, Result};
use tokio::{sync::Mutex, task::JoinHandle};
use tokio_util::sync::CancellationToken;

use super::normalize::{InspectionCancelled, NormalizedSource, normalize_loaded_source};

#[derive(Default)]
pub(super) struct InspectionOwner {
    cancellation: CancellationToken,
    // Never take the handle before awaiting: caller cancellation releases the mutex,
    // not this owner's join obligation. The next inspection/close drains it first.
    worker: Mutex<Option<JoinHandle<Result<NormalizedSource>>>>,
}

impl InspectionOwner {
    pub(super) async fn inspect(&self, bytes: Vec<u8>) -> Result<NormalizedSource> {
        let mut worker = self.worker.lock().await;
        drain(&mut worker).await?;
        if self.cancellation.is_cancelled() {
            return Err(InspectionCancelled.into());
        }
        let cancellation = self.cancellation.child_token();
        let _cancel_on_drop = cancellation.clone().drop_guard();
        *worker = Some(tokio::task::spawn_blocking(move || {
            normalize_loaded_source(bytes, cancellation)
        }));
        let result = match worker.as_mut() {
            Some(task) => task.await,
            None => {
                return Err(anyhow::anyhow!(
                    "attachment inspection worker was not registered"
                ));
            }
        };
        *worker = None;
        let inspected = result.context("attachment inspection worker failed")??;
        if self.cancellation.is_cancelled() {
            return Err(InspectionCancelled.into());
        }
        Ok(inspected)
    }

    pub(super) fn signal_close(&self) {
        self.cancellation.cancel();
    }

    pub(super) fn is_closed(&self) -> bool {
        self.cancellation.is_cancelled()
    }

    pub(super) async fn close(&self) -> Result<()> {
        self.signal_close();
        let mut worker = self.worker.lock().await;
        drain(&mut worker).await
    }
}

async fn drain(worker: &mut Option<JoinHandle<Result<NormalizedSource>>>) -> Result<()> {
    if let Some(task) = worker.as_mut() {
        let joined = task.await;
        *worker = None;
        match joined.context("retained attachment inspection worker failed")? {
            Ok(_) => {}
            Err(error) if error.is::<InspectionCancelled>() => {}
            Err(error) => return Err(error).context("retained attachment inspection failed"),
        }
    }
    Ok(())
}
