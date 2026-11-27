//! Mechanical conversion of the Native conversation feed's typed values.

use anyhow::Result;
use pl_studio_runtime as protocol;

use crate::api::studio::types::*;

use super::thread_stream;

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

pub(crate) fn current_collection_ref(
    value: protocol::CurrentCollectionRef,
) -> BridgeCurrentCollectionRef {
    BridgeCurrentCollectionRef {
        owner_id: value.owner_id,
        collection: value.collection,
        revision: value.revision,
    }
}

fn model_recovery_notice(value: protocol::ModelRecoveryNotice) -> BridgeModelRecoveryNotice {
    use protocol::ModelRecoveryPhase;

    BridgeModelRecoveryNotice {
        failure_kind: value.failure_kind.map(|kind| kind.as_str().to_owned()),
        reason: value.reason.map(thread_stream::provider_recovery_label),
        retry_count: value.retry_count,
        max_retries: value.max_retries,
        effective_wait_millis: value.effective_wait_millis,
        failure: value.failure.map(thread_stream::bridge_turn_failure),
        phase: match value.phase {
            ModelRecoveryPhase::Repairing => BridgeModelRecoveryPhase::Repairing,
            ModelRecoveryPhase::Waiting => BridgeModelRecoveryPhase::Waiting,
            ModelRecoveryPhase::Retrying => BridgeModelRecoveryPhase::Retrying,
            ModelRecoveryPhase::Recovered => BridgeModelRecoveryPhase::Recovered,
            ModelRecoveryPhase::Exhausted => BridgeModelRecoveryPhase::Exhausted,
            ModelRecoveryPhase::Failed => BridgeModelRecoveryPhase::Failed,
            ModelRecoveryPhase::Cancelled => BridgeModelRecoveryPhase::Cancelled,
        },
    }
}

fn body_ref(value: protocol::BodyRef) -> BridgeBodyRef {
    BridgeBodyRef {
        database_id: value.database_id,
        body_id: value.body_id,
        owner_event_id: value.owner_event_id,
        body_key: value.body_key,
        role: value.role,
        byte_length: value.byte_length,
        media_type: value.media_type,
        inline_text: value.inline_text,
    }
}

pub(crate) fn runtime_body_ref(value: BridgeBodyRef) -> protocol::BodyRef {
    protocol::BodyRef {
        database_id: value.database_id,
        body_id: value.body_id,
        owner_event_id: value.owner_event_id,
        body_key: value.body_key,
        role: value.role,
        byte_length: value.byte_length,
        media_type: value.media_type,
        inline_text: value.inline_text,
    }
}

pub(crate) fn body_window(value: protocol::BodyWindow) -> BridgeBodyWindow {
    BridgeBodyWindow {
        offset: value.offset,
        text: value.text,
        bytes_base64: value.bytes_base64,
        total_bytes: value.total_bytes,
        eof: value.eof,
    }
}

pub(crate) fn runtime_session_detail_kind(
    value: BridgeSessionDetailKind,
) -> protocol::SessionDetailKind {
    use protocol::SessionDetailKind;

    match value {
        BridgeSessionDetailKind::Plan => SessionDetailKind::Plan,
        BridgeSessionDetailKind::Interactions => SessionDetailKind::Interactions,
        BridgeSessionDetailKind::Todo => SessionDetailKind::Todo,
        BridgeSessionDetailKind::Workflow => SessionDetailKind::Workflow,
        BridgeSessionDetailKind::ActiveSkills => SessionDetailKind::ActiveSkills,
        BridgeSessionDetailKind::ActiveMcpServers => SessionDetailKind::ActiveMcpServers,
        BridgeSessionDetailKind::ActiveLspServers => SessionDetailKind::ActiveLspServers,
    }
}

pub(crate) fn session_detail_window(
    value: protocol::SessionDetailWindow,
) -> BridgeSessionDetailWindow {
    BridgeSessionDetailWindow {
        owner_epoch: value.owner_epoch,
        revision: value.revision,
        offset: value.offset,
        total_bytes: value.total_bytes,
        bytes: value.bytes,
    }
}

fn work_group_status(value: protocol::WorkGroupStatus) -> BridgeWorkGroupStatus {
    match value {
        protocol::WorkGroupStatus::Active => BridgeWorkGroupStatus::Active,
        protocol::WorkGroupStatus::Completed => BridgeWorkGroupStatus::Completed,
        protocol::WorkGroupStatus::Failed => BridgeWorkGroupStatus::Failed,
        protocol::WorkGroupStatus::Cancelled => BridgeWorkGroupStatus::Cancelled,
    }
}

