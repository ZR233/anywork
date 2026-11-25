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
            has_incomplete_usage: cost.has_incomplete_usage,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_studio_runtime::{
        RuntimeCostAmount, StudioPurposeCostSnapshot, StudioSessionCostSnapshot,
        StudioSessionCostsState,
    };

    #[test]
    fn priced_incomplete_session_cost_matches_product_json_and_bridge() {
        let fixture: serde_json::Value = serde_json::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../test/fixtures/session_cost_snapshot.json"
        )))
        .unwrap();
        let amount = RuntimeCostAmount {
            currency: "USD".into(),
            amount: 0.25,
        };
        let cost = StudioSessionCostSnapshot {
            root_thread_id: "root".into(),
            purpose_costs: vec![StudioPurposeCostSnapshot {
                purpose: Some("main".into()),
                estimated_costs: vec![amount.clone()],
                has_unpriced_usage: false,
            }],
            estimated_costs: vec![amount],
            has_unpriced_usage: false,
            has_incomplete_usage: true,
        };
        assert_eq!(serde_json::to_value(&cost).unwrap(), fixture);
        assert_eq!(
            serde_json::from_value::<StudioSessionCostSnapshot>(fixture.clone()).unwrap(),
            cost
        );

        let bridge = bridge_session_costs_state(StudioSessionCostsState {
            root_thread_id: "root".into(),
            revision: u64::MAX,
            updated_at: 1000,
            statistics_pending: false,
            statistics_gap: false,
            read_failed: false,
            cost: Some(cost),
        });
        assert_eq!(bridge.revision, u64::MAX);
        assert!(!bridge.statistics_pending);
        assert!(!bridge.statistics_gap);
        assert!(!bridge.read_failed);
        assert_eq!(serde_json::to_value(bridge.cost.unwrap()).unwrap(), fixture);

        let mut missing_completeness = fixture;
        missing_completeness
            .as_object_mut()
            .unwrap()
            .remove("hasIncompleteUsage");
        let error =
            serde_json::from_value::<StudioSessionCostSnapshot>(missing_completeness).unwrap_err();
        assert!(error.to_string().contains("hasIncompleteUsage"), "{error}");
    }
}
