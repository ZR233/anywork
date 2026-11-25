use pl_model::{
    config::{
        AccountConfig, AccountModelEntry, AccountModelOrigin, ModelDescriptor, model_descriptor,
    },
    model::{ModelDefinition, ModelParameter},
};
use serde_json::json;

#[test]
fn local_model_definition_cannot_publish_a_codex_service_tier() {
    let mut model = ModelDefinition::compatible("manual-model");
    model.extra.parameters.push(
        serde_json::from_value(json!({
            "name": "service_tier",
            "candidates": ["priority"],
            "wire": {"priority": {"set": [{"path": "service_tier", "value": "priority"}]}}
        }))
        .unwrap(),
    );
    let account = AccountConfig::from_explicit_models(
        pl_model::protocol::providers::openai::compatible_endpoint(
            "Manual fixture",
            "http://127.0.0.1:0",
        ),
        vec![model],
    );
    let catalog = account.effective_catalog(None).unwrap();
    assert_eq!(catalog.len(), 1);
    assert!(model_descriptor(&catalog[0]).service_tiers.is_none());
}

#[test]
fn service_tiers_descriptor_preserves_order_names_and_read_only_default() {
    let mut model = ModelDefinition::compatible("fixture-model");
    model.extra.parameters.push(
        serde_json::from_value::<ModelParameter>(json!({
            "name":"service_tier", "default":"ultrafast",
            "candidates":["ultrafast","priority","unnamed"],
            "candidateDisplayNames":{"ultrafast":" Ultrafast ","priority":"Fast","unnamed":"  "},
            "wire": {
                "ultrafast":{"set":[{"path":"service_tier","value":"ultrafast"}]},
                "priority":{"set":[{"path":"service_tier","value":"priority"}]},
                "unnamed":{"set":[{"path":"service_tier","value":"unnamed"}]}
            }
        }))
        .unwrap(),
    );
    let entry = AccountModelEntry::new(model, AccountModelOrigin::Online);
    let descriptor = model_descriptor(&entry);
    let tiers = descriptor.service_tiers.as_ref().unwrap();
    assert_eq!(tiers.default.as_deref(), Some("ultrafast"));
    assert_eq!(
        tiers
            .candidates
            .iter()
            .map(|tier| tier.id.as_str())
            .collect::<Vec<_>>(),
        ["ultrafast", "priority", "unnamed"]
    );
    assert_eq!(
        tiers
            .candidates
            .iter()
            .map(|tier| tier.display_name.as_deref())
            .collect::<Vec<_>>(),
        [Some(" Ultrafast "), Some("Fast"), None]
    );
    assert!(descriptor.reasoning.is_none());
    let wire = serde_json::to_value(descriptor).unwrap();
    assert_eq!(
        wire["serviceTiers"]["candidates"][0],
        json!({"id":"ultrafast","displayName":" Ultrafast "})
    );
}

#[test]
fn previous_parameter_and_descriptor_payloads_remain_readable_without_tiers() {
    let parameter: ModelParameter = serde_json::from_value(json!({
        "name":"effort","candidates":["high"],
        "wire":{"high":{"set":[{"path":"reasoning.effort","value":"high"}]}}
    }))
    .unwrap();
    assert!(parameter.candidate_display_names.is_empty());
    let model = ModelDefinition::compatible("old-model");
    let descriptor = model_descriptor(&AccountModelEntry::new(model, AccountModelOrigin::Manual));
    let mut wire = serde_json::to_value(descriptor).unwrap();
    wire.as_object_mut().unwrap().remove("serviceTiers");
    let restored: ModelDescriptor = serde_json::from_value(wire).unwrap();
    assert!(restored.service_tiers.is_none());
}
