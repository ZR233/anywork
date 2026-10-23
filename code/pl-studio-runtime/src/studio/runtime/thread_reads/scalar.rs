use std::sync::Arc;

use pl_protocol::{AgentSessionPlanDocument, WorkflowRuntimeSnapshot};
use pl_protocol::studio::{ReadText, StudioError, StudioErrorCode, TextChunk, ThreadStorageState};
use pl_protocol::thread_facets::authoring::PlanDocumentRef;
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::execution::StorageReadHeader;
use pl_protocol::thread_facets::read::values::{MetricsIdentityReadHeader, PlanDocumentReadHeader,
    PlanDocumentValue, WorkflowReadHeader, WorkflowRunReadValue};

use super::super::read_budget::{FieldTable, bounded_header, protocol, require_budget, text_chunk};
use super::budget::validate_revision;

/// An immutable identity locator; live counters and their sequence are deliberately absent.
pub(in crate::studio::runtime) struct MetricsIdentitySource {
    pub(in crate::studio::runtime) turn_id: String,
    pub(in crate::studio::runtime) attempt_id: Option<String>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum MetricsField { TurnId, AttemptId }

pub(in crate::studio::runtime) struct MetricsIdentityMaterial {
    scope: ReadScopeIdentity,
    source: Arc<MetricsIdentitySource>,
    fields: FieldTable<MetricsField>,
}

impl MetricsIdentityMaterial {
    pub(in crate::studio::runtime) fn new(scope: ReadScopeIdentity, source: Arc<MetricsIdentitySource>) -> Self {
        Self { scope, source, fields: FieldTable::default() }
    }

    pub(in crate::studio::runtime) fn header(&self) -> Result<MetricsIdentityReadHeader, StudioError> {
        bounded_header(|inline| Ok(MetricsIdentityReadHeader { scope: self.scope.clone(),
            turn_id: self.fields.read(MetricsField::TurnId, &self.source.turn_id, inline)?,
            attempt_id: self.source.attempt_id.as_ref().map(|value|
                self.fields.read(MetricsField::AttemptId, value, inline)).transpose()? }))
    }

    pub(in crate::studio::runtime) fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        let value = match self.fields.field(field_id)? {
            MetricsField::TurnId => self.source.turn_id.as_str(),
            MetricsField::AttemptId => self.source.attempt_id.as_deref()
                .ok_or_else(|| protocol("Pinned metrics identity has no attempt field"))?,
        };
        text_chunk(field_id, value, offset, max_bytes)
    }
}

pub(super) struct StorageMaterial {
    scope: ReadScopeIdentity,
    source: Arc<ThreadStorageState>,
    fields: FieldTable<()>,
}

impl StorageMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, source: Arc<ThreadStorageState>) -> Self {
        Self { scope, source, fields: FieldTable::default() }
    }

    pub(super) fn header(&self) -> Result<StorageReadHeader, StudioError> {
        bounded_header(|inline| Ok(StorageReadHeader { scope: self.scope.clone(),
            fault: self.source.fault, fault_generation: self.source.fault_generation,
            accepted_sequence: self.source.accepted_sequence, durable_sequence: self.source.durable_sequence,
            execution: self.source.execution, pressure_paused: self.source.pressure_paused,
            resume_required: self.source.resume_required, can_resume: self.source.can_resume,
            last_error: self.source.last_error.as_ref().map(|value| self.fields.read((), value, inline)).transpose()?,
        }))
    }

    pub(super) fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        self.fields.field(field_id)?;
        let value = self.source.last_error.as_deref()
            .ok_or_else(|| protocol("Pinned storage source has no error text"))?;
        text_chunk(field_id, value, offset, max_bytes)
    }
}

pub(super) struct PlanDocumentMaterial {
    scope: ReadScopeIdentity,
    source: Arc<AgentSessionPlanDocument>,
}

impl PlanDocumentMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, expected: &PlanDocumentRef,
        source: Arc<AgentSessionPlanDocument>) -> Result<Self, StudioError>
    {
        if source.version != expected.version || source.content_hash != expected.content_hash {
            return Err(StudioError::new(StudioErrorCode::Superseded,
                "The requested Plan document is no longer available", false));
        }
        Ok(Self { scope, source })
    }

    pub(super) fn header(&self) -> Result<PlanDocumentReadHeader, StudioError> {
        let value = PlanDocumentReadHeader { scope: self.scope.clone(), version: self.source.version,
            content_hash: self.source.content_hash.clone() };
        require_budget(&value)?;
        Ok(value)
    }

    pub(super) fn document(&self) -> Result<PlanDocumentValue, StudioError> {
        let value = PlanDocumentValue { scope: self.scope.clone(), version: self.source.version,
            content_hash: self.source.content_hash.clone(), markdown: self.source.markdown.clone() };
        require_budget(&value)?;
        Ok(value)
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum WorkflowField { LineageId, RunId, ModeId, GraphHash, StateId, StateTitle, ModeName }

pub(super) struct WorkflowMaterial {
    scope: ReadScopeIdentity,
    source: Arc<WorkflowRuntimeSnapshot>,
    fields: FieldTable<WorkflowField>,
}

impl WorkflowMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, source: Arc<WorkflowRuntimeSnapshot>) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        Ok(Self { scope, source, fields: FieldTable::default() })
    }

    pub(super) fn header(&self) -> Result<WorkflowReadHeader, StudioError> {
        bounded_header(|inline| {
            let current_run = self.source.current_run.as_ref().map(|value| {
                Ok::<_, StudioError>(WorkflowRunReadValue {
                    lineage_id: self.read(WorkflowField::LineageId, inline)?, run_id: self.read(WorkflowField::RunId, inline)?,
                    mode_id: self.read(WorkflowField::ModeId, inline)?, graph_revision: value.graph_revision,
                    graph_hash: self.read(WorkflowField::GraphHash, inline)?, lifecycle: value.lifecycle,
                    current_state_id: self.read(WorkflowField::StateId, inline)?, started_at: value.started_at,
                    updated_at: value.updated_at, current_state_title: self.read(WorkflowField::StateTitle, inline)?,
                    mode_display_name: self.read(WorkflowField::ModeName, inline)?, mode_deleted: value.mode_deleted,
                })
            }).transpose()?;
            Ok(WorkflowReadHeader { scope: self.scope.clone(), revision: self.source.revision, current_run })
        })
    }

    pub(super) fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        text_chunk(field_id, self.source_text(self.fields.field(field_id)?)?, offset, max_bytes)
    }

    fn read(&self, field: WorkflowField, inline: usize) -> Result<ReadText, StudioError> {
        self.fields.read(field, self.source_text(field)?, inline)
    }

    fn source_text(&self, field: WorkflowField) -> Result<&str, StudioError> {
        let value = self.source.current_run.as_ref().ok_or_else(|| protocol("Pinned Workflow has no current run"))?;
        Ok(match field {
            WorkflowField::LineageId => &value.lineage_id,
            WorkflowField::RunId => &value.run_id,
            WorkflowField::ModeId => value.mode_id.as_str(),
            WorkflowField::GraphHash => &value.graph_hash,
            WorkflowField::StateId => &value.current_state_id,
            WorkflowField::StateTitle => &value.current_state_title,
            WorkflowField::ModeName => &value.mode_display_name,
        })
    }
}
