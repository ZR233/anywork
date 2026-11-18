//! 用户可见的执行控制命令：精确停止与无内容继续。
//!
//! 两条命令都只做产品侧的身份、权限、模型与工作区校验，然后把请求交给同一个 core 执行器：
//! 停止按执行身份取消，继续消费一次性 token 并预约新执行。回执只表示受理；生效由目标
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

    /// Resume is accepted in RAM; repeated requests read the original bounded owner receipt.
    pub async fn continue_thread(
        &self,
        thread_id: String,
        request: ContinueThreadRequest,
    ) -> Result<ContinueThreadResponse> {
        Self::validate_operation_id(&request.operation_id)?;
        let record = self.read_owned_thread(&thread_id).await?;
        ensure_user_root_target(&record, UserThreadAction::Continue)?;
        let core_request = pl_core::thread::ResumeRequest {
            operation_id: request.operation_id.clone(),
            expected_continuation_token: request.expected_continuation_token.clone(),
            request_digest: Some(resume_request_digest(
                &thread_id,
                &request.expected_continuation_token,
                request.expected_model_route_revision,
            )),
        };
        if let Some(thread) = self
            .session_of(&thread_id)
            .and_then(|session| session.thread(&thread_id))
            && let pl_core::thread::ContinuationRead::Known(operation) = thread
                .read_resume(core_request.clone())
                .await
                .map_err(control_error)?
        {
            return Ok(self.continue_response(thread_id, operation));
        }
        let lifecycle_guard = self.lifecycle_lock.lock().await;
        let (_, thread, agent_operation) = self
            .prepare_prompt_admission(
                &thread_id,
                UserThreadAction::Continue,
                &request.operation_id,
            )
            .await?;
        // Activation precedes the per-agent operation permit. Recheck after acquiring that permit.
        if let pl_core::thread::ContinuationRead::Known(operation) = thread
            .read_resume(core_request.clone())
            .await
            .map_err(control_error)?
        {
            return Ok(self.continue_response(thread_id, operation));
        }
        check_route_revision(&thread.snapshot(), request.expected_model_route_revision)?;
        let operation = thread
            .resume_execution(
                core_request,
                pl_core::thread::input::InputDriverOptions {
                    max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
                },
            )
            .await
            .map_err(control_error)?;
        drop(agent_operation);
        drop(lifecycle_guard);
        self.residency.touch(&thread_id).await;
        Ok(self.continue_response(thread_id, operation))
    }

    fn continuation_receipt(
        &self,
        thread_id: &str,
        operation: &pl_core::thread::ContinuationOperation,
    ) -> crate::StudioCommandReceipt {
        let mut receipt = self.command_receipt(
            operation.request.operation_id.clone(),
            true,
            vec![ResourceStamp {
                resource_key: format!("thread-execution:{thread_id}"),
                owner_epoch: operation.acceptance_epoch.to_string(),
                revision: operation.accepted_revision,
            }],
            CommandEffectPoint::Immediate,
            false,
        );
        receipt.effective = false;
        receipt.requires_identity_observation = true;
        receipt
    }

    fn continue_response(
        &self,
        thread_id: String,
        operation: pl_core::thread::ContinuationOperation,
    ) -> ContinueThreadResponse {
        let receipt = self.continuation_receipt(&thread_id, &operation);
        ContinueThreadResponse {
            thread_id,
            input_id: operation.request.operation_id,
            continuation_id: operation.request.expected_continuation_token,
            cursor: operation.accepted_revision,
            receipt,
        }
    }

    pub async fn read_continuation_operation(
        &self,
        thread_id: String,
        operation_id: String,
        expected_continuation_token: String,
    ) -> Result<ContinuationOperationView> {
        Self::validate_operation_id(&operation_id)?;
        self.read_owned_thread(&thread_id).await?;
        // Read-only lookup never activates a cold owner and never consults History for deduplication.
        let thread = self
            .session_of(&thread_id)
            .and_then(|session| session.thread(&thread_id))
            .ok_or_else(|| control_error(pl_core::thread::ThreadError::StaleContinuation))?;
        let request = pl_core::thread::ResumeRequest {
            operation_id: operation_id.clone(),
            expected_continuation_token: expected_continuation_token.clone(),
            request_digest: None,
        };
        match thread.read_resume(request).await.map_err(control_error)? {
            pl_core::thread::ContinuationRead::NotAccepted => Ok(ContinuationOperationView {
                thread_id,
                operation_id,
                expected_continuation_token,
                state: ContinuationOperationState::NotAccepted,
                acceptance_epoch: None,
                execution_id: None,
                turn_id: None,
                accepted_revision: None,
                disposition: None,
                receipt: None,
            }),
            pl_core::thread::ContinuationRead::Known(operation) => {
                let receipt = self.continuation_receipt(&thread_id, &operation);
                let disposition = match operation.disposition {
                    pl_core::thread::ContinuationDisposition::Scheduled => {
                        crate::ContinuationDisposition::Scheduled
                    }
                    pl_core::thread::ContinuationDisposition::Effective => {
                        crate::ContinuationDisposition::Effective
                    }
                    pl_core::thread::ContinuationDisposition::NotExecuted(reason) => {
                        crate::ContinuationDisposition::NotExecuted(format!("{reason:?}"))
                    }
                };
                Ok(ContinuationOperationView {
                    thread_id,
                    operation_id,
                    expected_continuation_token,
                    state: ContinuationOperationState::Known,
                    acceptance_epoch: Some(operation.acceptance_epoch.to_string()),
                    execution_id: Some(operation.execution_id),
                    turn_id: Some(operation.turn_id),
                    accepted_revision: Some(operation.accepted_revision),
                    disposition: Some(disposition),
                    receipt: Some(receipt),
                })
            }
        }
    }
}

