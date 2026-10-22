//! Manager-wide connection admission and ordered transport shutdown.
use super::{RemoteClientError, SshConnection, SshConnectionState, SshManager};
use std::sync::Arc;
use tokio_util::task::task_tracker::TaskTrackerToken;

impl SshManager {
    pub(super) async fn close_owned_connection(
        &self,
        alias: &str,
        connection: Arc<SshConnection>,
    ) -> Result<(), RemoteClientError> {
        // Register even an unpublished attachment before cleanup. Cancellation or a failure
        // cannot drop the only owner; subsequent shutdown also drains this retirement list.
        {
            let mut retired = self.retired_connections.lock().await;
            if !retired
                .iter()
                .any(|(_, current)| Arc::ptr_eq(current, &connection))
            {
                retired.push((alias.to_owned(), connection.clone()));
            }
        }
        connection.client.begin_close();
        connection.heartbeat.cancel();
        let transport = connection.client.close().await;
        let process = {
            let mut process = connection.process.lock().await;
            super::ssh::terminate_ssh_child(&mut process, alias).await
        };
        let failures = [transport.err(), process.err()]
            .into_iter()
            .flatten()
            .map(|error| error.to_string())
            .collect::<Vec<_>>();
        if !failures.is_empty() {
            return Err(RemoteClientError::Protocol(format!(
                "{alias} cleanup: {}",
                failures.join("; ")
            )));
        }
        {
            let mut connections = self.connections.lock().await;
            if connections
                .get(alias)
                .is_some_and(|current| Arc::ptr_eq(current, &connection))
            {
                connections.remove(alias);
            }
            if connections.len().saturating_mul(4) < connections.capacity() {
                connections.shrink_to_fit();
            }
        }
        {
            let mut retired = self.retired_connections.lock().await;
            retired.retain(|(_, current)| !Arc::ptr_eq(current, &connection));
            if retired.is_empty() {
                retired.shrink_to_fit();
            }
        }
        self.workspaces
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .retain(|(server, _), entry| {
                server != alias
                    || entry
                        .lease
                        .upgrade()
                        .is_some_and(|lease| !lease.is_connection(&connection.client))
            });
        let sender = self.ensure_state(alias).await;
        let desired = self.desired_connections.read().await;
        if !desired.contains_key(alias)
            && !self.connections.lock().await.contains_key(alias)
            && !self
                .retired_connections
                .lock()
                .await
                .iter()
                .any(|(server, _)| server == alias)
        {
            sender.send_replace(SshConnectionState::Disconnected);
        }
        Ok(())
    }

    pub(super) async fn admit_connection(&self) -> Result<TaskTrackerToken, RemoteClientError> {
        let accepting = self.admission.lock().await;
        if !*accepting {
            return Err(RemoteClientError::ManagerClosing);
        }
        // TaskTracker::close does not reject later tracked spawns. This token keeps the
        // tracker nonempty until an admitted caller has registered every derived owner;
        // those owners in turn stay counted while they register their own child tasks.
        Ok(self.operations.token())
    }

    /// Seals admission, cancels connection intents, then joins all published and retiring owners.
    /// Independent failures do not stop other resources from closing; unconfirmed owners stay billed.
    pub async fn shutdown(&self) -> Result<(), RemoteClientError> {
        {
            let mut accepting = self.admission.lock().await;
            *accepting = false;
            self.operations.close();
        }
        self.closing.cancel();
        {
            let mut desired = self.desired_connections.write().await;
            for intent in desired.values() {
                intent.cancelled.cancel();
            }
            desired.clear();
            for connection in self.connections.lock().await.values() {
                connection.client.begin_close();
                connection.heartbeat.cancel();
            }
        }
        self.operations.wait().await;
        let mut connections = self
            .connections
            .lock()
            .await
            .iter()
            .map(|(alias, connection)| (alias.clone(), connection.clone()))
            .collect::<Vec<_>>();
        for (alias, connection) in self.retired_connections.lock().await.iter() {
            if !connections
                .iter()
                .any(|(_, current)| Arc::ptr_eq(current, connection))
            {
                connections.push((alias.clone(), connection.clone()));
            }
        }
        use futures::{StreamExt, stream::FuturesUnordered};
        let mut closing = connections
            .into_iter()
            .map(|(alias, connection)| async move {
                let result = self.close_owned_connection(&alias, connection).await;
                (alias, result)
            })
            .collect::<FuturesUnordered<_>>();
        let mut failures = Vec::new();
        while let Some((alias, result)) = closing.next().await {
            if let Err(error) = result {
                self.set_state(
                    &alias,
                    SshConnectionState::Failed {
                        code: "sshShutdownFailed".into(),
                        message: error.to_string(),
                    },
                )
                .await;
                failures.push(error.to_string());
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(RemoteClientError::Protocol(format!(
                "{} SSH owner(s) did not confirm closure: {}",
                failures.len(),
                failures.join("; ")
            )))
        }
    }
}
