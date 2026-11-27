//! Agent control tool frontends; directory ownership and access decisions belong to the product host.
use super::control::{
    AgentCallContext, AgentCloseOutcome, AgentInterruptResult, AgentSendResult, AgentSpawnResult,
    ControlError,
};
pub use pl_agent_tool::ToolDefinition;
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
pub use pl_protocol::NewThreadModelRoute;
pub use pl_protocol::{AgentWorkspaceMode, DelegationMode};
pub use serde_json::Error as SchemaEncodingError;
use std::sync::Arc;

/// A real caller context projected at the owning host, never decoded from tool arguments.
pub struct AgentInvocation {
    pub call: AgentCallContext,
    pub message_id: String,
}

pub trait AgentToolContext: Send + 'static {
    fn bind(
        self,
        identity: &pl_protocol::AgentThreadIdentity,
    ) -> Result<AgentInvocation, ControlError>;
}

impl AgentToolContext for CallContext {
    fn bind(
        self,
        identity: &pl_protocol::AgentThreadIdentity,
    ) -> Result<AgentInvocation, ControlError> {
        if self.thread_id != identity.thread_id.as_str() {
            return Err(ControlError::Missing(self.thread_id));
        }
        Ok(AgentInvocation {
            message_id: format!(
                "agent-message:{}:{}:{}",
                self.thread_id.len(),
                self.thread_id,
                self.call_id
            ),
            call: AgentCallContext {
                caller: identity.agent_id.clone(),
                call_id: self.call_id,
                cancellation: self.cancellation,
            },
        })
    }
}

impl AgentToolContext for AgentCallContext {
    fn bind(
        self,
        identity: &pl_protocol::AgentThreadIdentity,
    ) -> Result<AgentInvocation, ControlError> {
        if self.caller != identity.agent_id {
            return Err(ControlError::Missing(self.caller.to_string()));
        }
        Ok(AgentInvocation {
            message_id: self.call_id.clone(),
            call: self,
        })
    }
}

/// One executable Profile selected by the product from a single published catalog generation.
#[derive(Debug, Clone)]
pub struct AgentSpawnProfile {
    pub profile_id: String,
    pub workspace_mode: AgentWorkspaceMode,
    pub backend: pl_protocol::AgentBackendKind,
}

