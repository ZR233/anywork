//! ACP task receipts describe the ACP execution owner, without Native inbox semantics.

use anyhow::Result;
use pl_agent_tool::{ToolDefinition, typed::output_schema_for};
use pl_core::thread::cold::OutputRepair;
use pl_tool::task_control::TaskStatusView;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct WaitInput {
    /// Exact task IDs returned by this ACP instance. Any selected terminal task wakes the wait.
    /// An empty list waits only for the timeout; it does not observe Native messages.
    #[serde(default)]
    pub task_ids: Vec<String>,
    /// Maximum wait in milliseconds; defaults to sixty seconds.
    #[serde(default)]
    #[schemars(range(min = 1, max = 300000))]
    pub timeout_ms: Option<u64>,
}

#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct WaitOutput {
    pub tasks: Vec<TaskStatusView>,
    pub timed_out: bool,
}

#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct QueryOutput {
    pub task: TaskStatusView,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<ResultPage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub archive_error: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub output_repairs: Vec<RepairView>,
}

#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ResultPage {
    pub format: String,
    pub version: u32,
    pub content: String,
    pub total_bytes: usize,
    pub next_cursor: Option<usize>,
}

#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct RepairView {
    call_id: String,
    reference: ResourceView,
}

#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ResourceView {
    id: String,
    content_digest: String,
    byte_len: u64,
    media_type: String,
}

impl From<&OutputRepair> for RepairView {
    fn from(repair: &OutputRepair) -> Self {
        Self {
            call_id: repair.call_id.clone(),
            reference: ResourceView {
                id: repair.reference.id().into(),
                content_digest: repair.reference.content_digest().into(),
                byte_len: repair.reference.byte_len(),
                media_type: repair.reference.media_type().into(),
            },
        }
    }
}

pub(super) fn definition(native: ToolDefinition, operation: &str) -> Result<ToolDefinition> {
    use pl_tool::task_control::{ListTasksInput, QueryTaskInput};
    let (description, input, output) = match operation {
        "list" => (
            "List tasks owned by this ACP instance without consuming their results.",
            pl_agent_tool::typed::input_schema_for::<ListTasksInput>(),
            output_schema_for::<Vec<TaskStatusView>>(),
        ),
        "wait" => (
            "Wait for any selected ACP task to reach a terminal state, or for the timeout. Use exact task IDs. Empty taskIds waits only for the timeout; this tool does not observe Native messages. Cancellation or timeout stops this observation, not the selected tasks. Read results with anywork_get_tool_task.",
            pl_agent_tool::typed::input_schema_for::<WaitInput>(),
            output_schema_for::<WaitOutput>(),
        ),
        "get" => (
            "Read the status and original result of an ACP task without consuming or repeating it. Omit resultCursor for status only. resultCursor=0 starts UTF-8 pages; append result.content in cursor order until nextCursor is null, then decode the joined HostResult JSON. The author value, when present, is at result.data.value; result.content holds content and is_error records failure. archiveError and outputRepairs report retention failures and subsequent repairs. This cursor does not page raw stdout/stderr files.",
            pl_agent_tool::typed::input_schema_for::<QueryTaskInput>(),
            output_schema_for::<QueryOutput>(),
        ),
        "cancel" => return Ok(native),
        _ => anyhow::bail!("unknown ACP task contract"),
    };
    Ok(ToolDefinition::json(native.name(), description, input)?.with_output_schema(output)?)
}
