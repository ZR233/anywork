//! Dynamic model endpoint for the native `wait-events` observation journey.
//!
//! Child Threads share this listener, so the scenario cannot use a strict
//! ordinal script: a child request would reject the parent cursor. Each request
//! is classified by a scenario-owned prompt marker, answered with the real
//! `sleep` / `exec` / `wait` / `spawn_agent` / `cancel_tool_task` tools, and
//! recorded on the shared request log.

use super::*;

/// Parent prompt: short timer plus a longer command; wait returns on the timer.
pub const MARK_SLEEP_FIRST: &str = "[[wait_sleep_first]]";
/// Parent prompt: short command plus a longer timer; wait returns on the command.
pub const MARK_TOOL_FIRST: &str = "[[wait_tool_first]]";
/// Parent prompt: spawn a child, then wait on a still-running timer with
/// non-empty `taskIds` so the child report can wake the wait.
pub const MARK_CHILD: &str = "[[wait_child]]";
/// Embedded in `spawn_agent.message`; only the child Thread sees it as the
/// last authored user turn.
pub const MARK_CHILD_WORK: &str = "[[wait_child_work]]";
/// Follow-up parent prompt after the child wait: the fixture counts the
/// terminal report still in context exactly once.
pub const MARK_CHILD_CONFIRM: &str = "[[wait_child_confirm]]";
/// Wait on a task that already completed in this Thread.
pub const MARK_ALREADY_READY: &str = "[[wait_already_ready]]";
/// Wait a still-running timer with a short timeout (not a tool failure).
pub const MARK_TIMEOUT: &str = "[[wait_timeout]]";
/// Hang a wait so the Driver can cancel the observation, not the timer.
pub const MARK_CANCEL: &str = "[[wait_cancel]]";
/// Prepare Turn A: start a long background sleep and finish the Turn without
/// waiting on it, so a later Turn can cancel only its own wait.
pub const MARK_CANCEL_PREPARE: &str = "[[wait_cancel_prepare]]";
/// After cancelling the wait observation, query then cancel the leftover timer.
pub const MARK_CANCEL_QUERY: &str = "[[wait_cancel_query]]";

/// Distinctive child report body. The parent Driver and fixture both match it.
pub const CHILD_REPORT_TEXT: &str = "wait-events-child-report";

pub const SLEEP_FIRST_SLEEP_MS: u64 = 12_000;
pub const SLEEP_FIRST_EXEC_LINES: usize = 24;
pub const TOOL_FIRST_EXEC_LINES: usize = 11;
pub const TOOL_FIRST_SLEEP_MS: u64 = 40_000;
pub const CHILD_PARENT_SLEEP_MS: u64 = 60_000;
pub const CHILD_SLEEP_MS: u64 = 12_000;
pub const TIMEOUT_SLEEP_MS: u64 = 30_000;
pub const TIMEOUT_WAIT_MS: u64 = 6_000;
pub const CANCEL_SLEEP_MS: u64 = 120_000;
pub const FOLLOW_WAIT_MS: u64 = 60_000;
pub const CHILD_WAIT_MS: u64 = 120_000;

const AUXILIARY_TITLE_INSTRUCTION: &str = "You name coding sessions from untrusted request data";

