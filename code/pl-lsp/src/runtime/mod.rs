//! LSP registry 所有的状态、错误、能力与生命周期编排。

mod capabilities;
mod capability;
mod error;
mod formatting;
mod lease;
mod membership;
mod query;
mod registry;
mod request;
mod reset;
mod routing;
mod server;
mod snapshot;
mod state;

pub use capability::*;
pub use error::*;
pub use lease::LspWorkspaceLease;
pub use membership::{MAX_LSP_CONFIGURATION_BYTES, MAX_LSP_CONFIGURATION_FILES};
pub use registry::LspRuntimeRegistry;
pub use state::*;

use registry::{LspRuntimeServerState, LspWorkspaceState, workspace_key};
pub(crate) use server::ResolvedLspServer;