/// A malformed declaration is a catalog failure, never permission to expose a generic schema.
#[derive(Debug, thiserror::Error)]
pub enum AgentSpawnSchemaError {
    #[error("invalid generated spawn schema: {0}")]
    Shape(&'static str),
    #[error("duplicate spawn Profile identity: {0}")]
    DuplicateProfile(String),
    #[error("failed to encode spawn schema")]
    Encoding(#[from] SchemaEncodingError),
}

/// A message whose id is assigned from the trusted core call identity, never supplied by model arguments.
#[derive(Debug)]
pub struct AgentMessage {
    pub id: String,
    pub target: String,
    pub message: String,
}

/// 子智能体创建参数；Profile 的解释与权限由 Studio 管理。
#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentSpawn {
    pub profile_id: String,
    /// ACP 的有序会话选项，在首条消息前应用。
    /// 使用服务声明的选项 ID，以及字符串值 ID 或布尔值。
    #[serde(default)]
    pub acp_config: Vec<AcpSessionConfig>,
    /// 仅在自动分发的 Native 目标中必填；ACP 始终拒绝路由覆盖。
    #[serde(default)]
    pub model_selection: Option<NewThreadModelRoute>,
    /// 子会话列表显示的简短任务说明；必填、非空，最多 80 个 Unicode 字符。
    pub task_summary: AgentTaskSummary,
    /// 任务目标和关键约束，以及完整上下文或可访问交接文件的引用、用途与版本。二者共同覆盖已批准契约、事实、接口、责任归属和验证要求。应用层不限制长度。
    pub message: String,
    /// 可选的工作区相对可写目录，仅 directory Profile 接受。
    pub writable_paths: Option<Vec<String>>,
    /// 被审查的直接子智能体 agentId；review Profile 必填，其他 Profile 拒绝。宿主采用该成员的冻结工作区。
    pub review_target_agent_id: Option<String>,
    /// 可选的宿主绑定审查反馈，发给被审执行者；仅 review Profile 接受。
    #[serde(default, deserialize_with = "review_feedback")]
    pub review_feedback: Option<ReviewFeedback>,
    /// 内部创建元数据，不暴露在模型参数中。
    #[serde(default)]
    #[schemars(skip)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpSessionConfig {
    pub id: String,
    pub value: AcpSessionConfigValue,
}

#[derive(Debug, Clone, serde::Deserialize, schemars::JsonSchema)]
#[serde(untagged)]
pub enum AcpSessionConfigValue {
    Select(String),
    Boolean(bool),
}

pub use pl_protocol::AgentReviewFeedback as ReviewFeedback;

fn review_feedback<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<ReviewFeedback>, D::Error> {
    serde::Deserialize::deserialize(deserializer).map(Some)
}

/// Validated single-line task title, supplied by the caller before child resources are allocated.
#[derive(Debug, Clone, serde::Deserialize, schemars::JsonSchema)]
#[serde(try_from = "String")]
#[schemars(with = "String", extend("minLength" = 1, "maxLength" = 80))]
pub struct AgentTaskSummary(String);

#[derive(Debug, thiserror::Error)]
pub enum AgentTaskSummaryError {
    #[error("taskSummary cannot be empty")]
    Empty,
    #[error("taskSummary exceeds 80 Unicode characters")]
    TooLong,
}

impl TryFrom<String> for AgentTaskSummary {
    type Error = AgentTaskSummaryError;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        let normalized = value.split_whitespace().collect::<Vec<_>>().join(" ");
        if normalized.is_empty() {
            return Err(AgentTaskSummaryError::Empty);
        }
        if normalized.chars().count() > 80 {
            return Err(AgentTaskSummaryError::TooLong);
        }
        Ok(Self(normalized))
    }
}

impl AgentTaskSummary {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Physical workspace release used by host shutdown and explicit project archival.
/// This is not a `close_agent` policy or permission to retire a child's saved session.
#[derive(
    Debug,
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    serde::Serialize,
    serde::Deserialize,
    schemars::JsonSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceRelease {
    /// Retain the workspace and its recoverable lease for later inspection or integration.
    #[default]
    Preserve,
    /// The host has independently authorized disposal (for example project archival).
    Cleanup,
}

/// Explicit final child close. Force only permits discarding dirty or unmerged child content;
/// identity, locks, borrowers, process exit and durable storage acknowledgements remain required.
#[derive(Debug, Clone, Copy, Default, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentCloseOptions {
    #[serde(default)]
    pub force: bool,
}

/// Product coordinator ports. Native encoding belongs to the frontend, not the owner.
pub trait AgentControlHost: Send + Sync + std::fmt::Debug + 'static {
    fn spawn(
        &self,
        context: AgentCallContext,
        request: AgentSpawn,
    ) -> impl std::future::Future<Output = Result<AgentSpawnResult, ControlError>> + Send;
    fn send(
        &self,
        context: AgentCallContext,
        message: AgentMessage,
    ) -> impl std::future::Future<Output = Result<AgentSendResult, ControlError>> + Send;
    fn list(
        &self,
        context: AgentCallContext,
    ) -> impl std::future::Future<Output = Result<Vec<serde_json::Value>, ControlError>> + Send;
    fn interrupt(
        &self,
        context: AgentCallContext,
        target: &str,
    ) -> impl std::future::Future<Output = Result<AgentInterruptResult, ControlError>> + Send;
    fn close(
        &self,
        context: AgentCallContext,
        target: &str,
        options: AgentCloseOptions,
    ) -> impl std::future::Future<Output = Result<AgentCloseOutcome, ControlError>> + Send;
}

