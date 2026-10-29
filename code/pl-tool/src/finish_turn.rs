//! Explicit Turn handoff. Ending a Turn does not assert that the assigned task is complete.
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Tool, ToolError},
};
pub use pl_core::{
    context::OpaquePayload,
    tool::opaque::{Registration, RegistryError},
};
pub use pl_protocol::ToolSpec;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
pub use serde_json::Error as ReportDecodeError;

pub const TOOL_FINISH_TURN: &str = "finish_turn";
/// Producer-owned report identity; historical and unknown versions remain opaque.
pub const FINISH_TURN_FORMAT: &str = "pl.tool.finish-turn";
pub const FINISH_TURN_VERSION: u32 = 2;

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
pub fn declaration() -> ToolSpec {
    ToolSpec::function(
        TOOL_FINISH_TURN,
        "End this Turn with a complete Markdown report. This does not declare the task complete.",
        schemars::schema_for!(OrdinaryFinishTurnInput).to_value(),
    )
}

pub fn review_declaration() -> ToolSpec {
    ToolSpec::function(
        TOOL_FINISH_TURN,
        "End this review Turn with the full report and an optional structured review conclusion. reviewedVersion must identify the actual reviewed commit or diff/content; it is not a host verification of disk state.",
        schemars::schema_for!(FinishTurnInput).to_value(),
    )
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

/// Decodes only the current saved report without granting execution authority.
/// # Errors
/// Returns a decoding error for a malformed recognized payload.
pub fn saved_report(payload: &OpaquePayload) -> Result<Option<SavedFinishTurn>, ReportDecodeError> {
    if payload.format() != FINISH_TURN_FORMAT || payload.version() != FINISH_TURN_VERSION {
        return Ok(None);
    }
    serde_json::from_str(payload.content()).map(Some)
}

/// Registers explicit Turn-ending authority.
/// # Errors
/// Propagates invalid registration identity.
pub fn registration(declaration: OpaquePayload) -> Result<Registration, RegistryError> {
    registration_with_review(declaration, None)
}

/// Registers a host-selected review role alongside explicit Turn-ending authority.
/// # Errors
/// Propagates invalid registration identity.
pub fn registration_with_review(
    declaration: OpaquePayload,
    review: Option<ReviewAuthority>,
) -> Result<Registration, RegistryError> {
    Ok(Registration::new(
        TOOL_FINISH_TURN.into(),
        declaration,
        FinishTurnTool { review },
    )?
    .with_turn_completion())
}

impl Tool for FinishTurnTool {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let report: FinishTurnInput = if self.review.is_some() {
            serde_json::from_str(input.content()).map_err(ToolError::new)?
        } else {
            let ordinary: OrdinaryFinishTurnInput =
                serde_json::from_str(input.content()).map_err(ToolError::new)?;
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
            FINISH_TURN_FORMAT,
            FINISH_TURN_VERSION,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn current_saved_report_preserves_full_message_and_review() {
        let saved = SavedFinishTurn {
            message: " \n完整报告\n".repeat(4096),
            review: Some(ReviewResult {
                disposition: ReviewDisposition::NeedsChanges,
                summary: "必须修复".into(),
                reviewed_version: "commit:1234".into(),
            }),
            feedback_message: Some("冻结身份与原始回送正文\n".into()),
        };
        let payload = OpaquePayload::new(
            FINISH_TURN_FORMAT,
            FINISH_TURN_VERSION,
            serde_json::to_string(&saved).unwrap(),
        )
        .unwrap();
        let original = payload.clone();
        let report = saved_report(&payload).unwrap().unwrap();
        assert_eq!(report.message, saved.message);
        assert_eq!(report.feedback_message, saved.feedback_message);
        let review = report.review.unwrap();
        assert_eq!(review.disposition, ReviewDisposition::NeedsChanges);
        assert_eq!(review.summary, "必须修复");
        assert_eq!(review.reviewed_version, "commit:1234");
        assert_eq!(payload, original);
    }

    #[test]
    fn saved_report_does_not_interpret_retired_or_unknown_payloads() {
        for (format, version) in [
            (FINISH_TURN_FORMAT, 1),
            (FINISH_TURN_FORMAT, FINISH_TURN_VERSION + 1),
            ("different.format", FINISH_TURN_VERSION),
        ] {
            // Even recognizable report text is not authority to reinterpret another version.
            let payload = OpaquePayload::new(format, version, r#"{"message":"approved"}"#).unwrap();
            assert!(saved_report(&payload).unwrap().is_none());
        }
        let malformed = OpaquePayload::new(
            FINISH_TURN_FORMAT,
            FINISH_TURN_VERSION,
            r#"{"review":null}"#,
        )
        .unwrap();
        assert!(saved_report(&malformed).is_err());

        let ordinary = OpaquePayload::new(
            FINISH_TURN_FORMAT,
            FINISH_TURN_VERSION,
            r#"{"message":"approved","review":null,"feedbackMessage":null}"#,
        )
        .unwrap();
        let report = saved_report(&ordinary).unwrap().unwrap();
        assert_eq!(report.message, "approved");
        assert!(report.review.is_none());
        assert!(report.feedback_message.is_none());
    }
}
