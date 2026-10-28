//! Timeline 内容源的 wire 契约：无状态页、有界尾部订阅与按身份详情。
//!
//! 这里没有窗口、焦点、方向翻页或“展开整条”的操作回执。三个入口分别对应 core 的三条能力：
//! 一页升序预览、一条有界尾部连接（基线 + 连续补丁／显式重同步）、一段按字段与版本绑定的详情块。
//!
//! [`TimelineItem`] 使用独立描述与带身份的字段表达预览值，不重建持久化条目。工具
//! output artifacts、原始记录正文和问答正文都是内容字段，不允许藏进静态元数据绕过预算。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

mod descriptor;
pub use descriptor::*;

/// 每页默认条目数。
pub const TIMELINE_PAGE_ITEMS: usize = 32;
/// 单页最多接纳的条目数；显式请求超出即被拒绝，不做静默放宽。
pub const TIMELINE_PAGE_MAX_ITEMS: usize = 100;
/// 页游标与详情 continuation 的版本号；语义变化时递增并拒绝旧 token。
pub const TIMELINE_CURSOR_VERSION: u32 = 1;
/// 页游标 token 前缀；item identity 不会以它开头，因此解码是确定性的。
const PAGE_CURSOR_PREFIX: &str = "tlp1.";
/// 详情 continuation token 前缀。
const DETAIL_CURSOR_PREFIX: &str = "tld1.";

/// 条目的执行终态事实，与保存水位 `saved` 严格独立。
///
/// `Terminal` 表示执行终态，允许后续可靠内容修订及 Append；它与内容 revision、订阅版本、
/// `saved`（writer 已确认该 revision 落盘）互不推导。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum TimelineLifecycle {
    Streaming,
    Terminal,
}

/// 一帧是否需要立即应用，还是普通文本可以合帧。
///
/// 由 core 依据权威内容事实给出（新身份首字、执行终态准入、保存确认、字段删除、权威替换都是
/// `Immediate`），宿主不得自行分类或节流生产者。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum TimelinePriority {
    Immediate,
    Coalesced,
}

/// 一个内容字段的变化落在哪个域上。
///
/// 变体身份与宿主字段域一一对应：字段类别决定客户端把 `text` 应用到条目结构的哪里，而不是让消费者
/// 重新解析整条 JSON。映射只由字段身份决定，不从内容字符串推断。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    rename_all = "camelCase",
    tag = "kind",
    rename_all_fields = "camelCase"
)]
pub enum ThreadContentField {
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
    /// 普通问答投影的一段正文：`question_index` 是原问题顺序，`part` 定位该问题内的具体正文。
    ToolUserInput {
        question_index: u32,
        part: ThreadUserInputFieldPart,
    },
    /// 原始记录的一段正文：`payload_index` 是它在原记录里的顺序。
    RawPayload {
        payload_index: u32,
    },
}

/// 普通问答投影里一段可展示正文的位置。
///
/// 问答的标题、问题、选项说明与答案都是用户可见正文，必须共享同一份内容预算：任何一段都不留在
/// 静态元数据里绕过有界预览。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    rename_all = "camelCase",
    tag = "kind",
    rename_all_fields = "camelCase"
)]
pub enum ThreadUserInputFieldPart {
    /// 问题标题。
    Header,
    /// 完整问题正文。
    Question,
    /// 该问题的一个已接受答案值。
    Answer { answer_index: u32 },
    /// 该问题一个选项的标签。
    OptionLabel { option_index: u32 },
    /// 该问题一个选项的说明。
    OptionDescription { option_index: u32 },
}

impl ThreadContentField {
    /// 稳定的字段身份标签，用于绑定不透明详情 continuation。
    ///
    /// 标签只表达身份（不会随内容变化），因此 continuation 可以被逐项校验，而不必猜测“附近某个
    /// 字段”。
    pub fn token_label(&self) -> String {
        match self {
            Self::Text => "text".to_owned(),
            Self::ThinkingSummary { chunk_index } => format!("thinkingSummary:{chunk_index}"),
            Self::ThinkingContent { chunk_index } => format!("thinkingContent:{chunk_index}"),
            Self::ToolArguments => "toolArguments".to_owned(),
            Self::ToolResult => "toolResult".to_owned(),
            Self::ToolOutputArtifacts => "toolOutputArtifacts".to_owned(),
            Self::ToolUserInput {
                question_index,
                part,
            } => format!(
                "toolUserInput:{question_index}:{}",
                user_input_part_label(*part)
            ),
            Self::RawPayload { payload_index } => format!("rawPayload:{payload_index}"),
        }
    }
}

