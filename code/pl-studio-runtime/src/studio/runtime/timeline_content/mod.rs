//! HTTP 与 FRB 共用的 Timeline 内容映射：唯一一处 core → 产品预览／字段变化转换。
//!
//! [`TimelineContentReader`] 捕获**同一个**共享 `Session` 与 Thread 身份，页、详情与尾部连接都从它
//! 出发：一次打开之后不再按 thread id 重查运行时实例，因此旧的句柄不会读到另一个实例，也不会与
//! 自己的尾部观察分叉。HTTP 每条请求与 FRB 每个句柄共用这一份映射实现。
//!
//! 这里不缓存第二份正文，也不重建客户端基线。

mod field;
pub(crate) mod meta;
pub(crate) mod preview;

use anyhow::Result;
use pl_core::chat::{
    ChatDetailRequest, ChatPageRequest, ChatTail, ChatTailUpdate, Session, TimelineEpoch,
};
use pl_protocol::{
    TimelineCompletionCursor, TimelineDetailChunk, TimelineDetailQuery, TimelinePage,
    TimelinePageQuery, TimelineTailBaseline, TimelineTailUpdate,
};

use super::StudioRuntime;
use field::{core_field, detail_cursor, encode_detail_cursor, encode_page_cursor, page_cursor};
use preview::timeline_item;

/// 一个 Thread 的内容句柄：捕获同一共享 `Session` 与 Thread 身份。
///
/// 它只持内容事实的引用（不是执行 owner pin），因此读取不会激活 Thread、也不阻止其空闲退役；关闭
/// 句柄即释放这些引用，而 Thread、Turn 与历史 writer 继续运行。
#[derive(Clone)]
pub struct TimelineContentReader {
    thread: pl_protocol::Thread,
    recovery: crate::studio::StudioRecoveryRegistry,
    session: Session,
}

impl TimelineContentReader {
    /// 本句柄所属的 Thread 身份。
    pub fn thread_id(&self) -> &str {
        &self.thread.id
    }

    /// 当前注册 Session 的完成代际。
    pub fn epoch(&self) -> String {
        self.session.epoch().as_str().to_owned()
    }

    /// 已初始化 Session 的当前可见完成上界；冷会话初始化前为零。
    pub fn head_seq(&self) -> u64 {
        self.session.head_seq()
    }

    /// 当前注册 Session 已由 writer 确认的连续持久化完成前缀。
    /// page/open_tail 已完成初始化后，冷历史的该值同样来自真实持久化种子。
    pub fn durable_seq(&self) -> u64 {
        self.session.durable_seq()
    }

    /// 复核本句柄的恢复读准入：与分页、详情和尾部建立共用同一 Registry 决策。
    ///
    /// 组合观察在交付已捕获的基线或已就绪事件前调用它——仍使用原已登记接收者与原捕获
    /// 基线，不为检查重新订阅或重读正文。`AccessBlocked` 拒绝读取，执行阻塞与 advisory
    /// 不额外禁止健康历史；失败保留原类型化错误。
    ///
    /// # Errors
    /// 传播 [`crate::studio::StudioRecoveryRegistry::ensure_thread_read_access`] 的类型化失败。
    pub(crate) fn ensure_read_access(&self) -> Result<()> {
        self.recovery.ensure_thread_read_access(&self.thread)
    }

    /// 读一页最新或更旧的 keyset 页。
    ///
    /// # Errors
    /// 未知／跨 Thread 的游标与非法条目数返回 `InvalidArgument`，其余为宿主的类型化存储与预览失败。
    pub async fn page(&self, query: &TimelinePageQuery) -> Result<TimelinePage> {
        self.recovery.ensure_thread_read_access(&self.thread)?;
        let before = match query.before.as_deref() {
            None => None,
            Some(token) => Some(page_cursor(&self.thread.id, token)?),
        };
        let page = self
            .session
            .page(ChatPageRequest {
                before,
                limit: query.limit(),
            })
            .await?;
        self.recovery.ensure_thread_read_access(&self.thread)?;
        let mut items = Vec::with_capacity(page.items.len());
        for item in &page.items {
            items.push(timeline_item(item)?);
        }
        Ok(TimelinePage {
            thread_id: self.thread.id.clone(),
            timeline_epoch: page.epoch.as_str().to_owned(),
            items,
            before: page
                .before
                .as_ref()
                .map(|cursor| encode_page_cursor(&self.thread.id, cursor)),
            has_older: page.has_older,
        })
    }

