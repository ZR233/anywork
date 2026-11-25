//! Complete, history-independent logical current data and local restart reducers.
//!
//! These APIs do not select a production persistence backend. The checkpoint path remains
//! separate until its callers are migrated; no current operation reads or replays history.

use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
    str::FromStr,
    sync::Arc,
};

use serde::{Deserialize, Serialize};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use super::{
    ActiveExecution, ContinuationPoint, ModelUsageOrigin, RuntimeFact, ThreadLifecycle,
    ThreadSnapshot, ToolDelivery, ToolDeliveryTarget, UsageSummary, extensions, inbox, input,
    interactions, permissions, task,
};
use crate::context::{
    ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
};
use crate::model::{ModelError, ModelToolDeclaration, ToolCallMode};

mod capture;
mod serde_views;
pub(crate) use capture::{CapturedStream, CurrentRead};

pub const CURRENT_SCHEMA_VERSION: u32 = 1;

/// Authorization generation of one live owner, not a cursor into execution history.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct RuntimeEpoch(Uuid);

impl RuntimeEpoch {
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }
}

impl Default for RuntimeEpoch {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for RuntimeEpoch {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

impl FromStr for RuntimeEpoch {
    type Err = CurrentError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        let uuid = Uuid::parse_str(value).map_err(|_| CurrentError::InvalidEpoch)?;
        if uuid.get_version_num() != 4
            || uuid.get_variant() != uuid::Variant::RFC4122
            || uuid.to_string() != value
        {
            return Err(CurrentError::InvalidEpoch);
        }
        Ok(Self(uuid))
    }
}

impl Serialize for RuntimeEpoch {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for RuntimeEpoch {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        String::deserialize(deserializer)?
            .parse()
            .map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadCurrent {
    pub schema_version: u32,
    pub thread_id: String,
    pub saved_runtime_epoch: RuntimeEpoch,
    pub snapshot_revision: u64,
    pub saved_at: i64,
    pub state: ThreadCurrentState,
    pub model_call: Option<CurrentModelCall>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentModelCall {
    pub source_run_id: RuntimeEpoch,
    pub source_execution_id: String,
    pub source_turn_id: String,
    pub source_attempt_id: String,
    pub tools: Arc<[ModelToolDeclaration]>,
    pub tool_call_mode: ToolCallMode,
    pub solo_tool_ids: Arc<[String]>,
    pub prepared_parameters: Option<OpaquePayload>,
    pub phase: SavedModelPhase,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum SavedModelPhase {
    Preparing {
        pending_step_input: Option<PendingStepInput>,
    },
    Streaming {
        stream: OpaquePayload,
    },
    Applied,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PendingStepInput {
    pub content: Vec<ContextContent>,
}

/// Persistent view of existing business facts, excluding history fences and live authority.
/// Task and usage adapters deliberately do not change the old checkpoint's serde contract.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadCurrentState {
    pub lifecycle: ThreadLifecycle,
    pub execution: Option<ActiveExecution>,
    #[serde(with = "serde_views::continuation")]
    pub continuation: Option<ContinuationPoint>,
    #[serde(default)]
    pub continuation_operations: std::collections::VecDeque<super::ContinuationOperation>,
    #[serde(with = "serde_views::inputs")]
    pub inputs: Arc<[input::InputRecord]>,
    pub input_ordinal: u64,
    pub terminal_inputs: Arc<[input::InputIdentity]>,
    pub context: ContextSnapshot,
    pub private_context: Option<OpaquePayload>,
    #[serde(with = "serde_views::tasks")]
    pub tasks: BTreeMap<String, task::TaskRecord>,
    pub task_start_ordinal: u64,
    pub tool_previews: BTreeMap<String, SavedToolProgress>,
    pub deliveries: Arc<[ToolDelivery]>,
    pub discovered_tools: Arc<[ModelToolDeclaration]>,
    pub runtime_facts: Arc<[RuntimeFact]>,
    pub extensions: BTreeMap<String, extensions::ExtensionRecord>,
    pub extension_sequence: u64,
    pub inbox: Arc<[inbox::InboxRecord]>,
    pub inbox_sequence: u64,
    pub consumed_messages: u64,
    pub wake_messages_through: u64,
    pub consumed_message_identities: Arc<[inbox::MessageIdentity]>,
    pub interactions: BTreeMap<String, interactions::InteractionRecord>,
    pub permissions: BTreeMap<String, permissions::PermissionRecord>,
    pub last_attempt_usage: Option<crate::model::ModelUsage>,
    pub last_attempt_usage_origin: Option<ModelUsageOrigin>,
    #[serde(with = "serde_views::usage")]
    pub usage_summary: UsageSummary,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SavedToolProgress {
    pub source_run_id: RuntimeEpoch,
    pub version: u64,
    pub parts: Vec<SavedToolProgressPart>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SavedToolProgressPart {
    pub id: String,
    pub version: u64,
    pub text: String,
}

impl SavedToolProgress {
    pub fn capture(source_run_id: RuntimeEpoch, progress: &crate::model::ToolProgress) -> Self {
        Self {
            source_run_id,
            version: progress.version(),
            parts: progress
                .parts()
                .iter()
                .map(|part| SavedToolProgressPart {
                    id: part.id().into(),
                    version: part.version(),
                    text: part.text(),
                })
                .collect(),
        }
    }

    /// Rebuilds a complete observation baseline, not an executable task or an append lineage.
    pub fn restore(&self) -> Result<crate::model::ToolProgress, CurrentError> {
        self.validate()?;
        Ok(crate::model::ToolProgress::new(
            self.version,
            self.parts
                .iter()
                .map(|part| {
                    crate::model::ToolProgressPart::from_current(
                        part.id.clone(),
                        part.version,
                        part.text.clone(),
                    )
                })
                .collect(),
        ))
    }

    fn validate(&self) -> Result<(), CurrentError> {
        let mut ids = std::collections::BTreeSet::new();
        let bytes = self.parts.iter().try_fold(0u64, |bytes, part| {
            if !ids.insert(&part.id) {
                return Err(CurrentError::InvalidToolPreview);
            }
            bytes
                .checked_add(part.text.len() as u64)
                .ok_or(CurrentError::InvalidToolPreview)
        })?;
        if bytes > crate::model::MAX_TOOL_PROGRESS_BYTES
            || self.parts.len() > crate::model::MAX_TOOL_PROGRESS_PARTS
        {
            return Err(CurrentError::InvalidToolPreview);
        }
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum CurrentError {
    #[error("unsupported current schema {0}")]
    Schema(u32),
    #[error("current Thread identity does not match {0}")]
    ThreadIdentity(String),
    #[error("runtime epoch must be a canonical UUIDv4")]
    InvalidEpoch,
    #[error("current identity is invalid or belongs to an old owner")]
    InvalidIdentity,
    #[error("current is not paused for user-authorized resume")]
    NotPaused,
    #[error("current owner operation failed: {0}")]
    Owner(#[source] Arc<super::ThreadError>),
    #[error("current context conflicts with saved record {0}")]
    RecordConflict(String),
    #[error("current state revision exhausted")]
    RevisionExhausted,
    #[error("current capture clock is outside its supported epoch-millisecond range")]
    ClockRange,
    #[error("saved tool preview exceeds its accepted bounds or has duplicate identities")]
    InvalidToolPreview,
    #[error("active model stream has no complete producer snapshot")]
    MissingStream,
    #[error("current owner has closed")]
    Closed,
    #[error("final current handoff failed: {0}")]
    Final(#[source] Arc<CurrentError>),
    #[error("current operation cancelled")]
    Cancelled,
    #[error("current capture exceeded its one-second deadline")]
    CaptureTimedOut,
    #[error("current is paused waiting for an interaction response")]
    PendingInteraction,
    #[error("current is paused waiting for a permission response")]
    PendingPermission,
    #[error(transparent)]
    Context(#[from] crate::context::ContextError),
    #[error("model current capture or binding failed: {0}")]
    Model(#[source] Arc<ModelError>),
    #[error("current encoding failed: {0}")]
    Encoding(#[from] serde_json::Error),
    #[error("current attachment could not be verified: {0}")]
    Resource(#[from] crate::context::ResourceReadError),
}

/// Pure confirmed-result pairing shared by live acceptance and paused Current reconciliation.
/// Execution authority, interaction controls and extension CAS never enter this function.
pub(in crate::thread) fn pair_known_call_result(
    context: &mut ContextSnapshot,
    record: ContextRecord,
) -> Result<bool, CurrentError> {
    let ContextSource::ToolResult { call_id, tool_id } = &record.source else {
        return Err(CurrentError::InvalidIdentity);
    };
    if let Some(existing) = context.records.iter().find(|existing| matches!(&existing.source, ContextSource::ToolResult { call_id: known, .. } if known == call_id)) {
        if existing.source != record.source || existing.content != record.content { return Err(CurrentError::RecordConflict(existing.id.clone())); }
        return Ok(false);
    }
    if context
        .records
        .iter()
        .any(|existing| existing.id == record.id)
    {
        return Err(CurrentError::RecordConflict(record.id));
    }
    let batch = context
        .records
        .iter()
        .find_map(|source| {
            source
                .tool_calls
                .iter()
                .position(|call| &call.call_id == call_id && &call.tool_id == tool_id)
                .map(|ordinal| (&source.tool_calls, ordinal))
        })
        .ok_or(CurrentError::InvalidIdentity)?;
    let insertion = context
        .records
        .iter()
        .position(|existing| match &existing.source {
            ContextSource::ToolResult { call_id: known, .. } => batch
                .0
                .iter()
                .position(|call| &call.call_id == known)
                .is_some_and(|ordinal| ordinal > batch.1),
            _ => false,
        })
        .unwrap_or(context.records.len());
    let revision = context
        .revision
        .checked_add(1)
        .ok_or(CurrentError::RevisionExhausted)?;
    let mut records = context.records.to_vec();
    records.insert(insertion, record);
    *context = ContextSnapshot {
        revision,
        records: records.into(),
    };
    Ok(true)
}

impl ThreadCurrentState {
    /// Moves no live capability across owners. Source execution and lifecycle are retained by the
    /// caller as observations; the new physical owner starts open, without an active execution.
    pub fn to_paused_snapshot(&self) -> ThreadSnapshot {
        ThreadSnapshot {
            lifecycle: ThreadLifecycle::Open,
            continuation: self.continuation.clone(),
            continuation_operations: self.continuation_operations.clone(),
            inputs: self.inputs.clone(),
            input_ordinal: self.input_ordinal,
            terminal_inputs: self.terminal_inputs.clone(),
            context: self.context.clone(),
            private_context: self.private_context.clone(),
            tasks: self.tasks.clone(),
            deliveries: self.deliveries.clone(),
            discovered_tools: self.discovered_tools.clone(),
            runtime_facts: self.runtime_facts.clone(),
            extensions: self.extensions.clone(),
            extension_sequence: self.extension_sequence,
            inbox: self.inbox.clone(),
            inbox_sequence: self.inbox_sequence,
            consumed_messages: self.consumed_messages,
            wake_messages_through: self.wake_messages_through,
            consumed_message_identities: self.consumed_message_identities.clone(),
            interactions: self.interactions.clone(),
            permissions: self.permissions.clone(),
            last_attempt_usage: self.last_attempt_usage.clone(),
            last_attempt_usage_origin: self.last_attempt_usage_origin.clone(),
            usage_summary: {
                let mut summary = self.usage_summary.clone();
                summary.applied_sequence = 0;
                summary
            },
            ..Default::default()
        }
    }

    /// Explicit old-state conversion. Legacy start sequences become relative local start order;
    /// the old record and its checkpoint encoding remain untouched for existing consumers.
    pub fn from_snapshot(
        state: &ThreadSnapshot,
        epoch: RuntimeEpoch,
    ) -> Result<Self, CurrentError> {
        let mut tasks = state.tasks.clone();
        let mut ordered = tasks.values_mut().collect::<Vec<_>>();
        ordered.sort_by(|left, right| {
            left.started_sequence
                .cmp(&right.started_sequence)
                .then_with(|| left.id.cmp(&right.id))
        });
        let task_start_ordinal = ordered.len() as u64;
        for (index, task) in ordered.into_iter().enumerate() {
            task.started_sequence = Some(index as u64 + 1);
        }
        let mut tool_previews = BTreeMap::new();
        for (id, task) in &tasks {
            let Some(progress) = state.tool_progress.get(id) else {
                continue;
            };
            let saved = SavedToolProgress::capture(epoch, progress);
            saved.validate()?;
            tool_previews.insert(task.call_id.clone(), saved);
        }
        let continuation = state.continuation.clone();
        let mut usage_summary = state.usage_summary.clone();
        usage_summary.applied_sequence = 0;
        Ok(Self {
            lifecycle: state.lifecycle,
            execution: state.execution.clone(),
            continuation,
            continuation_operations: state.continuation_operations.clone(),
            inputs: state.inputs.clone(),
            input_ordinal: state.input_ordinal,
            terminal_inputs: state.terminal_inputs.clone(),
            context: state.context.clone(),
            private_context: state.private_context.clone(),
            tasks,
            task_start_ordinal,
            tool_previews,
            deliveries: state.deliveries.clone(),
            discovered_tools: state.discovered_tools.clone(),
            runtime_facts: state.runtime_facts.clone(),
            extensions: state.extensions.clone(),
            extension_sequence: state.extension_sequence,
            inbox: state.inbox.clone(),
            inbox_sequence: state.inbox_sequence,
            consumed_messages: state.consumed_messages,
            wake_messages_through: state.wake_messages_through,
            consumed_message_identities: state.consumed_message_identities.clone(),
            interactions: state.interactions.clone(),
            permissions: state.permissions.clone(),
            last_attempt_usage: state.last_attempt_usage.clone(),
            last_attempt_usage_origin: state.last_attempt_usage_origin.clone(),
            usage_summary,
        })
    }

    /// New-current task start uses the same business field as a local ordinal, not a history fence.
    pub fn start_task(&mut self, mut record: task::TaskRecord) -> Result<(), CurrentError> {
        if self.tasks.contains_key(&record.id) {
            return Err(CurrentError::InvalidIdentity);
        }
        let order = self
            .task_start_ordinal
            .checked_add(1)
            .ok_or(CurrentError::RevisionExhausted)?;
        record.started_sequence = Some(order);
        self.tasks.insert(record.id.clone(), record);
        self.task_start_ordinal = order;
        Ok(())
    }

    fn append_record(&mut self, record: ContextRecord) -> Result<bool, CurrentError> {
        if let Some(existing) = self
            .context
            .records
            .iter()
            .find(|existing| existing.id == record.id)
        {
            return if existing == &record {
                Ok(false)
            } else {
                Err(CurrentError::RecordConflict(record.id))
            };
        }
        let revision = self
            .context
            .revision
            .checked_add(1)
            .ok_or(CurrentError::RevisionExhausted)?;
        let mut records = self.context.records.to_vec();
        records.push(record);
        self.context = ContextSnapshot {
            revision,
            records: records.into(),
        };
        Ok(true)
    }
}

impl ThreadCurrent {
    pub fn from_json(bytes: &[u8], thread_id: &str) -> Result<Self, CurrentError> {
        let mut current: Self = serde_json::from_slice(bytes)?;
        // Older saves can contain previews after their tasks left Current.
        let task_calls = current
            .state
            .tasks
            .values()
            .map(|task| task.call_id.as_str())
            .collect::<BTreeSet<_>>();
        current
            .state
            .tool_previews
            .retain(|call_id, _| task_calls.contains(call_id.as_str()));
        current.validate(thread_id)?;
        Ok(current)
    }

    pub fn new(thread_id: String, epoch: RuntimeEpoch) -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            thread_id,
            saved_runtime_epoch: epoch,
            snapshot_revision: 0,
            saved_at: 0,
            state: ThreadCurrentState::default(),
            model_call: None,
        }
    }

    pub fn validate(&self, thread_id: &str) -> Result<(), CurrentError> {
        if self.schema_version != CURRENT_SCHEMA_VERSION {
            return Err(CurrentError::Schema(self.schema_version));
        }
        if thread_id.is_empty() || self.thread_id != thread_id {
            return Err(CurrentError::ThreadIdentity(thread_id.into()));
        }
        if self.state.continuation_operations.len() > 64 {
            return Err(CurrentError::InvalidIdentity);
        }
        let mut operations = std::collections::BTreeSet::new();
        for operation in &self.state.continuation_operations {
            if operation.request.operation_id.is_empty()
                || operation.request.expected_continuation_token.is_empty()
                || operation.execution_id.is_empty()
                || operation.turn_id.is_empty()
                || !operations.insert(&operation.request.operation_id)
            {
                return Err(CurrentError::InvalidIdentity);
            }
        }
        self.state.context.pending_calls()?;
        for preview in self.state.tool_previews.values() {
            preview.validate()?;
        }
        if let Some(call) = &self.model_call
            && (call.source_execution_id.is_empty()
                || call.source_attempt_id.is_empty()
                || call.source_turn_id.is_empty())
        {
            return Err(CurrentError::InvalidIdentity);
        }
        Ok(())
    }

    /// Activates a *paused* logical object. Source identities and old observations remain unchanged.
    /// This does not construct a session, task, executor, permission lease or model request.
    pub fn activate_paused(mut self, thread_id: &str) -> Result<Self, CurrentError> {
        self.validate(thread_id)?;
        self.saved_runtime_epoch = RuntimeEpoch::new();
        self.snapshot_revision = 0;
        self.state.inputs = self
            .state
            .inputs
            .iter()
            .filter(|record| record.input.purpose == input::InputPurpose::Message)
            .cloned()
            .collect::<Vec<_>>()
            .into();
        self.state.terminal_inputs = self
            .state
            .terminal_inputs
            .iter()
            .filter(|identity| identity.purpose == input::InputPurpose::Message)
            .cloned()
            .collect::<Vec<_>>()
            .into();
        if self.state.continuation.is_none()
            && (self.state.execution.is_some()
                || self.model_call.is_some()
                || !self.state.inputs.is_empty())
        {
            self.state.continuation = Some(ContinuationPoint::new(
                0,
                "restored",
                self.state
                    .execution
                    .as_ref()
                    .and_then(|e| e.turn_id.clone()),
                Some(super::ContinuationReason::ProcessInterrupted),
            ));
        }

        for operation in &mut self.state.continuation_operations {
            if operation.disposition == super::ContinuationDisposition::Scheduled {
                operation.disposition = super::ContinuationDisposition::NotExecuted(
                    super::ContinuationNotExecuted::RestoredPaused,
                );
            }
        }

        if let Some(point) = &mut self.state.continuation {
            point.id = uuid::Uuid::new_v4().to_string();
        }
        Ok(self)
    }

    /// Contents required to resume this current, including producer-owned opaque projections.
    /// Producers decode only their own formats; Core never interprets unknown opaque payloads.
    pub fn recovery_contents(&self) -> Vec<&ContextContent> {
        let mut content = self
            .state
            .context
            .records
            .iter()
            .flat_map(|record| &record.content)
            .collect::<Vec<_>>();
        content.extend(
            self.state
                .inputs
                .iter()
                .flat_map(|record| &record.input.context),
        );
        content.extend(
            self.state
                .inbox
                .iter()
                .flat_map(|record| &record.message.context),
        );
        content.extend(self.state.deliveries.iter().flat_map(|delivery| {
            delivery
                .output
                .context()
                .iter()
                .chain(&delivery.delivered_context)
        }));
        content.extend(
            self.state
                .runtime_facts
                .iter()
                .flat_map(|fact| &fact.content),
        );
        if let Some(CurrentModelCall {
            phase:
                SavedModelPhase::Preparing {
                    pending_step_input: Some(input),
                },
            ..
        }) = &self.model_call
        {
            content.extend(&input.content);
        }
        content
    }

    /// Validates direct resource references through the existing service, without history lookup.
    /// The owning producer additionally validates resource references inside its opaque formats.
    pub async fn validate_resources(
        &self,
        resources: &crate::context::ResourceAccess,
        cancellation: CancellationToken,
    ) -> Result<(), CurrentError> {
        for item in self.recovery_contents() {
            if let ContextContent::Resource { reference } = item {
                resources.read(reference, cancellation.clone()).await?;
            }
        }
        Ok(())
    }

    /// Known local results are applied before unknown-call pairing. Clearing deliveries and
    /// installing context/inbox happen in one synchronous replacement of the logical state.
    pub fn apply_saved_local_deliveries_once(&mut self) -> Result<(), CurrentError> {
        let mut next = self.state.clone();
        for delivery in self.state.deliveries.iter() {
            match &delivery.target {
                ToolDeliveryTarget::CallResult => {
                    let turn_id = next
                        .context
                        .records
                        .iter()
                        .find(|record| {
                            record
                                .tool_calls
                                .iter()
                                .any(|call| call.call_id == delivery.call_id)
                        })
                        .and_then(|record| record.turn_id.clone());
                    pair_known_call_result(
                        &mut next.context,
                        ContextRecord {
                            id: format!("current:result:{}", delivery.call_id),
                            turn_id,
                            source: ContextSource::ToolResult {
                                call_id: delivery.call_id.clone(),
                                tool_id: delivery.tool_id.clone(),
                            },
                            content: delivery.delivered_context.clone(),
                            tool_calls: Vec::new(),
                        },
                    )?;
                }
                ToolDeliveryTarget::Inbox { message_id } => {
                    deliver_message(
                        &mut next,
                        message_id,
                        delivery,
                        format!("task:{}", delivery.call_id),
                    )?;
                }
                ToolDeliveryTarget::Nested { parent_call_id } => {
                    // The old parent's future is not revived. Preserve its exact known child result
                    // as a runtime report for the fresh request, never as a second parent ToolResult.
                    let id = format!("current:nested:{}", delivery.call_id);
                    deliver_message(&mut next, &id, delivery, format!("nested:{parent_call_id}"))?;
                }
            }
            if let Some(task) = next
                .tasks
                .values_mut()
                .find(|task| task.call_id == delivery.call_id)
            {
                task.status = task::TaskStatus::from_outcome(&delivery.outcome);
            }
        }
        next.deliveries = Arc::from([]);
        self.state = next;
        Ok(())
    }

    /// Protocol pairing only: does not create a tool/attempt/turn terminal fact or execute anything.
    pub fn normalize_unpaired_old_calls_as_unknown(&mut self) -> Result<(), CurrentError> {
        let pending = self.state.context.pending_calls()?;
        let mut next = self.state.clone();
        for call in pending {
            let turn_id = next
                .context
                .records
                .iter()
                .find(|record| {
                    record
                        .tool_calls
                        .iter()
                        .any(|old| old.call_id == call.call_id)
                })
                .and_then(|record| record.turn_id.clone());
            next.append_record(ContextRecord {
                id: format!("current:unknown:{}", call.call_id),
                turn_id,
                source: ContextSource::ToolResult {
                    call_id: call.call_id,
                    tool_id: call.tool_id,
                },
                content: vec![ContextContent::Text {
                    text: Arc::from(
                        "上次运行的结果未知；恢复未重新执行该操作；继续前须核验实际状态。",
                    ),
                }],
                tool_calls: Vec::new(),
            })?;
        }
        for task in self.state.tasks.values().filter(|task| {
            task.acknowledgement.is_some() && task.status == task::TaskStatus::Running
        }) {
            // An acknowledgement already closed its protocol call; final background uncertainty
            // is a runtime note, not another result for the same call.
            if !self
                .state
                .inbox
                .iter()
                .any(|message| message.message.source_id == task.id)
                && !self.state.context.records.iter().any(|record| {
                    matches!(&record.source,
                    ContextSource::AgentMessage { source_id, .. } if source_id == &task.id)
                })
            {
                next.append_record(ContextRecord { id: format!("current:background-unknown:{}", task.call_id),
                    turn_id: Some(task.turn_id.clone()), source: ContextSource::Runtime { source_id: task.id.clone() },
                    content: vec![ContextContent::Text { text: Arc::from("上次运行的后台操作结果未知；恢复未重新执行该操作；继续前须核验实际状态。") }], tool_calls: Vec::new() })?;
            }
        }
        next.context.validate_complete()?;
        self.state = next;
        Ok(())
    }

    /// Local recovery precedes model compatibility and request creation. No external work or
    /// historical terminal publication occurs; an unavailable provider cannot undo these facts.
    pub fn reconcile_saved_local_state(&mut self) -> Result<(), CurrentError> {
        self.apply_saved_local_deliveries_once()?;
        self.normalize_unpaired_old_calls_as_unknown()
    }

    pub(crate) fn check_model_waits(&self) -> Result<(), CurrentError> {
        if self
            .state
            .interactions
            .values()
            .any(|record| record.state == interactions::InteractionState::Pending)
        {
            return Err(CurrentError::PendingInteraction);
        }
        if self
            .state
            .permissions
            .values()
            .any(|record| record.state == permissions::PermissionState::Pending)
        {
            return Err(CurrentError::PendingPermission);
        }
        Ok(())
    }
}

pub(crate) fn is_uuid_v4(id: &str) -> bool {
    Uuid::parse_str(id).is_ok_and(|uuid| {
        uuid.get_version_num() == 4
            && uuid.get_variant() == uuid::Variant::RFC4122
            && uuid.to_string() == id
    })
}

fn deliver_message(
    state: &mut ThreadCurrentState,
    id: &str,
    delivery: &ToolDelivery,
    source_id: String,
) -> Result<(), CurrentError> {
    let context = if delivery.delivered_context.is_empty() {
        delivery.output.context().to_vec()
    } else {
        delivery.delivered_context.clone()
    };
    let message = inbox::ThreadMessage {
        id: id.into(),
        source_id,
        kind: crate::context::AgentMessageKind::Report,
        payload: delivery.output.payload().clone(),
        context,
    };
    if let Some(existing) = state.inbox.iter().find(|record| record.message.id == id) {
        if existing.message != message {
            return Err(CurrentError::RecordConflict(id.into()));
        }
        return Ok(());
    }
    if let Some(existing) = state
        .consumed_message_identities
        .iter()
        .find(|identity| identity.id == id)
    {
        return if existing.digest == message.digest() {
            Ok(())
        } else {
            Err(CurrentError::RecordConflict(id.into()))
        };
    }
    let sequence = state
        .inbox_sequence
        .checked_add(1)
        .ok_or(CurrentError::RevisionExhausted)?;
    let mut records = state.inbox.to_vec();
    records.push(inbox::InboxRecord { sequence, message });
    state.inbox = records.into();
    state.inbox_sequence = sequence;
    state.wake_messages_through = sequence;
    Ok(())
}
