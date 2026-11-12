//! Bounded raw h2 byte streams. Only bytes delivered to AsyncRead release credit.
use std::{
    io,
    pin::Pin,
    sync::{Arc, Mutex},
    task::{Context, Poll},
};

use bytes::Bytes;
use h2::{FlowControl, RecvStream, SendStream};
use tokio::{
    io::{AsyncRead, AsyncWriteExt, ReadBuf},
    sync::watch,
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

pub(crate) const WINDOW: u32 = 64 * 1024;
pub(crate) const CONNECTION_WINDOW: u32 = 32 * 1024 * 1024;
pub(crate) const STREAMS: u32 = 256;
pub(crate) const ORDINARY: usize = 240;
pub(crate) const CONTROL: usize = 16;
pub(crate) const DESCRIPTOR_LIMIT: usize = 1024 * 1024;

pub(crate) type Permit = Arc<tokio::sync::OwnedSemaphorePermit>;
pub(crate) type Reset = Arc<Mutex<SendStream<Bytes>>>;
pub(crate) enum ResetOwner {
    Send(Reset),
    Response(Arc<Mutex<h2::server::SendResponse<Bytes>>>),
}
impl ResetOwner {
    fn cancel(&self) {
        match self {
            Self::Send(stream) => stream
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .send_reset(h2::Reason::CANCEL),
            Self::Response(stream) => stream
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .send_reset(h2::Reason::CANCEL),
        }
    }
}
impl From<Reset> for ResetOwner {
    fn from(value: Reset) -> Self {
        Self::Send(value)
    }
}
pub(crate) type Trailers = watch::Receiver<Option<Result<http::HeaderMap, String>>>;

pub(crate) struct BodyReader {
    reader: tokio::io::DuplexStream,
    flow: FlowControl,
    done: Trailers,
    cancel: CancellationToken,
    reset: ResetOwner,
    finished: bool,
    pending_error: Option<String>,
    _permit: Option<Permit>,
}

impl Drop for BodyReader {
    fn drop(&mut self) {
        if !self.finished {
            self.reset.cancel();
        }
        self.cancel.cancel();
    }
}

impl AsyncRead for BodyReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        output: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if let Some(error) = self.pending_error.take() {
            return Poll::Ready(Err(io::Error::other(error)));
        }
        let before = output.filled().len();
        let capacity = output.remaining();
        let result = Pin::new(&mut self.reader).poll_read(cx, output);
        if let Poll::Ready(Ok(())) = &result {
            let delivered = output.filled().len() - before;
            if delivered != 0 {
                if let Err(error) = self.flow.release_capacity(delivered) {
                    self.pending_error = Some(error.to_string());
                }
            } else if capacity != 0 {
                self.finished = true;
                let terminal = self.done.borrow().clone();
                return Poll::Ready(match terminal {
                    Some(Ok(_)) => Ok(()),
                    Some(Err(error)) => Err(io::Error::other(error)),
                    None => Err(io::Error::new(
                        io::ErrorKind::UnexpectedEof,
                        "h2 receive owner ended without a terminal result",
                    )),
                });
            }
        }
        result
    }
}

pub(crate) fn receive(
    mut body: RecvStream,
    reset: ResetOwner,
    tasks: &TaskTracker,
    closing: CancellationToken,
    permit: Option<Permit>,
) -> (BodyReader, Trailers) {
    let flow = body.flow_control().clone();
    let (mut writer, reader) = tokio::io::duplex(WINDOW as usize);
    let (send, done) = watch::channel(None);
    let cancel = CancellationToken::new();
    let stopped = cancel.clone();
    let held = permit.clone();
    tasks.spawn(async move {
        let _permit = held;
        let work = async {
            while let Some(data) = body.data().await {
                writer.write_all(&data.map_err(io::Error::other)?).await?;
            }
            body.trailers()
                .await
                .map(|trailers| trailers.unwrap_or_default())
                .map_err(io::Error::other)
        };
        let result: io::Result<http::HeaderMap> = tokio::select! {
            result = work => result,
            _ = stopped.cancelled() => Err(io::ErrorKind::Interrupted.into()),
            _ = closing.cancelled() => Err(io::ErrorKind::BrokenPipe.into()),
        };
        send.send_replace(Some(result.map_err(|error| error.to_string())));
    });
    (
        BodyReader {
            reader,
            flow,
            done: done.clone(),
            cancel,
            reset,
            finished: false,
            pending_error: None,
            _permit: permit,
        },
        done,
    )
}

pub(crate) async fn send(
    stream: &mut SendStream<Bytes>,
    mut bytes: Bytes,
    end: bool,
    cancel: &CancellationToken,
) -> io::Result<()> {
    if bytes.is_empty() {
        if end {
            stream.send_data(bytes, true).map_err(io::Error::other)?;
        }
        return Ok(());
    }
    while !bytes.is_empty() {
        stream.reserve_capacity(bytes.len());
        let capacity = tokio::select! {
            _ = cancel.cancelled() => return Err(io::ErrorKind::Interrupted.into()),
            capacity = futures::future::poll_fn(|cx| stream.poll_capacity(cx)) => capacity.ok_or(io::ErrorKind::BrokenPipe)?.map_err(io::Error::other)?,
        };
        let length = bytes.len().min(capacity);
        if length == 0 {
            continue;
        }
        let data = bytes.split_to(length);
        stream
            .send_data(data, end && bytes.is_empty())
            .map_err(io::Error::other)?;
    }
    Ok(())
}

pub(crate) async fn collect(mut body: RecvStream, limit: usize) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    while let Some(data) = body.data().await {
        let data = data.map_err(io::Error::other)?;
        if data.len() > limit.saturating_sub(bytes.len()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "bounded response exceeded its limit",
            ));
        }
        bytes.extend_from_slice(&data);
        body.flow_control()
            .release_capacity(data.len())
            .map_err(io::Error::other)?;
    }
    body.trailers().await.map_err(io::Error::other)?;
    Ok(bytes)
}

pub(crate) fn encode_descriptor<S: serde::Serialize>(descriptor: &S) -> io::Result<Vec<u8>> {
    let bytes = serde_json::to_vec(descriptor).map_err(io::Error::other)?;
    if bytes.len() > DESCRIPTOR_LIMIT {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "descriptor exceeds 1 MiB",
        ));
    }
    let mut encoded = Vec::with_capacity(4 + bytes.len());
    encoded.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
    encoded.extend_from_slice(&bytes);
    Ok(encoded)
}

pub(crate) async fn read_descriptor<R: AsyncRead + Unpin, S: serde::de::DeserializeOwned>(
    reader: &mut R,
) -> io::Result<S> {
    use tokio::io::AsyncReadExt;
    let length = reader.read_u32().await? as usize;
    if length > DESCRIPTOR_LIMIT {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "descriptor exceeds 1 MiB",
        ));
    }
    let mut bytes = vec![0; length];
    reader.read_exact(&mut bytes).await?;
    serde_json::from_slice(&bytes).map_err(io::Error::other)
}
