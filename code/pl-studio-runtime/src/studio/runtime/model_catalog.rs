//! Account-scoped discovery admission and durable ownership of active/retired probe tasks.

use super::StudioRuntime;
use crate::config::AccountId;
use anyhow::{Result, anyhow};
use pl_protocol::studio::{SyncAccountModelsReply, SyncAccountModelsRequest};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex, PoisonError},
};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Default)]
pub(super) struct ModelCatalogTasks(Arc<Mutex<Tasks>>);

#[derive(Default)]
struct Tasks {
    started: bool,
    closing: bool,
    next_id: u64,
    active: BTreeMap<AccountId, u64>,
    // Never removed merely because a waiter was cancelled or a newer generation was admitted.
    retained: BTreeMap<u64, Arc<ProbeTask>>,
    close: Option<Arc<ProbeTask>>,
}

struct ProbeTask {
    account: Option<AccountId>,
    operation_id: String,
    generation: u64,
    cancel: CancellationToken,
    join: tokio::sync::Mutex<Option<tokio::task::JoinHandle<Result<()>>>>,
    outcome: Mutex<Option<Result<(), String>>>,
}

impl ProbeTask {
    fn finished(&self) -> bool {
        self.join
            .try_lock()
            .is_ok_and(|slot| slot.as_ref().is_none_or(|task| task.is_finished()))
    }

