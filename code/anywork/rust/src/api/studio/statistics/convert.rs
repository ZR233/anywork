//! Typed bridge conversions for the statistics-only feed protocol.

use super::feed::StatisticsFeedCloseError;
use super::types::{
    BridgeStatisticsEffortPage, BridgeStatisticsEffortSummary, BridgeStatisticsFeedHeader,
    BridgeStatisticsHistoryPage, BridgeStatisticsModelMatchState, BridgeStatisticsSample,
    BridgeStatisticsSummary, BridgeStatisticsSummaryPage,
};
use crate::api::studio::types::BridgeError;
use pl_studio_runtime::statistics::{
    StatisticsEffortPage, StatisticsError, StatisticsFeedHeader, StatisticsHistoryPage,
    StatisticsSummary, StatisticsSummaryPage,
};

pub(super) fn bridge_header(value: StatisticsFeedHeader) -> BridgeStatisticsFeedHeader {
    BridgeStatisticsFeedHeader {
        owner_epoch: value.owner_epoch,
        feed_id: value.feed_id,
        delivery_sequence: value.delivery_sequence,
        publication_revision: value.publication_revision,
        summaries_revision: value.summaries_revision,
        history_revision: value.history_revision,
        summary_count: value.summary_count,
        history_count: value.history_count,
        statistics_pending: value.statistics_pending,
        statistics_gap: value.statistics_gap,
        read_failed: value.read_failed,
    }
}

pub(super) fn bridge_summary_page(value: StatisticsSummaryPage) -> BridgeStatisticsSummaryPage {
    BridgeStatisticsSummaryPage {
        owner_epoch: value.owner_epoch,
        feed_id: value.feed_id,
        scope_id: value.scope_id,
        publication_revision: value.publication_revision,
        material_revision: value.material_revision,
        offset: value.offset,
        total_count: value.total_count,
        next_offset: value.next_offset,
        source_bytes: value.source_bytes,
        items: value.items.into_iter().map(bridge_summary).collect(),
    }
}

fn bridge_summary(value: StatisticsSummary) -> BridgeStatisticsSummary {
    BridgeStatisticsSummary {
        account_id: value.account_id,
        account_display_name: value.account_display_name,
        model_id: value.model_id,
        sample_count: value.sample_count,
        completion_tokens: value.completion_tokens,
        total_ttft_millis: value.total_ttft_millis,
        ttft_sample_count: value.ttft_sample_count,
        total_response_millis: value.total_response_millis,
        tokens_per_second: value.tokens_per_second,
        average_ttft_millis: value.average_ttft_millis,
        average_response_millis: value.average_response_millis,
        effort_count: value.effort_count,
    }
}

pub(super) fn bridge_history_page(value: StatisticsHistoryPage) -> BridgeStatisticsHistoryPage {
    BridgeStatisticsHistoryPage {
        owner_epoch: value.owner_epoch,
        feed_id: value.feed_id,
        scope_id: value.scope_id,
        publication_revision: value.publication_revision,
        material_revision: value.material_revision,
        offset: value.offset,
        total_count: value.total_count,
        next_offset: value.next_offset,
        source_bytes: value.source_bytes,
        items: value.items.into_iter().map(bridge_sample).collect(),
    }
}

fn bridge_sample(
    value: pl_studio_runtime::statistics::StudioModelPerformanceSample,
) -> BridgeStatisticsSample {
    BridgeStatisticsSample {
        thread_id: value.thread_id,
        call_id: value.call_id,
        purpose: value.purpose,
        first_output_source: value.first_output_source.into(),
        usage_status: value.usage_status.into(),
        ttft_availability: value.ttft_availability.into(),
        throughput_availability: value.throughput_availability.into(),
        completed_at: value.completed_at,
        account_id: value.account_id,
        account_display_name: value.account_display_name,
        model_id: value.model_id,
        sent_model: value.sent_model,
        reported_model: value.reported_model,
        model_match_state: match value.model_match_state {
            pl_protocol::ModelMatchState::Matched => BridgeStatisticsModelMatchState::Matched,
            pl_protocol::ModelMatchState::Mismatched => BridgeStatisticsModelMatchState::Mismatched,
            pl_protocol::ModelMatchState::Unreported => BridgeStatisticsModelMatchState::Unreported,
            pl_protocol::ModelMatchState::LegacyUnknown => {
                BridgeStatisticsModelMatchState::LegacyUnknown
            }
        },
        effort: value.effort,
        completion_tokens: value.completion_tokens,
        ttft_millis: value.ttft_millis,
        decode_millis: value.decode_millis,
        total_response_millis: value.total_response_millis,
        tokens_per_second: value.tokens_per_second,
    }
}

