//! 当前执行活动的 typed 投影。
//!
//! 活动是独立于 Timeline 内容的投影：内容只决定有哪些条目，活动只描述“当前在做什么”。
//! 它是 canonical 事实的**纯函数**：只读 owner 已发布的 `ThreadSnapshot`（turns/attempts/
//! tasks/permissions/interactions/input_execution/model_progress/model_execution/tool_progress）与
//! “上一条已发布活动”，不读会话、不读历史、不等待也不发送任何东西，因此订阅、快照与冷读得到同一
//! 条投影，而不是第二份正文缓存，也不会在每帧回源 SQL。
//!
//! 摘要只读当前观察的**有界尾部**（[`summary::ACTIVITY_SUMMARY_TAIL_BYTES`]），不按 token 物化整段正文；
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

use crate::{
    ACTIVITY_SUMMARY_LIMIT, ThreadActivity, ThreadActivityArguments, ThreadActivityKind,
    ThreadActivityToolEntry, ThreadActivityToolState, ThreadActivityTools,
};
use pl_core::context::ContextContent;
use pl_core::model::{ModelProgress, ObservedPart};
use pl_core::thread::{
    AttemptStatus, ExecutionPhase, ModelExecutionPhase, RequestAttempt, ThreadSnapshot, TurnRecord,
    TurnState,
    input::InputExecution,
    interactions::InteractionState,
    permissions::PermissionState,
    task::{TaskRecord, TaskStatus},
};

mod origin;
mod summary;
mod tools;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(in crate::studio::thread_projection) struct ModelPartLocation {
    pub generation: u32,
    pub index: usize,
}

#[cfg(test)]
pub(super) struct ActiveTextPart {
    pub(super) id: String,
    pub(super) model_part: Option<ModelPartLocation>,
}

use super::observation_parts::{ObservedKind, classify};
use origin::*;
pub(in crate::studio::thread_projection) use summary::bounded_summary;
use summary::*;
use tools::*;
pub(in crate::studio::thread_projection) use tools::{call_arguments, command_line};

/// A frame-local view of the original current owner's admitted activity and part locations.
/// It borrows the same immutable observation as current content; it owns no retained history.
#[cfg(test)]
struct AdmittedActivity<'a> {
    atoms: &'a [crate::ChatAtom],
    parts: Vec<&'a ObservedPart>,
}

#[cfg(test)]
impl<'a> AdmittedActivity<'a> {
    fn new(
        state: &'a ThreadSnapshot,
        atoms: &'a [crate::ChatAtom],
        active: &[ActiveTextPart],
    ) -> Self {
        let mut parts = Vec::new();
        if let Some(progress) = &state.model_progress {
            for ActiveTextPart {
                id,
                model_part: location,
                ..
            } in active
            {
                let Some(location) = location.filter(|location| {
                    location.generation == progress.progress.observation().generation
                }) else {
                    continue;
                };
                let Some(atom) = atoms.iter().find(|atom| {
                    atom.id == *id
                        && atom.attempt_id.as_deref() == Some(&progress.attempt_id)
                        && matches!(atom.lifecycle, crate::ChatAtomLifecycle::Active { .. })
                }) else {
                    continue;
                };
                let Some(part) = progress.progress.parts().get(location.index) else {
                    continue;
                };
                // A whole-snapshot replacement can reuse a position, length and content version.
                // A location is only a hint until the typed identity agrees in this generation.
                let Some((current_id, _, _)) = super::observation_parts::observation_preview(
                    &progress.attempt_id,
                    location.generation,
                    part,
                    &crate::ThreadContentLifecycle::streaming(),
                ) else {
                    continue;
                };
                if current_id == atom.id {
                    parts.push((location.index, part));
                }
            }
        }
        parts.sort_unstable_by_key(|(index, _)| *index);
        parts.dedup_by_key(|(index, _)| *index);
        Self {
            atoms,
            parts: parts.into_iter().map(|(_, part)| part).collect(),
        }
    }
}

#[cfg(test)]
fn activity_parts<'a>(
    progress: &'a ModelProgress,
    admitted: Option<&'a AdmittedActivity<'a>>,
) -> impl DoubleEndedIterator<Item = &'a ObservedPart> {
    admitted
        .into_iter()
        .flat_map(|view| view.parts.iter().copied())
        .chain(
            admitted
                .is_none()
                .then(|| progress.parts().iter())
                .into_iter()
                .flatten(),
        )
}

#[cfg(not(test))]
enum AdmittedActivity<'a> {
    #[allow(dead_code)]
    Never(std::marker::PhantomData<&'a ()>),
}

#[cfg(not(test))]
fn activity_parts<'a>(
    progress: &'a ModelProgress,
    _admitted: Option<&'a AdmittedActivity<'a>>,
) -> impl DoubleEndedIterator<Item = &'a ObservedPart> {
    progress.parts().iter()
}

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
    project_activity_using(thread_id, state, previous, None)
}

