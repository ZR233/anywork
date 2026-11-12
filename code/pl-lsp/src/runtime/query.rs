//! LSP 查询编排：路由 → client → 请求 → 格式化；以及文件变更通知。

use std::path::Path;

use crate::client::uri::path_to_file_uri;
use crate::query::{LspDiagnostic, LspQuery, LspQueryOperation, LspQueryResult};

use super::formatting::{format_diagnostics, format_lsp_result};
use super::request::request_for_query;
use super::{LspResult, LspRuntimeRegistry};

impl LspRuntimeRegistry {
    pub async fn query_in_workspace(
        &self,
        workspace_root: impl AsRef<Path>,
        query: LspQuery,
    ) -> LspResult<LspQueryResult> {
        let workspace_root = super::workspace_key(workspace_root.as_ref());
        if !self.has_ready_servers(&workspace_root).await {
            return Err(super::LspRuntimeError::Unavailable(
                "no LSP server is ready in this workspace".into(),
            ));
        }
        if query.operation == LspQueryOperation::Diagnostics {
            return self
                .query_diagnostics_in_workspace(&workspace_root, query)
                .await;
        }
        let (server_id, resolved, client) = self
            .client_for_query_in_workspace(&workspace_root, &query)
            .await?;
        if let Some(path) = query.file_path.as_deref() {
            let uri = path_to_file_uri(path, client.path_style());
            client.open_document(path, &uri).await?;
        }
        let value = request_for_query(&client, &query).await?;
        let formatted = format_lsp_result(
            query.operation,
            &value,
            &resolved.workspace_root,
            client.path_style(),
        );
        Ok(LspQueryResult {
            success: true,
            operation: query.operation,
            server_id: Some(server_id),
            result: formatted.text,
            result_count: formatted.result_count,
            file_count: formatted.file_count,
        })
    }

    pub async fn notify_file_changed(&self, path: impl AsRef<Path>) {
        let path = path.as_ref();
        self.refresh_for_configuration_path(path).await;
        for client in self.open_clients_for_path(path).await {
            if let Err(error) = client.file_changed(path).await {
                tracing::warn!(path = %path.display(), %error, "LSP file change notification failed");
            }
            if let Err(error) = client.refresh_document(path).await {
                tracing::warn!(path = %path.display(), %error, "LSP document refresh failed");
            }
        }
    }

    pub async fn notify_file_deleted(&self, path: impl AsRef<Path>) {
        let path = path.as_ref();
        self.refresh_for_configuration_path(path).await;
        for client in self.open_clients_for_path(path).await {
            if let Err(error) = client.file_deleted(path).await {
                tracing::warn!(path = %path.display(), %error, "LSP file deletion notification failed");
            }
        }
    }

    async fn refresh_for_configuration_path(&self, path: &Path) {
        let roots: Vec<_> = self
            .state
            .lock()
            .await
            .workspaces
            .iter()
            .filter(|(root, workspace)| {
                let configuration = root.join(".anywork/lsp");
                path.starts_with(&configuration)
                    || configuration.starts_with(path)
                    || workspace
                        .defaults_directory
                        .as_ref()
                        .is_some_and(|directory| {
                            path.starts_with(directory) || directory.starts_with(path)
                        })
            })
            .map(|(root, _)| root.clone())
            .collect();
        for root in roots {
            self.refresh_workspace_configuration(root).await;
        }
    }

    async fn query_diagnostics_in_workspace(
        &self,
        workspace_root: &Path,
        query: LspQuery,
    ) -> LspResult<LspQueryResult> {
        let max_results = query.max_results.unwrap_or(100);
        let mut diagnostics = self
            .all_diagnostics_for_workspace(workspace_root, query.file_path.as_deref())
            .await;
        let server_id = if query.server_id.is_some() || query.language_id.is_some() {
            let server_id = self
                .server_id_for_query_in_workspace(workspace_root, &query)
                .await?;
            self.ensure_operation_supported_in_workspace(
                workspace_root,
                &server_id,
                query.operation,
            )
            .await?;
            Some(server_id)
        } else {
            None
        };
        if let Some(server_id) = server_id.as_deref() {
            diagnostics.retain(|diagnostic| diagnostic.server_id == server_id);
        }
        let formatted = format_diagnostics(&diagnostics, max_results);
        Ok(LspQueryResult {
            success: true,
            operation: LspQueryOperation::Diagnostics,
            server_id,
            result: formatted.text,
            result_count: formatted.result_count,
            file_count: formatted.file_count,
        })
    }

    async fn all_diagnostics_for_workspace(
        &self,
        workspace_root: &Path,
        path: Option<&Path>,
    ) -> Vec<LspDiagnostic> {
        let containers = self
            .state
            .lock()
            .await
            .workspaces
            .get(workspace_root)
            .map(|workspace| {
                workspace
                    .servers
                    .values()
                    .filter(|server| server.healthy())
                    .filter_map(|server| {
                        server.client.as_ref().map(|client| {
                            (
                                server.diagnostics.clone(),
                                path.map(|path| path_to_file_uri(path, client.path_style())),
                            )
                        })
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let mut diagnostics = Vec::new();
        for (container, uri) in containers {
            diagnostics.extend(
                container
                    .lock()
                    .await
                    .values()
                    .flat_map(|items| items.iter())
                    .filter(|diagnostic| uri.as_ref().is_none_or(|uri| diagnostic.uri == *uri))
                    .cloned(),
            );
        }
        diagnostics.sort_by(|left, right| {
            left.path
                .cmp(&right.path)
                .then(left.range.start.line.cmp(&right.range.start.line))
                .then(left.range.start.character.cmp(&right.range.start.character))
        });
        diagnostics
    }
}
