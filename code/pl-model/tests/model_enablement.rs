//! 模型启用、统一选择资格、路由准入与选模资料的公开行为。
//!
//! 这些用例只通过 pl-model 的公开 API 验证完整能力：禁用必须真正挡住执行，而不是只多一个
//! 字段；资料与计费类别必须绑定精确目录成员，不能靠同名或默认值蒙对。
use pl_model::config::{
    AccountConfig, AccountId, AgentModelConfig, AgentRoleId, ModelCatalogId,
    ModelRouteAvailability, ModelRouteConfig, ReasoningEffort, builtin_account_catalog,
    model_descriptor, selection_guide_descriptor,
};
use pl_model::model::{
    ModelInfo, ModelSelectionGuide, ModelSelectionSource, ModelSelectionSourceKind, ModelType,
    bundled_selection_guide, bundled_selection_guides,
};
use pl_model::protocol::ProtocolEndpoint;
use pl_protocol::BillingKind;
use pretty_assertions::assert_eq;
use serde_json::json;

fn openai_account() -> AccountConfig {
    AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(None),
        ModelCatalogId::new("openai").unwrap(),
        Vec::new(),
    )
}

fn member(account: &AccountConfig, model_id: &str) -> pl_model::config::AccountModelEntry {
    account
        .effective_catalog(None)
        .unwrap()
        .into_iter()
        .find(|entry| entry.model.model_id == model_id)
        .unwrap_or_else(|| panic!("{model_id} must stay in the effective catalog"))
}

fn selectable_ids(account: &AccountConfig) -> Vec<String> {
    account
        .selectable_catalog(Some(ModelType::Text))
        .unwrap()
        .into_iter()
        .map(|entry| entry.model.model_id)
        .collect()
}

/// 禁用保留成员、来源与其他覆盖，只是把它从选择资格里排除。
#[test]
fn disabled_model_stays_in_catalog_but_loses_selection_qualification() {
    let mut account = openai_account();
    let total = account.effective_catalog(None).unwrap().len();
    account
        .set_model_connection_mode("gpt-6-luna", pl_model::protocol::ConnectionMode::Http)
        .unwrap();
    account
        .set_model_auto_compact_override("gpt-6-luna", Some(123_456))
        .unwrap();
    account.set_model_enabled("gpt-6-luna", false).unwrap();

    // 完整目录（管理页）仍保留成员、来源与覆盖。
    assert_eq!(account.effective_catalog(None).unwrap().len(), total);
    let disabled = member(&account, "gpt-6-luna");
    assert_eq!(
        disabled.origin,
        pl_model::config::AccountModelOrigin::Bundled
    );
    assert!(!disabled.enabled);
    assert_eq!(disabled.context.auto_compact_limit, Some(123_456));
    assert_eq!(
        account.connection_overrides().get("gpt-6-luna"),
        Some(&pl_model::protocol::ConnectionMode::Http)
    );
    assert!(!model_descriptor(&disabled).enabled);
    assert!(
        model_descriptor(&disabled)
            .type_support
            .iter()
            .all(|support| support.exclusions.is_empty()),
        "启用意图不能改写类型资格"
    );

    // 选择资格排除禁用项，同时保留其他合格成员。
    let selectable = selectable_ids(&account);
    assert!(!selectable.contains(&"gpt-6-luna".to_string()));
    assert!(selectable.contains(&"gpt-6-astra".to_string()));

    // 重新启用恢复选择资格，且不产生新的成员或覆盖。
    account.set_model_enabled("gpt-6-luna", true).unwrap();
    assert!(account.disabled_models().is_empty());
    assert!(selectable_ids(&account).contains(&"gpt-6-luna".to_string()));
    assert_eq!(account.effective_catalog(None).unwrap().len(), total);
}

/// 同名模型不会被另一个账号的禁用状态污染。
#[test]
fn disabled_models_do_not_cross_account_boundaries() {
    let mut disabled_account = openai_account();
    let other_account = openai_account();
    disabled_account
        .set_model_enabled("gpt-6-astra", false)
        .unwrap();

    assert!(!selectable_ids(&disabled_account).contains(&"gpt-6-astra".to_string()));
    assert!(selectable_ids(&other_account).contains(&"gpt-6-astra".to_string()));
    assert!(member(&other_account, "gpt-6-astra").enabled);
}

