mod directory;
mod download;
pub use directory::RemoteDirectoryReader;
pub use download::RemoteDownloadError;
use std::sync::Arc;

use std::collections::VecDeque;
use std::path::PathBuf;

use crate::tool_error;
use pl_protocol::Result;
use pl_protocol::remote::{
    RemoteCopyRequest, RemotePathRequest, RemoteRemoveRequest, RemoteRenameRequest, RemoteRequest,
    RemoteResponse,
};

use crate::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest,
    WorkspaceFileRemoveRequest, WorkspaceFileStat, WorkspaceFileStatRequest,
    WorkspaceFileWriteRequest,
};

use crate::workspace::{WorkspaceInstructionDocument, WorkspaceInstructions};

use super::client::{RemoteClient, RemoteClientError, expect_ack};

impl From<crate::workspace::WriteMode> for pl_protocol::remote::RemoteWriteMode {
    fn from(mode: crate::workspace::WriteMode) -> Self {
        match mode {
            crate::workspace::WriteMode::Create => Self::Create,
            crate::workspace::WriteMode::Overwrite => Self::Overwrite,
            crate::workspace::WriteMode::Append => Self::Append,
        }
    }
}

const DEFAULT_INSTRUCTION_FILENAMES: &[&str] = &["AGENTS.override.md", "AGENTS.md", "Agents.md"];

/// 将现有 workspace 文件端口映射到远端 helper 原语的 backend。
#[derive(Debug, Clone)]
pub struct RemoteWorkspaceFileBackend {
    pub(super) lease: std::sync::Arc<super::client::workspace::WorkspaceLease>,
    client: RemoteClient,
    workspace_id: String,
    canonical_path: String,
}

impl RemoteWorkspaceFileBackend {
    pub(super) fn new(
        client: RemoteClient,
        lease: std::sync::Arc<super::client::workspace::WorkspaceLease>,
    ) -> Self {
        Self {
            client,
            workspace_id: lease.id.clone(),
            canonical_path: lease.path.clone(),
            lease,
        }
    }
    async fn request(
        &self,
        request: RemoteRequest,
        body: &[u8],
    ) -> std::result::Result<super::RemoteReply, RemoteClientError> {
        self.client
            .workspace_request(self.lease.clone(), request, body)
            .await
    }

    /// 返回当前 SSH channel 内的 opaque workspace id。
    pub fn workspace_id(&self) -> &str {
        &self.workspace_id
    }

    /// 返回 helper 依据远端文件系统解析出的 canonical POSIX 根路径。
    pub fn canonical_path(&self) -> &str {
        &self.canonical_path
    }

    pub(super) fn binding_identity(&self) -> String {
        // Membership retains both hosts while comparing identities, so two live leases
        // cannot reuse an allocation address. Cloned backends share the same lease.
        // This identity is only for live in-process comparison and must not be persisted.
        format!("remote-workspace:{:p}", std::sync::Arc::as_ptr(&self.lease))
    }

    /// Whether both workspaces use the same transport and workspace handle.
    /// Equal paths or workspace IDs alone do not identify a connection.
    pub fn is_same_binding(&self, other: &Self) -> bool {
        self.client.is_same_connection(&other.client)
            && self.workspace_id == other.workspace_id
            && self.canonical_path == other.canonical_path
    }

