//! Model-callable task controls over the Thread's restricted task capability.
use pl_core::{
    context::OpaquePayload,
    thread::{TaskAccess, ThreadError, ToolOutcome},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::time::Duration;

pub use pl_core::thread::task::{TaskRecord, TaskStatus};

/// Task control appearance; scheduling and state transitions remain in core.
#[derive(Debug, Clone, Copy)]
pub enum TaskControlKind {
    Wait,
    Query,
    Cancel,
}

#[derive(Debug)]
pub struct TaskControlTool {
    definition: pl_agent_tool::ToolDefinition,
    kind: TaskControlKind,
}

impl TaskControlTool {
    /// Selects the task-control operation without creating runtime resources.
    pub fn new(kind: TaskControlKind, definition: pl_agent_tool::ToolDefinition) -> Self {
        Self { definition, kind }
    }

    /// Registers only the permissions needed by this control.
    ///
    /// The supplied preparation has already validated the registration identity.
    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        let kind = self.kind;
        let registration = prepared.attach(pl_agent_tool::ToolHandle::new(self));
        match kind {
            TaskControlKind::Wait => registration
                .with_presentation_contract(pl_core::model::ToolPresentationContract::new(
                    "builtin.wait@1",
                ))
                .with_task_waiting(),
            TaskControlKind::Cancel => registration.with_task_cancellation(),
            TaskControlKind::Query => registration,
        }
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WaitTasksInput {
    /// Exact receipt task IDs to observe, including sleep timers. Any selected terminal task or new
    /// Thread message wakes the wait; an empty list observes messages only.
    #[serde(default)]
    pub task_ids: Vec<String>,
    /// Maximum wait in milliseconds; defaults to sixty seconds.
    #[serde(default)]
    #[schemars(range(min = 1, max = 300000))]
    pub timeout_ms: Option<u64>,
}

/// Committed task, inbox, and immediate user-input readiness without consuming bodies.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WaitTasksOutput {
    pub tasks: Vec<TaskRecord>,
    pub messages_ready: bool,
    #[serde(default)]
    pub user_inputs_ready: bool,
    pub timed_out: bool,
}

/// The exact lightweight result saved as delivered context and used by product projections.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WaitTasksView {
    pub tasks: Vec<TaskStatusView>,
    pub messages_ready: bool,
    #[serde(default)]
    pub user_inputs_ready: bool,
    pub timed_out: bool,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QueryTaskInput {
    pub task_id: String,
    /// UTF-8 byte offset into the immutable complete result; omitted reads status only.
    #[serde(default)]
    pub result_cursor: Option<usize>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CancelTaskInput {
    pub task_id: String,
}

#[derive(Debug, thiserror::Error)]
enum ControlError {
    #[error("task controls require a Thread execution context")]
    MissingRuntime,
    #[error("wait timeout must be between 1 and 300000 milliseconds")]
    Timeout,
    #[error("result cursor is outside the result or splits a UTF-8 character")]
    Cursor,
    #[error(
        "Original result for terminal task {task_id:?} is unavailable. The task was not re-executed."
    )]
    ResultUnavailable { task_id: String },
    #[error("Saved result identity does not match task {task_id:?}")]
    ResultIdentity { task_id: String },
}

/// Task metadata in the model-visible status view, without the complete task's internal links.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct TaskStatusView {
    pub task_id: String,
    pub tool_id: String,
    #[schemars(with = "String")]
    pub status: TaskStatus,
    pub cancel_requested: bool,
}

#[derive(Serialize, JsonSchema)]
struct QueryResult {
    task: TaskStatusView,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<ResultPage>,
}

#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ResultPage {
    content: String,
    next_cursor: Option<usize>,
    total_bytes: usize,
}
impl From<&TaskRecord> for TaskStatusView {
    fn from(task: &TaskRecord) -> Self {
        Self {
            task_id: task.id.clone(),
            tool_id: task.tool_id.clone(),
            status: task.status,
            cancel_requested: task.cancel_requested,
        }
    }
}

