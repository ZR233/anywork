//! Typed wait/sleep presentation derived from canonical parameters, tasks and results.
//!
//! This is a product decode boundary: core never interprets `wait`/`sleep`. Incomplete or illegal
//! parameters leave the field absent so the original tool card remains. A succeeded wait whose
//! delivered view cannot be decoded also stays untyped. Target names and statuses come from the
//! resident snapshot or the official wait view; history never scans other items to fill them.
use super::activity::{bounded_summary, call_arguments, command_line};
use crate::{
    ThreadToolState, ThreadWaitIntent, ThreadWaitPresentation, ThreadWaitState, ThreadWaitTarget,
    ThreadWaitTargetStatus,
};
use pl_core::thread::{
    ThreadSnapshot,
    task::{TaskRecord, TaskStatus},
};
use pl_tool::session::SleepInput;
use pl_tool::task_control::{WaitTasksInput, WaitTasksView};

/// Projects one wait/sleep call from its canonical arguments, resident tasks and terminal result.
///
/// Returns `None` when the call is not wait/sleep, when the parameters are not a complete legal
/// wait/sleep payload, or when a succeeded wait has no decodable `WaitTasksView`.
pub(in crate::studio) fn project_wait(
    snapshot: Option<&ThreadSnapshot>,
    name: &str,
    arguments: &str,
    state: &ThreadToolState,
) -> Option<ThreadWaitPresentation> {
    match name {
        "wait" => project_event_wait(snapshot, arguments, state),
        "sleep" => project_timer(arguments, state),
        _ => None,
    }
}

fn project_event_wait(
    snapshot: Option<&ThreadSnapshot>,
    arguments: &str,
    state: &ThreadToolState,
) -> Option<ThreadWaitPresentation> {
    let input: WaitTasksInput = serde_json::from_str(arguments).ok()?;
    let timeout_ms = input.timeout_ms.unwrap_or(60_000);
    if !(1..=300_000).contains(&timeout_ms) {
        return None;
    }
    if input.task_ids.iter().any(|task_id| task_id.is_empty()) {
        return None;
    }
    let view = match state {
        ThreadToolState::Succeeded(succeeded) => {
            Some(decode_wait_view(succeeded.output().result())?)
        }
        ThreadToolState::Failed(failed) => failed
            .output()
            .and_then(|output| decode_wait_view(output.result())),
        _ => None,
    };
    let mut targets = Vec::with_capacity(input.task_ids.len());
    for task_id in &input.task_ids {
        let recovered = view
            .as_ref()
            .and_then(|view| view.tasks.iter().find(|task| task.task_id == *task_id));
        let record = snapshot.and_then(|snapshot| find_task(snapshot, task_id));
        let tool_name = recovered
            .map(|task| task.tool_id.clone())
            .or_else(|| record.map(|task| task.tool_id.clone()));
        let summary = record.and_then(|task| command_summary(snapshot, task));
        let status = recovered
            .map(|task| task.status)
            .or_else(|| record.map(|task| task.status))
            .map(target_status);
        targets.push(ThreadWaitTarget::new(
            task_id.clone(),
            tool_name,
            summary,
            status,
        ));
    }
    let success = match state {
        ThreadToolState::Succeeded(_) if view.as_ref()?.timed_out => ThreadWaitState::TimedOut,
        _ => ThreadWaitState::Ready,
    };
    let wait_state = wait_state(state, success);
    Some(ThreadWaitPresentation::new(
        ThreadWaitIntent::Events {
            targets,
            timeout_ms,
        },
        wait_state,
        match wait_state {
            ThreadWaitState::Ready => Some(view.as_ref()?.messages_ready),
            _ => None,
        },
    ))
}

fn project_timer(arguments: &str, state: &ThreadToolState) -> Option<ThreadWaitPresentation> {
    let input: SleepInput = serde_json::from_str(arguments).ok()?;
    if !(1..=86_400_000).contains(&input.duration_ms) {
        return None;
    }
    Some(ThreadWaitPresentation::new(
        ThreadWaitIntent::Timer {
            duration_ms: input.duration_ms,
        },
        wait_state(state, ThreadWaitState::Elapsed),
        None,
    ))
}

fn decode_wait_view(result: &str) -> Option<WaitTasksView> {
    serde_json::from_str(result).ok()
}

fn wait_state(state: &ThreadToolState, success: ThreadWaitState) -> ThreadWaitState {
    match state {
        ThreadToolState::Queued(_)
        | ThreadToolState::Started(_)
        | ThreadToolState::Streaming(_)
        | ThreadToolState::AwaitingApproval(_)
        | ThreadToolState::Approved(_)
        | ThreadToolState::Running(_)
        | ThreadToolState::Cancelling(_) => ThreadWaitState::Waiting,
        ThreadToolState::Succeeded(_) => success,
        ThreadToolState::Failed(_) => ThreadWaitState::Failed,
        ThreadToolState::Denied(_) | ThreadToolState::Cancelled(_) => ThreadWaitState::Cancelled,
        ThreadToolState::Interrupted(_) => ThreadWaitState::Interrupted,
    }
}

fn find_task<'a>(snapshot: &'a ThreadSnapshot, task_id: &str) -> Option<&'a TaskRecord> {
    snapshot.tasks.get(task_id).or_else(|| {
        snapshot
            .terminal_tasks
            .iter()
            .find(|task| task.id == task_id)
    })
}

fn command_summary(snapshot: Option<&ThreadSnapshot>, task: &TaskRecord) -> Option<(String, bool)> {
    let arguments = call_arguments(snapshot?, &task.call_id)?;
    command_line(arguments, bounded_summary)
}

fn target_status(status: TaskStatus) -> ThreadWaitTargetStatus {
    match status {
        TaskStatus::Running => ThreadWaitTargetStatus::Running,
        TaskStatus::Succeeded => ThreadWaitTargetStatus::Succeeded,
        TaskStatus::Failed => ThreadWaitTargetStatus::Failed,
        TaskStatus::Cancelled => ThreadWaitTargetStatus::Cancelled,
        TaskStatus::Interrupted => ThreadWaitTargetStatus::Interrupted,
    }
}
