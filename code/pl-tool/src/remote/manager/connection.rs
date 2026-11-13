use super::*;
use asset::{load_helper, upload_helper};
use ssh::{run_ssh_capture, ssh_command};

impl SshManager {
    pub(super) async fn connect_once(
        &self,
        alias: &str,
        intent: Arc<ConnectionIntent>,
    ) -> Result<(), SshError> {
        self.set_intent_state(alias, &intent, SshConnectionState::Connecting)
            .await;
        let old = self.connections.lock().await.get(alias).cloned();
        if let Some(old) = old
            && let Err(error) = self.close_owned_connection(alias, old.clone()).await
        {
            if self
                .connections
                .lock()
                .await
                .get(alias)
                .is_some_and(|current| Arc::ptr_eq(current, &old))
            {
                return Err(error);
            }
            tracing::warn!(%alias,%error,"previous connection ended with unconfirmed remote cleanup");
        }
        // This registered task retains setup ownership through its bounded cleanup;
        // cancellation does not drop an in-flight OpenSSH child/reap future.
        let connection = match self.create_connection(alias, &intent.cancelled).await {
            Ok(connection) => Arc::new(connection),
            Err(error) => {
                self.set_intent_state(
                    alias,
                    &intent,
                    SshConnectionState::Failed {
                        code: if matches!(error, SshError::AuthenticationFailed(_)) {
                            "sshAuthFailed"
                        } else {
                            "sshConnectionFailed"
                        }
                        .into(),
                        message: error.to_string(),
                    },
                )
                .await;
                return Err(error);
            }
        };
        if self.closing.is_cancelled() || intent.cancelled.is_cancelled() {
            self.close_owned_connection(alias, connection).await?;
            return Err(SshError::Cancelled);
        }
        let desired = self.desired_connections.read().await;
        if self.closing.is_cancelled()
            || intent.cancelled.is_cancelled()
            || !desired
                .get(alias)
                .is_some_and(|current| Arc::ptr_eq(current, &intent))
        {
            drop(desired);
            self.close_owned_connection(alias, connection).await?;
            return Err(SshError::Cancelled);
        }
        self.connections
            .lock()
            .await
            .insert(alias.into(), connection.clone());
        self.ensure_state(alias)
            .await
            .send_replace(SshConnectionState::Ready {
                helper_version: connection
                    .executor
                    .helper_build()
                    .unwrap_or_default()
                    .into(),
                architecture: connection.executor.target_info().arch.clone(),
            });
        self.ready_revisions.send_modify(|revisions| {
            let revision = revisions.entry(alias.into()).or_default();
            *revision = revision.saturating_add(1);
        });
        drop(desired);
        let manager = self.clone();
        let alias = alias.to_owned();
        self.operations.spawn(async move {
            let failure=loop {
                tokio::select! {
                    _=manager.closing.cancelled()=>return,
                    _=connection.executor.closed()=>break "SSH/h2 connection ended".to_owned(),
                    _=tokio::time::sleep(std::time::Duration::from_millis(100))=>{
                        match connection.process.lock().await.try_wait() {
                            Ok(Some(status))=>break format!("OpenSSH exited: {status}"),
                            Err(error)=>break format!("OpenSSH status failed: {error}"),Ok(None)=>{},
                        }
                    }
                }
            };
            let current={
                let desired=manager.desired_connections.read().await;
                let connections=manager.connections.lock().await;
                let current=connections.get(&alias).is_some_and(|current|Arc::ptr_eq(current,&connection));
                if current && desired.get(&alias).is_some_and(|current|Arc::ptr_eq(current,&intent)) && !intent.cancelled.is_cancelled() {
                    manager.ensure_state(&alias).await.send_replace(SshConnectionState::Failed {code:"sshDisconnected".into(),message:failure});
                }
                current
            };
            if current && let Err(error)=manager.close_owned_connection(&alias,connection).await {tracing::warn!(%alias,%error,"SSH cleanup unconfirmed");}
        });
        Ok(())
    }

