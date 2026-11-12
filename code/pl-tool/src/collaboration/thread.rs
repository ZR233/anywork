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
pub use pl_protocol::studio::NewThreadModelRoute;
pub use pl_protocol::{AgentWorkspaceMode, DelegationMode};
pub use serde_json::Error as SchemaEncodingError;
use std::sync::Arc;

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

/// Child creation parameters; Profile interpretation and permissions belong to Studio.
#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentSpawn {
    pub profile_id: String,
    /// Required only for Native targets in automatic delegation; ACP always rejects overrides.
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
            ).expect("valid tool definition"),
            Self::List => pl_agent_tool::ToolDefinition::json(
                "list_agents",
                "List agents visible within the caller's thread tree.",
                pl_agent_tool::typed::input_schema_for::<Empty>(),
            ).expect("valid tool definition"),
            Self::Interrupt => pl_agent_tool::ToolDefinition::json(
                "interrupt_agent",
                "Pause queued execution and interrupt a descendant agent's active turn.",
                pl_agent_tool::typed::input_schema_for::<Target>(),
            ).expect("valid tool definition"),
            Self::Close => pl_agent_tool::ToolDefinition::json(
                "close_agent",
                "Permanently close a descendant and its descendants: stop and join execution, tools and processes, await existing save acknowledgements, and remove only each child's own existing bound Git worktree. Full history, checkpoints, reliable attachments, reports, statistics, evaluations, independent session files and branch refs are retained. Finish review and integration first; otherwise keep it idle or interrupt it. By default dirty/untracked changes or a child HEAD not contained in the actual root delivery HEAD block worktree cleanup. force=true permits discarding only that content, never bypassing ownership, Git identity or locks, active borrowers, process exit or save acknowledgements. The result reports executionClosed and worktreeCleanup per agent; partial failure retains all member facts and may be retried only against the original binding.",
                pl_agent_tool::typed::input_schema_for::<CloseInput>(),
            ).expect("valid tool definition"),
        }))
    }
}

/// One Thread's frontend over a shared product coordination service.
pub struct ThreadAgentControl<H> {
    definition: ToolDefinition,
    host: Arc<H>,
    kind: AgentControlKind,
    caller: pl_protocol::AgentThreadIdentity,
    validate: Box<dyn Fn() -> Result<(), ControlError> + Send + Sync>,
}

impl<H: std::fmt::Debug> std::fmt::Debug for ThreadAgentControl<H> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ThreadAgentControl")
            .field("host", &self.host)
            .field("kind", &self.kind)
            .field("caller", &self.caller)
            .finish_non_exhaustive()
    }
}

impl<H: AgentControlHost> ThreadAgentControl<H> {
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
        }
    }

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

impl<H: AgentControlHost> pl_agent_tool::Tool for ThreadAgentControl<H> {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

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
        if context.thread_id != self.caller.thread_id.as_str() {
            return Err(ToolError::new(ControlError::Missing(context.thread_id)));
        }
        (self.validate)().map_err(ToolError::new)?;
        let call = AgentCallContext {
            caller: self.caller.agent_id.clone(),
            call_id: context.call_id.clone(),
            cancellation: context.cancellation,
        };
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
    let encoded = serde_json::to_string(&value).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.studio.agent-control", 1, encoded.clone())
            .map_err(ToolError::new)?,
        vec![pl_core::context::ContextContent::Text {
            text: Arc::from(encoded),
        }],
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::collaboration::control::{AgentCloseResult, AgentWorktreeCleanup, SpawnReceipt};

    #[test]
    fn spawn_receipt_preserves_native_wire_and_model_projection() {
        let receipt = SpawnReceipt {
            agent_id: "published-child".into(),
            profile_id: "executor".into(),
            model: Some(NewThreadModelRoute {
                account_id: "account".into(),
                model_id: "model".into(),
                effort: None,
            }),
            delegation: Default::default(),
            workspace: None,
            message_accepted: false,
            message_sequence: None,
        };
        let encoded = output(receipt).unwrap();
        assert_eq!(encoded.payload().format(), "pl.studio.agent-control");
        assert_eq!(encoded.payload().version(), 1);
        let value: serde_json::Value = serde_json::from_str(encoded.payload().content()).unwrap();
        assert_eq!(value["agentId"], "published-child");
        assert_eq!(value["messageAccepted"], false);
        assert!(value.get("messageSequence").is_none());
        assert!(
            matches!(encoded.context(), [pl_core::context::ContextContent::Text { text }]
            if text.as_ref() == encoded.payload().content())
        );
    }

    #[test]
    fn close_outcome_keeps_every_member_and_cleanup_fact() {
        let outcome = AgentCloseOutcome {
            target: "child".into(),
            agents: vec![
                AgentCloseResult {
                    agent_id: "grandchild".into(),
                    execution_closed: true,
                    worktree_cleanup: AgentWorktreeCleanup::NotPresent {
                        path: "/workspace/child".into(),
                        registration_present: true,
                    },
                },
                AgentCloseResult {
                    agent_id: "child".into(),
                    execution_closed: false,
                    worktree_cleanup: AgentWorktreeCleanup::Pending,
                },
            ],
            error: Some(pl_protocol::StateError {
                code: "agentCloseIncomplete".into(),
                message: "save ACK failed".into(),
                retryable: true,
            }),
        };
        let encoded = output(outcome).unwrap();
        let value: serde_json::Value = serde_json::from_str(encoded.payload().content()).unwrap();
        assert_eq!(value["agents"][0]["worktreeCleanup"]["kind"], "notPresent");
        assert_eq!(
            value["agents"][0]["worktreeCleanup"]["registrationPresent"],
            true
        );
        assert_eq!(value["agents"][1]["executionClosed"], false);
        assert_eq!(value["agents"][1]["worktreeCleanup"]["kind"], "pending");
        assert_eq!(value["error"]["code"], "agentCloseIncomplete");
    }
}
