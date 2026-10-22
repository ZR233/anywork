//! 文件读写流：从同一打开的普通文件句柄分块传输，长度与偏移全部使用 `u64`。
//!
//! 读取方只有在校验到与声明一致的 `transferred` 终结后才报告 EOF；上传方从调用方 reader
//! 增量取块，缺结束记录或短读都不会发布半文件。

use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use futures::FutureExt;
use futures::future::BoxFuture;
use pl_protocol::remote::{
    RemoteFileMetadata, RemoteMessage, RemoteReadRequest, RemoteRequest, RemoteResponse,
    RemoteWriteRequest,
};
use pl_remote_helper::remote_transport::{
    DATA_CHUNK_BYTES, RecordReader, RecordWriter, RemoteRecord, RemoteStream,
};
use tokio::io::{AsyncRead, AsyncReadExt, ReadBuf, ReadHalf, WriteHalf};
use tokio::sync::Mutex;

use super::super::error::RemoteClientError;
use super::session::{
    OperationStream, StreamLease, StreamOwnership, message_kind, read_record, response_kind,
    response_record,
};

/// One file read stream; `AsyncRead` yields exactly the declared range and then a verified EOF.
pub struct RemoteFileReader {
    metadata: RemoteFileMetadata,
    /// Dropped as soon as the stream reached its terminal state, releasing reader/writer,
    /// workspace handle and physical permit.
    state: Option<Arc<Mutex<FileStreamState>>>,
    pending: Option<BoxFuture<'static, Result<Option<Vec<u8>>, RemoteClientError>>>,
    buffer: Vec<u8>,
    position: usize,
    finished: bool,
    /// First unrecoverable failure; every later poll reports it instead of a normal EOF.
    failure: Option<RemoteClientError>,
}

impl std::fmt::Debug for RemoteFileReader {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RemoteFileReader")
            .field("offset", &self.metadata.offset)
            .field("total_len", &self.metadata.total_len)
            .field("transfer_len", &self.metadata.transfer_len)
            .field("finished", &self.finished)
            .field("failed", &self.failure.is_some())
            .finish_non_exhaustive()
    }
}

impl RemoteFileReader {
    /// The declared range of this read stream: start offset, file length and transfer length.
    pub fn metadata(&self) -> &RemoteFileMetadata {
        &self.metadata
    }
}

struct FileStreamState {
    reader: RecordReader<ReadHalf<RemoteStream>>,
    _writer: RecordWriter<WriteHalf<RemoteStream>>,
    ownership: StreamOwnership,
    metadata: RemoteFileMetadata,
    /// Absolute offset of the next expected `data` record.
    received: u64,
    verified: bool,
}

/// Opens one file read stream after validating its metadata against the request and the file.
pub(super) async fn open(
    lease: StreamLease,
    request: RemoteReadRequest,
) -> Result<RemoteFileReader, RemoteClientError> {
    let expected_offset = request.offset;
    let requested_range = request.max_bytes;
    let mut stream = lease.open_stream().await?;
    stream
        .send_request(RemoteRequest::ReadFile(request))
        .await?;
    let record = stream.read().await?;
    let metadata = match response_record(record, "read file")? {
        RemoteResponse::File(metadata) => metadata,
        response => {
            return Err(RemoteClientError::protocol(format!(
                "expected file metadata, received {}",
                response_kind(&response)
            )));
        }
    };
    if metadata.offset != expected_offset {
        return Err(RemoteClientError::protocol(format!(
            "helper opened the file at offset {} instead of the requested {expected_offset}",
            metadata.offset
        )));
    }
    let remaining = metadata
        .total_len
        .checked_sub(metadata.offset)
        .ok_or_else(|| {
            RemoteClientError::protocol("file metadata offset is past the declared file length")
        })?;
    let requested = requested_range.unwrap_or(remaining).min(remaining);
    if metadata.transfer_len != requested {
        return Err(RemoteClientError::protocol(format!(
            "helper declared {} transferred bytes where exactly {requested} were requested",
            metadata.transfer_len
        )));
    }
    Ok(RemoteFileReader::new(stream, metadata))
}

impl RemoteFileReader {
    fn new(stream: OperationStream, metadata: RemoteFileMetadata) -> Self {
        let parts = stream.into_parts();
        let state = FileStreamState {
            reader: parts.reader,
            _writer: parts.writer,
            ownership: parts.ownership,
            metadata: metadata.clone(),
            received: metadata.offset,
            verified: false,
        };
        Self {
            metadata,
            state: Some(Arc::new(Mutex::new(state))),
            pending: None,
            buffer: Vec::new(),
            position: 0,
            finished: false,
            failure: None,
        }
    }
}

impl AsyncRead for RemoteFileReader {
    fn poll_read(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if let Some(failure) = &this.failure {
            return Poll::Ready(Err(file_io_error(failure.clone())));
        }
        if buffer.remaining() == 0 {
            // No capacity for even one byte: never consume a record or touch the network.
            return Poll::Ready(Ok(()));
        }
        loop {
            if this.position < this.buffer.len() {
                let available = &this.buffer[this.position..];
                let take = available.len().min(buffer.remaining());
                buffer.put_slice(&available[..take]);
                this.position += take;
                return Poll::Ready(Ok(()));
            }
            if this.finished {
                return Poll::Ready(Ok(()));
            }
            if this.pending.is_none() {
                let state = this.state.clone();
                this.pending = Some(
                    async move {
                        match state {
                            Some(state) => step(&state).await,
                            None => Ok(None),
                        }
                    }
                    .boxed(),
                );
            }
            let pending = this
                .pending
                .as_mut()
                .expect("a file read step was just installed");
            match std::future::Future::poll(pending.as_mut(), context) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Ok(Some(bytes))) => {
                    this.pending = None;
                    this.buffer = bytes;
                    this.position = 0;
                }
                Poll::Ready(Ok(None)) => {
                    this.pending = None;
                    this.buffer = Vec::new();
                    this.position = 0;
                    this.finished = true;
                    this.state = None;
                    return Poll::Ready(Ok(()));
                }
                Poll::Ready(Err(error)) => {
                    this.pending = None;
                    this.buffer = Vec::new();
                    this.position = 0;
                    this.finished = true;
                    this.state = None;
                    let mapped = file_io_error(error.clone());
                    this.failure = Some(error);
                    return Poll::Ready(Err(mapped));
                }
            }
        }
    }
}

