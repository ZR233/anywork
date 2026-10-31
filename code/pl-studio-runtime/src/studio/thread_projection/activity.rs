//! 当前执行活动的 typed 投影。
//!
//! 活动是独立于 Timeline 内容的投影：内容只决定有哪些条目，活动只描述“当前在做什么”。
//! 它是 canonical 事实的**纯函数**：只读 owner 已发布的 `ThreadSnapshot`（turns/attempts/
//! tasks/permissions/interactions/input_execution/model_progress/model_execution/tool_progress）与
//! “上一条已发布活动”，不读会话、不读历史、不等待也不发送任何东西，因此订阅、快照与冷读得到同一
//! 条投影，而不是第二份正文缓存，也不会在每帧回源 SQL。
//!
//! 摘要只读当前观察的**有界尾部**（[`ACTIVITY_SUMMARY_TAIL_BYTES`]），不按 token 物化整段正文；
//! 正文快照只共享当前活动自己的 `ContentBlock`；订阅者从共享来源编码增量，不物化累计全文、
//! 不读会话或 SQL，也不从已完成内容回填当前态。
//!
//! `preparing` 来自 core 的**显式** [`ModelExecutionPhase`] 准备类阶段（准备上下文 / 构造请求 /
//! 准备请求 / 准入等待），或没有更精确阶段事实时的**中性**兜底；两者都只是“此刻没有可观察到的前台
//! provider 阶段”，不声称正在准备或压缩上下文。只有 provider 调用**真正开始执行**后的等待
//! （[`ModelExecutionPhase::Running`]，或运行中的 attempt 还没有任何流式事实）才是 `waitingApi`：
//! 构造请求、模型实现自己的请求准备与准入等待都不算等待 API，也不借“没有运行中的 attempt”把它报成
//! 准备上下文。
use std::collections::BTreeSet;

use pl_core::context::ContextContent;
use pl_core::model::{
    AggregateChannel, ModelProgress, ObservedItemKind, ObservedPart, ObservedPartIdentity,
    ObservedPartKind,
};
use pl_core::thread::{
    AttemptStatus, ExecutionPhase, ModelExecutionPhase, RequestAttempt, ThreadSnapshot, TurnRecord,
    TurnState,
    input::InputExecution,
    interactions::InteractionState,
    permissions::PermissionState,
    task::{TaskRecord, TaskStatus},
};
use pl_protocol::{
    ACTIVITY_SUMMARY_LIMIT, ThreadActivity, ThreadActivityArguments, ThreadActivityKind,
    ThreadActivityToolEntry, ThreadActivityToolState, ThreadActivityTools,
};

/// 当前执行活动的权威小摘要；`None` 表示该 Thread 当前没有活动。
///
/// 这是**纯内存投影**：给定同一 `state` 与同一 `previous` 必定得到同一结果。`previous` 是同一
/// 订阅上一条已经发布的活动，用来给稳定身份的活动维护单调递增的 [`ThreadActivity::revision`]；
/// 身份不变时只有内容真的变化才递增，身份变化即新活动、版本归零，从而迟到的同身份帧回不到旧活动。
pub(in crate::studio) fn project_activity(
    thread_id: &str,
    state: &ThreadSnapshot,
    previous: Option<&ThreadActivity>,
) -> Option<ThreadActivity> {
    let origin = active_origin(state)?;
    let attempt = origin.turn_id.and_then(|id| turn_attempt(state, id));
    let tasks = active_tasks(state);
    let kind = if origin.execution_id.is_some()
        && state
            .execution
            .as_ref()
            .is_some_and(|execution| execution.phase == ExecutionPhase::Stopping)
    {
        ThreadActivityKind::Stopping
    } else {
        origin
            .turn_id
            .map_or(ThreadActivityKind::Preparing, |turn_id| {
                kind(state, turn_id, attempt, &tasks)
            })
    };
    let tools = project_tools(state, &tasks, origin.turn_id, kind, previous);
    let associated = associated_attempt(attempt);
    let (summary, summary_truncated) = summary(state, associated, origin.turn_id, kind, &tools);
    let previous_turn = previous.filter(|prev| {
        prev.turn_id.as_deref() == origin.turn_id
            && prev.execution_id.as_deref() == origin.execution_id
    });
    let thinking_summary = match kind {
        ThreadActivityKind::Responding => None,
        _ => latest_thinking_summary(state, associated)
            .or_else(|| previous_turn.and_then(|prev| prev.thinking_summary.clone())),
    };
    let thinking_seconds = match kind {
        ThreadActivityKind::Responding => None,
        _ => previous_turn.and_then(|prev| prev.thinking_seconds),
    };
    let step = associated.map_or("preparing", |attempt| attempt.attempt_id.as_str());
    let body = ThreadActivity {
        thread_id: thread_id.to_owned(),
        identity: ThreadActivity::identity(origin.source_id, step, kind),
        revision: 0,
        turn_id: origin.turn_id.map(str::to_owned),
        execution_id: origin.execution_id.map(str::to_owned),
        input_id: origin.input_id.map(str::to_owned),
        attempt_id: associated.map(|attempt| attempt.attempt_id.clone()),
        kind,
        summary,
        summary_truncated,
        thinking_summary,
        thinking_seconds,
        tools,
    };
    Some(match previous {
        Some(previous) if previous.identity == body.identity => {
            if same_body(previous, &body) {
                // 事实没变：沿用上一条（连同它的版本），调用方的相等判断因此不会发帧。
                return Some(previous.clone());
            }
            ThreadActivity {
                revision: previous.revision.saturating_add(1),
                ..body
            }
        }
        _ => body,
    })
}

/// 当前活动的真实来源；执行准备可以早于 Turn 建立。
///
/// Turn 记录只保留运行中的 Turn，但**原生 `exec` 超过 1s 默认转后台**：一个已经完成的 Turn 仍可能
/// 有正在运行的工具任务，其 Turn 记录已经离开运行集合。因此活动不能只看 `TurnState::Running`，
/// 还要由运行中的任务事实、正在进行的打断，以及**仍在等待用户回答的交互**确定当前 Turn：否则
/// “等待输入”会因为 Turn 记录离场而整条消失。
struct ActivityOrigin<'a> {
    source_id: &'a str,
    turn_id: Option<&'a str>,
    execution_id: Option<&'a str>,
    input_id: Option<&'a str>,
}

fn turn_origin<'a>(
    state: &'a ThreadSnapshot,
    turn_id: &'a str,
    input_id: Option<&'a str>,
) -> ActivityOrigin<'a> {
    let execution_id = state
        .execution
        .as_ref()
        .filter(|execution| execution.turn_id.as_deref() == Some(turn_id))
        .map(|execution| execution.id.as_str());
    ActivityOrigin {
        source_id: execution_id.unwrap_or(turn_id),
        turn_id: Some(turn_id),
        execution_id,
        input_id,
    }
}

fn active_origin(state: &ThreadSnapshot) -> Option<ActivityOrigin<'_>> {
    if let InputExecution::Interrupting { turn_id } = &state.input_execution {
        let input_id = state
            .turns
            .iter()
            .find(|turn| &turn.turn_id == turn_id)
            .and_then(|turn| turn.input_id.as_deref());
        return Some(turn_origin(state, turn_id, input_id));
    }
    if let Some(turn) = running_turn(state) {
        return Some(turn_origin(state, &turn.turn_id, turn.input_id.as_deref()));
    }
    if let Some(execution) = state.execution.as_ref() {
        return Some(ActivityOrigin {
            source_id: &execution.id,
            turn_id: execution.turn_id.as_deref(),
            execution_id: Some(&execution.id),
            input_id: None,
        });
    }
    // Turn 已结束但后台任务仍在运行：以最近仍在运行的调用所属 Turn 作为当前活动。
    let background = state
        .tasks
        .values()
        .filter(|task| task.status == TaskStatus::Running)
        .max_by(|left, right| {
            left.turn_id
                .cmp(&right.turn_id)
                .then_with(|| left.call_id.cmp(&right.call_id))
        });
    if let Some(background) = background {
        return Some(turn_origin(state, &background.turn_id, None));
    }
    // Turn 已经离开运行集合，但仍有一条等待用户回答的交互：以该交互所属 Turn 作为当前活动，
    // 否则“等待输入”会因为 Turn 记录离场而整条消失。
    let pending = state
        .interactions
        .values()
        .filter(|record| record.state == InteractionState::Pending)
        .max_by_key(|record| record.updated_at)?;
    Some(turn_origin(state, &pending.request.turn_id, None))
}

