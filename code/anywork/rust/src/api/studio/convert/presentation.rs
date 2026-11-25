//! Mechanical mappings for the independent History and Current FRB ports.

use pl_studio_runtime as protocol;
use pl_studio_runtime::history as runtime_history;

use super::{chat, thread_stream};
use crate::api::studio::types::*;

type ConvertResult<T> = Result<T, anyhow::Error>;

pub(crate) fn history_demand(value: BridgeHistoryDemand) -> runtime_history::HistoryDemand {
    runtime_history::HistoryDemand {
        max_rows: value.max_rows,
        max_bytes: value.max_bytes,
    }
}

pub(crate) fn read_demand(value: BridgeReadDemand) -> protocol::ReadDemand {
    chat::demand(value)
}

pub(crate) fn history_events_query(
    value: BridgeHistoryEventsQuery,
) -> runtime_history::HistoryEventsQuery {
    match value {
        BridgeHistoryEventsQuery::AllEvents => runtime_history::HistoryEventsQuery::AllEvents,
        BridgeHistoryEventsQuery::Entity { entity_id } => {
            runtime_history::HistoryEventsQuery::Entity { entity_id }
        }
        BridgeHistoryEventsQuery::Turn { turn_id } => {
            runtime_history::HistoryEventsQuery::Turn { turn_id }
        }
        BridgeHistoryEventsQuery::Source { source } => {
            runtime_history::HistoryEventsQuery::Source {
                source: protocol_source_id(source),
            }
        }
        BridgeHistoryEventsQuery::Call { call_id } => {
            runtime_history::HistoryEventsQuery::Call { call_id }
        }
        BridgeHistoryEventsQuery::Originals {
            query_class,
            parent_id,
        } => runtime_history::HistoryEventsQuery::Originals {
            scope: protocol::ChatScope {
                query_class: protocol::ChatClassFilter::Class { value: query_class },
                parent_id,
            },
        },
        BridgeHistoryEventsQuery::TextOriginals => {
            runtime_history::HistoryEventsQuery::TextOriginals
        }
    }
}

fn protocol_source_id(value: BridgeChatSourceId) -> protocol::ChatSourceId {
    match value {
        BridgeChatSourceId::ForegroundTurn { turn_id } => {
            protocol::ChatSourceId::ForegroundTurn { turn_id }
        }
        BridgeChatSourceId::Input { input_id } => protocol::ChatSourceId::Input { input_id },
        BridgeChatSourceId::InboxMessage {
            source_id,
            message_id,
        } => protocol::ChatSourceId::InboxMessage {
            source_id,
            message_id,
        },
        BridgeChatSourceId::BackgroundResult { message_id } => {
            protocol::ChatSourceId::BackgroundResult { message_id }
        }
        BridgeChatSourceId::Operation { operation_id } => {
            protocol::ChatSourceId::Operation { operation_id }
        }
        BridgeChatSourceId::Receipt { receipt_id } => {
            protocol::ChatSourceId::Receipt { receipt_id }
        }
    }
}

pub(crate) fn cut_to_bridge(value: runtime_history::HistoryCut) -> BridgeHistoryCut {
    BridgeHistoryCut { token: value.token }
}

fn cut(value: runtime_history::HistoryCut) -> BridgeHistoryCut {
    cut_to_bridge(value)
}

pub(crate) fn bridge_to_cut(value: BridgeHistoryCut) -> runtime_history::HistoryCut {
    runtime_history::HistoryCut { token: value.token }
}

fn body_ref(value: runtime_history::HistoryEventBodyRef) -> BridgeHistoryEventBodyRef {
    BridgeHistoryEventBodyRef {
        database_id: value.database_id,
        owner_event_id: value.owner_event_id,
        body_key: value.body_key,
        body_id: value.body_id,
        byte_start: value.byte_start,
        byte_length: value.byte_length,
    }
}

fn timeline_role(value: runtime_history::HistoryTimelineRole) -> BridgeHistoryTimelineRole {
    match value {
        runtime_history::HistoryTimelineRole::Boundary => BridgeHistoryTimelineRole::Boundary,
        runtime_history::HistoryTimelineRole::Work => BridgeHistoryTimelineRole::Work,
        runtime_history::HistoryTimelineRole::Hidden => BridgeHistoryTimelineRole::Hidden,
    }
}