fn timeline_item(value: protocol::TimelineItem) -> Result<BridgeTimelineItem> {
    Ok(match value {
        protocol::TimelineItem::UserMessage {
            id,
            seq,
            turn_id,
            input_id,
            channel,
            text,
            attachments,
            occurred_at_ms,
        } => BridgeTimelineItem::UserMessage {
            id,
            seq,
            turn_id,
            input_id,
            channel,
            text,
            attachments_json: serde_json::to_string(&attachments)?,
            occurred_at_ms,
        },
        protocol::TimelineItem::AssistantText {
            id,
            seq,
            turn_id,
            attempt_id,
            channel,
            text,
            body_ref: reference,
            is_final_turn_delivery,
            outcome,
            model_recovery,
            occurred_at_ms,
        } => BridgeTimelineItem::AssistantText {
            id,
            seq,
            turn_id,
            attempt_id,
            channel,
            text,
            body_ref: reference.map(body_ref),
            is_final_turn_delivery,
            outcome,
            model_recovery: model_recovery.map(|notice| Box::new(model_recovery_notice(*notice))),
            occurred_at_ms,
        },
        protocol::TimelineItem::WorkGroup {
            id,
            first_seq,
            last_seq,
            after_boundary_seq,
            before_boundary_seq,
            member_count,
            summary,
            status,
            started_at_ms,
            finished_at_ms,
        } => BridgeTimelineItem::WorkGroup {
            id,
            first_seq,
            last_seq,
            after_boundary_seq,
            before_boundary_seq,
            member_count,
            summary,
            status: work_group_status(status),
            started_at_ms,
            finished_at_ms,
        },
        protocol::TimelineItem::Compaction {
            id,
            seq,
            turn_id,
            summary,
            outcome,
            tokens_before,
            tokens_after,
            occurred_at_ms,
        } => BridgeTimelineItem::Compaction {
            id,
            seq,
            turn_id,
            summary,
            outcome,
            tokens_before,
            tokens_after,
            occurred_at_ms,
        },
        protocol::TimelineItem::PlanResolution {
            id,
            seq,
            turn_id,
            decision,
            document,
            document_ref,
            feedback,
            occurred_at_ms,
        } => BridgeTimelineItem::PlanResolution {
            id,
            seq,
            turn_id,
            decision,
            document,
            document_ref: document_ref.map(body_ref),
            feedback,
            occurred_at_ms,
        },
        protocol::TimelineItem::ConnectionNotice {
            id,
            seq,
            turn_id,
            scope,
            state,
            transport,
            fallback_transport,
            attempt,
            max_attempts,
            recoverable,
            reason,
            duration_ms,
            occurred_at_ms,
        } => BridgeTimelineItem::ConnectionNotice {
            id,
            seq,
            turn_id,
            scope,
            state,
            transport,
            fallback_transport,
            attempt,
            max_attempts,
            recoverable,
            reason,
            duration_ms,
            occurred_at_ms,
        },
        protocol::TimelineItem::TurnOutcome {
            id,
            seq,
            turn_id,
            input_id,
            outcome,
            message,
            turn_failure,
            occurred_at_ms,
        } => BridgeTimelineItem::TurnOutcome {
            id,
            seq,
            turn_id,
            input_id,
            outcome,
            message,
            turn_failure: turn_failure
                .map(|failure| Box::new(thread_stream::bridge_turn_failure(*failure))),
            occurred_at_ms,
        },
        protocol::TimelineItem::StandaloneTool {
            id,
            seq,
            turn_id,
            call_id,
            tool_name,
            presentation_contract,
            state,
            summary,
            payload_json,
            bodies,
            occurred_at_ms,
        } => BridgeTimelineItem::StandaloneTool {
            id,
            seq,
            turn_id,
            call_id,
            tool_name,
            presentation_contract,
            state,
            summary,
            payload_json,
            bodies: bodies.into_iter().map(body_ref).collect(),
            occurred_at_ms,
        },
        protocol::TimelineItem::Fallback {
            id,
            seq,
            event_id,
            event_kind,
            reason,
            raw_preview,
            occurred_at_ms,
        } => BridgeTimelineItem::Fallback {
            id,
            seq,
            event_id,
            event_kind,
            reason,
            raw_preview,
            occurred_at_ms,
        },
    })
}

