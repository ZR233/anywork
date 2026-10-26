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
                pl_protocol::studio::ControlFailureFacts::ChildThreadAction { thread_id: record.id .to_owned(), action: action.label() .to_owned(), parent_thread_id: record.parent_thread_id.clone() },
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
            pl_protocol::studio::ControlFailureFacts::ThreadAction { thread_id: record.id .to_owned(), action: action.label() .to_owned() },
        ),
    ))
}

/// Fails closed when a caller's frozen identity is not the one the Thread currently publishes.
fn stale_identity(
    reason: StudioErrorReason,
    message: &'static str,
    extra: pl_protocol::studio::ControlFailureFacts,
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
    /// Rejects an archived target, no current execution, a stale execution identity and a closed owner.
    pub async fn stop_thread(
        &self,
        thread_id: String,
        request: StopThreadRequest,
    ) -> Result<StopThreadResponse> {
        Self::validate_operation_id(&request.operation_id)?;
        let record = self.read_owned_thread(&thread_id).await?;
        ensure_thread_not_archived(&record, UserThreadAction::Stop)?;
        // Match the mailbox's identity priority even when no owner is resident. Only the empty
        // identity is invalid here; whitespace and all other nonempty identities remain unchanged.
        if request.expected_execution_id.is_empty() {
            return Err(stale_identity(
                StudioErrorReason::StaleExecution,
                "The observed execution is no longer current; reload before stopping",
                pl_protocol::studio::ControlFailureFacts::ExpectedExecution {
                    thread_id: thread_id.to_owned(),
                    expected_execution_id: request.expected_execution_id.to_owned(),
                },
            ));
        }
        let Some(thread) = self.threads.thread(&thread_id) else {
            // A cold Thread owns no execution. Do not activate it merely to decide a stop.
            return Err(stale_identity(
                StudioErrorReason::NoExecution,
                "This Thread has no current execution to stop",
                pl_protocol::studio::ControlFailureFacts::ExpectedExecution { thread_id: thread_id .to_owned(), expected_execution_id: request.expected_execution_id .to_owned() },
            ));
        };
        let stopped = thread
            .interrupt_execution(request.expected_execution_id.clone())
            .await
            .map_err(|error| match error {
                pl_core::thread::ThreadError::NoExecution => stale_identity(
                    StudioErrorReason::NoExecution,
                    "This Thread has no current execution to stop",
                    pl_protocol::studio::ControlFailureFacts::ExpectedExecution {
                        thread_id: thread_id.to_owned(),
                        expected_execution_id: request.expected_execution_id.to_owned(),
                    },
                ),
                pl_core::thread::ThreadError::InvalidIdentity => stale_identity(
                    StudioErrorReason::StaleExecution,
                    "The observed execution is no longer current; reload before stopping",
                    pl_protocol::studio::ControlFailureFacts::ExpectedExecution { thread_id: thread_id .to_owned(), expected_execution_id: request.expected_execution_id .to_owned() },
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
                    pl_protocol::studio::ControlFailureFacts::Executing { thread_id: thread_id .to_owned(), execution_id: execution.id .to_owned(), phase: format!("{:?}", execution.phase) },
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
                    pl_protocol::studio::ControlFailureFacts::ExpectedContinuation { thread_id: thread_id .to_owned(), expected_continuation_id: request.expected_continuation_id .to_owned() },
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
        // guard (`run_thread_lifecycle_operation` → `archive_thread_owned`) — so keeping either one alive through the
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
        wait_for_accepted_continuation(thread_id, identity, deadline, || {
            self.read_continuation_operation_view(thread_id, identity, ContinuationLookup::Admission)
        })
            .await
    }

    /// The retryable answer for "accepted, but its receipt is not durable yet".
    fn accepted_identity_pending(
        &self,
        thread_id: &str,
        identity: &ContinuationIdentity<'_>,
    ) -> Result<ContinuationOperationView> {
        Err(Self::accepted_identity_pending_error(
            thread_id, identity, None,
        ))
    }

    /// The same retryable answer for callers that are not returning a receipt value.
    ///
    /// The internal pending marker never leaves a public command: a repeat during the
    /// "admitted but not yet durable" window answers the documented retryable Busy instead.
    fn accepted_identity_pending_error(
        thread_id: &str,
        identity: &ContinuationIdentity<'_>,
        cause: Option<anyhow::Error>,
    ) -> anyhow::Error {
        let pending = StudioError::new(
                StudioErrorCode::Busy,
                "The continuation was accepted but its receipt is not durable yet; retry the same operation",
                true,
            )
            .with_reason(
            StudioErrorReason::ContinuationAccepted,
            accepted_continuation_facts(thread_id, identity),
        );
        match cause {
            Some(error) => error.context(pending),
            None => anyhow::Error::new(pending),
        }
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
            .read_continuation_operation_view(&thread_id, &identity, ContinuationLookup::Query)
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
                .with_reason(StudioErrorReason::ContinuationUnavailable,
                    pl_protocol::studio::ControlFailureFacts::ContinuationOperation { thread_id: thread_id .to_owned(), operation_id: operation_id .to_owned() },
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
            .read_continuation_operation_view(thread_id, identity, ContinuationLookup::Admission)
            .await
        {
            Ok(found) => Ok(found),
            Err(error) if error.downcast_ref::<AcceptedIdentityPending>().is_some() => {
                Err(Self::accepted_identity_pending_error(
                    thread_id,
                    identity,
                    Some(error),
                ))
            }
            Err(error) => Err(error),
        }
    }

    async fn read_continuation_operation_view(
        &self,
        thread_id: &str,
        request: &ContinuationIdentity<'_>,
        lookup: ContinuationLookup,
    ) -> Result<Option<ContinuationOperationView>> {
        // A storage fault or an unreached durable fence is propagated: only a reliable "no durable
        // record" answer may fall through to the resident facts or become NotFound.
        let history = self.read_timeline_history(thread_id).await?;
        if let Some(previous) = history.input_identity(request.operation_id).await? {
            // A query may report no continuation for a message, but a command must reject this
            // occupied identity before activation/claim, even after core's terminal window evicts it.
            if previous.entry.purpose != pl_core::thread::input::InputPurpose::Continuation {
                return lookup.other_input_purpose(thread_id, request.operation_id);
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
            return lookup.other_input_purpose(thread_id, request.operation_id);
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
                    pl_protocol::studio::ControlFailureFacts::ContinuationOperation { thread_id: thread_id .to_owned(), operation_id: request.operation_id .to_owned() },
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

/// Queries may ignore other input purposes; admission must not reuse any occupied identity.
#[derive(Clone, Copy)]
enum ContinuationLookup {
    Query,
    Admission,
}

impl ContinuationLookup {
    fn other_input_purpose(
        self,
        thread_id: &str,
        operation_id: &str,
    ) -> Result<Option<ContinuationOperationView>> {
        match self {
            Self::Query => Ok(None),
            Self::Admission => Err(stale_identity(
                StudioErrorReason::StaleContinuation,
                "This operation identity already belongs to a different input purpose",
                pl_protocol::studio::ControlFailureFacts::ContinuationOperation {
                    thread_id: thread_id.to_owned(),
                    operation_id: operation_id.to_owned(),
                },
            )),
        }
    }
}

/// Only the original admission is awaited: reads cannot claim, re-authorise or flush it again.
async fn wait_for_accepted_continuation<Read, ReadFuture>(
    thread_id: &str,
    identity: &ContinuationIdentity<'_>,
    deadline: tokio::time::Instant,
    mut read: Read,
) -> Result<ContinuationOperationView>
where
    Read: FnMut() -> ReadFuture,
    ReadFuture: std::future::Future<Output = Result<Option<ContinuationOperationView>>>,
{
    let mut pending_cause = None;
    loop {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if remaining.is_zero() {
            return Err(StudioRuntime::accepted_identity_pending_error(
                thread_id,
                identity,
                pending_cause,
            ));
        }
        // The read and every poll share one deadline, so repeated Busy never renews the budget.
        match tokio::time::timeout(remaining, read()).await {
            Ok(Ok(Some(view))) => return Ok(view),
            Ok(Ok(None)) => {}
            Ok(Err(error)) if error.downcast_ref::<AcceptedIdentityPending>().is_some() => {}
            Ok(Err(error)) => {
                let public = crate::error_mapping::studio_error_from_anyhow_ref(&error);
                if public.code != StudioErrorCode::Busy || !public.retryable {
                    // Preserve the actual category, retryability and source chain. The new outer
                    // typed context only records what this command already knows about admission.
                    return Err(error.context(public.with_reason(
                        StudioErrorReason::ContinuationAccepted,
                        accepted_continuation_facts(thread_id, identity),
                    )));
                }
                pending_cause = Some(error);
            }
            Err(elapsed) => {
                return Err(StudioRuntime::accepted_identity_pending_error(
                    thread_id,
                    identity,
                    pending_cause.or_else(|| Some(anyhow::Error::new(elapsed))),
                ));
            }
        }
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        if !remaining.is_zero() {
            tokio::time::sleep(ACCEPTED_IDENTITY_POLL.min(remaining)).await;
        }
    }
}

fn accepted_continuation_facts(
    thread_id: &str,
    identity: &ContinuationIdentity<'_>,
) -> pl_protocol::studio::ControlFailureFacts {
    pl_protocol::studio::ControlFailureFacts::ContinuationAccepted {
        thread_id: thread_id.to_owned(),
        operation_id: identity.operation_id.to_owned(),
        accepted: true,
    }
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
            pl_protocol::studio::ControlFailureFacts::ContinuationPointConflict { thread_id: thread_id .to_owned(), operation_id: request.operation_id .to_owned(), expected_continuation_id: expected .to_owned(), accepted_continuation_id: accepted_point_id .to_owned() },
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
            pl_protocol::studio::ControlFailureFacts::ContinuationRouteConflict { thread_id: thread_id .to_owned(), operation_id: request.operation_id .to_owned(), expected_model_route_revision: expected, accepted_model_route_revision: accepted },
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
            pl_protocol::studio::ControlFailureFacts::ExpectedContinuation { thread_id: thread_id .to_owned(), expected_continuation_id: request.expected_continuation_id .to_owned() },
        ));
    };
    if point.id != request.expected_continuation_id {
        return Err(stale_identity(
            StudioErrorReason::StaleContinuation,
            "The observed continuation is no longer current",
            pl_protocol::studio::ControlFailureFacts::StaleContinuation { thread_id: thread_id .to_owned(), expected_continuation_id: request.expected_continuation_id .to_owned(), current_continuation_id: point.id .to_owned() },
        ));
    }
    if point.claim.is_some() {
        return Err(stale_identity(
            StudioErrorReason::ContinuationClaimed,
            "This continuation was already accepted by another operation",
            pl_protocol::studio::ControlFailureFacts::ClaimedContinuation { thread_id: thread_id .to_owned(), continuation_id: point.id .to_owned() },
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::storage::history::{EffectCommit, HistoryReadFailure, InputIdentityWrite};
    use crate::studio::storage::state::InputIdentityEntry;
    use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord};
    use pl_core::context::OpaquePayload;
    use pl_core::thread::input::{
        InputDriverOptions, InputPurpose, InputRecord, InputState, ThreadInput,
    };
    use pl_core::thread::{
        ContinuationPoint, ContinuationReason, ThreadCheckpoint, ThreadEffectBatch, ThreadHandle,
        ThreadSnapshot,
    };
    use pl_protocol::studio::{ControlFailureFacts, StudioErrorDetails};
    use std::time::Duration;

    async fn cold_runtime() -> Result<(tempfile::TempDir, StudioRuntime, pl_protocol::Thread)> {
        let temp = tempfile::tempdir()?;
        let runtime = StudioRuntime::initialize(crate::StudioRuntimeOptions {
            studio_home: Some(temp.path().join("home")),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        })
        .await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: "control-project".into(),
            name: "Control fixture".into(),
            path: workspace.to_string_lossy().into_owned(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        });
        let (registered, thread) = DirectoryDelta::register_root_thread(
            "control-thread".into(),
            "control-project",
            "Control fixture",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            workspace.to_string_lossy().into_owned(),
        );
        delta.thread_upserts = registered.thread_upserts;
        runtime.store.persist_directory_summaries(&delta).await?;
        Ok((temp, runtime, thread))
    }

    #[tokio::test]
    async fn durable_message_id_outside_resident_window_cannot_claim_continuation() -> Result<()> {
        let (_temp, runtime, thread) = cold_runtime().await?;
        let history = runtime.store.history(&thread.id).await?;
        // Real checkpoint pruning evicts the oldest terminal identity. The durable index must
        // still reject it, rather than relying on core's recent 64 identities to catch reuse.
        let records = (1..=65)
            .map(|ordinal| InputRecord {
                input: ThreadInput {
                    id: format!("message-{ordinal}"),
                    purpose: InputPurpose::Message,
                    payload: OpaquePayload::text("original task body"),
                    context: Vec::new(),
                },
                ordinal,
                revision: 2,
                accepted_sequence: ordinal,
                continuation: None,
                delivery: Default::default(),
                state: InputState::Consumed {
                    turn_id: format!("turn-{ordinal}"),
                    attempt_id: format!("attempt-{ordinal}"),
                },
            })
            .collect::<Vec<_>>();
        let identities = records
            .iter()
            .map(|record| InputIdentityWrite {
                entry: InputIdentityEntry::new(
                    pl_core::thread::input::input_identity(record),
                    record.accepted_sequence,
                ),
                request_digest: Some(record.input.digest()),
                presentation: pl_protocol::MessagePresentation::Visible,
            })
            .collect::<Vec<_>>();
        let point = ContinuationPoint::new(
            66,
            "stopped-work",
            None,
            Some(ContinuationReason::UserStop),
        );
        let checkpoint = ThreadCheckpoint::capture(
            thread.id.clone(),
            66,
            ThreadSnapshot {
                commit_sequence: 66,
                inputs: records.into(),
                continuation: Some(point.clone()),
                ..Default::default()
            },
        );
        assert_eq!(checkpoint.state.terminal_inputs.len(), 64);
        assert!(checkpoint.state.inputs.is_empty());
        assert!(
            checkpoint
                .state
                .terminal_inputs
                .iter()
                .all(|input| input.id != "message-1")
        );
        let mut original = pl_protocol::ThreadItem::completed_user_message(
            "original-message".into(),
            thread.id.clone(),
            "turn-1".into(),
            "original task body".into(),
            Vec::new(),
            1,
        );
        original.ordinal = 1;
        history
            .commit_checkpoint_effect(
                &checkpoint,
                &ThreadEffectBatch {
                    thread_id: thread.id.clone(),
                    sequence: 66,
                    ..Default::default()
                },
                EffectCommit {
                    items: std::slice::from_ref(&original),
                    rolled_back_turns: &Default::default(),
                    identities: &identities,
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let saved_checkpoint = serde_json::to_value(history.checkpoint().await?)?;
        let saved_identity = history
            .input_identity("message-1")
            .await?
            .expect("old input remains durable");
        let saved_identity = serde_json::to_value(saved_identity.entry)?;
        assert!(runtime.threads.observed_thread(&thread.id).is_none());

        // Read-only operation lookup may say NotFound; that is not admission permission.
        let query = runtime
            .read_continuation_operation(thread.id.clone(), "message-1".into())
            .await
            .expect_err("a message is not a continuation operation");
        assert_eq!(
            crate::error_mapping::studio_error_from_anyhow_ref(&query).code,
            StudioErrorCode::NotFound
        );
        let refused = runtime
            .continue_thread(
                thread.id.clone(),
                ContinueThreadRequest {
                    operation_id: "message-1".into(),
                    expected_continuation_id: point.id,
                    expected_model_route_revision: 0,
                },
            )
            .await
            .expect_err("a durable message identity cannot be claimed again");
        let refused = crate::error_mapping::studio_error_from_anyhow_ref(&refused);
        assert_eq!(refused.code, StudioErrorCode::Conflict);
        assert_eq!(refused.reason(), Some("staleContinuation"));
        assert_eq!(
            refused.details.as_deref(),
            Some(&StudioErrorDetails::Control {
            reason: "staleContinuation".into(),
            facts: ControlFailureFacts::ContinuationOperation {
                thread_id: thread.id.clone(),
                operation_id: "message-1".into(),
            },
            })
        );
        // No owner was activated, hence no new claim or cancellation could run. The original
        // body, unclaimed continuation and all saved state retain their exact durable identity.
        assert!(runtime.threads.observed_thread(&thread.id).is_none());
        assert_eq!(history.watermark().await?, 66);
        assert_eq!(history.item(&original.id).await?, Some(original));
        assert_eq!(
            serde_json::to_value(history.checkpoint().await?)?,
            saved_checkpoint
        );
        assert_eq!(
            serde_json::to_value(
                history
                    .input_identity("message-1")
                    .await?
                    .expect("old identity preserved")
                    .entry
            )?,
            saved_identity
        );
        drop(history);
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    async fn accepted_owner(operation_id: &str) -> Result<ThreadHandle> {
        let thread = ThreadHandle::resume_without_model(
            "accepted-thread".into(),
            Some(ThreadCheckpoint::capture(
                "accepted-thread".into(),
                1,
                ThreadSnapshot {
                    commit_sequence: 1,
                    continuation: Some(ContinuationPoint::new(1, "owed-work", None, None)),
                    ..Default::default()
                },
            )),
        )?;
        let admitted = thread
            .continue_thread(
                operation_id.into(),
                InputDriverOptions {
                    max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
                },
            )
            .await?;
        assert_eq!(admitted.input.id, operation_id);
        assert_eq!(admitted.input.purpose, InputPurpose::Continuation);
        Ok(thread)
    }

    fn assert_accepted(error: &anyhow::Error, operation_id: &str) -> StudioError {
        let public = crate::error_mapping::studio_error_from_anyhow_ref(error);
        assert_eq!(
            public.details.as_deref(),
            Some(&StudioErrorDetails::Control {
            reason: "continuationAccepted".into(),
            facts: ControlFailureFacts::ContinuationAccepted {
                thread_id: "accepted-thread".into(),
                operation_id: operation_id.into(),
                accepted: true,
            },
            })
        );
        public
    }

    #[tokio::test(start_paused = true)]
    async fn accepted_history_busy_keeps_one_budget_and_original_admission() -> Result<()> {
        let thread = accepted_owner("accepted-busy").await?;
        let identity = ContinuationIdentity {
            operation_id: "accepted-busy",
            expected_continuation_id: None,
            expected_model_route_revision: None,
        };
        let busy = StudioError::new(StudioErrorCode::Busy, "history fence pending", true);
        // Includes the read's original correlation ID, which must survive in the cause chain.
        let original_busy_diagnostic = busy.to_string();
        let (first_entered, mut first_polled) = tokio::sync::oneshot::channel();
        let (second_entered, mut second_polled) = tokio::sync::oneshot::channel();
        let mut first_read = Some((first_entered, busy));
        let mut second_read = Some(second_entered);
        let mut reads = 0;
        let started_at = tokio::time::Instant::now();
        let mut waiting = Box::pin(wait_for_accepted_continuation(
            "accepted-thread",
            &identity,
            started_at + ACCEPTED_IDENTITY_WAIT,
            || {
                reads += 1;
                let (entered, busy) = match first_read.take() {
                    Some((entered, busy)) => (entered, Some(busy)),
                    None => (second_read.take().expect("only two reads are expected"), None),
                };
                async move {
                    entered.send(()).expect("read-stage observer is retained");
                    if let Some(busy) = busy {
                        // Consume four fifths of the real five-second budget before returning
                        // Busy. A deadline renewed after this read would expire much later.
                        tokio::time::sleep(Duration::from_secs(4)).await;
                        Err(anyhow::Error::new(std::io::Error::other(
                            "injected durable fence wait",
                        ))
                        .context(busy))
                    } else {
                        // This read was actually polled, but can only end through the production
                        // wait's remaining budget, never by an injected successful outcome.
                        std::future::pending().await
                    }
                }
            },
        ));
        assert!(futures::poll!(waiting.as_mut()).is_pending());
        first_polled.try_recv().expect("first read really entered before waiting");
        // Await the owning production future and let paused-time auto-advance drive timers in
        // order. Do not assume an expired Sleep is Ready on the first poll after time::advance.
        let result = waiting.as_mut().await;
        let elapsed = tokio::time::Instant::now().duration_since(started_at);
        drop(waiting);
        // Owner cleanup may itself advance paused time; it is outside the measured wait interval.
        thread.close().await?;
        second_polled.try_recv().expect("second read really entered Pending");
        assert_eq!(elapsed, ACCEPTED_IDENTITY_WAIT, "Busy must not renew the original deadline");
        let error = result.expect_err("the accepted receipt remains pending at the deadline");
        let public = assert_accepted(&error, identity.operation_id);
        assert_eq!(
            (public.code, public.retryable),
            (StudioErrorCode::Busy, true)
        );
        assert_eq!(reads, 2, "retryable Busy must not escape before the next read");
        assert!(
            error.downcast_ref::<std::io::Error>().is_some(),
            "the pending result retains the original Busy cause"
        );
        assert!(
            error.chain().skip(1).any(|cause| cause.to_string() == original_busy_diagnostic),
            "the original Busy and its correlation ID remain in the cause chain"
        );
        Ok(())
    }

    #[tokio::test]
    async fn accepted_hard_read_failure_preserves_category_retryability_and_cause() -> Result<()> {
        let thread = accepted_owner("accepted-fault").await?;
        let identity = ContinuationIdentity {
            operation_id: "accepted-fault",
            expected_continuation_id: None,
            expected_model_route_revision: None,
        };
        for (failure, code, retryable) in [
            (HistoryReadFailure::Storage, StudioErrorCode::Storage, true),
            (HistoryReadFailure::Protocol, StudioErrorCode::Protocol, false),
        ] {
            let source =
                anyhow::Error::new(std::io::Error::other("injected hard history failure"))
                .context(failure);
            // Keep a concrete inner StudioError as well: the adapter must see the *new outer*
            // accepted facts, without discarding this original typed error or its source chain.
            let original = crate::error_mapping::studio_error_from_anyhow_ref(&source);
            let mut source = Some(source.context(original.clone()));
            let mut reads = 0;
            let error = wait_for_accepted_continuation(
                "accepted-thread",
                &identity,
                tokio::time::Instant::now() + ACCEPTED_IDENTITY_WAIT,
                || {
                    reads += 1;
                    std::future::ready(Err(source.take().expect("hard failure is never retried")))
                },
            )
            .await
            .expect_err("an actual read failure is not a pending receipt");
            let public = assert_accepted(&error, identity.operation_id);
            assert_eq!((public.code, public.retryable), (code, retryable));
            assert_eq!(public.correlation_id, original.correlation_id);
            assert_eq!(public.message, original.message);
            assert_eq!(reads, 1);
            assert!(error.downcast_ref::<HistoryReadFailure>().is_some());
            assert_eq!(
                error
                    .downcast_ref::<std::io::Error>()
                    .expect("original cause retained")
                    .to_string(),
                "injected hard history failure"
            );
            assert!(
                error
                    .chain()
                    .skip(1)
                    .any(|cause| cause.to_string() == original.to_string()),
                "the original typed error remains in the cause chain"
            );
        }
        thread.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn cold_stop_reports_no_execution_without_activation_or_receipt() -> Result<()> {
        let (_temp, runtime, thread) = cold_runtime().await?;
        assert!(runtime.threads.observed_thread(&thread.id).is_none());
        for (expected_execution_id, reason) in [
            ("", "staleExecution"),
            ("old-execution", "noExecution"),
            (" ", "noExecution"),
        ] {
            let error = runtime
                .stop_thread(
                    thread.id.clone(),
                    StopThreadRequest {
                        operation_id: "stop-cold".into(),
                        expected_execution_id: expected_execution_id.into(),
                    },
                )
                .await
                .expect_err("a cold stop must reject without a successful receipt");
            let public = crate::error_mapping::studio_error_from_anyhow_ref(&error);
            assert_eq!(public.code, StudioErrorCode::Conflict);
            assert_eq!(
                public.details.as_deref(),
                Some(&StudioErrorDetails::Control {
                    reason: reason.into(),
                    facts: ControlFailureFacts::ExpectedExecution {
                        thread_id: thread.id.clone(),
                        expected_execution_id: expected_execution_id.into(),
                    },
                })
            );
            assert!(runtime.threads.observed_thread(&thread.id).is_none());
        }
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
