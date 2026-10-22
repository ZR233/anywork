//! 逻辑远端 workspace 的文件 backend：每次操作在当前健康物理连接上取得 workspace 与流租约。
//!
//! backend 只持有逻辑绑定（endpoint 代次 + canonical 路径），不持有任何物理 workspace 句柄：
//! 真实操作自己取租约，句柄随操作结束释放并登记为待释放责任。

mod download;
pub use download::RemoteDownloadError;

use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;

use pl_protocol::Result;
use pl_protocol::remote::{
    RemoteCopyRequest, RemotePathRequest, RemoteReadRequest, RemoteRemoveRequest,
    RemoteRenameRequest, RemoteRequest, RemoteResourceClass, RemoteResponse, RemoteWriteMode,
    RemoteWriteRequest,
};
use pl_remote_helper::remote_transport::DATA_CHUNK_BYTES;
use tokio::io::AsyncReadExt;

use crate::file::matches_pattern;
use crate::tool_error;
use crate::workspace::{WorkspaceInstructionDocument, WorkspaceInstructions};
use crate::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileListRequest, WorkspaceFileListResult,
    WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest, WorkspaceFileRemoveRequest,
    WorkspaceFileStat, WorkspaceFileStatRequest, WorkspaceFileWriteRequest,
};

use super::client::{RemoteDirectoryStream, StreamLease, response_kind};
use super::error::RemoteClientError;
use super::manager::{BindingId, Endpoint};

const DEFAULT_INSTRUCTION_FILENAMES: &[&str] = &["AGENTS.override.md", "AGENTS.md", "Agents.md"];

/// 将现有 workspace 文件端口映射到远端 helper 原语的 backend。
///
/// 它只持有逻辑绑定（endpoint 实例 + 代次 + canonical 路径）；具体操作在所选健康连接上取得
/// 真实 workspace/stream 租约，因此物理 id 与连接可以随池变化，而不会把物理 workspace id
/// 跨连接使用，也不会让空闲 backend 保住一条扩展连接。
#[derive(Debug, Clone)]
pub struct RemoteWorkspaceFileBackend {
    endpoint: Arc<Endpoint>,
    canonical_path: String,
    identity: String,
    binding: BindingId,
}

impl RemoteWorkspaceFileBackend {
    pub(super) fn new(endpoint: Arc<Endpoint>, canonical_path: String, binding: BindingId) -> Self {
        let identity = format!("{}:{canonical_path}", endpoint.identity());
        Self {
            endpoint,
            canonical_path,
            identity,
            binding,
        }
    }

    /// 返回 helper 依据远端文件系统解析出的 canonical POSIX 根路径。
    pub fn canonical_path(&self) -> &str {
        &self.canonical_path
    }

    /// 逻辑绑定的进程内身份：endpoint 实例、代次与 canonical 路径共同决定。
    ///
    /// 该身份只用于当前进程内的绑定比较，不能持久化；重连产生新代次或绑定到另一个 workspace
    /// 后都必须重新装配，旧 LSP host 不得被复用。
    pub(super) fn binding_identity(&self) -> String {
        self.identity.clone()
    }