/// 运行中的 Turn 记录；没有运行中的 Turn 就没有可读的 Turn 级事实。
fn running_turn(state: &ThreadSnapshot) -> Option<&TurnRecord> {
    state
        .turns
        .iter()
        .rev()
        .find(|record| record.state == TurnState::Running)
}

/// 一个 Turn 最新的 attempt；Turn 尚未开始任何 attempt 时为 `None`。
fn turn_attempt<'a>(state: &'a ThreadSnapshot, turn_id: &str) -> Option<&'a RequestAttempt> {
    state
        .attempts
        .iter()
        .rev()
        .find(|attempt| attempt.turn_id == turn_id)
}

/// 仍在运行的任务（不限 Turn）。
///
/// 原生 `exec` 超过 1s 默认转后台，后台调用可能属于一个已经结束的 Turn，也可能与新的 Turn 并行；
/// 它们都是当前活动里“还在跑”的事实，因此一律列出，由前台阶段决定谁是前台工具。
fn active_tasks(state: &ThreadSnapshot) -> Vec<&TaskRecord> {
    state
        .tasks
        .values()
        .filter(|task| task.status == TaskStatus::Running)
        .collect()
}

/// 活动当前指向的 attempt：只有运行中或已提交的 attempt 才代表“当前步骤”。
///
/// 失败/取消的 attempt 是历史的：Turn 正在为下一次尝试做准备时，活动不再指向它。
/// 已提交 attempt 只参与阶段与摘要判断，正文快照只共享运行中 attempt 的来源。
fn associated_attempt(attempt: Option<&RequestAttempt>) -> Option<&RequestAttempt> {
    attempt.filter(|attempt| {
        matches!(
            attempt.status,
            AttemptStatus::Running | AttemptStatus::Committed
        )
    })
}

/// 活动 kind 的判定顺序：打断 → 待批准 → 待回答 → **运行中的模型 attempt** → **core 显式执行阶段**
/// → 运行中工具 → attempt 事实。
///
/// 模型 attempt 与显式执行阶段都排在工具之前是刻意的：前台正在流式回复或正在准备/等待模型时，并行
/// 工具是**后台**工具，不能被 `runningTool` 盖过；只有没有前台模型阶段时，运行中的工具才是前台阶段。
/// 每一步都对应一个可直接观察的 canonical 事实，任何一步都不从错误文本或 UI 文案推断。
///
/// `Preparing` 由 core 的**显式**准备类阶段（`PreparingContext` / `BuildingRequest` /
/// `PreparingRequest` / `Admitting`）给出；没有更精确阶段事实时它是**中性**兜底，只表示“此刻没有可
/// 观察到的前台 provider 阶段”，**不**断言正在准备或压缩上下文。只有 provider 调用真正开始执行
/// （[`ModelExecutionPhase::Running`]）才算等待模型实现，绝不再借“没有运行中的 attempt”把它报成准备
/// 上下文。
fn kind(
    state: &ThreadSnapshot,
    turn_id: &str,
    attempt: Option<&RequestAttempt>,
    active_tasks: &[&TaskRecord],
) -> ThreadActivityKind {
    if matches!(
        &state.input_execution,
        InputExecution::Interrupting { turn_id: id } if id.as_str() == turn_id
    ) || active_tasks
        .iter()
        .any(|task| task.turn_id == turn_id && task.cancel_requested)
    {
        return ThreadActivityKind::Stopping;
    }
    if active_tasks
        .iter()
        .any(|task| task.turn_id == turn_id && awaiting_approval(state, task))
    {
        return ThreadActivityKind::AwaitingApproval;
    }
    if state.interactions.values().any(|record| {
        record.request.turn_id == turn_id && record.state == InteractionState::Pending
    }) {
        return ThreadActivityKind::AwaitingInput;
    }
    if let Some(attempt) = attempt
        && matches!(attempt.status, AttemptStatus::Running)
    {
        let (response, reasoning) = has_stream_facts(state, attempt);
        return if response {
            ThreadActivityKind::Responding
        } else if reasoning {
            ThreadActivityKind::Thinking
        } else {
            waiting_kind(state)
        };
    }
    // No running attempt yet, but the owner reports an explicit driver phase: the foreground is
    // that phase, and any still-running tool is a background tool.
    if let Some(phase) = state.model_execution
        && running_turn(state).is_some_and(|turn| turn.turn_id == turn_id)
    {
        return phase_kind(phase);
    }
    if active_tasks.iter().any(|task| task.turn_id == turn_id) {
        return ThreadActivityKind::RunningTool;
    }
    let Some(attempt) = attempt else {
        return ThreadActivityKind::Preparing;
    };
    match committed_output(state, attempt) {
        Some(output) if !output.tool_calls.is_empty() => ThreadActivityKind::Planning,
        Some(_) => ThreadActivityKind::Responding,
        None => ThreadActivityKind::Preparing,
    }
}

/// 显式执行阶段 → 活动 kind。
///
/// 只有 provider 调用已经开始执行（`Running`）才是等待模型实现；上下文准备、请求构造、模型实现自己的
/// 请求准备与容量/存储准入一律归中性的 `Preparing`，因此既不会把准入等待说成等待 API，也不会把准备
/// 阶段说成正在压缩上下文。
fn phase_kind(phase: ModelExecutionPhase) -> ThreadActivityKind {
    match phase {
        ModelExecutionPhase::CompactingContext => ThreadActivityKind::Compacting,
        ModelExecutionPhase::PreparingContext
        | ModelExecutionPhase::BuildingRequest
        | ModelExecutionPhase::PreparingRequest
        | ModelExecutionPhase::Admitting => ThreadActivityKind::Preparing,
        ModelExecutionPhase::Running => ThreadActivityKind::WaitingApi,
    }
}

/// 运行中的 attempt 尚无流式事实时的前台阶段：provider 调用已经在执行（`Running`）或没有任何显式阶段
/// 事实时就是等待模型实现；只有显式报告仍在准备上下文/构造请求/准备请求/准入时才是 `Preparing`。
fn waiting_kind(state: &ThreadSnapshot) -> ThreadActivityKind {
    state
        .model_execution
        .map_or(ThreadActivityKind::WaitingApi, phase_kind)
}

fn awaiting_approval(state: &ThreadSnapshot, task: &TaskRecord) -> bool {
    state.permissions.values().any(|permission| {
        permission.call_id == task.call_id && permission.state == PermissionState::Pending
    })
}

fn tool_state(state: &ThreadSnapshot, task: &TaskRecord) -> ThreadActivityToolState {
    if task.cancel_requested {
        return ThreadActivityToolState::Cancelling;
    }
    if awaiting_approval(state, task) {
        return ThreadActivityToolState::AwaitingApproval;
    }
    ThreadActivityToolState::Running
}

