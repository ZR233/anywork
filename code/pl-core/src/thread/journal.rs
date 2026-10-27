//! Immutable Thread effect batches.
//!
//! An effect batch is the only durable copy of the facts one commit produced. It is built from the
//! live state right before that state drops terminal execution and exported history, so the delta
//! describes what changed rather than what the owner currently retains.
use super::*;

/// Context mutation within an atomic Thread commit.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "value")]
pub enum ContextChange {
    Append {
        revision: u64,
        records: Arc<[ContextRecord]>,
    },
    Replace(ContextSnapshot),
}

/// Request facts reference the input context revision already committed in the same journal.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttemptUpdate {
    #[serde(default)]
    pub request_metadata: Option<OpaquePayload>,
    #[serde(default)]
    pub usage_binding: Option<crate::model::ModelUsageBinding>,
    #[serde(default)]
    pub tool_projection: Option<OpaquePayload>,
    pub turn_id: String,
    pub attempt_id: String,
    pub retry_of: Option<String>,
    pub input_revision: u64,
    pub tools: Arc<[ModelToolDeclaration]>,
    pub outcome: AttemptOutcome,
    pub input_estimate: Option<crate::model::TokenEstimate>,
}

/// Explicit private-material mutation. Missing mutation means unchanged.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "value")]
pub enum PrivateContextChange {
    Set(OpaquePayload),
    Clear,
}

/// One atomic output batch containing context, output, continuation and lifecycle changes.
///
/// Runtime owners publish these batches to persistence and live observers. They never replay them
/// to reconstruct their own state; restart uses [`super::ThreadCheckpoint`] instead.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadEffectBatch {
    /// Time this fact batch became canonical in memory, independent from asynchronous database flush.
    pub committed_at: i64,
    #[serde(default)]
    pub permissions: Arc<[permissions::PermissionRecord]>,
    #[serde(default)]
    pub wake_messages_through: Option<u64>,
    #[serde(default)]
    pub inputs: Arc<[input::InputChange]>,
    #[serde(default)]
    pub tasks: Arc<[task::TaskRecord]>,
    pub thread_id: String,
    pub sequence: u64,
    pub context: Option<ContextChange>,
    /// None means unchanged; Clear is preserved as an explicit serialized operation.
    pub private_context: Option<PrivateContextChange>,
    pub attempt: Option<AttemptUpdate>,
    pub turn: Option<TurnRecord>,
    pub discovered_tools: Option<Arc<[ModelToolDeclaration]>>,
    pub deliveries: Arc<[ToolDelivery]>,
    /// Durable resource supplements for already-committed deliveries of this commit.
    ///
    /// A re-saved archive names the committed call identity its reference belongs to, so the
    /// reference is applied to that one tool identity — the live projection and history writer
    /// append it to the already-projected result — instead of a second delivery for the same call,
    /// which the journal rejects. Empty for every commit that repairs nothing.
    #[serde(default)]
    pub delivery_repairs: Arc<[cold::OutputRepair]>,
    pub extensions: Arc<[extensions::ExtensionChange]>,
    pub inbox: Arc<[inbox::InboxRecord]>,
    pub consumed_messages: Option<u64>,
    pub interactions: Arc<[interactions::InteractionRecord]>,
    pub replacements: Arc<[ContextReplacement]>,
    pub runtime_facts: Option<Arc<[RuntimeFact]>>,
    pub lifecycle: Option<ThreadLifecycle>,
}

/// Invalid encoded journal data. Unknown outer formats are rejected without altering raw bytes.
#[derive(Debug, thiserror::Error)]
pub enum JournalCodecError {
    #[error("unsupported Thread commit format {format} version {version}")]
    Unsupported { format: String, version: u32 },
    #[error("invalid Thread commit encoding: {0}")]
    Encoding(#[from] serde_json::Error),
}

impl ThreadEffectBatch {
    /// Freezes the actual effect batch as an opaque persistence payload.
    ///
    /// # Errors
    /// Returns an encoding failure without changing the committed state.
    pub fn encode(&self) -> Result<OpaquePayload, JournalCodecError> {
        let content = serde_json::to_string(self)?;
        Ok(
            OpaquePayload::new("pl.core.thread-effect-batch", 1, content)
                .expect("static nonempty format and nonzero version"),
        )
    }

    /// Loads a framework commit without interpreting nested tool or model payload formats.
    ///
    /// # Errors
    /// Rejects an unsupported outer schema or invalid envelope encoding.
    pub fn decode(payload: &OpaquePayload) -> Result<Self, JournalCodecError> {
        let supported = matches!(
            (payload.format(), payload.version()),
            ("pl.core.thread-effect-batch", 1)
        );
        if !supported {
            return Err(JournalCodecError::Unsupported {
                format: payload.format().into(),
                version: payload.version(),
            });
        }
        Ok(serde_json::from_str(payload.content())?)
    }

