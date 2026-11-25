//! Model catalog changes feed the product resource stream through one managed observer.

use std::sync::{Arc, Mutex, PoisonError};

use anyhow::Result;
use tokio::sync::broadcast::error::RecvError;

use super::StudioRuntime;
use super::observation_lifecycle::{
    ObservationCloseError, ObservationStartError, ObserverTask, RuntimeObserver,
};
use super::settings_api::{model_catalog_snapshot, model_catalog_state};
use crate::{ModelCatalogSnapshot, ProductEventBus};

/// Serialize revision admission and event emission across Settings and catalog observations.
#[derive(Clone, Default)]
pub(super) struct ModelCatalogPublication(Arc<Mutex<Option<u64>>>);

impl ModelCatalogPublication {
    pub(super) fn publish(&self, events: &ProductEventBus, catalog: ModelCatalogSnapshot) {
        let mut revision = self.0.lock().unwrap_or_else(PoisonError::into_inner);
        if revision.is_some_and(|previous| catalog.revision <= previous) {
            return;
        }
        *revision = Some(catalog.revision);
        events.emit_model_catalog_state(model_catalog_state(catalog));
    }
}

impl StudioRuntime {
    pub(super) async fn start_model_refresh(&self) -> Result<()> {
        let config = self.config_runtime.clone();
        let events = self.agent_facility.product_events.clone();
        let publication = self.observations.model_catalog_publication.clone();
        self.observations.start(RuntimeObserver::ModelRefresh, move |cancellation| async move {
            let mut catalogs = config.subscribe_model_catalogs();
            let task_cancel = cancellation.clone();
            let task = tokio::spawn(async move {
                loop {
                    tokio::select! {
                        biased;
                        () = task_cancel.cancelled() => break,
                        received = catalogs.recv() => match received {
                            Ok(()) | Err(RecvError::Lagged(_)) => {},
                            Err(RecvError::Closed) => break,
                        },
                    }
                    let published = config.read_with_catalog().map_err(anyhow::Error::from)
                        .and_then(|(settings, catalog)| model_catalog_snapshot(&settings, &catalog));
                    match published {
                        Ok(catalog) => publication.publish(&events, catalog),
                        Err(error) => tracing::error!(%error, "could not publish model catalog snapshot"),
                    }
                }
            });
            Ok(ObserverTask::new(cancellation, task))
        }).await.map(|_| ()).map_err(|error| ObservationStartError(error).into())
    }

    pub(super) async fn stop_model_refresh(&self) -> Result<()> {
        let report = self
            .observations
            .close(RuntimeObserver::ModelRefresh, None)
            .await;
        if report.is_clean() {
            return Ok(());
        }
        Err(ObservationCloseError(report).into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::StudioProductEventKind;
    use crate::studio::runtime::bot_archive_test_host::BotArchiveTestHost;

    #[tokio::test]
    async fn settings_reload_publishes_each_model_catalog_revision_once() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let host = BotArchiveTestHost::new(temp.path()).await?;
        let runtime = &host.runtime;
        let (settings, initial) = runtime.config_runtime.read_with_catalog()?;
        let mut events = runtime.agent_facility.product_events.subscribe_internal();

        let reloaded = runtime.reload_settings(settings.revision).await?;
        assert!(reloaded.catalog.revision > initial.revision);
        runtime.publish_settings_state()?;
        runtime.publish_settings_state()?;

        let mut revisions = Vec::new();
        loop {
            match events.try_recv() {
                Ok(event) => {
                    if let StudioProductEventKind::ModelCatalogStateChanged(snapshot) = event.kind {
                        revisions.push(snapshot.state.revision());
                    }
                }
                Err(tokio::sync::broadcast::error::TryRecvError::Empty) => break,
                Err(error) => return Err(error.into()),
            }
        }
        assert_eq!(revisions, [reloaded.catalog.revision]);
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
