use pl_protocol::products::read::workspace as protocol;
use pl_studio_runtime::workspace::StudioAgentDirectoryRead;

use super::super::identity::{
    BridgeProductCollectionRef, BridgeProductEntityRef, BridgeProductReadOrigin,
    BridgeProductReadScopeIdentity,
};
use super::super::references::BridgeAgentDirectoryReadRef;
use super::super::source::BridgeSourceStateErrorRead;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::thread_directory::BridgeFrozenModelSelectionRead;
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{
    BridgeDelegationMode, BridgeDelegationPreference, BridgeError, BridgeFeedCloseReport,
    BridgeTurnBudgetLimit,
};

impl ModelsRead for StudioAgentDirectoryRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        Self::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        Self::ensure_open(self)
    }
    fn request_close(&self) {
        Self::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        Self::close(self)
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAgentDirectoryReadConnection {
    read: ModelsReadHandle<StudioAgentDirectoryRead>,
}

pub async fn open_agent_directory_read(
    reference: BridgeAgentDirectoryReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeAgentDirectoryReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeAgentDirectoryReadConnection {
        read: open_read(move |runtime| runtime.open_agent_directory_read(reference, origin))
            .await?,
    })
}
impl BridgeAgentDirectoryReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeAgentDirectoryReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioAgentDirectoryRead::header)?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAgentDirectoryEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeAgentDirectoryEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_agent(
        &self,
        agent_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.lookup_agent(agent_id))?
            .await?
            .map(Into::into))
    }
    pub async fn agents(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAgentDirectoryEntryReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.agents(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryReadHeader {
    pub agents: BridgeTypedListRef,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAgentWorkspaceDisposition {
    Preserve,
    Cleanup,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAgentFaultClassification {
    RecoverableRuntime,
    RecoverableProtocol,
    AggregateCorruption,
    LegacyUnknown,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentBudgetPauseRead {
    pub turn_id: BridgeReadText,
    pub limit: BridgeTurnBudgetLimit,
    pub paused_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeAgentStateRead {
    Idle {
        budget_pause: Option<BridgeAgentBudgetPauseRead>,
    },
    Queued {
        turn_id: BridgeReadText,
    },
    Running {
        turn_id: BridgeReadText,
    },
    WaitingTool {
        turn_id: BridgeReadText,
    },
    WaitingInteraction {
        turn_id: BridgeReadText,
        interaction_id: BridgeReadText,
    },
    Cancelling {
        turn_id: BridgeReadText,
    },
    Closing {
        workspace_disposition: BridgeAgentWorkspaceDisposition,
        turn_id: Option<BridgeReadText>,
        error: Option<BridgeSourceStateErrorRead>,
    },
    Closed,
    Faulted {
        error: BridgeSourceStateErrorRead,
        turn_id: Option<BridgeReadText>,
        classification: BridgeAgentFaultClassification,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryEntryRead {
    pub id: BridgeReadText,
    pub thread_id: BridgeReadText,
    pub root_thread_id: BridgeReadText,
    pub path: BridgeReadText,
    pub parent_path: Option<BridgeReadText>,
    pub role: BridgeReadText,
    pub task: BridgeReadText,
    pub summary: Option<BridgeReadText>,
    pub delegation_mode: BridgeDelegationMode,
    pub delegation_preference: BridgeDelegationPreference,
    pub frozen_model: Option<BridgeFrozenModelSelectionRead>,
    pub depth: u32,
    pub state: BridgeAgentStateRead,
    pub execution: Option<crate::api::studio::types::BridgeAgentExecution>,
    pub can_stop: bool,
    pub awaiting_scheduling: bool,
    pub updated_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeAgentDirectoryEntryRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryEntryReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAgentDirectoryEntryRead>,
    pub next_offset: Option<u64>,
}

impl From<protocol::AgentDirectoryReadHeader> for BridgeAgentDirectoryReadHeader {
    fn from(value: protocol::AgentDirectoryReadHeader) -> Self {
        Self {
            agents: value.agents.into(),
        }
    }
}
impl From<pl_protocol::AgentWorkspaceDisposition> for BridgeAgentWorkspaceDisposition {
    fn from(value: pl_protocol::AgentWorkspaceDisposition) -> Self {
        match value {
            pl_protocol::AgentWorkspaceDisposition::Preserve => Self::Preserve,
            pl_protocol::AgentWorkspaceDisposition::Cleanup => Self::Cleanup,
        }
    }
}
impl From<pl_protocol::AgentFaultClassification> for BridgeAgentFaultClassification {
    fn from(value: pl_protocol::AgentFaultClassification) -> Self {
        match value {
            pl_protocol::AgentFaultClassification::RecoverableRuntime => Self::RecoverableRuntime,
            pl_protocol::AgentFaultClassification::RecoverableProtocol => Self::RecoverableProtocol,
            pl_protocol::AgentFaultClassification::AggregateCorruption => Self::AggregateCorruption,
            pl_protocol::AgentFaultClassification::LegacyUnknown => Self::LegacyUnknown,
        }
    }
}
impl From<protocol::AgentBudgetPauseRead> for BridgeAgentBudgetPauseRead {
    fn from(value: protocol::AgentBudgetPauseRead) -> Self {
        Self {
            turn_id: value.turn_id.into(),
            limit: value.limit.into(),
            paused_at: value.paused_at,
        }
    }
}
impl From<protocol::AgentStateRead> for BridgeAgentStateRead {
    fn from(value: protocol::AgentStateRead) -> Self {
        match value {
            protocol::AgentStateRead::Idle { budget_pause } => Self::Idle {
                budget_pause: budget_pause.map(Into::into),
            },
            protocol::AgentStateRead::Queued { turn_id } => Self::Queued {
                turn_id: turn_id.into(),
            },
            protocol::AgentStateRead::Running { turn_id } => Self::Running {
                turn_id: turn_id.into(),
            },
            protocol::AgentStateRead::WaitingTool { turn_id } => Self::WaitingTool {
                turn_id: turn_id.into(),
            },
            protocol::AgentStateRead::WaitingInteraction {
                turn_id,
                interaction_id,
            } => Self::WaitingInteraction {
                turn_id: turn_id.into(),
                interaction_id: interaction_id.into(),
            },
            protocol::AgentStateRead::Cancelling { turn_id } => Self::Cancelling {
                turn_id: turn_id.into(),
            },
            protocol::AgentStateRead::Closing {
                workspace_disposition,
                turn_id,
                error,
            } => Self::Closing {
                workspace_disposition: workspace_disposition.into(),
                turn_id: turn_id.map(Into::into),
                error: error.map(Into::into),
            },
            protocol::AgentStateRead::Closed => Self::Closed,
            protocol::AgentStateRead::Faulted {
                error,
                turn_id,
                classification,
            } => Self::Faulted {
                error: error.into(),
                turn_id: turn_id.map(Into::into),
                classification: classification.into(),
            },
        }
    }
}
impl From<protocol::AgentDirectoryEntryRead> for BridgeAgentDirectoryEntryRead {
    fn from(value: protocol::AgentDirectoryEntryRead) -> Self {
        Self {
            id: value.id.into(),
            thread_id: value.thread_id.into(),
            root_thread_id: value.root_thread_id.into(),
            path: value.path.into(),
            parent_path: value.parent_path.map(Into::into),
            role: value.role.into(),
            task: value.task.into(),
            summary: value.summary.map(Into::into),
            delegation_mode: value.delegation_mode.into(),
            delegation_preference: value.delegation_preference.into(),
            frozen_model: value.frozen_model.map(Into::into),
            depth: value.depth,
            state: value.state.into(),
            execution: value.execution.map(Into::into),
            can_stop: value.can_stop,
            awaiting_scheduling: value.awaiting_scheduling,
            updated_at: value.updated_at,
        }
    }
}
impl From<protocol::AgentDirectoryEntityRead> for BridgeAgentDirectoryEntityRead {
    fn from(value: protocol::AgentDirectoryEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}
impl From<protocol::AgentDirectoryEntryPage> for BridgeAgentDirectoryEntryPage {
    fn from(value: protocol::AgentDirectoryEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
impl From<protocol::AgentDirectoryEntryReadPage> for BridgeAgentDirectoryEntryReadPage {
    fn from(value: protocol::AgentDirectoryEntryReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
