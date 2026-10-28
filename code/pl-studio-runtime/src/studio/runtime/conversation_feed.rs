//! 同一会话的组合观察所有者；只组合两域等待，不投影事实或合并两域水位。

use anyhow::Result;
use futures::future::BoxFuture;
use pl_protocol::{
    ThreadSubscriptionRequest, ThreadSubscriptionUpdate, TimelineTailBaseline, TimelineTailUpdate,
    studio::{StudioError, StudioErrorCode},
};
use tokio_util::sync::CancellationToken;

use super::{StudioRuntime, StudioThreadSubscription, TimelineContentReader, TimelineTailStream};

/// 两域各自有序的数据事件；正常结束和失败由传输转换为各自的终帧。
#[derive(Debug)]
pub enum ConversationEvent {
    State {
        update: Box<ThreadSubscriptionUpdate>,
    },
    ContentBaseline {
        baseline: TimelineTailBaseline,
    },
    ContentUpdate {
        update: TimelineTailUpdate,
    },
}

type StateWait = BoxFuture<
    'static,
    (
        StudioThreadSubscription,
        Result<Option<ThreadSubscriptionUpdate>>,
    ),
>;
type ContentWait = BoxFuture<'static, (TimelineTailStream, Result<Option<TimelineTailUpdate>>)>;

/// 单消费者组合观察。独立内容查询不借用接收等待，也不拥有执行资源。
///
/// 每域的订阅和在途读取都存放在本体：另一域先就绪或取消一次 `recv` 不会丢掉状态首帧。
/// 本体不派生后台任务；关闭与析构只退役自己的观察，不取消业务执行或可靠保存。
pub struct ConversationFeed {
    reader: TimelineContentReader,
    subscription_id: String,
    initial: Option<TimelineTailBaseline>,
    state_wait: Option<StateWait>,
    content_wait: Option<ContentWait>,
    cancel: CancellationToken,
}

impl std::fmt::Debug for ConversationFeed {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ConversationFeed")
            .field("thread_id", &self.thread_id())
            .field("subscription_id", &self.subscription_id)
            .field("closed", &self.cancel.is_cancelled())
            .field("has_initial", &self.initial.is_some())
            .field("has_state_wait", &self.state_wait.is_some())
            .field("has_content_wait", &self.content_wait.is_some())
            .finish()
    }
}

impl StudioRuntime {
    /// 打开同一会话的内容尾部与状态观察；每个域沿自己的登记／基线边界恢复。
    ///
    /// # Errors
    /// 传播内容准备、基线转换与状态准入失败。部分打开失败或等待被取消时，局部所有者自动释放。
    pub async fn open_conversation_feed(&self, thread_id: &str) -> Result<ConversationFeed> {
        let reader = self.timeline_reader(thread_id).await?;
        let mut content = reader.open_tail().await?;
        let subscription_id = content.subscription_id().to_owned();
        let initial = content.initial().await?;
        let state = self
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: thread_id.to_owned(),
            })
            .await?;
        let cancel = CancellationToken::new();
        Ok(ConversationFeed {
            reader,
            subscription_id,
            initial: Some(initial),
            state_wait: Some(wait_state(state, cancel.clone())),
            content_wait: Some(wait_content(content, cancel.clone())),
            cancel,
        })
    }
}

impl ConversationFeed {
    /// 所绑定的会话身份。
    pub fn thread_id(&self) -> &str {
        self.reader.thread_id()
    }

    /// 所拥有内容尾部的身份；重新打开会产生新身份。
    pub fn subscription_id(&self) -> &str {
        &self.subscription_id
    }

    /// 与尾部绑定同一 Session 的独立查询句柄，可由传输克隆以避开接收等待。
    pub fn reader(&self) -> &TimelineContentReader {
        &self.reader
    }

