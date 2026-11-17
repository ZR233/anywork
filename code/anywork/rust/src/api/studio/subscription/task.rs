//! 保留原始任务和终态，避免等待者消费失败后伪报成功。

use tokio::task::JoinHandle;

use crate::api::studio::types::BridgeError;

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
pub(crate) struct OwnedTaskSlot {
    pub(crate) task: Option<JoinHandle<Result<(), BridgeError>>>,
    pub(crate) outcome: Option<Result<(), BridgeError>>,
}

impl OwnedTaskSlot {
    pub(crate) async fn join(&mut self, message: &'static str) -> Result<(), BridgeError> {
        if let Some(task) = self.task.as_mut() {
            let result = match task.await {
                Ok(result) => result,
                Err(_) => Err(pl_studio_runtime::StudioError::new(
                    pl_studio_runtime::StudioErrorCode::Internal,
                    message,
                    false,
                )
                .into()),
            };
            self.task = None;
            self.outcome = Some(result);
        }
        self.outcome.clone().unwrap_or(Ok(()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::poll;
    use std::task::Poll;
    use tokio::sync::oneshot;

    #[tokio::test]
    async fn abandoned_wait_keeps_original_task_and_its_terminal_failure() {
        let (release, waiting) = oneshot::channel();
        let original: BridgeError = pl_studio_runtime::StudioError::new(
            pl_studio_runtime::StudioErrorCode::Storage,
            "original task failure",
            false,
        )
        .into();
        let failure = original.clone();
        let mut slot = OwnedTaskSlot {
            task: Some(tokio::spawn(async move {
                let _ = waiting.await;
                Err(failure)
            })),
            outcome: None,
        };
        let mut first = Box::pin(slot.join("task stopped"));
        assert!(matches!(poll!(first.as_mut()), Poll::Pending));
        drop(first);
        release.send(()).unwrap();
        assert_eq!(slot.join("task stopped").await.unwrap_err(), original);
        assert!(slot.task.is_none());
        assert_eq!(slot.join("task stopped").await.unwrap_err(), original);
    }

    #[tokio::test]
    async fn panic_is_not_erased_by_a_second_join() {
        let mut slot = OwnedTaskSlot {
            task: Some(tokio::spawn(async { panic!("injected task panic") })),
            outcome: None,
        };
        let first = slot.join("task failed").await.unwrap_err();
        assert!(!first.retryable);
        assert_eq!(slot.join("task failed").await.unwrap_err(), first);
    }
}