    async fn create_connection(
        &self,
        alias: &str,
        cancelled: &CancellationToken,
    ) -> Result<SshConnection, SshError> {
        let check = || {
            if self.closing.is_cancelled() {
                Err(SshError::ManagerClosing)
            } else if cancelled.is_cancelled() {
                Err(SshError::Cancelled)
            } else {
                Ok(())
            }
        };
        check()?;
        let profile = self.profile(alias).await?;
        let password = self.server_password(alias).await;
        let platform = run_ssh_capture(
            &profile,
            &self.ssh_config,
            password.as_deref(),
            "uname -s; uname -m",
        )
        .await?;
        let target = RemoteHelperTarget::from_uname(&platform)?;
        let assets = self.helper_assets.clone().ok_or_else(|| {
            SshError::Protocol(format!(
                "helper artifact for {} is unavailable",
                target.triple()
            ))
        })?;
        check()?;
        let helper = load_helper(assets, target).await?;
        check()?;
        let remote_path =
            upload_helper(&profile, &self.ssh_config, password.as_deref(), &helper).await?;
        check()?;
        let mut prepared = ssh_command(&profile, &self.ssh_config, password.as_deref()).await?;
        prepared
            .command
            .command_mut()
            .arg(ssh::posix_remote_command(&format!(
                "exec {remote_path} --stdio"
            )))
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());
        let spawned = pl_remote_helper::process::spawn_background_command(&mut prepared.command)
            .map_err(|error| SshError::Protocol(format!("start SSH transport: {error}")))?;
        let mut process = spawned.process;
        let stdin = spawned
            .stdin
            .ok_or_else(|| SshError::Protocol("SSH stdin missing".into()))?;
        let stdout = spawned
            .stdout
            .ok_or_else(|| SshError::Protocol("SSH stdout missing".into()))?;
        // Continuously drain stderr even during the handshake; startup noise cannot
        // fill the pipe and stall protocol initialization. Only a bounded tail is kept.
        let diagnostic = Arc::new(std::sync::Mutex::new(Vec::new()));
        let stopped = CancellationToken::new();
        if let Some(mut stderr) = spawned.stderr {
            let diagnostic = diagnostic.clone();
            let stop = stopped.clone();
            let closing = self.closing.clone();
            self.operations.spawn(async move {
                use tokio::io::AsyncReadExt;
                let mut bytes=[0;4096];
                loop {
                    let count=tokio::select! { result=stderr.read(&mut bytes)=>result,_=stop.cancelled()=>break,_=closing.cancelled()=>break };
                    match count {Ok(0)|Err(_)=>break,Ok(count)=>{
                        let mut tail=diagnostic.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
                        tail.extend_from_slice(&bytes[..count]);let excess=tail.len().saturating_sub(4096);tail.drain(..excess);
                    }}
                }
            });
        }
        struct StopOnDrop(Option<CancellationToken>);
        impl Drop for StopOnDrop {
            fn drop(&mut self) {
                if let Some(stop) = self.0.take() {
                    stop.cancel();
                }
            }
        }
        let mut stop_guard = StopOnDrop(Some(stopped.clone()));
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(25),
            Executor::remote(tokio::io::join(stdout, stdin)),
        )
        .await;
        let executor = match result {
            Ok(Ok(executor)) => executor,
            result => {
                ssh::terminate_ssh_child(&mut process, alias).await?;
                let tail = String::from_utf8_lossy(
                    &diagnostic
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner),
                )
                .trim()
                .to_owned();
                if ssh::is_ssh_auth_failure(&tail) {
                    return Err(SshError::AuthenticationFailed(ssh::auth_failure(&tail)));
                }
                return Err(match result {
                    Ok(Err(error)) => error.into(),
                    Err(_) => SshError::Protocol("helper handshake timed out".into()),
                    Ok(Ok(_)) => unreachable!(),
                });
            }
        };
        // The registered stderr owner outlives this setup, until this exact connection ends.
        let stop = stopped.clone();
        let watch = executor.clone();
        let closing = self.closing.clone();
        self.operations.spawn(async move {
            tokio::select! {_=watch.closed()=>{},_=closing.cancelled()=>{}};
            stop.cancel();
        });
        stop_guard.0.take();
        Ok(SshConnection {
            profile: Arc::new(profile),
            executor,
            process: Mutex::new(process),
            close: Mutex::new(None),
        })
    }
}
