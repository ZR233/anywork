//! Language-service input contracts and workspace-bound Thread tools.
#[cfg(target_os = "linux")]
mod host;
mod thread;
#[cfg(target_os = "linux")]
pub use host::LocalLspHostBackend;
pub use pl_tool_lsp_capabilities::LspCapabilitiesInput;
pub use pl_tool_lsp_query::LspQueryInput;
pub use thread::{LspPathBinding, LspToolKind, ThreadLspTool};
