//! HTTP 与 FRB 共用的 Timeline 内容映射：唯一一处 core → 产品预览／字段变化转换。
//!
//! [`TimelineContentReader`] 捕获**同一个**共享 `Session` 与 Thread 身份，页、详情与尾部连接都从它
//! 出发：一次打开之后不再按 thread id 重查运行时实例，因此旧的句柄不会读到另一个实例，也不会与
//! 自己的尾部观察分叉。HTTP 每条请求与 FRB 每个句柄共用这一份映射实现。
//!
//! 这里不缓存第二份正文，也不重建客户端基线。

mod field;
pub(crate) mod preview;

use anyhow::Result;
use pl_core::chat::{
    ChatDetailRequest, ChatPageRequest, ChatTail, ChatTailUpdate, ChatUpdatePriority, FieldChange,
    Session, TailChange,
};
use pl_protocol::{
    TimelineChange, TimelineDetailChunk, TimelineDetailQuery, TimelineFieldChange,
    TimelineFieldUpdate, TimelineLifecycle, TimelinePage, TimelinePageQuery, TimelinePriority,
    TimelineResyncReason, TimelineTailBaseline, TimelineTailUpdate,
};

use super::StudioRuntime;
use super::chat_item::item_shell;
use field::{
    core_field, detail_cursor, encode_detail_cursor, encode_page_cursor, page_cursor, wire_field,
};
use preview::timeline_item;

/// 一个 Thread 的内容句柄：捕获同一共享 `Session` 与 Thread 身份。
///
/// 它只持内容事实的引用（不是执行 owner pin），因此读取不会激活 Thread、也不阻止其空闲退役；关闭
/// 句柄即释放这些引用，而 Thread、Turn 与历史 writer 继续运行。
#[derive(Clone)]
pub struct TimelineContentReader {
    thread_id: String,
    session: Session,
}

impl TimelineContentReader {
    /// 本句柄所属的 Thread 身份。
    pub fn thread_id(&self) -> &str {
        &self.thread_id
    }

    /// 读一页最新或更旧的 keyset 页。
    ///
    /// # Errors
    /// 未知／跨 Thread 的游标与非法条目数返回 `InvalidArgument`，其余为宿主的类型化存储与预览失败。
    pub async fn page(&self, query: &TimelinePageQuery) -> Result<TimelinePage> {
        let before = match query.before.as_deref() {
            None => None,
            Some(token) => Some(page_cursor(&self.thread_id, token)?),
        };
        let page = self
            .session
            .page(ChatPageRequest {
                before,
                limit: query.limit(),
            })
            .await?;
        let mut items = Vec::with_capacity(page.items.len());
        for item in &page.items {
            items.push(timeline_item(item)?);
        }
        Ok(TimelinePage {
            thread_id: self.thread_id.clone(),
            items,
            before: page
                .before
                .as_ref()
                .map(|cursor| encode_page_cursor(&self.thread_id, cursor)),
            has_older: page.has_older,
        })
    }

    /// 读一段完整正文块。
    ///
    /// # Errors
    /// 跨上下文的 continuation、非法块大小、过期 revision、未知条目／字段与存储失败。
    pub async fn read_detail(
        &self,
        item_id: &str,
        query: &TimelineDetailQuery,
    ) -> Result<TimelineDetailChunk> {
        let mut request = ChatDetailRequest::new(item_id, core_field(query.field), query.revision);
        if let Some(token) = query.continuation.as_deref() {
            request =
                request.with_continuation(detail_cursor(&self.thread_id, item_id, query, token)?);
        }
        if let Some(max_bytes) = query.max_bytes {
            request = request.with_max_bytes(max_bytes as usize);
        }
        let chunk = self.session.read_detail(request).await?;
        Ok(TimelineDetailChunk {
            thread_id: self.thread_id.clone(),
            item_id: chunk.item_id,
            field: query.field,
            revision: chunk.revision,
            text: chunk.text,
            total_bytes: chunk.total_bytes,
            continuation: chunk.continuation.map(|cursor| {
                encode_detail_cursor(&self.thread_id, item_id, query, cursor.offset())
            }),
        })
    }