fn business_row_scope(
    value: runtime_history::HistoryBusinessRowScope,
) -> BridgeHistoryBusinessRowScope {
    match value {
        runtime_history::HistoryBusinessRowScope::Turn => BridgeHistoryBusinessRowScope::Turn,
        runtime_history::HistoryBusinessRowScope::Source => BridgeHistoryBusinessRowScope::Source,
        runtime_history::HistoryBusinessRowScope::Cost => BridgeHistoryBusinessRowScope::Cost,
        runtime_history::HistoryBusinessRowScope::Accounting => {
            BridgeHistoryBusinessRowScope::Accounting
        }
    }
}

fn original_info(value: runtime_history::HistoryOriginalInfo) -> BridgeHistoryOriginalInfo {
    BridgeHistoryOriginalInfo {
        query_class: value.query_class,
        parent_id: value.parent_id,
        original_kind: chat::atom_kind(value.original_kind),
        tool_name: value.tool_name,
    }
}

pub(crate) fn event_record(value: runtime_history::HistoryEventRecord) -> BridgeHistoryEventRecord {
    BridgeHistoryEventRecord {
        seq: value.seq,
        event_id: value.event_id,
        kind: value.kind.as_str().to_owned(),
        timeline_role: timeline_role(value.timeline_role),
        occurred_at: value.occurred_at,
        recorded_at: value.recorded_at,
        run_id: value.run_id,
        turn_id: value.turn_id,
        attempt_id: value.attempt_id,
        call_id: value.call_id,
        entity_id: value.entity_id,
        message_id: value.message_id,
        tool_name: value.tool_name,
        source: value.source.map(chat::source_id),
        original: value.original.map(original_info),
        row_scope: value.row_scope.map(business_row_scope),
        row_key: value.row_key,
        payload_schema: value.payload_schema,
        payload_json: value.payload_json,
    }
}

fn timeline_entry(value: runtime_history::HistoryTimelineEntry) -> BridgeHistoryTimelineEntry {
    BridgeHistoryTimelineEntry {
        event: event_record(value.event),
        has_folded_after: value.has_folded_after,
        tail_folded_ended_at: value.tail_folded_ended_at,
    }
}

pub(crate) fn timeline_page(
    value: runtime_history::HistoryTimelinePage,
) -> BridgeHistoryTimelinePage {
    BridgeHistoryTimelinePage {
        cut: cut(value.cut),
        entries: value.entries.into_iter().map(timeline_entry).collect(),
        has_folded_before_oldest: value.has_folded_before_oldest,
        next: value.next,
    }
}

pub(crate) fn work_range_page(
    value: runtime_history::HistoryWorkRangePage,
) -> BridgeHistoryWorkRangePage {
    BridgeHistoryWorkRangePage {
        cut: cut(value.cut),
        after_seq: value.after_seq,
        before_seq: value.before_seq,
        events: value.events.into_iter().map(event_record).collect(),
        next: value.next,
    }
}

