//! 配置转发只持窄依赖；scope 在创建前登记，关闭先取消通知等待再 join 原任务。

use super::super::StudioRuntime;
use super::super::observation_lifecycle::{ObservationStartError, ObserverTask, RuntimeObserver};

impl StudioRuntime {
    pub(super) async fn start_agent_profiles_forwarder(&self) -> anyhow::Result<()> {
        let bus = self.agent_facility.product_events.clone();
        let config = self.config_runtime.clone();
        self.observations
            .start(RuntimeObserver::Profiles, move |cancellation| async move {
                let mut updates = config.subscribe_agent_profiles();
                let task_cancel = cancellation.clone();
                let task = tokio::spawn(async move {
                    loop {
                        tokio::select! {
                            biased;
                            _ = task_cancel.cancelled() => break,
                            change = updates.changed() => if change.is_err() { break; },
                        }
                        match config.agent_profiles_snapshot() {
                            Ok(snapshot) => {
                                bus.emit_agent_profiles_state(snapshot.into());
                            }
                            Err(error) => {
                                tracing::warn!(%error, "Agent Profiles snapshot read failed")
                            }
                        }
                    }
                });
                Ok(ObserverTask::new(cancellation, task))
            })
            .await
            .map(|_| ())
            .map_err(|error| ObservationStartError(error).into())
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use pl_lifecycle::{CloseError, OpenError};
    use tokio::sync::oneshot;

    use super::*;
    use crate::studio::runtime::observation_lifecycle::RuntimeObservationOwner;

    #[tokio::test]
    async fn idle_observer_cancel_wakes_without_source_closing() {
        let owner = RuntimeObservationOwner::new();
        let (source, mut updates) = tokio::sync::watch::channel(());
        let (exited, exit) = oneshot::channel();
        let resource = owner
            .start(RuntimeObserver::Profiles, move |cancel| async move {
                let task_cancel = cancel.clone();
                let task = tokio::spawn(async move {
                    tokio::select! {
                        biased;
                        _ = task_cancel.cancelled() => {},
                        _ = updates.changed() => panic!("source did not change"),
                    }
                    exited.send(()).unwrap();
                });
                Ok(ObserverTask::new(cancel, task))
            })
            .await
            .unwrap();
        owner.request_close();
        let report = owner.close(RuntimeObserver::Profiles, None).await;
        assert!(report.is_clean());
        exit.await.unwrap();
        assert_eq!(source.receiver_count(), 0);
        drop(resource);
    }

    #[tokio::test]
    async fn concurrent_start_keeps_one_identity_when_a_waiter_leaves() {
        let owner = RuntimeObservationOwner::new();
        let created = Arc::new(AtomicUsize::new(0));
        let (entered, entry) = oneshot::channel();
        let (release, released) = oneshot::channel();
        let started = created.clone();
        let first = owner.start(RuntimeObserver::Profiles, move |cancel| async move {
            started.fetch_add(1, Ordering::SeqCst);
            entered.send(()).unwrap();
            released.await.unwrap();
            let task_cancel = cancel.clone();
            let task = tokio::spawn(async move { task_cancel.cancelled().await });
            Ok(ObserverTask::new(cancel, task))
        });
        let second = owner.start(RuntimeObserver::Profiles, |_| async {
            panic!("a concurrent caller must not run a replacement factory")
        });
        let mut leaving = Box::pin(first.clone());
        assert!(futures::poll!(&mut leaving).is_pending());
        entry.await.unwrap();
        drop(leaving);
        release.send(()).unwrap();
        let (a, b) = tokio::join!(first, second);
        let (a, b) = (a.unwrap(), b.unwrap());
        assert!(Arc::ptr_eq(&a, &b));
        assert_eq!(created.load(Ordering::SeqCst), 1);
        owner.request_close();
        assert!(
            owner
                .close(RuntimeObserver::Profiles, None)
                .await
                .is_clean()
        );
    }

    #[tokio::test]
    async fn all_start_waiters_may_leave_before_late_resource_and_close() {
        let owner = RuntimeObservationOwner::new();
        let created = Arc::new(AtomicUsize::new(0));
        let (entered, entry) = oneshot::channel();
        let (release, released) = oneshot::channel();
        let (exited, exit) = oneshot::channel();
        let count = created.clone();
        let mut start = Box::pin(owner.start(
            RuntimeObserver::Persistence,
            move |cancel| async move {
                entered.send(()).unwrap();
                released.await.unwrap();
                count.fetch_add(1, Ordering::SeqCst);
                let task_cancel = cancel.clone();
                let task = tokio::spawn(async move {
                    task_cancel.cancelled().await;
                    exited.send(()).unwrap();
                });
                Ok(ObserverTask::new(cancel, task))
            },
        ));
        assert!(futures::poll!(&mut start).is_pending());
        entry.await.unwrap();
        drop(start); // stored Shared 不再被任何启动等待者 poll。
        owner.request_close();
        let pending = owner
            .close(
                RuntimeObserver::Persistence,
                Some(pl_lifecycle::Instant::now()),
            )
            .await;
        assert!(!pending.is_clean());
        assert_eq!(pending.pending.len(), 1);
        let identity = pending.pending[0].resource.clone();
        assert_eq!(identity.label, "persistenceObserver");
        release.send(()).unwrap();
        assert!(
            owner
                .close(RuntimeObserver::Persistence, None)
                .await
                .is_clean()
        );
        exit.await.unwrap();
        assert_eq!(created.load(Ordering::SeqCst), 1);
        let result = owner
            .start(RuntimeObserver::Persistence, |_| async {
                panic!("a cancelled epoch must never restart")
            })
            .await;
        assert!(matches!(result, Err(error) if matches!(error.as_ref(), OpenError::Cancelled)));
    }

    #[tokio::test]
    async fn unpolled_start_has_no_effect_and_loses_to_scope_close() {
        let owner = RuntimeObservationOwner::new();
        let future = owner.start(RuntimeObserver::Lsp, |_| async {
            panic!("closed scope must reject the factory without executing it")
        });
        owner.request_close();
        assert!(owner.close(RuntimeObserver::Lsp, None).await.is_clean());
        assert!(
            matches!(future.await, Err(error) if matches!(error.as_ref(), OpenError::ScopeClosed))
        );
    }

    #[tokio::test]
    async fn task_panic_keeps_original_join_diagnostic_across_close_observations() {
        let owner = RuntimeObservationOwner::new();
        let original = owner
            .start(RuntimeObserver::Profiles, |cancel| async move {
                let task = tokio::spawn(async { panic!("original observer panic identity") });
                Ok(ObserverTask::new(cancel, task))
            })
            .await
            .unwrap();
        owner.request_close();
        let first = owner.close(RuntimeObserver::Profiles, None).await;
        let again = owner.close(RuntimeObserver::Profiles, None).await;
        assert!(!first.is_clean());
        assert_eq!(first.failures.len(), 1);
        assert_eq!(first.failures[0].resource, again.failures[0].resource);
        assert_eq!(first.failures[0].attempt_id, again.failures[0].attempt_id);
        let (CloseError::Resource(a), CloseError::Resource(b)) =
            (&first.failures[0].error, &again.failures[0].error)
        else {
            panic!("original typed error missing")
        };
        assert!(Arc::ptr_eq(a, b));
        assert!(a.to_string().contains("original observer panic identity"));
        let cached = owner
            .start(RuntimeObserver::Profiles, |_| async {
                panic!("panic must not open a replacement observer")
            })
            .await
            .unwrap();
        assert!(Arc::ptr_eq(&original, &cached));
    }

    #[tokio::test]
    async fn unexpected_abort_is_not_cooperative_cancellation() {
        let owner = RuntimeObservationOwner::new();
        let (abort_tx, abort_rx) = oneshot::channel();
        let _resource = owner
            .start(RuntimeObserver::Profiles, |cancel| async move {
                let task = tokio::spawn(std::future::pending::<()>());
                abort_tx.send(task.abort_handle()).unwrap();
                Ok(ObserverTask::new(cancel, task))
            })
            .await
            .unwrap();
        abort_rx.await.unwrap().abort();
        owner.request_close();
        let report = owner.close(RuntimeObserver::Profiles, None).await;
        assert!(!report.is_clean());
        assert_eq!(report.failures.len(), 1);
        assert!(matches!(report.failures[0].error, CloseError::Resource(_)));
    }

    #[tokio::test]
    async fn observers_do_not_keep_the_runtime_or_its_owner_alive() -> anyhow::Result<()> {
        let temp = tempfile::tempdir()?;
        let host =
            crate::studio::runtime::bot_archive_test_host::BotArchiveTestHost::new(temp.path())
                .await?;
        // 其他业务任务的 self clone 不在本次迁移范围；先按原 owner 收束，只留下三类观察。
        let (models, tools, recovery, catalogs) = tokio::join!(
            host.runtime.stop_model_refresh(),
            host.runtime.stop_tool_refresh(),
            host.runtime.stop_recovery_scan(),
            host.runtime.stop_model_catalog_probes(),
        );
        models?;
        tools?;
        recovery?;
        catalogs?;
        host.runtime
            .bots
            .shutdown()
            .await
            .map_err(|error| anyhow::anyhow!("{error:?}"))?;
        let runtime = Arc::downgrade(&host.runtime);
        let owner = Arc::downgrade(&host.runtime.observations);
        let scoped = host.runtime.observations.clone();
        let mut resources = Vec::new();
        for observer in [
            RuntimeObserver::Profiles,
            RuntimeObserver::Persistence,
            RuntimeObserver::Lsp,
        ] {
            resources.push(
                scoped
                    .start(observer, |_| async { panic!("already started") })
                    .await
                    .unwrap(),
            );
        }
        let writer = host
            .runtime
            .agent_facility
            .persistence
            .lock()
            .await
            .clone()
            .unwrap();
        let store = host.runtime.store.clone();
        let executor = host.runtime.thread_factory.local_executor();
        drop(host);
        assert!(
            runtime.upgrade().is_none(),
            "observer must not capture a full runtime"
        );
        assert_eq!(
            Arc::strong_count(&scoped),
            1,
            "data tasks only borrow narrow services"
        );
        drop(scoped);
        assert!(
            owner.upgrade().is_none(),
            "last real owner Drop must remain reachable"
        );
        for resource in resources {
            resource
                .close()
                .await
                .map_err(|error| anyhow::anyhow!("{error:?}"))?;
        }
        executor.close().await?;
        writer.shutdown().await?;
        store.close().await?;
        Ok(())
    }
}
