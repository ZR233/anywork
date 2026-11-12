use std::path::{Path, PathBuf};

use futures::FutureExt;
use futures::future::BoxFuture;
use pl_lsp::host::{
    LspHostBackend, LspHostError, LspHostFileStat, LspHostProcess, LspHostSpawnRequest,
};

use super::RemoteWorkspaceHost;
use super::path::relative_workspace_path;

impl RemoteWorkspaceHost {
    fn lsp_host(&self) -> Result<pl_lsp::host::ExecutorLspHost, LspHostError> {
        pl_lsp::host::ExecutorLspHost::new(
            self.files.executor().clone(),
            self.files.canonical_path(),
        )
    }
}
impl LspHostBackend for RemoteWorkspaceHost {
    fn path_style(&self) -> pl_lsp::host::LspPathStyle {
        pl_lsp::host::LspPathStyle::Posix
    }
    fn identity(&self) -> String {
        self.files.binding_identity()
    }
    fn read_file<'a>(
        &'a self,
        path: &'a Path,
        max_bytes: u64,
    ) -> BoxFuture<'a, Result<Vec<u8>, LspHostError>> {
        async move { self.lsp_host()?.read_file(path, max_bytes).await }.boxed()
    }
    fn stat<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<Option<LspHostFileStat>, LspHostError>> {
        async move { self.lsp_host()?.stat(path).await }.boxed()
    }
    fn list_directory<'a>(
        &'a self,
        path: &'a Path,
        max_entries: usize,
    ) -> BoxFuture<'a, Result<Vec<String>, LspHostError>> {
        async move { self.lsp_host()?.list_directory(path, max_entries).await }.boxed()
    }
    fn spawn<'a>(
        &'a self,
        request: LspHostSpawnRequest,
    ) -> BoxFuture<'a, Result<LspHostProcess, LspHostError>> {
        async move { self.lsp_host()?.spawn(request).await }.boxed()
    }
}

pub(crate) async fn resolve_lsp_query_path(
    files: &super::ExecutorWorkspaceFileBackend,
    path: &Path,
    operation: pl_lsp::query::LspQueryOperation,
) -> pl_protocol::Result<PathBuf> {
    let relative = relative_workspace_path(files.canonical_path(), path)
        .map_err(|()| crate::tool_error("lsp_query", "path escapes the remote workspace"))?;
    let mut candidate = relative.as_str();
    loop {
        if let Some(stat) = files
            .inspect_path(candidate.to_owned(), None)
            .await
            .map_err(crate::workspace_file::file_error)?
        {
            if operation.requires_file() && !stat.is_file {
                return Err(crate::tool_error(
                    "lsp_query",
                    "query path is not a regular file",
                ));
            }
            break;
        }
        if operation.requires_file() || candidate == "." {
            return Err(crate::tool_error("lsp_query", "query path does not exist"));
        }
        candidate = candidate.rsplit_once('/').map_or(".", |(parent, _)| parent);
    }
    Ok(PathBuf::from(format!(
        "{}/{}",
        files.canonical_path().trim_end_matches('/'),
        relative
    )))
}
