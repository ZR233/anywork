//! Resident bytes kept by host consumers, charged until ownership leaves the remote adapter.
use pl_remote_helper::budget::{ByteLease, ResourceBudget};
use std::{
    io,
    pin::Pin,
    task::{Context, Poll},
};
use tokio::io::AsyncWrite;

pub(in crate::remote) struct ResidentBuffer {
    bytes: Vec<u8>,
    memory: ByteLease,
    limit: usize,
}
impl ResidentBuffer {
    pub(super) fn new(budget: &ResourceBudget, limit: usize) -> io::Result<Self> {
        let memory = budget.try_reserve(0).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::OutOfMemory,
                "consumer resource admission unavailable",
            )
        })?;
        Ok(Self {
            bytes: Vec::new(),
            memory,
            limit,
        })
    }
    pub(in crate::remote) fn into_bytes(self) -> Vec<u8> {
        self.bytes
    }
}
impl AsyncWrite for ResidentBuffer {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        let size = self.bytes.len().saturating_add(bytes.len());
        if size > self.limit {
            return Poll::Ready(Err(io::Error::new(
                io::ErrorKind::OutOfMemory,
                "consumer exceeds its resource grant",
            )));
        }
        if size > self.bytes.capacity() {
            let capacity = size
                .max(self.bytes.capacity().saturating_mul(2))
                .min(self.limit);
            // Charge the peak during a possible reallocation, then retain the actual capacity.
            let previous = self.bytes.capacity();
            if !self.memory.resize(previous.saturating_add(capacity)) {
                return Poll::Ready(Err(io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "host resident-byte grant exhausted",
                )));
            }
            let additional = capacity - self.bytes.len();
            if let Err(error) = self.bytes.try_reserve_exact(additional) {
                self.memory.resize(previous);
                return Poll::Ready(Err(io::Error::other(error)));
            }
            let capacity = self.bytes.capacity();
            self.memory.resize(capacity);
        }
        self.bytes.extend_from_slice(bytes);
        Poll::Ready(Ok(bytes.len()))
    }
    fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}