/// 并行工具事实：运行中任务及其**纯内存**参数摘要。
///
/// 活跃工具一律列出（即使参数不可读），因为“有一个工具在跑”本身是活动必须展示的事实；只有参数
/// 摘要才允许降级为工具名称。`ordinal` 取 owner 写在该任务上的真实开始序号 `started_sequence`，
/// 供宿主判断“第几个开始”；`started_at` 的 Unix 秒在本会话并不存在，如实给 `None`，绝不编造时间。
fn project_tools(
    state: &ThreadSnapshot,
    active_tasks: &[&TaskRecord],
    foreground_turn: Option<&str>,
    kind: ThreadActivityKind,
    previous: Option<&ThreadActivity>,
) -> ThreadActivityTools {
    let foreground = foreground_calls(state, active_tasks, foreground_turn, kind);
    // 启动顺序是 owner 的真实事实：任务开始时拿到自己的提交序号，所以并发工具的“最近开始”既不是
    // GUI 猜的、不是同秒时间戳或 `call_id` 排序，也不用最新输出冒充启动。只有更早的 v2 记录缺这个
    // 字段时才回落到该 Turn 的调用次序（内存事实），最后才是调用身份。
    let mut ordered = active_tasks.to_vec();
    ordered.sort_by(|left, right| {
        start_order(state, left)
            .cmp(&start_order(state, right))
            .then_with(|| left.call_id.cmp(&right.call_id))
    });
    let now_secs = now_unix_seconds();
    let entries = ordered
        .iter()
        .map(|task| tool_entry(state, task, previous, now_secs))
        .collect::<Vec<_>>();
    let background = active_tasks
        .iter()
        .filter(|task| !foreground.contains(task.call_id.as_str()))
        .count();
    let latest_started = entries.last().cloned();
    ThreadActivityTools {
        count: u32::try_from(entries.len()).unwrap_or(u32::MAX),
        background: u32::try_from(background).unwrap_or(u32::MAX),
        active: entries,
        latest_started,
    }
}

fn now_unix_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| {
            i64::try_from(duration.as_secs()).unwrap_or(i64::MAX)
        })
}

/// 一次调用的真实启动次序键：owner 的开始序号，缺失时回落到该 Turn 的调用次序。
///
/// 键的第一段把“有 owner 开始序号”排在“只有调用次序”和“都没有”之前；同一档内先用 owner 的
/// `started_sequence`（同一提交批内并发创建时可能相等），再用该 Turn 的实际调用次序 `call_rank`
/// 破平，最后才由调用身份稳定排序。因此 `latest_started` 指向的始终是真正最后开始的那次调用，
/// 既不是 GUI 猜的、不是同秒时间戳或 `call_id` 排序，也不用最新输出冒充启动。
fn start_order(state: &ThreadSnapshot, task: &TaskRecord) -> (u8, u64, u64, u64) {
    let (attempt, call) = call_rank(state, &task.call_id)
        .map_or((u64::MAX, u64::MAX), |(attempt, call)| {
            (attempt as u64, call as u64)
        });
    match task.started_sequence {
        Some(sequence) => (0, sequence, attempt, call),
        None => (1, 0, attempt, call),
    }
}

/// 当前就在前台的活跃调用：前台就是工具本身（运行/待批准/取消）时才非空。
fn foreground_calls<'a>(
    state: &ThreadSnapshot,
    active_tasks: &[&'a TaskRecord],
    foreground_turn: Option<&str>,
    kind: ThreadActivityKind,
) -> BTreeSet<&'a str> {
    let current = || {
        active_tasks
            .iter()
            .filter(move |task| Some(task.turn_id.as_str()) == foreground_turn)
    };
    match kind {
        ThreadActivityKind::RunningTool => current().map(|task| task.call_id.as_str()).collect(),
        ThreadActivityKind::AwaitingApproval => current()
            .filter(|task| awaiting_approval(state, task))
            .map(|task| task.call_id.as_str())
            .collect(),
        ThreadActivityKind::Stopping => current()
            .filter(|task| task.cancel_requested)
            .map(|task| task.call_id.as_str())
            .collect(),
        ThreadActivityKind::Preparing
        | ThreadActivityKind::Compacting
        | ThreadActivityKind::WaitingApi
        | ThreadActivityKind::Thinking
        | ThreadActivityKind::Responding
        | ThreadActivityKind::Planning
        | ThreadActivityKind::AwaitingInput => BTreeSet::new(),
    }
}

fn tool_entry(
    state: &ThreadSnapshot,
    task: &TaskRecord,
    previous: Option<&ThreadActivity>,
    now_secs: i64,
) -> ThreadActivityToolEntry {
    let (arguments, summary) = tool_arguments(state, task);
    let started_at = previous
        .and_then(|prev| {
            prev.tools
                .active
                .iter()
                .find(|entry| entry.call_id == task.call_id)
                .and_then(|entry| entry.started_at)
        })
        .or(Some(now_secs));
    ThreadActivityToolEntry {
        call_id: task.call_id.clone(),
        task_id: Some(task.id.clone()),
        name: task.tool_id.clone(),
        summary,
        arguments,
        state: tool_state(state, task),
        // The owner's real start order of this task, so a host can name "the most recently started
        // call" without guessing from call ids, wall-clock seconds or the newest output. Absent only
        // on older v2 records that predate the field.
        ordinal: task.started_sequence,
        started_at,
        wait: wait_presentation(state, task),
    }
}

fn wait_presentation(
    state: &ThreadSnapshot,
    task: &TaskRecord,
) -> Option<pl_protocol::ThreadWaitPresentation> {
    if !matches!(task.tool_id.as_str(), "wait" | "sleep") {
        return None;
    }
    let arguments = call_arguments(state, &task.call_id)?;
    let activity_state = tool_state(state, task);
    let tool_lifecycle = match activity_state {
        ThreadActivityToolState::Cancelling => pl_protocol::ThreadToolState::Cancelling(
            pl_protocol::CancellingThreadTool::new(String::new()),
        ),
        ThreadActivityToolState::Finished => return None,
        ThreadActivityToolState::Running | ThreadActivityToolState::AwaitingApproval => {
            pl_protocol::ThreadToolState::Running(
                pl_protocol::RunningThreadTool::new(String::new()),
            )
        }
    };
    super::wait::project_wait(Some(state), &task.tool_id, &arguments, &tool_lifecycle)
}

/// 工具条目的参数事实：完整性判断与摘要。
///
/// 参数来自该 Turn 已提交 attempt 的工具调用（内存事实）；只有参数完整且解析出工具约定的命令行
/// 字段时才给出命令行摘要，其余情况一律回落工具名称，不拼不完整参数、也不填假参数。
fn tool_arguments(state: &ThreadSnapshot, task: &TaskRecord) -> (ThreadActivityArguments, String) {
    match call_arguments(state, &task.call_id) {
        Some(arguments) => match command_line(&arguments) {
            Some(command) => (ThreadActivityArguments::CommandLine, command),
            None => (
                ThreadActivityArguments::Opaque,
                tool_name_summary(&task.tool_id),
            ),
        },
        None => (
            ThreadActivityArguments::Unavailable,
            tool_name_summary(&task.tool_id),
        ),
    }
}

/// 某次工具调用在内存里的完整参数；调用尚未提交或已经离开内存事实时为 `None`。
fn call_arguments(state: &ThreadSnapshot, call_id: &str) -> Option<String> {
    state
        .context
        .records
        .iter()
        .flat_map(|record| &record.tool_calls)
        .find(|call| call.call_id == call_id)
        .map(|call| call.arguments.content().to_owned())
}

fn call_rank(state: &ThreadSnapshot, call_id: &str) -> Option<(usize, usize)> {
    state
        .context
        .records
        .iter()
        .enumerate()
        .find_map(|(index, record)| {
            record
                .tool_calls
                .iter()
                .position(|call| call.call_id == call_id)
                .map(|rank| (index, rank))
        })
}

fn committed_output<'a>(
    state: &'a ThreadSnapshot,
    attempt: &RequestAttempt,
) -> Option<&'a pl_core::context::ContextRecord> {
    let id = format!("{}:output", attempt.attempt_id);
    state.context.records.iter().find(|record| record.id == id)
}

/// 工具约定的命令行字段：参数是 JSON 对象且含非空字符串 `command`。
///
/// 这是唯一允许的命令行提取方式；解析不出就回落工具名称，绝不猜测或拼接不完整参数。
fn command_line(arguments: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(arguments).ok()?;
    let command = value.get("command")?.as_str()?.trim();
    (!command.is_empty()).then(|| command.to_owned())
}

fn tool_name_summary(tool_id: &str) -> String {
    bounded(tool_id).0
}

