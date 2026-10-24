use super::config::BotConfigFile;
use super::inbound::{InboundDecision, InboundHost, classify_event};
use super::owner::RuntimeInboundHost;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::http::FeishuHttp;
use super::protocol::ws::{FeishuWsSession, WsEndpointDiscovery, WsInbound};
use crate::studio::unix_seconds;
use pl_protocol::studio::BotConnectionState;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;
use tokio::sync::{Mutex, watch};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

pub struct BotConnectionOwner {
    bot_id: String,
    generation: AtomicU64,
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
            generation: AtomicU64::new(0),
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
    ) -> Result<u64, FeishuError> {
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
        let _owner_generation = self.generation.fetch_add(1, Ordering::AcqRel) + 1;
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
        Ok(_owner_generation)
    }

    async fn join_inner(&self) -> Result<(), FeishuError> {
        self.cancel.lock().await.cancel();
        let mut slot = self.task.lock().await;
        let Some(task) = slot.as_mut() else {
            return Ok(());
        };
        let joined = Pin::new(task).await;
        *slot = None;
        drop(slot);
        *self.cancel.lock().await = CancellationToken::new();
        match joined {
            Ok(()) => Ok(()),
            Err(error) if error.is_cancelled() => Ok(()),
            Err(_) => Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot connection join failed",
                true,
                None,
            )),
        }
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
                    Some(WsInbound::Event(event)) => {
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
