//! One SSH process per active helper attachment. Reconnect uses the original private socket.
use super::*;
use futures::{FutureExt, future::BoxFuture};
use pl_remote_helper::budget::ResourceBudget;

impl SshManager {
    pub(super) fn connect_once<'a>(
        &'a self,
        alias: &'a str,
        intent: Arc<ConnectionIntent>,
    ) -> BoxFuture<'a, Result<(), RemoteClientError>> {
        async move {
            if self.closing.is_cancelled() {
                return Err(RemoteClientError::ManagerClosing);
            }
            if intent.cancelled.is_cancelled() {
                return Err(RemoteClientError::Cancelled);
            }
            let mut previous = self.connections.lock().await.get(alias).cloned();
            if let Some(connection) = previous.clone() {
                if !connection.client.is_disconnected() {
                    return Ok(());
                }
                connection.heartbeat.cancel();
                if connection.client.attachment_expired() || connection.client.is_closing() {
                    // Join an existing close before touching its SSH child: cutting the pipe
                    // first would destroy the cleanup receipt that close is still awaiting.
                    if let Err(error) = self.close_owned_connection(alias, connection.clone()).await
                    {
                        tracing::warn!(%alias, %error, "retiring helper with unconfirmed cleanup");
                    }
                    let mut current = self.connections.lock().await;
                    if current
                        .get(alias)
                        .is_some_and(|current| Arc::ptr_eq(current, &connection))
                    {
                        current.remove(alias);
                    }
                    previous = None;
                } else {
                    let mut process = connection.process.lock().await;
                    ssh::terminate_ssh_child(&mut process, alias).await?;
                }
            }
            if intent.cancelled.is_cancelled() {
                return Err(RemoteClientError::Cancelled);
            }
            let profile = self.profile(alias).await?;
            self.set_intent_state(
                alias,
                &intent,
                if previous.is_some() {
                    SshConnectionState::Reconnecting {
                        attempt: 1,
                        delay_seconds: 0,
                    }
                } else {
                    SshConnectionState::Connecting
                },
            )
            .await;
            let resumed = previous.is_some();
            match self
                .connect_attachment(&profile, previous.as_deref(), &intent.cancelled)
                .await
            {
                Ok((connection, hello)) => {
                    let connection = Arc::new(connection);
                    let sender = self.ensure_state(alias).await;
                    let published = {
                        // Disconnect cancels its intent under the write side of this gate. No
                        // network, process wait or callback runs inside this publication section.
                        let desired = self.desired_connections.read().await;
                        if !self.closing.is_cancelled()
                            && !intent.cancelled.is_cancelled()
                            && !connection.client.is_closing()
                            && desired
                                .get(alias)
                                .is_some_and(|current| Arc::ptr_eq(current, &intent))
                        {
                            self.connections
                                .lock()
                                .await
                                .insert(alias.to_owned(), connection.clone());
                            sender.send_replace(SshConnectionState::Ready {
                                helper_version: hello.helper_version,
                                architecture: hello.architecture,
                            });
                            if !resumed {
                                self.ready_revisions.send_modify(|revisions| {
                                    let revision = revisions.entry(alias.to_owned()).or_default();
                                    *revision = revision.saturating_add(1);
                                });
                            }
                            true
                        } else {
                            false
                        }
                    };
                    if !published {
                        self.close_owned_connection(alias, connection).await?;
                        return Err(RemoteClientError::Cancelled);
                    }
                    self.spawn_heartbeat(
                        alias.to_owned(),
                        connection.client.clone(),
                        connection.heartbeat.clone(),
                    );
                    self.spawn_disconnect_monitor(
                        alias.to_owned(),
                        connection.client.clone(),
                        intent,
                    );
                    Ok(())
                }
                Err(error) => {
                    self.set_intent_state(
                        alias,
                        &intent,
                        SshConnectionState::Failed {
                            code: if matches!(error, RemoteClientError::AuthenticationFailed(_)) {
                                "sshAuthFailed"
                            } else {
                                "sshConnectionFailed"
                            }
                            .into(),
                            message: error.to_string(),
                        },
                    )
                    .await;
                    Err(error)
                }
            }
        }
        .boxed()
    }
    async fn connect_attachment(
        &self,
        profile: &SshServerProfile,
        previous: Option<&SshConnection>,
        cancelled: &CancellationToken,
    ) -> Result<(SshConnection, RemoteHello), RemoteClientError> {
        let password = self.server_password(&profile.alias).await;
        let remote_path = match previous {
            Some(previous) => previous.remote_path.clone(),
            None => {
                let platform = run_ssh_capture(
                    profile,
                    &self.ssh_config,
                    password.as_deref(),
                    "uname -s; uname -m",
                )
                .await?;
                let target = RemoteHelperTarget::from_uname(&platform)?;
                let assets = self.helper_assets.clone().ok_or_else(|| {
                    RemoteClientError::Protocol(format!(
                        "helper artifact for {} is unavailable",
                        target.triple()
                    ))
                })?;
                let helper = load_helper(assets, target).await?;
                if cancelled.is_cancelled() || self.closing.is_cancelled() {
                    return Err(RemoteClientError::Cancelled);
                }
                upload_helper(profile, &self.ssh_config, password.as_deref(), &helper).await?
            }
        };
        if cancelled.is_cancelled() || self.closing.is_cancelled() {
            return Err(RemoteClientError::Cancelled);
        }
        let command = match previous.and_then(|previous| previous.client.session()) {
            Some(session) => format!(
                "exec {remote_path} --attach {}",
                crate::shell::shell_quote_word(&session.socket_path)
            ),
            None => format!("exec {remote_path}"),
        };
        let mut prepared = ssh_command(profile, &self.ssh_config, password.as_deref()).await?;
        prepared
            .command
            .command_mut()
            .arg(ssh::posix_remote_command(&command))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = prepared
            .command
            .spawn()
            .map_err(|e| RemoteClientError::Protocol(format!("start SSH transport: {e}")))?;
        let stdin = child
            .stdin()
            .take()
            .ok_or_else(|| RemoteClientError::Protocol("SSH stdin missing".into()))?;
        let stdout = child
            .stdout()
            .take()
            .ok_or_else(|| RemoteClientError::Protocol("SSH stdout missing".into()))?;
        let handshake = async {
            if let Some(previous) = previous {
                let hello = previous.client.reattach(stdout, stdin).await?;
                Ok::<_, RemoteClientError>((previous.client.clone(), hello))
            } else {
                let budget = self
                    .budget
                    .get_or_try_init(|| async {
                        let policy = self.resource_policy;
                        let allocation = tokio::task::spawn_blocking(move || policy.allocation())
                            .await
                            .map_err(|e| RemoteClientError::Protocol(e.to_string()))??;
                        ResourceBudget::new(allocation).map_err(RemoteClientError::from)
                    })
                    .await?
                    .clone();
                let client =
                    RemoteClient::with_budget(stdout, stdin, budget, self.resource_policy).await?;
                let result = client
                    .request(
                        RemoteRequest::Hello {
                            protocol_version: REMOTE_PROTOCOL_VERSION,
                        },
                        &[],
                    )
                    .await;
                match result {
                    Ok(reply) => match reply.response {
                        RemoteResponse::Hello(hello) => Ok((client, hello)),
                        _ => {
                            client.close().await?;
                            Err(RemoteClientError::Protocol(
                                "invalid helper handshake".into(),
                            ))
                        }
                    },
                    Err(error) => {
                        client.close().await?;
                        Err(error)
                    }
                }
            }
        };
        let result = tokio::time::timeout(std::time::Duration::from_secs(25), handshake)
            .await
            .unwrap_or_else(|_| {
                Err(RemoteClientError::Protocol(
                    "helper handshake timed out".into(),
                ))
            });
        let (client, hello) = match result {
            Ok(result) => result,
            Err(error) => {
                ssh::terminate_ssh_child(&mut child, &profile.alias).await?;
                let diagnostic = ssh::initialization_diagnostic(child.stderr().take()).await?;
                if ssh::is_ssh_auth_failure(&diagnostic) {
                    return Err(RemoteClientError::AuthenticationFailed(ssh::auth_failure(
                        &diagnostic,
                    )));
                }
                return Err(RemoteClientError::Protocol(format!(
                    "helper attachment failed: {error}; {diagnostic}"
                )));
            }
        };
        let execution_environment = match execution_environment_from_hello(&hello) {
            Ok(environment) => environment,
            Err(error) => {
                client.close().await?;
                ssh::terminate_ssh_child(&mut child, &profile.alias).await?;
                return Err(error);
            }
        };
        if let Some(mut stderr) = child.stderr().take() {
            let observer = client.clone();
            let closing = self.closing.clone();
            let alias = profile.alias.clone();
            let generation = client.generation();
            self.operations.spawn(async move {
                use tokio::io::AsyncReadExt;
                let mut retained = Vec::new();
                let mut buffer = [0; 1024];
                let disconnected = observer.wait_disconnected();
                tokio::pin!(disconnected);
                let mut draining = false;
                let deadline = tokio::time::sleep(std::time::Duration::from_secs(2));
                tokio::pin!(deadline);
                loop {
                    tokio::select! {
                        _ = closing.cancelled(), if !draining => { draining = true; deadline.as_mut().reset(tokio::time::Instant::now() + std::time::Duration::from_secs(2)); },
                        _ = &mut disconnected, if !draining => { draining = true; deadline.as_mut().reset(tokio::time::Instant::now() + std::time::Duration::from_secs(2)); },
                        _ = &mut deadline, if draining => break,
                        count = stderr.read(&mut buffer) => match count {
                            Ok(0) | Err(_) => break,
                            Ok(count) => { retained.extend_from_slice(&buffer[..count]); if retained.len() > 4096 { retained.drain(..retained.len()-4096); } }
                        }
                    }
                }
                if !retained.is_empty() { tracing::warn!(%alias, generation, diagnostic = %String::from_utf8_lossy(&retained), "SSH transport stderr tail"); }
            });
        }
        Ok((
            SshConnection {
                profile: Arc::new(profile.clone()),
                client,
                process: Arc::new(Mutex::new(child)),
                heartbeat: CancellationToken::new(),
                execution_environment,
                remote_path,
            },
            hello,
        ))
    }
}
