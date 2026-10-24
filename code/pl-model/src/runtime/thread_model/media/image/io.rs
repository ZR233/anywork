//! Cancellable memory IO for official image decoders/encoders; no image fields are parsed here.
use std::io::{self, Cursor, Read, Seek, SeekFrom, Write};
use std::sync::Arc;
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
pub(super) struct ImageCancellation {
    pub owner: CancellationToken,
    pub request: CancellationToken,
}
impl ImageCancellation {
    pub fn check(&self) -> Result<(), pl_core::model::ModelError> {
        if self.owner.is_cancelled() || self.request.is_cancelled() {
            return Err(super::cancelled());
        }
        Ok(())
    }
    fn io_check(&self) -> io::Result<()> {
        if self.owner.is_cancelled() || self.request.is_cancelled() {
            // read_exact retries Interrupted; cancellation must not use that error kind.
            return Err(io::Error::other("image preparation cancelled"));
        }
        Ok(())
    }
}

pub(super) struct ImageReader {
    cursor: Cursor<Arc<[u8]>>,
    cancellation: ImageCancellation,
}
impl ImageReader {
    pub fn new(bytes: Arc<[u8]>, cancellation: ImageCancellation) -> Self {
        Self {
            cursor: Cursor::new(bytes),
            cancellation,
        }
    }
}
impl Read for ImageReader {
    fn read(&mut self, output: &mut [u8]) -> io::Result<usize> {
        self.cancellation.io_check()?;
        self.cursor.read(output)
    }
}
impl Seek for ImageReader {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.cancellation.io_check()?;
        self.cursor.seek(position)
    }
}

pub(super) struct ImageWriter {
    cursor: Cursor<Vec<u8>>,
    cancellation: ImageCancellation,
    limit: u64,
    pub limit_exceeded: bool,
}
impl ImageWriter {
    pub fn new(cancellation: ImageCancellation, limit: u64) -> Self {
        Self {
            cursor: Cursor::new(Vec::new()),
            cancellation,
            limit,
            limit_exceeded: false,
        }
    }
    pub fn into_bytes(self) -> Vec<u8> {
        self.cursor.into_inner()
    }
}
impl Write for ImageWriter {
    fn write(&mut self, input: &[u8]) -> io::Result<usize> {
        self.cancellation.io_check()?;
        let end = self
            .cursor
            .position()
            .checked_add(input.len() as u64)
            .ok_or_else(|| io::Error::other("image output size overflow"))?;
        if end > self.limit {
            self.limit_exceeded = true;
            return Err(io::Error::other(
                "image candidate exceeds native byte limit",
            ));
        }
        let end = usize::try_from(end).map_err(io::Error::other)?;
        let additional = end.saturating_sub(self.cursor.get_ref().len());
        self.cursor
            .get_mut()
            .try_reserve_exact(additional)
            .map_err(io::Error::other)?;
        self.cursor.write(input)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.cancellation.io_check()
    }
}
impl Seek for ImageWriter {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.cancellation.io_check()?;
        self.cursor.seek(position)
    }
}
