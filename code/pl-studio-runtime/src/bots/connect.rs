use super::config::BotConfigFile;
use super::inbound::{InboundDecision, InboundHost, classify_event};
use super::owner::{BotRuntime, ManagedBot, RuntimeInboundHost};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::http::FeishuHttp;
use super::protocol::ws::{FeishuWsSession, WsEndpointDiscovery};
use crate::BotConnectionState;
use crate::studio::unix_seconds;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use tokio::sync::{Mutex, watch};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

pub struct BotConnectionOwner {
    bot_id: String,
    operations: Mutex<()>,
    cancel: Mutex<CancellationToken>,
    task: Mutex<Option<JoinHandle<()>>>,
    state: watch::Sender<BotConnectionState>,
    sealed: AtomicBool,
}

impl BotConnectionOwner {
    pub fn new(bot_id: String) -> Self {
        Self {
            bot_id,
            operations: Mutex::new(()),
            cancel: Mutex::new(CancellationToken::new()),
            task: Mutex::new(None),
            state: watch::channel(BotConnectionState::Disabled).0,
            sealed: AtomicBool::new(false),
        }
    }

    pub fn snapshot(&self) -> BotConnectionState {
        self.state.borrow().clone()
    }

    pub fn subscribe(&self) -> watch::Receiver<BotConnectionState> {
        self.state.subscribe()
    }

    pub async fn close(&self) -> Result<(), FeishuError> {
        let _operation = self.operations.lock().await;
        self.sealed.store(true, Ordering::SeqCst);
        self.join_inner().await?;
        let _ = self.state.send(BotConnectionState::Disabled);
        Ok(())
    }

    pub async fn stop(&self) -> Result<(), FeishuError> {
        let _operation = self.operations.lock().await;
        self.join_inner().await?;
        let _ = self.state.send(BotConnectionState::Disabled);
        Ok(())
    }

    pub async fn start(
        &self,
        http: FeishuHttp,
        config: BotConfigFile,
        secret: String,
        host: Arc<RuntimeInboundHost>,
    ) -> Result<(), FeishuError> {
        let _operation = self.operations.lock().await;
        if self.sealed.load(Ordering::SeqCst) {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot connection is sealed",
                false,
                None,
            ));
        }
        self.join_inner().await?;
        if !host.is_current() {
            return Err(FeishuError::new(
                FeishuErrorKind::Conflict,
                "connection start was superseded before launch",
                true,
                None,
            ));
        }
        let cancel = CancellationToken::new();
        *self.cancel.lock().await = cancel.clone();
        let _ = self.state.send(BotConnectionState::Connecting);
        {
            let mut slot = self.task.lock().await;
            let task = tokio::spawn(run_connection(ConnectionArgs {
                bot_id: self.bot_id.clone(),
                http,
                config,
                secret,
                host,
                cancel,
                published: self.state.clone(),
            }));
            *slot = Some(task);
        }
        Ok(())
    }

    async fn join_inner(&self) -> Result<(), FeishuError> {
        self.cancel.lock().await.cancel();
        let mut slot = self.task.lock().await;
        if slot.is_none() {
            return Ok(());
        }
        let joined = super::join_owned_task(&mut slot).await;
        drop(slot);
        *self.cancel.lock().await = CancellationToken::new();
        joined.map_err(|_| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot connection join failed",
                true,
                None,
            )
        })
    }
}

struct ConnectionArgs {
    bot_id: String,
    http: FeishuHttp,
    config: BotConfigFile,
    secret: String,
    host: Arc<RuntimeInboundHost>,
    cancel: CancellationToken,
    published: watch::Sender<BotConnectionState>,
}

