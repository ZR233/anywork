//! Model contracts and built-in inventory assembled from the selected protocol crates.
pub use pl_model_wire::model::*;

pub fn bundled_model_definition(
    catalog: &str,
) -> Result<BundledModelDefinition, ModelDefinitionError> {
    match catalog {
        "openai" => pl_model_openai::bundled_definition(),
        "deepseek" => pl_model_openai_deepseek::bundled_definition(),
        "xai" => pl_model_openai_xai::bundled_definition(),
        "gemini" | "vertex-ai" => pl_model_gemini::bundled_definition(),
        _ => Err(ModelDefinitionError::Unsupported),
    }
}

pub fn default_models() -> Result<Vec<ModelInfo>, ModelDefinitionError> {
    let mut models = pl_model_openai_deepseek::bundled_definition()?.models;
    models.extend(pl_model_openai::bundled_definition()?.models);
    models.extend(pl_model_openai_xai::bundled_definition()?.models);
    models.extend(pl_model_openai_mimo::models::models());
    models.extend(pl_model_openai_glm::models::models());
    models.extend(pl_model_gemini::bundled_definition()?.models);
    Ok(models)
}

pub use crate::selection::{bundled_selection_guide, bundled_selection_guides};
