//! Reads deferred file displays through their original Thread and SSH workspace.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, ensure};
use pl_tool::{
    file_display::{
        DeferredWorkspaceFile, FileDisplayResult, TOOL_SHOW_FILES, saved_file_display_receipt,
    },
    workspace_file::ExecutorWorkspaceFileBackend,
};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

use crate::{history, studio::StudioRuntime};

pub struct DisplayDownloadRequest {
    pub thread_id: String,
    pub item_id: String,
    pub index: usize,
    pub destination: PathBuf,
}

#[derive(Debug, PartialEq, Eq)]
pub enum DisplayDownloadOutcome {
    Saved,
    Stopped,
}

impl StudioRuntime {
    /// Saves one published item to an already confirmed device-local destination.
    /// The observer receives cumulative staged bytes and the acknowledged pause state.
    pub async fn download_display_file(
        &self,
        request: DisplayDownloadRequest,
        pause: watch::Receiver<bool>,
        cancel: CancellationToken,
        progress: impl FnMut(u64, bool) + Send,
    ) -> Result<DisplayDownloadOutcome> {
        let prepare = async {
            let target = self
                .display_download_target(&request.thread_id, &request.item_id, request.index)
                .await?;
            let binding = self.display_file_binding(&request.thread_id)?;
            Ok::<_, anyhow::Error>((target, binding))
        };
        let (target, binding) = tokio::select! {
            biased;
            _ = cancel.cancelled() => return Ok(DisplayDownloadOutcome::Stopped),
            prepared = prepare => prepared?,
        };
        let control = TransferControl {
            pause,
            user_cancel: &cancel,
            binding_cancel: &binding.cancel,
        };
        let mut destination = StagedDestination::open(request.destination).await?;
        let copied = binding
            .copy(&target, &mut destination.writer, control, progress)
            .await;
        // Tokio File may still own a blocking write after write_all accepts its bytes.
        // Settle it before dropping the staging path, including on cancellation.
        let flushed = destination
            .writer
            .flush()
            .await
            .context("Flush temporary download file");
        let Some(written) = copied? else {
            flushed?;
            return Ok(DisplayDownloadOutcome::Stopped);
        };
        flushed?;
        debug_assert_eq!(target.size, written);
        destination
            .writer
            .sync_all()
            .await
            .context("Flush downloaded file")?;
        if cancel.is_cancelled() {
            return Ok(DisplayDownloadOutcome::Stopped);
        }
        ensure!(
            !binding.cancel.is_cancelled(),
            "Original SSH workspace is unavailable"
        );
        destination.commit().await?;
        Ok(DisplayDownloadOutcome::Saved)
    }

    async fn display_download_target(
        &self,
        thread_id: &str,
        item_id: &str,
        index: usize,
    ) -> Result<DeferredWorkspaceFile> {
        use crate::studio::{
            runtime::chat_item::TOOL_OUTPUT_ARTIFACTS_FIELD, thread_projection::order,
        };
        // Work-group rows use a call key while a standalone atom uses its entity key.
        let call_id = order::business_id("tool", item_id)
            .or_else(|| item_id.strip_prefix("call:").filter(|id| !id.is_empty()))
            .context("Invalid file display identity")?;
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        // Inspect live and pending deliveries before History. The reliable writer commits
        // each original before releasing its pending effect.
        if let Some(handle) = self
            .session_of(thread_id)
            .and_then(|session| session.observed_thread(thread_id))
        {
            let snapshot = handle.snapshot();
            let effects = handle.effects().await?;
            if let Some(delivery) = snapshot
                .deliveries
                .iter()
                .chain(effects.iter().flat_map(|effect| effect.deliveries.iter()))
                .find(|delivery| delivery.tool_id == TOOL_SHOW_FILES && delivery.call_id == call_id)
            {
                return deferred_target(delivery.output.details(), index);
            }
        }
        let reader = self.store.open_history_reader(thread_id).await?;
        let result = async {
            if let Some(event) = reader
                .original_for_entity(
                    order::tool_id(call_id),
                    None,
                    history::HistoryDemand {
                        max_rows: 1,
                        max_bytes: 1024 * 1024,
                    },
                )
                .await?
            {
                ensure!(
                    event.kind == history::HistoryEventKind::ToolCompleted
                        && event.call_id.as_deref() == Some(call_id)
                        && event.tool_name.as_deref() == Some(TOOL_SHOW_FILES),
                    "Item is not a completed file display"
                );
                let body = history::read_event_body_bytes(
                    &reader,
                    &event,
                    TOOL_OUTPUT_ARTIFACTS_FIELD,
                    Some(8 * 1024 * 1024),
                )
                .await?
                .context("File display receipt is missing")?;
                let details = file_display_details(&body)?;
                return deferred_target(Some(&details), index);
            }
            anyhow::bail!("File display is not available")
        }
        .await;
        reader.close().await;
        result
    }

