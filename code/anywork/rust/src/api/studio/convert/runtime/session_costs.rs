use crate::api::studio::types::{
    BridgePurposeCostSnapshot, BridgeRuntimeCostAmount, BridgeSessionCostSnapshot,
    BridgeSessionCostsState,
};

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