pub(crate) fn work_group_member(value: protocol::WorkGroupMember) -> BridgeWorkGroupMember {
    match value {
        protocol::WorkGroupMember::Reasoning {
            id,
            seq,
            text,
            summary,
            body_ref: reference,
            outcome,
            started_at_ms,
            finished_at_ms,
        } => BridgeWorkGroupMember::Reasoning {
            id,
            seq,
            text,
            summary,
            body_ref: reference.map(body_ref),
            outcome,
            started_at_ms,
            finished_at_ms,
        },
        protocol::WorkGroupMember::ToolCall {
            id,
            seq,
            call_id,
            turn_id,
            tool_name,
            presentation_contract,
            status,
            summary,
            arguments,
            result_preview,
            payload_json,
            bodies,
            wait_json,
            started_at_ms,
            finished_at_ms,
        } => BridgeWorkGroupMember::ToolCall {
            id,
            seq,
            call_id,
            turn_id,
            tool_name,
            presentation_contract,
            status,
            summary,
            arguments,
            result_preview,
            payload_json,
            bodies: bodies.into_iter().map(body_ref).collect(),
            wait_json,
            started_at_ms,
            finished_at_ms,
        },
        protocol::WorkGroupMember::Agent {
            id,
            seq,
            agent_id,
            name,
            status,
            summary,
            payload_json,
            started_at_ms,
            finished_at_ms,
        } => BridgeWorkGroupMember::Agent {
            id,
            seq,
            agent_id,
            name,
            status,
            summary,
            payload_json,
            started_at_ms,
            finished_at_ms,
        },
        protocol::WorkGroupMember::FileChange {
            id,
            seq,
            summary,
            payload_json,
            bodies,
            occurred_at_ms,
        } => BridgeWorkGroupMember::FileChange {
            id,
            seq,
            summary,
            payload_json,
            bodies: bodies.into_iter().map(body_ref).collect(),
            occurred_at_ms,
        },
        protocol::WorkGroupMember::Skill {
            id,
            seq,
            name,
            summary,
            payload_json,
            occurred_at_ms,
        } => BridgeWorkGroupMember::Skill {
            id,
            seq,
            name,
            summary,
            payload_json,
            occurred_at_ms,
        },
        protocol::WorkGroupMember::Fallback {
            id,
            seq,
            event_id,
            event_kind,
            reason,
            occurred_at_ms,
        } => BridgeWorkGroupMember::Fallback {
            id,
            seq,
            event_id,
            event_kind,
            reason,
            occurred_at_ms,
        },
    }
}

pub(crate) fn timeline_patch(value: protocol::TimelinePatch) -> Result<BridgeTimelinePatch> {
    Ok(match value {
        protocol::TimelinePatch::Reset {
            items,
            has_more_older,
            older_cursor,
            revision,
        } => BridgeTimelinePatch::Reset {
            items: items
                .into_iter()
                .map(timeline_item)
                .collect::<Result<_>>()?,
            has_more_older,
            older_cursor,
            revision,
        },
        protocol::TimelinePatch::PrependOlder {
            items,
            has_more_older,
            older_cursor,
        } => BridgeTimelinePatch::PrependOlder {
            items: items
                .into_iter()
                .map(timeline_item)
                .collect::<Result<_>>()?,
            has_more_older,
            older_cursor,
        },
        protocol::TimelinePatch::Append { items } => BridgeTimelinePatch::Append {
            items: items
                .into_iter()
                .map(timeline_item)
                .collect::<Result<_>>()?,
        },
        protocol::TimelinePatch::Update { item } => BridgeTimelinePatch::Update {
            item: Box::new(timeline_item(item)?),
        },
        protocol::TimelinePatch::Remove { item_id } => BridgeTimelinePatch::Remove { item_id },
    })
}

fn live_attention(value: protocol::LiveAttention) -> BridgeLiveAttention {
    BridgeLiveAttention {
        id: value.id,
        kind: value.kind,
        summary: value.summary,
        call_id: value.call_id,
    }
}

fn live_status_phase(value: protocol::LiveStatusPhase) -> BridgeLiveStatusPhase {
    match value {
        protocol::LiveStatusPhase::Idle => BridgeLiveStatusPhase::Idle,
        protocol::LiveStatusPhase::Working {
            items,
            reasoning_preview,
            started_at_ms,
        } => BridgeLiveStatusPhase::Working {
            items: items.into_iter().map(work_group_member).collect(),
            reasoning_preview,
            started_at_ms,
        },
        protocol::LiveStatusPhase::StreamingText {
            attempt_id,
            item_id,
            text,
            started_at_ms,
        } => BridgeLiveStatusPhase::StreamingText {
            attempt_id,
            item_id,
            text,
            started_at_ms,
        },
        protocol::LiveStatusPhase::Compacting {
            manual,
            started_at_ms,
        } => BridgeLiveStatusPhase::Compacting {
            manual,
            started_at_ms,
        },
        protocol::LiveStatusPhase::Reconnecting {
            attempt_id,
            message,
            retry_after_ms,
            attempt,
            max_attempts,
        } => BridgeLiveStatusPhase::Reconnecting {
            attempt_id,
            message,
            retry_after_ms,
            attempt,
            max_attempts,
        },
        protocol::LiveStatusPhase::Stopping { started_at_ms } => {
            BridgeLiveStatusPhase::Stopping { started_at_ms }
        }
    }
}