/// 活动摘要：当前步骤文本的最新非空逻辑行（只读**有界尾部**），或活跃工具的命令行摘要。
fn summary(
    state: &ThreadSnapshot,
    attempt: Option<&RequestAttempt>,
    foreground_turn: Option<&str>,
    kind: ThreadActivityKind,
    tools: &ThreadActivityTools,
) -> (String, bool) {
    let line = match kind {
        ThreadActivityKind::Thinking | ThreadActivityKind::Responding => {
            let Some(attempt) = attempt else {
                return (String::new(), false);
            };
            let stream = if kind == ThreadActivityKind::Responding {
                ObservedStream::Response
            } else {
                ObservedStream::Reasoning
            };
            let Some(line) = latest_stream_line(state, attempt, stream) else {
                return (String::new(), false);
            };
            // 有界尾部读取可能连行首一起截掉，此时摘要本身也如实标记为截断。
            return bounded_marked(&line.text, line.cut);
        }
        ThreadActivityKind::RunningTool
        | ThreadActivityKind::AwaitingApproval
        | ThreadActivityKind::Stopping => tools
            .active
            .iter()
            .rev()
            .find(|entry| {
                entry
                    .task_id
                    .as_ref()
                    .and_then(|id| state.tasks.get(id))
                    .is_some_and(|task| Some(task.turn_id.as_str()) == foreground_turn)
            })
            .map_or_else(String::new, |entry| entry.summary.clone()),
        ThreadActivityKind::Preparing
        | ThreadActivityKind::Compacting
        | ThreadActivityKind::Planning
        | ThreadActivityKind::WaitingApi
        | ThreadActivityKind::AwaitingInput => String::new(),
    };
    bounded(&line)
}

/// 当前 attempt 最新的思考摘要（`ObservedStream::Summary`）；无摘要事实时返回 `None`。
fn latest_thinking_summary(
    state: &ThreadSnapshot,
    attempt: Option<&RequestAttempt>,
) -> Option<String> {
    let attempt = attempt?;
    let progress = state
        .model_progress
        .as_ref()
        .filter(|progress| progress.attempt_id == attempt.attempt_id)?;
    for part in progress.progress.parts().iter().rev() {
        if part.is_empty() || observed_stream(part) != Some(ObservedStream::Summary) {
            continue;
        }
        if let Some(line) = observed_tail_line(part) {
            let text = bounded(&line.text).0;
            if !text.is_empty() {
                return Some(text);
            }
        }
    }
    None
}

/// 摘要尾部窗口的字节上限。
///
/// 摘要是“当前执行行”，因此只需要末尾有界字节：读取它的代价与已经流出的正文长度无关。窗口大于摘要
/// 上限若干倍，足以在不物化整段正文的前提下取到最新非空逻辑行。
const ACTIVITY_SUMMARY_TAIL_BYTES: usize = 4096;

/// 有界尾部：文本片段，以及该片段是否可能截掉了最后一行（或正文）的开头。
struct TailWindow {
    text: String,
    cut: bool,
}

/// 有界尾部里的一条逻辑行。
struct TailLine {
    text: String,
    cut: bool,
}

/// 当前 attempt 在某条流上的最新非空逻辑行；只读共享内容块的有界尾部。
///
/// 运行中的 attempt 直接读 owner 已发布的 typed 观察（[`ObservedPart`]）：每条观察都有自己的稳定身份
/// 与只追加内容块，因此这里只需要末尾有界字节，不按 token 复制整段正文。reasoning 完全没有可显示行
/// 时用 summary part 补充（它是 reasoning 的补充事实，不是另一段 raw 正文）。已提交的 attempt 用提交
/// 的输出正文（同样是尾部有界读取）。没有事实时返回 `None`——活动不会用历史正文冒充“当前正在输出的
/// 文本”。
fn latest_stream_line(
    state: &ThreadSnapshot,
    attempt: &RequestAttempt,
    stream: ObservedStream,
) -> Option<TailLine> {
    let Some(progress) = state
        .model_progress
        .as_ref()
        .filter(|progress| progress.attempt_id == attempt.attempt_id)
    else {
        return committed_stream_line(state, attempt, stream);
    };
    for part in progress.progress.parts().iter().rev() {
        if part.is_empty() || observed_stream(part) != Some(stream) {
            continue;
        }
        if let Some(line) = observed_tail_line(part) {
            return Some(line);
        }
    }
    if stream != ObservedStream::Reasoning {
        return None;
    }
    for part in progress.progress.parts().iter().rev() {
        if part.is_empty() || observed_stream(part) != Some(ObservedStream::Summary) {
            continue;
        }
        if let Some(line) = observed_tail_line(part) {
            return Some(line);
        }
    }
    None
}

/// 一条观察的有界尾部 → 最新非空逻辑行。
fn observed_tail_line(part: &ObservedPart) -> Option<TailLine> {
    tail_line(observed_tail(part)?)
}

/// 共享内容块的有界尾部：只物化末尾有界字节，不复制已观察的整段正文。
fn observed_tail(part: &ObservedPart) -> Option<TailWindow> {
    let block = part.content();
    let len = block.len();
    if len == 0 {
        return None;
    }
    let start = len.saturating_sub(ACTIVITY_SUMMARY_TAIL_BYTES);
    // `suffix_since` 只接受字符边界；UTF-8 字符最多 4 字节，因此最多向后试 4 个偏移即可命中边界。
    for offset in 0..4 {
        let candidate = start.saturating_add(offset);
        if candidate > len {
            break;
        }
        if let Some(text) = block.suffix_since(candidate) {
            return Some(TailWindow {
                text,
                cut: candidate > 0,
            });
        }
    }
    None
}

/// 已提交输出的最新非空逻辑行；提交输出只承载正文，没有 reasoning 事实。
fn committed_stream_line(
    state: &ThreadSnapshot,
    attempt: &RequestAttempt,
    stream: ObservedStream,
) -> Option<TailLine> {
    if stream != ObservedStream::Response {
        return None;
    }
    let output = committed_output(state, attempt)?;
    tail_line(committed_tail(&output.content)?)
}

/// 提交输出的有界尾部：只取末尾若干文本段的有界字节，不物化整段提交正文。
fn committed_tail(content: &[ContextContent]) -> Option<TailWindow> {
    // 只统计长度（O(文本段数)，不复制正文），用来判断窗口是否截掉了更早的正文。
    let total: usize = content
        .iter()
        .filter_map(|part| match part {
            ContextContent::Text { text } => Some(text.len()),
            _ => None,
        })
        .sum();
    if total == 0 {
        return None;
    }
    let mut pieces: Vec<&str> = Vec::new();
    let mut collected = 0usize;
    for part in content.iter().rev() {
        let ContextContent::Text { text } = part else {
            continue;
        };
        if text.is_empty() {
            continue;
        }
        let remaining = ACTIVITY_SUMMARY_TAIL_BYTES.saturating_sub(collected);
        if text.len() <= remaining {
            pieces.push(&**text);
            collected += text.len();
        } else {
            // 末尾窗口落在这一段内部：只取这一段的末尾 `remaining` 字节（对齐到字符边界），
            // 绝不复制更早的正文。
            let mut start = text.len() - remaining;
            while start < text.len() && !text.is_char_boundary(start) {
                start += 1;
            }
            pieces.push(&text[start..]);
            collected += text.len() - start;
        }
        if collected >= ACTIVITY_SUMMARY_TAIL_BYTES {
            // 窗口已填满，更早的文本段被主动放弃。
            break;
        }
    }
    if pieces.is_empty() {
        return None;
    }
    let mut text = String::with_capacity(collected.min(ACTIVITY_SUMMARY_TAIL_BYTES));
    for piece in pieces.iter().rev() {
        text.push_str(piece);
    }
    Some(TailWindow {
        cut: text.len() < total,
        text,
    })
}

/// 有界尾部 → 最新非空逻辑行；只有窗口里没有任何行边界时，最后一行才可能被窗口截掉行首。
fn tail_line(window: TailWindow) -> Option<TailLine> {
    let text = last_logical_line(&window.text)?.to_owned();
    let has_break = window.text.contains('\n') || window.text.contains('\r');
    Some(TailLine {
        text,
        cut: window.cut && !has_break,
    })
}

