use super::owner::{CLAIM_RENEW_INTERVAL, Step, watch_error};
use crate::bots::InboundWorkOutcome;
use crate::bots::protocol::error::FeishuError;
use crate::studio::{StudioRuntime, StudioThreadSubscription, TimelineTailStream};
use pl_protocol::ThreadSubscriptionRequest;
use tokio_util::sync::CancellationToken;

/// 观察句柄：订阅与有界尾部窗口都只作为唤醒源；失效后由 `ensure_alive` 重开。
pub(super) struct ReplyWatch {
    subscription: Option<StudioThreadSubscription>,
    window: Option<TimelineTailStream>,
}

impl ReplyWatch {
    pub(super) async fn open(
        runtime: &StudioRuntime,
        thread_id: &str,
    ) -> Result<Self, FeishuError> {
        let subscription = runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: thread_id.to_string(),
            })
            .await
            .map_err(|error| watch_error("bot Thread subscribe failed", &format!("{error:#}")))?;
        let window = runtime
            .open_timeline_tail(thread_id)
            .await
            .map_err(|error| watch_error("bot chat window failed", &format!("{error:#}")))?;
        Ok(Self {
            subscription: Some(subscription),
            window: Some(window),
        })
    }

    pub(super) async fn ensure_alive(
        &mut self,
        runtime: &StudioRuntime,
        thread_id: &str,
    ) -> Result<(), FeishuError> {
        if self.subscription.is_none() {
            let subscription = runtime
                .subscribe_thread(ThreadSubscriptionRequest {
                    thread_id: thread_id.to_string(),
                })
                .await
                .map_err(|error| {
                    watch_error("bot Thread resubscribe failed", &format!("{error:#}"))
                })?;
            self.subscription = Some(subscription);
        }
        if self.window.is_none() {
            let window = runtime
                .open_timeline_tail(thread_id)
                .await
                .map_err(|error| {
                    watch_error("bot chat window reopen failed", &format!("{error:#}"))
                })?;
            self.window = Some(window);
        }
        Ok(())
    }

    /// 等待任一唤醒或续约定时；取消是 Interrupted（保留未决），不是本地交互结束。
    pub(super) async fn wait(&mut self, cancel: &CancellationToken) -> Step {
        let renew = tokio::time::sleep(CLAIM_RENEW_INTERVAL);
        tokio::pin!(renew);
        tokio::select! {
            _ = cancel.cancelled() => Step::Done(InboundWorkOutcome::Interrupted),
            _ = &mut renew => Step::Wait,
            update = subscription_recv(self.subscription.as_mut()) => {
                match update {
                    // 帧内容只作唤醒；结局一律由下一轮 canonical 重建裁决。
                    Ok(Some(_)) => Step::Wait,
                    Ok(None) | Err(_) => {
                        self.subscription = None;
                        Step::Wait
                    }
                }
            }
            update = window_next(self.window.as_mut()) => {
                match update {
                    Ok(Some(_)) => Step::Wait,
                    Ok(None) | Err(_) => {
                        self.window = None;
                        Step::Wait
                    }
                }
            }
        }
    }
}

async fn subscription_recv(
    subscription: Option<&mut StudioThreadSubscription>,
) -> anyhow::Result<Option<pl_protocol::ThreadSubscriptionUpdate>> {
    match subscription {
        Some(subscription) => subscription.recv().await,
        None => std::future::pending().await,
    }
}

async fn window_next(
    window: Option<&mut TimelineTailStream>,
) -> anyhow::Result<Option<pl_protocol::TimelineTailUpdate>> {
    match window {
        Some(window) => window.next().await,
        None => std::future::pending().await,
    }
}