/// 未知成员被拒绝且状态零修改；重复切换是幂等的。
#[test]
fn set_model_enabled_rejects_unknown_members_without_mutation() {
    let mut account = openai_account();
    account.set_model_enabled("gpt-6-luna", false).unwrap();
    let before = account.disabled_models().clone();
    assert!(account.set_model_enabled("not-a-member", false).is_err());
    assert!(account.set_model_enabled("not-a-member", true).is_err());
    assert_eq!(account.disabled_models(), &before);
    account.set_model_enabled("gpt-6-luna", false).unwrap();
    assert_eq!(account.disabled_models(), &before);
    account.set_model_enabled("gpt-6-luna", true).unwrap();
    account.set_model_enabled("gpt-6-luna", true).unwrap();
    assert!(account.disabled_models().is_empty());
}

/// 撤下再出现的同一成员继续应用保存的禁用覆盖，且不误判为配置损坏。
#[test]
fn disabled_member_survives_withdrawal_and_reappearance() {
    let mut account = openai_account();
    let inventory = account.effective_models(None).unwrap();
    account
        .set_model_catalog_overlay(inventory.clone())
        .unwrap();
    account.set_model_enabled("gpt-6-luna", false).unwrap();

    let withdrawn = inventory
        .iter()
        .filter(|model| model.model_id != "gpt-6-luna")
        .cloned()
        .collect::<Vec<ModelInfo>>();
    account.set_model_catalog_overlay(withdrawn).unwrap();
    assert!(account.disabled_models().contains("gpt-6-luna"));
    assert!(
        !account
            .effective_catalog(None)
            .unwrap()
            .iter()
            .any(|entry| entry.model.model_id == "gpt-6-luna")
    );
    let id = AccountId::new("openai-main").unwrap();
    account.validate_declarations(&id).unwrap();

    account.set_model_catalog_overlay(inventory).unwrap();
    let restored = member(&account, "gpt-6-luna");
    assert!(!restored.enabled);
    assert_eq!(
        restored.origin,
        pl_model::config::AccountModelOrigin::Online
    );
    assert!(!selectable_ids(&account).contains(&"gpt-6-luna".to_string()));
}

/// 禁用让已有路由明确不可用但不改写声明；严格解析拒绝构造请求。
#[test]
fn disabled_route_is_unavailable_but_declarations_stay_intact() {
    let mut account = openai_account();
    let effort = account
        .effective_models(None)
        .unwrap()
        .into_iter()
        .find(|model| model.model_id == "gpt-6-astra")
        .unwrap()
        .default_effort()
        .map(ReasoningEffort::new);
    let account_id = AccountId::new("openai-main").unwrap();
    let role = AgentRoleId::new("executor").unwrap();
    let route = ModelRouteConfig {
        account_id: account_id.clone(),
        model_id: "gpt-6-astra".into(),
        effort,
    };
    account.set_model_enabled("gpt-6-astra", false).unwrap();
    let mut config = AgentModelConfig {
        accounts: [(account_id.clone(), account)].into(),
        routes: [(role.clone(), route.clone())].into(),
    };

    // 声明仍然合法：禁用是 desired 状态，不是配置损坏。
    config.validate_declarations().unwrap();
    assert_eq!(
        config.route_availability(&route).unwrap(),
        ModelRouteAvailability::ModelDisabled {
            account_id: account_id.clone(),
            model_id: "gpt-6-astra".into(),
        }
    );
    let error = config.resolve(&role).unwrap_err().to_string();
    assert!(
        error.contains("disabled"),
        "resolve must name the disabled model, got {error}"
    );
    assert!(config.validate().is_err());
    assert_eq!(config.routes[&role], route);

    // 重新启用后同一声明恢复可用，选择没有被自动替换。
    config
        .accounts
        .get_mut(&account_id)
        .unwrap()
        .set_model_enabled("gpt-6-astra", true)
        .unwrap();
    assert_eq!(
        config.route_availability(&route).unwrap(),
        ModelRouteAvailability::Available
    );
    config.validate().unwrap();
    let resolved = config.resolve(&role).unwrap();
    assert_eq!(resolved.model.model_id, "gpt-6-astra");
}

