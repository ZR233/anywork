//! One streaming verification path for downloaded, cached and leased installers.
use std::io::{self, Read};

use minisign_verify::{PublicKey, Signature};
use sha2::{Digest, Sha256};

use crate::{StudioUpdateAsset, StudioUpdateError, StudioUpdateErrorCode};

pub(super) fn verify(
    mut reader: impl Read,
    asset: &StudioUpdateAsset,
    public_key: &str,
    signature_text: &str,
) -> Result<(), StudioUpdateError> {
    let key = PublicKey::decode(public_key).map_err(signature_error)?;
    let signature = Signature::decode(signature_text).map_err(signature_error)?;
    let mut verifier = key.verify_stream(&signature).map_err(signature_error)?;
    let mut hasher = Sha256::new();
    let mut length = 0_u64;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = match reader.read(&mut buffer) {
            Ok(0) => break,
            Ok(count) => count,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(crate::error::io_error(error)),
        };
        // The manifest's bounded size is enforced during the scan, including for
        // cached files that another process may have replaced or extended.
        if count as u64 > asset.size.saturating_sub(length) {
            return Err(size_error());
        }
        length += count as u64;
        hasher.update(&buffer[..count]);
        verifier.update(&buffer[..count]);
    }
    if length != asset.size {
        return Err(size_error());
    }
    if hex::encode(hasher.finalize()) != asset.sha256 {
        return Err(StudioUpdateError::new(
            StudioUpdateErrorCode::HashMismatch,
            "installer SHA-256 does not match the manifest",
        ));
    }
    verifier.finalize().map_err(signature_error)
}

fn size_error() -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::DownloadIncomplete,
        "installer size does not match the manifest",
    )
}

fn signature_error(error: minisign_verify::Error) -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::SignatureInvalid,
        format!("Minisign verification failed: {error}"),
    )
}

#[cfg(test)]
mod tests {
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
}
