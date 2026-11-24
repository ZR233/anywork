//! Typed Interaction aggregates and lifecycle state machines.

mod state;

pub use state::*;

use std::collections::HashMap;
use std::fmt;

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::MessagePresentation;
use crate::{LabeledEnum, UserQuestion};

/// 一个 UserInput 问题的已提交答案。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UserInputAnswer {
    pub answers: Vec<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum InteractionKind {
    UserInput,
    ToolApproval,
}

impl InteractionKind {
    pub fn as_str(self) -> &'static str {
        self.label()
    }
}

/// Interaction lifecycle 的只读投影；不作为可写状态保存。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum InteractionStatus {
    Pending,
    Resolved,
    Cancelled,
    Expired,
}

/// Interaction 的业务用途；UI 仍按 content kind 渲染，不从用途推导领域状态。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum InteractionPurpose {
    #[default]
    General,
    AgentSessionPlanConfirmation(crate::plan_tool::AgentSessionPlanConfirmationPurpose),
}

impl InteractionStatus {
    pub fn as_str(self) -> &'static str {
        self.label()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InteractionScope {
    pub thread_id: String,
    pub turn_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_path: Option<String>,
    #[serde(default)]
    pub purpose: InteractionPurpose,
}

/// Interaction 决议后生成下一条 AgentSession 用户消息的通用预设。
///
/// 创建方决定消息内容来源和 GUI presentation；产品 runtime 只解释这份协议，不能按业务
/// purpose 特判。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InteractionContinuationPreset {
    pub message: InteractionContinuationMessage,
    pub presentation: MessagePresentation,
}

impl InteractionContinuationPreset {
    pub fn resolution(presentation: MessagePresentation) -> Self {
        Self {
            message: InteractionContinuationMessage::Resolution,
            presentation,
        }
    }

    pub fn question(question_id: impl Into<String>, presentation: MessagePresentation) -> Self {
        Self {
            message: InteractionContinuationMessage::Question {
                question_id: question_id.into(),
            },
            presentation,
        }
    }
}

/// continuation 用户消息的内容来源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum InteractionContinuationMessage {
    /// 通用 typed resolution envelope。
    Resolution,
    /// 复用某个 UserInput question 的完整正文。
    Question { question_id: String },
}

/// Interaction kind 与其 payload/state 的唯一绑定。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum InteractionContent {
    UserInput(UserInputInteraction),
    ToolApproval(ToolApprovalInteraction),
}

/// 主会话中的一条只读子任务交互摘要。
///
/// 事实仍归原子会话所有：这里只携带来源成员、原交互身份、类型、revision 与只读展示内容，
/// 供主会话展示与提交决议，不物化第二份可写交互。决定必须回到原交互身份与版本，主会话只是
/// 调用者身份。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChildInteractionSummary {
    /// 持有该交互的成员会话；它就是 `interaction.scope.thread_id`。
    pub child_thread_id: String,
    pub interaction_id: String,
    pub kind: InteractionKind,
    pub revision: u64,
    pub interaction: InteractionRequest,
}

impl ChildInteractionSummary {
    pub fn new(interaction: InteractionRequest) -> Self {
        Self {
            child_thread_id: interaction.scope.thread_id.clone(),
            interaction_id: interaction.interaction_id.clone(),
            kind: interaction.kind(),
            revision: interaction.revision,
            interaction,
        }
    }
}

/// 一个有 identity、revision 与 typed content 的 Interaction 聚合。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InteractionRequest {
    pub interaction_id: String,
    pub scope: InteractionScope,
    pub revision: u64,
    pub content: InteractionContent,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<InteractionContinuationPreset>,
    pub created_at: i64,
    pub updated_at: i64,
}

impl InteractionRequest {
    pub fn user_input(
        interaction_id: impl Into<String>,
        scope: InteractionScope,
        questions: Vec<UserQuestion>,
        created_at: i64,
    ) -> Self {
        let interaction_id = interaction_id.into();
        Self {
            content: InteractionContent::UserInput(UserInputInteraction::new(
                questions,
                interaction_id.clone(),
            )),
            interaction_id,
            scope,
            revision: 0,
            continuation: None,
            created_at,
            updated_at: created_at,
        }
    }