    /// 建立一条有界尾部连接。
    ///
    /// # Errors
    /// 共享基线的存储与预览读取失败。
    pub async fn open_tail(&self) -> Result<TimelineTailStream> {
        let tail = self.session.subscribe_tail().await?;
        Ok(TimelineTailStream {
            thread_id: self.thread_id.clone(),
            // 复用已有的 id 能力（时间前缀 + 进程内序号），因此重启后也不会重复旧身份，且不额外
            // 引入随机/编码依赖。
            subscription_id: crate::studio::ids::new_id("timeline-tail"),
            tail,
        })
    }
}

/// 一条 `GET /timeline/events` 连接或一个 FRB `BridgeTimeline` 自有的尾部观察。
pub struct TimelineTailStream {
    thread_id: String,
    subscription_id: String,
    tail: ChatTail,
}

impl TimelineTailStream {
    /// 本连接的订阅身份；重同步沿用，重连必须换新。
    pub fn subscription_id(&self) -> &str {
        &self.subscription_id
    }

    /// 移交建立观察时捕获的最新小页基线（含真实更旧边界），只移交一次。
    ///
    /// 首帧的所有权交给调用方，连接本身不再保留第二份；重复取用得到明确错误。
    ///
    /// # Errors
    /// 首帧已被取用，或条目的内容字段身份无法映射成产品字段——都明确失败，不猜一个标签。
    pub fn initial(&mut self) -> Result<TimelineTailBaseline> {
        let baseline = self.tail.initial()?;
        self.baseline(&baseline)
    }

    /// 等待并交付下一帧；`Ok(None)` 只表示会话不再发布进度。
    pub async fn next(&mut self) -> Result<Option<TimelineTailUpdate>> {
        let Some(update) = self.tail.next().await? else {
            return Ok(None);
        };
        self.convert(update).map(Some)
    }

    /// 释放本连接的基线、连续性缓存与 Session 引用。
    pub fn close(&mut self) {
        self.tail.close();
    }

    fn baseline(&self, baseline: &pl_core::chat::ChatTailBaseline) -> Result<TimelineTailBaseline> {
        Ok(TimelineTailBaseline {
            subscription_id: self.subscription_id.clone(),
            version: baseline.version,
            items: baseline
                .items
                .iter()
                .map(timeline_item)
                .collect::<Result<_>>()?,
            before: baseline
                .before
                .as_ref()
                .map(|cursor| encode_page_cursor(&self.thread_id, cursor)),
            has_older: baseline.has_older,
        })
    }

    fn convert(&self, update: ChatTailUpdate) -> Result<TimelineTailUpdate> {
        Ok(match update {
            ChatTailUpdate::Resync { baseline, reason } => TimelineTailUpdate::Resync {
                subscription_id: self.subscription_id.clone(),
                reason: match reason {
                    pl_core::chat::ChatResyncReason::Lagging => TimelineResyncReason::Lagging,
                    pl_core::chat::ChatResyncReason::Unavailable => {
                        TimelineResyncReason::Unavailable
                    }
                },
                baseline: self.baseline(&baseline)?,
            },
            ChatTailUpdate::Patch(patch) => {
                let mut changes = Vec::with_capacity(patch.changes.len());
                for change in patch.changes {
                    changes.push(self.change(change)?);
                }
                TimelineTailUpdate::Patch {
                    subscription_id: self.subscription_id.clone(),
                    from: patch.from,
                    to: patch.to,
                    changes,
                    priority: match patch.priority {
                        ChatUpdatePriority::Immediate => TimelinePriority::Immediate,
                        ChatUpdatePriority::Coalesced => TimelinePriority::Coalesced,
                    },
                }
            }
        })
    }