/// 问答正文位置的稳定标签。
fn user_input_part_label(part: ThreadUserInputFieldPart) -> String {
    match part {
        ThreadUserInputFieldPart::Header => "header".to_owned(),
        ThreadUserInputFieldPart::Question => "question".to_owned(),
        ThreadUserInputFieldPart::Answer { answer_index } => format!("answer:{answer_index}"),
        ThreadUserInputFieldPart::OptionLabel { option_index } => {
            format!("optionLabel:{option_index}")
        }
        ThreadUserInputFieldPart::OptionDescription { option_index } => {
            format!("optionDescription:{option_index}")
        }
    }
}

/// 一个内容字段的详情引用：完整正文按 `(item, field, revision)` 读取。
///
/// `total_bytes` 是该字段完整正文的 UTF-8 字节数，`preview_bytes` 是本次预览实际携带的字节数；
/// 两者相等表示预览即完整正文。长度按原始 UTF-8 字节计，不按客户端字符单位计。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TimelineDetailRef {
    pub field: ThreadContentField,
    pub revision: u64,
    pub total_bytes: u64,
    pub preview_bytes: u64,
}

/// 一条时间线条目的预览值。
///
/// 身份、描述与正文分离；完整性、省略量与详情引用从当前字段及 revision 派生，不驻留冗余副本。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelineItem {
    pub header: TimelineItemHeader,
    pub revision: u64,
    pub descriptor: TimelineDescriptor,
    /// 只读来源语义，不是持久化字段或 GUI 分组结果。
    pub source: TimelineItemSource,
    pub saved: bool,
    pub lifecycle: TimelineLifecycle,
    pub fields: Vec<TimelineFieldPreview>,
}

/// 实际预览长度直接由 `text` 的 UTF-8 字节长度取得。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelineFieldPreview {
    pub field: ThreadContentField,
    pub text: String,
    pub total_bytes: u64,
}

impl TimelineFieldPreview {
    pub fn preview_bytes(&self) -> u64 {
        self.text.len() as u64
    }
}

impl TimelineItem {
    /// 按当前修订派生详情引用，不缓存另一份字段长度或版本。
    pub fn details(&self) -> impl Iterator<Item = TimelineDetailRef> + '_ {
        self.fields.iter().map(|field| TimelineDetailRef {
            field: field.field,
            revision: self.revision,
            total_bytes: field.total_bytes,
            preview_bytes: field.preview_bytes(),
        })
    }

    pub fn omitted_bytes(&self) -> u64 {
        self.fields.iter().fold(0, |total: u64, field| {
            total.saturating_add(field.total_bytes.saturating_sub(field.preview_bytes()))
        })
    }
}

/// 原始条目的来源；展示端不解析内部身份或本地化提示文案。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum TimelineItemSource {
    Content,
    ModelRecovery {
        attempt_id: String,
        notice: TimelineRecoveryNotice,
    },
}

/// 同一模型 attempt 逐条保存的恢复提示类别。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TimelineRecoveryNotice {
    Retry,
    Result,
}

/// 一页请求：只有“最新”或“某条边界之前”。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelinePageQuery {
    /// 上一页返回的不透明边界 token；缺省表示最新一页。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<String>,
    /// 本页最多条目数，缺省 32，合法范围 1..=100。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

impl TimelinePageQuery {
    /// 请求的条目数；越界值原样交给共享领域能力拒绝，不在 wire 层静默夹取。
    pub fn limit(&self) -> Option<usize> {
        self.limit.map(|limit| limit as usize)
    }
}

/// 一页升序预览条目、下一更旧边界与是否真的还有更旧内容。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelinePage {
    pub thread_id: String,
    pub items: Vec<TimelineItem>,
    /// 请求更旧一页时要原样回传的边界 token；只有 `has_older` 为真时给出。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<String>,
    pub has_older: bool,
}