/// 已解析目录缓存不能把禁用成员重新投影成可用。
#[test]
fn resolved_catalog_cache_keeps_disabled_members_unselectable() {
    let mut config = AgentModelConfig {
        accounts: [(AccountId::new("openai-main").unwrap(), openai_account())].into(),
        routes: Default::default(),
    };
    config.reconcile_model_catalog().unwrap();

    let account = config
        .accounts
        .get_mut(&AccountId::new("openai-main").unwrap())
        .unwrap();
    account.set_model_enabled("gpt-6-luna", false).unwrap();
    let cached = member(account, "gpt-6-luna");
    assert!(!cached.enabled);
    assert!(!selectable_ids(account).contains(&"gpt-6-luna".to_string()));
    assert!(
        account
            .selectable_catalog(None)
            .unwrap()
            .iter()
            .any(|entry| entry.model.model_id == "gpt-6-astra")
    );

    // 目录 overlay 更新同样不复活禁用成员。
    let inventory = account.effective_models(None).unwrap();
    account.set_model_catalog_overlay(inventory).unwrap();
    assert!(!selectable_ids(account).contains(&"gpt-6-luna".to_string()));
}

/// 计费类别来自明确模板与 canonical endpoint，与金额统计开关独立。
#[test]
fn billing_kind_follows_template_and_canonical_endpoint() {
    let registry = builtin_account_catalog().unwrap();
    let template = |id: &str| {
        registry
            .templates
            .iter()
            .find(|template| template.id.as_str() == id)
            .unwrap()
            .account
            .clone()
    };

    let coding_plan = template("zhipu-coding-plan");
    // 模板身份只参与推导，不把类别写死进配置。
    assert_eq!(coding_plan.billing_kind, None);
    assert_eq!(
        coding_plan.billing_kind().unwrap(),
        BillingKind::Subscription
    );
    // 订阅模板同时关闭金额估算：两者是独立事实。
    assert_eq!(
        coding_plan.pricing_mode,
        pl_model::model::PricingMode::Disabled
    );
    assert_eq!(
        template("mimo-token-plan").billing_kind().unwrap(),
        BillingKind::Subscription
    );
    assert_eq!(
        template("openai").billing_kind().unwrap(),
        BillingKind::Metered
    );
    assert_eq!(
        template("deepseek").billing_kind().unwrap(),
        BillingKind::Metered
    );

    // 自定义兼容入口既不是订阅也不是已知按量计价。
    let compatible = template("openai-compatible");
    assert_eq!(compatible.billing_kind().unwrap(), BillingKind::Unknown);
    assert_eq!(
        compatible.pricing_mode,
        pl_model::model::PricingMode::Disabled
    );

    // 推导只认模板自身的 canonical endpoint。
    assert_eq!(
        coding_plan.inferred_billing_kind().unwrap(),
        BillingKind::Subscription
    );
    let mut moved = coding_plan.clone();
    moved.base_url = "https://example.test/v1".into();
    assert_eq!(moved.inferred_billing_kind().unwrap(), BillingKind::Unknown);

    // 同一模板 + 非 canonical endpoint：生效类别是未知，不会被模板写成订阅。
    let proxied = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::compatible("Local proxy", "https://example.test/v1")
            .with_protocol(pl_model::protocol::ProtocolKind::Zhipu),
        ModelCatalogId::new("zhipu-responses").unwrap(),
        Vec::new(),
    )
    .with_template(pl_model::config::AccountTemplateId::new("zhipu-coding-plan").unwrap());
    assert_eq!(proxied.billing_kind, None);
    assert_eq!(proxied.billing_kind().unwrap(), BillingKind::Unknown);
    assert_eq!(
        proxied.inferred_billing_kind().unwrap(),
        BillingKind::Unknown
    );

    // 用户显式选择独立保留，即使与推导结果不同。
    let mut explicit = coding_plan.clone();
    explicit.billing_kind = Some(BillingKind::Metered);
    assert_eq!(explicit.billing_kind().unwrap(), BillingKind::Metered);
    assert_eq!(
        explicit.inferred_billing_kind().unwrap(),
        BillingKind::Subscription
    );

    let custom = openai_account();
    assert_eq!(custom.billing_kind, None);
    assert_eq!(custom.billing_kind().unwrap(), BillingKind::Unknown);
    assert_eq!(
        custom.inferred_billing_kind().unwrap(),
        BillingKind::Unknown
    );

    // 旧配置缺这两个字段时按「全部启用、计费未知」解码，而不是猜成订阅。
    let legacy: AccountConfig = serde_json::from_value(json!({
        "protocol": "open_ai",
        "name": "legacy",
        "base_url": "https://api.openai.com/v1",
        "catalog": {
            "source": "bundled",
            "catalog": "openai",
            "additional_models": []
        }
    }))
    .unwrap();
    assert_eq!(legacy.billing_kind, None);
    assert_eq!(legacy.billing_kind().unwrap(), BillingKind::Unknown);
    assert!(legacy.disabled_models().is_empty());
    assert!(
        legacy
            .effective_catalog(None)
            .unwrap()
            .iter()
            .all(|entry| entry.enabled)
    );
}