    fn display_file_binding(&self, thread_id: &str) -> Result<DisplayFileBinding> {
        let binding = self
            .thread_factory
            .binding_snapshot(thread_id)
            .context("Original SSH workspace is unavailable")?;
        let _guard = binding.lifetime.qualification_guard();
        ensure!(
            binding.authorization.is_active() && !binding.lifetime.cancellation.is_cancelled(),
            "Original SSH workspace is unavailable"
        );
        let usage = binding
            .workspace_usage
            .upgrade()
            .context("Original workspace lease expired")?;
        let remote = binding
            .remote
            .context("Original SSH workspace is unavailable")?;
        Ok(DisplayFileBinding {
            files: remote.files().with_workspace(binding.workspace),
            cancel: binding.lifetime.cancellation.clone(),
            _usage: usage,
        })
    }

    /// Materializes a deferred channel attachment only after the bound adapter admits its size.
    pub(crate) async fn read_deferred_display_for_channel(
        &self,
        thread_id: &str,
        target: &DeferredWorkspaceFile,
        cancel: &CancellationToken,
    ) -> Result<Option<Vec<u8>>> {
        let binding = self.display_file_binding(thread_id)?;
        let (_pause, pause) = watch::channel(false);
        let control = TransferControl {
            pause,
            user_cancel: cancel,
            binding_cancel: &binding.cancel,
        };
        let mut bytes = Vec::new();
        let read = binding.copy(target, &mut bytes, control, |_, _| {}).await?;
        Ok(read.map(|_| bytes))
    }
}

fn file_display_details(body: &[u8]) -> Result<serde_json::Value> {
    let parts: Vec<serde_json::Value> = serde_json::from_slice(body)?;
    let mut receipts = parts
        .into_iter()
        .filter(|part| part.get("fileDisplay").is_some());
    let receipt = receipts.next().context("File display receipt is missing")?;
    ensure!(
        receipts.next().is_none(),
        "File display has duplicate receipts"
    );
    Ok(receipt)
}

fn deferred_target(
    details: Option<&serde_json::Value>,
    index: usize,
) -> Result<DeferredWorkspaceFile> {
    let receipt =
        saved_file_display_receipt(details)?.context("File display receipt is missing")?;
    let Some(FileDisplayResult::Deferred { target, .. }) = receipt.files.into_iter().nth(index)
    else {
        anyhow::bail!("File display item does not have a deferred source");
    };
    Ok(target)
}

struct DisplayFileBinding {
    files: ExecutorWorkspaceFileBackend,
    cancel: CancellationToken,
    _usage: crate::studio::worktree::worktree_lease::WorkspaceUsageLease,
}

