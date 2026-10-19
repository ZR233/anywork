//! Typed discovery dialects for candidate sets and independently observed defaults.
use std::collections::BTreeMap;

use serde::Deserialize;

use super::{ModelCatalogQueryError, effort_parameter, nullable};
use crate::{
    model::{ModelInfo, ModelParameter, ModelParameterDefaultObservation, ParameterWire},
    provider::ProviderAdapterKind,
};

#[derive(Default, Deserialize)]
pub(super) struct ReasoningDeclaration {
    pub effort: Option<Effort>,
    supported_reasoning_levels: Option<Vec<ReasoningLevel>>,
    #[serde(default, deserialize_with = "nullable")]
    default_reasoning_level: Option<Option<String>>,
    parameters: Option<Vec<OnlineParameter>>,
    #[serde(rename = "reasoningEfforts")]
    candidates: Option<Vec<ReasoningCandidate>>,
    #[serde(rename = "reasoningEffort", default, deserialize_with = "nullable")]
    default: Option<Option<String>>,
    #[serde(rename = "supportsReasoningEffort")]
    pub supports_effort: Option<bool>,
}

#[derive(Deserialize)]
pub(super) struct Effort {
    pub supported_levels: Vec<String>,
    #[serde(default, deserialize_with = "nullable")]
    pub default_level: Option<Option<String>>,
}

#[derive(Deserialize)]
struct ReasoningLevel {
    effort: String,
}

#[derive(Deserialize)]
struct ReasoningCandidate {
    value: String,
    #[serde(default)]
    default: bool,
}

#[derive(Deserialize)]
struct OnlineParameter {
    name: String,
    label: Option<String>,
    candidates: Vec<String>,
    #[serde(default, deserialize_with = "nullable")]
    default: Option<Option<String>>,
    #[serde(default)]
    wire: BTreeMap<String, ParameterWire>,
}

impl ReasoningDeclaration {
    pub fn declares_candidates(&self) -> bool {
        self.parameters.is_some()
            || self.effort.is_some()
            || self.supported_reasoning_levels.is_some()
            || self.candidates.is_some()
    }

    pub fn declares_parameters(&self) -> bool {
        self.declares_candidates() || self.supports_effort == Some(false)
    }

    pub fn apply(
        self,
        model: &mut ModelInfo,
        adapter: ProviderAdapterKind,
        explicit_reasoning: Option<bool>,
    ) -> Result<(), ModelCatalogQueryError> {
        let candidates_declared = self.declares_candidates();
        let mut levels = None;
        let mut defaults = BTreeMap::new();
        if let Some(effort) = self.effort {
            merge_levels(&mut levels, effort.supported_levels)?;
            merge_default(&mut defaults, "effort", effort.default_level)?;
        }
        if let Some(values) = self.supported_reasoning_levels {
            merge_levels(
                &mut levels,
                values.into_iter().map(|value| value.effort).collect(),
            )?;
        }
        if let Some(values) = self.candidates {
            let marked = values
                .iter()
                .filter(|value| value.default)
                .collect::<Vec<_>>();
            if marked.len() > 1 {
                return Err(ModelCatalogQueryError::Protocol);
            }
            merge_default(
                &mut defaults,
                "effort",
                marked.first().map(|value| Some(value.value.clone())),
            )?;
            merge_levels(
                &mut levels,
                values.into_iter().map(|value| value.value).collect(),
            )?;
        }
        merge_default(&mut defaults, "effort", self.default)?;
        merge_default(&mut defaults, "effort", self.default_reasoning_level)?;
        let previous_default = model
            .effort_parameter()
            .and_then(|parameter| parameter.default.clone());
        if let Some(parameters) = self.parameters {
            // A complete parameter declaration and a separate candidate dialect are ambiguous.
            if levels.is_some() {
                return Err(ModelCatalogQueryError::Protocol);
            }
            let effort_path = if super::uses_responses_effort(adapter) {
                "reasoning.effort"
            } else {
                "reasoning_effort"
            };
            if parameters.iter().any(|parameter| {
                parameter.name != "effort"
                    || parameter.wire.iter().any(|(candidate, wire)| {
                        !wire.remove.is_empty()
                            || wire.set.len() != 1
                            || wire.set[0].path != effort_path
                            || wire.set[0].value != serde_json::Value::String(candidate.clone())
                    })
            }) {
                return Err(ModelCatalogQueryError::Protocol);
            }
            model.parameters = parameters
                .into_iter()
                .map(|parameter| {
                    merge_default(&mut defaults, &parameter.name, parameter.default)?;
                    Ok(ModelParameter {
                        name: parameter.name,
                        label: parameter.label,
                        candidates: parameter.candidates,
                        default: None,
                        wire: parameter.wire,
                    })
                })
                .collect::<Result<_, ModelCatalogQueryError>>()?;
        }
        if let Some(values) = levels {
            model
                .parameters
                .retain(|parameter| parameter.name != "effort");
            if !values.is_empty() {
                model.parameters.push(effort_parameter(values, adapter));
            }
        }
        if self.supports_effort == Some(false) || explicit_reasoning == Some(false) {
            if candidates_declared && !model.supported_efforts().is_empty()
                || defaults.get("effort").is_some_and(Option::is_some)
            {
                return Err(ModelCatalogQueryError::Protocol);
            }
            model
                .parameters
                .retain(|parameter| parameter.name != "effort");
        }
        if candidates_declared
            && explicit_reasoning.is_none()
            && self.supports_effort != Some(false)
        {
            model.capabilities.reasoning = !model.supported_efforts().is_empty();
        }
        if let Some(parameter) = model
            .parameters
            .iter_mut()
            .find(|parameter| parameter.name == "effort")
        {
            parameter.default =
                previous_default.filter(|value| parameter.candidates.contains(value));
        }
        for (name, value) in defaults {
            let parameter = model
                .parameters
                .iter_mut()
                .find(|parameter| parameter.name == name);
            if candidates_declared
                && value.as_ref().is_some_and(|value| {
                    parameter
                        .as_ref()
                        .is_none_or(|parameter| !parameter.has_candidate(value))
                })
            {
                return Err(ModelCatalogQueryError::Protocol);
            }
            if let Some(parameter) = parameter {
                parameter.default = value.clone().filter(|value| parameter.has_candidate(value));
            }
            model
                .observation
                .get_or_insert_with(Default::default)
                .parameter_defaults
                .insert(name, ModelParameterDefaultObservation { value, order: 0 });
        }
        Ok(())
    }
}

fn merge_levels(
    target: &mut Option<Vec<String>>,
    levels: Vec<String>,
) -> Result<(), ModelCatalogQueryError> {
    if levels.iter().any(|value| value.trim().is_empty())
        || levels
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            != levels.len()
        || target.as_ref().is_some_and(|previous| previous != &levels)
    {
        return Err(ModelCatalogQueryError::Protocol);
    }
    *target = Some(levels);
    Ok(())
}

fn merge_default(
    target: &mut BTreeMap<String, Option<String>>,
    name: &str,
    value: Option<Option<String>>,
) -> Result<(), ModelCatalogQueryError> {
    if let Some(value) = value {
        if value.as_ref().is_some_and(|value| value.trim().is_empty())
            || target.get(name).is_some_and(|previous| previous != &value)
        {
            return Err(ModelCatalogQueryError::Protocol);
        }
        target.insert(name.to_owned(), value);
    }
    Ok(())
}
