//! openai-deepseek model protocol.

pub mod deepseek_catalog;

pub mod tools;
pub mod upload;

pub const UPLOAD: pl_model_types::files::UploadFile =
    |request| Box::pin(upload::upload_file(request));

/// Embedded, validated deployment defaults for this protocol.
pub fn bundled_definition() -> Result<
    pl_model_types::model::BundledModelDefinition,
    pl_model_types::model::ModelDefinitionError,
> {
    pl_model_types::model::BundledModelDefinition::parse(
        include_str!("../assets/model.json"),
        "deepseek",
    )
}