/// Stable agent-control operations; none grants permission to bypass the host's relationship checks.
#[derive(Debug, Clone, Copy)]
pub enum AgentControlKind {
    Spawn,
    Send,
    List,
    Interrupt,
    Close,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct Empty {}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct Target {
    target: String,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CloseInput {
    target: String,
    #[serde(default)]
    force: bool,
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct SendInput {
    target: String,
    /// Full continuation, including new decisions, superseded requirements and acceptance criteria. No application length limit.
    message: String,
}

impl AgentControlKind {
    /// Uses the product's same-generation executable Profile view and frozen delegation mode.
    /// Automatic mode requires model selection; fixed mode omits it. An empty view omits spawn.
    /// Other controls never include current agents, statuses or execution identities.
    ///
    /// # Errors
    /// Returns schema construction failures or duplicate Profile identities; no fallback is emitted.
    pub fn declaration(
        self,
        profiles: &[AgentSpawnProfile],
        mode: DelegationMode,
    ) -> Result<Option<ToolDefinition>, AgentSpawnSchemaError> {
        Ok(Some(match self {
            Self::Spawn => return super::spawn_schema::declaration(profiles, mode),
            Self::Send => pl_agent_tool::ToolDefinition::json(
                "send_message",
                "Send a prompt to a direct child. Interrupt its active turn and continue with this message after tool cleanup; start it if idle. The receipt confirms acceptance, not completion.",
                pl_agent_tool::typed::input_schema_for::<SendInput>(),
            ).expect("valid tool definition")
                .with_output_schema(crate::binding::program_schema::<AgentSendResult>())
                .expect("static send message schema"),
            Self::List => pl_agent_tool::ToolDefinition::json(
                "list_agents",
                "List agents visible within the caller's thread tree.",
                pl_agent_tool::typed::input_schema_for::<Empty>(),
            ).expect("valid tool definition"),
            Self::Interrupt => pl_agent_tool::ToolDefinition::json(
                "interrupt_agent",
                "Pause queued execution and interrupt a descendant agent's active turn.",
                pl_agent_tool::typed::input_schema_for::<Target>(),
            ).expect("valid tool definition")
                .with_output_schema(crate::binding::program_schema::<AgentInterruptResult>())
                .expect("static interrupt result schema"),
            Self::Close => pl_agent_tool::ToolDefinition::json(
                "close_agent",
                "If you are a Native root retiring a direct Native child after final acceptance, call evaluate_agent separately and check its successful receipt before calling close_agent. Permanently close a descendant and its descendants: stop and join execution, tools and processes, await existing save acknowledgements, and remove only each child's own existing bound Git worktree. Full history, checkpoints, reliable attachments, reports, statistics, evaluations, independent session files and branch refs are retained. Finish review and integration first; otherwise keep it idle or interrupt it. By default dirty/untracked changes or a child HEAD not contained in the actual root delivery HEAD block worktree cleanup. force=true permits discarding only that content, never bypassing ownership, Git identity or locks, active borrowers, process exit or save acknowledgements. The result reports executionClosed and worktreeCleanup per agent; partial failure retains all member facts and may be retried only against the original binding.",
                pl_agent_tool::typed::input_schema_for::<CloseInput>(),
            ).expect("valid tool definition"),
        }))
    }
}

/// One Thread's frontend over a shared product coordination service.
pub struct ThreadAgentControl<H, C = CallContext> {
    definition: ToolDefinition,
    host: Arc<H>,
    kind: AgentControlKind,
    caller: pl_protocol::AgentThreadIdentity,
    validate: Box<dyn Fn() -> Result<(), ControlError> + Send + Sync>,
    context: std::marker::PhantomData<fn(C)>,
}

impl<H: std::fmt::Debug, C> std::fmt::Debug for ThreadAgentControl<H, C> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ThreadAgentControl")
            .field("host", &self.host)
            .field("kind", &self.kind)
            .field("caller", &self.caller)
            .finish_non_exhaustive()
    }
}

impl<H: AgentControlHost, C> ThreadAgentControl<H, C> {
    /// Associates an operation with its product-owned coordinator.
    pub fn new(
        host: Arc<H>,
        kind: AgentControlKind,
        definition: ToolDefinition,
        caller: pl_protocol::AgentThreadIdentity,
        validate: impl Fn() -> Result<(), ControlError> + Send + Sync + 'static,
    ) -> Self {
        Self {
            host,
            kind,
            definition,
            caller,
            validate: Box::new(validate),
            context: std::marker::PhantomData,
        }
    }
}

impl<H: AgentControlHost> ThreadAgentControl<H> {
    /// Transfers an executor; product coordination remains behind the host port.
    ///
    /// The supplied preparation has already validated the registration identity.
    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        let kind = self.kind;
        let contract = match kind {
            AgentControlKind::Spawn => Some("builtin.spawn_agent@1"),
            AgentControlKind::Send => Some("builtin.send_message@1"),
            AgentControlKind::List | AgentControlKind::Interrupt | AgentControlKind::Close => None,
        };
        let mut registration = prepared.attach(pl_agent_tool::ToolHandle::new(self));
        if let Some(contract) = contract {
            registration = registration.with_presentation_contract(
                pl_core::model::ToolPresentationContract::new(contract),
            );
        }
        match kind {
            AgentControlKind::List => registration,
            AgentControlKind::Spawn
            | AgentControlKind::Send
            | AgentControlKind::Interrupt
            | AgentControlKind::Close => registration.foreground(),
        }
    }
}

