//! Cursor-only inspection budget and cancellation; no container fields are interpreted here.
use std::io::{self, Cursor, Read, Seek, SeekFrom};
use tokio_util::sync::CancellationToken;

pub(super) struct ProbeReader<'a> {
    cursor: Cursor<&'a [u8]>,
    remaining_bytes: u64,
    remaining_operations: u64,
    exhausted: bool,
    cancellation: CancellationToken,
}

impl<'a> ProbeReader<'a> {
    pub(super) fn new(bytes: &'a [u8], cancellation: CancellationToken) -> Self {
        Self {
            cursor: Cursor::new(bytes),
            remaining_bytes: (bytes.len() as u64).saturating_mul(8).saturating_add(4096),
            remaining_operations: 1_000_000,
            exhausted: false,
            cancellation,
        }
    }

    pub(super) fn check(&self) -> anyhow::Result<()> {
        if self.cancellation.is_cancelled() {
            return Err(super::InspectionCancelled.into());
        }
        anyhow::ensure!(!self.exhausted, "attachment inspection IO budget exhausted");
        Ok(())
    }

    fn operation(&mut self) -> io::Result<()> {
        // read_exact/io::copy retry Interrupted indefinitely. Cancellation must end
        // the library read; check() translates it to our typed cancellation result.
        if self.cancellation.is_cancelled() {
            return Err(io::Error::other("attachment inspection cancelled"));
        }
        if self.remaining_operations == 0 {
            self.exhausted = true;
            return Err(io::Error::other(
                "attachment inspection IO operation budget exhausted",
            ));
        }
        self.remaining_operations -= 1;
        Ok(())
    }
}

impl Read for ProbeReader<'_> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        self.operation()?;
        let available = (self.cursor.get_ref().len() as u64).saturating_sub(self.cursor.position());
        if !buffer.is_empty() && available > 0 && self.remaining_bytes == 0 {
            self.exhausted = true;
            return Err(io::Error::other(
                "attachment inspection byte budget exhausted",
            ));
        }
        let limit = buffer
            .len()
            .min(usize::try_from(self.remaining_bytes).unwrap_or(usize::MAX));
        let read = self.cursor.read(&mut buffer[..limit])?;
        self.remaining_bytes -= read as u64;
        Ok(read)
    }
}

impl Seek for ProbeReader<'_> {
    fn seek(&mut self, position: SeekFrom) -> io::Result<u64> {
        self.operation()?;
        let end = self.cursor.get_ref().len() as i128;
        let target = match position {
            SeekFrom::Start(value) => i128::from(value),
            SeekFrom::End(offset) => end + i128::from(offset),
            SeekFrom::Current(offset) => i128::from(self.cursor.position()) + i128::from(offset),
        };
        if target < 0 || target > end {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "media element is outside the input snapshot",
            ));
        }
        self.cursor.seek(SeekFrom::Start(
            u64::try_from(target).map_err(io::Error::other)?,
        ))
    }
}
