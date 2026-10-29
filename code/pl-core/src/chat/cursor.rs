//! 完成代际、无状态页请求、严格 keyset 边界与页结果。
//!
//! 页不是窗口：请求只表达「最新」或「某条更旧边界之前」，结果只表达「这一页有什么、下一条边界
//! 在哪、是否真的还有更旧内容」。没有 offset 分页、没有 against 方向、没有跨页拼接状态。

use crate::chat::{ChatError, ChatItem};

/// 每页默认条目数。
pub const DEFAULT_PAGE_ITEMS: usize = 32;
/// 单页最多接纳的条目数；显式请求超出该范围即被拒绝，不做静默放宽。
pub const MAX_PAGE_ITEMS: usize = 100;
/// 单页预览字节预算；预算提前截页仍返回真实的下一边界。
pub const PAGE_PREVIEW_BYTES: usize = 2 * 1024 * 1024;

/// 完成集合的一次运行代际：宿主创建 Session 时注入的不透明标识。
///
/// `timelineEpoch` 标识同一注册 Session 的这一次运行。宿主在**每次**构建 Session 时提供一个新的
/// 唯一代际（Runtime 使用其既有的业务 ID 能力生成），重启或重建必然换新 epoch，因此旧 epoch 的
/// 游标、订阅与补发位置按类型化错误拒绝，而不是被新集合静默重解释。它不同于
/// Session/incarnation、领域 revision、活动 generation/revision 和传输 deliverySequence。
///
/// 代际是不透明字符串：Core 不生成、不解释其内容，只要求非空并按原样比较；产品游标按
/// [`TimelineEpoch::as_str`] 编码，解码后原样还原即可继续参与比较。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TimelineEpoch(String);

impl TimelineEpoch {
    /// 由宿主提供的不透明代际构造；空串不是合法代际。
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] 当 `epoch` 为空。
    pub fn new(epoch: impl Into<String>) -> Result<Self, ChatError> {
        let epoch = epoch.into();
        if epoch.is_empty() {
            return Err(ChatError::InvalidArgument(
                "timeline epoch must not be empty".to_owned(),
            ));
        }
        Ok(Self(epoch))
    }

    /// The opaque generation text, exactly as the host provided it.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// 连续接纳位置；序号零表示该代尚未接纳任何完成项。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatCompletionCursor {
    pub epoch: TimelineEpoch,
    pub append_seq: u64,
}

impl ChatCompletionCursor {
    pub fn new(epoch: TimelineEpoch, append_seq: u64) -> Self {
        Self { epoch, append_seq }
    }
}

/// 严格 `(append_seq, item_id)` keyset 边界，绑定产生它的完成代际。
///
/// 比较键就是会话内固定的 `(完成序号, 身份)`，因此同一身份的位置不会因页游标而漂移；序号与身份
/// 一一对应，两个序号相同的记录由读取合并校验直接拒绝。边界可以指向尚未落盘的权威记录：游标只
/// 表达顺序事实，不要求该记录已经存在于 durable history，也不把数据库 applied-write 水位当作
/// 内容版本。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct ChatCursor {
    pub epoch: TimelineEpoch,
    pub append_seq: u64,
    pub item_id: String,
}

impl ChatCursor {
    /// 由完成代际、顺序与稳定身份构造边界。
    pub fn new(epoch: TimelineEpoch, append_seq: u64, item_id: impl Into<String>) -> Self {
        Self {
            epoch,
            append_seq,
            item_id: item_id.into(),
        }
    }

    /// 一条记录的自身边界。
    pub fn of(epoch: &TimelineEpoch, item: &ChatItem) -> Self {
        Self::new(epoch.clone(), item.append_seq, item.item_id.clone())
    }

    /// 校验该边界属于这次请求的完成代际。
    pub(crate) fn validate_epoch(&self, epoch: &TimelineEpoch) -> Result<(), ChatError> {
        if &self.epoch == epoch {
            return Ok(());
        }
        Err(ChatError::EpochMismatch {
            cursor: self.epoch.clone(),
            session: epoch.clone(),
        })
    }
}

/// 一页请求：只有 `latest`（`before` 为 `None`）或“某条边界之前”。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatPageRequest {
    pub before: Option<ChatCursor>,
    pub limit: Option<usize>,
}

impl ChatPageRequest {
    /// 最新一页（默认条目数）。
    pub fn latest() -> Self {
        Self::default()
    }

    /// 严格位于 `before` 之前的一页。
    pub fn before(before: ChatCursor) -> Self {
        Self {
            before: Some(before),
            limit: None,
        }
    }

    /// 指定本页最多返回的条目数。
    pub fn with_limit(mut self, limit: usize) -> Self {
        self.limit = Some(limit);
        self
    }

    /// 校验后的条目数：缺省 32，显式值必须在 `1..=100`。
    ///
    /// # Errors
    /// 显式 `limit` 为 0 或超过 [`MAX_PAGE_ITEMS`] 时返回 [`ChatError::InvalidArgument`]，不静默
    /// 截断成允许范围内的值。
    pub fn limit(&self) -> Result<usize, ChatError> {
        match self.limit {
            None => Ok(DEFAULT_PAGE_ITEMS),
            Some(limit) if (1..=MAX_PAGE_ITEMS).contains(&limit) => Ok(limit),
            Some(limit) => Err(ChatError::InvalidArgument(format!(
                "page limit {limit} is outside 1..={MAX_PAGE_ITEMS}"
            ))),
        }
    }
}

/// 一页升序条目、下一条更旧边界、是否真的还有更旧内容，以及产生它的完成代际。
///
/// `before` 只在 `has_older` 为真时给出，并取自本页实际第一条（最旧）条目，因此后续页严格接续、
/// 不重复也不跳过。`has_older` 由真实存在性证明（多出一条候选或存储侧存在性检查），短页本身不
/// 等于到头。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatPage {
    pub epoch: TimelineEpoch,
    pub items: Vec<ChatItem>,
    pub before: Option<ChatCursor>,
    pub has_older: bool,
}

/// 存储侧一页结果：只回答“读到哪些条目”与“该窗口之外是否还有更多行”。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatHistoryPage {
    pub items: Vec<ChatItem>,
    pub has_more: bool,
}
