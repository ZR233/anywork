//! 自动压缩阈值从模型声明和 provider 用户选择解析，配置中只保存覆盖。

use std::collections::BTreeMap;

use pl_model::config::{AccountConfig, AccountId, AgentModelConfig, AgentRoleId, ModelRouteConfig};
use pl_model::model::ModelDefinition;
use pretty_assertions::assert_eq;
use serde_json::json;

fn model(model_id: &str, capacity: Option<u64>) -> ModelDefinition {
    let mut model = ModelDefinition::compatible(model_id);
    model.base.context_window = capacity;
    model.base.max_context_window = capacity;
    model.extra.max_output_tokens = None;
    model
}

fn provider(models: Vec<ModelDefinition>) -> AccountConfig {
    AccountConfig::from_explicit_models(
        pl_model::protocol::providers::openai::compatible_endpoint(
            "Fixture",
            "https://example.test/v1",
        ),
        models,
    )
}

fn config(provider: AccountConfig) -> AgentModelConfig {
    AgentModelConfig {
        accounts: [(AccountId::new("fixture").unwrap(), provider)].into(),
        routes: BTreeMap::new(),
    }
}

fn resolved(account: &AccountConfig, model: &ModelDefinition) -> Option<u64> {
    account
        .effective_catalog(None)
        .unwrap()
        .into_iter()
        .find(|entry| entry.model.base.slug == model.base.slug)
        .unwrap()
        .context
        .auto_compact_limit
}

#[test]
fn catalog_filter_route_and_descriptor_share_context_resolution() {
    use pl_model::model::ModelContextUnavailable;
    use pl_model::{config::model_descriptor, model::ModelType};
    let mut exhausted = model("exhausted", Some(100));
    exhausted.extra.max_output_tokens = Some(100);
    let account = provider(vec![
        model("unknown", None),
        exhausted,
        model("tiny", Some(1)),
        model("valid", Some(100)),
    ]);
    let catalog = account.effective_catalog(None).unwrap();
    assert_eq!(catalog.len(), 4);
    assert_eq!(
        account
            .effective_models(Some(ModelType::Text))
            .unwrap()
            .iter()
            .map(|model| model.base.slug.as_str())
            .collect::<Vec<_>>(),
        ["exhausted", "tiny", "unknown", "valid"]
    );
    for entry in catalog {
        let descriptor = model_descriptor(&entry);
        assert_eq!(descriptor.context, entry.context);
        assert_eq!(
            descriptor.type_support,
            [entry.type_support(ModelType::Text)]
        );
        let available = entry.type_support(ModelType::Text).exclusions.is_empty();
        let config = config(account.clone());
        let route = ModelRouteConfig {
            account_id: AccountId::new("fixture").unwrap(),
            model_id: entry.model.base.slug.clone(),
            effort: None,
        };
        assert_eq!(
            config
                .resolve_route(AgentRoleId::new("executor").unwrap(), &route)
                .is_ok(),
            available
        );
        if entry.model.base.slug == "tiny" {
            assert_eq!(entry.context.auto_compact_limit, None);
            assert!(
                available,
                "disabled automatic compaction is not context invalidity"
            );
        }
    }
    let mut inconsistent = model("invalid", Some(100));
    inconsistent.base.max_context_window = Some(99);
    assert_eq!(
        inconsistent.resolve_context(None).unavailable,
        Some(ModelContextUnavailable::InvalidParameters)
    );
}

#[test]
fn route_defaults_reserve_output_within_the_current_capacity() {
    let mut preset = model("preset", Some(400_000));
    preset.base.auto_compact_token_limit = Some(150_000);
    let mut current_window = model("current", Some(100_000));
    current_window.base.max_context_window = Some(400_000);
    let mut maximum_only = model("maximum", None);
    maximum_only.base.max_context_window = Some(200_000);
    let mut reserved = model("reserved", Some(400_000));
    reserved.extra.max_output_tokens = Some(128_000);
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
        ("reserved", 360_000),
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
        assert_eq!(
            route.context.auto_compact_limit,
            Some(expected),
            "{model_id}"
        );
    }
}