/// 一条活动观察所属的流。
///
/// `Summary` 是 reasoning item 的 summary part：它是 reasoning 的补充事实（没有 raw reasoning
/// 时才用于摘要），因此与 raw reasoning 分开聚合，不混成同一段正文。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ObservedStream {
    Response,
    Reasoning,
    Summary,
}

/// 判定一条观察属于哪个流。
///
/// 聚合通道是 adapter 尚未报告 item 边界时的整通道预览；provider part 由它自己的 item/part 事实
/// 决定。两者不匹配（例如 reasoning item 上的 OutputText）不是事实，直接忽略，不猜测、不合并。
fn observed_stream(part: &ObservedPart) -> Option<ObservedStream> {
    match part.identity() {
        ObservedPartIdentity::Aggregate { channel } => match channel {
            AggregateChannel::Text => Some(ObservedStream::Response),
            AggregateChannel::Reasoning => Some(ObservedStream::Reasoning),
        },
        ObservedPartIdentity::Provider(identity) => match (identity.item_kind, identity.part) {
            (ObservedItemKind::Text(_), ObservedPartKind::OutputText) => {
                Some(ObservedStream::Response)
            }
            (ObservedItemKind::Reasoning, ObservedPartKind::ReasoningText) => {
                Some(ObservedStream::Reasoning)
            }
            (ObservedItemKind::Reasoning, ObservedPartKind::SummaryText) => {
                Some(ObservedStream::Summary)
            }
            _ => None,
        },
    }
}

/// 当前 attempt 是否已有输出正文 / reasoning 的流式事实。
///
/// 只检查每条观察的长度，因此活动分类不会为判断“是否在思考/回复”而物化任何正文。
fn has_stream_facts(state: &ThreadSnapshot, attempt: &RequestAttempt) -> (bool, bool) {
    let Some(progress) = state
        .model_progress
        .as_ref()
        .filter(|progress| progress.attempt_id == attempt.attempt_id)
    else {
        return (false, false);
    };
    let mut response = false;
    let mut reasoning = false;
    for part in progress.progress.parts() {
        if part.is_empty() {
            continue;
        }
        match observed_stream(part) {
            Some(ObservedStream::Response) => response = true,
            Some(ObservedStream::Reasoning | ObservedStream::Summary) => reasoning = true,
            None => {}
        }
    }
    (response, reasoning)
}

/// 一条观察 → 详情内容段的身份与所属流。
///
/// 身份与实时投影、writer 共用同一组 `order::*` 函数，因此 id 与 canonical 条目一致：默认聚合通道
/// 落在 `model:{attempt}:text|reasoning`，item 化后的正文落在该 provider item/part 的 canonical id。
fn observed_content_part(
    attempt_id: &str,
    generation: u32,
    part: &ObservedPart,
) -> Option<(String, ObservedStream)> {
    let stream = observed_stream(part)?;
    let item_id = match part.identity() {
        ObservedPartIdentity::Aggregate { channel } => match channel {
            AggregateChannel::Text => super::order::observation_id(attempt_id, generation, "text"),
            AggregateChannel::Reasoning => {
                super::order::observation_id(attempt_id, generation, "reasoning")
            }
        },
        ObservedPartIdentity::Provider(identity) => super::order::presentation_id(
            attempt_id,
            generation,
            &identity.item_id,
            Some(identity.presentation_part()),
        ),
    };
    Some((item_id, stream))
}

/// 文本的最新非空逻辑行；`\n` / `\r` 都是行边界，尾部没有换行符的行同样参与。
fn last_logical_line(text: &str) -> Option<&str> {
    text.rsplit(['\n', '\r'])
        .map(str::trim)
        .find(|line| !line.is_empty())
}

/// 摘要按可见字符上限截断：(文本, 是否被截断)。
fn bounded(text: &str) -> (String, bool) {
    if text.chars().count() <= ACTIVITY_SUMMARY_LIMIT {
        return (text.to_owned(), false);
    }
    (text.chars().take(ACTIVITY_SUMMARY_LIMIT).collect(), true)
}

/// 摘要按可见字符上限截断；`cut` 表示推断来源本身已经做过有界截断。
fn bounded_marked(text: &str, cut: bool) -> (String, bool) {
    let (summary, truncated) = bounded(text);
    (summary, truncated || cut)
}

/// 忽略版本后的活动事实相等；用于判断一次投影是否真的改变了活动。
///
/// 比较的是**已发布的有界事实**（身份、前台 kind、有界摘要、活跃工具条目），既不复制正文，也不整体
/// 克隆两条活动去比较。版本因此只随这些有界事实的变化递增，而流式正文的每个 token 不会让这里去做一次
/// 完整内容比较。
fn same_body(left: &ThreadActivity, right: &ThreadActivity) -> bool {
    left.thread_id == right.thread_id
        && left.identity == right.identity
        && left.turn_id == right.turn_id
        && left.execution_id == right.execution_id
        && left.input_id == right.input_id
        && left.attempt_id == right.attempt_id
        && left.kind == right.kind
        && left.summary == right.summary
        && left.summary_truncated == right.summary_truncated
        && left.thinking_summary == right.thinking_summary
        && left.thinking_seconds == right.thinking_seconds
        && left.tools == right.tools
}

/// 当前活动的共享来源；只保留共享句柄、活动身份和实时工具元数据。
struct ActivitySource {
    activity: ThreadActivity,
    /// 活动指向的稳定 attempt 身份；内容段身份由实时投影与 writer 共用的 `order::*` 派生，因此与
    /// canonical 条目一致。
    attempt_id: Option<String>,
    /// 该 attempt 当前观察的**共享句柄**（只追加内容块的前缀链），克隆不复制正文。
    progress: Option<ModelProgress>,
    /// 活跃工具条目的键；只有它变化时才重建工具来源。
    tool_key: Vec<ThreadActivityToolEntry>,
    tools: Vec<ToolSource>,
    source: ActivitySourceKey,
}

/// 来源签名：换活动、观察出现或消失时重新捕获来源。
struct ActivitySourceKey {
    identity: String,
    attempt_id: Option<String>,
    observed: bool,
}

impl ActivitySourceKey {
    /// 两份来源是否指向同一个活动与同一组已经存在的观察事实。
    fn same(&self, other: &Self) -> bool {
        self.identity == other.identity
            && self.attempt_id == other.attempt_id
            && self.observed == other.observed
    }
}

/// 一条活跃工具调用的驻留来源：身份、参数事实与共享输出句柄。
struct ToolSource {
    entry: ThreadActivityToolEntry,
    task_id: Option<String>,
    /// 该调用的完整参数（调用已提交才有）；读不到时如实为 `None`，不填假参数。
    arguments: Option<std::sync::Arc<pl_core::model::ContentBlock>>,
    /// `None` 表示尚无观测；`Some` 的空 parts 表示生产者已发布空输出事实。
    ///
    /// 判空与截断都由共享内容块自己给出，读取时才知道字节数，不复制已观察正文。
    task_output: Option<pl_core::model::ToolProgress>,
}

/// One immutable view of the current activity. Text remains shared with its canonical producer;
/// each subscriber encodes only the suffix since its own last delivery.
#[derive(Debug, Clone, Default)]
pub(in crate::studio) struct ActivitySnapshot {
    /// 发布该活动快照前已可查询的完成上界；传输在活动退出前连续移交到此位置。
    pub completed_through: u64,
    pub activity: Option<ThreadActivity>,
    pub reasoning: Vec<pl_protocol::ActivityPartMetadata>,
    pub response: Vec<pl_protocol::ActivityPartMetadata>,
    pub tools: Vec<pl_protocol::ActivityToolMetadata>,
    pub text: std::collections::BTreeMap<
        pl_protocol::ActivityTextRegion,
        std::sync::Arc<pl_core::model::ContentBlock>,
    >,
}

