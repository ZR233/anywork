use std::fmt;
use std::future::Future;

use pl_protocol::Result;

/// workspace 文件工具的统一后端。
///
/// 工具层负责解析统一输入、生成统一 JSON 输出并执行 patch 匹配逻辑；
/// backend 只表达“在某个 workspace 中读、写、删”的能力。本地目录、
/// Docker 容器或远程沙箱都应通过实现该 trait 接入，避免为同名 file 工具维护多套协议。
pub trait WorkspaceFileBackend: fmt::Debug + Send + Sync {
    /// Creates an invocation-only access view, preserving physical confinement and write policy.
    /// `None` keeps the original backend. A host grant never requires a backend to relax its boundary.
    fn for_grant(&self, _grant: &pl_core::tool::execution_policy::ExecutionGrant) -> Option<Self>
    where
        Self: Sized,
    {
        None
    }

    /// Executor-backed targets override this with one target-side operation. Non-executor
    /// integrations retain the shared grammar through their narrow file capability.
    fn apply_patch(
        &self,
        cwd: String,
        patch: &str,
    ) -> impl Future<Output = std::result::Result<pl_patch::PatchReport, pl_patch::PatchFailure>> + Send
    where
        Self: Sized,
    {
        super::patch::apply_via_files(self, cwd, patch)
    }

    fn default_cwd(&self) -> impl Future<Output = Result<String>> + Send;

    /// A validated absolute host locator, only for a backend whose files are local.
    /// Remote backends must retain the default `None`, regardless of their path syntax.
    fn local_file_path(
        &self,
        _request: WorkspaceFileStatRequest,
    ) -> impl Future<Output = Result<Option<String>>> + Send {
        async { Ok(None) }
    }

    /// Returns absence only for a missing path; access and transport failures remain errors.
    fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> impl Future<Output = Result<Option<WorkspaceFileStat>>> + Send;

    fn stat(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> impl Future<Output = Result<WorkspaceFileStat>> + Send {
        async move {
            let path = request.path.clone();
            self.stat_optional(request)
                .await?
                .ok_or_else(|| crate::tool_error("file", format!("path not found: {path}")))
        }
    }

    fn read_text(
        &self,
        request: WorkspaceFileReadRequest,
    ) -> impl Future<Output = Result<String>> + Send;

    fn read_bytes(
        &self,
        request: WorkspaceFileReadBytesRequest,
    ) -> impl Future<Output = Result<Vec<u8>>> + Send;

    fn write_text(
        &self,
        request: WorkspaceFileWriteRequest,
    ) -> impl Future<Output = Result<()>> + Send;

    fn remove_file(
        &self,
        request: WorkspaceFileRemoveRequest,
    ) -> impl Future<Output = Result<()>> + Send;

    /// Recursively creates a workspace-relative directory using the same confinement as writes.
    fn create_directory(
        &self,
        path: String,
        cwd: Option<String>,
    ) -> impl Future<Output = Result<()>> + Send;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileStatRequest {
    pub path: String,
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileStat {
    pub path: String,
    pub is_file: bool,
    pub is_dir: bool,
    pub len: Option<u64>,
    pub readonly: Option<bool>,
    pub modified_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileReadRequest {
    pub path: String,
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileReadBytesRequest {
    pub path: String,
    pub cwd: Option<String>,
    pub max_bytes: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileWriteRequest {
    pub mode: crate::workspace::WriteMode,
    pub path: String,
    pub cwd: Option<String>,
    pub content: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceFileRemoveRequest {
    pub path: String,
    pub cwd: Option<String>,
}
