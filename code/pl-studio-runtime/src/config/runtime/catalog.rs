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
                let publication = self.publish_catalog_locked(&mut state, Vec::new());
                drop(state);
                drop(_command);
                self.notify_projection(publication);
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
        let publication = self.publish_catalog_locked(&mut state, Vec::new());
        drop(state);
        drop(_command);
        self.notify_projection(publication);
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
        let minimum = match &result {
            Ok(ModelCatalogQueryResult::Updated { identity, .. })
            | Ok(ModelCatalogQueryResult::NotModified { identity, .. })
                if identity.as_str() != probe.query.identity() =>
            {
                return Ok(());
            }
            Ok(ModelCatalogQueryResult::Updated { .. }) => state
                .observations
                .values()
                .filter_map(|observation| observation.cache.as_ref())
                .flat_map(|cache| &cache.models)
                .filter_map(|model| model.observation.as_ref())
                .map(pl_model::model::ModelObservation::latest_order)
                .max()
                .unwrap_or(0),
            Ok(ModelCatalogQueryResult::NotModified { .. }) | Err(_) => 0,
        };
        // Freeze this adoption's inputs before sequence/cache IO, while the command guard
        // still serializes durable work with input invalidation and the closing gate.
        let mut next_observations = state.observations.clone();
        let desired = state.desired.clone();
        let current_accounts = state.snapshot.config.models.accounts.clone();
        drop(state);
        let cache = match result {
            Ok(ModelCatalogQueryResult::Updated {
                identity,
                etag,
                mut models,
            }) => match model_catalog::next_observation_order(self.store.paths(), minimum) {
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
            },
            Ok(ModelCatalogQueryResult::NotModified { etag, .. }) => match &old.cache {
                Some(cache) => Ok(cache.not_modified(etag)),
                None => Err(StudioModelCatalogError::UnexpectedNotModified),
            },
            Err(error) => Err(model_catalog::query_error(error)?),
        };
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
        let profiles_config = effective_config.clone();
        if let Some(config) = effective_config {
            state.snapshot.config = config;
        }
        state.observations = next_observations;
        let publication = self.publish_catalog_locked(&mut state, affected);
        drop(state);
        // Model withdrawal/recovery changes whether an otherwise enabled child Profile can run.
        // Publish that availability through the existing Profile owner and generation channel.
        if let Some(config) = profiles_config {
            self.profiles.adopt_scan(self.store.paths(), &config);
        }
        drop(_command);
        self.notify_projection(publication);
        Ok(())
    }

    fn publish_catalog_locked(
        &self,
        state: &mut RuntimeState,
        affected: Vec<AccountId>,
    ) -> ProjectionPublication {
        state.catalog.revision = state.catalog.revision.saturating_add(1);
        state.catalog.updated_at = unix_seconds();
        state.catalog.catalogs = statuses(&state.observations);
        model_projection::observe_source(&mut state.models_status, state.catalog.updated_at);
        let mut publication = self.publish_projection_locked(state);
        publication.catalog_change = Some(CatalogChange { affected });
        publication
    }

    /// Serializes with commit, prevents new publication, and cancels outstanding network futures.
    pub(crate) fn close_model_catalogs(&self) -> ConfigRuntimeResult<()> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| config_runtime_poisoned())?;
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        if state.closing {
            return Ok(());
        }
        state.closing = true;
        let stopped_at = unix_seconds();
        model_projection::stop_source(&mut state.models_status, stopped_at);
        let previous = state.catalog.catalogs.clone();
        let mut cancellations = Vec::with_capacity(state.observations.len());
        for observation in state.observations.values_mut() {
            cancellations.push(observation.cancellation.clone());
            if observation.status.probing {
                observation.status.probing = false;
                observation.status.error = Some(StudioModelCatalogError::Closing);
            }
        }
        state.catalog.catalogs = statuses(&state.observations);
        if previous != state.catalog.catalogs {
            state.catalog.revision = state.catalog.revision.saturating_add(1);
            state.catalog.updated_at = stopped_at;
        }
        let publication = self.publish_projection_locked(&mut state);
        drop(state);
        let profiles = self.profiles.stop_captured();
        drop(_command);
        for cancellation in cancellations {
            cancellation.cancel();
        }
        profiles.notify();
        self.notify_projection(publication);
        Ok(())
    }
}
