//! One deterministic resolution inside each account: local declarations plus that account's own
//! observations.
//!
//! Online observations, explicit local overrides, names, budgets, capabilities, parameters and
//! prices are resolved inside the owning account only. An account never borrows a field from
//! another account that happens to declare the same `model_id`.
use std::collections::BTreeMap;

use super::{AccountConfig, AccountModelEntry, AgentModelConfig};
use crate::model::{
    ModelMetadataField,
    observation::{SHARED_FIELDS, apply_field, apply_parameter_defaults},
};
use pl_protocol::Result;

impl AgentModelConfig {
    /// Rebuild every account's effective catalog from its own declarations and observations.
    ///
    /// No IO, timestamps or credentials are consulted by the merge, and no value crosses an
    /// account boundary. Ordinary field precedence inside one account is: explicit online
    /// declaration, then that account's explicit local model, then the bundled definition it
    /// binds. Display names are the exception: an existing manual model name wins over online
    /// names; without one, a nonblank online name wins over the bundled name and model ID.
    ///
    /// # Errors
    /// Invalid local declarations or account transport profiles.
    pub fn reconcile_model_catalog(&mut self) -> Result<()> {
        for account in self.accounts.values_mut() {
            reconcile_account(account)?;
        }
        Ok(())
    }
}

fn reconcile_account(account: &mut AccountConfig) -> Result<()> {
    account.clear_resolved_catalog();
    let mut local = account.clone();
    local.clear_model_catalog_overlay();
    // The account's own declaration base: bundled members overlaid by its explicit models.
    let local_entries = local.effective_catalog(None)?;
    let mut merged = local_entries
        .into_iter()
        .map(|entry| (entry.model.base.slug.clone(), entry.model))
        .collect::<BTreeMap<_, _>>();
    let entries = account.catalog_with_defaults(crate::protocol::builtin_protocols())?;

    // Observations carry their own acquisition order; ordering is meaningful only inside this
    // account's query identity.
    let mut observations = Vec::new();
    let mut default_observations = Vec::new();
    for model in account.model_observations() {
        let Some(observation) = &model.observation else {
            continue;
        };
        if let Some(target) = merged.get_mut(&model.base.slug) {
            target.base.fields.extend(model.base.fields.clone());
            if model.base.model_messages != Default::default() {
                target.base.model_messages = model.base.model_messages.clone();
            }
            if model.base.truncation_policy != Default::default() {
                target.base.truncation_policy = model.base.truncation_policy.clone();
            }
        }
        for (parameter, default) in &observation.parameter_defaults {
            default_observations.push((
                default.order,
                model.base.slug.clone(),
                parameter.clone(),
                default.value.clone(),
            ));
        }
        for (&field, &order) in &observation.fields {
            observations.push((order, model.base.slug.clone(), field, model.clone()));
        }
    }
    observations.sort_by(|left, right| (&left.0, &left.1).cmp(&(&right.0, &right.1)));

    let mut winners = BTreeMap::new();
    for (order, model_id, field, observed) in observations {
        let Some(target) = merged.get_mut(&model_id) else {
            continue;
        };
        apply_field(target, &observed, field);
        if let Some(value) = observed
            .observation
            .as_ref()
            .and_then(|observation| observation.budgets.get(&field))
        {
            match field {
                ModelMetadataField::ContextWindow => target.base.context_window = *value,
                ModelMetadataField::MaxContextWindow => target.base.max_context_window = *value,
                _ => {}
            }
        }
        winners.insert((model_id, field), order);
    }

    for (model_id, model) in &mut merged {
        if let (Some(current), Some(maximum)) =
            (model.base.context_window, model.base.max_context_window)
            && current > maximum
        {
            if winners.get(&(model_id.clone(), ModelMetadataField::ContextWindow))
                > winners.get(&(model_id.clone(), ModelMetadataField::MaxContextWindow))
            {
                model.base.max_context_window = Some(current);
            } else {
                model.base.context_window = Some(maximum);
            }
        }
        if !model.extra.capabilities.reasoning
            && winners.get(&(model_id.clone(), ModelMetadataField::Reasoning))
                >= winners.get(&(model_id.clone(), ModelMetadataField::Parameters))
        {
            model.base.supported_reasoning_levels = None;
            model.base.default_reasoning_level = None;
            model.extra.effort_wire.clear();
        }
    }

    default_observations
        .sort_by(|left, right| (&left.0, &left.1, &left.2).cmp(&(&right.0, &right.1, &right.2)));
    for (_, model_id, name, value) in default_observations {
        let Some(model) = merged.get_mut(&model_id) else {
            continue;
        };
        if name == "effort" {
            model.base.default_reasoning_level =
                value.filter(|v| model.supported_efforts().contains(v));
            continue;
        }
        if let Some(parameter) = model
            .extra
            .parameters
            .iter_mut()
            .find(|parameter| parameter.name == name)
        {
            parameter.default = value.filter(|value| parameter.candidates.contains(value));
        }
    }

    let mut resolved = Vec::with_capacity(entries.len());
    for entry in entries {
        let mut entry = entry;
        let Some(definition) = merged.get(&entry.model.base.slug) else {
            resolved.push(entry);
            continue;
        };
        entry.model.base.fields = definition.base.fields.clone();
        entry.model.base.model_messages = definition.base.model_messages.clone();
        entry.model.base.truncation_policy = definition.base.truncation_policy.clone();
        for &field in SHARED_FIELDS {
            apply_field(&mut entry.model, definition, field);
        }
        // Inherited capabilities follow this account's current declaration, even when the
        // inventory was cached before a new media encoder was added. Keep explicit online
        // input declarations authoritative and never borrow codecs across wire APIs/accounts.
        if !winners.contains_key(&(entry.model.base.slug.clone(), ModelMetadataField::Input))
            && entry.model.extra.binding.transport.protocol
                == definition.extra.binding.transport.protocol
        {
            for profile in &definition.extra.binding.request.media {
                if entry
                    .model
                    .extra
                    .binding
                    .request
                    .media_profile(profile.modality)
                    .is_none()
                {
                    entry
                        .model
                        .extra
                        .binding
                        .request
                        .media
                        .push(profile.clone());
                }
            }
        }
        apply_parameter_defaults(&mut entry.model, definition);
        let model_id = entry.model.base.slug.clone();
        let fields = winners
            .iter()
            .filter(|((observed_model, _), _)| observed_model == &model_id)
            .map(|((_, field), order)| (*field, *order))
            .collect::<BTreeMap<_, _>>();
        if !fields.is_empty() {
            let observation = entry.model.observation.get_or_insert_with(Default::default);
            observation.fields = fields;
            observation.budgets.clear();
        }
        // Withdraw unused encoders, but never borrow a codec from another account.
        entry.model.extra.binding.request.media.retain(|profile| {
            definition
                .extra
                .capabilities
                .supports_input_modality(profile.modality)
        });
        if let Some(manual) = account
            .model_overrides()
            .iter()
            .find(|manual| manual.base.slug == entry.model.base.slug)
        {
            manual.apply(&mut entry.model)?;
        }
        resolved.push(entry);
    }
    let mut resolved: Vec<AccountModelEntry> = resolved;
    account.resolve_entries_context(&mut resolved)?;
    account.set_resolved_catalog(resolved);
    Ok(())
}
