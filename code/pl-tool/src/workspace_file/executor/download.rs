//! One stream per transfer. Failed reads cancel the unpublished destination writer.
use super::*;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
#[derive(Debug, thiserror::Error)]
pub enum WorkspaceDownloadError {
    #[error("target file path failed")]
    Path(#[source] WorkspaceFileError),
    #[error("target file open failed")]
    Open(#[source] pl_remote_helper::ExecutionError),
    #[error("source read failed")]
    Read(#[source] std::io::Error),
    #[error("file transfer failed")]
    Io(#[from] std::io::Error),
    #[error("file transfer exceeded {limit} bytes")]
    TooLarge { limit: u64 },
    #[error("file ended before the confirmed prefix")]
    Incomplete,
}
impl ExecutorWorkspaceFileBackend {
    pub async fn copy_file_to<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
    ) -> std::result::Result<u64, WorkspaceDownloadError> {
        self.copy_capture(path, writer, None, None).await
    }
    pub async fn copy_capture_bounded<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: u64,
    ) -> std::result::Result<u64, WorkspaceDownloadError> {
        self.copy_capture(path, writer, Some(limit), None).await
    }
    pub async fn copy_capture_prefix<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        confirmed: u64,
        limit: u64,
    ) -> std::result::Result<u64, WorkspaceDownloadError> {
        self.copy_capture(path, writer, Some(limit), Some(confirmed))
            .await
    }
    async fn copy_capture<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: Option<u64>,
        prefix: Option<u64>,
    ) -> std::result::Result<u64, WorkspaceDownloadError> {
        if let (Some(prefix), Some(limit)) = (prefix, limit)
            && prefix > limit
        {
            return Err(WorkspaceDownloadError::TooLarge { limit });
        }
        let path = self
            .bound(
                self.path_request(path.into(), None)
                    .map_err(WorkspaceDownloadError::Path)?,
                true,
            )
            .await
            .map_err(WorkspaceDownloadError::Path)?;
        let mut reader = self
            .executor
            .fs()
            .read(&path)
            .await
            .map_err(WorkspaceDownloadError::Open)?;
        let mut offset = 0;
        let mut bytes = vec![0; 65536];
        loop {
            let remaining = prefix
                .map(|prefix| prefix.saturating_sub(offset))
                .unwrap_or(u64::MAX);
            if remaining == 0 {
                break;
            }
            let capacity = remaining.min(bytes.len() as u64) as usize;
            let count = reader
                .read(&mut bytes[..capacity])
                .await
                .map_err(WorkspaceDownloadError::Read)?;
            if count == 0 {
                if prefix.is_some() {
                    return Err(WorkspaceDownloadError::Incomplete);
                }
                break;
            }
            if let Some(limit) = limit
                && (count as u64) > limit.saturating_sub(offset)
            {
                return Err(WorkspaceDownloadError::TooLarge { limit });
            }
            writer.write_all(&bytes[..count]).await?;
            offset += count as u64;
        }
        Ok(offset)
    }
    pub async fn copy_file_from<R: AsyncRead + Unpin + Send>(
        &self,
        path: &str,
        mode: crate::workspace::WriteMode,
        total_len: u64,
        reader: &mut R,
    ) -> Result<u64> {
        let follow = matches!(mode, crate::workspace::WriteMode::Append);
        let path = self
            .bound(
                self.path_request(path.into(), None).map_err(file_error)?,
                follow,
            )
            .await
            .map_err(file_error)?;
        let mode = match mode {
            crate::workspace::WriteMode::Create => pl_remote_helper::fs::WriteMode::CreateNew,
            crate::workspace::WriteMode::Overwrite => {
                pl_remote_helper::fs::WriteMode::ReplaceAtomic
            }
            crate::workspace::WriteMode::Append => pl_remote_helper::fs::WriteMode::Append,
        };
        self.ensure_writable(&path).await?;
        self.create_parent(&path).await?;
        let mut writer = self
            .executor
            .fs()
            .write(&path, mode, Some(total_len))
            .await
            .map_err(file_error)?;
        let bytes = tokio::io::copy(reader, &mut writer)
            .await
            .map_err(|error| tool_error("file", error))?;
        let result = writer.finish().await.map_err(file_error)?;
        debug_assert_eq!(bytes, result.bytes);
        self.notify_changed(&path).await;
        Ok(result.bytes)
    }
}