impl pl_agent_tool::Tool for TaskControlTool {
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
        let access = context
            .tasks
            .as_ref()
            .ok_or_else(|| ToolError::new(ControlError::MissingRuntime))?;
        match self.kind {
            TaskControlKind::Wait => {
                let input: WaitTasksInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let timeout = input.timeout_ms.unwrap_or(60_000);
                if !(1..=300_000).contains(&timeout) {
                    return Err(ToolError::new(ControlError::Timeout));
                }
                let result = access
                    .wait(
                        &input.task_ids,
                        Duration::from_millis(timeout),
                        context.cancellation.clone(),
                    )
                    .await
                    .map_err(ToolError::new)?;
                let payload = WaitTasksOutput {
                    tasks: result.tasks,
                    messages_ready: result.messages_ready,
                    user_inputs_ready: result.user_inputs_ready,
                    timed_out: result.timed_out,
                };
                let view = WaitTasksView {
                    tasks: payload.tasks.iter().map(TaskStatusView::from).collect(),
                    messages_ready: payload.messages_ready,
                    user_inputs_ready: payload.user_inputs_ready,
                    timed_out: payload.timed_out,
                };
                let details = serde_json::to_value(payload).map_err(ToolError::new)?;
                Ok(output(&view)?.with_details(details))
            }
            TaskControlKind::Query => {
                let input: QueryTaskInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                query(access, input).await
            }
            TaskControlKind::Cancel => {
                let input: CancelTaskInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let receipt = access
                    .cancel(input.task_id.clone())
                    .await
                    .map_err(ToolError::new)?;
                let view = serde_json::json!({"taskId":input.task_id,"cancellation":receipt});
                Ok(ToolOutput::json(view))
            }
        }
    }
}

async fn query(access: &TaskAccess, input: QueryTaskInput) -> Result<ToolOutput, ToolError> {
    let resident = match access.get(&input.task_id) {
        Ok(task) => Some(task),
        Err(ThreadError::TaskNotFound { .. }) => None,
        Err(error) => return Err(ToolError::new(error)),
    };
    let (task, delivery) = match resident {
        Some(task) if input.result_cursor.is_none() || task.status == TaskStatus::Running => {
            (task, None)
        }
        resident => {
            // Current may have relocated the call while History retains the original call ID.
            // Page the terminal task and delivery from the same committed fact.
            match access
                .durable(&input.task_id)
                .await
                .map_err(ToolError::new)?
            {
                Some(fact) => (fact.task, fact.delivery),
                None => (
                    resident.ok_or_else(|| {
                        ToolError::new(ThreadError::TaskNotFound {
                            task_id: input.task_id.clone(),
                        })
                    })?,
                    None,
                ),
            }
        }
    };
    if task.id != input.task_id {
        return Err(ToolError::new(ThreadError::TaskNotFound {
            task_id: input.task_id,
        }));
    }
    if input.result_cursor.is_some() && task.status != TaskStatus::Running && delivery.is_none() {
        return Err(ToolError::new(ControlError::ResultUnavailable {
            task_id: input.task_id,
        }));
    }
    let result = if let Some(start) = input.result_cursor
        && let Some(delivery) = delivery
    {
        if delivery.call_id != task.call_id
            || delivery.tool_id != task.tool_id
            || !matches!(
                (task.status, &delivery.outcome),
                (TaskStatus::Succeeded, ToolOutcome::Succeeded)
                    | (TaskStatus::Failed, ToolOutcome::Failed(_))
                    | (TaskStatus::Cancelled, ToolOutcome::Cancelled)
                    | (TaskStatus::Interrupted, ToolOutcome::Interrupted)
            )
        {
            return Err(ToolError::new(ControlError::ResultIdentity {
                task_id: input.task_id,
            }));
        }
        let text = serde_json::to_string(delivery.output.result()).map_err(ToolError::new)?;
        if start > text.len() || !text.is_char_boundary(start) {
            return Err(ToolError::new(ControlError::Cursor));
        }
        let mut end = start.saturating_add(8192).min(text.len());
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        Some(ResultPage {
            content: text[start..end].to_owned(),
            next_cursor: (end < text.len()).then_some(end),
            total_bytes: text.len(),
        })
    } else {
        None
    };
    output(&QueryResult {
        task: TaskStatusView::from(&task),
        result,
    })
}

