//! 用户可见的执行控制命令：精确停止与无内容继续。
//!
//! 两条命令都只做产品侧的身份、权限、模型与工作区校验，然后把请求交给同一个 core 执行器：
//! 停止按执行身份取消，继续受理一条无正文控制输入并认领继续点。回执只表示受理；生效由目标
//! 执行真正结束或新轮次真正准入决定。

use anyhow::Result;

use pl_protocol::studio::{
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
        let Some(thread) = self.threads.thread(&thread_id) else {
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

    /// Continues the main session without new user content.
    ///
    /// The operation identity is the control input's own identity, so a repeat answers with the
    /// original receipt instead of claiming the point twice, and a repeat never clears a stop the
    /// user issued afterwards. The control input carries no user text: the work that is owed stays
    /// the same session, the old Turn keeps its history and a new Turn starts from saved context.
    ///
    /// # Errors
    /// Rejects a child target, an archived Thread, a stale continuation or route revision, a pending
    /// interaction, storage pressure and a Thread that owes no work.
    pub async fn continue_thread(
        &self,
        thread_id: String,
        request: ContinueThreadRequest,
    ) -> Result<ContinueThreadResponse> {
        Self::validate_operation_id(&request.operation_id)?;
        let lifecycle_guard = self.lifecycle_lock.lock().await;
        let thread_record = self.read_owned_thread(&thread_id).await?;
        // A child target is refused from the trusted association before any owner is activated.
        ensure_user_root_target(&thread_record, UserThreadAction::Continue)?;
        // What this caller froze: the operation identity plus the two facts that must match a repeat.
        let identity = ContinuationIdentity {
            operation_id: &request.operation_id,
            expected_continuation_id: Some(&request.expected_continuation_id),
            expected_model_route_revision: Some(request.expected_model_route_revision),
        };
        // A repeat answers the original admission before any new validation: it is not new work, so
        // a later stop, a later route change or a claimed point cannot turn it into a conflict.
        // This site holds the lifecycle lock, so an admission that is resident but not yet durable
        // answers the retryable Busy instead of waiting while it would block other lifecycle work.
        if let Some(view) = self.replayable_continuation(&thread_id, &identity).await? {
            return Ok(ContinueThreadResponse {
                thread_id,
                input_id: view.input_id,
                continuation_id: view.continuation_id,
                cursor: view.accepted_sequence,
                receipt: view.receipt,
            });
        }
        let agent_operation = self.threads.agent_operation(&thread_id).await;
        self.threads.ensure_agent_admission_open(&thread_id)?;
        self.ensure_prompt_runtime_ready().await?;
        let thread = self.ensure_thread_owner(&thread_id).await?;
        // An explicit continuation is also where a main session repairs the decision notices it may
        // not have consumed yet. A failure is reported to the caller instead of being swallowed; the
        // continuation itself has not been admitted yet, so retrying is safe.
        self.reconcile_child_interaction_notices(&thread_id).await?;
        // Re-check the durable receipt now that the owner is resident: admission may have landed
        // while this command was activating, and the queue would then hold the identity already.
        if let Some(view) = self.replayable_continuation(&thread_id, &identity).await? {
            return Ok(ContinueThreadResponse {
                thread_id,
                input_id: view.input_id,
                continuation_id: view.continuation_id,
                cursor: view.accepted_sequence,
                receipt: view.receipt,
            });
        }
        let state = thread.snapshot();
        // The qualification order is fixed: a current execution or its cleanup comes before the
        // continuation point, so a stop that is still settling never starts a new Turn.
        if let Some(execution) = state.execution.as_ref() {
            return Err(anyhow::Error::new(
                StudioError::new(
                    StudioErrorCode::Busy,
                    "The Thread is still executing or settling; wait for it to stop before continuing",
                    true,
                )
                .with_reason(
                    StudioErrorReason::ExecutionInProgress,
                    serde_json::json!({
                        "threadId": thread_id,
                        "executionId": execution.id,
                        "phase": format!("{:?}", execution.phase),
                    }),
                ),
            ));
        }
        // The caller's frozen route is a CAS against the saved route extension, exactly like an
        // explicit submission: a stale selector must not continue with a model never observed.
        check_route_revision(&state, request.expected_model_route_revision)?;
        check_continuation(&thread_id, &state, &request)?;
        let driver = pl_core::thread::input::InputDriverOptions {
            // A continued main session keeps its existing unlimited main-session policy.
            max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
        };
        thread
            .continue_thread(request.operation_id.clone(), driver)
            .await
            .map_err(|error| match error {
                pl_core::thread::ThreadError::NoContinuation => stale_identity(
                    StudioErrorReason::ContinuationUnavailable,
                    "This Thread has no continuation to claim",
                    serde_json::json!({
                        "threadId": thread_id,
                        "expectedContinuationId": request.expected_continuation_id,
                    }),
                ),
                pl_core::thread::ThreadError::InvalidControlInput => anyhow::Error::new(
                    StudioError::invalid_argument("continuation control input carries content"),
                ),
                error => anyhow::Error::new(error),
            })?;
        self.residency.touch(&thread_id).await;
        // The admission already happened under the lifecycle lock, so a stop, close or archive that
        // arrives from here on is its own later fact and must not be delayed by this wait. Both the
        // lifecycle lock and the per-Thread operation guard were only needed up to the admission, and
        // the archive takes them in that order — lifecycle admission first, then the same per-Thread
        // guard (`run_archive` → `archive_thread_owned`) — so keeping either one alive through the
        // durability wait would let this command block closing for the whole wait.
        drop(lifecycle_guard);
        drop(agent_operation);
        // The admission is only a receipt once its identity is a durable fact: the history row is the
        // single place a repeat (or a reopened process) rebuilds the same receipt from. Until that row
        // lands this command reports a retryable condition instead of returning a receipt no
        // canonical fact could reproduce.
        let view = self
            .await_accepted_continuation(&thread_id, &identity)
            .await?;
        Ok(ContinueThreadResponse {
            thread_id,
            input_id: view.input_id,
            continuation_id: view.continuation_id,
            cursor: view.accepted_sequence,
            receipt: view.receipt,
        })
    }

    /// Waits for the accepted operation to reach the durable identity index, then reads it back.
    ///
    /// The index row is written by the same commit that admits the control input, so this is a
    /// bounded wait on an already-committed fact — not a second source of truth. A caller whose
    /// request is cancelled during the wait loses nothing: the admission stands and the same
    /// operation identity reads the same receipt afterwards.
    async fn await_accepted_continuation(
        &self,
        thread_id: &str,
        identity: &ContinuationIdentity<'_>,
    ) -> Result<ContinuationOperationView> {
        let deadline = tokio::time::Instant::now() + ACCEPTED_IDENTITY_WAIT;
        loop {
            // The read itself is bounded by the remaining budget: a slow database must not extend the
            // wait past the deadline.
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            if remaining.is_zero() {
                return self.accepted_identity_pending(thread_id, identity);
            }
            match tokio::time::timeout(
                remaining,
                self.read_continuation_operation_view(thread_id, identity),
            )
            .await
            {
                Ok(found) => {
                    match found {
                        Ok(Some(view)) => return Ok(view),
                        // The admission is resident but its durable row is not readable yet: the
                        // answer may land inside this budget, so keep polling instead of answering a
                        // retryable Busy the caller did not have to receive.
                        Err(error) if error.downcast_ref::<AcceptedIdentityPending>().is_some() => {
                        }
                        // Any other failure is a real one and is propagated immediately.
                        Err(error) => return Err(error),
                        Ok(None) => {}
                    }
                }
                Err(_) => return self.accepted_identity_pending(thread_id, identity),
            }
            // The poll wait is bounded by the same budget: a sleep that always ran its full interval
            // would return past the deadline the caller was promised.
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            if !remaining.is_zero() {
                tokio::time::sleep(ACCEPTED_IDENTITY_POLL.min(remaining)).await;
            }
        }
    }

    /// The retryable answer for "accepted, but its receipt is not durable yet".
    fn accepted_identity_pending(
        &self,
        thread_id: &str,
        identity: &ContinuationIdentity<'_>,
    ) -> Result<ContinuationOperationView> {
        Err(Self::accepted_identity_pending_error(thread_id, identity))
    }

    /// The same retryable answer for callers that are not returning a receipt value.
    ///
    /// The internal pending marker never leaves a public command: a repeat during the
    /// "admitted but not yet durable" window answers the documented retryable Busy instead.
    fn accepted_identity_pending_error(
        thread_id: &str,
        identity: &ContinuationIdentity<'_>,
    ) -> anyhow::Error {
        anyhow::Error::new(
            StudioError::new(
                StudioErrorCode::Busy,
                "The continuation was accepted but its receipt is not durable yet; retry the same operation",
                true,
            )
            .with_reason(
                StudioErrorReason::ContinuationUnavailable,
                serde_json::json!({
                    "threadId": thread_id,
                    "operationId": identity.operation_id,
                    "accepted": true,
                }),
            ),
        )
    }

    /// Reads one continuation operation without activating the Thread.
    ///
    /// The resident owner answers from its admitted input facts; a Thread with no owner answers from
    /// the durable history identity index, so a receipt that was saved before the response was lost
    /// is still readable after a restart. A query never re-authorises execution and never clears a
    /// later stop; it also stays readable for an archived Thread, because reading a fact is not
    /// deciding, continuing or stopping work in it.
    ///
    /// # Errors
    /// Rejects an unknown Thread and an operation identity that carries no accepted continuation.
    pub async fn read_continuation_operation(
        &self,
        thread_id: String,
        operation_id: String,
    ) -> Result<ContinuationOperationView> {
        Self::validate_operation_id(&operation_id)?;
        self.read_owned_thread(&thread_id).await?;
        let identity = ContinuationIdentity {
            operation_id: &operation_id,
            // A read-only query names nothing to compare: it reports the accepted facts as they are.
            expected_continuation_id: None,
            expected_model_route_revision: None,
        };
        let view = match self
            .read_continuation_operation_view(&thread_id, &identity)
            .await
        {
            Ok(view) => view,
            // A query has no budget to wait in, so the internal "row not readable yet" marker becomes
            // the same public retryable answer the command returns.
            Err(error) if error.downcast_ref::<AcceptedIdentityPending>().is_some() => {
                return self.accepted_identity_pending(&thread_id, &identity);
            }
            Err(error) => return Err(error),
        };
        view.ok_or_else(|| {
            anyhow::Error::new(
                StudioError::new(
                    StudioErrorCode::NotFound,
                    "No accepted continuation operation carries this identity",
                    false,
                )
                .with_details(
                    serde_json::json!({ "threadId": thread_id, "operationId": operation_id }),
                ),
            )
        })
    }

    /// One projection shared by the command repeat check and the read-only query.
    ///
    /// The durable identity index is consulted first, because it is the only place that carries the
    /// *frozen* request identity (continuation point, route revision and admission revision). The
    /// resident queue is only a fallback for the short window before the admission commit is saved;
    /// it is never treated as a different kind of receipt.
    /// Answers a repeat of an already accepted continuation without leaking the internal marker.
    ///
    /// While the admission is resident but its identity row is not durable yet, the honest public
    /// answer is the documented retryable Busy: the same operation identity reads the same receipt
    /// once that row lands, so nothing is re-authorised and nothing is lost.
    async fn replayable_continuation(
        &self,
        thread_id: &str,
        identity: &ContinuationIdentity<'_>,
    ) -> Result<Option<ContinuationOperationView>> {
        match self
            .read_continuation_operation_view(thread_id, identity)
            .await
        {
            Ok(found) => Ok(found),
            Err(error) if error.downcast_ref::<AcceptedIdentityPending>().is_some() => {
                Err(Self::accepted_identity_pending_error(thread_id, identity))
            }
            Err(error) => Err(error),
        }
    }

    async fn read_continuation_operation_view(
        &self,
        thread_id: &str,
        request: &ContinuationIdentity<'_>,
    ) -> Result<Option<ContinuationOperationView>> {
        // A storage fault or an unreached durable fence is propagated: only a reliable "no durable
        // record" answer may fall through to the resident facts or become NotFound.
        let history = self.read_timeline_history(thread_id).await?;
        if let Some(previous) = history.input_identity(request.operation_id).await? {
            // A normal message identity under the same id is not a continuation operation, and it is
            // never answered as one.
            if previous.entry.purpose != pl_core::thread::input::InputPurpose::Continuation {
                return Ok(None);
            }
            let stored_digest = previous.request_digest.clone();
            return Ok(Some(self.continuation_view(
                thread_id,
                ContinuationFacts {
                    input_id: previous.entry.id.clone(),
                    continuation: previous.entry.continuation.as_ref(),
                    accepted_sequence: previous.entry.accepted_sequence,
                    state: &previous.entry.state,
                    expected_model_route_revision: previous.entry.expected_model_route_revision,
                    admission_revision: previous.entry.continuation_admission_revision,
                    stored_digest: stored_digest.as_deref(),
                    durable: true,
                },
                request,
            )?));
        }
        let Some(thread) = self.threads.thread(thread_id) else {
            return Ok(None);
        };
        let snapshot = thread.snapshot();
        let Some(record) = snapshot
            .inputs
            .iter()
            .find(|record| record.input.id == request.operation_id)
        else {
            return Ok(None);
        };
        // The resident queue also has to prove the purpose: a pending normal message with the same
        // identity must never be replayed as a continuation receipt.
        if record.input.purpose != pl_core::thread::input::InputPurpose::Continuation {
            return Ok(None);
        }
        // The resident queue can only prove that the admission happened, not the frozen identity it
        // was accepted with: that lives in the durable row written by the admission commit. An
        // identity whose row is still missing is therefore a retryable condition — never a
        // conflicting request, and never a receipt no canonical fact could reproduce. It is reported
        // as an internal marker so the post-admission wait keeps polling for the row instead of
        // aborting on a condition that usually clears within milliseconds.
        Err(anyhow::Error::new(AcceptedIdentityPending))
    }

    fn continuation_view(
        &self,
        thread_id: &str,
        facts: ContinuationFacts<'_>,
        request: &ContinuationIdentity<'_>,
    ) -> Result<ContinuationOperationView> {
        let Some(continuation) = facts.continuation else {
            return Err(anyhow::Error::new(StudioError::invalid_argument(
                "input identity is not a continuation operation",
            )));
        };
        // Same operation identity with a different frozen continuation or a different frozen route
        // revision is a conflicting request, not a receipt: answering it would claim work the caller
        // never observed. A genuine repeat carries the same frozen facts, so it still gets the
        // original receipt before any route staleness check.
        ensure_accepted_continuation(
            thread_id,
            request,
            &continuation.point_id,
            facts.expected_model_route_revision,
        )?;
        // The durable request digest is the accepted request identity itself; a stored digest that no
        // longer matches the frozen facts means the row does not describe this operation.
        if let (Some(route_revision), Some(point_id), Some(accepted_digest)) = (
            request.expected_model_route_revision,
            request.expected_continuation_id,
            facts.stored_digest,
        ) {
            let recomputed = crate::studio::thread_projection::continuation_request_digest(
                thread_id,
                point_id,
                Some(route_revision),
            );
            if recomputed != accepted_digest {
                return Err(stale_identity(
                    StudioErrorReason::StaleContinuation,
                    "The accepted request identity does not match this operation",
                    serde_json::json!({
                        "threadId": thread_id,
                        "operationId": request.operation_id,
                    }),
                ));
            }
        }
        let state = match facts.state {
            pl_core::thread::input::InputState::Pending => ContinuationOperationState::Pending,
            pl_core::thread::input::InputState::Consumed { turn_id, .. } => {
                ContinuationOperationState::Consumed {
                    turn_id: turn_id.clone(),
                }
            }
            pl_core::thread::input::InputState::Discarded => ContinuationOperationState::Discarded,
        };
        // The receipt is rebuilt from the same canonical facts the first admission used: the control
        // input stamp at its admission revision, the continuation stamp at the accepted sequence, and
        // the "not yet effective / not yet durable" flags the admission really had. `durable` on the
        // view describes where this read came from and never rewrites the receipt.
        let admission_revision = facts
            .admission_revision
            .unwrap_or(ADMISSION_REVISION_FALLBACK);
        let mut receipt = self.command_receipt(
            request.operation_id.to_owned(),
            true,
            vec![
                self.resource_stamp(
                    format!("thread-input:{}", facts.input_id),
                    admission_revision,
                ),
                ResourceStamp {
                    resource_key: format!("thread-continuation:{}", continuation.point_id),
                    owner_epoch: self.owner_epoch().to_owned(),
                    revision: facts.accepted_sequence,
                },
            ],
            CommandEffectPoint::Immediate,
            false,
        );
        receipt.effective = false;
        receipt.requires_identity_observation = true;
        Ok(ContinuationOperationView {
            thread_id: thread_id.to_owned(),
            operation_id: request.operation_id.to_owned(),
            input_id: facts.input_id,
            continuation_id: continuation.point_id.clone(),
            accepted_sequence: facts.accepted_sequence,
            state,
            durable: facts.durable,
            receipt,
        })
    }
}

/// Frozen facts of one accepted continuation operation, from the durable index or the queue.
struct ContinuationFacts<'a> {
    input_id: String,
    continuation: Option<&'a pl_core::thread::input::InputContinuation>,
    accepted_sequence: u64,
    state: &'a pl_core::thread::input::InputState,
    expected_model_route_revision: Option<u64>,
    admission_revision: Option<u64>,
    stored_digest: Option<&'a str>,
    durable: bool,
}

