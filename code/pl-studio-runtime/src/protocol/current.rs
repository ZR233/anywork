//! Small deferred-reference types shared with `ThreadSnapshot` and `ThreadActivity`,
//! plus frozen structs referenced by legacy history migration codecs.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::plan_tool::AgentSessionPlanPhase;
use crate::{ThreadActivityKind, ThreadActivityToolState, TurnPhase};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentContentRef {
    pub owner_id: String,
    pub domain: String,
    pub entity_id: String,
    pub content_key: String,
    pub generation: String,
}

/// An explicitly deferred State field.
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
