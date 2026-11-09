//! 绑定到单个 workspace 的已解析 server 定义。

use std::path::{Path, PathBuf};

use crate::query::LspQueryOperation;

/// catalog 定义经 driver 解析并绑定 workspace root 后的运行时形态。
#[derive(Debug, Clone)]
pub(crate) struct ResolvedLspServer {
    pub id: String,
    pub display_name: String,
    pub program: String,
    pub args: Vec<String>,
    pub env: std::collections::BTreeMap<String, String>,
    pub settings: serde_json::Value,
    pub extensions: Vec<String>,
    pub language_ids: Vec<String>,
    pub operations: Vec<LspQueryOperation>,
    pub workspace_root: PathBuf,
}

impl ResolvedLspServer {
    /// 路由校验：该 server 是否声明支持此操作。
    pub(crate) fn supports(&self, operation: LspQueryOperation) -> bool {
        self.operations.contains(&operation)
    }

    /// 根据文件扩展名返回对应的 language ID。
    pub(crate) fn language_for_path(&self, path: &Path) -> Option<&str> {
        let extension = path.extension()?.to_string_lossy().to_ascii_lowercase();
        let extension = format!(".{extension}");
        self.extensions
            .iter()
            .position(|candidate| candidate == &extension)
            .and_then(|index| self.language_ids.get(index))
            .map(String::as_str)
    }

    /// 判断文件扩展名是否由该 server 声明，供所有路径路由复用同一解析规则。
    pub(crate) fn matches_path(&self, path: &Path) -> bool {
        let Some(extension) = path.extension() else {
            return false;
        };
        let extension = format!(".{}", extension.to_string_lossy().to_ascii_lowercase());
        self.extensions
            .iter()
            .any(|candidate| candidate == &extension)
    }
}