    /// Whether both backends describe the same logical binding generation and workspace.
    ///
    /// Equal paths or helper handle ids alone never identify a binding: a reconnect produces a new
    /// endpoint generation and therefore a different binding.
    pub fn is_same_binding(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.endpoint, &other.endpoint) && self.identity == other.identity
    }

    /// Admits one file operation on a healthy physical connection.
    pub(super) async fn operation_lease(
        &self,
        class: RemoteResourceClass,
    ) -> std::result::Result<StreamLease, RemoteClientError> {
        self.endpoint
            .acquire(&self.canonical_path, self.binding, class)
            .await
    }

    async fn lease(&self, class: RemoteResourceClass) -> Result<StreamLease> {
        self.operation_lease(class).await.map_err(remote_file_error)
    }

    fn path_request(
        lease: &StreamLease,
        path: String,
        cwd: Option<String>,
    ) -> Result<RemotePathRequest> {
        let workspace_id = lease
            .workspace_id()
            .ok_or_else(|| tool_error("file", "remote operation has no workspace handle"))?
            .to_string();
        Ok(RemotePathRequest {
            workspace_id,
            path: resolve_remote_path(path, cwd)?,
        })
    }

    /// 读取目录的一层 typed entry，供本地 Skills/LSP 等编排增量消费。
    pub async fn list_directory_entries(&self, path: String) -> Result<RemoteDirectoryStream> {
        let lease = self.lease(RemoteResourceClass::Directory).await?;
        let request = Self::path_request(&lease, path, None)?;
        lease
            .directory(RemoteRequest::ListDirectory(request))
            .await
            .map_err(remote_file_error)
    }

    /// 读取路径元数据；不存在时返回 `None`。
    pub async fn stat_optional(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> Result<Option<WorkspaceFileStat>> {
        let lease = self.lease(RemoteResourceClass::Metadata).await?;
        let request = Self::path_request(&lease, path, cwd)?;
        match lease.request(RemoteRequest::Stat(request)).await {
            Ok(RemoteResponse::Stat(stat)) => Ok(Some(WorkspaceFileStat {
                path: stat.path,
                is_file: stat.is_file,
                is_dir: stat.is_directory,
                len: stat.len,
                readonly: Some(stat.readonly),
                modified_at: stat.modified_at,
            })),
            Ok(response) => Err(tool_error(
                "stat_path",
                format!(
                    "unexpected remote stat response: {}",
                    response_kind(&response)
                ),
            )),
            Err(RemoteClientError::Remote {
                code: pl_protocol::remote::RemoteErrorCode::PathNotFound,
                ..
            }) => Ok(None),
            Err(error) => Err(remote_file_error(error)),
        }
    }

    /// 递归创建 workspace 内的目录。
    pub async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        let lease = self.lease(RemoteResourceClass::Metadata).await?;
        let request = Self::path_request(&lease, path, cwd)?;
        let response = lease
            .request(RemoteRequest::CreateDirectory(request))
            .await
            .map_err(remote_file_error)?;
        expect_ack(response)
    }

    /// 原子写入远端 workspace 中的原始字节。
    pub async fn write_bytes_atomic(
        &self,
        path: String,
        cwd: Option<String>,
        body: &[u8],
    ) -> Result<()> {
        let mut source = body;
        self.upload(
            path,
            cwd,
            &mut source,
            body.len() as u64,
            RemoteWriteMode::Overwrite,
        )
        .await
        .map(|_| ())
    }

    /// 从调用方 reader 增量上传，返回 helper 确认的字节数。
    ///
    /// # Errors
    /// 拒绝越界路径、短读源、传输失败与 helper 拒绝；失败不会发布半文件。
    pub async fn copy_file_from<R>(
        &self,
        path: &str,
        reader: &mut R,
        total_len: u64,
        mode: RemoteWriteMode,
    ) -> Result<u64>
    where
        R: tokio::io::AsyncRead + Unpin + Send,
    {
        self.upload(path.to_owned(), None, reader, total_len, mode)
            .await
    }

    async fn upload<R>(
        &self,
        path: String,
        cwd: Option<String>,
        reader: &mut R,
        total_len: u64,
        mode: RemoteWriteMode,
    ) -> Result<u64>
    where
        R: tokio::io::AsyncRead + Unpin + Send,
    {
        let lease = self.lease(RemoteResourceClass::WriteFile).await?;
        let target = Self::path_request(&lease, path, cwd)?;
        lease
            .write_file(
                RemoteWriteRequest {
                    target,
                    mode,
                    total_len,
                },
                reader,
            )
            .await
            .map_err(remote_file_error)
    }

    /// 删除 workspace 内文件或目录，不跟随越界链接。
    pub async fn remove_path(
        &self,
        path: String,
        cwd: Option<String>,
        recursive: bool,
    ) -> Result<()> {
        let class = if recursive {
            RemoteResourceClass::Recursive
        } else {
            RemoteResourceClass::Metadata
        };
        let lease = self.lease(class).await?;
        let path = Self::path_request(&lease, path, cwd)?;
        let response = lease
            .request(RemoteRequest::RemovePath(RemoteRemoveRequest {
                workspace_id: path.workspace_id,
                path: path.path,
                recursive,
            }))
            .await
            .map_err(remote_file_error)?;
        expect_ack(response)
    }

    /// 在同一 workspace 内重命名路径。
    pub async fn rename_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
    ) -> Result<()> {
        let lease = self.lease(RemoteResourceClass::Metadata).await?;
        let source = Self::path_request(&lease, source, cwd.clone())?;
        let target = Self::path_request(&lease, target, cwd)?;
        let response = lease
            .request(RemoteRequest::RenamePath(RemoteRenameRequest {
                workspace_id: source.workspace_id,
                source: source.path,
                target: target.path,
            }))
            .await
            .map_err(remote_file_error)?;
        expect_ack(response)
    }

    /// 在同一 workspace 内复制文件或目录。
    pub async fn copy_path(
        &self,
        source: String,
        target: String,
        cwd: Option<String>,
        recursive: bool,
    ) -> Result<()> {
        let class = if recursive {
            RemoteResourceClass::Recursive
        } else {
            RemoteResourceClass::CopyFile
        };
        let lease = self.lease(class).await?;
        let source = Self::path_request(&lease, source, cwd.clone())?;
        let target = Self::path_request(&lease, target, cwd)?;
        let response = lease
            .request(RemoteRequest::CopyPath(RemoteCopyRequest {
                workspace_id: source.workspace_id,
                source: source.path,
                target: target.path,
                recursive,
            }))
            .await
            .map_err(remote_file_error)?;
        expect_ack(response)
    }

    /// 从同一打开的远端句柄流式读取：只有显式范围才设上限，否则读到本次传输结束。
    async fn read_bytes_streamed(
        &self,
        path: String,
        cwd: Option<String>,
        limit: Option<u64>,
    ) -> Result<Vec<u8>> {
        let lease = self.lease(RemoteResourceClass::ReadFile).await?;
        let path = resolve_remote_path(path, cwd)?;
        let workspace_id = lease
            .workspace_id()
            .ok_or_else(|| tool_error("read_file", "remote operation has no workspace handle"))?
            .to_string();
        let mut reader = lease
            .read_file(RemoteReadRequest {
                workspace_id,
                path,
                offset: 0,
                max_bytes: limit,
            })
            .await
            .map_err(remote_file_error)?;
        let mut bytes = Vec::new();
        let mut buffer = vec![0_u8; DATA_CHUNK_BYTES];
        loop {
            let count = reader
                .read(&mut buffer)
                .await
                .map_err(|error| tool_error("read_file", error.to_string()))?;
            if count == 0 {
                return Ok(bytes);
            }
            bytes.extend_from_slice(&buffer[..count]);
        }
    }
}

