use super::super::execution as bridge;
use pl_protocol::thread_facets::execution as protocol;

impl From<protocol::TurnCancellationKind> for bridge::BridgeTurnCancellationKind {
    fn from(value: protocol::TurnCancellationKind) -> Self {
        match value {
            protocol::TurnCancellationKind::Unspecified => Self::Unspecified,
            protocol::TurnCancellationKind::UserRequested => Self::UserRequested,
            protocol::TurnCancellationKind::RuntimeShutdown => Self::RuntimeShutdown,
            protocol::TurnCancellationKind::AgentClosed => Self::AgentClosed,
            protocol::TurnCancellationKind::Interrupted => Self::Interrupted,
            protocol::TurnCancellationKind::Recovery => Self::Recovery,
            protocol::TurnCancellationKind::Coalesced => Self::Coalesced,
        }
    }
}

impl From<protocol::TurnRolloverKind> for bridge::BridgeTurnRolloverKind {
    fn from(value: protocol::TurnRolloverKind) -> Self {
        match value {
            protocol::TurnRolloverKind::NotAttempted => Self::NotAttempted,
            protocol::TurnRolloverKind::Succeeded => Self::Succeeded,
            protocol::TurnRolloverKind::Failed => Self::Failed,
        }
    }
}

impl From<protocol::TurnBriefState> for bridge::BridgeTurnBriefState {
    fn from(value: protocol::TurnBriefState) -> Self {
        match value {
            protocol::TurnBriefState::Queued { queued_at } => Self::Queued { queued_at },
            protocol::TurnBriefState::Running { started_at, phase } => Self::Running {
                started_at,
                phase: phase.into(),
            },
            protocol::TurnBriefState::Completed {
                started_at,
                completed_at,
                completion,
            } => Self::Completed {
                started_at,
                completed_at,
                completion: completion.into(),
            },
            protocol::TurnBriefState::Cancelled {
                started_at,
                requested_at,
                completed_at,
                cause,
            } => Self::Cancelled {
                started_at,
                requested_at,
                completed_at,
                cause: cause.into(),
            },
            protocol::TurnBriefState::Failed {
                started_at,
                completed_at,
                category,
                provider_kind,
                http_status,
                retry,
            } => Self::Failed {
                started_at,
                completed_at,
                category: category.into(),
                provider_kind: provider_kind.map(Into::into),
                http_status,
                retry: retry.into(),
            },
            protocol::TurnBriefState::BudgetLimited {
                started_at,
                completed_at,
                limit,
                rollover,
            } => Self::BudgetLimited {
                started_at,
                completed_at,
                limit: limit.into(),
                rollover: rollover.into(),
            },
        }
    }
}

impl From<protocol::TurnBrief> for bridge::BridgeTurnBrief {
    fn from(value: protocol::TurnBrief) -> Self {
        Self {
            reference: value.reference.into(),
            revision: value.revision,
            updated_at: value.updated_at,
            state: value.state.into(),
        }
    }
}

impl From<pl_protocol::InteractionKind> for bridge::BridgeInteractionKind {
    fn from(value: pl_protocol::InteractionKind) -> Self {
        match value {
            pl_protocol::InteractionKind::UserInput => Self::UserInput,
            pl_protocol::InteractionKind::ToolApproval => Self::ToolApproval,
        }
    }
}

impl From<pl_protocol::InteractionStatus> for bridge::BridgeInteractionStatus {
    fn from(value: pl_protocol::InteractionStatus) -> Self {
        match value {
            pl_protocol::InteractionStatus::Pending => Self::Pending,
            pl_protocol::InteractionStatus::Resolved => Self::Resolved,
            pl_protocol::InteractionStatus::Cancelled => Self::Cancelled,
            pl_protocol::InteractionStatus::Expired => Self::Expired,
        }
    }
}

impl From<protocol::InteractionBrief> for bridge::BridgeInteractionBrief {
    fn from(value: protocol::InteractionBrief) -> Self {
        Self {
            reference: value.reference.into(),
            revision: value.revision,
            kind: value.kind.into(),
            status: value.status.into(),
            created_at: value.created_at,
            updated_at: value.updated_at,
        }
    }
}

impl From<protocol::InteractionIndexHeader> for bridge::BridgeInteractionIndexHeader {
    fn from(value: protocol::InteractionIndexHeader) -> Self {
        Self {
            reference: value.reference.into(),
            total: value.total,
            pending: value.pending,
        }
    }
}

