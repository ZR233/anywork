//! Adapter that presents the two halves of one stdio channel as a single duplex I/O.

use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

use crate::remote_transport::progress::Progress;

/// One physical channel made of an independent reader and writer.
///
/// The SSH stdio channel hands both directions over separately, while the multiplexer
/// wants one duplex object. This adapter is the only adaptation layer: it forwards I/O
/// verbatim and records real byte progress for heartbeat and lease decisions.
#[derive(Debug)]
pub(crate) struct Duplex<R, W> {
    reader: R,
    writer: W,
    progress: Arc<Progress>,
}

impl<R, W> Duplex<R, W> {
    pub(crate) fn new(reader: R, writer: W, progress: Arc<Progress>) -> Self {
        Self {
            reader,
            writer,
            progress,
        }
    }
}

impl<R, W> AsyncRead for Duplex<R, W>
where
    R: AsyncRead + Unpin,
    W: Unpin,
{
    fn poll_read(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let before = buffer.filled().len();
        match Pin::new(&mut this.reader).poll_read(context, buffer) {
            Poll::Ready(Ok(())) => {
                if buffer.filled().len() > before {
                    this.progress.touch();
                }
                Poll::Ready(Ok(()))
            }
            other => other,
        }
    }
}

impl<R, W> AsyncWrite for Duplex<R, W>
where
    R: Unpin,
    W: AsyncWrite + Unpin,
{
    fn poll_write(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        data: &[u8],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        match Pin::new(&mut this.writer).poll_write(context, data) {
            Poll::Ready(Ok(written)) => {
                if written > 0 {
                    this.progress.touch();
                }
                Poll::Ready(Ok(written))
            }
            other => other,
        }
    }

    fn poll_flush(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().writer).poll_flush(context)
    }

    fn poll_shutdown(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().writer).poll_shutdown(context)
    }
}