pub(crate) fn live_status_snapshot(
    value: protocol::LiveStatusSnapshot,
) -> BridgeLiveStatusSnapshot {
    BridgeLiveStatusSnapshot {
        revision: value.revision,
        phase: live_status_phase(value.phase),
        attentions: value.attentions.into_iter().map(live_attention).collect(),
        suppressed_by_interaction: value.suppressed_by_interaction,
    }
}

pub(crate) fn session_meta_snapshot(
    value: protocol::SessionMetaSnapshot,
) -> Result<BridgeSessionMetaSnapshot> {
    let usage = value.usage;
    // The backend exposes these core diagnostic types through fields, without re-exporting
    // their enum types to this crate. Their existing Serde representations preserve the
    // accounting observations across that boundary; Dart receives typed fields.
    let diagnostics = serde_json::from_value(serde_json::to_value(usage.diagnostics)?)?;
    let latest_call = serde_json::from_value(serde_json::to_value(usage.context.latest_call)?)?;
    Ok(BridgeSessionMetaSnapshot {
        thread_id: value.thread_id,
        status: thread_stream::bridge_thread_status(value.status),
        title: value.title,
        parent_thread_id: value.parent_thread_id,
        root_thread_id: value.root_thread_id,
        owner_epoch: value.owner_epoch,
        revision: value.revision,
        active_turn: value.active_turn.map(thread_stream::bridge_turn),
        last_turn: value.last_turn.map(thread_stream::bridge_turn),
        activity: value.activity.map(thread_stream::activity::activity),
        usage: BridgeUsageSummary {
            applied_sequence: usage.applied_sequence,
            binding: usage.binding.map(|binding| BridgeUsageBinding {
                route_identity: binding.route_identity,
                model: binding.model,
                context_window: binding.context_window,
                max_context_window: binding.max_context_window,
                auto_compact_limit: binding.auto_compact_limit,
            }),
            totals: BridgeUsageTotals {
                inference_count: usage.totals.inference_count,
                prompt_tokens: usage.totals.prompt_tokens,
                completion_tokens: usage.totals.completion_tokens,
                cached_prompt_tokens: usage.totals.cached_prompt_tokens,
                cache_write_tokens: usage.totals.cache_write_tokens,
                reasoning_tokens: usage.totals.reasoning_tokens,
                total_tokens: usage.totals.total_tokens,
            },
            cache: BridgeUsageCacheSummary {
                input_tokens: usage.cache.input_tokens,
                read_tokens: usage.cache.read_tokens,
                sample_count: usage.cache.sample_count,
                incomplete: usage.cache.incomplete,
            },
            context: BridgeUsageContextSummary {
                tokens: usage.context.tokens,
                latest_call,
            },
            throughput: BridgeUsageThroughputSummary {
                turn_id: usage.throughput.turn_id,
                completion_tokens: usage.throughput.completion_tokens,
                response_millis: usage.throughput.response_millis,
            },
            diagnostics,
            pricing: BridgeUsagePricingSummary {
                incomplete: usage.pricing.incomplete,
                estimated_costs: usage
                    .pricing
                    .estimated_costs
                    .into_iter()
                    .map(|cost| BridgeRuntimeCostAmount {
                        currency: cost.currency,
                        amount: cost.amount,
                    })
                    .collect(),
                estimated_cache_savings: usage
                    .pricing
                    .estimated_cache_savings
                    .into_iter()
                    .map(|cost| BridgeRuntimeCostAmount {
                        currency: cost.currency,
                        amount: cost.amount,
                    })
                    .collect(),
            },
        },
        context_metrics: value.context_metrics.map(thread_stream::runtime_usage),
        model_route: value.model_route.map(thread_stream::model_route_snapshot),
        runtime: value.runtime.map(thread_stream::runtime_snapshot),
        storage_state: value.storage_state.map(thread_stream::activity::storage),
        interactions: value
            .interactions
            .into_iter()
            .map(thread_stream::bridge_interaction)
            .collect::<Result<_>>()?,
        pending_interaction_count: value.pending_interaction_count,
        plan: value.plan.map(thread_stream::plan_runtime_snapshot),
        mode: value.mode.map(|mode| mode.to_string()),
        execution_present: value.execution_present,
    })
}