    /// 读一段完整正文块。
    ///
    /// # Errors
    /// 跨上下文的 continuation、非法块大小、过期 epoch、未知条目／字段与存储失败。
    pub async fn read_detail(
        &self,
        item_id: &str,
        query: &TimelineDetailQuery,
    ) -> Result<TimelineDetailChunk> {
        self.recovery.ensure_thread_read_access(&self.thread)?;
        let requested_epoch = TimelineEpoch::new(query.timeline_epoch.clone())?;
        let session_epoch = self.session.epoch();
        if requested_epoch != session_epoch {
            return Err(pl_core::chat::ChatError::EpochMismatch {
                cursor: requested_epoch,
                session: session_epoch,
            }
            .into());
        }
        let mut request = ChatDetailRequest::new(item_id, core_field(query.field));
        if let Some(token) = query.continuation.as_deref() {
            request =
                request.with_continuation(detail_cursor(&self.thread.id, item_id, query, token)?);
        }
        if let Some(max_bytes) = query.max_bytes {
            request = request.with_max_bytes(max_bytes as usize);
        }
        let chunk = self.session.read_detail(request).await?;
        self.recovery.ensure_thread_read_access(&self.thread)?;
        Ok(TimelineDetailChunk {
            thread_id: self.thread.id.clone(),
            item_id: chunk.item_id,
            field: query.field,
            timeline_epoch: query.timeline_epoch.clone(),
            text: chunk.text,
            total_bytes: chunk.total_bytes,
            continuation: chunk.continuation.map(|cursor| {
                encode_detail_cursor(&self.thread.id, item_id, query, cursor.offset())
            }),
        })
    }

    /// 建立一条有界尾部连接。
    ///
    /// # Errors
    /// 共享基线的存储与预览读取失败。
    pub async fn open_tail(&self) -> Result<TimelineTailStream> {
        self.recovery.ensure_thread_read_access(&self.thread)?;
        let tail = self.session.subscribe_tail().await?;
        self.recovery.ensure_thread_read_access(&self.thread)?;
        Ok(TimelineTailStream {
            thread: self.thread.clone(),
            recovery: self.recovery.clone(),
            // 复用已有的 id 能力（时间前缀 + 进程内序号），因此重启后也不会重复旧身份，且不额外
            // 引入随机/编码依赖。
            subscription_id: crate::studio::ids::new_id("timeline-tail"),
            epoch: self.session.epoch().as_str().to_owned(),
            tail,
        })
    }

    /// 只从已接纳的完成序号续接；内部占位首帧不公开为最新基线。
    pub async fn open_tail_after(
        &self,
        after: &TimelineCompletionCursor,
    ) -> Result<TimelineTailStream> {
        self.ensure_read_access()?;
        let mut tail = self
            .session
            .subscribe_after(pl_core::chat::ChatCompletionCursor::new(
                TimelineEpoch::new(after.timeline_epoch.clone())?,
                after.append_seq,
            ))
            .await?;
        tail.initial()?;
        self.ensure_read_access()?;
        Ok(TimelineTailStream {
            thread: self.thread.clone(),
            recovery: self.recovery.clone(),
            subscription_id: crate::studio::ids::new_id("timeline-tail"),
            epoch: self.session.epoch().as_str().to_owned(),
            tail,
        })
    }
}

