use super::*;

pub(super) fn awaiting_approval(state: &ThreadSnapshot, task: &TaskRecord) -> bool {
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
pub(super) fn project_tools(
    state: &ThreadSnapshot,
    active_tasks: &[&TaskRecord],
    foreground_turn: Option<&str>,
    kind: ThreadActivityKind,
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
    let entries = ordered
        .iter()
        .map(|task| tool_entry(state, task))
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

fn tool_entry(state: &ThreadSnapshot, task: &TaskRecord) -> ThreadActivityToolEntry {
    let (arguments, summary) = tool_arguments(state, task);
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
        started_at: None,
        wait: wait_presentation(state, task),
    }
}

pub(super) fn wait_presentation(
    state: &ThreadSnapshot,
    task: &TaskRecord,
) -> Option<crate::ThreadWaitPresentation> {
    if !matches!(task.tool_id.as_str(), "wait" | "sleep") {
        return None;
    }
    let arguments = call_arguments(state, &task.call_id)?;
    let activity_state = tool_state(state, task);
    let tool_lifecycle = match activity_state {
        ThreadActivityToolState::Cancelling => {
            crate::ThreadToolState::Cancelling(crate::CancellingThreadTool::new(String::new()))
        }
        ThreadActivityToolState::Finished => return None,
        ThreadActivityToolState::Running | ThreadActivityToolState::AwaitingApproval => {
            crate::ThreadToolState::Running(crate::RunningThreadTool::new(String::new()))
        }
    };
    super::super::wait::project_wait(Some(state), &task.tool_id, arguments, &tool_lifecycle)
}

/// 工具条目的参数事实：完整性判断与摘要。
///
/// 参数来自该 Turn 已提交 attempt 的工具调用（内存事实）；只有参数完整且解析出工具约定的命令行
/// 字段时才给出命令行摘要，其余情况一律回落工具名称，不拼不完整参数、也不填假参数。
fn tool_arguments(state: &ThreadSnapshot, task: &TaskRecord) -> (ThreadActivityArguments, String) {
    match call_arguments(state, &task.call_id) {
        Some(arguments) => match command_line(arguments, str::to_owned) {
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
pub(in crate::studio::thread_projection) fn call_arguments<'a>(
    state: &'a ThreadSnapshot,
    call_id: &str,
) -> Option<&'a str> {
    state
        .context
        .records
        .iter()
        .flat_map(|record| &record.tool_calls)
        .find(|call| call.call_id == call_id)
        .map(|call| call.arguments.content())
}

pub(super) fn call_rank(state: &ThreadSnapshot, call_id: &str) -> Option<(usize, usize)> {
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

/// 工具约定的命令行字段：参数是 JSON 对象且含非空字符串 `command`。
///
/// 这是唯一允许的命令行提取方式；解析不出就回落工具名称，绝不猜测或拼接不完整参数。
pub(in crate::studio::thread_projection) fn command_line<T>(
    arguments: &str,
    project: impl FnOnce(&str) -> T,
) -> Option<T> {
    let value: serde_json::Value = serde_json::from_str(arguments).ok()?;
    let command = value.get("command")?.as_str()?.trim();
    (!command.is_empty()).then(|| project(command))
}

fn tool_name_summary(tool_id: &str) -> String {
    bounded_summary(tool_id).0
}