/// Freeze the caller's route CAS in the bounded RAM receipt; no persisted identity is consulted.
fn resume_request_digest(thread_id: &str, token: &str, route_revision: u64) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(b"pl.studio.continuation-request\0");
    hasher.update(thread_id.as_bytes());
    hasher.update([0]);
    hasher.update(b"continuation");
    hasher.update([0]);
    hasher.update(token.as_bytes());
    hasher.update([0]);
    hasher.update(route_revision.to_le_bytes());
    format!("sha256:{}", hex::encode(hasher.finalize()))
}

fn control_error(error: pl_core::thread::ThreadError) -> anyhow::Error {
    match error {
        pl_core::thread::ThreadError::StaleContinuation => stale_identity(
            StudioErrorReason::StaleContinuation,
            "The continuation token is no longer current",
            serde_json::json!({}),
        ),
        pl_core::thread::ThreadError::InvalidIdentity => anyhow::Error::new(StudioError::new(
            StudioErrorCode::Conflict,
            "Resume operation identity conflicts with its original request",
            false,
        )),
        error => anyhow::Error::new(error),
    }
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
    async fn cold_activation_refreshes_resume_token_and_live_replay_preserves_its_receipt()
    -> Result<()> {
        const PROMPT: &str = "continue the interrupted work";
        let first = ReplyStage::new();
        let second = ReplyStage::new();
        let third = ReplyStage::new();
        let env = support::Environment::new(
            vec![
                support::prompt_step(PROMPT, 0, support::held_reply(&first, "first")),
                support::prompt_step(PROMPT, 1, support::held_reply(&second, "continued")),
                support::prompt_step(PROMPT, 2, support::held_reply(&third, "hot-continued")),
            ],
            vec![],
        )
        .await?;
        let result = async {
            let started = env.start(ThreadWorkspaceMode::Local, PROMPT).await?;
            let id = started.thread.id;
            support::reached(&first).await?;
            let session = env.runtime.require_session(&id)?;
            let thread = session.thread(&id).context("initial owner")?;
            let snapshot = thread.snapshot();
            let execution = snapshot
                .execution
                .as_ref()
                .context("initial execution")?
                .id
                .clone();
            let route = crate::studio::model_route::route_record(&snapshot, false)?
                .context("saved route")?
                .0
                .revision;
            thread.flush().await?;
            env.runtime
                .thread_observations
                .synchronize(Some(&id))
                .await?;
            let running_request = ContinueThreadRequest {
                operation_id: "running".into(),
                expected_continuation_token: "not-yet".into(),
                expected_model_route_revision: route,
            };
            let error = env
                .runtime
                .continue_thread(id.clone(), running_request)
                .await
                .unwrap_err();
            ensure!(
                reason(&error) == Some("staleContinuation"),
                "unexpected running error: {error:#}"
            );
            env.runtime
                .stop_thread(
                    id.clone(),
                    StopThreadRequest {
                        operation_id: "stop-first".into(),
                        expected_execution_id: execution,
                    },
                )
                .await?;
            let stopped = settled(&thread).await?;
            first.release();
            thread.flush().await?;
            env.runtime
                .thread_observations
                .synchronize(Some(&id))
                .await?;
            let point = stopped.continuation.context("stopped continuation")?.id;
            let mut request = ContinueThreadRequest {
                operation_id: "continue-once".into(),
                expected_continuation_token: point,
                expected_model_route_revision: route,
            };
            let stale = ContinueThreadRequest {
                operation_id: "stale".into(),
                expected_continuation_token: "obsolete-point".into(),
                ..request.clone()
            };
            let error = env
                .runtime
                .continue_thread(id.clone(), stale.clone())
                .await
                .unwrap_err();
            ensure!(
                reason(&error) == Some("staleContinuation"),
                "unexpected hot stale error: {error:#}"
            );
            let wrong_route = ContinueThreadRequest {
                operation_id: "wrong-route".into(),
                expected_model_route_revision: route + 1,
                ..request.clone()
            };
            let error = env
                .runtime
                .continue_thread(id.clone(), wrong_route)
                .await
                .unwrap_err();
            ensure!(
                error.downcast_ref::<crate::ConfigRuntimeError>().is_some(),
                "unexpected route error: {error:#}"
            );
            evict(&env.runtime, &session, &id).await?;
            let error = tokio::time::timeout(
                support::integration_test_deadline()?,
                env.runtime.continue_thread(id.clone(), stale),
            )
            .await
            .context("cold stale continuation did not return")?
            .unwrap_err();
            ensure!(
                reason(&error) == Some("staleContinuation"),
                "unexpected cold stale error: {error:#}"
            );
            let restored = session
                .thread(&id)
                .context("cold activation retained its owner")?;
            let fresh = restored
                .snapshot()
                .continuation
                .context("fresh continuation")?
                .id;
            ensure!(
                fresh != request.expected_continuation_token,
                "cold activation reused an old token"
            );
            request.expected_continuation_token = fresh;
            let accepted = tokio::time::timeout(
                support::integration_test_deadline()?,
                env.runtime.continue_thread(id.clone(), request.clone()),
            )
            .await
            .context("cold continuation did not return")??;
            support::reached(&second).await?;
            let resumed = session.thread(&id).context("resumed owner")?;
            let execution = resumed
                .snapshot()
                .execution
                .context("continued execution")?
                .id;
            let replay = env
                .runtime
                .continue_thread(id.clone(), request.clone())
                .await?;
            ensure!(replay == accepted, "repeat changed the original receipt");
            env.runtime
                .stop_thread(
                    id.clone(),
                    StopThreadRequest {
                        operation_id: "stop-second".into(),
                        expected_execution_id: execution,
                    },
                )
                .await?;
            let stopped_again = settled(&resumed).await?;
            second.release();
            resumed.flush().await?;
            env.runtime
                .thread_observations
                .synchronize(Some(&id))
                .await?;
            let hot_request = ContinueThreadRequest {
                operation_id: "continue-hot".into(),
                expected_continuation_token: stopped_again
                    .continuation
                    .context("second continuation")?
                    .id,
                expected_model_route_revision: route,
            };
            env.runtime.continue_thread(id.clone(), hot_request).await?;
            support::reached(&third).await?;
            let execution = resumed.snapshot().execution.context("hot execution")?.id;
            env.runtime
                .stop_thread(
                    id.clone(),
                    StopThreadRequest {
                        operation_id: "stop-third".into(),
                        expected_execution_id: execution,
                    },
                )
                .await?;
            settled(&resumed).await?;
            third.release();
            evict(&env.runtime, &session, &id).await?;
            let moved_repo = env.repo.with_file_name("temporarily-unavailable-repo");
            std::fs::rename(&env.repo, &moved_repo)
                .context("hide the workspace for cold receipt replay")?;
            let stale_read = env
                .runtime
                .read_continuation_operation(
                    id.clone(),
                    request.operation_id,
                    request.expected_continuation_token,
                )
                .await
                .unwrap_err();
            ensure!(
                reason(&stale_read) == Some("staleContinuation"),
                "cold read fabricated a replay: {stale_read:#}"
            );
            std::fs::rename(&moved_repo, &env.repo)
                .context("restore the workspace after cold receipt replay")?;
            ensure!(
                session.thread(&id).is_none(),
                "read-only feedback lookup materialized a cold owner"
            );
            ensure!(
                env.root_provider.recorded().len() == 3,
                "repeat started another model request"
            );
            Ok(())
        }
        .await;
        first.release();
        second.release();
        third.release();
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
                        expected_continuation_token: expected_point,
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
                    ensure!(restored.snapshot().continuation.as_ref().is_some_and(|current| !current.id.is_empty() && current.id != point), "cold activation must retain owed work under a fresh token");
                    let permit = session.agent_operation(&id).await;
                    ensure!(env.runtime.validate_prompt_owner(&id, &session, &thread).is_err(), "retired incarnation was admitted");
                    env.runtime.validate_prompt_owner(&id, &session, &restored)?;
                    drop(permit);
                    ensure!(env.root_provider.recorded().len() == 1, "cancelled caller admitted model work");
                    env.runtime.archive_thread("archive-after-cancel".into(), id.clone()).await?;
                    let error = env.runtime.continue_thread(id.clone(), ContinueThreadRequest {
                        operation_id: "after-archive".into(),
                        expected_continuation_token: point,
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