/// 选模资料按精确目录成员绑定，并带有可核对的测量条件。
#[test]
fn selection_guides_bind_exact_catalog_members() {
    builtin_account_catalog().unwrap().validate().unwrap();
    assert!(!bundled_selection_guides().is_empty());

    let luna = bundled_selection_guide("openai", "gpt-6-luna").expect("luna guide");
    assert!(luna.summary.chars().count() <= 240);
    assert!(luna.sources.len() <= 6);
    let benchmark = luna
        .sources
        .iter()
        .find(|source| source.kind == ModelSelectionSourceKind::Benchmark)
        .expect("luna keeps its measured index");
    let measurement = benchmark.measurement.as_ref().unwrap();
    assert_eq!(measurement.model, "GPT-6 Luna");
    assert_eq!(measurement.effort, Some("max"));
    assert_eq!(measurement.metric_version, Some("v4.3.2"));
    assert_eq!(measurement.score, Some(38.0));

    // 全部内置资料的分数都必须绑定明确的指标版本，否则不可比。
    for bundled in bundled_selection_guides() {
        for source in bundled.guide.sources {
            let Some(measurement) = source.measurement.as_ref() else {
                continue;
            };
            if measurement.score.is_some() {
                assert!(
                    measurement
                        .metric_version
                        .is_some_and(|version| !version.trim().is_empty()),
                    "{} keeps an unscoped score",
                    bundled.model_id
                );
            }
        }
    }

    // 版本化测量的精确型号不能被别名冒充。
    let deepseek = bundled_selection_guide("deepseek", "deepseek-v4-pro").expect("v4 pro guide");
    let versions = deepseek
        .sources
        .iter()
        .filter_map(|source| source.measurement.as_ref())
        .map(|measurement| measurement.model)
        .collect::<Vec<_>>();
    assert!(versions.contains(&"DeepSeek V4 Pro 0813"));

    // 不跨目录、不按同名模型补写资料。
    assert!(bundled_selection_guide("deepseek", "gpt-6-luna").is_none());
    assert!(bundled_selection_guide("openai", "mimo-v2.5-pro").is_none());
    assert!(bundled_selection_guide("openai", "gpt-5.5").is_none());

    // 同一供应商的多套目录显式共享资料。
    assert_eq!(
        bundled_selection_guide("zhipu", "glm-5.3"),
        bundled_selection_guide("zhipu-responses", "glm-5.3")
    );
}