    fn path_request(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> std::result::Result<RemotePathRequest, RemoteClientError> {
        Ok(RemotePathRequest {
            workspace_id: self.workspace_id.clone(),
            path: resolve_remote_path(path, cwd)?,
        })
    }

    /// 读取路径元数据；仅 helper 明确返回 `PathNotFound` 时返回 `None`。
    ///
    /// # Errors
    /// 保留本地路径校验、连接和 helper 响应的原生错误分类；不从显示文本推断缺失。
    pub async fn stat_optional(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> std::result::Result<Option<WorkspaceFileStat>, RemoteClientError> {
        let path = self.path_request(path, cwd)?;
        let reply = self.request(RemoteRequest::Stat(path), &[]).await;
        match reply {
            Ok(reply) => match reply.response {
                RemoteResponse::Stat(stat) => Ok(Some(WorkspaceFileStat {
                    path: stat.path,
                    is_file: stat.is_file,
                    is_dir: stat.is_directory,
                    len: stat.len,
                    readonly: Some(stat.readonly),
                    modified_at: stat.modified_at,
                })),
                _ => Err(RemoteClientError::Protocol(
                    "unexpected remote stat response".into(),
                )),
            },
            Err(RemoteClientError::Remote {
                code: pl_protocol::remote::RemoteErrorCode::PathNotFound,
                ..
            }) => Ok(None),
            Err(error) => Err(error),
        }
    }

    /// 递归创建 workspace 内的目录。
    pub async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        let request = self.path_request(path, cwd).map_err(remote_file_error)?;
        let reply = self
            .request(RemoteRequest::CreateDirectory(request), &[])
            .await
            .map_err(remote_file_error)?;
        expect_ack(reply).map_err(remote_file_error)
    }

    /// 原子写入远端 workspace 中的原始字节。
    pub async fn write_bytes_atomic(
        &self,
        path: String,
        cwd: Option<String>,
        body: &[u8],
    ) -> Result<()> {
        let target = self.path_request(path, cwd).map_err(remote_file_error)?;
        self.upload_bytes(
            target,
            pl_protocol::remote::RemoteWriteMode::Overwrite,
            body,
        )
        .await
    }

    /// 删除 workspace 内文件或目录，不跟随越界链接。
    pub async fn remove_path(
        &self,
        path: String,
        cwd: Option<String>,
        recursive: bool,
    ) -> Result<()> {
        let path = self.path_request(path, cwd).map_err(remote_file_error)?;
        let reply = self
            .request(
                RemoteRequest::RemovePath(RemoteRemoveRequest {
                    workspace_id: path.workspace_id,
                    path: path.path,
                    recursive,
                }),
                &[],
            )
            .await
            .map_err(remote_file_error)?;
        expect_ack(reply).map_err(remote_file_error)
    }

    /// 在同一 workspace 内重命名路径。
    pub async fn rename_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
    ) -> Result<()> {
        let source = self
            .path_request(source, cwd.clone())
            .map_err(remote_file_error)?;
        let target = self.path_request(target, cwd).map_err(remote_file_error)?;
        let reply = self
            .request(
                RemoteRequest::RenamePath(RemoteRenameRequest {
                    workspace_id: source.workspace_id,
                    source: source.path,
                    target: target.path,
                }),
                &[],
            )
            .await
            .map_err(remote_file_error)?;
        expect_ack(reply).map_err(remote_file_error)
    }

    /// 在同一 workspace 内复制文件或目录。
    pub async fn copy_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
        recursive: bool,
    ) -> Result<()> {
        let source = self
            .path_request(source, cwd.clone())
            .map_err(remote_file_error)?;
        let target = self.path_request(target, cwd).map_err(remote_file_error)?;
        let stat = self
            .stat_optional(source.path.clone(), None)
            .await
            .map_err(remote_file_error)?
            .ok_or_else(|| tool_error("copy_path", "source path does not exist"))?;
        if !stat.is_dir {
            return self.copy_file(source.path, target.path).await;
        }
        if !recursive {
            return Err(tool_error(
                "copy_path",
                "directory copy requires recursive=true",
            ));
        }
        if target.path == source.path
            || target
                .path
                .starts_with(&(source.path.trim_end_matches('/').to_owned() + "/"))
        {
            return Err(tool_error(
                "copy_path",
                "cannot copy a directory inside itself",
            ));
        }
        self.create_directory(target.path.clone(), None).await?;
        let mut stack = vec![(self.open_directory(source.path.clone()).await?, target.path)];
        while let Some((reader, destination)) = stack.last_mut() {
            let Some(entry) = reader.next().await? else {
                stack.pop();
                continue;
            };
            if entry.is_symlink {
                return Err(tool_error(
                    "copy_path",
                    "symbolic links are not copyable through the workspace backend",
                ));
            }
            let destination = format!("{}/{}", destination.trim_end_matches('/'), entry.name);
            if entry.is_directory {
                self.create_directory(destination.clone(), None).await?;
                stack.push((self.open_directory(entry.path).await?, destination));
            } else {
                self.copy_file(entry.path, destination).await?;
            }
        }
        Ok(())
    }
    async fn copy_file(&self, source: String, target: String) -> Result<()> {
        let reply = self
            .request(
                RemoteRequest::CopyPath(RemoteCopyRequest {
                    workspace_id: self.workspace_id.clone(),
                    source,
                    target,
                }),
                &[],
            )
            .await
            .map_err(remote_file_error)?;
        expect_ack(reply).map_err(remote_file_error)
    }
}

