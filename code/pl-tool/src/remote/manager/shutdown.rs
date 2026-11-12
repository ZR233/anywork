use super::*;
use tokio_util::task::task_tracker::TaskTrackerToken;
impl SshManager {
    pub(super) async fn admit_connection(&self) -> Result<TaskTrackerToken, SshError> {
        let accepting = self.admission.lock().await;
        if !*accepting {
            return Err(SshError::ManagerClosing);
        }
        Ok(self.operations.token())
    }
    pub(super) async fn close_owned_connection(
        &self,
        alias: &str,
        connection: Arc<SshConnection>,
    ) -> Result<(), SshError> {
        let mut result = {
            let mut slot = connection.close.lock().await;
            if let Some(result) = slot.as_ref() {
                result.clone()
            } else {
                let (send, receive) = watch::channel(None);
                *slot = Some(receive.clone());
                let manager = self.clone();
                let alias = alias.to_owned();
                let connection = connection.clone();
                self.operations.spawn(async move {
                    let transport=connection.executor.close();
                    let mut reaped=false;
                    let process=async {
                        let mut process=connection.process.lock().await;
                        match tokio::time::timeout(std::time::Duration::from_secs(2),process.wait()).await {
                            Ok(Ok(status))=>{reaped=true;if status.success(){Ok(())}else{Err(SshError::Protocol(format!("OpenSSH exited with {status}; remote cleanup is unconfirmed"))) }},
                            Ok(Err(error))=>Err(SshError::from(error)),
                            Err(_)=>{
                                // The observer returns at its deadline; this registered owner
                                // retains the child and continues the actual asynchronous reap.
                                let requested=process.start_kill();
                                let status=process.wait().await;
                                if let Err(error)=requested {tracing::debug!(%error,"SSH termination request");}
                                status.map_err(SshError::from)?;
                                reaped=true;
                                Err(SshError::Protocol("local SSH was terminated after cleanup deadline; remote cleanup is unconfirmed".into()))
                            }
                        }
                    };
                    let (transport,process)=tokio::join!(transport,process);
                    let result=transport.map_err(SshError::from).and(process);
                    let mut connections=manager.connections.lock().await;
                    if reaped && connections.get(&alias).is_some_and(|current|Arc::ptr_eq(current,&connection)){connections.remove(&alias);}
                    drop(connections);
                    if !reaped {connection.close.lock().await.take();}
                    send.send_replace(Some(result));
                });
                receive
            }
        };
        tokio::time::timeout(
            std::time::Duration::from_secs(2),
            result.wait_for(Option::is_some),
        )
        .await
        .map_err(|_| {
            SshError::Protocol(
                "SSH cleanup unconfirmed after two seconds; reap owner retained".into(),
            )
        })?
        .map_err(|_| SshError::Disconnected)?
        .as_ref()
        .cloned()
        .unwrap_or(Err(SshError::Disconnected))
    }
    pub async fn shutdown(&self) -> Result<(), SshError> {
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(2);
        {
            let mut admitted = self.admission.lock().await;
            *admitted = false;
            self.operations.close();
        }
        self.closing.cancel();
        for intent in self
            .desired_connections
            .write()
            .await
            .drain()
            .map(|(_, intent)| intent)
        {
            intent.cancelled.cancel();
        }
        let cursors = std::mem::take(&mut *self.directories.lock().await);
        for cursor in cursors.into_values() {
            cursor.stop.cancel();
            cursor.reader.lock().await.reader.take();
        }
        let connections = self
            .connections
            .lock()
            .await
            .iter()
            .map(|(alias, connection)| (alias.clone(), connection.clone()))
            .collect::<Vec<_>>();
        use futures::StreamExt;
        let mut closing = connections
            .into_iter()
            .map(|(alias, connection)| async move {
                self.close_owned_connection(&alias, connection).await
            })
            .collect::<futures::stream::FuturesUnordered<_>>();
        let mut failure = None;
        while let Some(result) = closing.next().await {
            if let Err(error) = result {
                failure.get_or_insert(error);
            }
        }
        if tokio::time::timeout_at(deadline, self.operations.wait())
            .await
            .is_err()
        {
            failure.get_or_insert_with(|| {
                SshError::Protocol("SSH tasks remain owned after cleanup deadline".into())
            });
        }
        failure.map_or(Ok(()), Err)
    }
}
