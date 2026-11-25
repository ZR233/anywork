#[cfg(test)]
use std::collections::BTreeMap;
use std::sync::Arc;

use super::super::{ConfigPaths, McpCatalogResource, McpDocumentError};
use super::{ConfigRuntime, ConfigRuntimeResult, config_runtime_poisoned};
use crate::{
    CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpCatalogSnapshot,
    McpDocumentCommitReceipt, McpDocumentContent, McpDocumentRef, McpScope,
    UpdateMcpDocumentRequest,
};

type DocumentCommit =
    std::result::Result<(McpDocumentCommitReceipt, Vec<McpScope>), McpDocumentError>;

impl ConfigRuntime {
    /// 读取指定环境作用域的 MCP 配置目录快照。
    pub fn mcp_catalog_snapshot(
        &self,
        scope: &McpScope,
    ) -> ConfigRuntimeResult<McpCatalogSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = self.read()?;
        Ok(self
            .mcp_catalog
            .read_catalog(self.store.paths(), &snapshot.config.models, scope)?)
    }

    /// 订阅指定环境作用域的 MCP 配置目录变更唤醒。
    #[cfg(test)]
    pub(super) fn subscribe_mcp_catalog(
        &self,
        scope: &McpScope,
    ) -> ConfigRuntimeResult<(McpCatalogSnapshot, tokio::sync::watch::Receiver<u64>)> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = self.read()?;
        Ok(self
            .mcp_catalog
            .subscribe(self.store.paths(), &snapshot.config.models, scope)?)
    }

    /// 解析指定环境作用域内所有有效 MCP 条目（含启用、禁用、缺前置条件）。
    #[cfg(test)]
    pub(super) fn effective_mcp_servers_for_scope(
        &self,
        scope: &McpScope,
    ) -> ConfigRuntimeResult<BTreeMap<String, super::super::ScopedEffectiveMcpServer>> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = self.read()?;
        Ok(self.mcp_catalog.effective_servers_for_scope(
            self.store.paths(),
            &snapshot.config.models,
            scope,
        )?)
    }

    /// 解析单个 Thread 在指定环境作用域下需要连接的 MCP servers。
    #[cfg(test)]
    pub(super) fn resolve_thread_mcp_configs(
        &self,
        scope: &McpScope,
        workspace_root: &std::path::Path,
        host_base_cwd: &std::path::Path,
        remote_commands: Option<Arc<pl_tool::command::ExecutorCommandBackend>>,
    ) -> ConfigRuntimeResult<BTreeMap<String, super::super::ResolvedThreadMcpServer>> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = self.read()?;
        Ok(self.mcp_catalog.resolve_thread_mcp_configs(
            self.store.paths(),
            &snapshot.config.models,
            scope,
            workspace_root,
            host_base_cwd,
            remote_commands,
        )?)
    }

    /// Reads effective servers and their validity under the same configuration command boundary.
    pub(crate) fn resolve_thread_mcp_snapshot(
        &self,
        scope: &McpScope,
        workspace_root: &std::path::Path,
        host_base_cwd: &std::path::Path,
        remote_commands: Option<Arc<pl_tool::command::ExecutorCommandBackend>>,
    ) -> ConfigRuntimeResult<super::super::mcp_resource::ResolvedThreadMcpSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = self.read()?;
        if self
            .mcp_catalog
            .configuration_authorization(scope)
            .is_some_and(|(authorization, _)| !authorization.is_active())
        {
            // A committed Host change can invalidate inherited scopes without commanding
            // their runtimes. Resolve that known invalidation before issuing a fresh lease.
            self.mcp_catalog
                .adopt_scan(self.store.paths(), &snapshot.config.models, scope)?;
        }
        Ok(self.mcp_catalog.resolve_thread_mcp_snapshot(
            self.store.paths(),
            &snapshot.config.models,
            scope,
            workspace_root,
            host_base_cwd,
            remote_commands,
        )?)
    }

    /// 读取单个 MCP 配置文件的完整源码与诊断。
    pub fn read_mcp_document(
        &self,
        document: &McpDocumentRef,
    ) -> std::result::Result<McpDocumentContent, McpDocumentError> {
        self.mcp_catalog.read_document(self.store.paths(), document)
    }

    /// 创建单个 MCP 配置文件，返回提交回执与受影响的作用域列表。
    pub fn create_mcp_document(&self, request: &CreateMcpDocumentRequest) -> DocumentCommit {
        self.edit_mcp_document(|catalog, paths, models| {
            catalog.create_document(paths, models, request)
        })
    }

    /// 更新单个 MCP 配置文件，返回提交回执与受影响的作用域列表。
    pub fn update_mcp_document(&self, request: &UpdateMcpDocumentRequest) -> DocumentCommit {
        self.edit_mcp_document(|catalog, paths, models| {
            catalog.update_document(paths, models, request)
        })
    }

    /// 删除单个 MCP 配置文件，返回提交回执与受影响的作用域列表。
    pub fn delete_mcp_document(&self, request: &DeleteMcpDocumentRequest) -> DocumentCommit {
        self.edit_mcp_document(|catalog, paths, models| {
            catalog.delete_document(paths, models, request)
        })
    }

    fn edit_mcp_document(
        &self,
        edit: impl FnOnce(
            &McpCatalogResource,
            &ConfigPaths,
            &pl_model::config::AgentModelConfig,
        ) -> DocumentCommit,
    ) -> DocumentCommit {
        let _command = self.command_lock.lock().map_err(|_| {
            McpDocumentError::Io("ConfigRuntime command lock is poisoned".to_owned())
        })?;
        let snapshot = self
            .read()
            .map_err(|error| McpDocumentError::Io(error.to_string()))?;
        edit(
            &self.mcp_catalog,
            self.store.paths(),
            &snapshot.config.models,
        )
    }

    /// 重新扫描指定环境作用域的 MCP 配置目录，返回最新快照与受影响的作用域列表。
    pub fn reload_mcp_catalog(
        &self,
        scope: &McpScope,
    ) -> ConfigRuntimeResult<(McpCatalogSnapshot, Vec<McpScope>)> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = self.read()?;
        Ok(self.mcp_catalog.adopt_scan_with_inheritance(
            self.store.paths(),
            &snapshot.config.models,
            scope,
        )?)
    }

    /// Reload only a calling owner's effective scope, including the Host inheritance source.
    /// Product events may be shared, but this operation does not command other Thread runtimes.
    pub(crate) fn reload_thread_mcp_catalog(
        &self,
        scope: &McpScope,
    ) -> ConfigRuntimeResult<(McpCatalogSnapshot, Vec<McpCatalogSnapshot>)> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let snapshot = self.read()?;
        let mut changed = Vec::new();
        if !matches!(scope, McpScope::Host) {
            let (host, updated) = self.mcp_catalog.adopt_scan(
                self.store.paths(),
                &snapshot.config.models,
                &McpScope::Host,
            )?;
            if updated {
                changed.push(host);
            }
        }
        let (catalog, updated) =
            self.mcp_catalog
                .adopt_scan(self.store.paths(), &snapshot.config.models, scope)?;
        if updated {
            changed.push(catalog.clone());
        }
        Ok((catalog, changed))
    }

    /// 当模型账号/凭据发生变化时，重新扫描已加载作用域的 MCP 配置目录（更新内置 MCP 前置条件状态）。
    pub fn refresh_mcp_catalogs_for_models(&self) -> ConfigRuntimeResult<Vec<McpCatalogSnapshot>> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        // Never republish a caller's earlier account/credential snapshot after a newer command.
        let snapshot = self.read()?;
        let models = &snapshot.config.models;
        let changed_scopes = self
            .mcp_catalog
            .refresh_all_scopes(self.store.paths(), models, &[]);
        changed_scopes
            .into_iter()
            .map(|scope| {
                self.mcp_catalog
                    .read_catalog(self.store.paths(), models, &scope)
            })
            .collect::<crate::Result<Vec<_>>>()
            .map_err(Into::into)
    }
}