impl DisplayFileBinding {
    async fn copy(
        &self,
        target: &DeferredWorkspaceFile,
        writer: &mut (impl AsyncWrite + Unpin + Send),
        mut control: TransferControl<'_>,
        mut progress: impl FnMut(u64, bool) + Send,
    ) -> Result<Option<u64>> {
        if !control.ready(0, &mut progress).await? {
            return Ok(None);
        }
        let opened = tokio::select! {
            biased;
            _ = control.user_cancel.cancelled() => return Ok(None),
            _ = control.binding_cancel.cancelled() => anyhow::bail!("Original SSH workspace is unavailable"),
            opened = self.files.open_deferred_file(target) => opened,
        };
        let mut reader = opened.context("Open original SSH file")?;
        let Some(written) = copy_body(
            &mut reader,
            writer,
            target.size,
            &mut control,
            &mut progress,
        )
        .await?
        else {
            return Ok(None);
        };
        drop(reader);
        tokio::select! {
            biased;
            _ = control.user_cancel.cancelled() => return Ok(None),
            _ = control.binding_cancel.cancelled() => anyhow::bail!("Original SSH workspace is unavailable"),
            checked = self.files.validate_deferred_file(target) => checked.context("Original SSH file changed during download")?,
        }
        Ok(control
            .ready(written, &mut progress)
            .await?
            .then_some(written))
    }
}

async fn copy_body(
    reader: &mut (impl AsyncRead + Unpin + Send),
    writer: &mut (impl AsyncWrite + Unpin + Send),
    size: u64,
    control: &mut TransferControl<'_>,
    progress: &mut (impl FnMut(u64, bool) + Send),
) -> Result<Option<u64>> {
    let mut bytes = vec![0; 64 * 1024];
    let mut written = 0_u64;
    loop {
        if !control.ready(written, progress).await? {
            return Ok(None);
        }
        let count = tokio::select! {
            biased;
            _ = control.user_cancel.cancelled() => return Ok(None),
            _ = control.binding_cancel.cancelled() => anyhow::bail!("Original SSH workspace is unavailable"),
            changed = control.pause.changed() => {
                changed.context("Download controls closed")?;
                continue;
            }
            read = reader.read(&mut bytes) => read.context("Read original SSH file")?,
        };
        if count == 0 {
            ensure!(
                written == size,
                "Original SSH file ended before its recorded size"
            );
            return Ok(Some(written));
        }
        ensure!(
            count as u64 <= size.saturating_sub(written),
            "Original SSH file grew during download"
        );
        if !control.ready(written, progress).await? {
            return Ok(None);
        }
        writer
            .write_all(&bytes[..count])
            .await
            .context("Write downloaded file")?;
        written += count as u64;
        progress(written, false);
    }
}

struct TransferControl<'a> {
    pause: watch::Receiver<bool>,
    user_cancel: &'a CancellationToken,
    binding_cancel: &'a CancellationToken,
}

impl TransferControl<'_> {
    async fn ready(
        &mut self,
        written: u64,
        report: &mut (impl FnMut(u64, bool) + Send),
    ) -> Result<bool> {
        let mut acknowledged = false;
        loop {
            if self.user_cancel.is_cancelled() {
                return Ok(false);
            }
            ensure!(
                !self.binding_cancel.is_cancelled(),
                "Original SSH workspace is unavailable"
            );
            if !*self.pause.borrow_and_update() {
                if acknowledged {
                    report(written, false);
                }
                return Ok(true);
            }
            if !acknowledged {
                report(written, true);
                acknowledged = true;
            }
            tokio::select! {
                biased;
                _ = self.user_cancel.cancelled() => return Ok(false),
                _ = self.binding_cancel.cancelled() => anyhow::bail!("Original SSH workspace is unavailable"),
                changed = self.pause.changed() => changed.context("Download controls closed")?,
            }
        }
    }
}

struct StagedDestination {
    destination: PathBuf,
    writer: tokio::fs::File,
    temporary: tempfile::NamedTempFile,
    replace: bool,
}

