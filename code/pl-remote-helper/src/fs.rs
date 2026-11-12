//! Small structured filesystem capabilities, bound to an executor rather than a workspace lease.
use serde::{Deserialize, Serialize};
use std::{
    io,
    pin::Pin,
    task::{Context, Poll},
};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, ReadBuf};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

use crate::{ExecutionError, Executor, TargetPath, executor::ExecutorBackend};

pub(crate) mod mutate;
mod patch;
mod write;

#[derive(Debug, Clone)]
pub struct FileSystem {
    pub(crate) executor: Executor,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Metadata {
    pub is_file: bool,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub len: u64,
    pub readonly: bool,
    pub modified_at: Option<i64>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectoryEntry {
    pub name: String,
    pub path: String,
    pub is_file: bool,
    pub is_dir: bool,
    pub is_symlink: bool,
}
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum WriteMode {
    ReplaceAtomic,
    CreateNew,
    Append,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WriteDescriptor {
    pub path: String,
    pub mode: WriteMode,
    pub expected_len: Option<u64>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WriteResult {
    pub bytes: u64,
    pub mode: WriteMode,
}

pub struct FileReader {
    pub(crate) io: Pin<Box<dyn AsyncRead + Send>>,
    pub(crate) _executor: Executor,
}
impl AsyncRead for FileReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        self.io.as_mut().poll_read(cx, buffer)
    }
}

pub struct FileWriter {
    pub(crate) io: Option<tokio::io::DuplexStream>,
    pub(crate) finish: Option<oneshot::Sender<()>>,
    pub(crate) result: Option<oneshot::Receiver<Result<WriteResult, ExecutionError>>>,
    pub(crate) cancel: CancellationToken,
    pub(crate) finishing: bool,
    pub(crate) _executor: Executor,
    pub(crate) _permit: Option<crate::stream::Permit>,
}
impl Drop for FileWriter {
    fn drop(&mut self) {
        if !self.finishing {
            self.cancel.cancel();
        }
    }
}
impl AsyncWrite for FileWriter {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bytes: &[u8],
    ) -> Poll<io::Result<usize>> {
        match &mut self.io {
            Some(io) => Pin::new(io).poll_write(cx, bytes),
            None => Poll::Ready(Err(io::ErrorKind::BrokenPipe.into())),
        }
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        match &mut self.io {
            Some(io) => Pin::new(io).poll_flush(cx),
            None => Poll::Ready(Err(io::ErrorKind::BrokenPipe.into())),
        }
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "file publication requires finish()",
        )))
    }
}
impl FileWriter {
    pub async fn finish(mut self) -> Result<WriteResult, ExecutionError> {
        self.finishing = true;
        let _ = self.finish.take().expect("writer finish owner").send(());
        self.io.take();
        self.result
            .take()
            .expect("write result owner")
            .await
            .map_err(|_| {
                ExecutionError::Disconnected("file publication result is unknown".into())
            })?
    }
}

