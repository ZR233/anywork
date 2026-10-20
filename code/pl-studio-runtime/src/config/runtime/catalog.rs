use super::*;
use crate::config::model_catalog::{CatalogProbe, SuccessCache};
use pl_protocol::studio::{StudioModelCatalogError, StudioModelCatalogSource};

impl ConfigRuntime {
    pub(crate) fn subscribe_model_catalogs(
        &self,
    ) -> tokio::sync::broadcast::Receiver<CatalogChange> {
        self.catalog_updates.subscribe()
    }

    /// Called on a blocking worker. No network or asynchronous lock is held here.
    pub(crate) fn begin_model_catalog_probe(
        &self,
        account_id: AccountId,
    ) -> ConfigRuntimeResult<Option<CatalogProbe>> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        if state.closing {
            return Ok(None);
        }
        let account = state
            .desired
            .models
            .accounts
            .get(&account_id)
            .ok_or_else(|| {
                PureError::ConfigError("model catalog account no longer exists".into())
            })?;
        if account.discovery_profile()?.is_none() {
            return Ok(None);
        }
        let query = match pl_model::protocol::discovery::ModelCatalogQuery::for_account(account) {
            Ok(query) => query,
            Err(error) => {
                let error = model_catalog::query_error(error)?;
                if let Some(observation) = state.observations.get_mut(&account_id) {
                    observation.status.error = Some(error);
                    observation.status.checked_at = Some(unix_seconds());
                }
                self.publish_catalog_locked(&mut state, Vec::new());
                return Ok(None);
            }
        };
        let observation = state
            .observations
            .get_mut(&account_id)
            .ok_or_else(|| PureError::ConfigError("model observation is missing".into()))?;
        if observation.status.probing {
            return Ok(None);
        }
        observation.status.probing = true;
        observation.status.error = None;
        let probe = CatalogProbe {
            account: account_id,
            generation: observation.generation,
            // 迁移来的历史快照没有记录厂商协议：在完整响应重新验证前，它既不继承旧声明
            // 也不参与条件请求，因此不交给解码器。
            previous: observation
                .cache
                .as_ref()
                .filter(|cache| cache.is_verified())
                .map(
                    |cache| pl_model::protocol::discovery::ModelCatalogQueryCache {
                        identity: query.identity().to_owned(),
                        etag: cache.query_etag().map(str::to_owned),
                        models: cache.models.clone(),
                    },
                ),
            query,
            cancellation: observation.cancellation.child_token(),
        };
        self.publish_catalog_locked(&mut state, Vec::new());
        Ok(Some(probe))
    }

    /// Atomic file replacement precedes publication. The command lock is also the closing gate.
    /// A spawned blocking commit must always be joined, never aborted/detached.
    pub(crate) fn finish_model_catalog_probe(
        &self,
        probe: CatalogProbe,
        result: std::result::Result<
            pl_model::protocol::discovery::ModelCatalogQueryResult,
            pl_model::protocol::discovery::ModelCatalogQueryError,
        >,
    ) -> ConfigRuntimeResult<()> {
        use pl_model::protocol::discovery::ModelCatalogQueryResult;
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let state = self.state.read().map_err(|_| config_runtime_poisoned())?;
        if state.closing || probe.cancellation.is_cancelled() {
            return Ok(());
        }
        let Some(old) = state.observations.get(&probe.account).cloned() else {
            return Ok(());
        };
        if old.generation != probe.generation
            || old.identity.as_deref() != Some(probe.query.identity())
        {
            return Ok(());
        }
        let cache = match result {
            Ok(ModelCatalogQueryResult::Updated {
                identity,
                etag,
                mut models,
            }) => {
                if identity != probe.query.identity() {
                    return Ok(());
                }
                let minimum = state
                    .observations
                    .values()
                    .filter_map(|observation| observation.cache.as_ref())
                    .flat_map(|cache| &cache.models)
                    .filter_map(|model| model.observation.as_ref())
                    .map(pl_model::model::ModelObservation::latest_order)
                    .max()
                    .unwrap_or(0);
                match model_catalog::next_observation_order(self.store.paths(), minimum) {
                    Ok(order) => {
                        for model in &mut models {
                            if let Some(observation) = &mut model.observation {
                                observation.commit(order);
                            }
                        }
                        Ok(SuccessCache::new(
                            &probe.account,
                            &identity,
                            etag,
                            models,
                            unix_seconds(),
                        ))
                    }
                    Err(_) => Err(StudioModelCatalogError::CacheWrite),
                }
            }
            Ok(ModelCatalogQueryResult::NotModified { identity, etag }) => {
                if identity != probe.query.identity() {
                    return Ok(());
                }
                match &old.cache {
                    Some(cache) => Ok(cache.not_modified(etag)),
                    None => Err(StudioModelCatalogError::UnexpectedNotModified),
                }
            }
            Err(error) => Err(model_catalog::query_error(error)?),
        };
        let mut next_observations = state.observations.clone();
        let desired = state.desired.clone();
        let current_accounts = state.snapshot.config.models.accounts.clone();
        drop(state);
        let next = next_observations
            .get_mut(&probe.account)
            .ok_or_else(|| PureError::ConfigError("model observation is missing".into()))?;
        next.status.probing = false;
        next.status.checked_at = Some(unix_seconds());
        let mut affected = Vec::new();
        let mut effective_config = None;
        match cache {
            Ok(cache) => {
                // Validate the complete proposed observation before touching the previous durable file.
                next.cache = Some(cache.clone());
                let accepted = (|| {
                    let effective = effective_runtime_config(&desired, &next_observations)
                        .map_err(|_| StudioModelCatalogError::Protocol)?;
                    effective
                        .validate_declarations()
                        .map_err(|_| StudioModelCatalogError::Protocol)?;
                    cache
                        .persist(self.store.paths(), &probe.account, probe.query.identity())
                        .map_err(|_| StudioModelCatalogError::CacheWrite)?;
                    Ok(effective)
                })();
                match accepted {
                    Ok(effective) => {
                        for (id, account) in &effective.models.accounts {
                            if current_accounts.get(id) != Some(account) {
                                affected.push(id.clone());
                            }
                        }
                        effective_config = Some(effective);
                        let next = next_observations.get_mut(&probe.account).ok_or_else(|| {
                            PureError::ConfigError("model observation is missing".into())
                        })?;
                        next.status.source = StudioModelCatalogSource::Online;
                        next.status.last_success_at = Some(cache.success_at);
                        next.status.checked_at = Some(cache.checked_at);
                        next.status.error = None;
                        next.status.cache_warning = None;
                    }
                    Err(error) => {
                        let next = next_observations.get_mut(&probe.account).ok_or_else(|| {
                            PureError::ConfigError("model observation is missing".into())
                        })?;
                        next.cache = old.cache.clone();
                        next.status.error = Some(error);
                    }
                }
            }
            Err(error) => next.status.error = Some(error),
        }
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        if let Some(config) = effective_config {
            state.snapshot.config = config;
        }
        state.observations = next_observations;
        self.publish_catalog_locked(&mut state, affected);
        Ok(())
    }

    fn publish_catalog_locked(&self, state: &mut RuntimeState, affected: Vec<AccountId>) {
        state.catalog.revision = state.catalog.revision.saturating_add(1);
        state.catalog.updated_at = unix_seconds();
        state.catalog.catalogs = statuses(&state.observations);
        let _ = self.catalog_updates.send(CatalogChange { affected });
    }

    /// Serializes with commit, prevents new publication, and cancels outstanding network futures.
    pub(crate) fn close_model_catalogs(&self) -> ConfigRuntimeResult<()> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        state.closing = true;
        for observation in state.observations.values_mut() {
            observation.cancellation.cancel();
            if observation.status.probing {
                observation.status.probing = false;
                observation.status.error = Some(StudioModelCatalogError::Closing);
            }
        }
        state.catalog.catalogs = statuses(&state.observations);
        Ok(())
    }
}