impl ActivitySource {
    fn snapshot(&self) -> ActivitySnapshot {
        use pl_protocol::{ActivityPartMetadata, ActivityTextRegion, ActivityToolMetadata};
        let mut value = ActivitySnapshot {
            activity: Some(self.activity.clone()),
            ..Default::default()
        };
        if let (Some(attempt_id), Some(progress)) =
            (self.attempt_id.as_deref(), self.progress.as_ref())
        {
            for part in progress.parts() {
                let Some((item_id, stream)) =
                    observed_content_part(attempt_id, progress.observation().generation, part)
                else {
                    continue;
                };
                let metadata = ActivityPartMetadata {
                    item_id: item_id.clone(),
                    complete: false,
                    total_bytes: part.len() as u64,
                };
                let region = match stream {
                    ObservedStream::Response => {
                        value.response.push(metadata);
                        ActivityTextRegion::Response { item_id }
                    }
                    ObservedStream::Reasoning | ObservedStream::Summary => {
                        value.reasoning.push(metadata);
                        ActivityTextRegion::Reasoning { item_id }
                    }
                };
                value.text.insert(region, part.content().clone());
            }
        }
        for tool in &self.tools {
            let arguments = tool.arguments.clone();
            value.tools.push(ActivityToolMetadata {
                call_id: tool.entry.call_id.clone(),
                task_id: tool.task_id.clone().or_else(|| tool.entry.task_id.clone()),
                name: tool.entry.name.clone(),
                state: tool.entry.state,
                started_at: tool.entry.started_at,
                source_order: tool.entry.ordinal,
                arguments_bytes: arguments.as_ref().map(|block| block.len() as u64),
                output_bytes: tool
                    .task_output
                    .as_ref()
                    .map(pl_core::model::ToolProgress::bytes),
                output_parts: tool.task_output.as_ref().map_or_else(Vec::new, |progress| {
                    progress
                        .parts()
                        .iter()
                        .map(|part| pl_protocol::ActivityToolOutputMetadata {
                            part_id: part.id().to_owned(),
                            total_bytes: part.len() as u64,
                        })
                        .collect()
                }),
                wait: tool.entry.wait.clone(),
            });
            if let Some(block) = arguments {
                value.text.insert(
                    ActivityTextRegion::ToolArguments {
                        call_id: tool.entry.call_id.clone(),
                    },
                    block,
                );
            }
            if let Some(progress) = &tool.task_output {
                for part in progress.parts() {
                    value.text.insert(
                        ActivityTextRegion::ToolOutput {
                            call_id: tool.entry.call_id.clone(),
                            part_id: part.id().to_owned(),
                        },
                        part.content().clone(),
                    );
                }
            }
        }
        value
    }
}

/// 活动指向的 attempt：活动身份优先，其次该 Turn 当前最新的 attempt。
fn activity_attempt<'a>(
    state: &'a ThreadSnapshot,
    activity: &ThreadActivity,
) -> Option<&'a RequestAttempt> {
    activity
        .attempt_id
        .as_deref()
        .and_then(|id| {
            state
                .attempts
                .iter()
                .find(|attempt| attempt.attempt_id == id)
        })
        .or_else(|| {
            activity
                .turn_id
                .as_deref()
                .and_then(|id| turn_attempt(state, id))
        })
}

/// 该 attempt 的共享观察句柄；克隆它只增加一次 `Arc` 引用计数，不复制已观察正文。
fn shared_progress(state: &ThreadSnapshot, attempt: &RequestAttempt) -> Option<ModelProgress> {
    if attempt.status != AttemptStatus::Running {
        return None;
    }
    state
        .model_progress
        .as_ref()
        .filter(|progress| progress.attempt_id == attempt.attempt_id)
        .map(|progress| progress.progress.clone())
}

/// 活跃工具条目的驻留来源：身份、参数与共享输出句柄。
fn tool_sources(state: &ThreadSnapshot, entries: &[ThreadActivityToolEntry]) -> Vec<ToolSource> {
    entries
        .iter()
        .map(|entry| {
            let task = state
                .tasks
                .values()
                .find(|task| task.call_id == entry.call_id);
            ToolSource {
                entry: entry.clone(),
                task_id: task.map(|task| task.id.clone()),
                arguments: call_arguments(state, &entry.call_id)
                    .map(|text| pl_core::model::ContentBlock::from_text(&text)),
                task_output: task.and_then(|task| state.tool_progress.get(&task.id).cloned()),
            }
        })
        .collect()
}

/// 活动的唯一投影 owner 助手。
///
/// 它把当前活动与共享正文来源的推导收敛到一处：只吃 owner 已发布的 `ThreadSnapshot`
/// 与上一条活动，不持有 Session、不 await、不读 SQL、不发帧。观察任务是这份助手的唯一持有者（每个
/// 驻留 Thread 一份），订阅与快照投影调用同一个 [`project_activity`]，因此活动定义只有一处。
///
/// 活动本体是有界 typed 摘要（稳定身份 + 前台 kind + 有界最新逻辑行 + 活跃工具条目），版本覆盖这些
/// 已发布事实及正文的共享进度版本，不按整段正文比较；快照只保留当前活动成员的共享观察句柄。
#[derive(Default)]
pub(in crate::studio) struct ActivityProjection {
    previous: Option<ThreadActivity>,
    source: Option<ActivitySource>,
    thinking_started_at: Option<ThinkingStartedAt>,
}

struct ThinkingStartedAt {
    turn_id: Option<String>,
    execution_id: Option<String>,
    attempt_id: Option<String>,
    at: i64,
}

impl ActivityProjection {
    pub(in crate::studio) fn snapshot(&self) -> ActivitySnapshot {
        self.source
            .as_ref()
            .map_or_else(ActivitySnapshot::default, ActivitySource::snapshot)
    }

    /// 由 owner 已发布状态推导当前活动，并刷新共享正文来源。
    ///
    /// `None` 表示当前没有活动，此时来源被清除；已完成正文不会回填当前态。
    /// 来源不变时只刷新有界活动本体与共享观察句柄，不物化正文。
    pub(in crate::studio) fn observe(
        &mut self,
        thread_id: &str,
        state: &ThreadSnapshot,
    ) -> Option<ThreadActivity> {
        let mut activity = project_activity(thread_id, state, self.previous.as_ref());
        if let Some(act) = activity.as_mut() {
            let now = now_unix_seconds();
            if act.kind == ThreadActivityKind::Thinking {
                let same_step = self.thinking_started_at.as_ref().is_some_and(|started| {
                    started.turn_id == act.turn_id
                        && started.execution_id == act.execution_id
                        && started.attempt_id == act.attempt_id
                });
                if !same_step {
                    self.thinking_started_at = Some(ThinkingStartedAt {
                        turn_id: act.turn_id.clone(),
                        execution_id: act.execution_id.clone(),
                        attempt_id: act.attempt_id.clone(),
                        at: now,
                    });
                }
                if act.thinking_summary.is_some()
                    && let Some(started) = self.thinking_started_at.as_ref()
                {
                    let elapsed = u64::try_from((now - started.at).max(0)).unwrap_or(0);
                    if act.thinking_seconds != Some(elapsed) {
                        act.thinking_seconds = Some(elapsed);
                    }
                }
            } else if let Some(started) = self.thinking_started_at.take()
                && started.turn_id == act.turn_id
                && started.execution_id == act.execution_id
                && act.kind != ThreadActivityKind::Responding
            {
                let elapsed = u64::try_from((now - started.at).max(0)).unwrap_or(0);
                act.thinking_seconds = Some(elapsed);
            }
            if let Some(prev) = self.previous.as_ref()
                && prev.identity == act.identity
            {
                if same_body(prev, act) {
                    act.revision = prev.revision;
                } else if act.revision == prev.revision {
                    act.revision = prev.revision.saturating_add(1);
                }
            }
        } else {
            self.thinking_started_at = None;
        }
        let source_changed = self.sync_source(state, activity.as_ref());
        if source_changed
            && let Some(act) = activity.as_mut()
            && let Some(previous) = self.previous.as_ref()
            && previous.identity == act.identity
            && previous.revision == act.revision
        {
            act.revision = previous.revision.saturating_add(1);
        }
        if let (Some(source), Some(activity)) = (self.source.as_mut(), activity.as_ref()) {
            source.activity = activity.clone();
        }
        self.previous = activity.clone();
        activity
    }

