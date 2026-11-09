//! Invocation-scoped adapters; grants and workspace policy never cross this boundary.
use super::*;

pub(crate) struct FileCapability<B>(pub Arc<B>);

impl<B: WorkspaceFileBackend> pl_tool_filesystem::StatBackend for FileCapability<B> {
    type Error = pl_protocol::PureError;
    async fn stat_optional(
        &self,
        request: pl_tool_filesystem::StatRequest,
    ) -> pl_protocol::Result<Option<pl_tool_filesystem::FileStat>> {
        self.0
            .stat_optional(WorkspaceFileStatRequest {
                path: request.path,
                cwd: request.cwd,
            })
            .await
            .map(|stat| {
                stat.map(|stat| pl_tool_filesystem::FileStat {
                    path: stat.path,
                    is_file: stat.is_file,
                    is_dir: stat.is_dir,
                    len: stat.len,
                    readonly: stat.readonly,
                    modified_at: stat.modified_at,
                })
            })
    }
}
impl<B: WorkspaceFileBackend> pl_tool_filesystem::WriteBackend for FileCapability<B> {
    type Error = pl_protocol::PureError;
    async fn write_text(
        &self,
        request: pl_tool_filesystem::WriteRequest,
    ) -> pl_protocol::Result<()> {
        self.0
            .write_text(WorkspaceFileWriteRequest {
                mode: match request.mode {
                    pl_tool_filesystem::WriteMode::Create => crate::workspace::WriteMode::Create,
                    pl_tool_filesystem::WriteMode::Overwrite => {
                        crate::workspace::WriteMode::Overwrite
                    }
                    pl_tool_filesystem::WriteMode::Append => crate::workspace::WriteMode::Append,
                },
                path: request.path,
                cwd: request.cwd,
                content: request.content,
            })
            .await
    }
}

pub(crate) fn granted_backend<B: WorkspaceFileBackend>(
    backend: &Arc<B>,
    grant: &pl_core::tool::execution_policy::ExecutionGrant,
) -> Arc<B> {
    backend
        .for_grant(grant)
        .map(Arc::new)
        .unwrap_or_else(|| Arc::clone(backend))
}
