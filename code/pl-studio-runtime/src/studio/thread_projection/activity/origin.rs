use super::*;

/// 当前活动的真实来源；执行准备可以早于 Turn 建立。
///
/// Turn 记录只保留运行中的 Turn，但**原生 `exec` 超过 1s 默认转后台**：一个已经完成的 Turn 仍可能
/// 有正在运行的工具任务，其 Turn 记录已经离开运行集合。因此活动不能只看 `TurnState::Running`，
/// 还要由运行中的任务事实、正在进行的打断，以及**仍在等待用户回答的交互**确定当前 Turn：否则
/// “等待输入”会因为 Turn 记录离场而整条消失。
pub(super) struct ActivityOrigin<'a> {
    pub(super) source_id: &'a str,
    pub(super) turn_id: Option<&'a str>,
    pub(super) execution_id: Option<&'a str>,
    pub(super) input_id: Option<&'a str>,
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

pub(super) fn active_origin(state: &ThreadSnapshot) -> Option<ActivityOrigin<'_>> {
    if let InputExecution::Interrupting { turn_id } = &state.input_execution {
        if let Some(turn_id) = turn_id {
            let input_id = state
                .turns
                .iter()
                .find(|turn| &turn.turn_id == turn_id)
                .and_then(|turn| turn.input_id.as_deref());
            return Some(turn_origin(state, turn_id, input_id));
        }
        if let Some(execution) = state.execution.as_ref() {
            return Some(ActivityOrigin {
                source_id: &execution.id,
                turn_id: execution.turn_id.as_deref(),
                execution_id: Some(&execution.id),
                input_id: None,
            });
        }
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
pub(super) fn running_turn(state: &ThreadSnapshot) -> Option<&TurnRecord> {
    state
        .turns
        .iter()
        .rev()
        .find(|record| record.state == TurnState::Running)
}

/// 一个 Turn 最新的 attempt；Turn 尚未开始任何 attempt 时为 `None`。
pub(super) fn turn_attempt<'a>(
    state: &'a ThreadSnapshot,
    turn_id: &str,
) -> Option<&'a RequestAttempt> {
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
pub(super) fn active_tasks(state: &ThreadSnapshot) -> Vec<&TaskRecord> {
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
pub(super) fn associated_attempt(attempt: Option<&RequestAttempt>) -> Option<&RequestAttempt> {
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
pub(super) fn kind(
    state: &ThreadSnapshot,
    turn_id: &str,
    attempt: Option<&RequestAttempt>,
    active_tasks: &[&TaskRecord],
    admitted: Option<&AdmittedActivity<'_>>,
) -> ThreadActivityKind {
    if matches!(
        &state.input_execution,
        InputExecution::Interrupting { turn_id: Some(id) } if id.as_str() == turn_id
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
        let (response, reasoning) = has_stream_facts(state, attempt, admitted);
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
