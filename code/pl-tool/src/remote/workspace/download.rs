//! One stream per transfer. Failed reads cancel the unpublished destination writer.
use super::*;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
#[derive(Debug, thiserror::Error)]
pub enum RemoteDownloadError {
    #[error("remote file path failed")]
    Path(#[source] SshError),
    #[error("remote file open failed")]
    Open(#[source] pl_remote_helper::ExecutionError),
    #[error("file transfer failed")]
    Io(#[from] std::io::Error),
    #[error("file transfer exceeded {limit} bytes")]
    TooLarge { limit: u64 },
    #[error("file ended before the confirmed prefix")]
    Incomplete,
}
impl RemoteWorkspaceFileBackend {
    pub async fn copy_file_to<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
    ) -> std::result::Result<u64, RemoteDownloadError> {
        self.copy_capture(path, writer, None, None).await
    }
    pub async fn copy_capture_bounded<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: u64,
    ) -> std::result::Result<u64, RemoteDownloadError> {
        self.copy_capture(path, writer, Some(limit), None).await
    }
    pub async fn copy_capture_prefix<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        confirmed: u64,
        limit: u64,
    ) -> std::result::Result<u64, RemoteDownloadError> {
        self.copy_capture(path, writer, Some(limit), Some(confirmed))
            .await
    }
    async fn copy_capture<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: Option<u64>,
        prefix: Option<u64>,
    ) -> std::result::Result<u64, RemoteDownloadError> {
        if let (Some(prefix), Some(limit)) = (prefix, limit)
            && prefix > limit
        {
            return Err(RemoteDownloadError::TooLarge { limit });
        }
        let path = self
            .bound(
                self.path_request(path.into(), None)
                    .map_err(RemoteDownloadError::Path)?,
                true,
            )
            .await
            .map_err(RemoteDownloadError::Path)?;
        let mut reader = self
            .executor
            .fs()
            .read(&path)
            .await
            .map_err(RemoteDownloadError::Open)?;
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
            let count = reader.read(&mut bytes[..capacity]).await?;
            if count == 0 {
                if prefix.is_some() {
                    return Err(RemoteDownloadError::Incomplete);
                }
                break;
            }
            if let Some(limit) = limit
                && (count as u64) > limit.saturating_sub(offset)
            {
                return Err(RemoteDownloadError::TooLarge { limit });
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
                self.path_request(path.into(), None)
                    .map_err(remote_file_error)?,
                follow,
            )
            .await
            .map_err(remote_file_error)?;
        let mode = match mode {
            crate::workspace::WriteMode::Create => pl_remote_helper::fs::WriteMode::CreateNew,
            crate::workspace::WriteMode::Overwrite => {
                pl_remote_helper::fs::WriteMode::ReplaceAtomic
            }
            crate::workspace::WriteMode::Append => pl_remote_helper::fs::WriteMode::Append,
        };
        let parent = self
            .executor
            .path(super::parent(path.as_str()))
            .map_err(|error| remote_file_error(error.into()))?;
        self.executor
            .fs()
            .create_dir(&parent, true)
            .await
            .map_err(|error| remote_file_error(error.into()))?;
        let mut writer = self
            .executor
            .fs()
            .write(&path, mode, Some(total_len))
            .await
            .map_err(|error| remote_file_error(error.into()))?;
        let bytes = tokio::io::copy(reader, &mut writer)
            .await
            .map_err(|error| tool_error("file", error))?;
        let result = writer
            .finish()
            .await
            .map_err(|error| remote_file_error(error.into()))?;
        debug_assert_eq!(bytes, result.bytes);
        Ok(result.bytes)
    }
}
