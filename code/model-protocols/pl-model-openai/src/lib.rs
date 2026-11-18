//! openai model protocol.

pub mod openai_catalog;

pub mod images;

pub use pl_model_openai_wire::generic_catalog;

pub mod search;

pub mod codex_usage;

/// Embedded, validated deployment defaults for this protocol.
pub fn bundled_definition() -> Result<
    pl_model_types::model::BundledModelDefinition,
    pl_model_types::model::ModelDefinitionError,
> {
    pl_model_types::model::BundledModelDefinition::parse(
        include_str!("../assets/model.json"),
        "openai",
    )
}