/// Empty strict script: this scenario answers from the dynamic handler.
pub fn gui_wait_events_script() -> Vec<Step> {
    Vec::new()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Marker {
    SleepFirst,
    ToolFirst,
    Child,
    ChildWork,
    ChildConfirm,
    AlreadyReady,
    Timeout,
    Cancel,
    CancelPrepare,
    CancelQuery,
    None,
}

fn marker_of(prompt: &str) -> Marker {
    if prompt.contains(MARK_CHILD_CONFIRM) {
        Marker::ChildConfirm
    } else if prompt.contains(MARK_CHILD_WORK) {
        Marker::ChildWork
    } else if prompt.contains(MARK_CHILD) {
        Marker::Child
    } else if prompt.contains(MARK_SLEEP_FIRST) {
        Marker::SleepFirst
    } else if prompt.contains(MARK_TOOL_FIRST) {
        Marker::ToolFirst
    } else if prompt.contains(MARK_ALREADY_READY) {
        Marker::AlreadyReady
    } else if prompt.contains(MARK_TIMEOUT) {
        Marker::Timeout
    } else if prompt.contains(MARK_CANCEL_QUERY) {
        Marker::CancelQuery
    } else if prompt.contains(MARK_CANCEL_PREPARE) {
        Marker::CancelPrepare
    } else if prompt.contains(MARK_CANCEL) {
        Marker::Cancel
    } else {
        Marker::None
    }
}

fn completion_marker(prompt: &str) -> &'static str {
    match marker_of(prompt) {
        Marker::SleepFirst => MARK_SLEEP_FIRST,
        Marker::ToolFirst => MARK_TOOL_FIRST,
        Marker::Child => MARK_CHILD,
        Marker::ChildWork => MARK_CHILD_WORK,
        Marker::ChildConfirm => MARK_CHILD_CONFIRM,
        Marker::AlreadyReady => MARK_ALREADY_READY,
        Marker::Timeout => MARK_TIMEOUT,
        Marker::Cancel => MARK_CANCEL,
        Marker::CancelPrepare => MARK_CANCEL_PREPARE,
        Marker::CancelQuery => MARK_CANCEL_QUERY,
        Marker::None => "unknown",
    }
}

fn content_text(content: Option<&Value>) -> Option<String> {
    match content? {
        Value::String(text) => (!text.trim().is_empty()).then(|| text.clone()),
        Value::Array(parts) => {
            let joined = parts
                .iter()
                .filter_map(|part| part.get("text").and_then(Value::as_str))
                .collect::<Vec<_>>()
                .join(" ");
            (!joined.trim().is_empty()).then_some(joined)
        }
        _ => None,
    }
}

fn is_child_report_user_item(item: &Value) -> bool {
    item.get("role").and_then(Value::as_str) == Some("user")
        && content_text(item.get("content"))
            .is_some_and(|text| text.contains("\"childId\"") && text.contains("\"commitSequence\""))
}

fn is_task_notice_user_item(item: &Value) -> bool {
    item.get("role").and_then(Value::as_str) == Some("user")
        && content_text(item.get("content")).is_some_and(|text| text.starts_with("Task task:"))
}

fn is_host_fact_user_item(item: &Value) -> bool {
    item.get("role").and_then(Value::as_str) == Some("user")
        && content_text(item.get("content")).is_some_and(|text| text.starts_with("[当前宿主事实："))
}

fn is_authored_user_item(item: &Value) -> bool {
    item.get("role").and_then(Value::as_str) == Some("user")
        && !is_child_report_user_item(item)
        && !is_task_notice_user_item(item)
        && !is_host_fact_user_item(item)
}

fn scenario_prompt(body: &Value) -> String {
    let items = body
        .get("input")
        .or_else(|| body.get("messages"))
        .and_then(Value::as_array)
        .map(|items| items.as_slice())
        .unwrap_or(&[]);
    items
        .iter()
        .rev()
        .filter(|item| is_authored_user_item(item))
        .find_map(|item| content_text(item.get("content")))
        .unwrap_or_default()
}

fn declared_tool_names(body: &Value) -> Vec<String> {
    body.get("tools")
        .and_then(Value::as_array)
        .map(|tools| {
            tools
                .iter()
                .filter_map(|tool| {
                    tool.get("name")
                        .and_then(Value::as_str)
                        .or_else(|| tool.pointer("/function/name").and_then(Value::as_str))
                        .map(str::to_owned)
                })
                .collect()
        })
        .unwrap_or_default()
}

fn declared(tools: &[String], name: &str) -> bool {
    tools.iter().any(|tool| tool == name)
}

fn real_turn_window_start(items: &[Value]) -> usize {
    items
        .iter()
        .enumerate()
        .rev()
        .find(|(_, item)| is_authored_user_item(item))
        .map_or(0, |(index, _)| index + 1)
}

