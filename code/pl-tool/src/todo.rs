use pl_protocol::{PureError, TodoItem, TodoStatus};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub const TOOL_UPDATE_TODO_LIST: &str = "update_todo_list";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TodoListInput {
    /// Optional short title or explanation for this todo list update.
    #[serde(default)]
    explanation: Option<String>,
    /// The complete todo list snapshot.
    #[schemars(length(min = 1))]
    items: Vec<TodoListInputItem>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TodoListInputItem {
    /// Task step text.
    step: String,
    /// Step status.
    status: TodoListInputStatus,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
enum TodoListInputStatus {
    Pending,
    InProgress,
    Completed,
}

impl From<TodoListInputStatus> for TodoStatus {
    fn from(status: TodoListInputStatus) -> Self {
        match status {
            TodoListInputStatus::Pending => Self::Pending,
            TodoListInputStatus::InProgress => Self::InProgress,
            TodoListInputStatus::Completed => Self::Completed,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct TodoDocument {
    explanation: Option<String>,
    items: Vec<TodoItem>,
}

/// Decodes a frozen checklist without re-running its update tool or changing the saved text.
///
/// # Errors
/// Rejects unsupported producer versions and malformed checklist data.
pub fn saved_snapshot(
    payload: &pl_core::context::OpaquePayload,
    call_id: String,
) -> Result<pl_protocol::TodoListSnapshot, PureError> {
    if payload.format() != "pl.tool.todo" || payload.version() != 1 {
        return Err(invalid_todo_list(
            "unsupported saved todo payload format or version",
        ));
    }
    let document: TodoDocument = serde_json::from_str(payload.content())?;
    Ok(pl_protocol::TodoListSnapshot {
        call_id,
        agent_id: None,
        path: None,
        parent_path: None,
        explanation: document.explanation,
        items: document.items,
    })
}

fn todo_document(args: TodoListInput) -> Result<TodoDocument, PureError> {
    if args.items.len() > 32 {
        return Err(invalid_todo_list("todo list may contain at most 32 items"));
    }
    if args.items.is_empty() {
        return Err(invalid_todo_list("items must not be empty"));
    }
    let mut in_progress_count = 0;
    let mut items = Vec::with_capacity(args.items.len());
    for item in args.items {
        let step = item.step.trim().to_string();
        if step.is_empty() {
            return Err(invalid_todo_list("item step must not be empty"));
        }
        let status = TodoStatus::from(item.status);
        if status == TodoStatus::InProgress {
            in_progress_count += 1;
        }
        items.push(TodoItem { step, status });
    }
    if in_progress_count > 1 {
        return Err(invalid_todo_list("at most one item can be inProgress"));
    }

    if items.iter().any(|item| item.step.chars().count() > 256) {
        return Err(invalid_todo_list("todo item exceeds 256 characters"));
    }
    let document = TodoDocument {
        explanation: args
            .explanation
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty()),
        items,
    };
    if serde_json::to_vec(&document)?.len() > 8 * 1024 {
        return Err(invalid_todo_list("todo context exceeds 8192 bytes"));
    }
    Ok(document)
}

/// Stateless authoring tool; each Thread owns checklist state as an opaque extension.
#[derive(Debug, Default)]
pub struct TodoUpdateTool;

impl pl_agent_tool::typed::TypedTool for TodoUpdateTool {
    const NAME: &'static str = TODO_UPDATE_TOOL_NAME;
    const DESCRIPTION: &'static str = TODO_UPDATE_TOOL_DESCRIPTION;
    type Args = TodoListInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: pl_core::tool::opaque::CallContext,
    ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
        let decode = |source: PureError| pl_core::tool::opaque::ToolError::new(source);
        let document = todo_document(input).map_err(decode)?;
        let encoded =
            serde_json::to_string(&document).map_err(pl_core::tool::opaque::ToolError::new)?;
        let payload = pl_core::context::OpaquePayload::new("pl.tool.todo", 1, encoded.clone())
            .map_err(pl_core::tool::opaque::ToolError::new)?;
        let previous = context.extensions.get("pl.tool.todo");
        if previous.is_some_and(|record| {
            record.payload.format() != "pl.tool.todo" || record.payload.version() != 1
        }) {
            return Err(decode(invalid_todo_list(
                "unsupported saved todo payload format or version",
            )));
        }
        let mutations = if previous.is_some_and(|record| record.payload == payload) {
            Vec::new()
        } else {
            vec![pl_core::thread::extensions::ExtensionMutation::Put {
                id: "pl.tool.todo".into(),
                expected_revision: previous.map(|record| record.revision),
                payload: payload.clone(),
            }]
        };
        Ok(pl_core::tool::ToolOutput::new(
            payload,
            vec![pl_core::context::ContextContent::Text {
                text: std::sync::Arc::from(encoded),
            }],
        )
        .with_extension_mutations(mutations))
    }
}

fn invalid_todo_list(message: &str) -> PureError {
    PureError::ToolExecutionFailed {
        tool: "update_todo_list".to_string(),
        error: message.to_string(),
    }
}

pub fn todo_update_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        TODO_UPDATE_TOOL_NAME,
        TODO_UPDATE_TOOL_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<TodoListInput>(),
    )
    .expect("static tool definition")
}

const TODO_UPDATE_TOOL_NAME: &str = crate::todo::TOOL_UPDATE_TODO_LIST;
const TODO_UPDATE_TOOL_DESCRIPTION: &str =
    "Replace the current task checklist; maintain at most one in-progress item.";
