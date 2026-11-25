use super::ModelSession;
use super::transport_policy::MODEL_MAX_RETRIES;
use crate::completion::stream::event::ModelStreamEvent;
use crate::completion::{CompletionFailure, CompletionTraceContext};
use pl_core::model::ModelMemberError;
use pl_core::thread::ModelSettlementPort;
use pl_protocol::{PureError, Result};
use std::sync::Arc;

#[derive(Debug, Clone)]
pub(super) enum BoundSettlement {
    Memory,
    Thread(ModelSettlementPort),
}

impl BoundSettlement {
    pub(super) fn turn_id(&self) -> Option<&str> {
        match self {
            Self::Memory => None,
            Self::Thread(port) => port.turn_id(),
        }
    }

    pub(super) async fn settle(
        &self,
        generation: u32,
        payload: pl_core::context::OpaquePayload,
    ) -> std::result::Result<(), ModelMemberError> {
        match self {
            Self::Memory => Ok(()),
            Self::Thread(port) => port.settle(generation, payload).await,
        }
    }

    pub(super) fn cancellation(&self) -> Option<&tokio_util::sync::CancellationToken> {
        match self {
            Self::Memory => None,
            Self::Thread(port) => port.cancellation(),
        }
    }
}

pub(super) fn settlement_trace(port: &ModelSettlementPort) -> CompletionTraceContext {
    CompletionTraceContext {
        session_id: port.thread_id().into(),
        turn_id: port.turn_id().unwrap_or_else(|| port.attempt_id()).into(),
        inference_id: port.attempt_id().into(),
    }
}

/// 单次模型调用的运行期上下文。
///
/// 连接 continuation 属于 [`ModelSession`]；请求诊断、Core 观测端口和 prompt cache scope
/// 只在当前调用内有效，不进入 canonical completion request。
#[derive(Debug, Clone)]
pub struct ModelInvocationContext {
    pub(super) session: ModelSession,
    pub(super) trace: Option<CompletionTraceContext>,
    pub(super) cancellation: Option<tokio_util::sync::CancellationToken>,
    pub(super) prompt_cache_scope: Option<super::PromptCacheScope>,
    pub(super) progress: Option<pl_core::model::ModelProgressSender>,
    pub(super) members: Option<pl_core::model::ModelMemberSender>,
    pub(super) settlement: Option<BoundSettlement>,
    pub(super) current: Option<super::current::CurrentInvocation>,
    pub(super) observer: Option<StreamObserver>,
    pub(super) purpose: InvocationPurpose,
    pub(super) billing_purpose: String,
    pub(super) billing_prompt: Option<super::ThreadPromptSnapshot>,
}

impl ModelInvocationContext {
    /// Selects invocation-owned receipt delivery for an independent, non-persisted call.
    pub fn in_memory(session: super::ModelSession) -> Self {
        Self {
            settlement: Some(BoundSettlement::Memory),
            ..Self::new(session)
        }
    }

    /// Binds the already registered Thread call before the first network send.
    pub fn with_settlement_port(
        mut self,
        purpose: impl Into<String>,
        port: ModelSettlementPort,
    ) -> Self {
        self.billing_purpose = purpose.into();
        self.trace = Some(settlement_trace(&port));
        self.settlement = Some(BoundSettlement::Thread(port));
        self
    }

    pub(super) fn bind_thread_settlement(mut self, independent: bool) -> Self {
        self.settlement = match self
            .members
            .as_ref()
            .and_then(|members| members.settlement_port())
        {
            Some(port) => {
                if port.turn_id().is_none()
                    && let Some(trace) = self.trace.as_mut()
                {
                    trace.turn_id = port.attempt_id().into();
                }
                Some(BoundSettlement::Thread(port.clone()))
            }
            None if independent => Some(BoundSettlement::Memory),
            None => None,
        };
        self
    }

    pub(super) fn with_billing_purpose(mut self, purpose: String) -> Self {
        self.billing_purpose = purpose;
        self
    }

    pub(super) fn with_billing_prompt(
        mut self,
        prompt: Option<super::ThreadPromptSnapshot>,
    ) -> Self {
        self.billing_prompt = prompt;
        self
    }
    pub(super) fn with_current(mut self, current: super::current::CurrentInvocation) -> Self {
        self.current = Some(current);
        self
    }
    pub(super) fn with_members(
        mut self,
        members: Option<pl_core::model::ModelMemberSender>,
    ) -> Self {
        self.members = members;
        self
    }
    /// Binds core request identities for wire diagnostics without a parallel event sink.
    pub fn with_trace_metadata(mut self, trace: CompletionTraceContext) -> Self {
        self.trace = Some(trace);
        self
    }

    pub(super) fn with_progress(
        mut self,
        progress: Option<pl_core::model::ModelProgressSender>,
    ) -> Self {
        self.progress = progress;
        self
    }