fn business_row_head(
    value: runtime_history::HistoryBusinessRowHead,
) -> BridgeHistoryBusinessRowHead {
    match value {
        runtime_history::HistoryBusinessRowHead::Turn(value) => {
            BridgeHistoryBusinessRowHead::Turn(BridgeHistoryTurnHead {
                turn_id: value.turn_id,
                input_id: value.input_id,
                run_id: value.run_id,
                state: match value.state {
                    runtime_history::HistoryTurnState::Unknown => BridgeHistoryTurnState::Unknown,
                    runtime_history::HistoryTurnState::Queued => BridgeHistoryTurnState::Queued,
                    runtime_history::HistoryTurnState::Running => BridgeHistoryTurnState::Running,
                    runtime_history::HistoryTurnState::Completed => {
                        BridgeHistoryTurnState::Completed
                    }
                    runtime_history::HistoryTurnState::Cancelled => {
                        BridgeHistoryTurnState::Cancelled
                    }
                    runtime_history::HistoryTurnState::Failed => BridgeHistoryTurnState::Failed,
                    runtime_history::HistoryTurnState::BudgetLimited => {
                        BridgeHistoryTurnState::BudgetLimited
                    }
                },
                phase: value.phase.map(thread_stream::turn_phase),
                context_disposition: match value.context_disposition {
                    protocol::ThreadContextDisposition::Active => {
                        BridgeHistoryContextDisposition::Active
                    }
                    protocol::ThreadContextDisposition::RolledBack => {
                        BridgeHistoryContextDisposition::RolledBack
                    }
                },
                queued_at: value.queued_at,
                started_at: value.started_at,
                finished_at: value.finished_at,
                updated_at: value.updated_at,
                detail_event_id: value.detail_event_id,
            })
        }
        runtime_history::HistoryBusinessRowHead::Source(value) => {
            BridgeHistoryBusinessRowHead::Source(BridgeHistorySourceHead {
                source: chat::source_id(value.source),
                lifecycle: match value.lifecycle {
                    protocol::ChatSourceLifecycle::Unknown => BridgeHistorySourceLifecycle::Unknown,
                    protocol::ChatSourceLifecycle::Active => BridgeHistorySourceLifecycle::Active,
                    protocol::ChatSourceLifecycle::Ended { outcome } => {
                        BridgeHistorySourceLifecycle::Ended {
                            outcome: chat::terminal_outcome(outcome),
                        }
                    }
                },
                started_at: value.started_at,
                ended_at: value.ended_at,
                observed_at: value.observed_at,
                detail_event_id: value.detail_event_id,
            })
        }
        runtime_history::HistoryBusinessRowHead::Cost(value) => {
            BridgeHistoryBusinessRowHead::Cost(BridgeHistoryCostHead {
                purpose: value.purpose,
                currency: value.currency,
                cost_delta: value.cost_delta,
                cost_total: value.cost_total,
                cache_savings_delta: value.cache_savings_delta,
                cache_savings_total: value.cache_savings_total,
                updated_at: value.updated_at,
                detail_event_id: value.detail_event_id,
            })
        }
        runtime_history::HistoryBusinessRowHead::Accounting(value) => {
            BridgeHistoryBusinessRowHead::Accounting(BridgeHistoryAccountingHead {
                prompt_tokens: value.prompt_tokens,
                completion_tokens: value.completion_tokens,
                cached_prompt_tokens: value.cached_prompt_tokens,
                cache_write_tokens: value.cache_write_tokens,
                reasoning_tokens: value.reasoning_tokens,
                inference_count: value.inference_count,
                total_tokens: value.total_tokens,
                cache_usage: thread_stream::cache_usage(value.cache_usage),
                has_incomplete_usage: value.has_incomplete_usage,
                has_unpriced_usage: value.has_unpriced_usage,
                updated_at: value.updated_at,
                detail_event_id: value.detail_event_id,
            })
        }
    }
}

fn business_row_entry(
    value: runtime_history::HistoryBusinessRowEntry,
) -> BridgeHistoryBusinessRowEntry {
    BridgeHistoryBusinessRowEntry {
        row_key: value.row_key,
        anchor_seq: value.anchor_seq,
        head_seq: value.head_seq,
        head: business_row_head(value.head),
    }
}

pub(crate) fn business_page(
    value: runtime_history::HistoryBusinessPage,
) -> BridgeHistoryBusinessPage {
    BridgeHistoryBusinessPage {
        cut: cut(value.cut),
        entries: value.entries.into_iter().map(business_row_entry).collect(),
        next: value.next,
    }
}

pub(crate) fn events_page(value: runtime_history::HistoryEventsPage) -> BridgeHistoryEventsPage {
    BridgeHistoryEventsPage {
        cut: cut(value.cut),
        entries: value.entries.into_iter().map(event_record).collect(),
        next: value.next,
    }
}

pub(crate) fn history_body_window(
    value: runtime_history::HistoryBodyWindow,
) -> BridgeHistoryBodyWindow {
    BridgeHistoryBodyWindow {
        offset: value.offset,
        bytes: value.bytes,
        total_length: value.total_length,
        media_type: value.media_type,
    }
}

