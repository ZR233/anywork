//! File transfer orchestration stays on the host; the helper owns only physical handles.
use super::*;
use pl_protocol::remote::REMOTE_IO_CHUNK_BYTES;
use sha2::{Digest, Sha256};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

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
    #[error("remote capture range or checksum is inconsistent at byte {offset}")]
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
struct TransferLease {
    client: RemoteClient,
    id: Option<String>,
}
impl Drop for TransferLease {
    fn drop(&mut self) {
        if let Some(transfer_id) = self.id.take() {
            self.client
                .release_resource(RemoteRequest::CloseTransfer { transfer_id });
        }
    }
}
impl TransferLease {
    async fn close(mut self) -> std::result::Result<(), RemoteClientError> {
        let transfer_id = self.id.as_ref().unwrap().clone();
        self.client
            .request(RemoteRequest::CloseTransfer { transfer_id }, &[])
            .await
            .and_then(super::super::client::expect_ack)?;
        self.id = None;
        Ok(())
    }
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
    /// Copies exactly the producer-confirmed prefix, retaining the original transfer identity.
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
        let path = self
            .path_request(path.to_owned(), None)
            .map_err(remote_file_error)
            .map_err(RemoteDownloadError::Path)?;
        let opened = self
            .request(RemoteRequest::OpenRead(path), &[])
            .await
            .map_err(|source| RemoteDownloadError::Read { offset: 0, source })?;
        let RemoteResponse::Transfer(opened) = opened.response else {
            return Err(RemoteDownloadError::Response("expected file handle".into()));
        };
        let lease = TransferLease {
            client: self.client.clone(),
            id: Some(opened.transfer_id.clone()),
        };
        let total = opened
            .total_len
            .ok_or(RemoteDownloadError::Inconsistent { offset: 0 })?;
        let source_total = total;
        let total = prefix.unwrap_or(source_total);
        if total > source_total {
            return Err(RemoteDownloadError::Inconsistent {
                offset: source_total,
            });
        }
        if let Some(limit) = limit
            && total > limit
        {
            return Err(RemoteDownloadError::TooLarge { total, limit });
        }
        let mut offset = 0;
        let mut digest = Sha256::new();
        while offset < total {
            let count = (total - offset).min(REMOTE_IO_CHUNK_BYTES as u64) as usize;
            let reply = self
                .request(
                    RemoteRequest::ReadFileChunk {
                        transfer_id: opened.transfer_id.clone(),
                        offset,
                        max_bytes: count,
                    },
                    &[],
                )
                .await
                .map_err(|source| RemoteDownloadError::Read { offset, source })?;
            let RemoteResponse::ByteRange {
                offset: actual,
                total_len,
            } = reply.response
            else {
                return Err(RemoteDownloadError::Response("expected byte range".into()));
            };
            if actual != offset || total_len != source_total || reply.body.len() != count {
                return Err(RemoteDownloadError::Inconsistent { offset });
            }
            writer
                .write_all(&reply.body)
                .await
                .map_err(|source| RemoteDownloadError::Write { offset, source })?;
            digest.update(&reply.body);
            offset += reply.body.len() as u64;
        }
        let final_state = self
            .request(
                RemoteRequest::TransferStatus {
                    transfer_id: opened.transfer_id.clone(),
                },
                &[],
            )
            .await
            .map_err(|source| RemoteDownloadError::Read { offset, source })?;
        let RemoteResponse::Transfer(final_state) = final_state.response else {
            return Err(RemoteDownloadError::Response(
                "expected transfer status".into(),
            ));
        };
        if final_state.revision != opened.revision
            || (prefix.is_none() && Some(hex::encode(digest.finalize())) != opened.sha256)
        {
            return Err(RemoteDownloadError::Inconsistent { offset });
        }
        lease
            .close()
            .await
            .map_err(|source| RemoteDownloadError::Read { offset, source })?;
        Ok(offset)
    }
    pub(super) async fn upload(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        let target = self
            .path_request(request.path, request.cwd)
            .map_err(remote_file_error)?;
        self.upload_bytes(target, request.mode.into(), request.content.as_bytes())
            .await
    }
    /// Uploads a known-length stream with bounded resident memory, even for multi-gigabyte files.
    /// The source is read once; acknowledged ranges survive transport replacement.
    pub async fn copy_file_from<R: AsyncRead + Unpin + Send>(
        &self,
        path: &str,
        mode: crate::workspace::WriteMode,
        total_len: u64,
        reader: &mut R,
    ) -> Result<u64> {
        self.upload_reader(
            self.path_request(path.to_owned(), None)
                .map_err(remote_file_error)?,
            mode.into(),
            total_len,
            reader,
        )
        .await
    }
    pub(super) async fn upload_bytes(
        &self,
        target: RemotePathRequest,
        mode: pl_protocol::remote::RemoteWriteMode,
        bytes: &[u8],
    ) -> Result<()> {
        self.upload_reader(target, mode, bytes.len() as u64, &mut &*bytes)
            .await
            .map(|_| ())
    }
    async fn upload_reader<R: AsyncRead + Unpin + Send>(
        &self,
        target: RemotePathRequest,
        mode: pl_protocol::remote::RemoteWriteMode,
        total_len: u64,
        reader: &mut R,
    ) -> Result<u64> {
        let opened = self
            .request(
                RemoteRequest::BeginWrite(pl_protocol::remote::RemoteWriteRequest {
                    target,
                    mode,
                    total_len,
                }),
                &[],
            )
            .await
            .map_err(remote_file_error)?;
        let RemoteResponse::Transfer(opened) = opened.response else {
            return Err(tool_error("write_file", "expected staging handle"));
        };
        let lease = TransferLease {
            client: self.client.clone(),
            id: Some(opened.transfer_id.clone()),
        };
        let mut offset = 0;
        let mut digest = Sha256::new();
        while offset < total_len {
            let count = (total_len - offset).min(REMOTE_IO_CHUNK_BYTES as u64) as usize;
            let mut bytes = vec![0; count];
            reader.read_exact(&mut bytes).await.map_err(|error| {
                tool_error("write_file", format!("source read at {offset}: {error}"))
            })?;
            digest.update(&bytes);
            let reply = self
                .request(
                    RemoteRequest::WriteChunk {
                        transfer_id: opened.transfer_id.clone(),
                        offset,
                        sha256: hex::encode(Sha256::digest(&bytes)),
                    },
                    &bytes,
                )
                .await
                .map_err(remote_file_error)?;
            if !matches!(reply.response, RemoteResponse::ChunkWritten { offset: actual, length, .. } if actual == offset && length == count as u64)
            {
                return Err(tool_error("write_file", "chunk receipt is inconsistent"));
            }
            offset += count as u64;
        }
        let result = self
            .request(
                RemoteRequest::CommitWrite {
                    transfer_id: opened.transfer_id,
                    length: total_len,
                    sha256: hex::encode(digest.finalize()),
                },
                &[],
            )
            .await
            .map_err(remote_file_error)?;
        if !matches!(result.response, RemoteResponse::Transfer(status) if status.committed && status.offset == total_len)
        {
            return Err(tool_error(
                "write_file",
                "file commit did not confirm completion",
            ));
        }
        lease.close().await.map_err(remote_file_error)?;
        Ok(total_len)
    }
}