/// 一条尾部连接的基线：最新小页与它自己的内容版本。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelineTailBaseline {
    /// 本连接的订阅身份；重连必须换新身份，同连接重同步保持不变。
    pub subscription_id: String,
    /// 订阅自己的内容版本；与条目 revision、持久化水位都无关。
    pub version: u64,
    pub items: Vec<TimelineItem>,
    /// 直接继续翻更旧一页的边界 token；只有 `hasOlder` 为真时给出。
    ///
    /// 它与 `items` 来自同一次一致读取，因此客户端用首帧就能建立最新小页并继续 older，不需要另发一次
    /// latest 查询再拼两份基线。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<String>,
    /// 是否真的还有更旧内容（来自同次一致读取的真实存在性证明，不凭条数猜 EOF）。
    pub has_older: bool,
}

/// 一个内容字段的变化。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum TimelineFieldChange {
    /// 正文不变，但所属 item 的 revision 仍要提交（版本帧不是空补丁）。
    Unchanged,
    /// 该字段仍以前缀方式扩展本地已交付末尾；`text` 是新增字节。
    Append { text: String },
    /// 本地基线已失效（权威替换、预览升级）；`text` 是整段权威正文。
    Replace { text: String },
    /// 该字段已从条目移除，消费者丢弃本地副本。
    Remove,
}

/// 同一 item 的一个字段变化。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TimelineFieldUpdate {
    pub field: ThreadContentField,
    pub change: TimelineFieldChange,
    /// 该字段完整正文的 UTF-8 字节数；预览被截断时仍是原文长度。
    pub total_bytes: u64,
    /// 本次交付的预览字节数。
    pub preview_bytes: u64,
}

/// 一次交付的变更，按身份表达，不带任何可见下标。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum TimelineChange {
    /// 订阅尚未交付过的一条权威条目。
    ///
    /// 条目本身按顺序内联太大，因此装箱：wire 形状不变，只是避免每个变更枚举都按最大变体取值。
    Add { item: Box<TimelineItem> },
    /// 同一身份的全部内容与状态字段，在**一次** `expectedRevision`/`revision` 提交里原子应用。
    ///
    /// 应用条件：本地该 `itemId` 的 content revision 等于 `expected_revision`；否则基线不连续，应按
    /// 宿主策略重同步。全部字段应用完成后**一次**提交 `revision`、保存水位 `saved` 与执行终态
    /// `lifecycle`。同 revision 的保存确认是合法更新，不要求伪造新的正文 revision。
    UpdateItem {
        item_id: String,
        expected_revision: u64,
        revision: u64,
        saved: bool,
        lifecycle: TimelineLifecycle,
        /// 元数据改变时携带当前头部与描述，不传输持久化正文外壳。
        #[serde(default, skip_serializing_if = "Option::is_none")]
        header: Option<TimelineItemHeader>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        descriptor: Option<Box<TimelineDescriptor>>,
        fields: Vec<TimelineFieldUpdate>,
    },
    /// 真实删除：该身份不再存在。预览缓存退出不是删除。
    Remove { item_id: String },
}

/// 订阅无法继续用连续补丁表达时的原因。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum TimelineResyncReason {
    /// 消费者落后超出了可证连续的窗口。
    Lagging,
    /// 一次变化触及了无法与本地副本对账的身份。
    Unavailable,
}

/// 一条尾部连接交付的一帧。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum TimelineTailUpdate {
    /// 连续补丁：`from` 必须等于本地已交付版本，`to` 必须前进。
    Patch {
        subscription_id: String,
        from: u64,
        to: u64,
        changes: Vec<TimelineChange>,
        priority: TimelinePriority,
    },
    /// 无法连续表达：给出原因与新的最新小页基线，同连接沿用本订阅身份。
    Resync {
        subscription_id: String,
        reason: TimelineResyncReason,
        baseline: TimelineTailBaseline,
    },
}

/// 详情读取请求：item 由路径给出，其余绑定在同一份 typed body 里。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineDetailQuery {
    pub field: ThreadContentField,
    /// 读取绑定的内容版本；与当前版本不一致时报过期，不混版本拼接。
    pub revision: u64,
    /// 上一块返回的不透明 continuation token。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<String>,
    /// 本块最多字节数，缺省 64 KiB，合法范围 4..=256 KiB。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_bytes: Option<u32>,
}

