//! Frozen pre-schema-18 display DTOs. Only named historical migrations decode these types.

use serde::{Deserialize, Serialize};

use pl_protocol::{
    ChatAtomContent, ChatAtomKind, ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome, PayloadData,
};

/// Bumped whenever the grouping rules change. A stored projection of another
/// version is rebuilt instead of being mixed with current items.
pub const TIMELINE_PROJECTION_VERSION: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TimelineItemKind {
    /// User/parent input or a formally accepted assistant text part.
    Text,
    /// One continuous stretch of foreground work (thinking, tools, reading, ...).
    WorkGroup,
    /// A clearly independent status or receipt (question result, plan decision,
    /// compaction receipt, stop/failure, final background result).
    Status,
}

impl TimelineItemKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Text => "text",
            Self::WorkGroup => "workGroup",
            Self::Status => "status",
        }
    }
}

/// Display-only process category used in a folded work-group summary. Never a
/// grouping rule: two members of different categories stay in one group.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TimelineCategory {
    Thinking,
    Read,
    Image,
    Command,
    Search,
    Edit,
    Wait,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineCategoryCount {
    pub category: TimelineCategory,
    pub count: u32,
}

/// Bounded, derivable group header data. Never copied member bodies or payloads.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineGroupSummary {
    /// Latest nonempty reasoning summary in this group's source order.
    /// Bounded by the activity summary limit; never the reasoning body.
    pub latest_thinking_summary: Option<String>,
    pub member_count: u32,
    /// Members whose reliable terminal fact is still missing.
    pub active_count: u32,
    pub failed_count: u32,
    pub cancelled_count: u32,
    /// Fixed display order; only categories with a positive count are present.
    pub categories: Vec<TimelineCategoryCount>,
    /// First member's reliable start and last member's reliable terminal time.
    /// Either remains unknown when the source fact does not prove it.
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
}

/// Typed member scope of one projection in one conversation database.
/// The original read owner validates this reference before opening a bounded
/// member window; clients never derive membership from an atom range.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineMembersRef {
    pub database_id: String,
    pub projection_version: u32,
    /// Opaque persisted incarnation of the derived projection. A successful
    /// rebuild changes it even when the algorithm version and item ID stay equal.
    pub projection_generation: String,
    pub item_id: String,
}

/// One top-level display item. Text and status items point at their original
/// content; a work group stores only identity, ordering and its bounded summary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineItem {
    /// Stable display identity derived from provable source facts, never a page
    /// index, member count, content hash or play-time counter.
    pub id: String,
    pub kind: TimelineItemKind,
    /// Actual source that owns the item. A group of adjacent independent
    /// background results is anchored by its first result; each member retains
    /// its own source identity.
    pub source: ChatSourceId,
    /// Domain kind for text/status items; `None` for a mixed work group.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub atom_kind: Option<ChatAtomKind>,
    pub delivery: ChatDeliveryKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text_channel: Option<pl_protocol::ThreadTextChannel>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    /// The original text/status atom's terminal outcome, when known. A mixed
    /// work group uses its result counts instead of an invented overall outcome.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub outcome: Option<ChatTerminalOutcome>,
    /// Only work groups carry a summary.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<TimelineGroupSummary>,
    /// Only work groups carry a typed member reference.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub members: Option<TimelineMembersRef>,
    /// Stable content references owned by the original atom (text body,
    /// reasoning summary, tool arguments/output and attachments).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub contents: Vec<ChatAtomContent>,
    /// Inline or deferred original payload for a text/status item.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payload: Option<PayloadData>,
    /// Original completion item that owns the payload/contents of a text/status
    /// item. A derived row stores only this reference, never a second body copy.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_item_id: Option<String>,
    /// `item_order` once the item entered history; `None` while still current.
    pub position: Option<u64>,
    /// No more active members are admitted from the original source. A closed
    /// foreground item may still await running members before entering history.
    /// An independent background-result tail can append completed results via
    /// `ChatPlacement::Update`; this flag does not freeze its derived summary.
    pub admission_closed: bool,
}

impl TimelineItem {
    pub fn is_work_group(&self) -> bool {
        self.kind == TimelineItemKind::WorkGroup
    }
}

use pl_protocol::{
    ChatAtom, ChatSourceState, CurrentActivityHead, CurrentCollectionRef, CurrentContentPreview,
    CurrentPlanHead, CurrentTurnHead, ThreadStatus,
};
/// 小 current 与完成切点一起发布，不包含完整 ThreadSnapshot/上下文或增长集合。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentProjection {
    pub source_effect_seq: u64,
    pub logical_status: ThreadStatus,
    /// 是否存在当前执行来源；持久化 running 不能单独证明这一事实。
    pub execution_present: bool,
    pub active: Option<CurrentActivityHead>,
    pub active_turn: Option<CurrentTurnHead>,
    /// Actual execution source states. These are not presentation boundaries.
    pub sources: Vec<ChatSourceState>,
    /// Ordered current fragments. A WorkGroup/Text/Status item not yet handed to
    /// Main history stays here with a typed, bounded member-query reference.
    #[serde(default)]
    pub items: Vec<TimelineItem>,
    /// Member facts of the current items, including unfinished ones. Clients
    /// index these only through the item's typed member scope.
    pub atoms: Vec<ChatAtom>,
    pub plan: Option<CurrentPlanHead>,
    pub interactions: Option<CurrentCollectionRef>,
    pub previews: Vec<CurrentContentPreview>,
    pub collections: Vec<CurrentCollectionRef>,
}

impl CurrentProjection {
    pub fn empty(source_effect_seq: u64, logical_status: ThreadStatus) -> Self {
        Self {
            source_effect_seq,
            logical_status,
            execution_present: false,
            active: None,
            active_turn: None,
            sources: Vec::new(),
            items: Vec::new(),
            atoms: Vec::new(),
            plan: None,
            interactions: None,
            previews: Vec::new(),
            collections: Vec::new(),
        }
    }
}

#[cfg(test)]
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub enum ChatEntry {
    Item(Box<TimelineItem>),
    Atom(Box<ChatAtom>),
    Source(ChatSourceState),
}

#[cfg(test)]
#[derive(Debug, Clone)]
pub enum ChatScope {
    Main,
    GroupMembers { reference: TimelineMembersRef },
}

#[derive(Debug)]
pub struct FrozenCurrentProjection {
    projection: CurrentProjection,
}
impl FrozenCurrentProjection {
    pub fn new(projection: CurrentProjection) -> std::sync::Arc<Self> {
        std::sync::Arc::new(Self { projection })
    }
    pub fn projection(&self) -> &CurrentProjection {
        &self.projection
    }
    pub fn json_bytes(&self) -> u64 {
        serde_json::to_vec(&self.projection).map_or(u64::MAX, |b| b.len() as u64)
    }
}