impl StagedDestination {
    async fn open(destination: PathBuf) -> Result<Self> {
        ensure!(
            destination.is_absolute() && destination.file_name().is_some(),
            "Save destination must be an absolute file path"
        );
        tokio::task::spawn_blocking(move || {
            let replace = match std::fs::symlink_metadata(&destination) {
                Ok(metadata) => {
                    ensure!(metadata.is_file(), "Save destination is not a regular file");
                    true
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
                Err(error) => return Err(error).context("Check save destination"),
            };
            let parent: &Path = destination
                .parent()
                .context("Save destination has no parent")?;
            let temporary = tempfile::Builder::new()
                .prefix(".anywork-download-")
                .tempfile_in(parent)
                .context("Create temporary download file")?;
            let writer = tokio::fs::File::from_std(
                temporary
                    .as_file()
                    .try_clone()
                    .context("Open temporary download file")?,
            );
            Ok(Self {
                destination,
                temporary,
                writer,
                replace,
            })
        })
        .await?
    }

    async fn commit(self) -> Result<()> {
        let Self {
            destination,
            temporary,
            writer,
            replace,
        } = self;
        drop(writer);
        tokio::task::spawn_blocking(move || {
            if replace {
                temporary.persist(destination)
            } else {
                temporary.persist_noclobber(destination)
            }
            .map(|_| ())
            .context("Commit downloaded file")
        })
        .await?
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn pausing_continues_the_same_reader_and_stop_drops_staging() -> Result<()> {
        for stop in [false, true] {
            let directory = tempfile::tempdir()?;
            let destination = directory.path().join("selected.bin");
            if stop {
                std::fs::write(&destination, b"previous file")?;
            }
            let mut staging = StagedDestination::open(destination.clone()).await?;
            let temporary = staging.temporary.path().to_owned();
            let (mut source, mut reader) = tokio::io::duplex(8);
            let (pause, receiver) = watch::channel(false);
            let user = CancellationToken::new();
            let binding = CancellationToken::new();
            let mut control = TransferControl {
                pause: receiver,
                user_cancel: &user,
                binding_cancel: &binding,
            };
            let (report, mut progress) = tokio::sync::mpsc::unbounded_channel();
            let mut publish = |size, paused| {
                let _ = report.send((size, paused));
            };
            let completion = copy_body(
                &mut reader,
                &mut staging.writer,
                8,
                &mut control,
                &mut publish,
            );
            let scenario = async {
                source.write_all(b"head").await?;
                assert_eq!(progress.recv().await, Some((4, false)));
                pause.send(true)?;
                assert_eq!(progress.recv().await, Some((4, true)));
                source.write_all(b"tail").await?;
                if stop {
                    assert_eq!(std::fs::read(&destination)?, b"previous file");
                } else {
                    assert!(!destination.exists());
                }
                assert!(progress.try_recv().is_err());
                if stop {
                    user.cancel();
                } else {
                    pause.send(false)?;
                    assert_eq!(progress.recv().await, Some((4, false)));
                    assert_eq!(progress.recv().await, Some((8, false)));
                }
                source.shutdown().await?;
                Ok::<_, anyhow::Error>(())
            };
            let (result, observed) =
                tokio::time::timeout(std::time::Duration::from_secs(5), async {
                    tokio::join!(completion, scenario)
                })
                .await?;
            observed?;
            if stop {
                assert_eq!(result?, None);
                drop(staging);
                assert_eq!(std::fs::read(destination)?, b"previous file");
            } else {
                assert_eq!(result?, Some(8));
                staging.writer.sync_all().await?;
                staging.commit().await?;
                assert_eq!(std::fs::read(destination)?, b"headtail");
            }
            assert!(!temporary.exists());
        }
        Ok(())
    }

    #[tokio::test]
    async fn staging_never_clobbers_a_file_created_during_transfer() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("selected.bin");
        let mut staging = StagedDestination::open(path.clone()).await?;
        let temporary = staging.temporary.path().to_owned();
        staging.writer.write_all(b"downloaded").await?;
        staging.writer.sync_all().await?;
        std::fs::write(&path, b"another writer")?;
        assert!(staging.commit().await.is_err());
        assert_eq!(std::fs::read(path)?, b"another writer");
        assert!(!temporary.exists());
        Ok(())
    }
}