    pub(super) fn between(
        thread_id: &str,
        previous: &ThreadSnapshot,
        current: &ThreadSnapshot,
        sequence: u64,
    ) -> Option<Self> {
        let context = if previous.context == current.context {
            None
        } else if current
            .context
            .records
            .starts_with(&previous.context.records)
        {
            Some(ContextChange::Append {
                revision: current.context.revision,
                records: current.context.records[previous.context.records.len()..]
                    .to_vec()
                    .into(),
            })
        } else {
            Some(ContextChange::Replace(current.context.clone()))
        };
        let private_context = (previous.private_context != current.private_context).then(|| {
            match &current.private_context {
                Some(payload) => PrivateContextChange::Set(payload.clone()),
                None => PrivateContextChange::Clear,
            }
        });
        let attempt = if Arc::ptr_eq(&previous.attempts, &current.attempts) {
            None
        } else {
            current.attempts.last().and_then(|attempt| {
                let facts = attempt.facts.as_ref();
                let outcome = match facts {
                    Some(facts) => facts.outcome.clone(),
                    None => attempt.status.body_less_outcome()?,
                };
                Some(AttemptUpdate {
                    request_metadata: facts.and_then(|facts| facts.request_metadata.clone()),
                    usage_binding: facts.and_then(|facts| facts.usage_binding.clone()),
                    tool_projection: facts.and_then(|facts| facts.tool_projection.clone()),
                    turn_id: attempt.turn_id.clone(),
                    attempt_id: attempt.attempt_id.clone(),
                    retry_of: attempt.retry_of.clone(),
                    input_revision: attempt.input_revision,
                    tools: facts.map(|facts| facts.tools.clone()).unwrap_or_default(),
                    outcome,
                    input_estimate: facts.and_then(|facts| facts.input_estimate),
                })
            })
        };
        let inputs: Arc<[input::InputChange]> = current.input_changes
            [previous.input_changes.len()..]
            .to_vec()
            .into();
        let tasks: Arc<[task::TaskRecord]> = current.task_changes[previous.task_changes.len()..]
            .to_vec()
            .into();
        // Delivered results leave resident state independently of each other, so identify the
        // changed entries instead of relying on a retained prefix. A result is exported once under
        // its call identity; a repair supplements the already-committed *context* record the model
        // reads instead of re-exporting the delivery, so a call identity never appears twice in the
        // journal and the result keeps its single identity.
        let exported_deliveries = previous
            .deliveries
            .iter()
            .map(|delivery| delivery.call_id.as_str())
            .collect::<std::collections::BTreeSet<_>>();
        let deliveries: Arc<[ToolDelivery]> = current
            .deliveries
            .iter()
            .filter(|delivery| !exported_deliveries.contains(delivery.call_id.as_str()))
            .cloned()
            .collect::<Vec<_>>()
            .into();
        let replacements: Arc<[ContextReplacement]> = current.context_replacements
            [previous.context_replacements.len()..]
            .to_vec()
            .into();
        // Repair supplements are a commit-export buffer like the replacements above: the commit that
        // publishes them consumes them, so the exported suffix is exactly this commit's facts.
        let delivery_repairs: Arc<[cold::OutputRepair]> = current.delivery_repairs
            [previous.delivery_repairs.len()..]
            .to_vec()
            .into();
        let runtime_facts = (previous.runtime_facts != current.runtime_facts)
            .then(|| current.runtime_facts.clone());
        let extensions: Arc<[extensions::ExtensionChange]> = current.extension_changes
            [previous.extension_changes.len()..]
            .to_vec()
            .into();
        // Admitted messages are identified by their monotonic sequence, not by their position: the
        // queue prunes consumed entries, so a positional suffix would mis-export a commit that both
        // advances the consumption watermark and admits a new message. The lower bound is the highest
        // sequence the previous snapshot already knew about.
        let admitted_through = previous
            .inbox_sequence
            .max(previous.inbox.last().map_or(0, |record| record.sequence))
            .max(previous.consumed_messages);
        let inbox: Arc<[inbox::InboxRecord]> = current
            .inbox
            .iter()
            .filter(|record| record.sequence > admitted_through)
            .cloned()
            .collect::<Vec<_>>()
            .into();
        let wake_messages_through = (previous.wake_messages_through
            != current.wake_messages_through)
            .then_some(current.wake_messages_through);
        let consumed_messages = (previous.consumed_messages != current.consumed_messages)
            .then_some(current.consumed_messages);
        let turn = (!Arc::ptr_eq(&previous.turns, &current.turns))
            .then(|| current.turns.last().cloned())
            .flatten();
        let permissions: Arc<[permissions::PermissionRecord]> = current.permission_changes
            [previous.permission_changes.len()..]
            .to_vec()
            .into();
        let interactions: Arc<[interactions::InteractionRecord]> = current.interaction_changes
            [previous.interaction_changes.len()..]
            .to_vec()
            .into();
        let discovered_tools = (previous.discovered_tools != current.discovered_tools)
            .then(|| current.discovered_tools.clone());
        let lifecycle = (previous.lifecycle != current.lifecycle).then_some(current.lifecycle);
        if context.is_none()
            && private_context.is_none()
            && attempt.is_none()
            && turn.is_none()
            && discovered_tools.is_none()
            && tasks.is_empty()
            && inputs.is_empty()
            && deliveries.is_empty()
            && delivery_repairs.is_empty()
            && replacements.is_empty()
            && runtime_facts.is_none()
            && lifecycle.is_none()
            && extensions.is_empty()
            && inbox.is_empty()
            && consumed_messages.is_none()
            && wake_messages_through.is_none()
            && permissions.is_empty()
            && interactions.is_empty()
        {
            return None;
        }
        Some(Self {
            committed_at: crate::time::unix_seconds(),
            wake_messages_through,
            inputs,
            tasks,
            thread_id: thread_id.to_owned(),
            sequence,
            context,
            private_context,
            attempt,
            turn,
            discovered_tools,
            deliveries,
            delivery_repairs,
            extensions,
            inbox,
            consumed_messages,
            permissions,
            interactions,
            replacements,
            runtime_facts,
            lifecycle,
        })
    }
}