async fn run_connection(args: ConnectionArgs) {
    let ConnectionArgs {
        bot_id,
        http,
        config,
        secret,
        host,
        cancel,
        published,
    } = args;
    let discovery = WsEndpointDiscovery::new(http.clone());
    let mut attempt = 0u32;
    loop {
        if cancel.is_cancelled() || !host.is_current() {
            return;
        }
        let _ = published.send(if attempt == 0 {
            BotConnectionState::Connecting
        } else {
            BotConnectionState::Reconnecting {
                next_attempt_at: Some(unix_seconds()),
                attempt,
            }
        });
        match connect_once(&ConnectionOnce {
            bot_id: &bot_id,
            discovery: &discovery,
            config: &config,
            secret: &secret,
            host: host.as_ref(),
            cancel: &cancel,
            published: &published,
        })
        .await
        {
            Ok(None) => {
                if cancel.is_cancelled() || !host.is_current() {
                    return;
                }
                attempt = attempt.saturating_add(1);
                let wait = reconnect_wait(attempt, None);
                let _ = published.send(BotConnectionState::Reconnecting {
                    next_attempt_at: Some(unix_seconds().saturating_add(wait.as_secs() as i64)),
                    attempt,
                });
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(wait) => {}
                }
            }
            Ok(Some(config)) => {
                if cancel.is_cancelled() || !host.is_current() {
                    return;
                }
                attempt = attempt.saturating_add(1);
                if config.reconnect_count >= 0 && attempt as i32 > config.reconnect_count {
                    let _ = published.send(BotConnectionState::Failed {
                        code: "reconnectLimit".to_string(),
                        message: "bot reconnect limit reached".to_string(),
                        retryable: true,
                        platform_code: None,
                    });
                    return;
                }
                let wait = reconnect_wait(attempt, Some(&config));
                let _ = published.send(BotConnectionState::Reconnecting {
                    next_attempt_at: Some(unix_seconds().saturating_add(wait.as_secs() as i64)),
                    attempt,
                });
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(wait) => {}
                }
            }
            Err(error) if error.retryable() && !cancel.is_cancelled() => {
                if !host.is_current() {
                    return;
                }
                tracing::warn!(bot_id = %bot_id, "bot connection retrying");
                attempt = attempt.saturating_add(1);
                let wait = Duration::from_secs(u64::from(attempt.min(30)));
                let _ = published.send(BotConnectionState::Reconnecting {
                    next_attempt_at: Some(unix_seconds().saturating_add(wait.as_secs() as i64)),
                    attempt,
                });
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(wait) => {}
                }
            }
            Err(error) => {
                if !host.is_current() {
                    return;
                }
                let diagnostic = error.diagnostic();
                let _ = published.send(BotConnectionState::Failed {
                    code: diagnostic.code,
                    message: diagnostic.message,
                    retryable: diagnostic.retryable,
                    platform_code: diagnostic.platform_code,
                });
                return;
            }
        }
    }
}

struct ConnectionOnce<'a> {
    bot_id: &'a str,
    discovery: &'a WsEndpointDiscovery,
    config: &'a BotConfigFile,
    secret: &'a str,
    host: &'a RuntimeInboundHost,
    cancel: &'a CancellationToken,
    published: &'a watch::Sender<BotConnectionState>,
}

async fn connect_once(
    args: &ConnectionOnce<'_>,
) -> Result<Option<super::protocol::ws::ConnectConfig>, FeishuError> {
    let ConnectionOnce {
        bot_id,
        discovery,
        config,
        secret,
        host,
        cancel,
        published,
    } = args;
    let bot_open_id = host.runtime.prefetch_bot_open_id(host, config).await?;
    if cancel.is_cancelled() || !host.is_current() {
        return Ok(None);
    }
    let discovered = discovery.discover(&config.feishu().app_id, secret).await?;
    if cancel.is_cancelled() || !host.is_current() {
        return Ok(None);
    }
    let mut session = FeishuWsSession::connect(discovered, cancel).await?;
    if !host.is_current() {
        session.close().await;
        return Ok(None);
    }
    let _ = published.send(BotConnectionState::Connected);
    let mut ping = tokio::time::interval(session.config.ping_interval);
    ping.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut ping_interval = session.config.ping_interval;
    loop {
        if !host.is_current() {
            session.close().await;
            return Ok(None);
        }
        tokio::select! {
            _ = cancel.cancelled() => {
                session.close().await;
                return Ok(None);
            }
            _ = ping.tick() => {
                session.send_ping().await?;
            }
            inbound = session.next_event(cancel) => {
                match inbound? {
                    None => {
                        let config = session.config.clone();
                        session.close().await;
                        return Ok(Some(config));
                    }
                    Some(event) => {
                        let decision = classify_event(config, &event.payload, Some(bot_open_id.as_str()));
                        let ack_ok = match decision {
                            InboundDecision::Ignore => true,
                            other => host.admit(bot_id, other).await.is_ok(),
                        };
                        session.send_ack(&event.frame, ack_ok).await?;
                    }
                }
            }
        }
        if ping_interval != session.config.ping_interval {
            ping = tokio::time::interval(session.config.ping_interval);
            ping.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            ping_interval = session.config.ping_interval;
        }
    }
}

fn reconnect_wait(attempt: u32, config: Option<&super::protocol::ws::ConnectConfig>) -> Duration {
    let base = config
        .map(|item| item.reconnect_interval)
        .unwrap_or(Duration::from_secs(u64::from(attempt.min(30))));
    let nonce = config
        .map(|item| item.reconnect_nonce)
        .unwrap_or(Duration::from_secs(1));
    base.saturating_add(Duration::from_millis(
        ((attempt as u64).saturating_mul(37)) % nonce.as_millis().max(1) as u64,
    ))
}