    /// Withdraws this generation's live usage and response time as one group.
    ///
    /// Used by every outer failure, cancellation and exhausted-retry path that never produced a
    /// `Failed` event, so no published snapshot can pair pre-failure tokens with a failure clock.
    pub(super) fn close_live_usage(&self) {
        if let Some(progress) = &self.progress {
            progress.close_live_usage();
        }
    }

    pub(super) fn with_session(mut self, session: ModelSession) -> Self {
        self.session = session;
        self
    }

    pub fn new(session: ModelSession) -> Self {
        Self {
            session,
            purpose: InvocationPurpose::Completion,
            billing_purpose: "completion".into(),
            billing_prompt: None,
            observer: None,
            trace: None,
            cancellation: None,
            prompt_cache_scope: None,
            progress: None,
            members: None,
            settlement: None,
            current: None,
        }
    }

    /// Observes provisional, normalized events as the provider stream is consumed.
    /// Each retry has a new generation; only the completion result is authoritative.
    pub fn with_stream_observer(
        mut self,
        observer: impl Fn(u32, &ModelStreamEvent) + Send + Sync + 'static,
    ) -> Self {
        self.observer = Some(StreamObserver(Arc::new(observer)));
        self
    }

    /// Associates cooperative cancellation with this invocation.
    pub fn with_cancellation(
        mut self,
        cancellation: Option<tokio_util::sync::CancellationToken>,
    ) -> Self {
        self.cancellation = cancellation;
        self
    }

    /// Supplies stable host ownership; the bound runtime resolves endpoint support and the wire key.
    pub fn with_prompt_cache_scope(mut self, scope: super::PromptCacheScope) -> Self {
        self.prompt_cache_scope = Some(scope);
        self
    }
    pub(super) fn begin_retry(
        &self,
        error: &mut CompletionFailure,
        decision: super::ModelRecoveryDecision,
        phase: pl_core::model::ModelRecoveryPhase,
        preparation: bool,
    ) -> Result<()> {
        let sender = self
            .progress
            .as_ref()
            .expect("invocation owns its observation");
        let message = decision
            .provider_failure
            .as_ref()
            .map_or_else(|| error.to_string(), |failure| failure.message.clone());
        let retry = decision.retry;
        let decision = decision.encode()?;
        sender
            .charge_output(
                sender
                    .charged_output()
                    .saturating_add(message.len() as u64)
                    .saturating_add(decision.content().len() as u64)
                    .saturating_add(256),
            )
            .map_err(|error| PureError::MemoryError(error.to_string()))?;
        let message = Arc::from(message);
        let staged = if preparation {
            sender.stage_preparation_recovery(
                MODEL_MAX_RETRIES,
                retry,
                message,
                Some(decision),
                phase,
            )
        } else {
            sender.stage_recovery(MODEL_MAX_RETRIES, retry, message, Some(decision), phase)
        };
        staged.map_err(|error| PureError::Protocol(error.to_string()))?;
        // These parts now belong solely to the retained failed generation. A
        // cancellation/refresh failure before the next send must not relabel
        // them as that unsent generation's current presentation.
        error.presentation_items.clear();
        Ok(())
    }

    pub(super) async fn admit_connection(
        &self,
        fact: pl_core::model::ModelConnectionFact,
        current: Option<&mut super::current::CurrentProducer>,
    ) -> std::result::Result<(), pl_core::model::ModelMemberError> {
        let Some(members) = self.members.as_ref() else {
            return Ok(());
        };
        let admission = members.connection(fact, self.cancellation.as_ref());
        if let Some(current) = current {
            current.wait(admission, None).await
        } else {
            admission.await
        }
    }

    pub(super) fn current_generation(&self) -> u32 {
        self.progress
            .as_ref()
            .map_or(0, |progress| progress.latest().observation().generation)
    }
}

impl Default for ModelInvocationContext {
    fn default() -> Self {
        Self::new(ModelSession::default())
    }
}

/// Parameters that belong only to this invocation, never to the shared model binding.
#[derive(Clone)]
pub(super) enum InvocationPurpose {
    Completion,
    RemoteCompaction {
        headers: std::collections::HashMap<String, String>,
        body: serde_json::Map<String, serde_json::Value>,
    },
}

// The purpose is diagnostic; compaction headers and the frozen prompt are not.
impl std::fmt::Debug for InvocationPurpose {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(match self {
            Self::Completion => "Completion",
            Self::RemoteCompaction { .. } => "RemoteCompaction",
        })
    }
}

type ObserverFn = dyn Fn(u32, &ModelStreamEvent) + Send + Sync;

#[derive(Clone)]
pub(crate) struct StreamObserver(Arc<ObserverFn>);

impl StreamObserver {
    pub(crate) fn observe(&self, generation: u32, event: &ModelStreamEvent) {
        (self.0)(generation, event);
    }
}

impl std::fmt::Debug for StreamObserver {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("StreamObserver")
    }
}