/// 在本地 core 中选择、解码并截断远端 workspace 根目录的项目说明文档。
pub async fn load_remote_workspace_instructions(
    backend: &RemoteWorkspaceFileBackend,
    max_bytes: usize,
    fallback_filenames: &[String],
) -> Result<WorkspaceInstructions> {
    if max_bytes == 0 {
        return Ok(WorkspaceInstructions {
            documents: Vec::new(),
        });
    }
    let mut seen = std::collections::HashSet::new();
    let candidates = DEFAULT_INSTRUCTION_FILENAMES
        .iter()
        .map(|name| (*name).to_string())
        .chain(
            fallback_filenames
                .iter()
                .map(|name| name.trim())
                .filter(|name| !name.is_empty())
                .map(ToOwned::to_owned),
        )
        .filter(|name| seen.insert(name.clone()));
    for path in candidates {
        let Some(stat) = backend
            .stat_optional(path.clone(), None)
            .await
            .map_err(remote_file_error)?
        else {
            continue;
        };
        if !stat.is_file {
            continue;
        }
        let bytes = backend
            .read_bytes(WorkspaceFileReadBytesRequest {
                path: path.clone(),
                cwd: None,
                max_bytes,
            })
            .await?;
        let take = bytes.len().min(max_bytes);
        return Ok(WorkspaceInstructions {
            documents: vec![WorkspaceInstructionDocument {
                path: PathBuf::from(backend.canonical_path()).join(&path),
                content: String::from_utf8_lossy(&bytes[..take]).into_owned(),
                bytes: take,
            }],
        });
    }
    Ok(WorkspaceInstructions {
        documents: Vec::new(),
    })
}

impl WorkspaceFileBackend for RemoteWorkspaceFileBackend {
    async fn default_cwd(&self) -> Result<String> {
        Ok(".".to_string())
    }

    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> Result<Option<WorkspaceFileStat>> {
        RemoteWorkspaceFileBackend::stat_optional(self, request.path, request.cwd)
            .await
            .map_err(remote_file_error)
    }

    async fn read_text(&self, request: WorkspaceFileReadRequest) -> Result<String> {
        let path = resolve_remote_path(request.path, request.cwd).map_err(remote_file_error)?;
        let mut bytes = self
            .client
            .resident_buffer(self.client.content_budget())
            .map_err(remote_file_error)?;
        self.copy_capture_bounded(&path, &mut bytes, self.client.content_budget() as u64)
            .await
            .map_err(|e| tool_error("read_file", e))?;
        String::from_utf8(bytes.into_bytes()).map_err(|e| tool_error("read_file", e))
    }
    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        let path = resolve_remote_path(request.path, request.cwd).map_err(remote_file_error)?;
        let mut bytes = self
            .client
            .resident_buffer(request.max_bytes)
            .map_err(remote_file_error)?;
        self.copy_capture_bounded(&path, &mut bytes, request.max_bytes as u64)
            .await
            .map_err(|e| tool_error("view_image", e))?;
        Ok(bytes.into_bytes())
    }
    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        self.upload(request).await
    }

    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> Result<()> {
        self.remove_path(request.path, request.cwd, false).await
    }

    async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        RemoteWorkspaceFileBackend::create_directory(self, path, cwd).await
    }
}

fn resolve_remote_path(
    path: String,
    cwd: Option<String>,
) -> std::result::Result<String, RemoteClientError> {
    let mut components = Vec::new();
    for source in cwd
        .filter(|cwd| !cwd.trim().is_empty() && cwd != ".")
        .into_iter()
        .chain(std::iter::once(path))
    {
        if source.starts_with('/') || source.contains('\\') {
            return Err(RemoteClientError::Remote {
                code: super::RemoteErrorCode::InvalidRequest,
                message: "remote workspace paths must be relative POSIX paths".into(),
            });
        }
        for component in source.split('/') {
            match component {
                "" | "." => {}
                ".." => {
                    return Err(RemoteClientError::Remote {
                        code: super::RemoteErrorCode::WorkspaceEscape,
                        message: "remote path must not escape workspace".into(),
                    });
                }
                value => components.push(value.to_string()),
            }
        }
    }
    Ok(if components.is_empty() {
        ".".to_string()
    } else {
        components.join("/")
    })
}

pub(super) fn remote_file_error(error: RemoteClientError) -> pl_protocol::PureError {
    tool_error("file", error)
}
