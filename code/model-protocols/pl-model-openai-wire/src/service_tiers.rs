//! Codex catalog declarations and the bounded Responses HTTP service-tier selection.
use std::collections::BTreeMap;

use serde::Deserialize;
use serde_json::Value;

use crate::{
    model::{ModelDefinition, ModelParameter, ParameterWire, WireAssignment},
    protocol::{ConnectionMode, ProtocolEndpoint, WireApi},
};
use pl_protocol::{PureError, Result};

/// Only an authenticated Codex workspace on the official protocol owns this capability.
pub fn supports_endpoint(endpoint: &ProtocolEndpoint) -> bool {
    endpoint.protocol.as_str() == "open_ai"
        && endpoint
            .authorization
            .as_ref()
            .is_some_and(|auth| auth.workspace_id().is_some())
}

/// Whether a request on this route can select an explicit service tier.
pub fn has_selectable_tier(endpoint: &ProtocolEndpoint, model: &ModelDefinition) -> bool {
    supports_endpoint(endpoint)
        && model.extra.parameters.iter().any(|parameter| {
            parameter.name == "service_tier"
                && parameter
                    .candidates
                    .iter()
                    .any(|tier| validate_model(model, Some(tier)).is_ok())
        })
}

/// Validates an explicit choice without applying the catalog's default or first candidate.
///
/// # Errors
/// Returns a configuration error for an unsupported identity, transport, candidate or wire rule.
pub fn validate(
    endpoint: &ProtocolEndpoint,
    model: &ModelDefinition,
    requested: Option<&str>,
) -> Result<()> {
    validate_model(model, requested)?;
    if requested.is_some() && !supports_endpoint(endpoint) {
        return Err(PureError::ConfigError(
            "service_tier requires authenticated Codex workspace Responses HTTP".into(),
        ));
    }
    Ok(())
}

pub(crate) fn validate_model(model: &ModelDefinition, requested: Option<&str>) -> Result<()> {
    let Some(requested) = requested else {
        return Ok(());
    };
    if model.extra.binding.transport.protocol != WireApi::Responses
        || model.extra.binding.transport.default_connection_mode != ConnectionMode::Http
        || !model.extra.parameters.iter().any(|parameter| {
            parameter.name == "service_tier"
                && parameter.has_candidate(requested)
                && parameter.wire_for(requested).is_some_and(|wire| {
                    wire.remove.is_empty()
                        && wire.set
                            == [WireAssignment {
                                path: "service_tier".into(),
                                value: Value::String(requested.into()),
                            }]
                })
        })
    {
        return Err(PureError::ConfigError(format!(
            "unsupported service_tier {requested:?} for the authenticated model route"
        )));
    }
    Ok(())
}

/// Raw fields are deliberately not typed until the query's Codex identity is verified.
/// Other endpoints may use these JSON names for unrelated data.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct ServiceTierDeclaration {
    service_tiers: Option<Value>,
    default_service_tier: Option<Value>,
    #[serde(skip)]
    authorized: bool,
}

#[derive(Deserialize)]
struct Tier {
    id: String,
    name: Option<String>,
}

impl ServiceTierDeclaration {
    pub fn authorize(&mut self, endpoint: &ProtocolEndpoint) {
        self.authorized = supports_endpoint(endpoint);
    }

    pub fn declared(&self) -> bool {
        self.authorized && (self.service_tiers.is_some() || self.default_service_tier.is_some())
    }

    pub fn apply(
        self,
        model: &mut ModelDefinition,
    ) -> std::result::Result<(), crate::discovery::ModelCatalogQueryError> {
        use crate::discovery::ModelCatalogQueryError::Protocol;
        if !self.authorized {
            model
                .extra
                .parameters
                .retain(|parameter| parameter.name != "service_tier");
            return Ok(());
        }
        if let Some(value) = self.service_tiers {
            let previous_default = model
                .extra
                .parameters
                .iter()
                .find(|p| p.name == "service_tier")
                .and_then(|p| p.default.clone());
            let tiers: Vec<Tier> = serde_json::from_value(value).map_err(|_| Protocol)?;
            let mut candidates = Vec::with_capacity(tiers.len());
            let mut names = BTreeMap::new();
            for tier in tiers {
                if tier.id.trim().is_empty() || candidates.contains(&tier.id) {
                    return Err(Protocol);
                }
                if let Some(name) = tier.name.filter(|name| !name.trim().is_empty()) {
                    names.insert(tier.id.clone(), name);
                }
                candidates.push(tier.id);
            }
            model
                .extra
                .parameters
                .retain(|parameter| parameter.name != "service_tier");
            if !candidates.is_empty() {
                let wire = candidates
                    .iter()
                    .map(|id| {
                        (
                            id.clone(),
                            ParameterWire {
                                set: vec![WireAssignment {
                                    path: "service_tier".into(),
                                    value: Value::String(id.clone()),
                                }],
                                remove: Vec::new(),
                            },
                        )
                    })
                    .collect();
                model.extra.parameters.push(ModelParameter {
                    name: "service_tier".into(),
                    label: None,
                    default: previous_default.filter(|value| candidates.contains(value)),
                    candidates,
                    candidate_display_names: names,
                    wire,
                });
            }
        }
        if let Some(value) = self.default_service_tier {
            let default: String = serde_json::from_value(value).map_err(|_| Protocol)?;
            let parameter = model
                .extra
                .parameters
                .iter_mut()
                .find(|p| p.name == "service_tier");
            let default = parameter
                .as_ref()
                .filter(|p| p.has_candidate(&default))
                .map(|_| default);
            if let Some(parameter) = parameter {
                parameter.default.clone_from(&default);
            }
            model
                .observation
                .get_or_insert_with(Default::default)
                .parameter_defaults
                .insert(
                    "service_tier".into(),
                    crate::model::ModelParameterDefaultObservation {
                        value: default,
                        order: 0,
                    },
                );
        }
        Ok(())
    }
}
