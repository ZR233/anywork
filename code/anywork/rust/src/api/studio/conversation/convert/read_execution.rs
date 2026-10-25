use super::super::read::execution as bridge;
use pl_protocol::thread_facets::read::execution as protocol;

impl From<protocol::TurnReadCancellationCause> for bridge::BridgeTurnReadCancellationCause {
    fn from(value: protocol::TurnReadCancellationCause) -> Self {
        match value {
            protocol::TurnReadCancellationCause::Unspecified => Self::Unspecified,
            protocol::TurnReadCancellationCause::UserRequested => Self::UserRequested,
            protocol::TurnReadCancellationCause::RuntimeShutdown => Self::RuntimeShutdown,
            protocol::TurnReadCancellationCause::AgentClosed => Self::AgentClosed,
            protocol::TurnReadCancellationCause::Interrupted => Self::Interrupted,
            protocol::TurnReadCancellationCause::Recovery => Self::Recovery,
            protocol::TurnReadCancellationCause::Coalesced { target_turn_id } => Self::Coalesced {
                target_turn_id: target_turn_id.into(),
            },
        }
    }
}

impl From<protocol::TurnReadRolloverOutcome> for bridge::BridgeTurnReadRolloverOutcome {
    fn from(value: protocol::TurnReadRolloverOutcome) -> Self {
        match value {
            protocol::TurnReadRolloverOutcome::NotAttempted => Self::NotAttempted,
            protocol::TurnReadRolloverOutcome::Succeeded => Self::Succeeded,
            protocol::TurnReadRolloverOutcome::Failed { error } => Self::Failed {
                error: error.into(),
            },
        }
    }
}

impl From<protocol::TurnReadFailure> for bridge::BridgeTurnReadFailure {
    fn from(value: protocol::TurnReadFailure) -> Self {
        Self {
            category: value.category.into(),
            provider_kind: value.provider_kind.map(Into::into),
            code: value.code.map(Into::into),
            http_status: value.http_status,
            message: value.message.into(),
            retry: value.retry.into(),
        }
    }
}