pub(crate) fn body_page(value: runtime_history::HistoryBodyPage) -> BridgeHistoryBodyPage {
    BridgeHistoryBodyPage {
        owner_event_id: value.owner_event_id,
        entries: value
            .entries
            .into_iter()
            .map(|entry| BridgeHistoryBodyEntry {
                ordinal: entry.ordinal,
                body_key: entry.body_key,
                role: match entry.role {
                    runtime_history::HistoryBodyRole::CanonicalPayload => {
                        BridgeHistoryBodyRole::CanonicalPayload
                    }
                    runtime_history::HistoryBodyRole::CanonicalMetadata => {
                        BridgeHistoryBodyRole::CanonicalMetadata
                    }
                    runtime_history::HistoryBodyRole::Body => BridgeHistoryBodyRole::Body,
                    runtime_history::HistoryBodyRole::ReasoningSummary => {
                        BridgeHistoryBodyRole::ReasoningSummary
                    }
                    runtime_history::HistoryBodyRole::ToolArguments => {
                        BridgeHistoryBodyRole::ToolArguments
                    }
                    runtime_history::HistoryBodyRole::ToolOutput => {
                        BridgeHistoryBodyRole::ToolOutput
                    }
                    runtime_history::HistoryBodyRole::Attachment => {
                        BridgeHistoryBodyRole::Attachment
                    }
                    runtime_history::HistoryBodyRole::WaitPresentation => {
                        BridgeHistoryBodyRole::WaitPresentation
                    }
                    runtime_history::HistoryBodyRole::Other { name } => {
                        BridgeHistoryBodyRole::Other { name }
                    }
                },
                reference: body_ref(entry.reference),
                media_type: entry.media_type,
            })
            .collect(),
        next: value.next,
    }
}

pub(crate) fn accounting(value: runtime_history::HistoryAccountingHead) -> BridgeHistoryAccounting {
    BridgeHistoryAccounting {
        head: match business_row_head(runtime_history::HistoryBusinessRowHead::Accounting(value)) {
            BridgeHistoryBusinessRowHead::Accounting(head) => head,
            _ => unreachable!("accounting row mapping"),
        },
    }
}

pub(crate) fn bridge_to_body_ref(
    value: BridgeHistoryEventBodyRef,
) -> runtime_history::HistoryEventBodyRef {
    runtime_history::HistoryEventBodyRef {
        database_id: value.database_id,
        owner_event_id: value.owner_event_id,
        body_key: value.body_key,
        body_id: value.body_id,
        byte_start: value.byte_start,
        byte_length: value.byte_length,
    }
}

pub(crate) fn current_revision(value: protocol::CurrentRevision) -> BridgeCurrentRevision {
    BridgeCurrentRevision {
        owner_id: value.owner_id,
        revision: value.revision,
    }
}

pub(crate) fn bridge_to_current_revision(
    value: BridgeCurrentRevision,
) -> protocol::CurrentRevision {
    protocol::CurrentRevision {
        owner_id: value.owner_id,
        revision: value.revision,
    }
}

pub(crate) fn current_content_ref(value: protocol::CurrentContentRef) -> BridgeCurrentContentRef {
    BridgeCurrentContentRef {
        owner_id: value.owner_id,
        domain: value.domain,
        entity_id: value.entity_id,
        content_key: value.content_key,
        generation: value.generation,
    }
}

pub(crate) fn current_state_field(value: protocol::CurrentStateField) -> BridgeCurrentStateField {
    match value {
        protocol::CurrentStateField::Body {
            field,
            reference,
            byte_length,
        } => BridgeCurrentStateField::Body {
            field,
            reference: current_content_ref(reference),
            byte_length,
        },
        protocol::CurrentStateField::Collection {
            field,
            reference,
            count,
        } => BridgeCurrentStateField::Collection {
            field,
            reference: current_collection_ref(reference),
            count,
        },
    }
}

