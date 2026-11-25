//! Account-scoped discovery admission and durable ownership of active/retired probe tasks.

use super::StudioRuntime;
use crate::config::AccountId;
use crate::{SyncAccountModelsReply, SyncAccountModelsRequest};
use anyhow::{Result, anyhow};
use std::sync::{Arc, Mutex, PoisonError};
use tokio_util::sync::CancellationToken;

use super::acp_ops::{RetainedTask, retained_output};
use super::task_registry::RetainedTaskRegistry;

#[derive(Clone, Default)]
pub(super) struct ModelCatalogTasks(Arc<Mutex<Tasks>>);

#[derive(Default)]
struct Tasks {
    started: bool,
    probes: RetainedTaskRegistry<AccountId, CatalogPayload, Result<()>>,
    close: Option<Arc<RetainedTask<Result<()>>>>,
}

#[derive(Clone)]
struct CatalogPayload {
    account: Option<AccountId>,
    operation_id: String,
    generation: u64,
}

async fn wait_probe(task: &RetainedTask<Result<()>>) -> Result<()> {
    retained_output(
        task.join().await,
        |result| result.map_err(|error| format!("{error:#}")),
        |error| format!("model catalog task failed: {error}"),
    )
    .map_err(|error| anyhow!(error))
}

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn start_model_catalog_probes(&self) -> Result<()> {
        {
            let mut tasks = self
                .model_catalog_tasks
                .0
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            if tasks.started || tasks.probes.is_closing() {
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
                .probes
                .finished_ids()
                .into_iter()
                .filter_map(|key| {
                    let payload = tasks.probes.payload(key)?.clone();
                    let task = tasks.probes.task(key)?;
                    Some((key, payload, task))
                })
                .collect::<Vec<_>>()
        };
        for (key, payload, task) in retired {
            let outcome = wait_probe(&task).await;
            if outcome.is_err()
                && let Some(account) = &payload.account
            {
                self.config_runtime
                    .fail_model_catalog_task(account.clone(), payload.generation)?;
            }
            let mut tasks = self
                .model_catalog_tasks
                .0
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            tasks.probes.remove(key);
        }
        let mut tasks = self
            .model_catalog_tasks
            .0
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        if tasks.probes.is_closing() {
            return Err(crate::StudioError::new(
                crate::StudioErrorCode::RuntimeStopped,
                "Model catalog owner is closing",
                false,
            )
            .into());
        }
        // Re-read only after taking the same admission gate used by shutdown and replacement.
        let generation = self.config_runtime.model_catalog_generation(&id)?;
        if let Some(existing) = tasks.probes.get(&id) {
            if existing.generation == generation && !existing.task.finished() {
                return Ok(SyncAccountModelsReply {
                    operation_id: existing.operation_id.clone(),
                    account_id: id.to_string(),
                    query_generation: generation,
                    joined_existing: true,
                });
            }
            existing.cancel.cancel();
        }
        let key = tasks
            .probes
            .allocate_id()
            .ok_or_else(|| anyhow!("catalog task identity exhausted"))?;
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
        tasks.probes.retain(
            key,
            id.clone(),
            CatalogPayload {
                account: Some(id.clone()),
                operation_id: request.operation_id.clone(),
                generation,
            },
            cancel,
            handle,
        );
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
            let probes = tasks.probes.begin_close();
            if tasks.close.is_none() {
                let owner = self.config_runtime.clone();
                // Register the closing commit before releasing admission; no local detached handle.
                let handle = tokio::task::spawn_blocking(move || {
                    owner.close_model_catalogs().map_err(Into::into)
                });
                tasks.close = Some(Arc::new(RetainedTask::running(handle)));
            }
            (tasks.close.as_ref().cloned(), probes)
        };
        let mut failure = None;
        if let Some(close) = close
            && let Err(error) = wait_probe(&close).await
        {
            failure = Some(error);
        }
        for task in probes {
            if let Err(error) = wait_probe(&task).await {
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
        tasks.probes.clear();
        Ok(())
    }
}
