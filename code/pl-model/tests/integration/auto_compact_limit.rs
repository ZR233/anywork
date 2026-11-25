//! 自动压缩阈值从模型声明和 provider 用户选择解析，配置中只保存覆盖。

use std::collections::BTreeMap;

use pl_model::config::{
    AccountConfig, AccountId, AccountModelOrigin, AgentModelConfig, AgentRoleId, ModelCatalogId,
    ModelRouteConfig,
};
use pl_model::model::{
    AutoCompactDefaultPolicy, DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT, ModelDefinition,
};
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
        match entry.model.base.slug.as_str() {
            "unknown" => {
                assert_eq!(entry.context.context_window, None);
                assert_eq!(
                    entry.context.auto_compact_limit,
                    Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
                );
                assert!(available);
            }
            "tiny" => {
                assert_eq!(entry.context.auto_compact_limit, None);
                assert!(
                    available,
                    "disabled automatic compaction is not context invalidity"
                );
            }
            _ => {}
        }
    }
    let mut inconsistent = model("invalid", Some(100));
    inconsistent.base.max_context_window = Some(99);
    assert_eq!(
        inconsistent
            .resolve_context(None, AutoCompactDefaultPolicy::Bundled)
            .unavailable,
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
        ("derived", DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
        ("current", 90_000),
        ("maximum", 180_000),
        ("reserved", DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
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
    for policy in [
        AutoCompactDefaultPolicy::Bundled,
        AutoCompactDefaultPolicy::UnbundledOrManual,
    ] {
        for capacity in [Some(0), Some(1)] {
            let mut model = model("unknown", capacity);

            assert_eq!(
                model.resolve_context(Some(12), policy).auto_compact_limit,
                None
            );
            model.base.auto_compact_token_limit = Some(20);

            assert_eq!(model.resolve_context(None, policy).auto_compact_limit, None);
            assert_eq!(
                model.resolve_context(Some(12), policy).auto_compact_limit,
                None
            );
        }
    }
    assert_eq!(
        model("unknown", None)
            .resolve_context(None, AutoCompactDefaultPolicy::Bundled)
            .auto_compact_limit,
        None
    );
    assert_eq!(
        model("unknown", None)
            .resolve_context(None, AutoCompactDefaultPolicy::UnbundledOrManual)
            .auto_compact_limit,
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );
    assert_eq!(
        model("unknown", None)
            .resolve_context(Some(12), AutoCompactDefaultPolicy::UnbundledOrManual)
            .auto_compact_limit,
        Some(12)
    );
    let large = model("large", Some(u64::MAX));
    let safe = ((u128::from(u64::MAX) * 90) / 100) as u64;
    assert_eq!(
        large
            .resolve_context(None, AutoCompactDefaultPolicy::Bundled)
            .auto_compact_limit,
        Some(safe)
    );
    assert_eq!(
        large
            .resolve_context(None, AutoCompactDefaultPolicy::UnbundledOrManual)
            .auto_compact_limit,
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );
    assert_eq!(
        large
            .resolve_context(Some(u64::MAX), AutoCompactDefaultPolicy::UnbundledOrManual)
            .auto_compact_limit,
        Some(safe)
    );
    let mut no_input_budget = model("no-input-budget", Some(100));
    for output in [100, 101] {
        no_input_budget.extra.max_output_tokens = Some(output);
        for policy in [
            AutoCompactDefaultPolicy::Bundled,
            AutoCompactDefaultPolicy::UnbundledOrManual,
        ] {
            assert_eq!(
                no_input_budget
                    .resolve_context(None, policy)
                    .auto_compact_limit,
                Some(90)
            );
        }
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
    assert_eq!(
        resolved(&first, &declared[1]),
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );
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
    assert_eq!(resolved(&first, &declared[1]), Some(360_000));
    first
        .set_model_auto_compact_override("second", None)
        .unwrap();
    assert_eq!(
        resolved(&first, &declared[1]),
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );
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

#[test]
fn manual_unknown_context_defaults_to_256k_without_polluting_config_and_survives_reconcile() {
    let mut cfg = config(provider(vec![model("manual-unknown", None)]));
    let account = cfg
        .accounts
        .get_mut(&AccountId::new("fixture").unwrap())
        .unwrap();
    let stored = serde_json::to_value(&*account).unwrap();
    assert_eq!(
        stored["catalog"]["models"],
        json!([{"base": {"slug": "manual-unknown"}}]),
        "256K fallback must stay out of serialized manual model declarations"
    );

    let entry = account.effective_catalog(None).unwrap().remove(0);
    assert_eq!(entry.origin, AccountModelOrigin::Manual);
    assert_eq!(entry.context.context_window, None);
    assert_eq!(
        entry.context.auto_compact_limit,
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );

    // Reconcile caches resolved_catalog; set/replace/clear overrides must preserve 256K fallback.
    cfg.reconcile_model_catalog().unwrap();
    let account = cfg
        .accounts
        .get_mut(&AccountId::new("fixture").unwrap())
        .unwrap();
    assert_eq!(
        account.effective_catalog(None).unwrap()[0]
            .context
            .auto_compact_limit,
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );

    account
        .set_model_auto_compact_override("manual-unknown", Some(500_000))
        .unwrap();
    assert_eq!(
        account.effective_catalog(None).unwrap()[0]
            .context
            .auto_compact_limit,
        Some(500_000)
    );

    account
        .set_model_auto_compact_override("manual-unknown", None)
        .unwrap();
    assert_eq!(
        account.effective_catalog(None).unwrap()[0]
            .context
            .auto_compact_limit,
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );

    account
        .replace_model_auto_compact_overrides([("manual-unknown".into(), 300_000)].into())
        .unwrap();
    assert_eq!(
        account.effective_catalog(None).unwrap()[0]
            .context
            .auto_compact_limit,
        Some(300_000)
    );
    account
        .replace_model_auto_compact_overrides(BTreeMap::new())
        .unwrap();
    assert_eq!(
        account.effective_catalog(None).unwrap()[0]
            .context
            .auto_compact_limit,
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );
}

#[test]
fn explicit_auto_compact_limit_on_manual_model_is_never_clamped_down_to_fallback() {
    let mut large_explicit = model("manual-explicit-large", Some(1_000_000));
    large_explicit.base.auto_compact_token_limit = Some(400_000);
    let mut unknown_explicit = model("manual-explicit-unknown", None);
    unknown_explicit.base.auto_compact_token_limit = Some(400_000);

    let account = provider(vec![large_explicit, unknown_explicit]);
    let catalog = account.effective_catalog(None).unwrap();
    let large = catalog
        .iter()
        .find(|entry| entry.model.base.slug == "manual-explicit-large")
        .unwrap();
    let unknown = catalog
        .iter()
        .find(|entry| entry.model.base.slug == "manual-explicit-unknown")
        .unwrap();
    assert_eq!(large.context.auto_compact_limit, Some(400_000));
    assert_eq!(unknown.context.auto_compact_limit, Some(400_000));
}

#[test]
fn unified_256k_fallback_applies_across_openai_compatible_and_gemini_protocols() {
    use pl_model::model::bundled_model_definition;

    let limit_for = |account: &AccountConfig, model_id: &str| {
        account
            .effective_catalog(None)
            .unwrap()
            .into_iter()
            .find(|entry| entry.model.base.slug == model_id)
            .unwrap_or_else(|| panic!("missing model {model_id}"))
            .context
            .auto_compact_limit
    };

    // 1. OpenAI Bundled account:
    //    - sparse manual override of bundled slug ("gpt-6.2-sol") retains bundled policy (90%)
    //    - new manual model uses UnbundledOrManual (256K fallback)
    //    - online models matching bundled keep bundled policy (or online 90% / explicit limit)
    //    - online models without bundled match use min(256K, 90%) or 256K when context unknown
    let mut bundled_override = ModelDefinition::compatible("gpt-6.2-sol");
    bundled_override.base.display_name = "Custom GPT-6.2 Sol".into();
    let custom_manual = model("my-custom-openai-model", Some(500_000));
    let mut openai = AccountConfig::from_bundled_catalog(
        pl_model::protocol::providers::openai::endpoint(None),
        ModelCatalogId::new("openai").unwrap(),
        vec![bundled_override, custom_manual],
    );

    let online_bundled_match = bundled_model_definition("openai")
        .unwrap()
        .models
        .into_iter()
        .find(|m| m.base.slug == "gpt-6.2-astra")
        .unwrap();
    let mut online_unbundled_unknown = ModelDefinition::compatible("ft:gpt-unknown");
    online_unbundled_unknown
        .extra
        .binding
        .set_transport(online_bundled_match.extra.binding.transport.clone());
    let mut online_unbundled_small = model("ft:gpt-small", Some(128_000));
    online_unbundled_small
        .extra
        .binding
        .set_transport(online_bundled_match.extra.binding.transport.clone());
    let mut online_unbundled_large = model("ft:gpt-large", Some(1_000_000));
    online_unbundled_large
        .extra
        .binding
        .set_transport(online_bundled_match.extra.binding.transport.clone());
    let mut online_unbundled_explicit = model("ft:gpt-explicit", Some(1_000_000));
    online_unbundled_explicit.base.auto_compact_token_limit = Some(400_000);
    online_unbundled_explicit
        .extra
        .binding
        .set_transport(online_bundled_match.extra.binding.transport.clone());

    openai
        .set_model_catalog_overlay(vec![
            online_bundled_match,
            online_unbundled_unknown,
            online_unbundled_small,
            online_unbundled_large,
            online_unbundled_explicit,
        ])
        .unwrap();

    // 2. Gemini Bundled account:
    //    - bundled/online bundled match "gemini-4-hydrogen" stays 512_000
    //    - online unbundled models follow min(256K, 90%) or 256K
    let mut gemini_override = ModelDefinition::compatible("gemini-4-carbon");
    gemini_override.base.display_name = "Custom Gemini 4 Carbon".into();
    let mut gemini_manual = model("my-gemini-manual", None);
    let gemini_bundled = bundled_model_definition("gemini")
        .unwrap()
        .models
        .into_iter()
        .find(|m| m.base.slug == "gemini-4-hydrogen")
        .unwrap();
    gemini_manual
        .extra
        .binding
        .set_transport(gemini_bundled.extra.binding.transport.clone());
    let mut gemini = AccountConfig::from_bundled_catalog(
        pl_model::protocol::providers::gemini::gemini_api_endpoint(None),
        ModelCatalogId::new("gemini").unwrap(),
        vec![gemini_override, gemini_manual],
    );
    let mut gemini_online_large = model("gemini-4.5-pro", Some(1_048_576));
    gemini_online_large
        .extra
        .binding
        .set_transport(gemini_bundled.extra.binding.transport.clone());
    let mut gemini_online_small = model("gemini-4.5-nano", Some(128_000));
    gemini_online_small
        .extra
        .binding
        .set_transport(gemini_bundled.extra.binding.transport.clone());
    let mut gemini_online_unknown = ModelDefinition::compatible("gemini-exp-unknown");
    gemini_online_unknown
        .extra
        .binding
        .set_transport(gemini_bundled.extra.binding.transport.clone());
    gemini
        .set_model_catalog_overlay(vec![
            gemini_bundled,
            gemini_online_large,
            gemini_online_small,
            gemini_online_unknown,
        ])
        .unwrap();

    // 3. OpenAI-compatible Explicit account with both online discovery and manual entries
    let mut compat = provider(vec![model("compat-manual-unknown", None)]);
    let compat_online_unknown = ModelDefinition::compatible("compat-online-unknown");
    let compat_online_small = model("compat-online-small", Some(200_000));
    let compat_online_large = model("compat-online-large", Some(1_000_000));
    compat
        .set_model_catalog_overlay(vec![
            compat_online_unknown,
            compat_online_small,
            compat_online_large,
        ])
        .unwrap();

    let mut cfg = AgentModelConfig {
        accounts: [
            (AccountId::new("openai").unwrap(), openai),
            (AccountId::new("gemini").unwrap(), gemini),
            (AccountId::new("compat").unwrap(), compat),
        ]
        .into(),
        routes: BTreeMap::new(),
    };

    for check_phase in ["before-reconcile", "after-reconcile"] {
        if check_phase == "after-reconcile" {
            cfg.reconcile_model_catalog().unwrap();
        }
        let openai = &cfg.accounts[&AccountId::new("openai").unwrap()];
        assert_eq!(
            limit_for(openai, "gpt-6.2-sol"),
            Some(945_000),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(openai, "gpt-6.2-astra"),
            Some(945_000),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(openai, "my-custom-openai-model"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(openai, "ft:gpt-unknown"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(openai, "ft:gpt-small"),
            Some(115_200),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(openai, "ft:gpt-large"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(openai, "ft:gpt-explicit"),
            Some(400_000),
            "{check_phase}"
        );

        let gemini = &cfg.accounts[&AccountId::new("gemini").unwrap()];
        assert_eq!(
            limit_for(gemini, "gemini-4-hydrogen"),
            Some(512_000),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(gemini, "gemini-4-carbon"),
            Some(512_000),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(gemini, "my-gemini-manual"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(gemini, "gemini-4.5-pro"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(gemini, "gemini-4.5-nano"),
            Some(115_200),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(gemini, "gemini-exp-unknown"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );

        let compat = &cfg.accounts[&AccountId::new("compat").unwrap()];
        assert_eq!(
            limit_for(compat, "compat-online-unknown"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(compat, "compat-online-small"),
            Some(180_000),
            "{check_phase}"
        );
        assert_eq!(
            limit_for(compat, "compat-online-large"),
            Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT),
            "{check_phase}"
        );
    }

    // Large-context unbundled model still allows user overrides up to 90% of context_window.
    let openai = cfg
        .accounts
        .get_mut(&AccountId::new("openai").unwrap())
        .unwrap();
    openai
        .set_model_auto_compact_override("ft:gpt-large", Some(900_000))
        .unwrap();
    assert_eq!(limit_for(openai, "ft:gpt-large"), Some(900_000));
    assert!(
        openai
            .set_model_auto_compact_override("ft:gpt-large", Some(900_001))
            .is_err()
    );
    openai
        .set_model_auto_compact_override("ft:gpt-large", None)
        .unwrap();
    assert_eq!(
        limit_for(openai, "ft:gpt-large"),
        Some(DEFAULT_FALLBACK_AUTO_COMPACT_LIMIT)
    );
}
