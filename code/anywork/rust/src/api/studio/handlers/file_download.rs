//! A desktop download lives in the bridge's managed scope until its writer exits.

use std::path::PathBuf;

use pl_lifecycle::{Managed, ManagedResource};
use pl_studio_runtime::{DisplayDownloadOutcome, DisplayDownloadRequest, StudioRuntime};
use tokio::{
    sync::{Mutex, watch},
    task::JoinHandle,
};
use tokio_util::sync::CancellationToken;

use crate::api::studio::{
    bridge_runtime::active_bridge,
    subscription::error::{close_error, open_error},
    types::BridgeError,
};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum BridgeFileDownloadPhase {
    Downloading,
    Paused,
    Saved,
    Stopped,
    Failed,
}

impl BridgeFileDownloadPhase {
    fn is_terminal(self) -> bool {
        matches!(self, Self::Saved | Self::Stopped | Self::Failed)
    }
}

#[derive(Clone)]
pub struct BridgeFileDownloadStatus {
    pub revision: u64,
    pub written: u64,
    pub phase: BridgeFileDownloadPhase,
    pub error: Option<BridgeError>,
}

pub struct BridgeFileDownload {
    managed: Managed<DownloadResource>,
}

struct DownloadResource {
    pause: watch::Sender<bool>,
    cancel: CancellationToken,
    status: watch::Receiver<BridgeFileDownloadStatus>,
    task: Mutex<Option<JoinHandle<()>>>,
}

impl DownloadResource {
    fn start(
        studio: StudioRuntime,
        request: DisplayDownloadRequest,
        cancel: CancellationToken,
    ) -> Self {
        let (pause, control) = watch::channel(false);
        let (publish, status) = watch::channel(BridgeFileDownloadStatus {
            revision: 1,
            written: 0,
            phase: BridgeFileDownloadPhase::Downloading,
            error: None,
        });
        let task_cancel = cancel.clone();
        let task = tokio::spawn(async move {
            let result = studio
                .download_display_file(request, control, task_cancel, |written, paused| {
                    let phase = if paused {
                        BridgeFileDownloadPhase::Paused
                    } else {
                        BridgeFileDownloadPhase::Downloading
                    };
                    publish.send_modify(|status| {
                        status.written = written;
                        status.phase = phase;
                        status.revision += 1;
                    });
                })
                .await;
            publish.send_modify(|status| {
                status.revision += 1;
                status.phase = match result {
                    Ok(DisplayDownloadOutcome::Saved) => BridgeFileDownloadPhase::Saved,
                    Ok(DisplayDownloadOutcome::Stopped) => BridgeFileDownloadPhase::Stopped,
                    Err(error) => {
                        status.error = Some(error.into());
                        BridgeFileDownloadPhase::Failed
                    }
                };
            });
        });
        Self {
            pause,
            cancel,
            status,
            task: Mutex::new(Some(task)),
        }
    }
}

impl ManagedResource for DownloadResource {
    type Error = BridgeError;

    fn request_close(&self) {
        self.cancel.cancel();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        let mut task = self.task.lock().await;
        if let Some(handle) = task.as_mut() {
            let result = handle.await;
            *task = None;
            result.map_err(anyhow::Error::from)?;
        }
        Ok(())
    }
}

impl BridgeFileDownload {
    pub async fn next_status(
        &self,
        after_revision: u64,
    ) -> Result<BridgeFileDownloadStatus, BridgeError> {
        let mut status = self.managed.get().status.clone();
        let latest = status
            .wait_for(|status| status.revision > after_revision || status.phase.is_terminal())
            .await
            .map_err(|_| {
                BridgeError::from(anyhow::anyhow!("Download owner ended without a result"))
            })?;
        Ok(latest.clone())
    }

    pub async fn set_paused(&self, paused: bool) -> Result<(), BridgeError> {
        let resource = self.managed.get();
        resource.pause.send_if_modified(|value| {
            let changed = *value != paused;
            *value = paused;
            changed
        });
        let mut status = resource.status.clone();
        status
            .wait_for(|status| {
                status.phase.is_terminal()
                    || (status.phase == BridgeFileDownloadPhase::Paused) == paused
            })
            .await
            .map_err(|_| {
                BridgeError::from(anyhow::anyhow!("Download owner ended without a result"))
            })?;
        Ok(())
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.managed.close().await.map_err(close_error)
    }
}

pub async fn start_file_download(
    thread_id: String,
    item_id: String,
    index: u32,
    destination: String,
) -> Result<BridgeFileDownload, BridgeError> {
    let bridge = active_bridge().await?;
    let studio = bridge.studio.clone();
    let request = DisplayDownloadRequest {
        thread_id,
        item_id,
        index: index as usize,
        destination: PathBuf::from(destination),
    };
    let managed = bridge
        .observation_scope
        .handle()
        .open("file-download", move |cancel| async move {
            Ok(DownloadResource::start(studio, request, cancel))
        })
        .await
        .map_err(open_error)?;
    Ok(BridgeFileDownload { managed })
}