/// 账号只在「自己的绑定目录 + 当前非手工成员」上取资料。
///
/// 撤下、手工同 ID 覆盖、显式自定义目录都必须是 `None`；目录读取失败必须上报错误，
/// 不能被伪装成「没有资料」。
#[test]
fn account_selection_guide_requires_current_non_manual_member() {
    let account = openai_account();
    let guide = account
        .model_selection_guide("gpt-6-astra")
        .unwrap()
        .expect("bundled guide");
    assert!(guide.summary.contains("旗舰"));
    // 其他目录的 model_id 不在本账号目录里，不回落到系统目录。
    assert!(account.model_selection_guide("glm-5.3").unwrap().is_none());

    // 在线目录撤下成员：当前没有该成员，不返回原资料。
    let mut withdrawn = openai_account();
    let inventory = withdrawn.effective_models(None).unwrap();
    withdrawn
        .set_model_catalog_overlay(
            inventory
                .iter()
                .filter(|model| model.model_id != "gpt-6-luna")
                .cloned()
                .collect(),
        )
        .unwrap();
    assert!(
        withdrawn
            .model_selection_guide("gpt-6-luna")
            .unwrap()
            .is_none()
    );

    // 同 ID 的手工覆盖由用户定义语义，不附内置资料。
    let mut manual = inventory
        .iter()
        .find(|model| model.model_id == "gpt-6-astra")
        .unwrap()
        .clone();
    manual.display_name = "Astra (local proxy)".into();
    let overridden = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(None),
        ModelCatalogId::new("openai").unwrap(),
        vec![manual],
    );
    assert_eq!(
        member(&overridden, "gpt-6-astra").origin,
        pl_model::config::AccountModelOrigin::Manual
    );
    assert!(
        overridden
            .model_selection_guide("gpt-6-astra")
            .unwrap()
            .is_none()
    );

    // 显式自定义目录没有内置资料。
    let explicit = AccountConfig::from_explicit_models(
        ProtocolEndpoint::openai(None),
        account.effective_models(None).unwrap(),
    );
    assert!(
        explicit
            .model_selection_guide("gpt-6-astra")
            .unwrap()
            .is_none()
    );

    // 目录读取失败上报错误，而不是返回 None。
    let mut broken = inventory
        .iter()
        .find(|model| model.model_id == "gpt-6-astra")
        .unwrap()
        .clone();
    broken.binding.transport.supported_connection_modes.clear();
    let broken = AccountConfig::from_bundled_catalog(
        ProtocolEndpoint::openai(None),
        ModelCatalogId::new("openai").unwrap(),
        vec![broken],
    );
    assert!(broken.model_selection_guide("gpt-6-astra").is_err());
}

/// 分数必须绑定指标版本；没有版本时只能不保留分数。
#[test]
fn selection_guide_rejects_unscoped_scores() {
    let guide = ModelSelectionGuide {
        summary: "scoped score fixture",
        task_suitability: &[pl_protocol::AgentTaskCategory::Coding],
        limitations: &[],
        sources: &[ModelSelectionSource {
            kind: ModelSelectionSourceKind::Benchmark,
            url: "https://example.test/benchmark",
            verified_at: 1_792_627_200,
            measurement: Some(pl_model::model::ModelSelectionMeasurement {
                model: "fixture",
                effort: Some("max"),
                metric: "Artificial Analysis Intelligence Index",
                metric_version: None,
                score: Some(99.0),
            }),
        }],
    };
    assert_eq!(
        guide.validate(),
        Err(pl_model::model::ModelSelectionGuideError::MissingMetricVersion)
    );
}

/// wire 投影只搬运资料，并把测量条件保留成结构化字段。
#[test]
fn selection_guide_projection_keeps_measurement_conditions() {
    let guide = bundled_selection_guide("openai", "gpt-6-luna").unwrap();
    let dto = selection_guide_descriptor(guide);
    let value = serde_json::to_value(&dto).unwrap();
    assert!(value["summary"].as_str().unwrap().chars().count() <= 240);
    assert!(
        value["taskSuitability"]
            .as_array()
            .unwrap()
            .contains(&json!("coding"))
    );
    let benchmark = value["sources"]
        .as_array()
        .unwrap()
        .iter()
        .find(|source| source["kind"] == "benchmark")
        .unwrap();
    assert_eq!(benchmark["measurement"]["model"], "GPT-6 Luna");
    assert_eq!(benchmark["measurement"]["effort"], "max");
    assert_eq!(benchmark["measurement"]["metricVersion"], "v4.3.2");
    assert_eq!(benchmark["measurement"]["score"], 38.0);
    assert_eq!(benchmark["verifiedAt"], 1_792_627_200);
}
