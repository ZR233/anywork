//! StudioRuntime 的按环境作用域 MCP 配置目录 API 与 Thread 级 MCP 状态/重连 API。

use anyhow::Result;
use pl_protocol::{
    CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpCatalogSnapshot,
    McpDocumentCommitReceipt, McpDocumentContent, McpDocumentRef, McpScope,
    ReconnectThreadMcpRequest, ThreadMcpStateSnapshot, UpdateMcpDocumentRequest,
};

use super::StudioRuntime;
use crate::config::McpDocumentError;

impl StudioRuntime {
    /// 读取指定环境作用域的 MCP 配置目录快照。
    pub fn read_mcp_catalog(&self, scope: &McpScope) -> Result<McpCatalogSnapshot> {
        Ok(self.config_runtime.mcp_catalog_snapshot(scope)?)
    }

    /// 重新扫描配置目录，发布事件并通知受影响的打开 Thread 增量协调；不等待连接握手。
    pub async fn reload_mcp_catalog(&self, scope: &McpScope) -> Result<McpCatalogSnapshot> {
        let (snapshot, changed_scopes) = self.config_runtime.reload_mcp_catalog(scope)?;
        self.notify_mcp_scopes_changed(&changed_scopes).await;
        Ok(snapshot)
    }

    /// 读取单个 MCP 配置文件的完整源码与诊断。
    pub fn read_mcp_document(
        &self,
        document: &McpDocumentRef,
    ) -> std::result::Result<McpDocumentContent, McpDocumentError> {
        self.config_runtime.read_mcp_document(document)
    }

    /// 创建配置文件，发布事件并通知受影响的打开 Thread 增量协调；不等待连接握手。
    pub async fn create_mcp_document(
        &self,
        request: &CreateMcpDocumentRequest,
    ) -> std::result::Result<McpDocumentCommitReceipt, McpDocumentError> {
        let (receipt, changed_scopes) = self.config_runtime.create_mcp_document(request)?;
        self.notify_mcp_scopes_changed(&changed_scopes).await;
        Ok(receipt)
    }

    /// 更新配置文件，发布事件并通知受影响的打开 Thread 增量协调；不等待连接握手。
    pub async fn update_mcp_document(
        &self,
        request: &UpdateMcpDocumentRequest,
    ) -> std::result::Result<McpDocumentCommitReceipt, McpDocumentError> {
        let (receipt, changed_scopes) = self.config_runtime.update_mcp_document(request)?;
        self.notify_mcp_scopes_changed(&changed_scopes).await;
        Ok(receipt)
    }

    /// 删除配置文件，发布事件并通知受影响的打开 Thread 增量协调；不等待连接握手。
    pub async fn delete_mcp_document(
        &self,
        request: &DeleteMcpDocumentRequest,
    ) -> std::result::Result<McpDocumentCommitReceipt, McpDocumentError> {
        let (receipt, changed_scopes) = self.config_runtime.delete_mcp_document(request)?;
        self.notify_mcp_scopes_changed(&changed_scopes).await;
        Ok(receipt)
    }

    /// 读取指定 Thread 的 MCP 运行时状态快照（关闭或未打开的已知 Thread 返回空快照）。
    pub async fn read_thread_mcp(&self, thread_id: &str) -> Result<ThreadMcpStateSnapshot> {
        self.thread_factory.read_thread_mcp(thread_id).await
    }

    /// 重连指定打开 Thread 的全部或单个 MCP server。
    pub async fn reconnect_thread_mcp(
        &self,
        request: ReconnectThreadMcpRequest,
    ) -> Result<ThreadMcpStateSnapshot> {
        let snapshot = self
            .thread_factory
            .reconnect_thread_mcp(&request.thread_id, request.server_id.as_deref())
            .await?;
        self.tool_catalog_updates.notify_one();
        Ok(snapshot)
    }

    pub(crate) async fn notify_mcp_scopes_changed(&self, changed_scopes: &[McpScope]) {
        for scope in changed_scopes {
            if let Ok(catalog) = self.config_runtime.mcp_catalog_snapshot(scope) {
                self.agent_facility.product_events.emit_mcp_catalog(catalog);
            }
        }
        self.thread_factory
            .reconcile_open_threads_for_scopes(changed_scopes)
            .await;
        self.tool_catalog_updates.notify_one();
    }
}
