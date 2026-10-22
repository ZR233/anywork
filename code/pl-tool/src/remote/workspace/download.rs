//! Bounded remote capture transfer into a caller-owned local writer.
//!
//! The transfer streams from one opened remote file handle, so a capture is never preloaded into
//! memory and its declared length is checked before the first local byte is staged.

use pl_protocol::remote::{RemoteReadRequest, RemoteResourceClass};
use pl_remote_helper::remote_transport::DATA_CHUNK_BYTES;
use tokio::io::{AsyncReadExt, AsyncWrite, AsyncWriteExt};

use super::RemoteWorkspaceFileBackend;
use crate::remote::error::RemoteClientError;

#[derive(Debug, thiserror::Error)]
pub enum RemoteDownloadError {
    #[error("invalid remote capture path")]
    Path(#[source] pl_protocol::PureError),
    #[error("remote capture read failed at byte {offset}")]
    Read {
        offset: u64,
        #[source]
        source: RemoteClientError,
    },
    #[error("remote capture range is inconsistent at byte {offset}")]
    Inconsistent { offset: u64 },
    #[error("unexpected remote capture response: {0}")]
    Response(String),
    #[error("local capture staging failed at byte {offset}")]
    Write {
        offset: u64,
        #[source]
        source: std::io::Error,
    },
    #[error("remote capture is {total} bytes, past the {limit}-byte transfer ceiling")]
    TooLarge { total: u64, limit: u64 },
}

impl RemoteWorkspaceFileBackend {
    /// Copies a completed remote capture without imposing a total-size limit.
    ///
    /// The caller owns the staging writer and publishes it only after this operation succeeds.
    ///
    /// # Errors
    /// Rejects invalid paths, changed lengths, incomplete transfers, transport and staging failures.
    pub async fn copy_file_to<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
    ) -> Result<u64, RemoteDownloadError> {
        self.copy_capture(path, writer, None).await
    }

    /// Copies a completed remote capture only while its real length stays within `limit`.
    ///
    /// The bound is enforced from the opened handle's authoritative total length before any byte
    /// is staged, so a runaway remote capture is refused with a typed reason instead of being
    /// transferred and rejected only after the whole copy. The caller owns the staging writer and
    /// publishes it only after this operation succeeds.
    ///
    /// # Errors
    /// Returns [`RemoteDownloadError::TooLarge`] for a capture past `limit`, plus the same path,
    /// transfer, transport and staging failures as [`Self::copy_file_to`].
    pub async fn copy_capture_bounded<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: u64,
    ) -> Result<u64, RemoteDownloadError> {
        self.copy_capture(path, writer, Some(limit)).await
    }

    async fn copy_capture<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: Option<u64>,
    ) -> Result<u64, RemoteDownloadError> {
        let lease = self
            .operation_lease(RemoteResourceClass::ReadFile)
            .await
            .map_err(|source| RemoteDownloadError::Read { offset: 0, source })?;
        let workspace_id = lease
            .workspace_id()
            .ok_or_else(|| {
                RemoteDownloadError::Response(
                    "remote operation has no workspace handle".to_string(),
                )
            })?
            .to_string();
        let path =
            super::resolve_remote_path(path.to_owned(), None).map_err(RemoteDownloadError::Path)?;
        let mut reader = lease
            .read_file(RemoteReadRequest {
                workspace_id,
                path,
                offset: 0,
                max_bytes: None,
            })
            .await
            .map_err(|source| RemoteDownloadError::Read { offset: 0, source })?;
        let total_len = reader.metadata().total_len;
        // The ceiling is checked against the authoritative total before staging a single byte.
        if let Some(limit) = limit
            && total_len > limit
        {
            return Err(RemoteDownloadError::TooLarge {
                total: total_len,
                limit,
            });
        }
        let mut buffer = vec![0_u8; DATA_CHUNK_BYTES];
        let mut offset = 0_u64;
        loop {
            let count = reader
                .read(&mut buffer)
                .await
                .map_err(|error| stream_read_error(error, offset))?;
            if count == 0 {
                break;
            }
            writer
                .write_all(&buffer[..count])
                .await
                .map_err(|source| RemoteDownloadError::Write { offset, source })?;
            offset += count as u64;
            if offset > total_len {
                return Err(RemoteDownloadError::Inconsistent { offset });
            }
        }
        if offset != total_len {
            return Err(RemoteDownloadError::Inconsistent { offset });
        }
        Ok(total_len)
    }
}

/// Keeps a typed remote failure that travels through the reader's `io::Error`.
///
/// The file stream wraps its own [`RemoteClientError`] as the `io::Error` source, so a disconnect or a
/// typed helper rejection keeps its code instead of becoming a string. A failure raised by the local
/// stream itself is still reported as a read failure with the real I/O kind preserved.
fn stream_read_error(error: std::io::Error, offset: u64) -> RemoteDownloadError {
    if let Some(source) = error
        .get_ref()
        .and_then(|inner| inner.downcast_ref::<RemoteClientError>())
    {
        return RemoteDownloadError::Read {
            offset,
            source: source.clone(),
        };
    }
    RemoteDownloadError::Read {
        offset,
        // A failure raised locally by the reader is not a helper-authored code, so it stays in the
        // client-side protocol bucket instead of claiming a remote error code.
        source: RemoteClientError::Protocol(format!(
            "remote capture stream read failed locally ({:?}): {error}",
            error.kind()
        )),
    }
}