pub(super) fn bridge_effort_page(value: StatisticsEffortPage) -> BridgeStatisticsEffortPage {
    BridgeStatisticsEffortPage {
        owner_epoch: value.owner_epoch,
        feed_id: value.feed_id,
        scope_id: value.scope_id,
        publication_revision: value.publication_revision,
        material_revision: value.material_revision,
        summary_index: value.summary_index,
        offset: value.offset,
        total_count: value.total_count,
        next_offset: value.next_offset,
        source_bytes: value.source_bytes,
        items: value
            .items
            .into_iter()
            .map(|value| BridgeStatisticsEffortSummary {
                effort: value.effort,
                sample_count: value.sample_count,
                completion_tokens: value.completion_tokens,
                total_ttft_millis: value.total_ttft_millis,
                ttft_sample_count: value.ttft_sample_count,
                total_response_millis: value.total_response_millis,
                tokens_per_second: value.tokens_per_second,
                average_ttft_millis: value.average_ttft_millis,
                average_response_millis: value.average_response_millis,
            })
            .collect(),
    }
}

pub(super) fn statistics_error(error: StatisticsError) -> BridgeError {
    use pl_protocol::studio::{StudioError, StudioErrorCode};
    let (code, retryable) = match error {
        StatisticsError::Closed => (StudioErrorCode::RuntimeStopped, false),
        StatisticsError::InvalidReference | StatisticsError::InvalidPageLimit => {
            (StudioErrorCode::InvalidArgument, false)
        }
        StatisticsError::NextInFlight | StatisticsError::PageInFlight => {
            (StudioErrorCode::Busy, true)
        }
        StatisticsError::PublicationCapacity
        | StatisticsError::ScopeCapacity
        | StatisticsError::PageCapacity => (StudioErrorCode::Overloaded, true),
    };
    let category = match error {
        StatisticsError::Closed => "closed",
        StatisticsError::InvalidReference => "invalidReference",
        StatisticsError::NextInFlight => "nextInFlight",
        StatisticsError::PublicationCapacity => "publicationCapacity",
        StatisticsError::ScopeCapacity => "scopeCapacity",
        StatisticsError::PageInFlight => "pageInFlight",
        StatisticsError::InvalidPageLimit => "invalidPageLimit",
        StatisticsError::PageCapacity => "pageCapacity",
    };
    let mut failure = BridgeError::from(StudioError::new(code, error.to_string(), retryable));
    failure.details_json = Some(serde_json::json!({"statisticsError": category}).to_string());
    failure
}

pub(super) fn statistics_close_error(error: StatisticsFeedCloseError) -> BridgeError {
    match error {
        StatisticsFeedCloseError::Feed(feed_error) => statistics_error(feed_error),
        StatisticsFeedCloseError::SinkStopped => {
            statistics_close_task_error("sinkStopped", "statistics sink stopped")
        }
        StatisticsFeedCloseError::ProducerTaskFailed => {
            statistics_close_task_error("producerTaskFailed", "statistics producer task failed")
        }
        StatisticsFeedCloseError::SinkTaskFailed => {
            statistics_close_task_error("sinkTaskFailed", "statistics sink task failed")
        }
    }
}

fn statistics_close_task_error(category: &str, message: &str) -> BridgeError {
    use pl_protocol::studio::{StudioError, StudioErrorCode};
    let mut failure = BridgeError::from(StudioError::new(
        StudioErrorCode::Unavailable,
        message,
        true,
    ));
    failure.details_json = Some(serde_json::json!({"statisticsCloseError": category}).to_string());
    failure
}
