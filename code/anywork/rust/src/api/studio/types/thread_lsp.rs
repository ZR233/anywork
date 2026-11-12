use serde::{Deserialize, Serialize};

use super::BridgeLspServerDto;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeThreadLspStateSnapshot {
    pub thread_id: String,
    pub revision: u64,
    pub binding_id: Option<String>,
    pub servers: Vec<BridgeLspServerDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadLspResetInput {
    pub thread_id: String,
    pub binding_id: String,
    pub server_id: String,
}

impl From<ThreadLspResetInput> for pl_protocol::studio::ThreadLspResetRequest {
    fn from(value: ThreadLspResetInput) -> Self {
        Self {
            thread_id: value.thread_id,
            binding_id: value.binding_id,
            server_id: value.server_id,
        }
    }
}

impl From<pl_studio_runtime::StudioThreadLspStateSnapshot> for BridgeThreadLspStateSnapshot {
    fn from(value: pl_studio_runtime::StudioThreadLspStateSnapshot) -> Self {
        Self {
            thread_id: value.thread_id,
            revision: value.revision,
            binding_id: value.binding_id,
            servers: value
                .servers
                .into_iter()
                .map(crate::api::studio::convert::runtime::bridge_lsp_server)
                .collect(),
        }
    }
}
