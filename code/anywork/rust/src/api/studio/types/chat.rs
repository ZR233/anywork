//! Timeline 内容源的 FRB DTO。
//!
//! 这里是同一份共享领域结果的第二套**外观**（FRB 需要自己的可生成类型），不是第二套语义：字段身份、
//! revision、保存水位与执行终态与 HTTP wire 一一对应。内容字段身份只由身份决定，客户端不解析正文来
//! 猜它属于哪里。

use super::BridgeThreadItem;

/// 条目的执行终态事实，与保存水位 `saved` 严格独立。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTimelineLifecycle {
    Streaming,
    Terminal,
}

/// 一帧是否需要立即应用，还是普通文本已经合帧。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTimelinePriority {
    Immediate,
    Coalesced,
}

/// 订阅无法继续用连续补丁表达时的原因。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTimelineResyncReason {
    Lagging,
    Unavailable,
}

/// 一个内容字段的变化落在哪个域上。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeContentField {
    Text,
    ThinkingSummary {
        chunk_index: u32,
    },
    ThinkingContent {
        chunk_index: u32,
    },
    ToolArguments,
    ToolResult,
    /// 工具的一次执行附加的开放产物（只在 canonical/详情边界编码）。
    ToolOutputArtifacts,
    /// 普通问答正文：问题位置 + 该问题内的一段可展示正文。
    ToolUserInput {
        question_index: u32,
        part: BridgeThreadUserInputFieldPart,
    },
    /// 原始记录的一段正文：它在原记录里的顺序。
    RawPayload {
        payload_index: u32,
    },
}

/// 普通问答投影里一段可展示正文的位置；问答正文共享同一条内容预算。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadUserInputFieldPart {
    Header,
    Question,
    Answer { answer_index: u32 },
    OptionLabel { option_index: u32 },
    OptionDescription { option_index: u32 },
}

/// 一个内容字段的详情引用：完整正文按 `(item, field, revision)` 读取。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineDetailRef {
    pub field: BridgeContentField,
    pub revision: u64,
    /// 该字段完整正文的 UTF-8 字节数。
    pub total_bytes: u64,
    /// 本次预览实际携带的字节数。
    pub preview_bytes: u64,
}

/// 一条时间线条目的预览值。
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTimelineItem {
    pub item: BridgeThreadItem,
    pub saved: bool,
    pub lifecycle: BridgeTimelineLifecycle,
    /// 预览省略的正文总字节数；零表示所有字段都是完整正文。
    pub omitted_bytes: u64,
    pub details: Vec<BridgeTimelineDetailRef>,
}

/// 一页升序预览条目、下一更旧边界与是否真的还有更旧内容。
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTimelinePage {
    pub items: Vec<BridgeTimelineItem>,
    /// 请求更旧一页时原样回传的不透明边界 token。
    pub before: Option<String>,
    pub has_older: bool,
}

/// 一条尾部连接的基线。
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTimelineBaseline {
    /// 本连接的订阅身份；重连换新，同连接重同步保持不变。
    pub subscription_id: String,
    /// 订阅自己的内容版本；与条目 revision、持久化水位无关。
    pub version: u64,
    pub items: Vec<BridgeTimelineItem>,
    /// 直接继续翻更旧一页的边界 token；只有 `has_older` 为真时给出。与 `items` 来自同一次一致读取。
    pub before: Option<String>,
    /// 是否真的还有更旧内容（真实存在性证明，不凭条数猜 EOF）。
    pub has_older: bool,
}

/// 一个内容字段的变化。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineFieldChange {
    /// 正文不变，但所属 item 的 revision 仍要提交（版本帧不是空补丁）。
    Unchanged,
    /// 该字段仍以前缀方式扩展本地已交付末尾；`text` 是新增字节。
    Append { text: String },
    /// 本地基线已失效；`text` 是整段权威正文。
    Replace { text: String },
    /// 该字段已从条目移除。
    Remove,
}

/// 同一 item 的一个字段变化。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineFieldUpdate {
    pub field: BridgeContentField,
    pub change: BridgeTimelineFieldChange,
    /// 该字段完整正文的 UTF-8 字节数；预览被截断时仍是原文长度。
    pub total_bytes: u64,
    /// 本次交付的预览字节数。
    pub preview_bytes: u64,
}

/// 一次交付的变更，按身份表达，不带可见下标。
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeTimelineChange {
    /// 订阅尚未交付过的一条权威条目（装箱以避免整个枚举按最大变体取值）。
    Add { item: Box<BridgeTimelineItem> },
    /// 同一身份的全部内容与状态字段，在**一次** expectedRevision/revision 提交里原子应用。
    ///
    /// 应用条件：本地该 `itemId` 的 content revision 等于 `expectedRevision`；否则按宿主策略重同步。
    UpdateItem {
        item_id: String,
        expected_revision: u64,
        revision: u64,
        /// 条目级省略量：全部字段完整长度与本次预览字节数之差的合计。
        omitted_bytes: u64,
        saved: bool,
        lifecycle: BridgeTimelineLifecycle,
        item_shell: Option<Box<BridgeThreadItem>>,
        fields: Vec<BridgeTimelineFieldUpdate>,
    },
    /// 真实删除：该身份不再存在。预览缓存退出不是删除。
    Remove { item_id: String },
}

/// 一条尾部连接交付的一帧。
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeTimelineUpdate {
    /// 连续补丁：`from` 必须等于本地已交付版本。
    Patch {
        subscription_id: String,
        from: u64,
        to: u64,
        changes: Vec<BridgeTimelineChange>,
        priority: BridgeTimelinePriority,
    },
    /// 无法连续表达：给出原因与新的最新小页基线，同连接沿用本订阅身份。
    Resync {
        subscription_id: String,
        reason: BridgeTimelineResyncReason,
        baseline: BridgeTimelineBaseline,
    },
}

/// 详情读取请求：item 由调用参数给出，其余绑定在同一份 typed 请求里。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineDetailQuery {
    pub field: BridgeContentField,
    pub revision: u64,
    pub continuation: Option<String>,
    pub max_bytes: Option<u32>,
}

/// 一段完整正文块。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineDetailChunk {
    pub item_id: String,
    pub field: BridgeContentField,
    pub revision: u64,
    pub text: String,
    /// 该字段完整正文的 UTF-8 字节数。
    pub total_bytes: u64,
    pub continuation: Option<String>,
}
