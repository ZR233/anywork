pub use pl_model_types::completion::event::{
    ModelBlockContent, ModelBlockField, ModelBlockKind, ProviderBlockIdentity,
    ToolInputDeltaPayload, ToolInputPayloadKind, WebSearchAction,
};

/// The OpenAI-family stream retains typed replay deltas until they are folded.
pub type ModelStreamEvent =
    pl_model_types::completion::event::ModelStreamEvent<super::replay::ReplayUpdate>;