enum DirectorySource {
    Native(Box<tokio::fs::ReadDir>),
    Remote(tokio::io::BufReader<FileReader>),
}
pub struct DirectoryReader {
    source: DirectorySource,
    executor: Executor,
}
impl std::fmt::Debug for DirectoryReader {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DirectoryReader")
            .field("executor", &self.executor.id())
            .finish_non_exhaustive()
    }
}
impl DirectoryReader {
    pub async fn next(&mut self) -> Result<Option<DirectoryEntry>, ExecutionError> {
        match &mut self.source {
            DirectorySource::Native(entries) => {
                let Some(entry) = entries
                    .next_entry()
                    .await
                    .map_err(|error| ExecutionError::io("read directory", error))?
                else {
                    return Ok(None);
                };
                let name = entry.file_name().into_string().map_err(|_| {
                    ExecutionError::InvalidInput("directory name is not UTF-8".into())
                })?;
                let path = entry.path().into_os_string().into_string().map_err(|_| {
                    ExecutionError::InvalidInput("directory path is not UTF-8".into())
                })?;
                let kind = entry
                    .file_type()
                    .await
                    .map_err(|error| ExecutionError::io("directory entry type", error))?;
                Ok(Some(DirectoryEntry {
                    name,
                    path,
                    is_file: kind.is_file(),
                    is_dir: kind.is_dir(),
                    is_symlink: kind.is_symlink(),
                }))
            }
            DirectorySource::Remote(reader) => {
                let mut line = Vec::new();
                let count = reader
                    .take((crate::stream::DESCRIPTOR_LIMIT + 1) as u64)
                    .read_until(b'\n', &mut line)
                    .await
                    .map_err(|error| ExecutionError::io("directory stream", error))?;
                if count == 0 {
                    return Ok(None);
                }
                if count > crate::stream::DESCRIPTOR_LIMIT || line.last() != Some(&b'\n') {
                    return Err(ExecutionError::Protocol(
                        "directory entry is oversized or incomplete".into(),
                    ));
                }
                serde_json::from_slice(&line)
                    .map(Some)
                    .map_err(|error| ExecutionError::Protocol(error.to_string()))
            }
        }
    }
}

#[derive(Serialize, Deserialize)]
pub(crate) enum MetadataRequest {
    Metadata(String),
    SymlinkMetadata(String),
    Canonicalize(String),
}
#[derive(Serialize, Deserialize)]
pub(crate) enum MetadataResponse {
    Metadata(Option<Metadata>),
    Canonical(String),
}

impl Executor {
    pub fn fs(&self) -> FileSystem {
        FileSystem {
            executor: self.clone(),
        }
    }
}