/// 一条 `GET /timeline/events` 连接或一个 FRB `BridgeTimeline` 自有的尾部观察。
pub struct TimelineTailStream {
    thread: pl_protocol::Thread,
    recovery: crate::studio::StudioRecoveryRegistry,
    subscription_id: String,
    epoch: String,
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
    pub async fn initial(&mut self) -> Result<TimelineTailBaseline> {
        self.recovery.ensure_thread_read_access(&self.thread)?;
        let baseline = self.tail.initial()?;
        self.baseline(&baseline)
    }

    /// 等待并交付下一帧；`Ok(None)` 只表示会话不再发布进度。
    pub async fn next(&mut self) -> Result<Option<TimelineTailUpdate>> {
        self.recovery.ensure_thread_read_access(&self.thread)?;
        let update = self.tail.next().await?;
        self.recovery.ensure_thread_read_access(&self.thread)?;
        match update {
            ChatTailUpdate::Closed => Ok(None),
            ChatTailUpdate::Batch(batch) => Ok(Some(TimelineTailUpdate::Batch {
                subscription_id: self.subscription_id.clone(),
                timeline_epoch: self.epoch.clone(),
                from_seq: batch.from_seq,
                through_seq: batch.through_seq,
                items: batch
                    .items
                    .iter()
                    .map(timeline_item)
                    .collect::<Result<_>>()?,
            })),
        }
    }

    /// 释放本连接的基线、连续性缓存与 Session 引用。
    pub fn close(&mut self) {
        self.tail.close();
    }

    fn baseline(&self, baseline: &pl_core::chat::ChatTailBaseline) -> Result<TimelineTailBaseline> {
        Ok(TimelineTailBaseline {
            subscription_id: self.subscription_id.clone(),
            timeline_epoch: baseline.epoch.as_str().to_owned(),
            completed_cursor: TimelineCompletionCursor {
                timeline_epoch: baseline.epoch.as_str().to_owned(),
                append_seq: baseline
                    .completed_cursor
                    .as_ref()
                    .map_or(0, |cursor| cursor.append_seq),
            },
            items: baseline
                .items
                .iter()
                .map(timeline_item)
                .collect::<Result<_>>()?,
            before: baseline
                .before
                .as_ref()
                .map(|cursor| encode_page_cursor(&self.thread.id, cursor)),
            has_older: baseline.has_older,
        })
    }
}

impl StudioRuntime {
    /// 打开一个 Thread 的内容句柄：捕获同一共享 `Session` 与 Thread 身份。
    ///
    /// 建立句柄时由存储所有者显式准备当前历史格式并校验 durable checkpoint 栅栏；之后页与详情纯读。
    /// 准备不创建缺失历史库、不激活执行 owner、不 flush writer，也不重放副作用。
    ///
    /// # Errors
    /// 未知 Thread、存储/迁移失败，或 history 落后于 durable checkpoint 栅栏（`Busy`）。
    pub async fn timeline_reader(&self, thread_id: &str) -> Result<TimelineContentReader> {
        // 该入口由存储重构提供，负责 prepare_history_access + 只读 checkpoint fence；
        // 不在读取映射复制迁移或为旧结构保留 fallback。
        self.prepare_timeline_history(thread_id).await?;
        self.timeline_projection_reader(thread_id).await
    }

    /// Handle construction and detail reads check the prepared representation without migrating it.
    async fn timeline_projection_reader(&self, thread_id: &str) -> Result<TimelineContentReader> {
        self.read_timeline_history(thread_id).await?;
        Ok(TimelineContentReader {
            thread: self.read_protocol_thread(thread_id).await?,
            recovery: self.recovery.clone(),
            session: self.store.chat_session(thread_id).await?,
        })
    }

    /// 独立内容入口先显式打开已有历史，再读一页轻量预览；HTTP 与 FRB 共用同一份映射。
    /// 已打开句柄的后续分页仍由 [`TimelineContentReader::page`] 严格只读完成。
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
