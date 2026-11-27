//! 产品智能体可复用定义快照与成员目录描述。

use serde::{Deserialize, Serialize};

/// 可复用智能体定义的不可变快照。
///
/// 定义身份、显示文本、用途与内容修订完整保留；账号、模型、推理强度与指令正文
/// 的冻结归 Profile／binding／指令快照各自的 owner，不在此重复第二份事实。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentDefinitionSnapshot {
    pub definition_id: String,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    /// 定义来源标识（内置声明表或用户 Profile）。
    pub source: String,
    /// 定义内容修订；配置定义更新只影响后续新实例。
    pub revision: String,
    /// 定义正文的内容身份。
    pub content_hash: String,
}
