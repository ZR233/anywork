//! Validated built-in model inventories.
use thiserror::Error;

use super::ModelDefinition;

#[derive(Debug, Clone, PartialEq)]
pub struct BundledModelDefinition {
    pub suggested_model: String,
    /// Initial route recommendation, independent of the model's weakest default effort.
    pub suggested_effort: Option<String>,
    pub models: Vec<ModelDefinition>,
}

/// A binary/packaging defect, never a damaged user configuration.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ModelDefinitionError {
    #[error("bundled model definition contains invalid model declarations")]
    Declaration,
    #[error("bundled model definition has an invalid recommendation")]
    Recommendation,
    #[error("no bundled model definition for this catalog")]
    Unsupported,
}

impl From<ModelDefinitionError> for pl_protocol::PureError {
    fn from(error: ModelDefinitionError) -> Self {
        // Provider/internal failure must not enter Studio's PersistentData reset path.
        pl_protocol::ProviderFailure::new(
            pl_protocol::ProviderFailureKind::Unknown,
            error.to_string(),
            pl_protocol::RetryDisposition::Permanent,
        )
        .with_source(error)
        .into()
    }
}

impl BundledModelDefinition {
    /// Validate an inventory and its initial route recommendation.
    /// # Errors
    /// Returns an error when a declaration or the recommendation is invalid.
    pub fn new(
        models: Vec<ModelDefinition>,
        suggested_model: &str,
        suggested_effort: Option<&str>,
    ) -> Result<Self, ModelDefinitionError> {
        let definition = Self {
            models,
            suggested_model: suggested_model.to_owned(),
            suggested_effort: suggested_effort.map(str::to_owned),
        };
        validate_inventory(&definition.models)?;
        let suggested = definition
            .models
            .iter()
            .find(|m| m.base.slug == definition.suggested_model)
            .ok_or(ModelDefinitionError::Recommendation)?;
        let supported_efforts = suggested.supported_efforts();
        let valid_recommendation = match &definition.suggested_effort {
            Some(effort) => supported_efforts.contains(effort),
            None => supported_efforts.is_empty(),
        };
        if !valid_recommendation {
            return Err(ModelDefinitionError::Recommendation);
        }
        Ok(definition)
    }
}

pub fn validate_inventory(models: &[ModelDefinition]) -> Result<(), ModelDefinitionError> {
    let mut model_ids = std::collections::BTreeSet::new();
    for model in models {
        if model.base.slug.trim().is_empty() || !model_ids.insert(&model.base.slug) {
            return Err(ModelDefinitionError::Declaration);
        }
        model
            .validate()
            .map_err(|_| ModelDefinitionError::Declaration)?;
    }
    Ok(())
}
