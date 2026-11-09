//! Read-only projections of healthy initialized servers.
use super::request::extensions_for_language;
use super::{
    LanguageToolInfo, LspRuntimeRegistry, LspWorkspaceCapabilities, LspWorkspaceServerCapabilities,
    LspWorkspaceState, workspace_key,
};
use std::path::Path;
impl LspRuntimeRegistry {
    pub async fn has_ready_servers(&self, root: impl AsRef<Path>) -> bool {
        self.state
            .lock()
            .await
            .workspaces
            .get(root.as_ref())
            .is_some_and(|workspace| workspace.servers.values().any(|server| server.healthy()))
    }
    pub async fn active_server_names(&self) -> Vec<String> {
        let mut names = Vec::new();
        for partition in self.partition_views() {
            let state = partition.state.lock().await;
            names.extend(state.workspaces.values().flat_map(active_names));
        }
        names.sort();
        names.dedup();
        names
    }
    pub async fn active_server_names_for_workspace(&self, root: impl AsRef<Path>) -> Vec<String> {
        self.state
            .lock()
            .await
            .workspaces
            .get(root.as_ref())
            .map(active_names)
            .unwrap_or_default()
    }
    pub async fn available_languages(&self) -> Vec<LanguageToolInfo> {
        let mut languages = Vec::new();
        for partition in self.partition_views() {
            let state = partition.state.lock().await;
            languages.extend(state.workspaces.values().flat_map(available_languages));
        }
        languages
            .sort_by(|a, b| (&a.language_id, &a.server_id).cmp(&(&b.language_id, &b.server_id)));
        languages.dedup_by(|a, b| a.language_id == b.language_id && a.server_id == b.server_id);
        languages
    }
    pub async fn available_languages_for_workspace(
        &self,
        root: impl AsRef<Path>,
    ) -> Vec<LanguageToolInfo> {
        self.state
            .lock()
            .await
            .workspaces
            .get(root.as_ref())
            .map(available_languages)
            .unwrap_or_default()
    }
    pub async fn capabilities_for_workspace(
        &self,
        root: impl AsRef<Path>,
    ) -> LspWorkspaceCapabilities {
        let root = workspace_key(root.as_ref());
        let state = self.state.lock().await;
        let servers = state
            .workspaces
            .get(&root)
            .map(|workspace| {
                workspace
                    .servers
                    .values()
                    .filter(|server| server.healthy())
                    .map(|server| LspWorkspaceServerCapabilities {
                        id: server.resolved.id.clone(),
                        display_name: server.resolved.display_name.clone(),
                        language_ids: server.resolved.language_ids.clone(),
                        operations: server
                            .resolved
                            .operations
                            .iter()
                            .filter(|operation| {
                                server
                                    .client
                                    .as_ref()
                                    .is_some_and(|client| client.supports(**operation))
                            })
                            .map(|operation| operation.as_str().to_string())
                            .collect(),
                        availability: "available".into(),
                        ready: true,
                    })
                    .collect()
            })
            .unwrap_or_default();
        LspWorkspaceCapabilities { servers }
    }
}
fn active_names(workspace: &LspWorkspaceState) -> Vec<String> {
    workspace
        .servers
        .iter()
        .filter(|(_, server)| server.healthy())
        .map(|(id, _)| id.clone())
        .collect()
}
fn available_languages(workspace: &LspWorkspaceState) -> Vec<LanguageToolInfo> {
    workspace
        .servers
        .values()
        .filter(|server| server.healthy())
        .flat_map(|server| {
            server
                .resolved
                .language_ids
                .iter()
                .map(|language| LanguageToolInfo {
                    language_id: language.clone(),
                    server_id: server.resolved.id.clone(),
                    display_name: server.resolved.display_name.clone(),
                    extensions: extensions_for_language(&server.resolved, language),
                })
        })
        .collect()
}
