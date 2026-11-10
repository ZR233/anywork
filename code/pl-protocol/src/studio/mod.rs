//! Studio transport-neutral command, response, event, and error protocol.

mod accounts;
mod acp;
mod acp_business;
pub use acp_business::*;
mod acp_detection;
mod acp_install;
mod attachment;
mod bots;
mod chatgpt_auth;
mod continuation;
mod error;
mod operation;
mod persistence;
mod query;
mod receipt;
mod request;
mod settings;
mod settings_update;
mod thread_preparation;
mod workspace;

pub use crate::mcp::{
    CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpCatalogEntry, McpCatalogSnapshot,
    McpConfigStatusKind, McpDocumentCommitReceipt, McpDocumentContent, McpDocumentDiagnostic,
    McpDocumentRef, McpEffectiveSource, McpExecutionLocation, McpScope, McpServerKey,
    ReconnectThreadMcpRequest, ReloadMcpCatalogRequest, ThreadMcpLifecycleKind,
    ThreadMcpServerState, ThreadMcpStateSnapshot, UpdateMcpDocumentRequest,
};
pub use accounts::*;
pub use acp::*;
pub use acp_detection::*;
pub use acp_install::*;
pub use attachment::*;
pub use bots::*;
pub use chatgpt_auth::*;
pub use continuation::*;
pub use error::*;
pub use operation::*;
pub use persistence::*;
pub use query::*;
pub use receipt::*;
pub use request::*;
pub use settings::*;
pub use settings_update::*;
pub use thread_preparation::*;
pub use workspace::*;
