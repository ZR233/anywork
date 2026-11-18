//! 用户可见的执行控制命令：精确停止与无内容继续。
//!
//! 两条命令都只做产品侧的身份、权限、模型与工作区校验，然后把请求交给同一个 core 执行器：
//! 停止按执行身份取消，继续受理一条无正文控制输入并认领继续点。回执只表示受理；生效由目标
//! 执行真正结束或新轮次真正准入决定。

use anyhow::Result;

use crate::{
    CommandEffectPoint, ContinuationOperationState, ContinuationOperationView,
    ContinueThreadRequest, ContinueThreadResponse, ResourceStamp, StopThreadRequest,
    StopThreadResponse, StudioError, StudioErrorCode, StudioErrorReason,
};

use crate::studio::ThreadRecord;

use super::super::StudioRuntime;

/// 用户公开入口允许的操作种类，只用于错误文案与原因标签。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio::runtime) enum UserThreadAction {
    /// 提交新内容。
    Submit,
    /// 无内容继续。
    Continue,
    /// 精确停止。
    Stop,
    /// 处理该会话的交互决议。
    Respond,
}

impl UserThreadAction {
    const fn label(self) -> &'static str {
        match self {
            Self::Submit => "send input to",
            Self::Continue => "continue",
            Self::Stop => "stop",
            Self::Respond => "answer",
        }
    }
}

/// Rejects a child Thread reached through a user-facing entry.
///
/// The child's execution belongs to its parent agent: the user may stop it from the agent list, but
/// sending, continuing or answering its questions is the parent's scheduling decision. The check
/// reads the trusted directory association, so hiding a button or spoofing a caller field cannot
/// pass it, and it runs before the owner is activated or attachment drafts are resolved.
pub(in crate::studio::runtime) fn ensure_user_root_target(
    record: &ThreadRecord,
    action: UserThreadAction,
) -> Result<()> {
    if record.parent_thread_id.is_some() {
        // `anyhow::Error::new` keeps the concrete `StudioError` type, which is what the transport
        // mapping downcasts; wrapping it in a `Box` would hide that type from the adapter.
        return Err(anyhow::Error::new(
            StudioError::new(
                StudioErrorCode::PermissionDenied,
                "A child agent is continued and instructed by the main session, not by the user",
                false,
            )
            .with_reason(
                StudioErrorReason::ChildThreadRequiresParentScheduling,
                serde_json::json!({
                    "threadId": record.id,
                    "action": action.label(),
                    "parentThreadId": record.parent_thread_id,
                }),
            ),
        ));
    }
    ensure_thread_not_archived(record, action)
}

/// Rejects an archived Thread for every product entry that would decide, run or stop work in it.
///
/// Archiving is a product state, so the refusal is a typed `Conflict` with its own reason instead of
/// a free-form internal failure: a client can tell "this session is archived" apart from a bug and
/// offer to restore it.
pub(in crate::studio::runtime) fn ensure_thread_not_archived(
    record: &ThreadRecord,
    action: UserThreadAction,
) -> Result<()> {
    if record.visibility == crate::studio::ThreadVisibility::Active {
        return Ok(());
    }
    Err(anyhow::Error::new(
        StudioError::new(
            StudioErrorCode::Conflict,
            "An archived session is read-only; restore it before running or deciding work in it",
            false,
        )
        .with_reason(
            StudioErrorReason::ThreadArchived,
            serde_json::json!({
                "threadId": record.id,
                "action": action.label(),
            }),
        ),
    ))
}

/// Fails closed when a caller's frozen identity is not the one the Thread currently publishes.
fn stale_identity(
    reason: StudioErrorReason,
    message: &'static str,
    extra: serde_json::Value,
) -> anyhow::Error {
    anyhow::Error::new(
        StudioError::new(StudioErrorCode::Conflict, message, false).with_reason(reason, extra),
    )
}