/// Reads one or more records until a data chunk or the verified end of the transfer.
async fn step(state: &Arc<Mutex<FileStreamState>>) -> Result<Option<Vec<u8>>, RemoteClientError> {
    // The lock is held only by this reader's own step future; it makes the record reader usable
    // from a poll-based `AsyncRead` without ever canceling a half-read record.
    let mut state = state.lock().await;
    loop {
        let FileStreamState {
            reader,
            ownership,
            metadata,
            received,
            verified,
            ..
        } = &mut *state;
        let record = read_record(reader, ownership.client(), "read file").await?;
        let Some(record) = record else {
            return if *verified {
                Ok(None)
            } else {
                Err(RemoteClientError::protocol(
                    "remote file stream ended before its transfer confirmation",
                ))
            };
        };
        let RemoteRecord { message, body } = record;
        match message {
            RemoteMessage::Data { offset } => {
                let length = body.len() as u64;
                if offset != *received {
                    return Err(RemoteClientError::protocol(format!(
                        "remote file chunk offset {offset} is not the expected {received}"
                    )));
                }
                if length == 0 {
                    continue;
                }
                if length > DATA_CHUNK_BYTES as u64 {
                    return Err(RemoteClientError::protocol(format!(
                        "remote file chunk of {length} bytes exceeds the chunk budget"
                    )));
                }
                let end = received
                    .checked_add(length)
                    .ok_or_else(|| RemoteClientError::protocol("remote file offset overflowed"))?;
                if end > metadata.offset + metadata.transfer_len {
                    return Err(RemoteClientError::protocol(
                        "remote file stream exceeded its declared transfer length",
                    ));
                }
                *received = end;
                return Ok(Some(body.to_vec()));
            }
            RemoteMessage::Response(RemoteResponse::Transferred { bytes }) => {
                if *verified {
                    return Err(RemoteClientError::protocol(
                        "remote file stream confirmed the transfer twice",
                    ));
                }
                let expected_end = metadata.offset + metadata.transfer_len;
                if bytes != metadata.transfer_len || *received != expected_end {
                    return Err(RemoteClientError::protocol(format!(
                        "remote file transfer ended after {received} of {expected_end} bytes (confirmed {bytes})"
                    )));
                }
                *verified = true;
                return Ok(None);
            }
            RemoteMessage::Response(RemoteResponse::Error(error)) => {
                return Err(RemoteClientError::remote(&error));
            }
            other => {
                return Err(RemoteClientError::protocol(format!(
                    "unexpected {} in a file read stream",
                    message_kind(&other)
                )));
            }
        }
    }
}

/// Uploads exactly `request.total_len` bytes and returns the helper-confirmed length.
pub(super) async fn upload<R>(
    lease: StreamLease,
    request: RemoteWriteRequest,
    reader: &mut R,
) -> Result<u64, RemoteClientError>
where
    R: AsyncRead + Unpin + Send,
{
    let total_len = request.total_len;
    let mut stream = lease.open_stream().await?;
    stream
        .send_request(RemoteRequest::WriteFile(request))
        .await?;
    match response_record(stream.read().await?, "write file")? {
        RemoteResponse::Ready => {}
        response => {
            return Err(RemoteClientError::protocol(format!(
                "expected a ready receipt, received {}",
                response_kind(&response)
            )));
        }
    }
    let mut buffer = vec![0_u8; DATA_CHUNK_BYTES];
    let mut offset = 0_u64;
    // The source reader is consumed only up to the declared length.
    while offset < total_len {
        let wanted = (total_len - offset).min(DATA_CHUNK_BYTES as u64) as usize;
        let mut filled = 0_usize;
        while filled < wanted {
            let count = reader.read(&mut buffer[filled..wanted]).await?;
            if count == 0 {
                break;
            }
            filled += count;
        }
        if filled == 0 {
            return Err(RemoteClientError::protocol(format!(
                "upload source ended after {offset} of {total_len} bytes"
            )));
        }
        stream
            .send(&RemoteMessage::Data { offset }, &buffer[..filled])
            .await?;
        offset += filled as u64;
    }
    stream
        .send(&RemoteMessage::UploadFinished { total_len }, &[])
        .await?;
    match response_record(stream.read().await?, "write file")? {
        RemoteResponse::Transferred { bytes } if bytes == total_len => Ok(bytes),
        RemoteResponse::Transferred { bytes } => Err(RemoteClientError::protocol(format!(
            "helper confirmed {bytes} of {total_len} uploaded bytes"
        ))),
        response => Err(RemoteClientError::protocol(format!(
            "expected a transfer receipt, received {}",
            response_kind(&response)
        ))),
    }
}

/// Keeps the typed remote failure as the `io::Error` source instead of a flattened string.
fn file_io_error(error: RemoteClientError) -> io::Error {
    let kind = match &error {
        RemoteClientError::Disconnected | RemoteClientError::ManagerClosing => {
            io::ErrorKind::BrokenPipe
        }
        RemoteClientError::Cancelled => io::ErrorKind::Interrupted,
        _ => io::ErrorKind::Other,
    };
    io::Error::new(kind, error)
}
