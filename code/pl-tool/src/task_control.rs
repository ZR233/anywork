//! Model-callable task controls over the Thread's restricted task capability.
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{TaskAccess, ThreadError},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
    },
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::{sync::Arc, time::Duration};

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
    kind: TaskControlKind,
}

impl TaskControlTool {
    /// Selects the task-control operation without creating runtime resources.
    pub fn new(kind: TaskControlKind) -> Self {
        Self { kind }
    }

    /// Registers only the permissions needed by this control.
    ///
    /// # Errors
    /// Returns invalid registration identity.
    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        let kind = self.kind;
        let id = match kind {
            TaskControlKind::Wait => "wait",
            TaskControlKind::Query => "get_tool_task",
            TaskControlKind::Cancel => "cancel_tool_task",
        };
        let registration = Registration::new(id.into(), declaration, self)?;
        Ok(match kind {
            TaskControlKind::Wait => registration
                .with_presentation_contract(pl_core::model::ToolPresentationContract::new(
                    "builtin.wait@1",
                ))
                .with_task_waiting(),
            TaskControlKind::Cancel => registration.with_task_cancellation(),
            TaskControlKind::Query => registration,
        })
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

/// Committed task and inbox readiness, without consuming or duplicating their result bodies.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WaitTasksOutput {
    pub tasks: Vec<TaskRecord>,
    pub messages_ready: bool,
    pub timed_out: bool,
}

/// The exact lightweight result saved as delivered context and used by product projections.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WaitTasksView {
    pub tasks: Vec<TaskStatusView>,
    pub messages_ready: bool,
    pub timed_out: bool,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QueryTaskInput {
    pub task_id: String,
    /// UTF-8 byte offset into the immutable complete payload; omitted reads status only.
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
    #[error("result cursor is outside the payload or splits a UTF-8 character")]
    Cursor,
}

/// Task metadata in the model-visible status view, without the complete task's internal links.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskStatusView {
    pub task_id: String,
    pub tool_id: String,
    pub status: TaskStatus,
    pub cancel_requested: bool,
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

impl Tool for TaskControlTool {
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
                    serde_json::from_str(input.content()).map_err(ToolError::new)?;
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
                    timed_out: result.timed_out,
                };
                let view = WaitTasksView {
                    tasks: payload.tasks.iter().map(TaskStatusView::from).collect(),
                    messages_ready: payload.messages_ready,
                    timed_out: payload.timed_out,
                };
                output("pl.tool.wait", &payload, &view)
            }
            TaskControlKind::Query => {
                let input: QueryTaskInput =
                    serde_json::from_str(input.content()).map_err(ToolError::new)?;
                query(access, input).await
            }
            TaskControlKind::Cancel => {
                let input: CancelTaskInput =
                    serde_json::from_str(input.content()).map_err(ToolError::new)?;
                let receipt = access
                    .cancel(input.task_id.clone())
                    .await
                    .map_err(ToolError::new)?;
                let view = serde_json::json!({"taskId":input.task_id,"cancellation":receipt});
                output("pl.tool.cancel-task", &view, &view)
            }
        }
    }
}

async fn query(access: &TaskAccess, input: QueryTaskInput) -> Result<ToolOutput, ToolError> {
    // The owner's task ledgers and effect window are bounded, so a finished task identity may have
    // left memory entirely. The durable store then answers the identity/status; a missing durable
    // fact stays a real "unknown task" error instead of reviving the task or faking a terminal.
    let (task, durable_delivery) = match access.get(&input.task_id) {
        Ok(task) => (task, None),
        Err(ThreadError::TaskNotFound { .. }) => match access
            .durable(&input.task_id)
            .await
            .map_err(ToolError::new)?
        {
            Some(fact) => (fact.task, Some(fact.delivery)),
            None => {
                return Err(ToolError::new(ThreadError::TaskNotFound {
                    task_id: input.task_id.clone(),
                }));
            }
        },
        Err(error) => return Err(ToolError::new(error)),
    };
    let mut view = serde_json::json!({"task":TaskStatusView::from(&task)});
    let delivery = if input.result_cursor.is_some() {
        match durable_delivery {
            Some(delivery) => delivery,
            None => read_result(access, &input.task_id).await?,
        }
    } else {
        None
    };
    if input.result_cursor.is_some() && task.status != TaskStatus::Running && delivery.is_none() {
        return Err(ToolError::new(ThreadError::InvalidOutput));
    }
    if let Some(start) = input.result_cursor
        && let Some(delivery) = delivery
    {
        let payload = delivery.output.payload();
        let text = payload.content();
        if start > text.len() || !text.is_char_boundary(start) {
            return Err(ToolError::new(ControlError::Cursor));
        }
        let mut end = start.saturating_add(8192).min(text.len());
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        view["result"] = serde_json::json!({"format":payload.format(),"version":payload.version(),"content":&text[start..end],"nextCursor":(end<text.len()).then_some(end),"totalBytes":text.len()});
    }
    output(
        "pl.tool.task",
        &serde_json::json!({"task":task,"result":view.get("result")}),
        &view,
    )
}

/// Reads a terminal result, preferring the owner's resident state and falling back to the durable
/// committed delivery once the owner has released the body.
async fn read_result(
    access: &TaskAccess,
    task_id: &str,
) -> Result<Option<pl_core::thread::ToolDelivery>, ToolError> {
    match access.result(task_id) {
        Ok(delivery) => Ok(delivery),
        // `InvalidOutput` means the commit already left the bounded live window: the durable calls
        // store holds the exact committed delivery, so the read is answered there instead of
        // reporting a missing result or repeating the tool.
        Err(ThreadError::InvalidOutput | ThreadError::TaskNotFound { .. }) => Ok(access
            .durable(task_id)
            .await
            .map_err(ToolError::new)?
            .and_then(|fact| fact.delivery)),
        Err(error) => Err(ToolError::new(error)),
    }
}

fn output(
    format: &str,
    payload: &impl Serialize,
    view: &impl Serialize,
) -> Result<ToolOutput, ToolError> {
    let payload = OpaquePayload::new(
        format,
        1,
        serde_json::to_string(payload).map_err(ToolError::new)?,
    )
    .map_err(ToolError::new)?;
    let text = serde_json::to_string(view).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        payload,
        vec![ContextContent::Text {
            text: Arc::from(text),
        }],
    ))
}

/// Lists this Thread's tasks without consuming messages or task results.
#[derive(Debug, Default)]
pub struct ListTasksTool;

impl ListTasksTool {
    /// Stable declaration for recovering task identities after a model context change.
    pub fn declaration() -> pl_protocol::ToolSpec {
        pl_protocol::ToolSpec::function(
            "list_tool_tasks",
            "List tasks owned by this Thread without consuming results; use get_tool_task for complete-result pages.",
            schemars::schema_for!(ListTasksInput).to_value(),
        )
    }

    /// Registers the read-only task view without waiting or cancellation authority.
    ///
    /// # Errors
    /// Returns an invalid registration identity.
    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        Registration::new("list_tool_tasks".into(), declaration, self)
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
struct ListTasksInput {}

impl Tool for ListTasksTool {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let _: ListTasksInput = serde_json::from_str(input.content()).map_err(ToolError::new)?;
        let access = context
            .tasks
            .as_ref()
            .ok_or_else(|| ToolError::new(ControlError::MissingRuntime))?;
        let tasks = access.list();
        let view = tasks.iter().map(TaskStatusView::from).collect::<Vec<_>>();
        output("pl.tool.list-tasks", &tasks, &view)
    }
}