    pub fn tool_approval(
        interaction_id: impl Into<String>,
        scope: InteractionScope,
        request: ToolApprovalRequest,
        created_at: i64,
    ) -> Self {
        let interaction_id = interaction_id.into();
        Self {
            content: InteractionContent::ToolApproval(ToolApprovalInteraction::new(
                request,
                interaction_id.clone(),
            )),
            interaction_id,
            scope,
            revision: 0,
            continuation: None,
            created_at,
            updated_at: created_at,
        }
    }

    pub fn kind(&self) -> InteractionKind {
        match &self.content {
            InteractionContent::UserInput(_) => InteractionKind::UserInput,
            InteractionContent::ToolApproval(_) => InteractionKind::ToolApproval,
        }
    }

    pub fn status(&self) -> InteractionStatus {
        match &self.content {
            InteractionContent::UserInput(value) => value.status(),
            InteractionContent::ToolApproval(value) => value.status(),
        }
    }

    pub fn resolution(&self) -> Option<InteractionResolution> {
        match &self.content {
            InteractionContent::UserInput(value) => value.resolution(),
            InteractionContent::ToolApproval(value) => value.resolution(),
        }
    }

    pub fn with_continuation(mut self, continuation: InteractionContinuationPreset) -> Self {
        self.continuation = Some(continuation);
        self
    }

    pub fn decide(
        &self,
        command: InteractionCommand,
    ) -> Result<InteractionTransitionDecision, InteractionTransitionError> {
        if command.interaction_id() != self.interaction_id {
            return Err(InteractionTransitionError::wrong_interaction(
                self,
                command.name(),
                command.interaction_id(),
            ));
        }
        if command.expected_revision() != self.revision {
            return Err(InteractionTransitionError::stale_revision(
                self,
                command.name(),
                command.expected_revision(),
            ));
        }
        let current = self.status();
        let next_content = match (&self.content, command) {
            (
                InteractionContent::UserInput(value),
                InteractionCommand::ResolveUserInput(command),
            ) => InteractionContent::UserInput(
                value
                    .decide(UserInputCommand::Resolve(command))
                    .map_err(|error| error.at(self))?,
            ),
            (
                InteractionContent::ToolApproval(value),
                InteractionCommand::ResolveToolApproval(command),
            ) => InteractionContent::ToolApproval(
                value
                    .decide(ToolApprovalCommand::Resolve(command))
                    .map_err(|error| error.at(self))?,
            ),
            (InteractionContent::UserInput(value), InteractionCommand::Cancel(command)) => {
                InteractionContent::UserInput(
                    value
                        .decide(UserInputCommand::Cancel(command))
                        .map_err(|error| error.at(self))?,
                )
            }
            (InteractionContent::ToolApproval(value), InteractionCommand::Cancel(command)) => {
                InteractionContent::ToolApproval(
                    value
                        .decide(ToolApprovalCommand::Cancel(command))
                        .map_err(|error| error.at(self))?,
                )
            }
            (_, command) => {
                return Err(
                    InteractionTransitionError::new(self.kind(), current, command.name()).at(self),
                );
            }
        };
        Ok(InteractionTransitionDecision {
            changed: next_content != self.content,
            next_content,
        })
    }