    /// Borrow the registered handle. Dropping a close waiter cannot drop the owned task/commit.
    async fn wait(&self) -> Result<()> {
        let mut slot = self.join.lock().await;
        if let Some(task) = slot.as_mut() {
            let outcome = match task.await {
                Ok(result) => result.map_err(|error| format!("{error:#}")),
                Err(error) => Err(format!("model catalog task failed: {error}")),
            };
            slot.take();
            *self.outcome.lock().unwrap_or_else(PoisonError::into_inner) = Some(outcome);
        }
        match self
            .outcome
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .as_ref()
        {
            Some(Err(error)) => Err(anyhow!("{error}")),
            _ => Ok(()),
        }
    }
}

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn start_model_catalog_probes(&self) -> Result<()> {
        {
            let mut tasks = self
                .model_catalog_tasks
                .0
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            if tasks.started || tasks.closing {
                return Ok(());
            }
            tasks.started = true;
        }
        let snapshot = self.config_runtime.read()?;
        for (id, account) in &snapshot.config.models.accounts {
            if account.discovery_profile()?.is_some() {
                self.sync_account_models(SyncAccountModelsRequest {
                    operation_id: format!("startup-model-catalog-{id}"),
                    account_id: id.to_string(),
                })
                .await?;
            }
        }
        Ok(())
    }

    /// Starts or joins the same account/query operation. The runtime, not this caller, owns it.
    pub async fn sync_account_models(
        &self,
        request: SyncAccountModelsRequest,
    ) -> Result<SyncAccountModelsReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let id = AccountId::new(&request.account_id)?;
        // Reap terminal retired generations without ever taking responsibility out of the owner.
        let retired = {
            let tasks = self
                .model_catalog_tasks
                .0
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            tasks
                .retained
                .iter()
                .filter(|(_, task)| task.finished())
                .map(|(key, task)| (*key, Arc::clone(task)))
                .collect::<Vec<_>>()
        };
        for (key, task) in retired {
            let outcome = task.wait().await;
            if outcome.is_err()
                && let Some(account) = &task.account
            {
                self.config_runtime
                    .fail_model_catalog_task(account.clone(), task.generation)?;
            }
            let mut tasks = self
                .model_catalog_tasks
                .0
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            tasks.retained.remove(&key);
            tasks.active.retain(|_, active| *active != key);
        }
        let mut tasks = self
            .model_catalog_tasks
            .0
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        if tasks.closing {
            return Err(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::RuntimeStopped,
                "Model catalog owner is closing",
                false,
            )
            .into());
        }
        // Re-read only after taking the same admission gate used by shutdown and replacement.
        let generation = self.config_runtime.model_catalog_generation(&id)?;
        if let Some(existing) = tasks
            .active
            .get(&id)
            .and_then(|key| tasks.retained.get(key))
        {
            if existing.generation == generation && !existing.finished() {
                return Ok(SyncAccountModelsReply {
                    operation_id: existing.operation_id.clone(),
                    account_id: id.to_string(),
                    query_generation: generation,
                    joined_existing: true,
                });
            }
            existing.cancel.cancel();
        }
        tasks.next_id = tasks
            .next_id
            .checked_add(1)
            .ok_or_else(|| anyhow!("catalog task identity exhausted"))?;
        let key = tasks.next_id;
        let runtime = self.clone();
        let account = id.clone();
        let cancel = CancellationToken::new();
        let worker_cancel = cancel.clone();
        let operation_id = request.operation_id.clone();
        let failure_owner = self.config_runtime.clone();
        let failure_account = id.clone();
        let handle = tokio::spawn(async move {
            let outcome = runtime
                .run_catalog_probe(account, generation, operation_id, worker_cancel)
                .await;
            if outcome.is_err() {
                let publication = tokio::task::spawn_blocking(move || {
                    failure_owner.fail_model_catalog_task(failure_account, generation)
                })
                .await;
                if !matches!(publication, Ok(Ok(()))) {
                    tracing::error!("could not publish model catalog task failure");
                }
            }
            outcome
        });
        tasks.retained.insert(
            key,
            Arc::new(ProbeTask {
                account: Some(id.clone()),
                operation_id: request.operation_id.clone(),
                generation,
                cancel,
                join: tokio::sync::Mutex::new(Some(handle)),
                outcome: Mutex::new(None),
            }),
        );
        tasks.active.insert(id.clone(), key);
        Ok(SyncAccountModelsReply {
            operation_id: request.operation_id,
            account_id: id.to_string(),
            query_generation: generation,
            joined_existing: false,
        })
    }

    async fn run_catalog_probe(
        &self,
        account: AccountId,
        generation: u64,
        operation_id: String,
        cancel: CancellationToken,
    ) -> Result<()> {
        let owner = self.config_runtime.clone();
        let probe = tokio::task::spawn_blocking(move || {
            owner.begin_model_catalog_probe(account, generation, operation_id)
        })
        .await??;
        let Some(probe) = probe else {
            return Ok(());
        };
        let result = tokio::select! {
            biased;
            _ = probe.cancellation.cancelled() => return Ok(()),
            _ = cancel.cancelled() => return Ok(()),
            result = probe.query.execute(probe.previous.as_ref()) => result,
        };
        let owner = self.config_runtime.clone();
        // This task is never aborted; blocking atomic commit remains part of its registered join.
        tokio::task::spawn_blocking(move || owner.finish_model_catalog_probe(probe, result))
            .await??;
        Ok(())
    }

    pub(in crate::studio::runtime) async fn stop_model_catalog_probes(&self) -> Result<()> {
        let (close, probes) = {
            let mut tasks = self
                .model_catalog_tasks
                .0
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            tasks.closing = true;
            for task in tasks.retained.values() {
                task.cancel.cancel();
            }
            if tasks.close.is_none() {
                let owner = self.config_runtime.clone();
                // Register the closing commit before releasing admission; no local detached handle.
                let handle = tokio::task::spawn_blocking(move || {
                    owner.close_model_catalogs().map_err(Into::into)
                });
                tasks.close = Some(Arc::new(ProbeTask {
                    account: None,
                    operation_id: "close".into(),
                    generation: 0,
                    cancel: CancellationToken::new(),
                    join: tokio::sync::Mutex::new(Some(handle)),
                    outcome: Mutex::new(None),
                }));
            }
            (
                tasks.close.as_ref().cloned(),
                tasks.retained.values().cloned().collect::<Vec<_>>(),
            )
        };
        let mut failure = None;
        if let Some(close) = close
            && let Err(error) = close.wait().await
        {
            failure = Some(error);
        }
        for task in probes {
            if let Err(error) = task.wait().await {
                failure.get_or_insert(error);
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        let mut tasks = self
            .model_catalog_tasks
            .0
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        tasks.active.clear();
        tasks.retained.clear();
        Ok(())
    }
}
