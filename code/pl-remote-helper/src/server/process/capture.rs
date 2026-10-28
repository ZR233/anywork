//! One raw dual-stream writer and shared budget; confirmed offsets freeze at the first fault.
use crate::path::{io_error, remote_error};
use pl_protocol::remote::{
    RemoteCapture, RemoteCaptureReceipt, RemoteError, RemoteErrorCode, RemoteOutputStream,
};
use std::path::Path;
use tokio::io::AsyncWriteExt;

pub(super) enum Capture {
    None,
    Files {
        stdout: Box<tokio::fs::File>,
        stderr: Box<tokio::fs::File>,
        receipt: RemoteCaptureReceipt,
        failed: bool,
    },
}

pub(super) enum Acceptance {
    Accepted,
    Refused,
}

impl Capture {
    pub(super) async fn prepare(
        policy: &RemoteCapture,
        paths: Option<(&Path, &Path)>,
    ) -> Result<Self, RemoteError> {
        match (policy, paths) {
            (RemoteCapture::None, None) => Ok(Self::None),
            (RemoteCapture::Files { limit_bytes, .. }, Some((stdout, stderr))) => {
                if *limit_bytes == 0 || stdout == stderr {
                    return Err(remote_error(
                        RemoteErrorCode::InvalidRequest,
                        "capture requires a positive shared budget and distinct stream paths",
                    ));
                }
                for path in [stdout, stderr] {
                    if let Some(parent) = path.parent() {
                        tokio::fs::create_dir_all(parent)
                            .await
                            .map_err(|e| io_error("create capture directory", e))?;
                    }
                }
                let stdout = crate::server::regular_file::create(stdout.to_owned())
                    .await
                    .map_err(|e| io_error("create stdout capture", e))?;
                let stderr = crate::server::regular_file::create(stderr.to_owned())
                    .await
                    .map_err(|e| io_error("create stderr capture", e))?;
                Ok(Self::Files {
                    stdout: Box::new(stdout),
                    stderr: Box::new(stderr),
                    failed: false,
                    receipt: RemoteCaptureReceipt {
                        limit_bytes: *limit_bytes,
                        stdout_confirmed_bytes: 0,
                        stderr_confirmed_bytes: 0,
                        captured_bytes: 0,
                        charged_bytes: 0,
                        refused_bytes: 0,
                    },
                })
            }
            _ => Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "capture policy and resolved paths disagree",
            )),
        }
    }

    pub(super) async fn append(
        &mut self,
        stream: RemoteOutputStream,
        body: &[u8],
    ) -> Result<Acceptance, RemoteError> {
        let Self::Files {
            stdout,
            stderr,
            receipt,
            failed,
        } = self
        else {
            return Ok(Acceptance::Accepted);
        };
        let cost = body.len() as u64;
        if *failed {
            return Ok(Acceptance::Refused);
        }
        if receipt.refused_bytes > 0 || cost > receipt.limit_bytes - receipt.charged_bytes {
            receipt.refused_bytes = receipt.refused_bytes.saturating_add(cost);
            return Ok(Acceptance::Refused);
        }
        receipt.captured_bytes += cost;
        receipt.charged_bytes += cost;
        let (file, confirmed) = match stream {
            RemoteOutputStream::Stdout => (stdout, &mut receipt.stdout_confirmed_bytes),
            RemoteOutputStream::Stderr => (stderr, &mut receipt.stderr_confirmed_bytes),
        };
        // Tokio file writes may complete in blocking IO. Flush before advancing the trusted prefix.
        if let Err(error) = file.write_all(body).await {
            *failed = true;
            return Err(remote_error(
                RemoteErrorCode::CaptureWrite,
                error.to_string(),
            ));
        }
        if let Err(error) = file.flush().await {
            *failed = true;
            return Err(remote_error(
                RemoteErrorCode::CaptureFlush,
                error.to_string(),
            ));
        }
        *confirmed += cost;
        Ok(Acceptance::Accepted)
    }

    pub(super) async fn flush(&mut self) -> Result<(), RemoteError> {
        let Self::Files {
            stdout,
            stderr,
            failed,
            ..
        } = self
        else {
            return Ok(());
        };
        if *failed {
            return Ok(());
        }
        for file in [stdout, stderr] {
            if let Err(error) = file.flush().await {
                *failed = true;
                return Err(remote_error(
                    RemoteErrorCode::CaptureFlush,
                    error.to_string(),
                ));
            }
        }
        Ok(())
    }
    pub(super) fn receipt(&self) -> Option<RemoteCaptureReceipt> {
        match self {
            Self::None => None,
            Self::Files { receipt, .. } => Some(*receipt),
        }
    }
}