    fn change(&self, change: TailChange) -> Result<TimelineChange> {
        Ok(match change {
            TailChange::Add { item } => TimelineChange::Add {
                item: Box::new(timeline_item(&item)?),
            },
            TailChange::Remove { item_id } => TimelineChange::Remove { item_id },
            TailChange::UpdateItem {
                item_id,
                expected_revision,
                revision,
                omitted_bytes,
                saved,
                lifecycle,
                meta,
                fields,
            } => {
                let mut converted = Vec::with_capacity(fields.len());
                for update in fields {
                    let Some(field) = wire_field(&update.field) else {
                        return self.protocol_gap();
                    };
                    converted.push(TimelineFieldUpdate {
                        field,
                        change: field_change(update.change),
                        total_bytes: update.total_bytes,
                        preview_bytes: update.preview_bytes,
                    });
                }
                TimelineChange::UpdateItem {
                    item_id,
                    expected_revision,
                    revision,
                    omitted_bytes,
                    saved,
                    lifecycle: lifecycle_of(lifecycle),
                    item_shell: meta
                        .as_deref()
                        .map(|bytes| item_shell(bytes, revision).map(Box::new))
                        .transpose()?,
                    fields: converted,
                }
            }
        })
    }

    /// 内容字段没有产品域：这是一次无法映射的权威变化，绝不静默丢弃结构化数据。
    fn protocol_gap<T>(&self) -> Result<T> {
        Err(anyhow::anyhow!(pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Protocol,
            "timeline tail delivered a content field this product cannot address",
            false,
        )))
    }
}

fn lifecycle_of(lifecycle: pl_core::chat::ChatLifecycle) -> TimelineLifecycle {
    match lifecycle {
        pl_core::chat::ChatLifecycle::Streaming => TimelineLifecycle::Streaming,
        pl_core::chat::ChatLifecycle::Terminal => TimelineLifecycle::Terminal,
    }
}

fn field_change(change: FieldChange) -> TimelineFieldChange {
    match change {
        FieldChange::Unchanged => TimelineFieldChange::Unchanged,
        FieldChange::Append(text) => TimelineFieldChange::Append { text },
        FieldChange::Replace(block) => TimelineFieldChange::Replace { text: block.text() },
        FieldChange::Remove => TimelineFieldChange::Remove,
    }
}

impl StudioRuntime {
    /// 打开一个 Thread 的内容句柄：捕获同一共享 `Session` 与 Thread 身份。
    ///
    /// 建立句柄前先做一次**只读**的 durable checkpoint 栅栏校验，与 Turns 历史复用同一份抽象：栅栏未
    /// 满足时类型化 `Busy` 失败闭锁，绝不返回落后行、也绝不因此激活 owner／flush writer／触发恢复。
    ///
    /// # Errors
    /// 未知 Thread 身份，或 history 落后于 durable checkpoint 栅栏（`Busy`）。
    pub async fn timeline_reader(&self, thread_id: &str) -> Result<TimelineContentReader> {
        // Opening a content handle is a read: it never imports or deletes storage, only verifies that
        // the durable watermark already covers the saved checkpoint fence.
        self.read_timeline_history(thread_id).await?;
        Ok(TimelineContentReader {
            thread_id: thread_id.to_owned(),
            session: self.chat_session(thread_id).await?,
        })
    }

    /// 读一页轻量预览；HTTP 与 FRB 共用同一份映射。
    ///
    /// # Errors
    /// 见 [`TimelineContentReader::page`]。
    pub async fn timeline_page(
        &self,
        thread_id: &str,
        query: &TimelinePageQuery,
    ) -> Result<TimelinePage> {
        self.timeline_reader(thread_id).await?.page(query).await
    }

    /// 打开一条有界尾部连接。
    ///
    /// # Errors
    /// 见 [`TimelineContentReader::open_tail`]。
    pub async fn open_timeline_tail(&self, thread_id: &str) -> Result<TimelineTailStream> {
        self.timeline_reader(thread_id).await?.open_tail().await
    }

    /// 读一段完整正文块。
    ///
    /// # Errors
    /// 见 [`TimelineContentReader::read_detail`]。
    pub async fn read_timeline_detail(
        &self,
        thread_id: &str,
        item_id: &str,
        query: &TimelineDetailQuery,
    ) -> Result<TimelineDetailChunk> {
        self.timeline_reader(thread_id)
            .await?
            .read_detail(item_id, query)
            .await
    }
}
