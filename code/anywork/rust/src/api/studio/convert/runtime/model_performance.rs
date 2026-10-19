use pl_studio_runtime::StudioModelPerformanceSnapshot;

use crate::api::studio::types::{
    BridgeModelMatchState, BridgeModelPerformanceSample, BridgeModelPerformanceSnapshot,
    BridgeModelPerformanceSummary, BridgePurposeCostSnapshot, BridgeRuntimeCostAmount,
    BridgeSessionCostSnapshot, BridgeSessionCostsState,
};

pub(crate) fn bridge_model_performance(
    value: StudioModelPerformanceSnapshot,
) -> BridgeModelPerformanceSnapshot {
    BridgeModelPerformanceSnapshot {
        revision: value.revision,
        updated_at: value.updated_at,
        statistics_pending: value.statistics_pending,
        statistics_gap: value.statistics_gap,
        read_failed: value.read_failed,
        summaries: value
            .summaries
            .into_iter()
            .map(|summary| BridgeModelPerformanceSummary {
                account_id: summary.account_id,
                account_display_name: summary.account_display_name,
                model_id: summary.model_id,
                sample_count: summary.sample_count,
                completion_tokens: summary.completion_tokens,
                total_ttft_millis: summary.total_ttft_millis,
                total_decode_millis: summary.total_decode_millis,
                total_response_millis: summary.total_response_millis,
                tokens_per_second: summary.tokens_per_second,
                average_ttft_millis: summary.average_ttft_millis,
                average_response_millis: summary.average_response_millis,
                effort_breakdowns: summary
                    .effort_breakdowns
                    .into_iter()
                    .map(|effort| {
                        crate::api::studio::types::response::BridgeModelPerformanceEffortSummary {
                            effort: effort.effort,
                            sample_count: effort.sample_count,
                            completion_tokens: effort.completion_tokens,
                            total_ttft_millis: effort.total_ttft_millis,
                            total_decode_millis: effort.total_decode_millis,
                            total_response_millis: effort.total_response_millis,
                            tokens_per_second: effort.tokens_per_second,
                            average_ttft_millis: effort.average_ttft_millis,
                            average_response_millis: effort.average_response_millis,
                        }
                    })
                    .collect(),
            })
            .collect(),
        history: value
            .history
            .into_iter()
            .map(|sample| BridgeModelPerformanceSample {
                completed_at: sample.completed_at,
                account_id: sample.account_id,
                account_display_name: sample.account_display_name,
                model_id: sample.model_id,
                sent_model: sample.sent_model,
                reported_model: sample.reported_model,
                model_match_state: match sample.model_match_state {
                    pl_protocol::ModelMatchState::Matched => BridgeModelMatchState::Matched,
                    pl_protocol::ModelMatchState::Mismatched => BridgeModelMatchState::Mismatched,
                    pl_protocol::ModelMatchState::Unreported => BridgeModelMatchState::Unreported,
                    pl_protocol::ModelMatchState::LegacyUnknown => {
                        BridgeModelMatchState::LegacyUnknown
                    }
                },
                effort: sample.effort,
                completion_tokens: sample.completion_tokens,
                ttft_millis: sample.ttft_millis,
                decode_millis: sample.decode_millis,
                total_response_millis: sample.total_response_millis,
                tokens_per_second: sample.tokens_per_second,
            })
            .collect(),
    }
}

pub(crate) fn bridge_session_costs_state(
    value: pl_studio_runtime::StudioSessionCostsState,
) -> BridgeSessionCostsState {
    BridgeSessionCostsState {
        root_thread_id: value.root_thread_id,
        revision: value.revision,
        updated_at: value.updated_at,
        statistics_pending: value.statistics_pending,
        statistics_gap: value.statistics_gap,
        read_failed: value.read_failed,
        cost: value.cost.map(|cost| BridgeSessionCostSnapshot {
            root_thread_id: cost.root_thread_id,
            purpose_costs: cost
                .purpose_costs
                .into_iter()
                .map(|cost| BridgePurposeCostSnapshot {
                    purpose: cost.purpose,
                    estimated_costs: cost
                        .estimated_costs
                        .into_iter()
                        .map(|amount| BridgeRuntimeCostAmount {
                            currency: amount.currency,
                            amount: amount.amount,
                        })
                        .collect(),
                    has_unpriced_usage: cost.has_unpriced_usage,
                })
                .collect(),
            estimated_costs: cost
                .estimated_costs
                .into_iter()
                .map(|cost| BridgeRuntimeCostAmount {
                    currency: cost.currency,
                    amount: cost.amount,
                })
                .collect(),
            has_unpriced_usage: cost.has_unpriced_usage,
        }),
    }
}