pub(crate) fn bridge_to_current_content_ref(
    value: BridgeCurrentContentRef,
) -> protocol::CurrentContentRef {
    protocol::CurrentContentRef {
        owner_id: value.owner_id,
        domain: value.domain,
        entity_id: value.entity_id,
        content_key: value.content_key,
        generation: value.generation,
    }
}

pub(crate) fn current_collection_ref(
    value: protocol::CurrentCollectionRef,
) -> BridgeCurrentCollectionRef {
    BridgeCurrentCollectionRef {
        owner_id: value.owner_id,
        collection: value.collection,
        revision: value.revision,
    }
}

pub(crate) fn bridge_to_current_collection_ref(
    value: BridgeCurrentCollectionRef,
) -> protocol::CurrentCollectionRef {
    protocol::CurrentCollectionRef {
        owner_id: value.owner_id,
        collection: value.collection,
        revision: value.revision,
    }
}

pub(crate) fn current_collection_page(
    value: protocol::CurrentCollectionPage,
) -> BridgeCurrentCollectionPage {
    BridgeCurrentCollectionPage {
        revision: value.revision,
        entries: value
            .entries
            .into_iter()
            .map(|entry| BridgeCurrentCollectionEntry {
                id: entry.id,
                position: entry.position,
                payload: match entry.payload {
                    protocol::CurrentPayloadData::Inline { bytes } => {
                        BridgeCurrentPayloadData::Inline { bytes }
                    }
                    protocol::CurrentPayloadData::Deferred {
                        reference,
                        byte_length,
                    } => BridgeCurrentPayloadData::Deferred {
                        reference: current_content_ref(reference),
                        byte_length,
                    },
                },
            })
            .collect(),
        continuation: value.continuation,
    }
}

fn current_atom(value: protocol::CurrentAtom) -> BridgeCurrentAtom {
    BridgeCurrentAtom {
        id: value.id,
        source: chat::source_id(value.source),
        source_state: value.source_state.map(chat::source_state),
        source_order: value.source_order,
        kind: chat::atom_kind(value.kind),
        delivery: chat::delivery(value.delivery),
        lifecycle: match value.lifecycle {
            protocol::ChatAtomLifecycle::Active { started, status } => {
                BridgeChatAtomLifecycle::Active {
                    started: started.map(chat::fact_position),
                    status: match status {
                        protocol::ChatActiveStatus::Running => BridgeChatActiveStatus::Running,
                        protocol::ChatActiveStatus::Waiting => BridgeChatActiveStatus::Waiting,
                    },
                }
            }
            protocol::ChatAtomLifecycle::Terminal {
                started,
                ended,
                outcome,
            } => BridgeChatAtomLifecycle::Terminal {
                started: started.map(chat::fact_position),
                ended: ended.map(chat::fact_position),
                outcome: chat::terminal_outcome(outcome),
            },
        },
        turn_id: value.turn_id,
        attempt_id: value.attempt_id,
        tool: value.tool.map(|tool| BridgeChatToolIdentity {
            call_id: tool.call_id,
            name: tool.name,
        }),
        wait: value.wait.map(thread_stream::wait_presentation),
        text_channel: value.text_channel.map(chat::text_channel),
        started_at: value.started_at,
        finished_at: value.finished_at,
        content_present: value.content_present,
        contents: value
            .contents
            .into_iter()
            .map(|content| BridgeCurrentAtomContent {
                role: match content.role {
                    protocol::ChatContentRole::Body => BridgeChatContentRole::Body,
                    protocol::ChatContentRole::ReasoningSummary => {
                        BridgeChatContentRole::ReasoningSummary
                    }
                    protocol::ChatContentRole::ToolArguments => {
                        BridgeChatContentRole::ToolArguments
                    }
                    protocol::ChatContentRole::ToolOutput => BridgeChatContentRole::ToolOutput,
                },
                reference: current_content_ref(content.reference),
            })
            .collect(),
    }
}

