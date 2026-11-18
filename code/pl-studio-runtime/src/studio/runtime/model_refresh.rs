//! Model catalog changes feed the existing product directory and resource revision stream.
use super::{
    StudioRuntime,
    background_task::{self, BackgroundTask},
};
use anyhow::Result;

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn start_model_refresh(&self) {
        let mut slot = self.settings_refresh.lock().await;
        if slot.as_ref().is_some_and(|task| !task.is_finished()) {
            return;
        }
        let mut catalogs = self.config_runtime.subscribe_model_catalogs();
        let runtime = self.clone();
        *slot = Some(BackgroundTask::new(tokio::spawn(async move {
            loop {
                match catalogs.recv().await {
                    Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                        if let Err(error) = runtime.publish_model_catalog_state() {
                            tracing::error!(%error, "could not publish model catalog snapshot");
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
            }
        })));
    }

    pub(in crate::studio::runtime) async fn stop_model_refresh(&self) -> Result<()> {
        background_task::stop(&self.settings_refresh)
            .await
            .map_err(anyhow::Error::new)
    }
}
