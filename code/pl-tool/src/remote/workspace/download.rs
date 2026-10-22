//! File transfer orchestration stays on the host; the helper owns only physical handles.
use super::*;
use futures::{StreamExt, stream::FuturesOrdered};
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
        let transfer_id = self.id.take().unwrap();
        self.client
            .request(RemoteRequest::CloseTransfer { transfer_id }, &[])
            .await
            .map(|_| ())
    }
}
impl RemoteWorkspaceFileBackend {
    pub async fn copy_file_to<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
    ) -> std::result::Result<u64, RemoteDownloadError> {
        self.copy_capture(path, writer, None).await
    }
    pub async fn copy_capture_bounded<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: u64,
    ) -> std::result::Result<u64, RemoteDownloadError> {
        self.copy_capture(path, writer, Some(limit)).await
    }
    async fn copy_capture<W: AsyncWrite + Unpin + Send>(
        &self,
        path: &str,
        writer: &mut W,
        limit: Option<u64>,
    ) -> std::result::Result<u64, RemoteDownloadError> {
        let path = self
            .path_request(path.to_owned(), None)
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
        if let Some(limit) = limit
            && total > limit
        {
            return Err(RemoteDownloadError::TooLarge { total, limit });
        }
        let mut offset = 0;
        let mut submitted = 0;
        let mut digest = Sha256::new();
        let mut pending = FuturesOrdered::new();
        let mut pipeline = 1;
        while offset < total {
            while submitted < total
                && pending.len() < pipeline.min(self.client.process_capacity().max(1))
            {
                let count = (total - submitted).min(self.client.fragment_bytes() as u64) as usize;
                pending.push_back(self.download_range(
                    opened.transfer_id.clone(),
                    submitted,
                    count,
                ));
                submitted += count as u64;
            }
            let (requested, count, reply) = pending
                .next()
                .await
                .ok_or(RemoteDownloadError::Inconsistent { offset })??;
            let RemoteResponse::ByteRange {
                offset: actual,
                total_len,
            } = reply.response
            else {
                return Err(RemoteDownloadError::Response("expected byte range".into()));
            };
            if actual != offset
                || actual != requested
                || total_len != total
                || reply.body.len() != count
            {
                return Err(RemoteDownloadError::Inconsistent { offset });
            }
            writer
                .write_all(&reply.body)
                .await
                .map_err(|source| RemoteDownloadError::Write { offset, source })?;
            digest.update(&reply.body);
            offset += reply.body.len() as u64;
            pipeline = next_pipeline(pipeline, reply.timing, self.client.process_capacity());
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
            || Some(hex::encode(digest.finalize())) != opened.sha256
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
        let target = self.path_request(request.path, request.cwd)?;
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
            self.path_request(path.to_owned(), None)?,
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
        let mut confirmed = 0;
        let mut digest = Sha256::new();
        let mut pending = FuturesOrdered::new();
        let mut pipeline = 1;
        while confirmed < total_len {
            while offset < total_len
                && pending.len() < pipeline.min(self.client.process_capacity().max(1))
            {
                let count = (total_len - offset).min(self.client.fragment_bytes() as u64) as usize;
                let Some(reservation) = self
                    .client
                    .reserve_upload(
                        self.lease.clone(),
                        opened.transfer_id.clone(),
                        offset,
                        count,
                        pending.is_empty(),
                    )
                    .await
                    .map_err(remote_file_error)?
                else {
                    break;
                };
                let mut bytes = vec![0; count];
                reader.read_exact(&mut bytes).await.map_err(|error| {
                    tool_error("write_file", format!("source read at {offset}: {error}"))
                })?;
                digest.update(&bytes);
                let requested = offset;
                let reply = reservation.submit(bytes);
                pending.push_back(async move { (requested, count, reply.await) });
                offset += count as u64;
            }
            let (requested, count, reply) = pending
                .next()
                .await
                .ok_or_else(|| tool_error("write_file", "transfer progress queue is empty"))?;
            let reply = reply.map_err(remote_file_error)?;
            if !matches!(reply.response, RemoteResponse::ChunkWritten { offset: actual, length, .. }
                if actual == requested && length == count as u64)
            {
                return Err(tool_error("write_file", "chunk receipt is inconsistent"));
            }
            confirmed += count as u64;
            pipeline = next_pipeline(pipeline, reply.timing, self.client.process_capacity());
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
    async fn download_range(
        &self,
        transfer_id: String,
        offset: u64,
        count: usize,
    ) -> std::result::Result<(u64, usize, super::super::RemoteReply), RemoteDownloadError> {
        let reply = self
            .request(
                RemoteRequest::ReadFileChunk {
                    transfer_id,
                    offset,
                    max_bytes: count,
                },
                &[],
            )
            .await
            .map_err(|source| RemoteDownloadError::Read { offset, source })?;
        Ok((offset, count, reply))
    }
}

fn next_pipeline(current: usize, timing: super::super::RemoteRequestTiming, limit: usize) -> usize {
    // Start with one physical quantum. Only completed exchanges provide demand evidence;
    // abundant host RAM alone must never queue an entire file. The remote phase includes
    // per-handle IO serialization, so a backed-up disk naturally reduces future concurrency.
    let service = timing.remote.filesystem_micros.max(1);
    let overlap = timing.exchange_micros.div_ceil(service).max(1);
    usize::try_from(overlap)
        .unwrap_or(usize::MAX)
        .min(current.saturating_add(1))
        .min(limit.max(1))
}