fn current_preview(value: protocol::CurrentContentPreview) -> BridgeCurrentContentPreview {
    BridgeCurrentContentPreview {
        id: value.id,
        role: match value.role {
            protocol::CurrentContentRole::Reasoning => BridgeCurrentContentRole::Reasoning,
            protocol::CurrentContentRole::Response => BridgeCurrentContentRole::Response,
            protocol::CurrentContentRole::ToolArguments => BridgeCurrentContentRole::ToolArguments,
            protocol::CurrentContentRole::ToolOutput => BridgeCurrentContentRole::ToolOutput,
        },
        text_channel: value.text_channel.map(chat::text_channel),
        text: value.text,
        reference: current_content_ref(value.reference),
    }
}

fn current_projection(value: protocol::CurrentProjection) -> BridgeCurrentProjection {
    BridgeCurrentProjection {
        logical_status: match value.logical_status {
            protocol::ThreadStatus::Idle => BridgeThreadStatus::Idle,
            protocol::ThreadStatus::Queued => BridgeThreadStatus::Queued,
            protocol::ThreadStatus::Running => BridgeThreadStatus::Running,
            protocol::ThreadStatus::WaitingTool => BridgeThreadStatus::WaitingTool,
            protocol::ThreadStatus::WaitingInteraction => BridgeThreadStatus::WaitingInteraction,
            protocol::ThreadStatus::Cancelling => BridgeThreadStatus::Cancelling,
            protocol::ThreadStatus::Closing => BridgeThreadStatus::Closing,
            protocol::ThreadStatus::Closed => BridgeThreadStatus::Closed,
            protocol::ThreadStatus::Faulted => BridgeThreadStatus::Faulted,
        },
        execution_present: value.execution_present,
        active: value.active.map(|head| BridgeCurrentActivityHead {
            id: head.id,
            kind: thread_stream::activity::activity_kind(head.kind),
            summary: head.summary,
            thinking_summary: head.thinking_summary,
            thinking_seconds: head.thinking_seconds,
            tool_count: head.tool_count,
            background_tool_count: head.background_tool_count,
            latest_tool: head.latest_tool.map(|tool| BridgeCurrentToolHead {
                call_id: tool.call_id,
                name: tool.name,
                state: thread_stream::activity::tool_state(tool.state),
            }),
        }),
        active_turn: value.active_turn.map(|turn| BridgeCurrentTurnHead {
            id: turn.id,
            phase: thread_stream::turn_phase(turn.phase),
        }),
        sources: value.sources.into_iter().map(chat::source_state).collect(),
        atoms: value.atoms.into_iter().map(current_atom).collect(),
        plan: value.plan.map(|plan| BridgeCurrentPlanHead {
            revision: plan.revision,
            phase: thread_stream::plan_phase(plan.phase),
            document: plan.document.map(current_content_ref),
        }),
        interactions: value.interactions.map(current_collection_ref),
        previews: value.previews.into_iter().map(current_preview).collect(),
        collections: value
            .collections
            .into_iter()
            .map(current_collection_ref)
            .collect(),
        model_recovery: value
            .model_recovery
            .map(|recovery| BridgeCurrentModelRecovery {
                attempt: recovery.attempt,
                max_attempts: recovery.max_attempts,
                reason: recovery.reason,
            }),
    }
}

pub(crate) fn current_view(value: protocol::CurrentView) -> ConvertResult<BridgeCurrentView> {
    Ok(BridgeCurrentView {
        revision: current_revision(value.revision),
        state: Box::new(thread_stream::bridge_thread_snapshot(*value.state)?),
        projection: current_projection(value.projection),
    })
}

pub(crate) fn current_frame(value: protocol::CurrentFrame) -> ConvertResult<BridgeCurrentFrame> {
    Ok(match value {
        protocol::CurrentFrame::Reset { view } => BridgeCurrentFrame::Reset {
            view: Box::new(current_view(*view)?),
        },
        protocol::CurrentFrame::Notification {
            revision,
            notification,
        } => BridgeCurrentFrame::Notification {
            revision: current_revision(revision),
            notification: Box::new(thread_stream::thread_notification(*notification)?),
        },
        protocol::CurrentFrame::Projection {
            revision,
            projection,
        } => BridgeCurrentFrame::Projection {
            revision: current_revision(revision),
            projection: Box::new(current_projection(*projection)),
        },
    })
}
