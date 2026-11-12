//! Shared close authority for native pipes. Public handles cannot keep a closed
//! executor's OS pipe or Windows job alive without polling again.
use std::{
    future::Future,
    io,
    pin::Pin,
    sync::{Arc, Mutex},
    task::{Context, Poll},
};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio_util::sync::CancellationToken;
type ReadIo = Pin<Box<dyn AsyncRead + Send>>;
type WriteIo = Pin<Box<dyn AsyncWrite + Send>>;
type ReadSlot = Arc<Mutex<Option<ReadIo>>>;
type WriteSlot = Arc<Mutex<Option<WriteIo>>>;
type Closed = Pin<Box<dyn Future<Output = ()> + Send>>;
pub(super) enum Control {
    Read(ReadSlot, CancellationToken),
    Write(WriteSlot, CancellationToken),
}
fn close_read(slot: &ReadSlot) {
    let io = slot
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    drop(io);
}
fn close_write(slot: &WriteSlot) {
    let io = slot
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    drop(io);
}
impl Control {
    pub fn close(&self) {
        match self {
            Self::Read(slot, closed) => {
                closed.cancel();
                close_read(slot);
            }
            Self::Write(slot, closed) => {
                closed.cancel();
                close_write(slot);
            }
        }
    }
}
pub(super) struct Reader {
    slot: ReadSlot,
    closed: Closed,
    finished: bool,
}
pub(super) struct Writer {
    slot: WriteSlot,
    closed: Closed,
}
pub(super) fn reader(
    io: impl AsyncRead + Send + 'static,
    closing: CancellationToken,
) -> (Reader, Control) {
    let slot = Arc::new(Mutex::new(Some(Box::pin(io) as ReadIo)));
    let closed = closing.child_token();
    (
        Reader {
            slot: slot.clone(),
            closed: Box::pin(closed.clone().cancelled_owned()),
            finished: false,
        },
        Control::Read(slot, closed),
    )
}
pub(super) fn writer(
    io: impl AsyncWrite + Send + 'static,
    closing: CancellationToken,
) -> (Writer, Control) {
    let slot = Arc::new(Mutex::new(Some(Box::pin(io) as WriteIo)));
    let closed = closing.child_token();
    (
        Writer {
            slot: slot.clone(),
            closed: Box::pin(closed.clone().cancelled_owned()),
        },
        Control::Write(slot, closed),
    )
}
impl Drop for Reader {
    fn drop(&mut self) {
        close_read(&self.slot);
    }
}
impl Drop for Writer {
    fn drop(&mut self) {
        close_write(&self.slot);
    }
}
impl AsyncRead for Reader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        output: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if self.finished {
            return Poll::Ready(Ok(()));
        }
        if self.closed.as_mut().poll(cx).is_ready() {
            close_read(&self.slot);
            return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
        }
        let mut held = self
            .slot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let before = output.filled().len();
        let capacity = output.remaining();
        let result = match held.as_mut() {
            Some(reader) => reader.as_mut().poll_read(cx, output),
            None => return Poll::Ready(Ok(())),
        };
        let released = if matches!(result, Poll::Ready(Err(_)))
            || (matches!(result, Poll::Ready(Ok(())))
                && capacity != 0
                && before == output.filled().len())
        {
            held.take()
        } else {
            None
        };
        let eof = matches!(result, Poll::Ready(Ok(())))
            && capacity != 0
            && before == output.filled().len();
        drop(held);
        drop(released);
        if eof {
            self.finished = true;
        }
        result
    }
}
impl AsyncWrite for Writer {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        if self.closed.as_mut().poll(cx).is_ready() {
            close_write(&self.slot);
            return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
        }
        match self
            .slot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_mut()
        {
            Some(writer) => writer.as_mut().poll_write(cx, bytes),
            None => Poll::Ready(Err(io::ErrorKind::BrokenPipe.into())),
        }
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        if self.closed.as_mut().poll(cx).is_ready() {
            return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
        }
        match self
            .slot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_mut()
        {
            Some(writer) => writer.as_mut().poll_flush(cx),
            None => Poll::Ready(Ok(())),
        }
    }
    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let mut held = self
            .slot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let result = match held.as_mut() {
            Some(writer) => writer.as_mut().poll_shutdown(cx),
            None => return Poll::Ready(Ok(())),
        };
        let released = if result.is_ready() { held.take() } else { None };
        drop(held);
        drop(released);
        result
    }
}
