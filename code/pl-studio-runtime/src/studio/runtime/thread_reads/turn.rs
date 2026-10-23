use std::sync::Arc;

use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::execution::{TurnReadCancellationCause, TurnReadFailure,
    TurnReadHeader, TurnReadRolloverOutcome, TurnReadState};
use pl_protocol::{Turn, TurnCancellationCause, TurnRolloverOutcome, TurnState};

use super::super::read_budget::{FieldTable, bounded_header, protocol, text_chunk};
use super::budget::validate_revision;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Field { InputId, Id, ThreadId, FailureCode, FailureMessage, CoalescedTarget, RolloverError }

pub(super) struct TurnMaterial {
    scope: ReadScopeIdentity,
    source: Arc<Turn>,
    fields: FieldTable<Field>,
}

impl TurnMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, source: Arc<Turn>) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        Ok(Self { scope, source, fields: FieldTable::default() })
    }

    pub(super) fn header(&self) -> Result<TurnReadHeader, StudioError> {
        bounded_header(|inline| {
            let state = match &self.source.state {
                TurnState::Queued(value) => TurnReadState::Queued { queued_at: value.queued_at() },
                TurnState::Running(value) => TurnReadState::Running {
                    started_at: value.started_at(), phase: value.phase(),
                },
                TurnState::Completed(value) => TurnReadState::Completed {
                    started_at: value.started_at(), completed_at: value.completed_at(), completion: value.completion(),
                },
                TurnState::Cancelled(value) => TurnReadState::Cancelled {
                    started_at: value.started_at(), requested_at: value.requested_at(), completed_at: value.completed_at(),
                    cause: match value.cause() {
                        TurnCancellationCause::Unspecified => TurnReadCancellationCause::Unspecified,
                        TurnCancellationCause::UserRequested => TurnReadCancellationCause::UserRequested,
                        TurnCancellationCause::RuntimeShutdown => TurnReadCancellationCause::RuntimeShutdown,
                        TurnCancellationCause::AgentClosed => TurnReadCancellationCause::AgentClosed,
                        TurnCancellationCause::Interrupted => TurnReadCancellationCause::Interrupted,
                        TurnCancellationCause::Recovery => TurnReadCancellationCause::Recovery,
                        TurnCancellationCause::Coalesced { .. } => TurnReadCancellationCause::Coalesced {
                            target_turn_id: self.read(Field::CoalescedTarget, inline)?,
                        },
                    },
                },
                TurnState::Failed(value) => TurnReadState::Failed {
                    started_at: value.started_at(), completed_at: value.completed_at(),
                    failure: TurnReadFailure {
                        category: value.failure().category, provider_kind: value.failure().provider_kind,
                        code: value.failure().code.as_ref().map(|_| self.read(Field::FailureCode, inline)).transpose()?,
                        http_status: value.failure().http_status, message: self.read(Field::FailureMessage, inline)?,
                        retry: value.failure().retry.clone(),
                    },
                },
                TurnState::BudgetLimited(value) => TurnReadState::BudgetLimited {
                    started_at: value.started_at(), completed_at: value.completed_at(), limit: value.limit().clone(),
                    rollover: match value.rollover() {
                        TurnRolloverOutcome::NotAttempted => TurnReadRolloverOutcome::NotAttempted,
                        TurnRolloverOutcome::Succeeded => TurnReadRolloverOutcome::Succeeded,
                        TurnRolloverOutcome::Failed { .. } => TurnReadRolloverOutcome::Failed {
                            error: self.read(Field::RolloverError, inline)?,
                        },
                    },
                },
            };
            Ok(TurnReadHeader {
                scope: self.scope.clone(),
                input_id: self.source.input_id.as_ref().map(|_| self.read(Field::InputId, inline)).transpose()?,
                id: self.read(Field::Id, inline)?, thread_id: self.read(Field::ThreadId, inline)?,
                revision: self.source.revision, updated_at: self.source.updated_at, state,
            })
        })
    }

    pub(super) fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        text_chunk(field_id, self.source_text(self.fields.field(field_id)?)?, offset, max_bytes)
    }

    fn read(&self, field: Field, inline: usize) -> Result<ReadText, StudioError> {
        self.fields.read(field, self.source_text(field)?, inline)
    }

    fn source_text(&self, field: Field) -> Result<&str, StudioError> {
        let value = match field {
            Field::InputId => self.source.input_id.as_deref(),
            Field::Id => Some(self.source.id.as_str()),
            Field::ThreadId => Some(self.source.thread_id.as_str()),
            Field::FailureCode => self.source.failure().and_then(|failure| failure.code.as_deref()),
            Field::FailureMessage => self.source.failure().map(|failure| failure.message.as_str()),
            Field::CoalescedTarget => match &self.source.state {
                TurnState::Cancelled(value) => match value.cause() {
                    TurnCancellationCause::Coalesced { target_turn_id } => Some(target_turn_id.as_str()),
                    TurnCancellationCause::Unspecified | TurnCancellationCause::UserRequested |
                    TurnCancellationCause::RuntimeShutdown | TurnCancellationCause::AgentClosed |
                    TurnCancellationCause::Interrupted | TurnCancellationCause::Recovery => None,
                },
                TurnState::Queued(_) | TurnState::Running(_) | TurnState::Completed(_) |
                TurnState::Failed(_) | TurnState::BudgetLimited(_) => None,
            },
            Field::RolloverError => match &self.source.state {
                TurnState::BudgetLimited(value) => match value.rollover() {
                    TurnRolloverOutcome::Failed { error } => Some(error.as_str()),
                    TurnRolloverOutcome::NotAttempted | TurnRolloverOutcome::Succeeded => None,
                },
                TurnState::Queued(_) | TurnState::Running(_) | TurnState::Completed(_) |
                TurnState::Cancelled(_) | TurnState::Failed(_) => None,
            },
        };
        value.ok_or_else(|| protocol("Text field does not address the pinned Turn schema"))
    }
}
