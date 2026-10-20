//! 自动压缩阈值从模型声明和 provider 用户选择解析，配置中只保存覆盖。

use std::collections::BTreeMap;

use pl_model::config::{AccountConfig, AccountId, AgentModelConfig, AgentRoleId, ModelRouteConfig};
use pl_model::model::ModelInfo;
use pl_model::protocol::ProtocolEndpoint;
use pretty_assertions::assert_eq;
use serde_json::json;

fn model(model_id: &str, capacity: Option<u64>) -> ModelInfo {
    let mut model = ModelInfo::compatible(model_id);
    model.context_window = capacity;
    model.max_context_window = capacity;
    model.max_output_tokens = None;
    model
}

fn provider(models: Vec<ModelInfo>) -> AccountConfig {
    AccountConfig::from_explicit_models(
        ProtocolEndpoint::compatible("Fixture", "https://example.test/v1"),
        models,
    )
}

fn config(provider: AccountConfig) -> AgentModelConfig {
    AgentModelConfig {
        accounts: [(AccountId::new("fixture").unwrap(), provider)].into(),
        routes: BTreeMap::new(),
    }
}

#[test]
fn route_defaults_reserve_output_within_the_current_capacity() {
    let mut preset = model("preset", Some(400_000));
    preset.auto_compact_token_limit = Some(150_000);
    let mut current_window = model("current", Some(100_000));
    current_window.max_context_window = Some(400_000);
    let mut maximum_only = model("maximum", None);
    maximum_only.max_context_window = Some(200_000);
    let mut reserved = model("reserved", Some(400_000));
    reserved.max_output_tokens = Some(128_000);
    let config = config(provider(vec![
        preset,
        model("derived", Some(400_000)),
        current_window,
        maximum_only,
        reserved,
    ]));
    config.validate().unwrap();
    for (model_id, expected) in [
        ("preset", 150_000),
        ("derived", 360_000),
        ("current", 90_000),
        ("maximum", 180_000),
        ("reserved", 272_000),
    ] {
        let route = config
            .resolve_route(
                AgentRoleId::new("executor").unwrap(),
                &ModelRouteConfig {
                    account_id: AccountId::new("fixture").unwrap(),
                    model_id: model_id.into(),
                    effort: None,
                },
            )
            .unwrap();
        assert_eq!(route.auto_compact_limit, Some(expected), "{model_id}");
    }
}

#[test]
fn unknown_or_floor_zero_capacity_never_enables_compaction() {
    for capacity in [None, Some(0), Some(1)] {
        let mut model = model("unknown", capacity);
        assert_eq!(model.default_auto_compact_token_limit(), None);
        assert_eq!(model.resolved_auto_compact_limit_with(Some(12)), None);
        model.auto_compact_token_limit = Some(20);
        assert_eq!(model.default_auto_compact_token_limit(), Some(20));
        assert_eq!(model.resolved_auto_compact_limit(), None);
        assert_eq!(model.resolved_auto_compact_limit_with(Some(12)), None);
    }
    let large = model("large", Some(u64::MAX));
    let safe = ((u128::from(u64::MAX) * 90) / 100) as u64;
    assert_eq!(large.resolved_auto_compact_limit(), Some(safe));
    assert_eq!(
        large.resolved_auto_compact_limit_with(Some(u64::MAX)),
        Some(safe)
    );
    let mut no_input_budget = model("no-input-budget", Some(100));
    for output in [100, 101] {
        no_input_budget.max_output_tokens = Some(output);
        assert_eq!(no_input_budget.resolved_auto_compact_limit(), None);
    }
}

#[test]
fn overrides_clamp_restore_and_remain_isolated_without_mutating_model_presets() {
    let mut preset = model("first", Some(400_000));
    preset.auto_compact_token_limit = Some(150_000);
    preset.max_output_tokens = Some(200_000);
    let mut first = provider(vec![preset, model("second", Some(400_000))]);
    let second_provider = first.clone();
    first
        .set_model_auto_compact_override("first", Some(500_000))
        .unwrap();
    let declared = first.effective_models(None).unwrap();
    assert_eq!(declared[0].auto_compact_token_limit, Some(150_000));
    assert_eq!(
        first.resolved_auto_compact_limit(&declared[0]),
        Some(200_000)
    );
    assert_eq!(
        first.resolved_auto_compact_limit(&declared[1]),
        Some(360_000)
    );
    assert_eq!(
        second_provider.resolved_auto_compact_limit(&declared[0]),
        Some(150_000)
    );
    first
        .set_model_auto_compact_override("second", Some(120_000))
        .unwrap();
    first
        .set_model_auto_compact_override("first", None)
        .unwrap();
    assert_eq!(
        first.resolved_auto_compact_limit(&declared[0]),
        Some(150_000)
    );
    assert_eq!(
        first.resolved_auto_compact_limit(&declared[1]),
        Some(120_000)
    );
    first
        .set_model_auto_compact_override("first", Some(150_000))
        .unwrap();
    assert_eq!(first.auto_compact_overrides().get("first"), None);
    let before = first.clone();
    assert!(
        first
            .set_model_auto_compact_override("first", Some(0))
            .is_err()
    );
    assert!(
        first
            .set_model_auto_compact_override("missing", Some(50))
            .is_err()
    );
    assert_eq!(first, before);
    first
        .set_model_auto_compact_override("second", Some(360_000))
        .unwrap();
    assert!(first.auto_compact_overrides().is_empty());
}

#[test]
fn desired_configuration_omits_defaults_and_preserves_overrides_across_round_trip() {
    let mut original = provider(vec![model("selected", Some(400_000))]);
    let empty = serde_json::to_value(&original).unwrap();
    assert!(empty["catalog"].get("auto_compact_overrides").is_none());
    let legacy: AccountConfig = serde_json::from_value(empty).unwrap();
    assert_eq!(legacy, original);
    original
        .set_model_auto_compact_override("selected", Some(123_456))
        .unwrap();
    let stored = serde_json::to_value(&original).unwrap();
    assert_eq!(
        stored["catalog"]["auto_compact_overrides"],
        json!({"selected": 123456})
    );
    let restored: AccountConfig = serde_json::from_value(stored.clone()).unwrap();
    assert_eq!(restored, original);
    config(restored).validate().unwrap();
    for invalid in [json!({"selected": 0}), json!({"missing": 123})] {
        let mut corrupted = stored.clone();
        corrupted["catalog"]["auto_compact_overrides"] = invalid;
        let parsed: AccountConfig = serde_json::from_value(corrupted).unwrap();
        assert!(config(parsed).validate().is_err());
    }
    let mut invalid_preset = model("invalid", Some(400_000));
    invalid_preset.auto_compact_token_limit = Some(0);
    assert!(invalid_preset.validate().is_err());
    assert!(config(provider(vec![invalid_preset])).validate().is_err());
}
