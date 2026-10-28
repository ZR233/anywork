//! Archive remote output only after a complete remote transfer into local staging.
use std::path::PathBuf;
use std::sync::Arc;

use pl_core::{context::ResourceReference, tool::opaque::ToolError};
use pl_tool::{exec::CommandOutputArchive, remote::RemoteWorkspaceFileBackend};

use super::MAX_COMMAND_ARCHIVE_BYTES;
use super::{FileResourceStore, ResourceStoreError, retention_failure, retention_io_fault};

#[derive(Debug, Clone)]
pub struct RemoteCommandOutputArchive {
    store: FileResourceStore,
    files: Arc<RemoteWorkspaceFileBackend>,
    host_scratch: PathBuf,
}

impl FileResourceStore {
    /// Binds the remote workspace lease and this Thread's host transfer scratch.
    ///
    /// Staging lives in the host-owned Thread scratch directory supplied by the factory, never
    /// under `thread-resources` and never guessed from a parent directory. That scratch is
    /// transfer space, not a model-writable workspace path.
    pub fn remote_command_archive(
        &self,
        files: Arc<RemoteWorkspaceFileBackend>,
        host_scratch: PathBuf,
    ) -> RemoteCommandOutputArchive {
        RemoteCommandOutputArchive {
            store: self.clone(),
            files,
            host_scratch,
        }
    }
}

impl CommandOutputArchive for RemoteCommandOutputArchive {
    async fn retain(
        &self,
        _: &str,
        snapshot: &pl_tool::command::CommandOutputSnapshot,
        stream: pl_tool::command::CommandCaptureStream,
    ) -> Result<ResourceReference, ToolError> {
        if snapshot.capture_offsets.total() > MAX_COMMAND_ARCHIVE_BYTES {
            return Err(retention_failure(ResourceStoreError::TooLarge {
                limit: MAX_COMMAND_ARCHIVE_BYTES,
            }));
        }
        let confirmed = snapshot.capture_offsets.get(stream);
        let path = match stream {
            pl_tool::command::CommandCaptureStream::Stdout => &snapshot.capture_file,
            pl_tool::command::CommandCaptureStream::Stderr => &snapshot.stderr_capture_file,
        }
        .to_str()
        .ok_or_else(|| ToolError::new(ResourceStoreError::Identity))?
        .replace('\\', "/");
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
            .map_err(remote_download_failure)?;
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
fn remote_download_failure(error: pl_tool::remote::RemoteDownloadError) -> ToolError {
    use pl_tool::remote::RemoteDownloadError;
    match error {
        RemoteDownloadError::Write { source, .. } => retention_io_fault(source),
        other => ToolError::new(other),
    }
}