fn output(view: &impl Serialize) -> Result<ToolOutput, ToolError> {
    serde_json::to_value(view)
        .map(ToolOutput::json)
        .map_err(ToolError::new)
}

/// Lists this Thread's tasks without consuming messages or task results.
#[derive(Debug, Default)]
pub struct ListTasksTool;

impl ListTasksTool {
    /// Stable declaration for recovering task identities after a model context change.
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        list_tasks_tool_definition()
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ListTasksInput {}

impl pl_agent_tool::typed::TypedTool for ListTasksTool {
    const NAME: &'static str = LIST_TASKS_TOOL_NAME;
    const DESCRIPTION: &'static str = LIST_TASKS_TOOL_DESCRIPTION;
    type Args = ListTasksInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(&self, _: Self::Args, context: CallContext) -> Result<ToolOutput, ToolError> {
        let access = context
            .tasks
            .as_ref()
            .ok_or_else(|| ToolError::new(ControlError::MissingRuntime))?;
        let tasks = access.list();
        let view = tasks.iter().map(TaskStatusView::from).collect::<Vec<_>>();
        output(&view)
    }
}

pub fn list_tasks_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        LIST_TASKS_TOOL_NAME,
        LIST_TASKS_TOOL_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<ListTasksInput>(),
    )
    .expect("static tool definition")
    .with_output_schema(crate::binding::program_schema::<Vec<TaskStatusView>>())
    .expect("static task list schema")
}

const LIST_TASKS_TOOL_NAME: &str = "list_tool_tasks";
const LIST_TASKS_TOOL_DESCRIPTION: &str = "List this Thread active and resident tasks without consuming results. Completed tasks may leave this list; keep returned taskId values and use get_tool_task to read their saved results.";

pub fn wait_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("wait",
                "Call wait ALONE in a model response. Observe exact receipt taskIds (including sleep timers): {\"taskIds\":[\"task:call-id\"]}. Any selected terminal task OR new Thread message returns first, not all tasks; already-ready events return immediately. Empty taskIds wait only for messages, including child reports: {\"taskIds\":[],\"timeoutMs\":300000}. Returns readiness without consuming results; full background results and child Turn reports arrive in your next model context. Match childId, turn and input identity before accepting child work. Never put agentId or bare callId in taskIds. Timeout or cancelling wait does not cancel the selected tasks.", pl_agent_tool::typed::input_schema_for::<crate::task_control::WaitTasksInput>()).expect("static tool definition")
        .with_output_schema(crate::binding::program_schema::<WaitTasksView>()).expect("static wait schema")
}

pub fn query_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("get_tool_task",
                "Read this Thread receipt taskId without consuming events. resultCursor=0 starts UTF-8 byte pages of the original tool result. Check task identity and status, append result.content in cursor order until nextCursor is null, then decode the joined JSON. The program value, when present, is in data.value. This cursor does not page raw stdout/stderr files. Finished results remain queryable after resident eviction; never rerun commands to recover output.", pl_agent_tool::typed::input_schema_for::<crate::task_control::QueryTaskInput>()).expect("static tool definition")
        .with_output_schema(crate::binding::program_schema::<QueryResult>()).expect("static task query schema")
}

pub fn cancel_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json("cancel_tool_task",
                "Request cancellation of one task. The acknowledgement is not proof of process exit; use wait to observe its terminal result.", pl_agent_tool::typed::input_schema_for::<crate::task_control::CancelTaskInput>()).expect("static tool definition")
        .with_output_schema(serde_json::json!({"type":"object","properties":{
            "taskId":{"type":"string"},"cancellation":{"enum":["requested","alreadyRequested","alreadyFinished"]}
        },"required":["taskId","cancellation"],"additionalProperties":false}))
        .expect("static cancellation schema")
}