/// 一段完整正文块。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TimelineDetailChunk {
    pub thread_id: String,
    pub item_id: String,
    pub field: ThreadContentField,
    pub revision: u64,
    pub text: String,
    /// 该字段完整正文的 UTF-8 字节数。
    pub total_bytes: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<String>,
}

/// 页边界 token 的载荷：绑定 Thread、版本与严格 `(ordinal, identity)` 顺序。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PageCursorPayload {
    version: u32,
    thread_id: String,
    order: u64,
    item_id: String,
}

/// 版本化、Thread 绑定的不透明页边界 token。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelinePageCursor {
    pub thread_id: String,
    pub order: u64,
    pub item_id: String,
}

impl TimelinePageCursor {
    /// 编码为可跨 wire 传输的 opaque token。
    ///
    /// # Panics
    /// 仅在内部 JSON 编码失败时 panic；字段均为可序列化的原始类型。
    pub fn encode(&self) -> String {
        let payload = serde_json::to_string(&PageCursorPayload {
            version: TIMELINE_CURSOR_VERSION,
            thread_id: self.thread_id.clone(),
            order: self.order,
            item_id: self.item_id.clone(),
        })
        .expect("timeline page cursor is serializable");
        format!("{PAGE_CURSOR_PREFIX}{payload}")
    }

    /// 解析 opaque token；非游标输入返回 `None`，由调用方明确拒绝而不是回落到猜测位置。
    pub fn decode(token: &str) -> Option<Self> {
        let payload = token.strip_prefix(PAGE_CURSOR_PREFIX)?;
        let cursor: PageCursorPayload = serde_json::from_str(payload).ok()?;
        (cursor.version == TIMELINE_CURSOR_VERSION).then_some(Self {
            thread_id: cursor.thread_id,
            order: cursor.order,
            item_id: cursor.item_id,
        })
    }
}

/// 详情 continuation 的载荷：绑定 Thread、item、字段身份、revision、版本与字节偏移。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DetailCursorPayload {
    version: u32,
    thread_id: String,
    item_id: String,
    field: String,
    revision: u64,
    offset: u64,
}

/// 版本化、上下文绑定的不透明详情 continuation。
///
/// 它同时绑定 Thread、item、字段身份、revision 与字节偏移，读取时逐项校验：从 A 字段取得的 token
/// 不能被带到 B 字段、另一条条目、另一版本或另一 Thread，也不会被当成“附近某个位置”的猜测。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimelineDetailCursor {
    pub thread_id: String,
    pub item_id: String,
    /// 字段身份的稳定标签（见 [`ThreadContentField::token_label`]）。
    pub field: String,
    pub revision: u64,
    pub offset: u64,
}

impl TimelineDetailCursor {
    /// 编码为可跨 wire 传输的 opaque token。
    ///
    /// # Panics
    /// 仅在内部 JSON 编码失败时 panic；字段均为可序列化的原始类型。
    pub fn encode(&self) -> String {
        let payload = serde_json::to_string(&DetailCursorPayload {
            version: TIMELINE_CURSOR_VERSION,
            thread_id: self.thread_id.clone(),
            item_id: self.item_id.clone(),
            field: self.field.clone(),
            revision: self.revision,
            offset: self.offset,
        })
        .expect("timeline detail cursor is serializable");
        format!("{DETAIL_CURSOR_PREFIX}{payload}")
    }

    /// 解析 opaque token；非法或版本不符返回 `None`，由调用方明确拒绝。
    pub fn decode(token: &str) -> Option<Self> {
        let payload = token.strip_prefix(DETAIL_CURSOR_PREFIX)?;
        let cursor: DetailCursorPayload = serde_json::from_str(payload).ok()?;
        (cursor.version == TIMELINE_CURSOR_VERSION).then_some(Self {
            thread_id: cursor.thread_id,
            item_id: cursor.item_id,
            field: cursor.field,
            revision: cursor.revision,
            offset: cursor.offset,
        })
    }
}