impl<H: AgentControlHost, C: AgentToolContext> pl_agent_tool::Tool for ThreadAgentControl<H, C> {
    type Input = pl_core::context::OpaquePayload;
    type Context = C;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: OpaquePayload, context: C) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(std::io::Error::other(
                "unsupported agent control encoding",
            )));
        }
        let invocation = context.bind(&self.caller).map_err(ToolError::new)?;
        let call = invocation.call;
        if call.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        (self.validate)().map_err(ToolError::new)?;
        match self.kind {
            AgentControlKind::Spawn => {
                let request: AgentSpawn =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let result = self
                    .host
                    .spawn(call, request)
                    .await
                    .map_err(ToolError::new)?;
                let receipt = output(result.receipt)?;
                match result.message_error {
                    Some(error) => Err(ToolError::new(error).with_output(receipt)),
                    None => Ok(receipt),
                }
            }
            AgentControlKind::Send => {
                let input: SendInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let result = self
                    .host
                    .send(
                        call,
                        AgentMessage {
                            id: invocation.message_id,
                            target: input.target,
                            message: input.message,
                        },
                    )
                    .await
                    .map_err(ToolError::new)?;
                output(result)
            }
            AgentControlKind::List => {
                let _: Empty =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                output(self.host.list(call).await.map_err(ToolError::new)?)
            }
            AgentControlKind::Interrupt => {
                let target: Target =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                output(
                    self.host
                        .interrupt(call, &target.target)
                        .await
                        .map_err(ToolError::new)?,
                )
            }
            AgentControlKind::Close => {
                let target: CloseInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let outcome = self
                    .host
                    .close(
                        call,
                        &target.target,
                        AgentCloseOptions {
                            force: target.force,
                        },
                    )
                    .await
                    .map_err(ToolError::new)?;
                let receipt = output(&outcome)?;
                match outcome.error {
                    Some(error) => Err(ToolError::new(CloseIncomplete(error)).with_output(receipt)),
                    None => Ok(receipt),
                }
            }
        }
    }
}

#[derive(Debug, thiserror::Error)]
#[error("Agent service failed: {}", .0.message)]
struct CloseIncomplete(pl_protocol::StateError);

fn output(value: impl serde::Serialize) -> Result<ToolOutput, ToolError> {
    serde_json::to_value(value)
        .map(ToolOutput::json)
        .map_err(ToolError::new)
}