impl From<protocol::TurnReadState> for bridge::BridgeTurnReadState {
    fn from(value: protocol::TurnReadState) -> Self {
        match value {
            protocol::TurnReadState::Queued { queued_at } => Self::Queued { queued_at },
            protocol::TurnReadState::Running { started_at, phase } => Self::Running {
                started_at,
                phase: phase.into(),
            },
            protocol::TurnReadState::Completed {
                started_at,
                completed_at,
                completion,
            } => Self::Completed {
                started_at,
                completed_at,
                completion: completion.into(),
            },
            protocol::TurnReadState::Cancelled {
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
            protocol::TurnReadState::Failed {
                started_at,
                completed_at,
                failure,
            } => Self::Failed {
                started_at,
                completed_at,
                failure: failure.into(),
            },
            protocol::TurnReadState::BudgetLimited {
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

impl From<protocol::TurnReadHeader> for bridge::BridgeTurnReadHeader {
    fn from(value: protocol::TurnReadHeader) -> Self {
        Self {
            scope: value.scope.into(),
            input_id: value.input_id.map(Into::into),
            id: value.id.into(),
            thread_id: value.thread_id.into(),
            revision: value.revision,
            updated_at: value.updated_at,
            state: value.state.into(),
        }
    }
}

impl From<protocol::InteractionIndexReadHeader> for bridge::BridgeInteractionIndexReadHeader {
    fn from(value: protocol::InteractionIndexReadHeader) -> Self {
        Self {
            scope: value.scope.into(),
            total: value.total,
            pending: value.pending,
        }
    }
}

impl From<protocol::InteractionBriefPage> for bridge::BridgeInteractionBriefPage {
    fn from(value: protocol::InteractionBriefPage) -> Self {
        Self {
            scope: value.scope.into(),
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::WaitReadIntent> for bridge::BridgeWaitReadIntent {
    fn from(value: protocol::WaitReadIntent) -> Self {
        match value {
            protocol::WaitReadIntent::Events {
                target_count,
                timeout_ms,
            } => Self::Events {
                target_count,
                timeout_ms,
            },
            protocol::WaitReadIntent::Timer { duration_ms } => Self::Timer { duration_ms },
        }
    }
}

impl From<protocol::WaitReadValue> for bridge::BridgeWaitReadValue {
    fn from(value: protocol::WaitReadValue) -> Self {
        Self {
            intent: value.intent.into(),
            state: value.state.into(),
            messages_ready: value.messages_ready,
        }
    }
}

impl From<protocol::ActivityToolReadItem> for bridge::BridgeActivityToolReadItem {
    fn from(value: protocol::ActivityToolReadItem) -> Self {
        Self {
            call_id: value.call_id.into(),
            task_id: value.task_id.map(Into::into),
            name: value.name.into(),
            summary: value.summary.into(),
            arguments: value.arguments.into(),
            state: value.state.into(),
            ordinal: value.ordinal,
            started_at: value.started_at,
            wait: value.wait.map(Into::into),
        }
    }
}

impl From<protocol::IndexedActivityToolReadItem> for bridge::BridgeIndexedActivityToolReadItem {
    fn from(value: protocol::IndexedActivityToolReadItem) -> Self {
        Self {
            index: value.index,
            call_id: value.call_id.into(),
            task_id: value.task_id.map(Into::into),
            name: value.name.into(),
            summary: value.summary.into(),
            arguments: value.arguments.into(),
            state: value.state.into(),
            ordinal: value.ordinal,
            started_at: value.started_at,
            wait: value.wait.map(Into::into),
        }
    }
}

impl From<protocol::ActivityReadHeader> for bridge::BridgeActivityReadHeader {
    fn from(value: protocol::ActivityReadHeader) -> Self {
        Self {
            scope: value.scope.into(),
            thread_id: value.thread_id.into(),
            identity: value.identity.into(),
            turn_id: value.turn_id.into(),
            revision: value.revision,
            input_id: value.input_id.map(Into::into),
            attempt_id: value.attempt_id.map(Into::into),
            kind: value.kind.into(),
            summary: value.summary.into(),
            summary_truncated: value.summary_truncated,
            count: value.count,
            background: value.background,
            active_count: value.active_count,
            latest_started: value.latest_started.map(Into::into),
        }
    }
}

impl From<protocol::WaitTargetReadItem> for bridge::BridgeWaitTargetReadItem {
    fn from(value: protocol::WaitTargetReadItem) -> Self {
        Self {
            index: value.index,
            task_id: value.task_id.into(),
            tool_name: value.tool_name.map(Into::into),
            summary: value.summary.map(Into::into),
            summary_truncated: value.summary_truncated,
            status: value.status.map(Into::into),
        }
    }
}

impl From<protocol::ActivityToolPage> for bridge::BridgeActivityToolPage {
    fn from(value: protocol::ActivityToolPage) -> Self {
        Self {
            scope: value.scope.into(),
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::WaitTargetPage> for bridge::BridgeWaitTargetPage {
    fn from(value: protocol::WaitTargetPage) -> Self {
        Self {
            scope: value.scope.into(),
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::StorageReadHeader> for bridge::BridgeStorageReadHeader {
    fn from(value: protocol::StorageReadHeader) -> Self {
        Self {
            scope: value.scope.into(),
            fault: value.fault.map(Into::into),
            fault_generation: value.fault_generation,
            accepted_sequence: value.accepted_sequence,
            durable_sequence: value.durable_sequence,
            execution: value.execution.into(),
            pressure_paused: value.pressure_paused,
            resume_required: value.resume_required,
            can_resume: value.can_resume,
            last_error: value.last_error.map(Into::into),
        }
    }
}