impl BotRuntime {
    pub(crate) async fn start_connection(
        &self,
        managed: &Arc<ManagedBot>,
        config: BotConfigFile,
        secret: String,
    ) -> Result<(), FeishuError> {
        let expected = {
            let _admission = managed.admission.lock().await;
            self.reject_closed_admission(managed)?;
            let current = managed.config.lock().await.clone();
            if current.config_revision != config.config_revision
                || current.feishu().app_id != config.feishu().app_id
                || current.workspace_id != config.workspace_id
                || current.enabled != config.enabled
                || current.tools_enabled != config.tools_enabled
                || current.feishu().trusted_open_ids != config.feishu().trusted_open_ids
                || current.feishu().trusted_chat_ids != config.feishu().trusted_chat_ids
                || current.name != config.name
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "connection start was superseded by a newer bot config",
                    true,
                    None,
                ));
            }
            if !current.enabled {
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "bot is disabled",
                    true,
                    None,
                ));
            }
            managed.generation.fetch_add(1, Ordering::AcqRel) + 1
        };
        let host = Arc::new(RuntimeInboundHost {
            runtime: self.clone(),
            current: managed.generation.clone(),
            expected,
        });
        if !host.is_current() {
            return Err(FeishuError::new(
                FeishuErrorKind::Conflict,
                "connection start was superseded before launch",
                true,
                None,
            ));
        }
        managed
            .connection
            .start(self.inner.http.clone(), config, secret, host)
            .await?;
        // 先取标量再 await：不把 config guard 持到入站恢复的 DB 操作之后。
        let bot_id = managed.config.lock().await.id.clone();
        let _ = self.restore_unfinished_inbound(&bot_id).await;
        Ok(())
    }

    pub(crate) async fn prefetch_bot_open_id(
        &self,
        host: &RuntimeInboundHost,
        config: &BotConfigFile,
    ) -> Result<String, FeishuError> {
        if !host.is_current() {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot identity prefetch was superseded",
                true,
                None,
            ));
        }
        let managed = self.managed(&config.id).await?;
        if let Some((cached_generation, existing)) = managed.bot_open_id.lock().await.clone()
            && cached_generation == host.expected
        {
            return Ok(existing);
        }
        let token = self.token(&managed, config).await?;
        let open_id = super::protocol::im::FeishuIm::new(self.inner.http.clone())
            .bot_open_id(&token)
            .await?;
        if !host.is_current() {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot identity prefetch was superseded",
                true,
                None,
            ));
        }
        let mut cache = managed.bot_open_id.lock().await;
        *cache = Some((host.expected, open_id.clone()));
        Ok(open_id)
    }

    pub(crate) async fn token(
        &self,
        managed: &ManagedBot,
        config: &BotConfigFile,
    ) -> Result<String, FeishuError> {
        self.inner
            .http
            .policy()
            .require_synthetic_app(&config.feishu().app_id)?;
        if managed
            .token
            .identity_matches(&config.feishu().app_id)
            .await
        {
            return managed.token.access_token().await;
        }
        let owner = self.ensure_record(&config.id).await?;
        owner.read_selected_secret(config).await?;
        managed.token.access_token().await
    }
}

pub(crate) struct WatchSlot {
    cancel: CancellationToken,
    handle: Option<JoinHandle<()>>,
}

impl WatchSlot {
    pub(super) fn new() -> Self {
        Self {
            cancel: CancellationToken::new(),
            handle: None,
        }
    }

    async fn join(&mut self) -> Result<(), FeishuError> {
        self.cancel.cancel();
        super::join_owned_task(&mut self.handle).await.map_err(|_| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot connection watch join failed",
                true,
                None,
            )
        })
    }
}

impl BotRuntime {
    pub(crate) async fn spawn_connection_watch(&self, managed: &Arc<ManagedBot>) {
        if self.management_sealed() {
            return;
        }
        let bot_id = managed.config.lock().await.id.clone();
        let slot = {
            let records = self.inner.bots.lock().await;
            let Some(record) = records.get(&bot_id) else {
                return;
            };
            record.watch.clone()
        };
        let mut guard = slot.lock().await;
        if self.management_sealed() {
            return;
        }
        if let Err(error) = guard.join().await {
            tracing::warn!(bot_id, %error, "previous bot connection watch join failed");
        }
        if self.management_sealed() {
            return;
        }
        guard.cancel = CancellationToken::new();
        let cancel = guard.cancel.clone();
        let mut rx = managed.connection.subscribe();
        let runtime = self.clone();
        runtime.request_publish();
        let handle = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    changed = rx.changed() => {
                        if changed.is_err() {
                            return;
                        }
                        runtime.request_publish();
                    }
                }
            }
        });
        if self.management_sealed() {
            guard.cancel.cancel();
            guard.handle = Some(handle);
            let _ = guard.join().await;
            return;
        }
        guard.handle = Some(handle);
    }

    pub(crate) async fn close_connection_watches(&self) -> Result<(), FeishuError> {
        let records = self.inner.bots.lock().await;
        let slots = records
            .values()
            .map(|record| record.watch.clone())
            .collect::<Vec<_>>();
        drop(records);
        for slot in slots {
            let mut guard = slot.lock().await;
            if let Err(error) = guard.join().await {
                // 及时上报已观察错误：不再 await 其他 slot，剩余句柄保持登记可重试。
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("bot connection watch join failed: {error}"),
                    true,
                    None,
                ));
            }
        }
        Ok(())
    }
}
