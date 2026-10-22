//! A generated stream with an explicit pause point for deterministic SSH replacement.
use std::{
    future::Future,
    io,
    pin::Pin,
    task::{Context, Poll},
};
use tokio::{
    io::{AsyncRead, ReadBuf},
    sync::oneshot,
};

pub struct GatedPattern {
    position: u64,
    length: u64,
    gate: u64,
    reached: Option<oneshot::Sender<()>>,
    resume: Option<oneshot::Receiver<()>>,
}
impl GatedPattern {
    pub fn new(length: u64, reached: oneshot::Sender<()>, resume: oneshot::Receiver<()>) -> Self {
        Self {
            position: 0,
            length,
            gate: length / 2,
            reached: Some(reached),
            resume: Some(resume),
        }
    }
}
impl AsyncRead for GatedPattern {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if self.position == self.length {
            return Poll::Ready(Ok(()));
        }
        if self.position == self.gate {
            if let Some(reached) = self.reached.take() {
                let _ = reached.send(());
            }
            if let Some(resume) = &mut self.resume {
                match Pin::new(resume).poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Err(_)) => {
                        return Poll::Ready(Err(io::Error::new(
                            io::ErrorKind::Interrupted,
                            "transfer fixture cancelled",
                        )));
                    }
                    Poll::Ready(Ok(())) => self.resume = None,
                }
            }
        }
        let end = if self.position < self.gate {
            self.gate
        } else {
            self.length
        };
        let count = (end - self.position).min(bytes.remaining() as u64) as usize;
        bytes.initialize_unfilled_to(count).fill(0xa5);
        bytes.advance(count);
        self.position += count as u64;
        Poll::Ready(Ok(()))
    }
}