impl StudioRuntime {
    /// Stops exactly the observed execution of a Thread the user may access.
    ///
    /// The target may be the main session or one member of its agent list: both entries name the
    /// execution they observed, so this does not stop whatever happens to run now. Accepting the
    /// stop pauses the queue and forms the continuation point the interruption leaves behind; the
    /// receipt only proves acceptance, so callers observe the execution leaving the canonical
    /// snapshot before treating the stop as effective.
    ///
    /// # Errors
    /// Rejects an archived target, a stale execution identity and a closed owner.
    pub async fn stop_thread(
        &self,
        thread_id: String,
        request: StopThreadRequest,
    ) -> Result<StopThreadResponse> {
        Self::validate_operation_id(&request.operation_id)?;
        let record = self.read_owned_thread(&thread_id).await?;
        ensure_thread_not_archived(&record, UserThreadAction::Stop)?;
        let Some(thread) = self
            .session_of(&thread_id)
            .and_then(|session| session.thread(&thread_id))
        else {
            // A cold Thread owns no execution, so the observed identity cannot be current.
            return Err(stale_identity(
                StudioErrorReason::StaleExecution,
                "The observed execution is no longer current; reload before stopping",
                serde_json::json!({
                    "threadId": thread_id,
                    "expectedExecutionId": request.expected_execution_id,
                }),
            ));
        };
        let stopped = thread
            .interrupt_execution(request.expected_execution_id.clone())
            .await
            .map_err(|error| match error {
                pl_core::thread::ThreadError::InvalidIdentity => stale_identity(
                    StudioErrorReason::StaleExecution,
                    "The observed execution is no longer current; reload before stopping",
                    serde_json::json!({
                        "threadId": thread_id,
                        "expectedExecutionId": request.expected_execution_id,
                    }),
                ),
                error => anyhow::Error::new(error),
            })?;
        let revision = thread.snapshot().commit_sequence;
        let mut receipt = self.command_receipt(
            request.operation_id,
            stopped,
            vec![self.resource_stamp(format!("thread-execution:{thread_id}"), revision)],
            CommandEffectPoint::Immediate,
            false,
        );
        // The cancellation request was accepted; the target execution and its cleanup must still
        // settle before the stop is effective.
        receipt.effective = false;
        receipt.requires_identity_observation = true;
        Ok(StopThreadResponse {
            thread_id,
            execution_id: request.expected_execution_id,
            stopped,
            receipt,
        })
    }

    /// Accepts continuation from the current owner without a persistence acknowledgement.
    pub async fn continue_thread(
        &self,
        thread_id: String,
        request: ContinueThreadRequest,
    ) -> Result<ContinueThreadResponse> {
        Self::validate_operation_id(&request.operation_id)?;
        let _lifecycle = self.lifecycle_lock.lock().await;
        let record = self.read_owned_thread(&thread_id).await?;
        ensure_user_root_target(&record, UserThreadAction::Continue)?;
        let (_, thread, _operation) = self
            .prepare_prompt_admission(
                &thread_id,
                UserThreadAction::Continue,
                &request.operation_id,
            )
            .await?;
        let state = thread.snapshot();
        if let Some(known) = current_continuation_record(&state, &request.operation_id) {
            let view = self.continuation_view(&thread_id, &known)?;
            anyhow::ensure!(
                view.continuation_id == request.expected_continuation_id,
                "operation identity belongs to another continuation"
            );
            return Ok(ContinueThreadResponse {
                thread_id,
                input_id: view.input_id,
                continuation_id: view.continuation_id,
                cursor: view.accepted_sequence,
                receipt: view.receipt,
            });
        }
        if let Some(execution) = state.execution.as_ref() {
            return Err(anyhow::Error::new(
                StudioError::new(StudioErrorCode::Busy,
                    "The Thread is still executing or settling; wait for it to stop before continuing", true)
                .with_reason(StudioErrorReason::ExecutionInProgress, serde_json::json!({
                    "threadId": thread_id, "executionId": execution.id,
                    "phase": format!("{:?}", execution.phase),
                })),
            ));
        }
        check_route_revision(&state, request.expected_model_route_revision)?;
        check_continuation(&thread_id, &state, &request)?;
        let accepted = thread
            .continue_thread(
                request.operation_id.clone(),
                pl_core::thread::input::InputDriverOptions {
                    max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
                },
            )
            .await?;
        self.residency.touch(&thread_id).await;
        let view = self.continuation_view(&thread_id, &accepted)?;
        Ok(ContinueThreadResponse {
            thread_id,
            input_id: view.input_id,
            continuation_id: view.continuation_id,
            cursor: view.accepted_sequence,
            receipt: view.receipt,
        })
    }

    /// Observes only the operation facts retained by the current owner. A missing fact is not
    /// recovered from History and does not prove that an old operation was never accepted.
    pub async fn read_continuation_operation(
        &self,
        thread_id: String,
        operation_id: String,
    ) -> Result<ContinuationOperationView> {
        Self::validate_operation_id(&operation_id)?;
        self.read_owned_thread(&thread_id).await?;
        let known = self
            .session_of(&thread_id)
            .and_then(|session| session.observed_thread(&thread_id))
            .and_then(|thread| current_continuation_record(&thread.snapshot(), &operation_id))
            .ok_or_else(|| StudioError::not_found("current continuation operation"))?;
        self.continuation_view(&thread_id, &known)
    }

