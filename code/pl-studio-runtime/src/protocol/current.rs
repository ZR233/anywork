//! Small current observations. These references belong to a live owner, never a history database.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::plan_tool::AgentSessionPlanPhase;

use crate::{
    ChatSourceState, ReadDemand, ThreadActivityKind, ThreadActivityToolState,
    ThreadNotificationEnvelope, ThreadSnapshot, ThreadStatus, TurnPhase,
};

pub const CURRENT_PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentRevision {
    pub owner_id: String,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentContentRef {
    pub owner_id: String,
    pub domain: String,
    pub entity_id: String,
    pub content_key: String,
    pub generation: String,
}

/// An explicitly deferred State field. The inline placeholder is not a complete value while
/// this head is present. Read the exact JSON value through CurrentReader::read_body on demand.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum CurrentStateField {
    Body {
        field: String,
        reference: CurrentContentRef,
        byte_length: u64,
    },
    Collection {
        field: String,
        reference: CurrentCollectionRef,
        count: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum CurrentPayloadData {
    Inline {
        bytes: Vec<u8>,
    },
    Deferred {
        reference: CurrentContentRef,
        byte_length: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentAtomContent {
    pub role: crate::ChatContentRole,
    pub reference: CurrentContentRef,
}

/// A current entity cannot certify that a canonical completion exists in history.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentAtom {
    pub id: String,
    pub source: crate::ChatSourceId,
    pub source_state: Option<crate::ChatSourceState>,
    pub source_order: Option<u64>,
    pub kind: crate::ChatAtomKind,
    pub delivery: crate::ChatDeliveryKind,
    pub lifecycle: crate::ChatAtomLifecycle,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub tool: Option<crate::ChatToolIdentity>,
    pub wait: Option<crate::ThreadWaitPresentation>,
    pub text_channel: Option<crate::ThreadTextChannel>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    pub content_present: Option<bool>,
    pub contents: Vec<CurrentAtomContent>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentView {
    pub revision: CurrentRevision,
    #[schema(value_type = Object)]
    pub state: Box<ThreadSnapshot>,
    pub projection: crate::CurrentProjection,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum CurrentFrame {
    Reset {
        view: Box<CurrentView>,
    },
    Notification {
        revision: CurrentRevision,
        #[schema(value_type = Object)]
        notification: Box<ThreadNotificationEnvelope>,
    },
    Projection {
        revision: CurrentRevision,
        projection: Box<crate::CurrentProjection>,
    },
}

impl CurrentFrame {
    pub fn validate_demand(&self, demand: ReadDemand) -> Result<(), crate::StudioError> {
        let bytes = serde_json::to_vec(self).map_err(|error| {
            crate::StudioError::new(crate::StudioErrorCode::Internal, error.to_string(), false)
        })?;
        demand.validate(bytes.len())?;
        Ok(())
    }
}

/// 当前 owner 的小型观察，不包含完整上下文、历史水位或增长集合。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentProjection {
    pub logical_status: ThreadStatus,
    /// 是否存在当前执行来源；持久化 running 不能单独证明这一事实。
    pub execution_present: bool,
    pub active: Option<CurrentActivityHead>,
    pub active_turn: Option<CurrentTurnHead>,
    /// Actual execution source states. These are not presentation boundaries.
    pub sources: Vec<ChatSourceState>,
    /// Actual activity atoms; not completed history or a work-group index.
    pub atoms: Vec<crate::CurrentAtom>,
    pub plan: Option<CurrentPlanHead>,
    pub interactions: Option<CurrentCollectionRef>,
    pub previews: Vec<CurrentContentPreview>,
    pub collections: Vec<CurrentCollectionRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_recovery: Option<CurrentModelRecovery>,
}

/// Pure-RAM live recovery status while an active model call is reconnecting/retrying.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentModelRecovery {
    pub attempt: u32,
    pub max_attempts: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// 与 ThreadActivity 的完整活动工具集合分离；增长成员只由 collections 按需交付。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentActivityHead {
    pub id: String,
    pub kind: ThreadActivityKind,
    pub summary: String,
    pub thinking_summary: Option<String>,
    pub thinking_seconds: Option<u64>,
    pub tool_count: u32,
    pub background_tool_count: u32,
    pub latest_tool: Option<CurrentToolHead>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentToolHead {
    pub call_id: String,
    pub name: String,
    pub state: ThreadActivityToolState,
}

impl CurrentProjection {
    pub fn empty(logical_status: ThreadStatus) -> Self {
        Self {
            logical_status,
            execution_present: false,
            active: None,
            active_turn: None,
            sources: Vec::new(),
            atoms: Vec::new(),
            plan: None,
            interactions: None,
            previews: Vec::new(),
            collections: Vec::new(),
            model_recovery: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentTurnHead {
    pub id: String,
    pub phase: TurnPhase,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentPlanHead {
    pub revision: u64,
    pub phase: AgentSessionPlanPhase,
    pub document: Option<crate::CurrentContentRef>,
}

/// Read-only resource heads from the same accepted Plan/interaction state.
/// These are not a second mutable business model or a persistent history row.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadBusinessRefs {
    pub plan: Option<CurrentPlanHead>,
    pub interactions: Option<CurrentCollectionRef>,
}

impl ThreadBusinessRefs {
    /// Only for a genuinely new state with no established business resources.
    pub fn empty() -> Self {
        Self {
            plan: None,
            interactions: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentCollectionRef {
    pub owner_id: String,
    pub collection: String,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum CurrentContentRole {
    Reasoning,
    Response,
    ToolArguments,
    ToolOutput,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentContentPreview {
    pub id: String,
    pub role: CurrentContentRole,
    /// Original canonical text channel; display role alone never grants outbound eligibility.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text_channel: Option<crate::ThreadTextChannel>,
    pub text: String,
    pub reference: crate::CurrentContentRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentCollectionEntry {
    pub id: String,
    pub position: i64,
    pub payload: crate::CurrentPayloadData,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentCollectionPage {
    pub revision: u64,
    pub entries: Vec<CurrentCollectionEntry>,
    pub continuation: Option<String>,
}
