//! User-input tool schema and model-facing result projection.

use pl_protocol::{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, UserQuestion, UserQuestionOption};
use schemars::JsonSchema;
use serde::Deserialize;

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
    /// `plan_confirmation` is reserved for plan_submit.
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
        if input
            .questions
            .iter()
            .any(|question| question.id == AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID)
        {
            return Err(pl_core::tool::opaque::ToolError::new(crate::tool_error(
                "request_user_input",
                format!(
                    "question ID `{AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID}` is reserved for plan_submit"
                ),
            )));
        }
        let mut ids = std::collections::BTreeSet::new();
        if input.questions.is_empty()
            || input.questions.iter().any(|question| {
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
        let questions = input
            .questions
            .into_iter()
            .map(UserQuestion::from)
            .collect::<Vec<_>>();
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