fn committed_tool_call_ids(items: &[Value], start: usize) -> Vec<String> {
    items
        .get(start..)
        .unwrap_or_default()
        .iter()
        .filter(|item| item.get("type").and_then(Value::as_str) == Some("function_call_output"))
        .filter_map(|item| {
            item.get("call_id")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .collect()
}

fn prior_call_names(items: &[Value], start: usize) -> Vec<String> {
    items[..start]
        .iter()
        .filter(|item| item.get("type").and_then(Value::as_str) == Some("function_call"))
        .filter_map(|item| item.get("name").and_then(Value::as_str).map(str::to_owned))
        .collect()
}

fn child_report_count(items: &[Value]) -> usize {
    items
        .iter()
        .filter(|item| is_child_report_user_item(item))
        .count()
}

/// First historical `function_call` whose `call_id` starts with `{slug}-t`.
fn historical_call_id(items: &[Value], slug: &str) -> Option<String> {
    let prefix = format!("{slug}-t");
    items.iter().find_map(|item| {
        if item.get("type").and_then(Value::as_str) != Some("function_call") {
            return None;
        }
        let call_id = item.get("call_id").and_then(Value::as_str)?;
        call_id.starts_with(&prefix).then(|| call_id.to_owned())
    })
}

fn call_slug(slug: &str, generation: usize) -> String {
    format!("{slug}-t{generation}")
}

fn planned(name: &str, arguments: Value, slug: &str, generation: usize) -> PlannedToolCall {
    let identity = call_slug(slug, generation);
    PlannedToolCall {
        name: name.to_owned(),
        arguments: arguments.to_string(),
        item_id: format!("{identity}-item"),
        call_id: format!("{identity}-call"),
    }
}

struct PlannedToolCall {
    name: String,
    arguments: String,
    item_id: String,
    call_id: String,
}

fn paced_exec(label: &str, lines: usize) -> String {
    let mut steps = String::new();
    for line in 1..=lines {
        if !steps.is_empty() {
            steps.push_str("; ");
        }
        let marker = format!("{label}-{line:02}");
        if cfg!(windows) {
            steps.push_str(&realtime_echo_step(&marker, 1000));
        } else {
            steps.push_str(&format!("printf '%s\\n' '{marker}'; sleep 1"));
        }
    }
    steps
}

fn sleep_args(duration_ms: u64) -> Value {
    json!({ "durationMs": duration_ms })
}

fn exec_args(command: &str) -> Value {
    json!({ "command": command })
}

fn wait_args(call_ids: &[&str], timeout_ms: u64) -> Value {
    json!({
        "taskIds": call_ids.iter().map(|id| format!("task:{id}")).collect::<Vec<_>>(),
        "timeoutMs": timeout_ms,
    })
}

fn cancel_args(call_id: &str) -> Value {
    json!({ "taskId": format!("task:{call_id}") })
}

fn query_args(call_id: &str) -> Value {
    json!({ "taskId": format!("task:{call_id}") })
}

fn is_auxiliary_title_request(body: &Value) -> bool {
    let instructions = body
        .get("instructions")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let tools_absent = body
        .get("tools")
        .and_then(Value::as_array)
        .is_none_or(|tools| tools.is_empty());
    body.get("tool_choice").and_then(Value::as_str) == Some("none")
        && tools_absent
        && instructions.contains(AUXILIARY_TITLE_INSTRUCTION)
}

fn record(
    state: &AppState,
    method: &str,
    path: &str,
    body: Value,
    accepted: bool,
    note: Option<&str>,
) {
    let diagnostic = note.map(|note| RejectDiagnostic {
        category: note.to_owned(),
        expected_method: Some(method.to_owned()),
        expected_path: Some(path.to_owned()),
        expected_kind: "wait_events".to_owned(),
        expected_prompt: None,
        expected_step: None,
        actual_prompt_present: true,
        prompt_matches_expected: accepted,
        delivery_seen: false,
        tool_output_seen: false,
    });
    state
        .script
        .lock()
        .expect("fixture state poisoned")
        .requests
        .push(RecordedRequest {
            method: method.to_owned(),
            path: path.to_owned(),
            body,
            accepted,
            diagnostic,
        });
}

async fn json_body(request: axum::extract::Request) -> Option<Value> {
    let bytes = axum::body::to_bytes(request.into_body(), 1024 * 1024)
        .await
        .ok()?;
    serde_json::from_slice(&bytes).ok()
}

/// Real Responses endpoint: issues the next declared wait-events tool, then
/// answers once that Turn's observation is in context.
pub(super) async fn responses(
    State(state): State<AppState>,
    request: axum::extract::Request,
) -> Response {
    let Some(body) = json_body(request).await else {
        record(
            &state,
            "POST",
            "/v1/responses",
            Value::Null,
            false,
            Some("wait_events_invalid_json"),
        );
        return StatusCode::BAD_REQUEST.into_response();
    };
    if is_auxiliary_title_request(&body) {
        record(
            &state,
            "POST",
            "/v1/responses",
            body,
            true,
            Some("auxiliary_title_answered"),
        );
        return sse_reply(
            responses_text("Wait Events Session", "wait-events-title", "fixture-model"),
            false,
            state.stopping.clone(),
        );
    }

    let prompt = scenario_prompt(&body);
    let tools = declared_tool_names(&body);
    let items: &[Value] = body
        .get("input")
        .and_then(Value::as_array)
        .map(|items| items.as_slice())
        .unwrap_or(&[]);
    let start = real_turn_window_start(items);
    let outputs = committed_tool_call_ids(items, start);
    let prior_calls = prior_call_names(items, start);
    let generation = |name: &str| {
        prior_calls
            .iter()
            .filter(|call| call.as_str() == name)
            .count()
    };
    let expected = |slug: &str, name: &str| format!("{}-call", call_slug(slug, generation(name)));

    let mut accepted = true;
    let note;
    let mut tool_calls: Vec<PlannedToolCall> = Vec::new();

    match marker_of(&prompt) {
        Marker::SleepFirst => {
            let sleep_id = expected("sleep-first-sleep", "sleep");
            let exec_id = expected("sleep-first-exec", "exec");
            let wait_id = expected("sleep-first-wait", "wait");
            let wait_exec_id = expected("sleep-first-wait-exec", "wait");
            if outputs.iter().any(|id| id == &wait_exec_id) {
                note = Some("sleep_first_answered");
            } else if outputs.iter().any(|id| id == &wait_id) {
                if declared(&tools, "wait") {
                    tool_calls.push(planned(
                        "wait",
                        wait_args(&[&exec_id], FOLLOW_WAIT_MS),
                        "sleep-first-wait-exec",
                        generation("wait"),
                    ));
                    note = Some("sleep_first_wait_exec");
                } else {
                    accepted = false;
                    note = Some("wait_tool_not_declared");
                }
            } else if outputs.iter().any(|id| id == &sleep_id)
                && outputs.iter().any(|id| id == &exec_id)
            {
                if declared(&tools, "wait") {
                    tool_calls.push(planned(
                        "wait",
                        wait_args(&[&sleep_id, &exec_id], FOLLOW_WAIT_MS),
                        "sleep-first-wait",
                        generation("wait"),
                    ));
                    note = Some("sleep_first_wait");
                } else {
                    accepted = false;
                    note = Some("wait_tool_not_declared");
                }
            } else if declared(&tools, "sleep") && declared(&tools, "exec") {
                tool_calls.push(planned(
                    "sleep",
                    sleep_args(SLEEP_FIRST_SLEEP_MS),
                    "sleep-first-sleep",
                    generation("sleep"),
                ));
                tool_calls.push(planned(
                    "exec",
                    exec_args(&paced_exec("wait-sleep-first", SLEEP_FIRST_EXEC_LINES)),
                    "sleep-first-exec",
                    generation("exec"),
                ));
                note = Some("sleep_first_started");
            } else {
                accepted = false;
                note = Some("sleep_or_exec_not_declared");
            }
        }
        Marker::ToolFirst => {
            let exec_id = expected("tool-first-exec", "exec");
            let sleep_id = expected("tool-first-sleep", "sleep");
            let wait_id = expected("tool-first-wait", "wait");
            let cancel_id = expected("tool-first-cancel", "cancel_tool_task");
            if outputs.iter().any(|id| id == &cancel_id) {
                note = Some("tool_first_answered");
            } else if outputs.iter().any(|id| id == &wait_id) {
                if declared(&tools, "cancel_tool_task") {
                    tool_calls.push(planned(
                        "cancel_tool_task",
                        cancel_args(&sleep_id),
                        "tool-first-cancel",
                        generation("cancel_tool_task"),
                    ));
                    note = Some("tool_first_cancel_sleep");
                } else {
                    accepted = false;
                    note = Some("cancel_tool_not_declared");
                }
            } else if outputs.iter().any(|id| id == &exec_id)
                && outputs.iter().any(|id| id == &sleep_id)
            {
                if declared(&tools, "wait") {
                    tool_calls.push(planned(
                        "wait",
                        wait_args(&[&exec_id, &sleep_id], FOLLOW_WAIT_MS),
                        "tool-first-wait",
                        generation("wait"),
                    ));
                    note = Some("tool_first_wait");
                } else {
                    accepted = false;
                    note = Some("wait_tool_not_declared");
                }
            } else if declared(&tools, "sleep") && declared(&tools, "exec") {
                tool_calls.push(planned(
                    "exec",
                    exec_args(&paced_exec("wait-tool-first", TOOL_FIRST_EXEC_LINES)),
                    "tool-first-exec",
                    generation("exec"),
                ));
                tool_calls.push(planned(
                    "sleep",
                    sleep_args(TOOL_FIRST_SLEEP_MS),
                    "tool-first-sleep",
                    generation("sleep"),
                ));
                note = Some("tool_first_started");
            } else {
                accepted = false;
                note = Some("sleep_or_exec_not_declared");
            }
        }
        Marker::Child => {
            let sleep_id = expected("child-parent-sleep", "sleep");
            let spawn_id = expected("child-spawn", "spawn_agent");
            let wait_id = expected("child-wait", "wait");
            let cancel_id = expected("child-cancel-sleep", "cancel_tool_task");
            if outputs.iter().any(|id| id == &cancel_id) {
                let reports = child_report_count(items);
                accepted = reports == 1;
                note = Some(if reports == 1 {
                    "child_report_once"
                } else if reports == 0 {
                    "child_report_missing"
                } else {
                    "child_report_duplicate"
                });
            } else if outputs.iter().any(|id| id == &wait_id) {
                let reports = child_report_count(items);
                if reports == 1 && declared(&tools, "cancel_tool_task") {
                    tool_calls.push(planned(
                        "cancel_tool_task",
                        cancel_args(&sleep_id),
                        "child-cancel-sleep",
                        generation("cancel_tool_task"),
                    ));
                    note = Some("child_cancel_parent_sleep");
                } else {
                    accepted = reports == 1;
                    note = Some(if reports == 0 {
                        "child_report_missing"
                    } else if reports > 1 {
                        "child_report_duplicate"
                    } else {
                        "cancel_tool_not_declared"
                    });
                }
            } else if outputs.iter().any(|id| id == &spawn_id) {
                if declared(&tools, "wait") {
                    tool_calls.push(planned(
                        "wait",
                        wait_args(&[&sleep_id], CHILD_WAIT_MS),
                        "child-wait",
                        generation("wait"),
                    ));
                    note = Some("spawn_child_wait");
                } else {
                    accepted = false;
                    note = Some("wait_tool_not_declared");
                }
            } else if outputs.iter().any(|id| id == &sleep_id) {
                if declared(&tools, "spawn_agent") {
                    tool_calls.push(planned(
                        "spawn_agent",
                        json!({
                            "profileId": "explorer",
                            "taskSummary": "Wait-events child report probe",
                            "message": format!(
                                "{MARK_CHILD_WORK} Sleep briefly, then finish_turn with {CHILD_REPORT_TEXT}."
                            ),
                        }),
                        "child-spawn",
                        generation("spawn_agent"),
                    ));
                    note = Some("spawn_child_requested");
                } else {
                    accepted = false;
                    note = Some("spawn_agent_tool_not_declared");
                }
            } else if declared(&tools, "sleep") {
                tool_calls.push(planned(
                    "sleep",
                    sleep_args(CHILD_PARENT_SLEEP_MS),
                    "child-parent-sleep",
                    generation("sleep"),
                ));
                note = Some("child_parent_sleep_started");
            } else {
                accepted = false;
                note = Some("sleep_tool_not_declared");
            }
        }
        Marker::ChildWork => {
            if declared(&tools, "spawn_agent") {
                note = Some("child_marker_on_parent");
            } else {
                let sleep_id = expected("child-work-sleep", "sleep");
                let wait_id = expected("child-work-wait", "wait");
                let finish_id = expected("child-work-finish", "finish_turn");
                if outputs.iter().any(|id| id == &finish_id) {
                    note = Some("child_work_answered");
                } else if outputs.iter().any(|id| id == &wait_id) {
                    if declared(&tools, "finish_turn") {
                        tool_calls.push(planned(
                            "finish_turn",
                            json!({ "message": CHILD_REPORT_TEXT }),
                            "child-work-finish",
                            generation("finish_turn"),
                        ));
                        note = Some("child_work_finish");
                    } else {
                        accepted = false;
                        note = Some("finish_turn_not_declared");
                    }
                } else if outputs.iter().any(|id| id == &sleep_id) {
                    if declared(&tools, "wait") {
                        tool_calls.push(planned(
                            "wait",
                            wait_args(&[&sleep_id], FOLLOW_WAIT_MS),
                            "child-work-wait",
                            generation("wait"),
                        ));
                        note = Some("child_work_wait");
                    } else {
                        accepted = false;
                        note = Some("wait_tool_not_declared");
                    }
                } else if declared(&tools, "sleep") {
                    tool_calls.push(planned(
                        "sleep",
                        sleep_args(CHILD_SLEEP_MS),
                        "child-work-sleep",
                        generation("sleep"),
                    ));
                    note = Some("child_work_sleep");
                } else {
                    accepted = false;
                    note = Some("child_sleep_not_declared");
                }
            }
        }
        Marker::ChildConfirm => {
            let reports = child_report_count(items);
            accepted = reports == 1;
            note = Some(if reports == 1 {
                "child_report_still_once"
            } else if reports == 0 {
                "child_report_dropped"
            } else {
                "child_report_duplicated_later"
            });
        }
        Marker::AlreadyReady => {
            let wait_id = expected("already-ready-wait", "wait");
            if outputs.iter().any(|id| id == &wait_id) {
                note = Some("already_ready_answered");
            } else if declared(&tools, "wait") {
                if let Some(sleep_id) = historical_call_id(items, "sleep-first-sleep") {
                    tool_calls.push(planned(
                        "wait",
                        wait_args(&[&sleep_id], 5_000),
                        "already-ready-wait",
                        generation("wait"),
                    ));
                    note = Some("already_ready_wait");
                } else {
                    accepted = false;
                    note = Some("already_ready_task_missing");
                }
            } else {
                accepted = false;
                note = Some("wait_tool_not_declared");
            }
        }
        Marker::Timeout => {
            let sleep_id = expected("timeout-sleep", "sleep");
            let wait_id = expected("timeout-wait", "wait");
            let cancel_id = expected("timeout-cancel", "cancel_tool_task");
            if outputs.iter().any(|id| id == &cancel_id) {
                note = Some("timeout_answered");
            } else if outputs.iter().any(|id| id == &wait_id) {
                if declared(&tools, "cancel_tool_task") {
                    tool_calls.push(planned(
                        "cancel_tool_task",
                        cancel_args(&sleep_id),
                        "timeout-cancel",
                        generation("cancel_tool_task"),
                    ));
                    note = Some("timeout_cancel_sleep");
                } else {
                    accepted = false;
                    note = Some("cancel_tool_not_declared");
                }
            } else if outputs.iter().any(|id| id == &sleep_id) {
                if declared(&tools, "wait") {
                    tool_calls.push(planned(
                        "wait",
                        wait_args(&[&sleep_id], TIMEOUT_WAIT_MS),
                        "timeout-wait",
                        generation("wait"),
                    ));
                    note = Some("timeout_wait");
                } else {
                    accepted = false;
                    note = Some("wait_tool_not_declared");
                }
            } else if declared(&tools, "sleep") {
                tool_calls.push(planned(
                    "sleep",
                    sleep_args(TIMEOUT_SLEEP_MS),
                    "timeout-sleep",
                    generation("sleep"),
                ));
                note = Some("timeout_sleep_started");
            } else {
                accepted = false;
                note = Some("sleep_tool_not_declared");
            }
        }
        Marker::Cancel => {
            let wait_id = expected("cancel-wait", "wait");
            if outputs.iter().any(|id| id == &wait_id) {
                note = Some("cancel_wait_returned");
            } else if let Some(sleep_id) = historical_call_id(items, "cancel-sleep") {
                if declared(&tools, "wait") {
                    tool_calls.push(planned(
                        "wait",
                        wait_args(&[&sleep_id], CHILD_WAIT_MS),
                        "cancel-wait",
                        generation("wait"),
                    ));
                    note = Some("cancel_wait_hanging");
                } else {
                    accepted = false;
                    note = Some("wait_tool_not_declared");
                }
            } else {
                accepted = false;
                note = Some("cancel_sleep_task_missing");
            }
        }
        Marker::CancelPrepare => {
            let sleep_id = expected("cancel-sleep", "sleep");
            if outputs.iter().any(|id| id == &sleep_id) {
                note = Some("cancel_prepare_answered");
            } else if declared(&tools, "sleep") {
                tool_calls.push(planned(
                    "sleep",
                    sleep_args(CANCEL_SLEEP_MS),
                    "cancel-sleep",
                    generation("sleep"),
                ));
                note = Some("cancel_sleep_started");
            } else {
                accepted = false;
                note = Some("sleep_tool_not_declared");
            }
        }
        Marker::CancelQuery => {
            let Some(sleep_id) = historical_call_id(items, "cancel-sleep") else {
                accepted = false;
                note = Some("cancel_sleep_task_missing");
                record(&state, "POST", "/v1/responses", body, accepted, note);
                return sse_reply(
                    responses_text(
                        "wait-events complete: missing cancel sleep",
                        "wait-events-answer",
                        "fixture-model",
                    ),
                    false,
                    state.stopping.clone(),
                );
            };
            let query_id = expected("cancel-query", "get_tool_task");
            let cancel_id = expected("cancel-query-cancel", "cancel_tool_task");
            if outputs.iter().any(|id| id == &cancel_id) {
                note = Some("cancel_query_answered");
            } else if outputs.iter().any(|id| id == &query_id) {
                if declared(&tools, "cancel_tool_task") {
                    tool_calls.push(planned(
                        "cancel_tool_task",
                        cancel_args(&sleep_id),
                        "cancel-query-cancel",
                        generation("cancel_tool_task"),
                    ));
                    note = Some("cancel_query_cancel");
                } else {
                    accepted = false;
                    note = Some("cancel_tool_not_declared");
                }
            } else if declared(&tools, "get_tool_task") {
                tool_calls.push(planned(
                    "get_tool_task",
                    query_args(&sleep_id),
                    "cancel-query",
                    generation("get_tool_task"),
                ));
                note = Some("cancel_query_status");
            } else {
                accepted = false;
                note = Some("get_tool_task_not_declared");
            }
        }
        Marker::None => {
            accepted = false;
            note = Some("wait_events_unknown_prompt");
        }
    }

    record(&state, "POST", "/v1/responses", body, accepted, note);
    if !tool_calls.is_empty() {
        let calls = tool_calls
            .iter()
            .map(|call| RealtimeToolCall {
                item_id: &call.item_id,
                call_id: &call.call_id,
                name: &call.name,
                arguments: call.arguments.clone(),
            })
            .collect::<Vec<_>>();
        return sse_reply(
            responses_tool_calls("wait-events", "fixture-model", &calls),
            false,
            state.stopping.clone(),
        );
    }
    let answer = if prompt.trim().is_empty() {
        "wait-events complete".to_owned()
    } else {
        format!("wait-events complete: {}", completion_marker(&prompt))
    };
    sse_reply(
        responses_text(&answer, "wait-events-answer", "fixture-model"),
        false,
        state.stopping.clone(),
    )
}