/// 在本地 core 中选择、解码并截断远端 workspace 根目录的项目说明文档。
///
/// 读取范围由调用方的 `max_bytes` 决定，不额外引入更小的固定文本上限。
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
    let limit = u64::try_from(max_bytes)
        .map_err(|_| tool_error("read_file", "instruction byte limit is unsupported"))?;
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
        let Some(stat) = backend.stat_optional(path.clone(), None).await? else {
            continue;
        };
        if !stat.is_file {
            continue;
        }
        let bytes = backend
            .read_bytes_streamed(path.clone(), None, Some(limit))
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
        RemoteWorkspaceFileBackend::stat_optional(self, request.path, request.cwd).await
    }

    async fn read_text(&self, request: WorkspaceFileReadRequest) -> Result<String> {
        // `read_text` is an explicitly whole-string consumer: the bytes are aggregated from one
        // streamed handle, not capped by a new transport-level constant.
        let bytes = self
            .read_bytes_streamed(request.path, request.cwd, None)
            .await?;
        String::from_utf8(bytes)
            .map_err(|error| tool_error("read_file", format!("remote file is not UTF-8: {error}")))
    }

    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        let limit = u64::try_from(request.max_bytes)
            .map_err(|_| tool_error("read_file", "remote read limit is unsupported"))?;
        self.read_bytes_streamed(request.path, request.cwd, Some(limit))
            .await
    }

    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        let total_len = request.content.len() as u64;
        let mut source = request.content.as_bytes();
        self.upload(
            request.path,
            request.cwd,
            &mut source,
            total_len,
            request.mode.into(),
        )
        .await
        .map(|_| ())
    }

    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> Result<()> {
        self.remove_path(request.path, request.cwd, false).await
    }

    async fn list(&self, request: WorkspaceFileListRequest) -> Result<WorkspaceFileListResult> {
        let root = resolve_remote_path(request.path, request.cwd)?;
        let mut queue = VecDeque::from([root]);
        let mut files = Vec::new();
        while let Some(path) = queue.pop_front() {
            let mut listing = self.list_directory_entries(path).await?;
            while let Some(entry) = listing.next_entry().await.map_err(remote_file_error)? {
                if entry.is_symlink {
                    continue;
                }
                if entry.is_directory {
                    if matches!(entry.name.as_str(), ".git" | "target" | "node_modules") {
                        continue;
                    }
                    if request.include_dirs && matches_pattern(&entry.path, Some(&request.glob)) {
                        files.push(format!("{}/", entry.path));
                    }
                    queue.push_back(entry.path);
                } else if matches_pattern(&entry.path, Some(&request.glob)) {
                    files.push(entry.path);
                }
                if files.len() > request.max_files {
                    files.sort();
                    files.truncate(request.max_files);
                    return Ok(WorkspaceFileListResult {
                        files,
                        truncated: true,
                    });
                }
            }
        }
        files.sort();
        Ok(WorkspaceFileListResult {
            files,
            truncated: false,
        })
    }

    async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        RemoteWorkspaceFileBackend::create_directory(self, path, cwd).await
    }
}

impl From<crate::workspace::WriteMode> for RemoteWriteMode {
    fn from(mode: crate::workspace::WriteMode) -> Self {
        match mode {
            crate::workspace::WriteMode::Create => Self::Create,
            crate::workspace::WriteMode::Overwrite => Self::Overwrite,
            crate::workspace::WriteMode::Append => Self::Append,
        }
    }
}

fn expect_ack(response: RemoteResponse) -> Result<()> {
    match response {
        RemoteResponse::Ack => Ok(()),
        response => Err(tool_error(
            "file",
            format!(
                "unexpected remote acknowledgement: {}",
                response_kind(&response)
            ),
        )),
    }
}

fn resolve_remote_path(path: String, cwd: Option<String>) -> Result<String> {
    let mut components = Vec::new();
    for source in cwd
        .filter(|cwd| !cwd.trim().is_empty() && cwd != ".")
        .into_iter()
        .chain(std::iter::once(path))
    {
        if source.starts_with('/') || source.contains('\\') {
            return Err(tool_error(
                "file",
                "remote workspace paths must be relative POSIX paths",
            ));
        }
        for component in source.split('/') {
            match component {
                "" | "." => {}
                ".." => {
                    return Err(tool_error("file", "remote path must not escape workspace"));
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

fn remote_file_error(error: RemoteClientError) -> pl_protocol::PureError {
    tool_error("file", error)
}
