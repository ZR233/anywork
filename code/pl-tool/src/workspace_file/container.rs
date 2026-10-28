use crate::tool_error;
use std::sync::Arc;

use crate::container::helpers::preview_error;
use crate::container::{
    ContainerBackend, ContainerCopyFromRequest, ContainerCopyToRequest, ContainerExecRequest,
};
use crate::shell::shell_quote_word;

use pl_protocol::Result;

use super::backend::{
    WorkspaceFileBackend, WorkspaceFileListRequest, WorkspaceFileListResult,
    WorkspaceFileReadBytesRequest, WorkspaceFileReadRequest, WorkspaceFileRemoveRequest,
    WorkspaceFileStat, WorkspaceFileStatRequest, WorkspaceFileWriteRequest,
};
use super::container_path::resolve_container_workspace_path;

#[derive(Debug, Clone)]
pub struct ContainerWorkspaceFileBackend<B> {
    backend: Arc<B>,
    listings: super::listing::ListingPager,
}

impl<B> ContainerWorkspaceFileBackend<B> {
    pub fn new(backend: Arc<B>) -> Self {
        Self {
            backend,
            listings: Default::default(),
        }
    }
}

impl<B> WorkspaceFileBackend for ContainerWorkspaceFileBackend<B>
where
    B: ContainerBackend,
{
    async fn default_cwd(&self) -> Result<String> {
        let output = self
            .backend
            .exec(ContainerExecRequest {
                call_id: None,
                command:
                    "if [ -d /workspace/repo ]; then printf /workspace/repo; else printf /workspace; fi"
                        .to_string(),
                cwd: Some("/".to_string()),
                timeout_secs: Some(10),
                output_bytes_cap: None,
                cancellation_token: None,
            })
            .await
            .map_err(|error| tool_error("file", error))?;
        if output.status != 0 {
            return Err(tool_error(
                "file",
                format!(
                    "failed to resolve default cwd: {}",
                    preview_error(&output.stderr, &output.stdout)
                ),
            ));
        }
        Ok(output.stdout.trim().to_string())
    }

    async fn stat_optional(
        &self,
        request: WorkspaceFileStatRequest,
    ) -> Result<Option<WorkspaceFileStat>> {
        let path = resolve_container_workspace_path(&request.path, request.cwd.as_deref())?;
        let command = format!(
            "p={path}; if test -f \"$p\"; then printf 'file\t'; wc -c < \"$p\"; elif test -d \"$p\"; then printf 'dir\t0'; elif test -e \"$p\" || test -L \"$p\"; then printf 'other\t0'; else parent=\"$p\"; while test \"$parent\" != /; do parent=$(dirname -- \"$parent\") || exit 14; if test -d \"$parent\"; then test -x \"$parent\" || exit 13; elif test -e \"$parent\" || test -L \"$parent\"; then exit 14; fi; done; printf 'missing\t0'; fi",
            path = shell_quote_word(&path)
        );
        let output = self
            .backend
            .exec(ContainerExecRequest {
                call_id: None,
                command,
                cwd: request.cwd,
                timeout_secs: Some(10),
                output_bytes_cap: None,
                cancellation_token: None,
            })
            .await
            .map_err(|error| tool_error("file", error))?;
        if output.status != 0 {
            return Err(tool_error(
                "file",
                format!(
                    "stat failed: {}",
                    preview_error(&output.stderr, &output.stdout)
                ),
            ));
        }
        let raw = output.stdout.trim();
        let mut parts = raw.split_whitespace();
        let kind = parts
            .next()
            .ok_or_else(|| tool_error("file", "stat returned no metadata"))?;
        if !matches!(kind, "file" | "dir" | "other" | "missing") {
            return Err(tool_error("file", "stat returned an invalid path kind"));
        }
        if kind == "missing" {
            return Ok(None);
        }
        let size = parts
            .next()
            .and_then(|value| value.parse::<u64>().ok())
            .ok_or_else(|| tool_error("file", "stat returned an invalid byte length"))?;
        let len = (kind == "file").then_some(size);
        Ok(Some(WorkspaceFileStat {
            path: request.path,
            is_file: kind == "file",
            is_dir: kind == "dir",
            len,
            readonly: None,
            modified_at: None,
        }))
    }

    async fn read_text(&self, request: WorkspaceFileReadRequest) -> Result<String> {
        let bytes = self
            .backend
            .copy_from(ContainerCopyFromRequest {
                path: resolve_container_workspace_path(&request.path, request.cwd.as_deref())?,
                archive: false,
            })
            .await
            .map_err(|error| {
                tool_error(
                    "workspace_file",
                    format!("failed to read `{}`: {error}", request.path),
                )
            })?;
        String::from_utf8(bytes).map_err(|error| {
            tool_error(
                "workspace_file",
                format!("failed to decode `{}` as UTF-8: {error}", request.path),
            )
        })
    }

    async fn read_bytes(&self, request: WorkspaceFileReadBytesRequest) -> Result<Vec<u8>> {
        let stat = self
            .stat(WorkspaceFileStatRequest {
                path: request.path.clone(),
                cwd: request.cwd.clone(),
            })
            .await?;
        if !stat.is_file {
            return Err(tool_error(
                "view_image",
                format!("'{}' is not a regular file", request.path),
            ));
        }
        if stat.len.is_some_and(|len| len > request.max_bytes as u64) {
            return Err(tool_error(
                "view_image",
                format!(
                    "'{}' exceeds the {} byte source limit",
                    request.path, request.max_bytes
                ),
            ));
        }
        let bytes = self
            .backend
            .copy_from(ContainerCopyFromRequest {
                path: resolve_container_workspace_path(&request.path, request.cwd.as_deref())?,
                archive: false,
            })
            .await
            .map_err(|error| {
                tool_error(
                    "view_image",
                    format!("failed to read `{}`: {error}", request.path),
                )
            })?;
        if bytes.len() > request.max_bytes {
            return Err(tool_error(
                "view_image",
                format!(
                    "'{}' changed while reading and exceeds the {} byte source limit",
                    request.path, request.max_bytes
                ),
            ));
        }
        Ok(bytes)
    }

    async fn write_text(&self, request: WorkspaceFileWriteRequest) -> Result<()> {
        self.backend
            .copy_to(ContainerCopyToRequest {
                path: resolve_container_workspace_path(&request.path, request.cwd.as_deref())?,
                content: request.content.into_bytes(),
            })
            .await
            .map_err(|error| {
                tool_error(
                    "apply_patch",
                    format!("failed to write `{}`: {error}", request.path),
                )
            })
    }

    async fn remove_file(&self, request: WorkspaceFileRemoveRequest) -> Result<()> {
        let path = resolve_container_workspace_path(&request.path, request.cwd.as_deref())?;
        let command = format!("rm -f -- {}", shell_quote_word(&path));
        let output = self
            .backend
            .exec(ContainerExecRequest {
                call_id: None,
                command,
                cwd: Some("/".to_string()),
                timeout_secs: Some(20),
                output_bytes_cap: None,
                cancellation_token: None,
            })
            .await
            .map_err(|error| tool_error("apply_patch", error))?;
        if output.status != 0 {
            return Err(tool_error(
                "apply_patch",
                format!(
                    "failed to remove `{}`: {}",
                    request.path,
                    preview_error(&output.stderr, &output.stdout)
                ),
            ));
        }
        Ok(())
    }

    async fn list(&self, request: WorkspaceFileListRequest) -> Result<WorkspaceFileListResult> {
        let path = request.path.clone();
        let cwd = request.cwd.clone();
        self.listings.page(request, async {
            use futures::StreamExt;
            let allocation = tokio::task::spawn_blocking(|| pl_remote_helper::budget::ResourcePolicy::default().allocation()).await
                .map_err(|e| tool_error("list_files", e))?.map_err(|e| tool_error("list_files", e))?;
            let command = format!("find {path} \\( -name .git -o -name target -o -name node_modules \\) -prune -o -type f -print -o -type d -exec printf '%s/\\n' {{}} +", path = shell_quote_word(&path));
            let output = self.backend.exec(ContainerExecRequest { call_id: None, command, cwd,
                timeout_secs: Some(20), output_bytes_cap: Some(allocation.resident_bytes / 2), cancellation_token: None }).await
                .map_err(|e| tool_error("list_files", e))?;
            if output.status != 0 || output.stdout_truncated {
                return Err(tool_error("list_files", "container listing could not complete within its resource grant"));
            }
            let entries = output.stdout.lines().filter(|line| !line.is_empty() && line.trim_end_matches('/') != path.trim_end_matches('/'))
                .filter(|line| !super::listing::skip_directory(line))
                .map(|line| Ok(super::WorkspaceFileListEntry { path: line.trim_end_matches('/').to_owned(), is_dir: line.ends_with('/') }))
                .collect::<Vec<_>>();
            Ok(futures::stream::iter(entries).boxed() as super::listing::Entries)
        }).await
    }

    async fn close_listing(&self, cursor: String) -> Result<()> {
        self.listings.close(&cursor);
        Ok(())
    }

    async fn create_directory(&self, path: String, cwd: Option<String>) -> Result<()> {
        let path = resolve_container_workspace_path(&path, cwd.as_deref())?;
        let command = format!("mkdir -p -- {}", shell_quote_word(&path));
        let output = self
            .backend
            .exec(ContainerExecRequest {
                call_id: None,
                command,
                cwd,
                timeout_secs: Some(20),
                output_bytes_cap: None,
                cancellation_token: None,
            })
            .await
            .map_err(|error| tool_error("create_directory", error))?;
        if output.status != 0 {
            return Err(tool_error(
                "create_directory",
                format!(
                    "failed to create directory: {}",
                    preview_error(&output.stderr, &output.stdout)
                ),
            ));
        }
        Ok(())
    }
}