/// Revision core assigns to the commit that admits an input.
///
/// The identity index records the admission revision on its first write; this constant only covers
/// the short window before that write, where the queue's own revision is still the admission one.
const ADMISSION_REVISION_FALLBACK: u64 = 1;

/// How long an accepted continuation may take to reach the durable identity index.
const ACCEPTED_IDENTITY_WAIT: std::time::Duration = std::time::Duration::from_secs(5);

/// Poll interval while waiting for that commit to land.
const ACCEPTED_IDENTITY_POLL: std::time::Duration = std::time::Duration::from_millis(10);

/// What a repeat or a query may assert about the operation it names.
struct ContinuationIdentity<'a> {
    operation_id: &'a str,
    expected_continuation_id: Option<&'a str>,
    expected_model_route_revision: Option<u64>,
}

/// Requires the request to describe the accepted continuation operation exactly.
///
/// The frozen facts come from the first admission — the durable identity row, or this runtime's
/// record of it before that row is saved — so the resident and durable paths make the same decision:
/// the same point and the same route revision answer the original receipt, anything else conflicts.
fn ensure_accepted_continuation(
    thread_id: &str,
    request: &ContinuationIdentity<'_>,
    accepted_point_id: &str,
    accepted_route_revision: Option<u64>,
) -> Result<()> {
    if let Some(expected) = request.expected_continuation_id
        && expected != accepted_point_id
    {
        return Err(stale_identity(
            StudioErrorReason::StaleContinuation,
            "The continuation this operation carries is not the one observed",
            serde_json::json!({
                "threadId": thread_id,
                "operationId": request.operation_id,
                "expectedContinuationId": expected,
                "acceptedContinuationId": accepted_point_id,
            }),
        ));
    }
    if let (Some(expected), Some(accepted)) = (
        request.expected_model_route_revision,
        accepted_route_revision,
    ) && expected != accepted
    {
        return Err(stale_identity(
            StudioErrorReason::StaleContinuation,
            "This operation was accepted with a different model route revision",
            serde_json::json!({
                "threadId": thread_id,
                "operationId": request.operation_id,
                "expectedModelRouteRevision": expected,
                "acceptedModelRouteRevision": accepted,
            }),
        ));
    }
    Ok(())
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

/// The accepted admission is resident but its durable identity row is not readable yet.
///
/// It is an internal marker, never a public outcome: the post-admission wait keeps polling on it, and
/// every entry that must answer without waiting converts it into the public retryable `Busy`. Keeping
/// it out of `StudioError` means a caller can never receive a condition that is expected to clear on
/// its own inside the same command.
#[derive(Debug)]
struct AcceptedIdentityPending;

impl std::fmt::Display for AcceptedIdentityPending {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("the accepted continuation receipt is not readable yet")
    }
}

impl std::error::Error for AcceptedIdentityPending {}
