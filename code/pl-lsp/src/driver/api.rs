use std::path::Path;

use serde_json::Value;

use crate::catalog::LspServerDefinition;

/// 解析占位符后的进程启动命令。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspResolvedCommand {
    pub program: String,
    pub args: Vec<String>,
}

/// 通用客户端所需的命令与配置投影，不负责安装、探测或语言专用逻辑。
pub trait LspServerDriver: Send + Sync {
    /// 解析进程启动参数；默认渲染 catalog command 的 `{workspaceRoot}` 占位符。
    fn resolve_command(
        &self,
        definition: &LspServerDefinition,
        workspace_root: &Path,
    ) -> LspResolvedCommand {
        definition.command.render(workspace_root)
    }

    /// 返回 LSP initialize 请求的 server 专项 `initializationOptions`。
    fn initialization_options(&self) -> Value {
        Value::Null
    }

    /// 返回 `workspace/configuration` 请求中单个 section 的值。
    fn configuration_response(&self, _section: Option<&str>) -> Value {
        Value::Null
    }
}