    /// Refresh shared snapshots without materializing text. The returned change
    /// covers content versions as well as the lightweight activity body.
    fn sync_source(&mut self, state: &ThreadSnapshot, activity: Option<&ThreadActivity>) -> bool {
        let Some(activity) = activity else {
            self.source = None;
            return false;
        };
        let attempt = activity_attempt(state, activity);
        let progress = attempt.and_then(|attempt| shared_progress(state, attempt));
        let source = ActivitySourceKey {
            identity: activity.identity.clone(),
            attempt_id: attempt.map(|attempt| attempt.attempt_id.clone()),
            observed: progress.is_some(),
        };
        if self
            .source
            .as_ref()
            .is_some_and(|detail| detail.source.same(&source))
        {
            let detail = self.source.as_mut().expect("checked above");
            let progress_version =
                |progress: &ModelProgress| (progress.observation().generation, progress.version());
            let mut changed = detail.progress.as_ref().map(progress_version)
                != progress.as_ref().map(progress_version);
            // 共享句柄：克隆只增加一次 `Arc` 引用计数，正文不参与。
            detail.progress = progress;
            if detail.tool_key != activity.tools.active {
                detail.tool_key = activity.tools.active.clone();
                detail.tools = tool_sources(state, &activity.tools.active);
                changed = true;
            } else {
                for tool in &mut detail.tools {
                    let next = tool
                        .task_id
                        .as_ref()
                        .and_then(|id| state.tool_progress.get(id).cloned());
                    if tool
                        .task_output
                        .as_ref()
                        .map(pl_core::model::ToolProgress::version)
                        != next.as_ref().map(pl_core::model::ToolProgress::version)
                    {
                        tool.task_output = next;
                        changed = true;
                    }
                }
            }
            return changed;
        }
        self.source = Some(ActivitySource {
            activity: activity.clone(),
            attempt_id: source.attempt_id.clone(),
            progress,
            tool_key: activity.tools.active.clone(),
            tools: tool_sources(state, &activity.tools.active),
            source,
        });
        true
    }

    /// 该助手当前驻留的字节：上一条活动摘要、当前活动本体与它捕获的共享来源。
    ///
    /// 常驻共享句柄（克隆 `Arc` 不复制正文）与小型身份按已发布事实计量，不物化整段文本。
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let mut bytes = self.previous.as_ref().map_or(0, activity_bytes);
        if let Some(detail) = self.source.as_ref() {
            bytes = bytes.saturating_add(activity_bytes(&detail.activity));
            for tool in &detail.tools {
                bytes = bytes
                    .saturating_add(tool.entry.name.len() as u64)
                    .saturating_add(tool.entry.summary.len() as u64)
                    .saturating_add(
                        tool.arguments
                            .as_ref()
                            .map_or(0, |arguments| arguments.len() as u64),
                    )
                    .saturating_add(
                        // 共享内容块按已观察字节计量，不物化整段正文。
                        tool.task_output
                            .as_ref()
                            .map_or(0, pl_core::model::ToolProgress::bytes),
                    );
            }
        }
        bytes
    }
}

