use super::*;
use crate::test_support::{PUBLIC_KEY, SIGNATURE, update};

struct InterruptedChunks {
    remaining: &'static [u8],
    interrupt: bool,
}

impl Read for InterruptedChunks {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if std::mem::take(&mut self.interrupt) {
            return Err(io::ErrorKind::Interrupted.into());
        }
        let limit = buffer.len().min(2);
        self.remaining.read(&mut buffer[..limit])
    }
}

#[test]
fn streaming_verification_checks_size_hash_and_signature_and_retries_interrupted_reads() {
    let asset = update(b"test").installer;
    verify(
        InterruptedChunks {
            remaining: b"test",
            interrupt: true,
        },
        &asset,
        PUBLIC_KEY,
        SIGNATURE,
    )
    .unwrap();
    for (bytes, metadata, expected) in [
        (
            b"tes".as_slice(),
            asset.clone(),
            StudioUpdateErrorCode::DownloadIncomplete,
        ),
        (
            b"tests".as_slice(),
            asset.clone(),
            StudioUpdateErrorCode::DownloadIncomplete,
        ),
        (
            b"Test".as_slice(),
            asset,
            StudioUpdateErrorCode::HashMismatch,
        ),
        (
            b"Test".as_slice(),
            update(b"Test").installer,
            StudioUpdateErrorCode::SignatureInvalid,
        ),
    ] {
        assert_eq!(
            verify(bytes, &metadata, PUBLIC_KEY, SIGNATURE)
                .unwrap_err()
                .code(),
            expected
        );
    }
}
