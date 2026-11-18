//! openai-xai model protocol.

pub mod xai_catalog;

/// Embedded, validated deployment defaults for this protocol.
pub fn bundled_definition() -> Result<
    pl_model_types::model::BundledModelDefinition,
    pl_model_types::model::ModelDefinitionError,
> {
    pl_model_types::model::BundledModelDefinition::parse(
        include_str!("../assets/model.json"),
        "xai",
    )
}
