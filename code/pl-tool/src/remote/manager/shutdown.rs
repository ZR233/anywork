//! Manager-wide endpoint admission and ordered connection-pool shutdown.

use std::sync::Arc;

use tokio_util::task::task_tracker::TaskTrackerToken;

use super::{RemoteClientError, SshConnectionState, SshManager};

impl SshManager {
    pub(super) async fn connection_lock(&self, server_id: &str) -> Arc<tokio::sync::Mutex<()>> {
        self.connection_locks
            .lock()
            .await
            .entry(server_id.to_string())
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(())))
            .clone()
    }

    pub(super) async fn admit_connection(&self) -> Result<TaskTrackerToken, RemoteClientError> {
        let accepting = self.admission.lock().await;
        if !*accepting {
            return Err(RemoteClientError::ManagerClosing);
        }
        Ok(self.operations.token())
    }

    /// Permanently seals endpoint admission and reclaims every owned physical connection.
    ///
    /// Each endpoint is an independent owner: their closes are issued and observed concurrently so
    /// one hanging or failing endpoint never delays the others. Only an endpoint whose teardown was
    /// confirmed is removed; a failed one stays owned and is retried by a later call.
    ///
    /// Repeated calls reuse retained endpoints after a failure or canceled wait. Dependent remote
    /// tools and services must be stopped before calling this.
    ///
    /// # Errors
    /// Returns an aggregated transport or process-wait failure; every failed endpoint is retained
    /// until it is confirmed closed.
    pub async fn shutdown(&self) -> Result<(), RemoteClientError> {
        {
            let mut accepting = self.admission.lock().await;
            *accepting = false;
            self.operations.close();
        }
        self.closing.cancel();
        self.desired_connections.write().await.clear();
        self.operations.wait().await;

        let endpoints = self
            .endpoints
            .lock()
            .await
            .iter()
            .map(|(server_id, endpoint)| (server_id.clone(), endpoint.clone()))
            .collect::<Vec<_>>();
        // Admission is sealed and all operations are drained above, so no per-server
        // serialization is needed: closing distinct endpoints concurrently is safe, and each
        // endpoint removes itself from the registry only after a confirmed close.
        let outcomes = futures::future::join_all(
            endpoints
                .iter()
                .map(|(_, endpoint)| endpoint.close("manager shutdown")),
        )
        .await;

        let mut failures: Vec<(String, RemoteClientError)> = Vec::new();
        let mut closed = Vec::new();
        for ((server_id, _), outcome) in endpoints.iter().zip(outcomes) {
            match outcome {
                Ok(()) => closed.push(server_id.clone()),
                Err(error) => failures.push((server_id.clone(), error)),
            }
        }
        {
            let mut registered = self.endpoints.lock().await;
            for server_id in closed {
                registered.remove(&server_id);
            }
        }
        for (server_id, error) in &failures {
            // The canonical connection state carries a diagnostic string by design; the error returned
            // to the caller below keeps its typed source.
            self.set_state(
                server_id,
                SshConnectionState::Failed {
                    code: "sshShutdownFailed".to_string(),
                    message: error.to_string(),
                },
            )
            .await;
        }
        if failures.is_empty() {
            Ok(())
        } else {
            let first = failures.first().map(|(_, error)| error.clone());
            let notes = failures
                .iter()
                .map(|(server_id, error)| format!("{server_id}: {error}"))
                .collect::<Vec<_>>();
            Err(RemoteClientError::aggregate(
                "SSH endpoint shutdown did not confirm",
                first,
                &notes,
            ))
        }
    }
}
