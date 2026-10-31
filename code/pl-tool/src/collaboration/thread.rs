//! Agent control tool frontends; directory ownership and access decisions belong to the product host.
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
    },
};
pub use pl_protocol::studio::NewThreadModelRoute;
pub use pl_protocol::{AgentWorkspaceMode, DelegationMode, ToolSpec};
pub use serde_json::Error as SchemaEncodingError;
use std::sync::Arc;

/// One executable Profile selected by the product from a single published catalog generation.
#[derive(Debug, Clone)]
pub struct AgentSpawnProfile {
    pub profile_id: String,
    pub workspace_mode: AgentWorkspaceMode,
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

/// Child creation parameters; Profile interpretation and permissions belong to Studio.
#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentSpawn {
    pub profile_id: String,
    /// Required only in automatic delegation; fixed Profile mode rejects overrides.
    #[serde(default)]
    pub model_selection: Option<NewThreadModelRoute>,
    /// Brief task description shown in the child list; required, nonempty, at most 80 Unicode characters.
    pub task_summary: AgentTaskSummary,
    /// Full self-contained task: goals, approved contract, facts, interfaces, steps, ownership and verification. No application length limit; include pseudocode when useful.
    pub message: String,
    /// Optional workspace-relative write directories, accepted only by directory Profiles.
    pub writable_paths: Option<Vec<String>>,
    /// Pure agentId of the reviewed direct child; required by review Profiles and rejected otherwise. The host adopts that agent's frozen workspace.
    pub review_target_agent_id: Option<String>,
    /// Optional host-bound feedback to the reviewed executor; accepted only by review Profiles.
    #[serde(default, deserialize_with = "review_feedback")]
    pub review_feedback: Option<ReviewFeedback>,
    /// Product-owned creation metadata; never interpreted as framework permissions.
    #[serde(default)]
    pub metadata: serde_json::Value,
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

/// Product coordinator ports. Return the original business facts and the chosen model projection together.
pub trait AgentControlHost: Send + Sync + std::fmt::Debug + 'static {
    fn spawn(
        &self,
        context: CallContext,
        request: AgentSpawn,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn send(
        &self,
        caller: &str,
        message: AgentMessage,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn list(
        &self,
        caller: &str,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn interrupt(
        &self,
        caller: &str,
        target: &str,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn close(
        &self,
        caller: &str,
        target: &str,
        options: AgentCloseOptions,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
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
    ) -> Result<Option<ToolSpec>, AgentSpawnSchemaError> {
        Ok(Some(match self {
            Self::Spawn => return super::spawn_schema::declaration(profiles, mode),
            Self::Send => pl_protocol::ToolSpec::function(
                "send_message",
                "Send a prompt to a direct child. Interrupt its active turn and continue with this message after tool cleanup; start it if idle. The receipt confirms acceptance, not completion.",
                schemars::schema_for!(SendInput).to_value(),
            ),
            Self::List => pl_protocol::ToolSpec::function(
                "list_agents",
                "List agents visible within the caller's thread tree.",
                schemars::schema_for!(Empty).to_value(),
            ),
            Self::Interrupt => pl_protocol::ToolSpec::function(
                "interrupt_agent",
                "Pause queued execution and interrupt a descendant agent's active turn.",
                schemars::schema_for!(Target).to_value(),
            ),
            Self::Close => pl_protocol::ToolSpec::function(
                "close_agent",
                "Permanently close a descendant and its descendants: stop and join execution, tools and processes, await existing save acknowledgements, and remove only each child's own existing bound Git worktree. Full history, checkpoints, reliable attachments, reports, statistics, evaluations, independent session files and branch refs are retained. Finish review and integration first; otherwise keep it idle or interrupt it. By default dirty/untracked changes or a child HEAD not contained in the actual root delivery HEAD block worktree cleanup. force=true permits discarding only that content, never bypassing ownership, Git identity or locks, active borrowers, process exit or save acknowledgements. The result reports executionClosed and worktreeCleanup per agent; partial failure retains all member facts and may be retried only against the original binding.",
                schemars::schema_for!(CloseInput).to_value(),
            ),
        }))
    }
}

/// One Thread's frontend over a shared product coordination service.
#[derive(Debug)]
pub struct ThreadAgentControl<H> {
    host: Arc<H>,
    kind: AgentControlKind,
}

impl<H: AgentControlHost> ThreadAgentControl<H> {
    /// Associates an operation with its product-owned coordinator.
    pub fn new(host: Arc<H>, kind: AgentControlKind) -> Self {
        Self { host, kind }
    }

    /// Transfers an executor; product coordination remains behind the host port.
    ///
    /// # Errors
    /// Returns invalid registry identity errors.
    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        let name = match self.kind {
            AgentControlKind::Spawn => "spawn_agent",
            AgentControlKind::Send => "send_message",
            AgentControlKind::List => "list_agents",
            AgentControlKind::Interrupt => "interrupt_agent",
            AgentControlKind::Close => "close_agent",
        };
        let kind = self.kind;
        let contract = match kind {
            AgentControlKind::Spawn => Some("builtin.spawn_agent@1"),
            AgentControlKind::Send => Some("builtin.send_message@1"),
            AgentControlKind::List | AgentControlKind::Interrupt | AgentControlKind::Close => None,
        };
        let mut registration = Registration::new(name.into(), declaration, self)?;
        if let Some(contract) = contract {
            registration = registration.with_presentation_contract(
                pl_core::model::ToolPresentationContract::new(contract),
            );
        }
        Ok(match kind {
            AgentControlKind::List => registration,
            AgentControlKind::Spawn
            | AgentControlKind::Send
            | AgentControlKind::Interrupt
            | AgentControlKind::Close => registration.foreground(),
        })
    }
}

impl<H: AgentControlHost> Tool for ThreadAgentControl<H> {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(std::io::Error::other(
                "unsupported agent control encoding",
            )));
        }
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        match self.kind {
            AgentControlKind::Spawn => {
                let request: AgentSpawn =
                    serde_json::from_str(input.content()).map_err(ToolError::new)?;
                self.host.spawn(context, request).await
            }
            AgentControlKind::Send => {
                let input: SendInput =
                    serde_json::from_str(input.content()).map_err(ToolError::new)?;
                self.host
                    .send(
                        &context.thread_id,
                        AgentMessage {
                            id: format!(
                                "agent-message:{}:{}:{}",
                                context.thread_id.len(),
                                context.thread_id,
                                context.call_id
                            ),
                            target: input.target,
                            message: input.message,
                        },
                    )
                    .await
            }
            AgentControlKind::List => {
                let _: Empty = serde_json::from_str(input.content()).map_err(ToolError::new)?;
                self.host.list(&context.thread_id).await
            }
            AgentControlKind::Interrupt => {
                let target: Target =
                    serde_json::from_str(input.content()).map_err(ToolError::new)?;
                self.host
                    .interrupt(&context.thread_id, &target.target)
                    .await
            }
            AgentControlKind::Close => {
                let target: CloseInput =
                    serde_json::from_str(input.content()).map_err(ToolError::new)?;
                self.host
                    .close(
                        &context.thread_id,
                        &target.target,
                        AgentCloseOptions {
                            force: target.force,
                        },
                    )
                    .await
            }
        }
    }
}