/// 一条活动摘要与工具条目的文本字节。
fn activity_bytes(activity: &ThreadActivity) -> u64 {
    let mut bytes = activity.summary.len() as u64
        + activity
            .thinking_summary
            .as_ref()
            .map_or(0, |summary| summary.len() as u64);
    for tool in activity
        .tools
        .active
        .iter()
        .chain(activity.tools.latest_started.iter())
    {
        bytes = bytes
            .saturating_add(tool.summary.len() as u64)
            .saturating_add(tool.name.len() as u64);
    }
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_core::model::{ActiveModelProgress, ToolProgress, ToolProgressPart, ToolProgressUpdate};
    use pl_core::thread::{
        ActiveExecution,
        interactions::{InteractionRecord, InteractionRequest},
    };
    use pl_protocol::ActivityTextRegion;
    use std::sync::Arc;

    fn running_state(text: &str) -> ThreadSnapshot {
        let attempt: RequestAttempt = serde_json::from_value(serde_json::json!({
            "turnId": "turn",
            "attemptId": "attempt",
            "retryOf": null,
            "inputRevision": 0,
            "status": {"kind": "running"}
        }))
        .unwrap();
        ThreadSnapshot {
            turns: Arc::from([TurnRecord {
                turn_id: "turn".into(),
                input_id: Some("input".into()),
                state: TurnState::Running,
                model_steps: 1,
                elapsed_ms: None,
            }]),
            attempts: Arc::from([attempt]),
            model_progress: Some(ActiveModelProgress {
                attempt_id: "attempt".into(),
                progress: ModelProgress::new(
                    1,
                    vec![
                        ObservedPart::new(ObservedPartIdentity::Aggregate {
                            channel: AggregateChannel::Text,
                        })
                        .appended(text),
                    ],
                ),
            }),
            ..Default::default()
        }
    }

    #[test]
    fn pre_turn_execution_uses_real_identity_in_all_five_phases() {
        let mut projection = ActivityProjection::default();
        for phase in [
            ExecutionPhase::Preparing,
            ExecutionPhase::AwaitingStorage,
            ExecutionPhase::AwaitingAdmission,
            ExecutionPhase::Running,
            ExecutionPhase::Stopping,
        ] {
            let state = ThreadSnapshot {
                execution: Some(ActiveExecution {
                    id: "opaque-execution:id".into(),
                    phase,
                    turn_id: None,
                }),
                // Without a Turn this unrelated model phase is not a provider call fact.
                model_execution: Some(ModelExecutionPhase::Running),
                ..Default::default()
            };
            let activity = projection.observe("thread", &state).unwrap();
            let kind = if phase == ExecutionPhase::Stopping {
                ThreadActivityKind::Stopping
            } else {
                ThreadActivityKind::Preparing
            };
            assert_eq!(activity.turn_id, None);
            assert_eq!(
                activity.execution_id.as_deref(),
                Some("opaque-execution:id")
            );
            assert_eq!(activity.kind, kind);
            assert_eq!(
                activity.identity,
                ThreadActivity::identity("opaque-execution:id", "preparing", kind)
            );
            assert!(projection.snapshot().text.is_empty());
        }
        assert!(
            projection
                .observe("thread", &ThreadSnapshot::default())
                .is_none()
        );
        assert!(projection.snapshot().activity.is_none());
    }

    #[test]
    fn turn_admission_preserves_execution_and_other_turn_sources_do_not_inherit_it() {
        let mut state = ThreadSnapshot {
            execution: Some(ActiveExecution {
                id: "execution".into(),
                phase: ExecutionPhase::Preparing,
                turn_id: None,
            }),
            ..Default::default()
        };
        let mut projection = ActivityProjection::default();
        let preparing = projection.observe("thread", &state).unwrap();
        state.turns = running_state("").turns;
        state.execution.as_mut().unwrap().phase = ExecutionPhase::Running;
        state.execution.as_mut().unwrap().turn_id = Some("turn".into());
        let admitted = projection.observe("thread", &state).unwrap();
        assert_eq!(admitted.turn_id.as_deref(), Some("turn"));
        assert_eq!(admitted.execution_id.as_deref(), Some("execution"));
        assert_eq!(preparing.identity, admitted.identity);

        let execution = state.execution.take();
        state = running_state("foreground response");
        state.execution = execution;
        state.tasks.insert(
            "background".into(),
            TaskRecord {
                id: "background".into(),
                call_id: "background-call".into(),
                tool_id: "exec".into(),
                turn_id: "background-turn".into(),
                revision: 1,
                status: TaskStatus::Running,
                cancel_requested: true,
                acknowledgement: None,
                started_sequence: Some(5),
            },
        );
        state.interactions.insert(
            "question".into(),
            InteractionRecord {
                created_at: 1,
                updated_at: 1,
                continuation_id: None,
                request: InteractionRequest {
                    id: "question".into(),
                    turn_id: "question-turn".into(),
                    payload: pl_core::context::OpaquePayload::new("test.question", 1, "{}")
                        .unwrap(),
                },
                revision: 1,
                state: InteractionState::Pending,
                extension_mutations: vec![],
            },
        );
        let foreground = projection.observe("thread", &state).unwrap();
        assert_eq!(foreground.kind, ThreadActivityKind::Responding);
        assert_eq!(foreground.turn_id.as_deref(), Some("turn"));
        assert_eq!(foreground.execution_id.as_deref(), Some("execution"));
        assert_eq!(foreground.tools.background, 1);

        let mut preparing_with_background = state.clone();
        preparing_with_background.attempts = Arc::from([]);
        preparing_with_background.model_progress = None;
        let preparing = project_activity("thread", &preparing_with_background, None).unwrap();
        assert_eq!(preparing.kind, ThreadActivityKind::Preparing);
        assert_eq!(preparing.tools.background, 1);

        // A known Running Turn is authoritative even if another execution identity is present.
        state.execution.as_mut().unwrap().turn_id = Some("unrelated-turn".into());
        let unrelated = projection.observe("thread", &state).unwrap();
        assert_eq!(unrelated.turn_id.as_deref(), Some("turn"));
        assert_eq!(unrelated.execution_id, None);
        assert_eq!(
            unrelated.identity,
            ThreadActivity::identity("turn", "attempt", ThreadActivityKind::Responding)
        );

        state.execution = None;
        state.turns = Arc::from([]);
        let background = projection.observe("thread", &state).unwrap();
        assert_eq!(background.turn_id.as_deref(), Some("background-turn"));
        assert_eq!(background.execution_id, None);
        assert_eq!(background.kind, ThreadActivityKind::Stopping);
        state.tasks.clear();
        let question = projection.observe("thread", &state).unwrap();
        assert_eq!(question.turn_id.as_deref(), Some("question-turn"));
        assert_eq!(question.execution_id, None);
        assert_eq!(question.kind, ThreadActivityKind::AwaitingInput);
        state.interactions.clear();
        assert!(projection.observe("thread", &state).is_none());
    }

    #[test]
    fn snapshot_shares_body_and_advances_when_bounded_summary_does_not() {
        let prefix = "文".repeat(ACTIVITY_SUMMARY_LIMIT + 1);
        let mut state = running_state(&prefix);
        let mut projection = ActivityProjection::default();
        let first = projection.observe("thread", &state).unwrap();
        let first_snapshot = projection.snapshot();
        let part = &state.model_progress.as_ref().unwrap().progress.parts()[0];
        let region = ActivityTextRegion::Response {
            item_id: first_snapshot.response[0].item_id.clone(),
        };
        assert!(Arc::ptr_eq(&first_snapshot.text[&region], part.content()));

        let appended = part.appended("继续");
        state.model_progress.as_mut().unwrap().progress =
            ModelProgress::new(2, vec![appended.clone()]);
        let next = projection.observe("thread", &state).unwrap();
        assert_eq!(first.summary, next.summary);
        assert_eq!(first.identity, next.identity);
        assert!(next.revision > first.revision);
        let snapshot = projection.snapshot();
        assert!(Arc::ptr_eq(&snapshot.text[&region], appended.content()));
        assert_eq!(snapshot.text[&region].text(), format!("{prefix}继续"));
        assert_eq!(first_snapshot.text[&region].text(), prefix);
        assert_eq!(projection.observe("thread", &state), Some(next));
    }

    #[test]
    fn completed_attempt_leaves_live_body_and_next_attempt_has_its_own_identity() {
        let mut state = running_state("old body");
        let mut projection = ActivityProjection::default();
        let first = projection.observe("thread", &state).unwrap();
        assert_eq!(projection.snapshot().response.len(), 1);
        // Keep even the stale producer handle resident: terminal attempt status is authoritative.
        Arc::make_mut(&mut state.attempts)[0].status = AttemptStatus::Committed;
        state.model_execution = Some(ModelExecutionPhase::PreparingContext);
        let preparing = projection.observe("thread", &state).unwrap();
        assert_eq!(preparing.kind, ThreadActivityKind::Preparing);
        let snapshot = projection.snapshot();
        assert!(snapshot.response.is_empty());
        assert!(snapshot.reasoning.is_empty());
        assert!(snapshot.text.is_empty());

        let mut next = running_state("new body");
        Arc::make_mut(&mut next.attempts)[0].attempt_id = "next-attempt".into();
        next.model_progress.as_mut().unwrap().attempt_id = "next-attempt".into();
        let current = projection.observe("thread", &next).unwrap();
        assert_ne!(first.identity, current.identity);
        let snapshot = projection.snapshot();
        assert_eq!(snapshot.text.len(), 1);
        assert_eq!(snapshot.text.values().next().unwrap().text(), "new body");
        assert_ne!(
            snapshot.response[0].item_id,
            super::super::order::observation_id("attempt", 0, "text")
        );

        next.turns = Arc::from([]);
        assert!(projection.observe("thread", &next).is_none());
        let ended = projection.snapshot();
        assert!(ended.activity.is_none());
        assert!(ended.text.is_empty());
    }

    #[test]
    fn background_tool_keeps_shared_output_until_actual_terminal_status() {
        let mut state = ThreadSnapshot::default();
        state.tasks.insert(
            "task".into(),
            TaskRecord {
                id: "task".into(),
                call_id: "call".into(),
                turn_id: "finished-turn".into(),
                tool_id: "exec".into(),
                revision: 1,
                status: TaskStatus::Running,
                cancel_requested: false,
                acknowledgement: None,
                started_sequence: Some(12),
            },
        );
        let mut projection = ActivityProjection::default();
        let activity = projection.observe("thread", &state).unwrap();
        assert_eq!(activity.kind, ThreadActivityKind::RunningTool);
        assert_eq!(projection.snapshot().tools[0].output_bytes, None);
        assert!(projection.snapshot().text.is_empty());

        state
            .tool_progress
            .insert("task".into(), ToolProgress::default());
        let observed_empty = projection.observe("thread", &state).unwrap();
        assert!(observed_empty.revision > activity.revision);
        assert_eq!(projection.snapshot().tools[0].output_bytes, Some(0));
        assert!(projection.snapshot().tools[0].output_parts.is_empty());
        assert!(projection.snapshot().text.is_empty());

        let progress = ToolProgress::new(1, vec![ToolProgressPart::new("empty")])
            .applied(&ToolProgressUpdate::append("stdout", "输出"))
            .applied(&ToolProgressUpdate::append("stderr", "error"));
        state.tool_progress.insert("task".into(), progress.clone());
        projection.observe("thread", &state).unwrap();
        let snapshot = projection.snapshot();
        assert_eq!(snapshot.tools[0].call_id, "call");
        assert_eq!(snapshot.tools[0].source_order, Some(12));
        assert_eq!(
            snapshot.tools[0].output_bytes,
            Some("输出error".len() as u64)
        );
        assert_eq!(
            snapshot.tools[0]
                .output_parts
                .iter()
                .map(|part| (part.part_id.as_str(), part.total_bytes))
                .collect::<Vec<_>>(),
            vec![("empty", 0), ("stdout", 6), ("stderr", 5)]
        );
        for part in progress.parts() {
            assert!(Arc::ptr_eq(
                &snapshot.text[&ActivityTextRegion::ToolOutput {
                    call_id: "call".into(),
                    part_id: part.id().into(),
                }],
                part.content()
            ));
        }
        state.tool_progress.remove("task");
        projection.observe("thread", &state).unwrap();
        assert_eq!(projection.snapshot().tools[0].output_bytes, None);
        assert!(projection.snapshot().text.is_empty());

        state.tasks.get_mut("task").unwrap().cancel_requested = true;
        let stopping = projection.observe("thread", &state).unwrap();
        assert_eq!(stopping.kind, ThreadActivityKind::Stopping);
        assert_eq!(projection.snapshot().tools.len(), 1);

        state.tasks.get_mut("task").unwrap().status = TaskStatus::Succeeded;
        assert!(projection.observe("thread", &state).is_none());
        assert!(projection.snapshot().tools.is_empty());
        assert!(projection.snapshot().text.is_empty());
    }
}