#[test]
fn unknown_or_floor_zero_capacity_never_enables_compaction() {
    for capacity in [Some(0), Some(1)] {
        let mut model = model("unknown", capacity);

        assert_eq!(model.resolve_context(Some(12)).auto_compact_limit, None);
        model.base.auto_compact_token_limit = Some(20);

        assert_eq!(model.resolve_context(None).auto_compact_limit, None);
        assert_eq!(model.resolve_context(Some(12)).auto_compact_limit, None);
    }
    assert_eq!(
        model("unknown", None)
            .resolve_context(Some(12))
            .auto_compact_limit,
        Some(12)
    );
    let large = model("large", Some(u64::MAX));
    let safe = ((u128::from(u64::MAX) * 90) / 100) as u64;
    assert_eq!(large.resolve_context(None).auto_compact_limit, Some(safe));
    assert_eq!(
        large.resolve_context(Some(u64::MAX)).auto_compact_limit,
        Some(safe)
    );
    let mut no_input_budget = model("no-input-budget", Some(100));
    for output in [100, 101] {
        no_input_budget.extra.max_output_tokens = Some(output);
        assert_eq!(
            no_input_budget.resolve_context(None).auto_compact_limit,
            Some(90)
        );
    }
}

#[test]
fn overrides_clamp_restore_and_remain_isolated_without_mutating_model_presets() {
    let mut preset = model("first", Some(400_000));
    preset.base.auto_compact_token_limit = Some(150_000);
    preset.extra.max_output_tokens = Some(200_000);
    let mut first = provider(vec![preset, model("second", Some(400_000))]);
    let second_provider = first.clone();
    first
        .set_model_auto_compact_override("first", Some(350_000))
        .unwrap();
    let declared = first.effective_models(None).unwrap();
    assert_eq!(declared[0].base.auto_compact_token_limit, Some(150_000));
    assert_eq!(resolved(&first, &declared[0]), Some(350_000));
    assert_eq!(resolved(&first, &declared[1]), Some(360_000));
    assert_eq!(resolved(&second_provider, &declared[0]), Some(150_000));
    first
        .set_model_auto_compact_override("second", Some(120_000))
        .unwrap();
    first
        .set_model_auto_compact_override("first", None)
        .unwrap();
    assert_eq!(resolved(&first, &declared[0]), Some(150_000));
    assert_eq!(resolved(&first, &declared[1]), Some(120_000));
    first
        .set_model_auto_compact_override("first", Some(150_000))
        .unwrap();
    assert_eq!(first.auto_compact_overrides().get("first"), Some(&150_000));
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
    assert_eq!(first.auto_compact_overrides().get("second"), Some(&360_000));
}

#[test]
fn override_edits_are_atomic_and_persist_only_valid_selections() {
    let mut original = provider(vec![model("selected", Some(400_000))]);
    original
        .replace_model_auto_compact_overrides([("selected".into(), 123_456)].into())
        .unwrap();
    let stored = serde_json::to_value(&original).unwrap();
    let restored: AccountConfig = serde_json::from_value(stored.clone()).unwrap();
    assert_eq!(restored, original);
    for invalid in [
        [("selected".into(), 0)].into(),
        [("selected".into(), 234_567), ("unknown".into(), 50)].into(),
    ] {
        let before = original.clone();
        assert!(
            original
                .replace_model_auto_compact_overrides(invalid)
                .is_err()
        );
        assert_eq!(original, before, "a rejected account edit is atomic");
    }
    original
        .replace_model_auto_compact_overrides([("selected".into(), 360_000)].into())
        .unwrap();
    assert_eq!(
        original.auto_compact_overrides().get("selected"),
        Some(&360_000)
    );
    config(restored).validate().unwrap();
    for invalid in [json!({"selected": 0}), json!({"missing": 123})] {
        let mut corrupted = stored.clone();
        corrupted["catalog"]["auto_compact_overrides"] = invalid;
        let parsed: AccountConfig = serde_json::from_value(corrupted).unwrap();
        assert!(config(parsed).validate().is_err());
    }
    let mut invalid_preset = model("invalid", Some(400_000));
    invalid_preset.base.auto_compact_token_limit = Some(0);
    assert!(invalid_preset.validate().is_err());
    assert!(config(provider(vec![invalid_preset])).validate().is_err());
}

#[test]
fn explicit_threshold_uses_the_maximum_capacity_for_admission_and_execution() {
    let mut astra = model("gpt-6.2-astra", Some(272_000));
    astra.base.max_context_window = Some(872_000);
    astra.extra.max_output_tokens = Some(128_000);
    let mut account = provider(vec![astra.clone()]);
    assert_eq!(resolved(&account, &astra), Some(244_800));
    account
        .set_model_auto_compact_override(&astra.base.slug, Some(700_000))
        .unwrap();
    assert_eq!(resolved(&account, &astra), Some(700_000));
    account
        .set_model_auto_compact_override(&astra.base.slug, Some(784_800))
        .unwrap();
    assert!(
        account
            .set_model_auto_compact_override(&astra.base.slug, Some(784_801))
            .is_err()
    );
    account
        .set_model_auto_compact_override(&astra.base.slug, None)
        .unwrap();
    assert_eq!(resolved(&account, &astra), Some(244_800));
}
