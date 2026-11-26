//! Host MCP protocol adapters. The product runtime remains the sole business owner.
pub mod projection;
mod service;
mod types;

pub mod ipc;

pub use projection::{JsonInput, ProjectedInput, ProjectionError, ToolProjection};
pub use service::HostMcpService;
pub use types::{
    HostCatalog, HostContent, HostError, HostInvocation, HostResult, HostTool, HostTools,
};

pub const STDIO_ARG: &str = "--stdio";
pub const IPC_ENDPOINT_ENV: &str = "ANYWORK_HOST_IPC_ENDPOINT";
pub const IPC_CAPABILITY_ENV: &str = "ANYWORK_HOST_IPC_CAPABILITY";
pub const MAX_MESSAGE_BYTES: usize = 4 * 1024 * 1024;