fn project_activity_using(
    thread_id: &str,
    state: &ThreadSnapshot,
    previous: Option<&ThreadActivity>,
    admitted: Option<&AdmittedActivity<'_>>,
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
                kind(state, turn_id, attempt, &tasks, admitted)
            })
    };
    let tools = project_tools(state, &tasks, origin.turn_id, kind);
    let associated = associated_attempt(attempt);
    let (summary, summary_truncated) =
        summary(state, associated, origin.turn_id, kind, &tools, admitted);
    let previous_turn = previous.filter(|prev| {
        prev.turn_id.as_deref() == origin.turn_id
            && prev.execution_id.as_deref() == origin.execution_id
    });
    let thinking_summary = match kind {
        ThreadActivityKind::Responding => None,
        _ => latest_thinking_summary(state, associated, admitted).or_else(|| {
            admitted
                .is_none()
                .then(|| previous_turn.and_then(|prev| prev.thinking_summary.clone()))
                .flatten()
        }),
    };
    let thinking_seconds = match kind {
        ThreadActivityKind::Responding => None,
        _ => previous_turn.and_then(|prev| prev.thinking_seconds),
    };
    let step = associated.map_or("preparing", |attempt| attempt.attempt_id.as_str());
    let body = ThreadActivity {
        deferred: Vec::new(),
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

/// Changes to source versions invalidate the activity without retaining another copy of it.
#[cfg(test)]
#[derive(PartialEq, Eq)]
struct ObservedVersions {
    attempt_id: Option<String>,
    model: Option<(u32, u64)>,
    tools: Vec<Option<u64>>,
}

#[cfg(test)]
impl ObservedVersions {
    fn capture(state: &ThreadSnapshot, activity: &ThreadActivity) -> Self {
        let attempt = activity_attempt(state, activity);
        let model = attempt
            .filter(|attempt| attempt.status == AttemptStatus::Running)
            .and_then(|attempt| {
                state
                    .model_progress
                    .as_ref()
                    .filter(|progress| progress.attempt_id == attempt.attempt_id)
            })
            .map(|progress| {
                (
                    progress.progress.observation().generation,
                    progress.progress.version(),
                )
            });
        let tools = activity
            .tools
            .active
            .iter()
            .map(|entry| {
                entry
                    .task_id
                    .as_ref()
                    .and_then(|id| state.tool_progress.get(id))
                    .map(pl_core::model::ToolProgress::version)
            })
            .collect();
        Self {
            attempt_id: attempt.map(|attempt| attempt.attempt_id.clone()),
            model,
            tools,
        }
    }
}

#[cfg(test)]
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

/// 活动的唯一投影 owner 助手。
///
/// 它把当前活动与共享正文来源的推导收敛到一处：只吃 owner 已发布的 `ThreadSnapshot`
/// 与上一条活动，不持有 Session、不 await、不读 SQL、不发帧。观察任务是这份助手的唯一持有者（每个
/// 驻留 Thread 一份），订阅与快照投影调用同一个 [`project_activity`]，因此活动定义只有一处。
///
/// 活动本体是有界 typed 摘要（稳定身份 + 前台 kind + 有界最新逻辑行 + 活跃工具条目），版本覆盖这些
/// 已发布事实及正文的共享进度版本，不按整段正文比较，也不重复保留正文。
#[cfg(test)]
#[derive(Default)]
pub(in crate::studio) struct ActivityProjection {
    previous: Option<ThreadActivity>,
    versions: Option<ObservedVersions>,
    thinking_started_at: Option<ThinkingStartedAt>,
}

#[cfg(test)]
struct ThinkingStartedAt {
    turn_id: Option<String>,
    execution_id: Option<String>,
    attempt_id: Option<String>,
    at: i64,
}

#[cfg(test)]
impl ActivityProjection {
    pub(super) fn current(&self) -> Option<&ThreadActivity> {
        self.previous.as_ref()
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
        self.observe_using(thread_id, state, None, 0)
    }

    fn observe_using(
        &mut self,
        thread_id: &str,
        state: &ThreadSnapshot,
        admitted: Option<&AdmittedActivity<'_>>,
        now: i64,
    ) -> Option<ThreadActivity> {
        let mut activity =
            project_activity_using(thread_id, state, self.previous.as_ref(), admitted);
        if let Some(act) = activity.as_mut() {
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
        let versions = activity
            .as_ref()
            .map(|activity| ObservedVersions::capture(state, activity));
        let source_changed = self.versions != versions;
        self.versions = versions;
        if source_changed
            && let Some(act) = activity.as_mut()
            && let Some(previous) = self.previous.as_ref()
            && previous.identity == act.identity
            && previous.revision == act.revision
        {
            act.revision = previous.revision.saturating_add(1);
        }
        self.previous = activity.clone();
        activity
    }
}

#[cfg(test)]
mod tests;
