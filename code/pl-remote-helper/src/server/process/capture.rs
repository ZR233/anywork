//! 捕获文件的唯一写入者；预算、头部、块标签与终态计量位于同一生命周期。
use crate::path::{io_error, remote_error};
use pl_protocol::remote::{
    RemoteCapture, RemoteCaptureReceipt, RemoteError, RemoteErrorCode, RemoteOutputStream,
};
use std::path::Path;
use tokio::io::AsyncWriteExt;

pub(super) enum Capture {
    None,
    File {
        file: tokio::fs::File,
        receipt: RemoteCaptureReceipt,
    },
}

pub(super) enum Acceptance {
    Accepted,
    Refused,
}

impl Capture {
    pub(super) async fn prepare(
        policy: &RemoteCapture,
        path: Option<&Path>,
        command: &str,
        cwd: &Path,
    ) -> Result<Self, RemoteError> {
        match (policy, path) {
            (RemoteCapture::None, None) => Ok(Self::None),
            (RemoteCapture::File { limit_bytes, .. }, Some(path)) => {
                let header = format!(
                    "=== COMMAND ===\n{command}\n\n=== CWD ===\n{}\n\n",
                    cwd.display()
                );
                if header.len() as u64 > *limit_bytes {
                    return Err(remote_error(
                        RemoteErrorCode::OutputLimitExceeded,
                        format!(
                            "capture header requires {} bytes, limit is {limit_bytes}; process was not started",
                            header.len()
                        ),
                    ));
                }
                if let Some(parent) = path.parent() {
                    tokio::fs::create_dir_all(parent)
                        .await
                        .map_err(|error| io_error("create capture directory", error))?;
                }
                let mut file = tokio::fs::File::create(path)
                    .await
                    .map_err(|error| io_error("create capture file", error))?;
                file.write_all(header.as_bytes())
                    .await
                    .map_err(|error| io_error("write capture header", error))?;
                Ok(Self::File {
                    file,
                    receipt: RemoteCaptureReceipt {
                        limit_bytes: *limit_bytes,
                        charged_bytes: header.len() as u64,
                        refused_bytes: 0,
                    },
                })
            }
            (RemoteCapture::None, Some(_)) | (RemoteCapture::File { .. }, None) => {
                Err(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "capture policy and resolved path disagree",
                ))
            }
        }
    }

    pub(super) async fn append(
        &mut self,
        stream: RemoteOutputStream,
        body: &[u8],
    ) -> Result<Acceptance, RemoteError> {
        let Self::File { file, receipt } = self else {
            return Ok(Acceptance::Accepted);
        };
        let label = match stream {
            RemoteOutputStream::Stdout => b"=== STDOUT ===\n",
            RemoteOutputStream::Stderr => b"=== STDERR ===\n",
        };
        let cost = label.len() as u64 + body.len() as u64 + u64::from(!body.ends_with(b"\n"));
        if receipt.refused_bytes > 0 || cost > receipt.limit_bytes - receipt.charged_bytes {
            receipt.refused_bytes = receipt.refused_bytes.saturating_add(cost);
            return Ok(Acceptance::Refused);
        }
        async {
            file.write_all(label).await?;
            file.write_all(body).await?;
            if !body.ends_with(b"\n") {
                file.write_all(b"\n").await?;
            }
            Ok::<_, std::io::Error>(())
        }
        .await
        .map_err(|error| io_error("capture process output", error))?;
        receipt.charged_bytes += cost;
        Ok(Acceptance::Accepted)
    }

    pub(super) async fn flush(&mut self) -> Result<(), RemoteError> {
        match self {
            Self::None => Ok(()),
            Self::File { file, .. } => file
                .flush()
                .await
                .map_err(|error| io_error("flush capture output", error)),
        }
    }

    pub(super) fn receipt(&self) -> Option<RemoteCaptureReceipt> {
        match self {
            Self::None => None,
            Self::File { receipt, .. } => Some(*receipt),
        }
    }
}
