//! User-input tool schema and model-facing result projection.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub const AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID: &str = "plan_confirmation";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct UserQuestionOption {
    pub label: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct UserQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    #[serde(default)]
    pub is_other: bool,
    #[serde(default)]
    pub is_secret: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<UserQuestionOption>>,
}

#[derive(Debug, Default)]
pub struct AskUserTool;

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AskUserInput {
    /// Structured questions shown to the user.
    #[schemars(length(min = 1))]
    questions: Vec<UserQuestionInput>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UserQuestionInput {
    /// Stable snake_case id used as the answer map key.
    /// `plan_confirmation` is reserved for plan_transition.
    id: String,
    /// Short label for the question.
    header: String,
    /// Question shown to the user.
    question: String,
    /// Whether a free-form custom answer should be accepted.
    #[serde(default)]
    is_other: bool,
    /// Whether the answer is sensitive and should be hidden in UI logs.
    #[serde(default)]
    is_secret: bool,
    /// Optional predefined choices.
    options: Option<Vec<UserQuestionOptionInput>>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UserQuestionOptionInput {
    /// Choice label shown to the user.
    label: String,
    /// Short explanation of the choice.
    description: String,
}

impl From<UserQuestionInput> for UserQuestion {
    fn from(question: UserQuestionInput) -> Self {
        Self {
            id: question.id,
            header: question.header,
            question: question.question,
            is_other: question.is_other,
            is_secret: question.is_secret,
            options: question.options.map(|options| {
                options
                    .into_iter()
                    .map(|option| UserQuestionOption {
                        label: option.label,
                        description: option.description,
                    })
                    .collect()
            }),
        }
    }
}

impl AskUserInput {
    pub fn into_questions(self) -> Result<Vec<UserQuestion>, pl_core::tool::opaque::ToolError> {
        if self
            .questions
            .iter()
            .any(|question| question.id == AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID)
        {
            return Err(pl_core::tool::opaque::ToolError::new(crate::tool_error(
                "request_user_input",
                format!(
                    "question ID `{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID}` is reserved for plan_transition"
                ),
            )));
        }
        let mut ids = std::collections::BTreeSet::new();
        if self.questions.is_empty()
            || self.questions.iter().any(|question| {
                question.id.trim().is_empty()
                    || question.question.trim().is_empty()
                    || !ids.insert(&question.id)
            })
        {
            return Err(pl_core::tool::opaque::ToolError::new(crate::tool_error(
                "request_user_input",
                "questions require unique nonempty IDs and question text",
            )));
        }
        Ok(self.questions.into_iter().map(UserQuestion::from).collect())
    }
}

impl pl_agent_tool::typed::TypedTool for AskUserTool {
    const NAME: &'static str = ASK_USER_TOOL_NAME;
    const DESCRIPTION: &'static str = ASK_USER_TOOL_DESCRIPTION;
    type Args = AskUserInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        _: pl_core::tool::opaque::CallContext,
    ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
        let questions = input.into_questions()?;
        let encoded =
            serde_json::to_string(&questions).map_err(pl_core::tool::opaque::ToolError::new)?;
        let payload = pl_core::context::OpaquePayload::new("pl.tool.user-input", 1, encoded)
            .map_err(pl_core::tool::opaque::ToolError::new)?;
        Ok(pl_core::tool::ToolOutput::new(
            payload.clone(),
            vec![pl_core::context::ContextContent::Text {
                text: std::sync::Arc::from("Waiting for the user's response."),
            }],
        )
        .with_interaction(payload))
    }
}

pub fn ask_user_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        ASK_USER_TOOL_NAME,
        ASK_USER_TOOL_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<AskUserInput>(),
    )
    .expect("static tool definition")
}

const ASK_USER_TOOL_NAME: &str = "request_user_input";
const ASK_USER_TOOL_DESCRIPTION: &str =
    "Ask structured questions and suspend until the user answers or cancels.";
