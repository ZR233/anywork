use super::ModelSession;
use super::transport_policy::MODEL_MAX_RETRIES;
use crate::completion::stream::event::ModelStreamEvent;
use crate::completion::{CompletionFailure, CompletionTraceContext};
use pl_protocol::{PureError, Result};
use std::sync::Arc;

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
    pub(super) current: Option<super::current::CurrentInvocation>,
    pub(super) observer: Option<StreamObserver>,
    pub(super) purpose: InvocationPurpose,
}

impl ModelInvocationContext {
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
            observer: None,
            trace: None,
            cancellation: None,
            prompt_cache_scope: None,
            progress: None,
            members: None,
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
    pub(super) fn begin_retry(&self, error: &mut CompletionFailure) -> Result<()> {
        let sender = self
            .progress
            .as_ref()
            .expect("invocation owns its observation");
        let message = error.to_string();
        sender
            .charge_output(
                sender
                    .charged_output()
                    .saturating_add(message.len() as u64)
                    .saturating_add(256),
            )
            .map_err(|error| PureError::MemoryError(error.to_string()))?;
        sender
            .begin_recovery(MODEL_MAX_RETRIES, Arc::from(message))
            .map_err(|error| PureError::Protocol(error.to_string()))?;
        // These parts now belong solely to the retained failed generation. A
        // cancellation/refresh failure before the next send must not relabel
        // them as that unsent generation's current presentation.
        error.presentation_items.clear();
        Ok(())
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