impl FileSystem {
    pub async fn apply_patch(
        &self,
        cwd: &TargetPath,
        patch: &str,
    ) -> Result<pl_patch::PatchReport, crate::PatchExecutionError> {
        self.validate(cwd)
            .map_err(crate::PatchExecutionError::Execution)?;
        match &self.executor.inner.backend {
            ExecutorBackend::Local => patch::apply(self.executor.clone(), cwd.clone(), patch)
                .await
                .map_err(crate::PatchExecutionError::Patch),
            ExecutorBackend::Remote(connection) => {
                let result: Result<pl_patch::PatchReport, pl_patch::PatchFailure> = connection
                    .patch(cwd.as_str(), patch)
                    .await
                    .map_err(crate::PatchExecutionError::Execution)?;
                result.map_err(crate::PatchExecutionError::Patch)
            }
        }
    }
    pub async fn write(
        &self,
        path: &TargetPath,
        mode: WriteMode,
        expected_len: Option<u64>,
    ) -> Result<FileWriter, ExecutionError> {
        self.validate(path)?;
        let descriptor = WriteDescriptor {
            path: path.value.clone(),
            mode,
            expected_len,
        };
        match &self.executor.inner.backend {
            ExecutorBackend::Local => write::open(self.executor.clone(), descriptor).await,
            ExecutorBackend::Remote(connection) => {
                connection.writer(self.executor.clone(), descriptor).await
            }
        }
    }
    fn validate(&self, path: &TargetPath) -> Result<(), ExecutionError> {
        if self.executor.is_closed() {
            Err(ExecutionError::Disconnected("executor is closed".into()))
        } else if path.executor == self.executor.id() {
            Ok(())
        } else {
            Err(ExecutionError::InvalidInput(
                "path belongs to another executor".into(),
            ))
        }
    }
    async fn metadata_request(
        &self,
        request: MetadataRequest,
    ) -> Result<MetadataResponse, ExecutionError> {
        match &self.executor.inner.backend {
            ExecutorBackend::Local => metadata_native(request).await,
            ExecutorBackend::Remote(connection) => connection.json("/fs/metadata", &request).await,
        }
    }
    pub async fn metadata(&self, path: &TargetPath) -> Result<Option<Metadata>, ExecutionError> {
        self.metadata_impl(path, false).await
    }
    pub async fn symlink_metadata(
        &self,
        path: &TargetPath,
    ) -> Result<Option<Metadata>, ExecutionError> {
        self.metadata_impl(path, true).await
    }
    async fn metadata_impl(
        &self,
        path: &TargetPath,
        symlink: bool,
    ) -> Result<Option<Metadata>, ExecutionError> {
        self.validate(path)?;
        let request = if symlink {
            MetadataRequest::SymlinkMetadata(path.value.clone())
        } else {
            MetadataRequest::Metadata(path.value.clone())
        };
        match self.metadata_request(request).await? {
            MetadataResponse::Metadata(metadata) => Ok(metadata),
            _ => Err(ExecutionError::Protocol(
                "unexpected metadata response".into(),
            )),
        }
    }
    pub async fn canonicalize(&self, path: &TargetPath) -> Result<TargetPath, ExecutionError> {
        self.validate(path)?;
        match self
            .metadata_request(MetadataRequest::Canonicalize(path.value.clone()))
            .await?
        {
            MetadataResponse::Canonical(path) => self.executor.path(path),
            _ => Err(ExecutionError::Protocol(
                "unexpected canonical path response".into(),
            )),
        }
    }
    pub async fn read(&self, path: &TargetPath) -> Result<FileReader, ExecutionError> {
        self.validate(path)?;
        let io: Pin<Box<dyn AsyncRead + Send>> = match &self.executor.inner.backend {
            ExecutorBackend::Local => Box::pin(
                tokio::fs::File::open(path.as_str())
                    .await
                    .map_err(|error| ExecutionError::io("open file", error))?,
            ),
            ExecutorBackend::Remote(connection) => {
                Box::pin(connection.reader("/fs/read", &path.value).await?)
            }
        };
        Ok(FileReader {
            io,
            _executor: self.executor.clone(),
        })
    }
    pub async fn read_dir(&self, path: &TargetPath) -> Result<DirectoryReader, ExecutionError> {
        self.validate(path)?;
        let source = match &self.executor.inner.backend {
            ExecutorBackend::Local => DirectorySource::Native(Box::new(
                tokio::fs::read_dir(path.as_str())
                    .await
                    .map_err(|error| ExecutionError::io("open directory", error))?,
            )),
            ExecutorBackend::Remote(connection) => {
                DirectorySource::Remote(tokio::io::BufReader::new(FileReader {
                    io: Box::pin(connection.reader("/fs/read-dir", &path.value).await?),
                    _executor: self.executor.clone(),
                }))
            }
        };
        Ok(DirectoryReader {
            source,
            executor: self.executor.clone(),
        })
    }
}

pub(crate) async fn metadata_native(
    request: MetadataRequest,
) -> Result<MetadataResponse, ExecutionError> {
    let result = match request {
        MetadataRequest::Metadata(path) => tokio::fs::metadata(path).await,
        MetadataRequest::SymlinkMetadata(path) => tokio::fs::symlink_metadata(path).await,
        MetadataRequest::Canonicalize(path) => {
            let path = tokio::fs::canonicalize(path)
                .await
                .map_err(|error| ExecutionError::io("canonicalize", error))?;
            return Ok(MetadataResponse::Canonical(
                path.into_os_string().into_string().map_err(|_| {
                    ExecutionError::InvalidInput("canonical path is not UTF-8".into())
                })?,
            ));
        }
    };
    match result {
        Ok(metadata) => Ok(MetadataResponse::Metadata(Some(Metadata {
            is_file: metadata.is_file(),
            is_dir: metadata.is_dir(),
            is_symlink: metadata.is_symlink(),
            len: metadata.len(),
            readonly: metadata.permissions().readonly(),
            modified_at: metadata
                .modified()
                .ok()
                .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|time| time.as_secs() as i64),
        }))),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            Ok(MetadataResponse::Metadata(None))
        }
        Err(error) => Err(ExecutionError::io("metadata", error)),
    }
}
