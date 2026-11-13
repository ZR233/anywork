//! Private, instance-scoped host domain transport. No MCP envelopes cross this boundary.
mod client;
mod platform;
mod server;
mod wire;

pub use client::IpcClient;
pub use server::IpcServer;
