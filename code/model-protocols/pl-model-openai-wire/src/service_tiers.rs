//! Online catalog service-tier declarations and exact request selection.
use std::collections::BTreeMap;

use crate::model::{ModelDefinition, ModelParameter, wire_set_one};
use pl_protocol::{PureError, Result};
use serde::Deserialize;

/// Whether a request on this route can select an explicit service tier.
pub fn has_selectable_tier(model: &ModelDefinition) -> bool {
    model
        .extra
        .parameters
        .iter()
        .find(|parameter| parameter.name == "service_tier")
        .is_some_and(|parameter| {
            parameter
                .candidates
                .iter()
                .any(|tier| validate(model, Some(tier)).is_ok())
        })
}

/// Validates an explicit choice without applying the catalog's default or first candidate.
///
/// # Errors
/// Returns a configuration error if the candidate or its exact wire assignment is invalid.
pub fn validate(model: &ModelDefinition, requested: Option<&str>) -> Result<()> {
    let Some(requested) = requested else {
        return Ok(());
    };
    if !model
        .extra
        .parameters
        .iter()
        .find(|parameter| parameter.name == "service_tier")
        .is_some_and(|parameter| {
            parameter.has_candidate(requested)
                && parameter.wire_for(requested) == Some(&wire_set_one("service_tier", requested))
        })
    {
        return Err(PureError::ConfigError(format!(
            "unsupported service_tier {requested:?} for the selected model route"
        )));
    }
    Ok(())
}

/// Service-tier fields produced by a catalog parser that recognizes the wire declaration.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct ServiceTierDeclaration {
    service_tiers: Option<Vec<Tier>>,
    #[serde(default, deserialize_with = "crate::discovery::nullable")]
    default_service_tier: Option<Option<String>>,
}

#[derive(Debug, Clone, Deserialize)]
struct Tier {
    id: String,
    name: Option<String>,
}

impl ServiceTierDeclaration {
    pub fn declared(&self) -> bool {
        self.service_tiers.is_some() || self.default_service_tier.is_some()
    }

    pub fn apply(
        self,
        model: &mut ModelDefinition,
    ) -> std::result::Result<(), crate::discovery::ModelCatalogQueryError> {
        use crate::discovery::ModelCatalogQueryError::Protocol;
        if let Some(tiers) = self.service_tiers {
            let previous_default = model
                .extra
                .parameters
                .iter()
                .find(|p| p.name == "service_tier")
                .and_then(|p| p.default.clone());
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
                    .map(|id| (id.clone(), wire_set_one("service_tier", id)))
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
        if let Some(default) = self.default_service_tier {
            let parameter = model
                .extra
                .parameters
                .iter_mut()
                .find(|p| p.name == "service_tier");
            let default = default
                .filter(|default| parameter.as_ref().is_some_and(|p| p.has_candidate(default)));
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
