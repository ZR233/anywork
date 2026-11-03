//! 会话成员的执行后端绑定。
//!
//! [`AgentBinding`] 是封闭枚举：成员的执行方式在创建期由 Profile 解析固定，
//! 根 Native 成员的模型路由仍按既有路由 owner 的提交事实在下一 Turn 冻结，
//! binding 不增设第二份可写路由。`Acp` 分支在 S4 之前没有可执行实现，
//! 出现即明确失败，不携带 Native 占位值。

use serde::{Deserialize, Serialize};

use crate::studio::NewThreadModelRoute;

/// 成员执行后端的封闭绑定。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AgentBinding {
    Native(NativeAgentConfig),
    Acp(AcpAgentConfig),
}

impl AgentBinding {
    /// 绑定的后端类别。
    pub fn backend(&self) -> super::AgentBackendKind {
        match self {
            Self::Native(_) => super::AgentBackendKind::Native,
            Self::Acp(_) => super::AgentBackendKind::Acp,
        }
    }
}

/// Native 后端绑定：复用既有 Native 事实，不重新定义一份模型路由。
///
/// `route` 是 child 创建期冻结的最终模型选择；根成员的当前路由由既有产品命令
/// 修改并按下一 Turn 生效，目录与 binding 只读取已提交事实，不双写。系统指令
/// 与执行配置仍由指令快照、Profile 冻结与 Native 所属域承载，正文不进入目录。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeAgentConfig {
    /// 创建期冻结的完整模型路由；根成员为 `None`（由既有路由 owner 管理）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub route: Option<NewThreadModelRoute>,
    /// 当前 Profile 的 Native 指令正文；目录投影必须省略，历史按自身冻结格式保存。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub system_instructions: Option<String>,
}

/// ACP 后端绑定：引用既有 ACP 账号与协议配置身份。
///
/// 只承载稳定账号 ID 与连接配置身份（`AcpAccountSettings.account_id` /
/// `connection_revision` 对应的事实），不包含 Native model、effort 或
/// system-instruction 占位值，也不复制供应商凭据或受管安装清单。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAgentConfig {
    pub account_id: String,
    /// 账号连接配置身份；随供应商/发行身份变化，不承载秘密材料。
    pub connection_revision: u64,
}
