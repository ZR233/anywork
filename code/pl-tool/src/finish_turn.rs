//! Explicit Turn handoff. Ending a Turn does not assert that the assigned task is complete.
pub use pl_agent_tool::ToolDefinition;
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, ToolError},
};
pub use pl_core::{
    context::OpaquePayload,
    tool::opaque::{Registration, RegistryError},
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
pub use serde_json::Error as ReportDecodeError;

pub const TOOL_FINISH_TURN: &str = "finish_turn";

/// Full report, retained without truncation or whitespace normalization.
#[derive(Debug, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FinishTurnInput {
    /// Complete Markdown report: outcome, evidence, problems and requested next action. No application length limit.
    #[schemars(length(min = 1))]
    pub message: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub review: Option<ReviewResult>,
}

#[derive(Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
struct OrdinaryFinishTurnInput {
    /// Complete Markdown report; no application length limit.
    #[schemars(length(min = 1))]
    message: String,
}

/// Ordinary roles do not advertise or accept a review parameter, including explicit null.
pub fn declaration() -> ToolDefinition {
    ToolDefinition::json(
        TOOL_FINISH_TURN,
        "End this Turn with a complete Markdown report. This does not declare the task complete.",
        pl_agent_tool::typed::input_schema_for::<OrdinaryFinishTurnInput>(),
    )
    .expect("valid tool definition")
}

pub fn review_declaration() -> ToolDefinition {
    ToolDefinition::json(
        TOOL_FINISH_TURN,
        "End this review Turn with the full report and an optional structured review conclusion. reviewedVersion must identify the actual reviewed commit or diff/content; it is not a host verification of disk state.",
        pl_agent_tool::typed::input_schema_for::<FinishTurnInput>(),
    ).expect("valid tool definition")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum ReviewDisposition {
    Approved,
    NeedsChanges,
    Inconclusive,
}

#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReviewResult {
    pub disposition: ReviewDisposition,
    #[schemars(length(min = 1, max = 512))]
    pub summary: String,
    #[schemars(length(min = 1, max = 2048))]
    pub reviewed_version: String,
}

/// Producer-owned receipt. The saved wrapper is never rebuilt by a later host renderer.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SavedFinishTurn {
    pub message: String,
    pub review: Option<ReviewResult>,
    pub feedback_message: Option<String>,
}

#[derive(Debug)]
pub struct FinishTurnTool {
    definition: ToolDefinition,
    review: Option<ReviewAuthority>,
}

/// Host-selected role authority, never accepted from model arguments.
#[derive(Debug)]
pub struct ReviewAuthority {
    /// Frozen host explanation, including the reviewer and its unique bound executor.
    pub feedback_prefix: String,
}

#[derive(Debug, thiserror::Error)]
#[error("message must contain a non-whitespace character")]
struct EmptyReport;

#[derive(Debug, thiserror::Error)]
enum InvalidReview {
    #[error("review results require a valid frozen review workspace and Profile")]
    Unauthorized,
    #[error("review summary must be nonempty and at most 512 Unicode characters")]
    Summary,
    #[error("reviewedVersion must be nonempty and at most 2048 Unicode characters")]
    Version,
}

/// Reads an immutable saved report without granting execution authority.
/// # Errors
/// Returns a decoding error for a malformed recognized payload.
pub fn saved_message(payload: &OpaquePayload) -> Result<Option<String>, ReportDecodeError> {
    Ok(saved_report(payload)?.map(|report| report.message))
}

/// Decodes historical v1 as message only; body text never implies a review disposition.
/// # Errors
/// Returns a decoding error for a malformed recognized payload.
pub fn saved_report(payload: &OpaquePayload) -> Result<Option<SavedFinishTurn>, ReportDecodeError> {
    if payload.format() != "pl.tool.finish-turn" {
        return Ok(None);
    }
    match payload.version() {
        1 => {
            #[derive(Deserialize)]
            #[serde(deny_unknown_fields)]
            struct LegacyReport {
                message: String,
            }
            let report: LegacyReport = serde_json::from_str(payload.content())?;
            Ok(Some(SavedFinishTurn {
                message: report.message,
                review: None,
                feedback_message: None,
            }))
        }
        2 => serde_json::from_str(payload.content()).map(Some),
        _ => Ok(None),
    }
}

/// Registers explicit Turn-ending authority.
/// The supplied preparation has already validated the registration identity.
pub fn registration(
    prepared: pl_core::tool::opaque::PreparedRegistration,
    definition: ToolDefinition,
) -> Registration {
    registration_with_review(prepared, None, definition)
}

/// Registers a host-selected review role alongside explicit Turn-ending authority.
/// The supplied definition must match the host-selected ordinary or review role.
pub fn registration_with_review(
    prepared: pl_core::tool::opaque::PreparedRegistration,
    review: Option<ReviewAuthority>,
    definition: ToolDefinition,
) -> Registration {
    prepared
        .attach(pl_agent_tool::ToolHandle::new(FinishTurnTool {
            definition,
            review,
        }))
        .with_turn_completion()
}

impl pl_agent_tool::Tool for FinishTurnTool {
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
        let report: FinishTurnInput = if self.review.is_some() {
            pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?
        } else {
            let ordinary: OrdinaryFinishTurnInput =
                pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
            FinishTurnInput {
                message: ordinary.message,
                review: None,
            }
        };
        if report.message.trim().is_empty() {
            return Err(ToolError::new(EmptyReport));
        }
        if let Some(review) = &report.review {
            if self.review.is_none() {
                return Err(ToolError::new(InvalidReview::Unauthorized));
            }
            if review.summary.trim().is_empty() || review.summary.chars().count() > 512 {
                return Err(ToolError::new(InvalidReview::Summary));
            }
            if review.reviewed_version.trim().is_empty()
                || review.reviewed_version.chars().count() > 2048
            {
                return Err(ToolError::new(InvalidReview::Version));
            }
        }
        let saved = SavedFinishTurn {
            feedback_message: self.review.as_ref().and_then(|authority| {
                report.review.as_ref().map(|review| {
                    format!(
                        "{}\n审查轮次：{}\n结构化结论：{}\n审查版本：{}\n摘要：{}\n\n{}",
                        authority.feedback_prefix,
                        context.turn_id,
                        match review.disposition {
                            ReviewDisposition::Approved => "approved",
                            ReviewDisposition::NeedsChanges => "needsChanges",
                            ReviewDisposition::Inconclusive => "inconclusive",
                        },
                        review.reviewed_version,
                        review.summary,
                        report.message
                    )
                })
            }),
            message: report.message,
            review: report.review,
        };
        let payload = OpaquePayload::new(
            "pl.tool.finish-turn",
            2,
            serde_json::to_string(&saved).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            payload,
            vec![pl_core::context::ContextContent::Text {
                text: saved.message.into(),
            }],
        )
        .ending_turn())
    }
}
