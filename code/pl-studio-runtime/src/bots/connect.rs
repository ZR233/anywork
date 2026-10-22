use super::config::BotConfigFile;
use super::inbound::{InboundDecision, InboundHost, classify_event};
use super::owner::RuntimeInboundHost;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::http::FeishuHttp;
use super::protocol::im::FeishuIm;
use super::protocol::ws::{FeishuWsSession, WsEndpointDiscovery, WsInbound};
use super::send::SendPlan;
use super::storage::{BotStateStore, SendRecord, SendRecordStatus, SendSegmentFact};
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
    let discovered = discovery.discover(&config.app_id, secret).await?;
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

pub struct ClaimedSend<'a> {
    pub http: &'a FeishuHttp,
    pub token: &'a str,
    pub bot_id: &'a str,
    pub chat_id: &'a str,
    pub operation_id: &'a str,
    pub store: &'a BotStateStore,
    pub plan: SendPlan,
    pub facts: Vec<SendSegmentFact>,
}

pub async fn send_text(
    claimed: ClaimedSend<'_>,
) -> Result<pl_protocol::studio::BotSendResult, FeishuError> {
    let ClaimedSend {
        http,
        token,
        bot_id,
        chat_id,
        operation_id,
        store,
        plan,
        mut facts,
    } = claimed;
    let im = FeishuIm::new(http.clone());
    let mut segments = Vec::new();
    let mut ids = Vec::new();
    let mut unknown = false;
    let mut rejected = false;
    for (index, segment) in plan.segments.iter().enumerate() {
        match im
            .send_text(token, chat_id, segment, &plan.uuids[index])
            .await
        {
            Ok(outcome) => {
                ids.push(outcome.message_id.clone());
                segments.push(pl_protocol::studio::BotSendSegment {
                    index: index as u32,
                    status: pl_protocol::studio::BotSendStatus::Succeeded,
                    platform_message_id: Some(outcome.message_id.clone()),
                    diagnostic: None,
                });
                facts[index].status = SendRecordStatus::Succeeded;
                facts[index].platform_message_id = Some(outcome.message_id.clone());
            }
            Err(error)
                if matches!(
                    error.kind(),
                    FeishuErrorKind::Timeout | FeishuErrorKind::Transport
                ) =>
            {
                unknown = true;
                segments.push(pl_protocol::studio::BotSendSegment {
                    index: index as u32,
                    status: pl_protocol::studio::BotSendStatus::Unknown,
                    platform_message_id: None,
                    diagnostic: Some(error.diagnostic()),
                });
                facts[index].status = SendRecordStatus::Unknown;
                facts[index].diagnostic = Some(error.diagnostic().message);
            }
            Err(error) => {
                rejected = true;
                segments.push(pl_protocol::studio::BotSendSegment {
                    index: index as u32,
                    status: pl_protocol::studio::BotSendStatus::Rejected,
                    platform_message_id: None,
                    diagnostic: Some(error.diagnostic()),
                });
                facts[index].status = SendRecordStatus::Rejected;
                facts[index].diagnostic = Some(error.diagnostic().message);
            }
        }
        persist_send_progress(
            store,
            &SendRecord {
                operation_id: operation_id.to_string(),
                bot_id: bot_id.to_string(),
                chat_id: chat_id.to_string(),
                content_hash: plan.content_hash.clone(),
                status: overall_send_status(unknown, rejected, ids.len(), plan.segments.len()),
                platform_message_ids: ids.clone(),
                segments: facts.clone(),
                facts_complete: true,
            },
        )
        .await?;
        if unknown || rejected {
            break;
        }
    }
    let status = persist_send_progress(
        store,
        &SendRecord {
            operation_id: operation_id.to_string(),
            bot_id: bot_id.to_string(),
            chat_id: chat_id.to_string(),
            content_hash: plan.content_hash.clone(),
            status: overall_send_status(unknown, rejected, ids.len(), plan.segments.len()),
            platform_message_ids: ids,
            segments: facts,
            facts_complete: true,
        },
    )
    .await?;
    Ok(pl_protocol::studio::BotSendResult {
        operation_id: operation_id.to_string(),
        bot_id: bot_id.to_string(),
        chat_id: chat_id.to_string(),
        status: product_send_status(status),
        segments,
        receipt: pl_protocol::studio::StudioCommandReceipt {
            operation_id: operation_id.to_string(),
            disposition: pl_protocol::studio::CommandDisposition::Applied,
            targets: Vec::new(),
            effect: pl_protocol::studio::CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
    })
}

pub(crate) fn replay_send(
    existing: SendRecord,
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
) -> pl_protocol::studio::BotSendResult {
    let facts_complete = existing.facts_complete;
    let status = product_send_status(existing.status);
    pl_protocol::studio::BotSendResult {
        operation_id: operation_id.to_string(),
        bot_id: bot_id.to_string(),
        chat_id: chat_id.to_string(),
        status,
        segments: existing
            .segments
            .into_iter()
            .map(|fact| pl_protocol::studio::BotSendSegment {
                index: fact.index,
                status: product_send_status(fact.status),
                platform_message_id: fact.platform_message_id,
                diagnostic: fact
                    .diagnostic
                    .map(|message| pl_protocol::studio::BotDiagnostic {
                        code: "sendSegment".to_string(),
                        message,
                        retryable: false,
                        platform_code: None,
                        guidance: if facts_complete {
                            None
                        } else {
                            Some("legacySegmentFactsUnproven".to_string())
                        },
                    }),
            })
            .collect(),
        receipt: pl_protocol::studio::StudioCommandReceipt {
            operation_id: operation_id.to_string(),
            disposition: pl_protocol::studio::CommandDisposition::NoChange,
            targets: Vec::new(),
            effect: pl_protocol::studio::CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
    }
}

async fn persist_send_progress(
    store: &BotStateStore,
    record: &SendRecord,
) -> Result<SendRecordStatus, FeishuError> {
    store.save_send(record).await?;
    Ok(record.status)
}

fn overall_send_status(
    unknown: bool,
    rejected: bool,
    succeeded: usize,
    planned_len: usize,
) -> SendRecordStatus {
    if unknown {
        SendRecordStatus::Unknown
    } else if rejected && succeeded == 0 {
        SendRecordStatus::Rejected
    } else if rejected || succeeded != planned_len {
        SendRecordStatus::Partial
    } else {
        SendRecordStatus::Succeeded
    }
}

fn product_send_status(status: SendRecordStatus) -> pl_protocol::studio::BotSendStatus {
    match status {
        SendRecordStatus::Succeeded => pl_protocol::studio::BotSendStatus::Succeeded,
        SendRecordStatus::Partial => pl_protocol::studio::BotSendStatus::Partial,
        SendRecordStatus::Rejected => pl_protocol::studio::BotSendStatus::Rejected,
        SendRecordStatus::Unknown => pl_protocol::studio::BotSendStatus::Unknown,
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
