//! One deterministic resolution of shared definitions and provider-owned routes.
use std::collections::BTreeMap;

use super::{AgentModelConfig, ProviderId, ProviderModelEntry, ProviderModelOrigin};
use crate::model::{
    ModelInfo, ModelMetadataField,
    observation::{SHARED_FIELDS, apply_field, apply_parameter_defaults},
};
use pl_protocol::Result;

impl AgentModelConfig {
    /// Rebuild all effective routes from the current local declarations and observations.
    /// No IO, timestamps or provider credentials are consulted by the merge.
    /// # Errors
    /// Invalid local declarations or provider transport profiles.
    pub fn reconcile_model_catalog(&mut self) -> Result<()> {
        let mut shared = BTreeMap::<String, (u8, ModelInfo)>::new();
        let mut routes = BTreeMap::<ProviderId, Vec<ProviderModelEntry>>::new();
        let mut observations = Vec::new();
        let mut default_observations = Vec::new();
        for (id, provider) in &mut self.providers {
            provider.clear_resolved_catalog();
            let mut local = provider.clone();
            local.clear_model_catalog_overlay();
            for entry in local.effective_catalog(None)? {
                let rank = if entry.origin == ProviderModelOrigin::Manual {
                    2
                } else {
                    1
                };
                let slot = shared
                    .entry(entry.model.model_id.clone())
                    .or_insert_with(|| (rank, entry.model.clone()));
                if rank > slot.0 {
                    *slot = (rank, entry.model.clone());
                }
            }
            let entries = provider.effective_catalog(None)?;
            for entry in &entries {
                shared
                    .entry(entry.model.model_id.clone())
                    .or_insert_with(|| (0, entry.model.clone()));
            }
            for model in provider.model_observations() {
                if let Some(observation) = &model.observation {
                    for (parameter, default) in &observation.parameter_defaults {
                        default_observations.push((
                            default.order,
                            id.clone(),
                            model.model_id.clone(),
                            parameter.clone(),
                            default.value.clone(),
                        ));
                    }
                    for (&field, &order) in &observation.fields {
                        observations.push((order, id.clone(), field, model.clone()));
                    }
                }
            }
            routes.insert(id.clone(), entries);
        }
        // Later acquisition wins. Provider IDs break ties without depending on hash/arrival order.
        observations.sort_by(|a, b| (&a.0, &a.1, &a.2).cmp(&(&b.0, &b.1, &b.2)));
        let mut winners = BTreeMap::new();
        for (order, provider, field, model) in observations {
            if let Some((_, target)) = shared.get_mut(&model.model_id) {
                apply_field(target, &model, field);
                if let Some(value) = model
                    .observation
                    .as_ref()
                    .and_then(|o| o.budgets.get(&field))
                {
                    match field {
                        ModelMetadataField::ContextWindow => target.context_window = *value,
                        ModelMetadataField::MaxContextWindow => target.max_context_window = *value,
                        _ => {}
                    }
                }
                winners.insert((model.model_id.clone(), field), (order, provider));
            }
        }
        for (model_id, (_, model)) in &mut shared {
            if let (Some(current), Some(maximum)) = (model.context_window, model.max_context_window)
                && current > maximum
            {
                if winners.get(&(model_id.clone(), ModelMetadataField::ContextWindow))
                    > winners.get(&(model_id.clone(), ModelMetadataField::MaxContextWindow))
                {
                    model.max_context_window = Some(current);
                } else {
                    model.context_window = Some(maximum);
                }
            }
            if !model.capabilities.reasoning
                && winners.get(&(model_id.clone(), ModelMetadataField::Reasoning))
                    >= winners.get(&(model_id.clone(), ModelMetadataField::Parameters))
            {
                model
                    .parameters
                    .retain(|parameter| parameter.name != "effort");
            }
        }
        default_observations
            .sort_by(|a, b| (&a.0, &a.1, &a.2, &a.3).cmp(&(&b.0, &b.1, &b.2, &b.3)));
        for (_, _, model_id, name, value) in default_observations {
            if let Some((_, model)) = shared.get_mut(&model_id)
                && let Some(parameter) = model
                    .parameters
                    .iter_mut()
                    .find(|parameter| parameter.name == name)
            {
                parameter.default = value.filter(|value| parameter.candidates.contains(value));
            }
        }
        for (id, entries) in &mut routes {
            for entry in entries.iter_mut() {
                let definition = &shared[&entry.model.model_id].1;
                for &field in SHARED_FIELDS {
                    apply_field(&mut entry.model, definition, field);
                }
                apply_parameter_defaults(&mut entry.model, definition);
                let fields = winners
                    .iter()
                    .filter(|((model_id, _), _)| model_id == &entry.model.model_id)
                    .map(|((_, field), (order, _))| (*field, *order))
                    .collect::<BTreeMap<_, _>>();
                if !fields.is_empty() {
                    let observation = entry.model.observation.get_or_insert_with(Default::default);
                    observation.fields = fields;
                    observation.budgets.clear();
                }
                // Withdraw unused encoders, but never borrow a codec from another route.
                entry.model.binding.request.media.retain(|profile| {
                    definition
                        .capabilities
                        .supports_input_modality(profile.modality)
                });
            }
            if let Some(provider) = self.providers.get_mut(id) {
                provider.set_resolved_catalog(entries.clone());
            }
        }
        Ok(())
    }
}
