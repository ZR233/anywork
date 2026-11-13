//! Archive a confirmed capture prefix through its frozen executor into durable host storage.
use std::path::PathBuf;
use std::sync::Arc;

use pl_core::{context::ResourceReference, tool::opaque::ToolError};
use pl_tool::{exec::CommandOutputArchive, workspace_file::ExecutorWorkspaceFileBackend};

use super::MAX_COMMAND_ARCHIVE_BYTES;
use super::{FileResourceStore, ResourceStoreError, retention_failure, retention_io_fault};

#[derive(Debug, Clone)]
pub struct ExecutorCommandOutputArchive {
    store: FileResourceStore,
    files: Arc<ExecutorWorkspaceFileBackend>,
    host_scratch: PathBuf,
}

impl FileResourceStore {
    /// Binds the execution workspace binding and this Thread's host transfer scratch.
    ///
    /// Staging lives in the host-owned Thread scratch directory supplied by the factory, never
    /// under `resources` and never guessed from a parent directory. That scratch is
    /// transfer space, not a model-writable workspace path.
    pub fn command_archive(
        &self,
        files: Arc<ExecutorWorkspaceFileBackend>,
        host_scratch: PathBuf,
    ) -> ExecutorCommandOutputArchive {
        ExecutorCommandOutputArchive {
            store: self.clone(),
            files,
            host_scratch,
        }
    }
}

impl CommandOutputArchive for ExecutorCommandOutputArchive {
    async fn retain(
        &self,
        _: &str,
        snapshot: &pl_tool::command::CommandOutputSnapshot,
        stream: pl_tool::command::CommandCaptureStream,
    ) -> Result<ResourceReference, ToolError> {
        if snapshot
            .capture
            .as_ref()
            .and_then(|capture| capture.confirmed_total())
            .is_some_and(|total| total > MAX_COMMAND_ARCHIVE_BYTES)
        {
            return Err(retention_failure(ResourceStoreError::TooLarge {
                limit: MAX_COMMAND_ARCHIVE_BYTES,
            }));
        }
        let confirmed = snapshot
            .confirmed_bytes(stream)
            .ok_or_else(|| pl_core::tool::opaque::ToolError::new(ResourceStoreError::Identity))?;
        let path = match stream {
            pl_tool::command::CommandCaptureStream::Stdout => &snapshot.capture_file,
            pl_tool::command::CommandCaptureStream::Stderr => &snapshot.stderr_capture_file,
        }
        .to_str()
        .ok_or_else(|| ToolError::new(ResourceStoreError::Identity))?
        .to_owned();
        let scratch = self.host_scratch.clone();
        let staging = tokio::task::spawn_blocking(move || {
            std::fs::create_dir_all(&scratch)
                .and_then(|()| tempfile::tempfile_in(&scratch))
                .map_err(|source| ResourceStoreError::Io {
                    path: scratch,
                    source,
                })
        })
        .await
        .map_err(ToolError::new)?
        .map_err(retention_failure)?;
        let local = staging.try_clone().map_err(retention_io_fault)?;
        let mut writer = tokio::fs::File::from_std(local);
        // Bound the transfer by the authoritative remote length before staging any byte, so a runaway
        // capture is refused without a full download. A local staging write failure is a storage
        // obligation; a transport/oversize failure is not, so it stays a plain tool error.
        self.files
            .copy_capture_prefix(&path, &mut writer, confirmed, MAX_COMMAND_ARCHIVE_BYTES)
            .await
            .map_err(|error| download_failure(error, self.files.executor().is_local()))?;
        writer.sync_all().await.map_err(retention_io_fault)?;
        drop(writer);
        let store = self.store.clone();
        tokio::task::spawn_blocking(move || {
            super::retain_command_capture_file(&store.root, staging)
        })
        .await
        .map_err(ToolError::new)?
        .map_err(retention_failure)
    }
}

/// Maps a bounded remote-capture transfer failure to the tool boundary.
///
/// A local staging write failure is the same typed storage fact a local capture failure is, so it is
/// reported through the obligation boundary. A path, framing, transport or oversize failure is not a
/// storage fault: it stays a plain tool error, and the category is taken from the typed variant
/// rather than parsed out of the text.
fn download_failure(
    error: pl_tool::workspace_file::WorkspaceDownloadError,
    source_is_local: bool,
) -> ToolError {
    use pl_tool::workspace_file::WorkspaceDownloadError;
    match error {
        WorkspaceDownloadError::Io(source) => retention_io_fault(source),
        WorkspaceDownloadError::Read(source) if source_is_local => retention_io_fault(source),
        WorkspaceDownloadError::Open(pl_remote_helper::ExecutionError::Io { source, .. })
            if source_is_local =>
        {
            retention_io_fault(std::io::Error::new(source.kind(), source.to_string()))
        }
        other => ToolError::new(other),
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use pl_core::context::ResourceReader;
    use pl_tool::command::{
        CommandCaptureStream, CommandProcessManager, CommandStartRequest, ExecutorCommandBackend,
    };
    use std::time::Duration;

    #[tokio::test]
    async fn executor_archive_retains_only_confirmed_raw_prefix_and_rejects_unknown_length()
    -> anyhow::Result<()> {
        let root = tempfile::tempdir()?;
        let backend = Arc::new(ExecutorCommandBackend::local(root.path())?);
        let binding = backend.binding();
        let files = Arc::new(ExecutorWorkspaceFileBackend::new(
            binding.executor().clone(),
            binding.root(),
        )?);
        let manager = CommandProcessManager::new(backend);
        let mut snapshot = manager
            .run_task(
                "task-archive-prefix",
                CommandStartRequest {
                    interactive: false,
                    command: "printf '\\377\\000raw'; printf error >&2".into(),
                    cwd: None,
                    allow_workspace_escape: false,
                    timeout: Duration::from_secs(10),
                    yield_time: Duration::ZERO,
                    max_output_chars: 128,
                    session_id: "archive-owner".into(),
                    tool_id: "capture".into(),
                    call_id: "call".into(),
                    cancellation_token: None,
                    output_observer: None,
                },
            )
            .await?;
        let reliable = tempfile::tempdir()?;
        let scratch = tempfile::tempdir()?;
        let store = FileResourceStore::new(reliable.path().into());
        let archive = store.command_archive(files, scratch.path().into());
        // Extra bytes written after the observed capture never become historical facts.
        use std::io::Write;
        std::fs::OpenOptions::new()
            .append(true)
            .open(&snapshot.capture_file)?
            .write_all(b"unconfirmed")?;
        let reference = archive
            .retain("archive-owner", &snapshot, CommandCaptureStream::Stdout)
            .await?;
        let retry = archive
            .retain("archive-owner", &snapshot, CommandCaptureStream::Stdout)
            .await?;
        assert_eq!(reference, retry);
        assert_eq!(
            store.read(reference, Default::default()).await?.as_ref(),
            b"\xff\0raw"
        );
        let stderr = archive
            .retain("archive-owner", &snapshot, CommandCaptureStream::Stderr)
            .await?;
        assert_eq!(
            store.read(stderr, Default::default()).await?.as_ref(),
            b"error"
        );
        snapshot.capture.as_mut().unwrap().stdout.confirmed_bytes = None;
        assert!(
            archive
                .retain("archive-owner", &snapshot, CommandCaptureStream::Stdout)
                .await
                .is_err()
        );
        Ok(())
    }
}