    fn continuation_view(
        &self,
        thread_id: &str,
        record: &pl_core::thread::input::InputRecord,
    ) -> Result<ContinuationOperationView> {
        let continuation = record.continuation.as_ref().ok_or_else(|| {
            StudioError::invalid_argument("input is not a continuation operation")
        })?;
        let state = match &record.state {
            pl_core::thread::input::InputState::Pending => ContinuationOperationState::Pending,
            pl_core::thread::input::InputState::Consumed { turn_id, .. } => {
                ContinuationOperationState::Consumed {
                    turn_id: turn_id.clone(),
                }
            }
            pl_core::thread::input::InputState::Discarded => ContinuationOperationState::Discarded,
        };
        let mut receipt = self.command_receipt(
            record.input.id.clone(),
            true,
            vec![
                self.resource_stamp(format!("thread-input:{}", record.input.id), record.revision),
                ResourceStamp {
                    resource_key: format!("thread-continuation:{}", continuation.point_id),
                    owner_epoch: self.owner_epoch().to_owned(),
                    revision: record.accepted_sequence,
                },
            ],
            CommandEffectPoint::Immediate,
            false,
        );
        receipt.effective = false;
        receipt.requires_identity_observation = true;
        Ok(ContinuationOperationView {
            thread_id: thread_id.to_owned(),
            operation_id: record.input.id.clone(),
            input_id: record.input.id.clone(),
            continuation_id: continuation.point_id.clone(),
            accepted_sequence: record.accepted_sequence,
            state,
            receipt,
        })
    }
}

fn current_continuation_record(
    state: &pl_core::thread::ThreadSnapshot,
    operation_id: &str,
) -> Option<pl_core::thread::input::InputRecord> {
    state
        .inputs
        .iter()
        .find(|record| {
            record.input.id == operation_id
                && record.input.purpose == pl_core::thread::input::InputPurpose::Continuation
                && record.continuation.is_some()
        })
        .cloned()
        .or_else(|| {
            state
                .terminal_inputs
                .iter()
                .find(|identity| identity.id == operation_id)
                .and_then(|identity| identity.control_receipt(state.commit_sequence))
        })
}

/// Compares the caller's frozen route revision with the saved route extension.
fn check_route_revision(state: &pl_core::thread::ThreadSnapshot, expected: u64) -> Result<()> {
    let (record, _) = crate::studio::model_route::route_record(state, false)?
        .ok_or_else(|| anyhow::anyhow!("Thread has no saved model route"))?;
    if record.revision != expected {
        return Err(crate::ConfigRuntimeError::StaleRevision {
            expected,
            actual: record.revision,
        }
        .into());
    }
    Ok(())
}