pub(crate) fn conversation_event(
    value: protocol::ConversationEvent,
) -> Result<BridgeConversationEvent> {
    Ok(match value {
        protocol::ConversationEvent::Timeline(patch) => BridgeConversationEvent::Timeline {
            patch: timeline_patch(patch)?,
        },
        protocol::ConversationEvent::LiveStatus(snapshot) => BridgeConversationEvent::LiveStatus {
            snapshot: live_status_snapshot(snapshot),
        },
        protocol::ConversationEvent::SessionMeta(snapshot) => {
            BridgeConversationEvent::SessionMeta {
                snapshot: Box::new(session_meta_snapshot(snapshot)?),
            }
        }
        protocol::ConversationEvent::InputPresented { input_id, item_id } => {
            BridgeConversationEvent::InputPresented { input_id, item_id }
        }
        protocol::ConversationEvent::ResyncRequired { reason } => {
            BridgeConversationEvent::ResyncRequired { reason }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use protocol::{
        ModelRecoveryNotice, ModelRecoveryPhase, ProviderFailureKind, ProviderFailureStage,
        ProviderRecovery, RetryDisposition, TurnFailure, TurnFailureCategory,
    };

    #[test]
    fn assistant_timeline_recovery_notices_match_fixture_consumed_by_dart() {
        use ModelRecoveryPhase::{Cancelled, Recovered, Waiting};
        use ProviderFailureKind::{RateLimit, ServiceBusy, Transport};
        use ProviderFailureStage::{Handshake, Request, Stream};

        let expected: serde_json::Value = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../test/fixtures/provider_recovery_notices.json"
        )))
        .unwrap();
        let cases = [
            (
                "waiting",
                Waiting,
                BridgeModelRecoveryPhase::Waiting,
                RateLimit,
                ProviderRecovery::None,
                45_000,
                429,
                "rate_limit_exceeded",
                "rate_limit_error",
                Request,
                "The provider limited the request.",
            ),
            (
                "recovered",
                Recovered,
                BridgeModelRecoveryPhase::Recovered,
                Transport,
                ProviderRecovery::HttpFallback,
                9_007_199_254_740_993,
                503,
                "upstream_connection_closed",
                "connection_error",
                Handshake,
                "The provider closed the connection during the handshake.",
            ),
            (
                "cancelled",
                Cancelled,
                BridgeModelRecoveryPhase::Cancelled,
                ServiceBusy,
                ProviderRecovery::None,
                u64::MAX,
                503,
                "service_unavailable",
                "overloaded_error",
                Stream,
                "The provider became unavailable while streaming the answer.",
            ),
        ];
        for (
            label,
            phase,
            bridge_phase,
            kind,
            reason,
            wait,
            status,
            code,
            error_type,
            stage,
            message,
        ) in cases
        {
            let mut failure = TurnFailure::permanent(TurnFailureCategory::Provider, message);
            failure.provider_kind = Some(kind);
            failure.code = Some(code.into());
            failure.http_status = Some(status);
            failure.error_type = Some(error_type.into());
            failure.request_id = Some(format!("req-recovery-{label}"));
            failure.stage = Some(stage);
            failure.retry = RetryDisposition::Retryable {
                retry_after_ms: Some(wait),
            };
            let notice = ModelRecoveryNotice {
                failure_kind: Some(kind),
                reason: Some(reason),
                retry_count: 1,
                max_retries: 2,
                effective_wait_millis: Some(wait),
                phase,
                failure: Some(failure.clone()),
            };
            let item = protocol::TimelineItem::AssistantText {
                id: "msg:7".into(),
                seq: 7,
                turn_id: Some("turn".into()),
                attempt_id: None,
                channel: "commentary".into(),
                text: "Recovered output".into(),
                body_ref: None,
                is_final_turn_delivery: false,
                outcome: "completed".into(),
                model_recovery: Some(Box::new(notice)),
                occurred_at_ms: None,
            };
            assert_eq!(
                serde_json::to_value(&item).unwrap()["modelRecovery"],
                expected[label]
            );
            let BridgeTimelineItem::AssistantText {
                id,
                model_recovery: Some(bridge),
                ..
            } = timeline_item(item).unwrap()
            else {
                panic!("assistant timeline item lost its recovery notice");
            };
            assert_eq!(id, "msg:7");
            assert_eq!(bridge.phase, bridge_phase);
            assert_eq!(bridge.effective_wait_millis, Some(wait));
            assert_eq!(
                bridge.failure,
                Some(thread_stream::bridge_turn_failure(failure))
            );
        }
    }
}