    /// 等待两域之一；内容基线只移交一次，各域的首帧都先于该域增量。
    ///
    /// 取消本次等待不会重建任何域的读取。两个源都自然结束才返回 `None`。
    ///
    /// # Errors
    /// 已请求关闭时优先返回类型化 `Cancelled`；源错误原样传播，不伪装成自然结束。交付任何
    /// 已捕获数据前复核同一读准入：复核失败保留原错误并收束本观察，不转成空数据或正常结束。
    pub async fn recv(&mut self) -> Result<Option<ConversationEvent>> {
        loop {
            if self.cancel.is_cancelled() {
                return Err(cancelled());
            }
            if let Some(baseline) = self.initial.take() {
                // 缓存基线可能已跨过等待：在已登记接收者与已捕获基线上复核同一读准入，
                // 不重新订阅、不重读正文；失败时收束原观察并保留类型化错误。
                if let Err(error) = self.reader.ensure_read_access() {
                    self.initial = Some(baseline);
                    self.request_close();
                    return Err(error);
                }
                return Ok(Some(ConversationEvent::ContentBaseline { baseline }));
            }
            if self.state_wait.is_none() && self.content_wait.is_none() {
                return Ok(None);
            }
            // 两域公平竞争；各自持久等待内部的取消分支始终优先，状态繁忙不饿死内容。
            tokio::select! {
                (state, result) = receive_slot(&mut self.state_wait) => {
                    // 已完成的 future 必须先清槽，错误路径也不能再次轮询它。
                    self.state_wait = None;
                    match result {
                        Ok(Some(update)) => {
                            if let Err(error) = self.reader.ensure_read_access() {
                                drop(state);
                                self.request_close();
                                return Err(error);
                            }
                            self.state_wait = Some(wait_state(state, self.cancel.clone()));
                            return Ok(Some(ConversationEvent::State { update: Box::new(update) }));
                        }
                        Ok(None) => drop(state),
                        Err(error) => {
                            self.request_close();
                            return Err(error);
                        }
                    }
                }
                (mut content, result) = receive_slot(&mut self.content_wait) => {
                    self.content_wait = None;
                    match result {
                        Ok(Some(update)) => {
                            if let Err(error) = self.reader.ensure_read_access() {
                                content.close();
                                self.request_close();
                                return Err(error);
                            }
                            self.content_wait = Some(wait_content(content, self.cancel.clone()));
                            return Ok(Some(ConversationEvent::ContentUpdate { update }));
                        }
                        Ok(None) => content.close(),
                        Err(error) => {
                            content.close();
                            self.request_close();
                            return Err(error);
                        }
                    }
                }
            }
        }
    }

    /// 同步封闭接收准入，唤醒两域等待；不发出业务取消。
    pub fn request_close(&self) {
        self.cancel.cancel();
    }

    /// 退役两域真实接收者、状态驻留 pin 与未交付首帧，可重复调用。
    ///
    /// 关闭被取消时，尚未收束的 future 仍留在本体，可再次关闭。独立查询句柄不声明订阅需求。
    ///
    /// # Errors
    /// 当前关闭只有资源释放，不产生业务错误。
    pub async fn close(&mut self) -> Result<()> {
        self.request_close();
        self.initial = None;
        if let Some(wait) = self.state_wait.as_mut() {
            let (state, _) = wait.await;
            self.state_wait = None;
            drop(state);
        }
        if let Some(wait) = self.content_wait.as_mut() {
            let (mut content, _) = wait.await;
            self.content_wait = None;
            content.close();
        }
        Ok(())
    }
}

impl Drop for ConversationFeed {
    fn drop(&mut self) {
        // 无派生任务：随后字段析构直接释放 future 所拥有的真实订阅与 pin。
        self.request_close();
    }
}

fn wait_state(mut state: StudioThreadSubscription, cancel: CancellationToken) -> StateWait {
    Box::pin(async move {
        let result = tokio::select! {
            biased;
            () = cancel.cancelled() => Err(cancelled()),
            result = state.recv() => result,
        };
        (state, result)
    })
}

fn wait_content(mut content: TimelineTailStream, cancel: CancellationToken) -> ContentWait {
    Box::pin(async move {
        let result = tokio::select! {
            biased;
            () = cancel.cancelled() => Err(cancelled()),
            result = content.next() => result,
        };
        (content, result)
    })
}

async fn receive_slot<T>(slot: &mut Option<BoxFuture<'static, T>>) -> T {
    match slot {
        Some(wait) => wait.await,
        None => std::future::pending().await,
    }
}

fn cancelled() -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Conversation observation is closed",
        false,
    )
    .into()
}