/// Requires the continuation the caller observed to be the one this Thread still owes.
fn check_continuation(
    thread_id: &str,
    state: &pl_core::thread::ThreadSnapshot,
    request: &ContinueThreadRequest,
) -> Result<()> {
    let Some(point) = state.continuation.as_ref() else {
        return Err(stale_identity(
            StudioErrorReason::ContinuationUnavailable,
            "This Thread has no continuation to claim",
            serde_json::json!({
                "threadId": thread_id,
                "expectedContinuationId": request.expected_continuation_id,
            }),
        ));
    };
    if point.id != request.expected_continuation_id {
        return Err(stale_identity(
            StudioErrorReason::StaleContinuation,
            "The observed continuation is no longer current",
            serde_json::json!({
                "threadId": thread_id,
                "expectedContinuationId": request.expected_continuation_id,
                "currentContinuationId": point.id,
            }),
        ));
    }
    if point.claim.is_some() {
        return Err(stale_identity(
            StudioErrorReason::ContinuationClaimed,
            "This continuation was already accepted by another operation",
            serde_json::json!({
                "threadId": thread_id,
                "continuationId": point.id,
            }),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ThreadWorkspaceMode;
    use crate::runtime_test_support as support;
    use anyhow::{Context, ensure};
    use pl_provider_fixture::ReplyStage;

    async fn settled(
        thread: &pl_core::thread::ThreadHandle,
    ) -> Result<pl_core::thread::ThreadSnapshot> {
        let mut updates = thread.subscribe();
        tokio::time::timeout(support::integration_test_deadline()?, async {
            while let Some(snapshot) = updates.next().await {
                if snapshot.execution.is_none()
                    && snapshot.continuation.is_some()
                    && matches!(
                        snapshot.input_execution,
                        pl_core::thread::input::InputExecution::Paused
                    )
                {
                    return Ok(snapshot);
                }
            }
            anyhow::bail!("owner closed before the stopped execution settled")
        })
        .await
        .context("stopped execution did not settle")?
    }

    async fn evict(
        runtime: &StudioRuntime,
        session: &crate::session::SessionRuntime,
        id: &str,
    ) -> Result<()> {
        let thread = session.thread(id).context("owner before idle eviction")?;
        thread.flush().await?;
        runtime.thread_observations.synchronize(Some(id)).await?;
        let evicted = session.evict_idle(id).await?;
        let diagnostic = thread.snapshot();
        ensure!(
            evicted,
            "stopped root was not evicted: inputs={:?}, turns={:?}, tasks={:?}, interactions={:?}, permissions={:?}, inbox={:?}, consumed={}, persistence={:?}, input_execution={:?}, observed={:?}",
            diagnostic.inputs,
            diagnostic.turns,
            diagnostic.tasks,
            diagnostic.interactions,
            diagnostic.permissions,
            diagnostic.inbox,
            diagnostic.consumed_messages,
            diagnostic.persistence,
            diagnostic.input_execution,
            session
                .observed_threads()
                .iter()
                .map(|(id, _)| id)
                .collect::<Vec<_>>()
        );
        ensure!(session.thread(id).is_none(), "root is still resident");
        Ok(())
    }

    fn reason(error: &anyhow::Error) -> Option<&str> {
        error
            .downcast_ref::<StudioError>()
            .and_then(StudioError::reason)
    }

    #[tokio::test]
    async fn continuation_uses_its_owner_and_missing_current_receipt_never_activates() -> Result<()>
    {
        const PROMPT: &str = "continue current work";
        let first = ReplyStage::new();
        let second = ReplyStage::new();
        let env = support::Environment::new(
            vec![
                support::prompt_step(PROMPT, 0, support::held_reply(&first, "first")),
                support::prompt_step(PROMPT, 1, support::held_reply(&second, "continued")),
            ],
            vec![],
        )
        .await?;
        let result = async {
            let started = env.start(ThreadWorkspaceMode::Local, PROMPT).await?;
            let id = started.thread.id;
            support::reached(&first).await?;
            let session = env.runtime.require_session(&id)?;
            let thread = session.thread(&id).context("current owner")?;
            let snapshot = thread.snapshot();
            let route = crate::studio::model_route::route_record(&snapshot, false)?
                .context("route")?
                .0
                .revision;
            env.runtime
                .stop_thread(
                    id.clone(),
                    StopThreadRequest {
                        operation_id: "stop-first".into(),
                        expected_execution_id: snapshot.execution.context("execution")?.id,
                    },
                )
                .await?;
            let point = settled(&thread)
                .await?
                .continuation
                .context("continuation")?
                .id;
            first.release();
            let request = ContinueThreadRequest {
                operation_id: "current-continue".into(),
                expected_continuation_id: point.clone(),
                expected_model_route_revision: route,
            };
            let accepted = env
                .runtime
                .continue_thread(id.clone(), request.clone())
                .await?;
            support::reached(&second).await?;
            let repeated = env.runtime.continue_thread(id.clone(), request).await?;
            ensure!(
                repeated.input_id == accepted.input_id && repeated.continuation_id == point,
                "repeat changed the current input identity"
            );
            env.runtime
                .stop_thread(
                    id.clone(),
                    StopThreadRequest {
                        operation_id: "stop-second".into(),
                        expected_execution_id: thread
                            .snapshot()
                            .execution
                            .context("continued execution")?
                            .id,
                    },
                )
                .await?;
            settled(&thread).await?;
            second.release();
            evict(&env.runtime, &session, &id).await?;
            let error = env
                .runtime
                .read_continuation_operation(id.clone(), accepted.input_id)
                .await
                .unwrap_err();
            ensure!(
                error
                    .downcast_ref::<StudioError>()
                    .is_some_and(|error| error.code == StudioErrorCode::NotFound),
                "unexpected missing current receipt: {error:#}"
            );
            ensure!(
                session.thread(&id).is_none(),
                "receipt query activated a cold owner"
            );
            ensure!(
                env.root_provider.recorded().len() == 2,
                "receipt lookup dispatched new model work"
            );
            Ok(())
        }
        .await;
        first.release();
        second.release();
        env.finish(result).await
    }

    #[tokio::test]
    async fn cancelled_waiter_and_session_close_settle_cold_preparation() -> Result<()> {
        const PROMPT: &str = "prepare a stopped session";
        for close_during_preparation in [false, true] {
            let stage = ReplyStage::new();
            let env = support::Environment::new(
                vec![support::prompt_step(
                    PROMPT,
                    0,
                    support::held_reply(&stage, "initial"),
                )],
                vec![],
            )
            .await?;
            let result = async {
                let id = env.start(ThreadWorkspaceMode::Local, PROMPT).await?.thread.id;
                support::reached(&stage).await?;
                let session = env.runtime.require_session(&id)?;
                let thread = session.thread(&id).context("initial owner")?;
                let snapshot = thread.snapshot();
                let execution = snapshot.execution.as_ref().context("initial execution")?.id.clone();
                let route = crate::studio::model_route::route_record(&snapshot, false)?
                    .context("saved route")?.0.revision;
                env.runtime.stop_thread(id.clone(), StopThreadRequest {
                    operation_id: "stop-for-preparation".into(),
                    expected_execution_id: execution,
                }).await?;
                let point = settled(&thread).await?.continuation.context("continuation")?.id;
                stage.release();
                evict(&env.runtime, &session, &id).await?;
                ensure!(!session.hosts(&id), "eviction left a preparation or owner");

                // The real assembler task cannot pass this permit until the test releases it.
                // Registration is observed through the same session that owns preparation.
                let permit = session.agent_operation(&id).await;
                let runtime = env.runtime.clone();
                let requested_id = id.clone();
                let expected_point = point.clone();
                let mut caller = tokio::spawn(async move {
                    runtime.continue_thread(requested_id, ContinueThreadRequest {
                        operation_id: "cancelled-continue".into(),
                        expected_continuation_id: expected_point,
                        expected_model_route_revision: route,
                    }).await
                });
                tokio::time::timeout(support::integration_test_deadline()?, async {
                    tokio::select! {
                        () = session.wait_for_registered_activation(&id) => Ok(()),
                        result = &mut caller => anyhow::bail!("continuation returned before registration: {result:?}"),
                    }
                }).await.context("activation was not registered")??;
                ensure!(session.hosts(&id), "continuation returned before registering preparation");
                if close_during_preparation {
                    let closing_session = session.clone();
                    let (closing, observed) = tokio::sync::oneshot::channel();
                    let close = tokio::spawn(async move {
                        let completion = closing_session.close_session();
                        tokio::pin!(completion);
                        let first = futures::poll!(completion.as_mut());
                        let _ = closing.send(());
                        match first {
                            std::task::Poll::Ready(report) => report,
                            std::task::Poll::Pending => completion.await,
                        }
                    });
                    tokio::time::timeout(support::integration_test_deadline()?, observed)
                        .await.context("session close did not seal admission")??;
                    ensure!(session.phase() != crate::session::SessionPhase::Open, "session remained open");
                    drop(permit);
                    ensure!(caller.await?.is_err(), "closed session accepted a continuation");
                    let report = close.await?;
                    ensure!(report.is_empty(), "session close failed: {report:?}");
                    ensure!(session.thread(&id).is_none() && !session.hosts(&id), "closed session retained a late owner");
                    ensure!(session.ensure_agent_admission_open(&id).is_err(), "closed incarnation admitted work");
                } else {
                    caller.abort();
                    ensure!(caller.await.unwrap_err().is_cancelled(), "caller was not cancelled");
                    ensure!(session.hosts(&id), "cancellation discarded the preparation owner");
                    drop(permit);
                    let restored = tokio::time::timeout(
                        support::integration_test_deadline()?,
                        env.runtime.ensure_thread_owner(&id),
                    ).await.context("owned preparation did not finish")??;
                    ensure!(session.thread(&id).is_some_and(|current| current.same_instance(&restored)), "preparation published outside the original session");
                    ensure!(restored.snapshot().continuation.as_ref().is_some_and(|current| current.id == point), "caller cancellation lost the saved continuation");
                    let permit = session.agent_operation(&id).await;
                    ensure!(env.runtime.validate_prompt_owner(&id, &session, &thread).is_err(), "retired incarnation was admitted");
                    env.runtime.validate_prompt_owner(&id, &session, &restored)?;
                    drop(permit);
                    ensure!(env.root_provider.recorded().len() == 1, "cancelled caller admitted model work");
                    env.runtime.archive_thread("archive-after-cancel".into(), id.clone()).await?;
                    let error = env.runtime.continue_thread(id.clone(), ContinueThreadRequest {
                        operation_id: "after-archive".into(),
                        expected_continuation_id: point,
                        expected_model_route_revision: route,
                    }).await.unwrap_err();
                    ensure!(reason(&error) == Some("threadArchived"), "archived root accepted work: {error:#}");
                }
                Ok(())
            }.await;
            stage.release();
            env.finish(result).await?;
        }
        Ok(())
    }
}
