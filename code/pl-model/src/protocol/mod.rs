//! Account protocol selection and model catalog discovery.
pub mod discovery;
pub use pl_model_wire::protocol::*;

/// Built-in provider implementations used by the account catalog.
pub mod providers {
    pub use pl_model_gemini::endpoint as gemini;
    pub use pl_model_openai::endpoint as openai;
    pub use pl_model_openai_deepseek::endpoint as deepseek;
    pub use pl_model_openai_glm::endpoint as glm;
    pub use pl_model_openai_mimo::endpoint as mimo;
    pub use pl_model_openai_xai::endpoint as xai;
}

mod registry;
pub use registry::{ProtocolRegistry, builtin_protocols};