    pub fn apply(&mut self, decision: InteractionTransitionDecision, updated_at: i64) {
        if decision.changed {
            self.content = decision.next_content;
            self.revision = self.revision.saturating_add(1);
            self.updated_at = updated_at;
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InteractionCommand {
    ResolveUserInput(ResolveUserInput),
    ResolveToolApproval(ResolveToolApproval),
    Cancel(CancelInteraction),
}

impl InteractionCommand {
    fn name(&self) -> &'static str {
        match self {
            Self::ResolveUserInput(_) => "resolveUserInput",
            Self::ResolveToolApproval(_) => "resolveToolApproval",
            Self::Cancel(_) => "cancel",
        }
    }

    fn interaction_id(&self) -> &str {
        match self {
            Self::ResolveUserInput(command) => &command.interaction_id,
            Self::ResolveToolApproval(command) => &command.interaction_id,
            Self::Cancel(command) => &command.interaction_id,
        }
    }

    fn expected_revision(&self) -> u64 {
        match self {
            Self::ResolveUserInput(command) => command.expected_revision,
            Self::ResolveToolApproval(command) => command.expected_revision,
            Self::Cancel(command) => command.expected_revision,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InteractionTransitionDecision {
    pub next_content: InteractionContent,
    pub changed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InteractionTransitionError {
    interaction_id: String,
    kind: InteractionKind,
    current: InteractionStatus,
    command: &'static str,
    violation: InteractionTransitionViolation,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum InteractionTransitionViolation {
    IllegalTransition,
    WrongInteraction { actual: String },
    StaleRevision { expected: u64, actual: u64 },
}

impl InteractionTransitionError {
    fn at(mut self, interaction: &InteractionRequest) -> Self {
        self.interaction_id = interaction.interaction_id.clone();
        self
    }

    pub(crate) fn new(
        kind: InteractionKind,
        current: InteractionStatus,
        command: &'static str,
    ) -> Self {
        Self {
            interaction_id: String::new(),
            kind,
            current,
            command,
            violation: InteractionTransitionViolation::IllegalTransition,
        }
    }

    fn wrong_interaction(
        interaction: &InteractionRequest,
        command: &'static str,
        actual: &str,
    ) -> Self {
        Self {
            interaction_id: interaction.interaction_id.clone(),
            kind: interaction.kind(),
            current: interaction.status(),
            command,
            violation: InteractionTransitionViolation::WrongInteraction {
                actual: actual.to_owned(),
            },
        }
    }

    fn stale_revision(
        interaction: &InteractionRequest,
        command: &'static str,
        actual: u64,
    ) -> Self {
        Self {
            interaction_id: interaction.interaction_id.clone(),
            kind: interaction.kind(),
            current: interaction.status(),
            command,
            violation: InteractionTransitionViolation::StaleRevision {
                expected: interaction.revision,
                actual,
            },
        }
    }
}

impl fmt::Display for InteractionTransitionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.violation {
            InteractionTransitionViolation::IllegalTransition => write!(
                formatter,
                "interaction {}/{:?}/{:?} does not accept command {}",
                self.interaction_id, self.kind, self.current, self.command
            ),
            InteractionTransitionViolation::WrongInteraction { actual } => write!(
                formatter,
                "interaction {} rejected command {} for different interaction {}",
                self.interaction_id, self.command, actual
            ),
            InteractionTransitionViolation::StaleRevision { expected, actual } => write!(
                formatter,
                "interaction {} rejected command {} at revision {}; current revision is {}",
                self.interaction_id, self.command, actual, expected
            ),
        }
    }
}

impl std::error::Error for InteractionTransitionError {}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum InteractionResolution {
    UserInput(UserInputResolution),
    ToolApproval(ToolApprovalResolutionPayload),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UserInputResolution {
    pub answers: HashMap<String, UserInputAnswer>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ToolApprovalResolutionPayload {
    pub decision: ToolApprovalResolution,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ToolApprovalResolution {
    Approved,
    Denied,
}

pl_protocol::impl_labeled_enum!(InteractionKind, "InteractionKind", [
    InteractionKind::UserInput => "userInput",
    InteractionKind::ToolApproval => "toolApproval",
]);

pl_protocol::impl_labeled_enum!(InteractionStatus, "InteractionStatus", [
    InteractionStatus::Pending => "pending",
    InteractionStatus::Resolved => "resolved",
    InteractionStatus::Cancelled => "cancelled",
    InteractionStatus::Expired => "expired",
]);
