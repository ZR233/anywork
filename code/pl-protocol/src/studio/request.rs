//! Studio 命令请求体。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OpenProjectRequest {
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SearchSkillsRequest {
    pub query: String,
    pub limit: Option<usize>,
}

/// 完整模型选择：账号、模型与可选 effort。
///
/// 同一份定义服务新建会话草稿与附件准入的 route、child 派发时的模型选择输入，以及目录/
/// 运行时投影的冻结模型身份摘要。它只描述「选了哪个模型」，不携带权限、工作区或 Profile。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, schemars::JsonSchema, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NewThreadModelRoute {
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateThreadRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub input: StudioPromptInput,
    pub mode: String,
    /// Complete route frozen with the draft; does not mutate Mode defaults.
    pub route: NewThreadModelRoute,
    /// 草稿同步解析后的分发模式。
    ///
    /// 省略表示创建时继承全局默认；GUI 的 StartDraft 会先解析并显式传值。落库的 Thread 与
    /// 目录投影始终是非空 resolved 枚举，恢复时不重新继承。显式 `profile` 必须传 `Some`，
    /// 不能用 `None` 冒充固定模式。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delegation_mode: Option<crate::DelegationMode>,
    /// 草稿同步解析后的自动选模偏好；省略表示继承全局默认。
    ///
    /// 偏好值本身总是具体类别（含 `balanced`），`None` 只表达「本次请求未指定」。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delegation_preference: Option<crate::DelegationPreference>,
    /// 会话工作区模式；省略时按 `local` 解释。
    #[serde(default)]
    pub workspace_mode: crate::ThreadWorkspaceMode,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioPromptInput {
    pub input_id: String,
    pub text: String,
    pub attachment_draft_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetThreadModeRequest {
    pub operation_id: String,
    pub mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RenameThreadRequest {
    pub operation_id: String,
    pub title: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SubmitPromptRequest {
    pub input: StudioPromptInput,
    /// The observed saved route/profile extension revision at the submit intent.
    pub expected_model_route_revision: u64,
}

/// 交互决议请求：用户只能经有权访问的主会话提交与原始请求绑定的决定。
///
/// `host_thread_id` 是承载这张卡片的会话，必须是主会话；原交互的 owner 必须是它的直接子会话
/// 或它自身。`expected_revision` 是调用方观察到的原交互版本，过期请求在产生任何决议副作用
/// 之前被拒绝。原交互记录仍然只保存在其所属会话中，主会话只是投影与调用者身份。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ResolveInteractionRequest {
    pub operation_id: String,
    pub host_thread_id: String,
    pub expected_revision: u64,
    pub resolution: crate::InteractionResolution,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExpectedRevisionRequest {
    pub expected_revision: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExpectedOpaqueRevisionRequest {
    pub expected_revision: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ScopeRequest {
    pub scope: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub server_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RepairLspRequest {
    pub server_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "scope", deny_unknown_fields)]
pub enum McpResetRequest {
    Server { server_id: String },
    All,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "scope", deny_unknown_fields)]
pub enum LspResetRequest {
    Server {
        project_id: String,
        server_id: String,
    },
    Workspace {
        project_id: String,
    },
    All,
}