impl From<protocol::InteractionDelta> for bridge::BridgeInteractionDelta {
    fn from(value: protocol::InteractionDelta) -> Self {
        Self {
            base_index_revision: value.base_index_revision,
            index: value.index.into(),
            upserted: value.upserted.into_iter().map(Into::into).collect(),
            removed_entries: value.removed_entries,
            terminal_facts: value.terminal_facts.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<protocol::ActivityBrief> for bridge::BridgeActivityBrief {
    fn from(value: protocol::ActivityBrief) -> Self {
        Self {
            reference: value.reference.into(),
            revision: value.revision,
            kind: value.kind.into(),
            tool_count: value.tool_count,
            background_count: value.background_count,
            active_count: value.active_count,
            has_latest_started: value.has_latest_started,
        }
    }
}

impl From<protocol::StorageBrief> for bridge::BridgeStorageBrief {
    fn from(value: protocol::StorageBrief) -> Self {
        Self {
            reference: value.reference.into(),
            fault: value.fault.map(Into::into),
            fault_generation: value.fault_generation,
            accepted_sequence: value.accepted_sequence,
            durable_sequence: value.durable_sequence,
            execution: value.execution.into(),
            pressure_paused: value.pressure_paused,
            resume_required: value.resume_required,
            can_resume: value.can_resume,
            has_last_error: value.has_last_error,
        }
    }
}

impl From<protocol::ExecutionBaseline> for bridge::BridgeExecutionBaseline {
    fn from(value: protocol::ExecutionBaseline) -> Self {
        Self {
            status: value.status.into(),
            execution: value.execution.map(Into::into),
            continuation: value.continuation.map(Into::into),
            active_turn: value.active_turn.map(Into::into),
            recent_terminal_turn: value.recent_terminal_turn.map(Into::into),
            interactions: value.interactions.into(),
            activity: value.activity.map(Into::into),
            storage: value.storage.map(Into::into),
        }
    }
}

impl From<protocol::TurnsReplacement> for bridge::BridgeTurnsReplacement {
    fn from(value: protocol::TurnsReplacement) -> Self {
        Self {
            active_turn: value.active_turn.map(Into::into),
            recent_terminal_turn: value.recent_terminal_turn.map(Into::into),
        }
    }
}

impl From<protocol::ActivityReplacement> for bridge::BridgeActivityReplacement {
    fn from(value: protocol::ActivityReplacement) -> Self {
        match value {
            protocol::ActivityReplacement::Unchanged => Self::Unchanged,
            protocol::ActivityReplacement::Replace { value } => Self::Replace {
                value: value.map(Into::into),
            },
        }
    }
}

impl From<protocol::StorageReplacement> for bridge::BridgeStorageReplacement {
    fn from(value: protocol::StorageReplacement) -> Self {
        match value {
            protocol::StorageReplacement::Unchanged => Self::Unchanged,
            protocol::StorageReplacement::Replace { value } => Self::Replace {
                value: value.map(Into::into),
            },
        }
    }
}

impl From<protocol::ExecutionChange> for bridge::BridgeExecutionChange {
    fn from(value: protocol::ExecutionChange) -> Self {
        Self {
            status: value.status.map(Into::into),
            execution: match value.execution {
                protocol::ExecutionReplacement::Unchanged => {
                    bridge::BridgeExecutionReplacement::Unchanged
                }
                protocol::ExecutionReplacement::Replace { value } => {
                    bridge::BridgeExecutionReplacement::Replace {
                        value: value.map(Into::into),
                    }
                }
            },
            continuation: match value.continuation {
                protocol::ContinuationReplacement::Unchanged => {
                    bridge::BridgeContinuationReplacement::Unchanged
                }
                protocol::ContinuationReplacement::Replace { value } => {
                    bridge::BridgeContinuationReplacement::Replace {
                        value: value.map(Into::into),
                    }
                }
            },
            turns: value.turns.map(Into::into),
            interactions: value.interactions.map(Into::into),
            activity: value.activity.into(),
            storage: value.storage.into(),
        }
    }
}

impl From<protocol::ExecutionEvent> for bridge::BridgeExecutionEvent {
    fn from(value: protocol::ExecutionEvent) -> Self {
        match value {
            protocol::ExecutionEvent::Baseline {
                identity,
                stamp,
                value,
            } => Self::Baseline {
                identity: identity.into(),
                stamp: stamp.into(),
                value: value.into(),
            },
            protocol::ExecutionEvent::Change {
                stamp,
                base_revision,
                value,
            } => Self::Change {
                stamp: stamp.into(),
                base_revision,
                value: value.into(),
            },
        }
    }
}

impl From<protocol::ExecutionFrame> for bridge::BridgeExecutionFrame {
    fn from(value: protocol::ExecutionFrame) -> Self {
        match value {
            protocol::ExecutionFrame::Data {
                delivery_sequence,
                event,
            } => Self::Data {
                delivery_sequence,
                event: (*event).into(),
            },
            protocol::ExecutionFrame::ResyncRequired { identity, reason } => Self::ResyncRequired {
                identity: identity.into(),
                reason: reason.into(),
            },
            protocol::ExecutionFrame::Failure { identity, error } => Self::Failure {
                identity: identity.into(),
                error: error.into(),
            },
            protocol::ExecutionFrame::Closed { identity, reason } => Self::Closed {
                identity: identity.into(),
                reason: reason.into(),
            },
        }
    }
}
