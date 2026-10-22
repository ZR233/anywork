//! Shared peer state. Independent endpoint kinds are counted separately;
//! hang/release uses a watch predicate rather than sleep.

use std::collections::{HashSet, VecDeque};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Result, bail};
use tokio::sync::{Mutex, mpsc, watch};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::types::{
    AckObservation, BOT_OPEN_ID, CallBound, CallKind, ClientConfig, DIRECT_CHAT_ID,
    FeishuLiveStatus, FeishuPeerOptions, FeishuReport, GROUP_CHAT_ID, GroupChat, HistoryMessage,
    OutboundWs, PAIRING_DIRECT_CHAT_ID, PollObservation, RecordedCall, RegistrationBeginOptions,
    RegistrationPollScript, RegistrationTenantBrand, SendDisposition, TRUSTED_USER_OPEN_ID,
    TokenScript, WsDiscoveryScript, WsUpgradeScript,
};
use super::wire::Pbbp2Frame;

pub(crate) struct WsConn {
    pub id: u64,
    pub tx: mpsc::Sender<OutboundWs>,
    /// Exclusive join owner. Never awaited while holding [`Shared`].
    pub join: std::sync::Arc<Mutex<JoinSlot<()>>>,
    pub closed: bool,
}

pub(crate) enum JoinSlot<T> {
    Pending(JoinHandle<T>),
    Joined(Result<(), String>),
}

impl<T> JoinSlot<T> {
    pub fn abort(&self) {
        if let Self::Pending(handle) = self {
            handle.abort();
        }
    }

    pub fn is_joined(&self) -> bool {
        matches!(self, Self::Joined(_))
    }

    /// Await without dropping an unfinished handle. Timeout leaves Pending in place.
    pub async fn join_with_timeout(&mut self, timeout: Duration) -> Result<(), String> {
        match self {
            Self::Joined(result) => result.clone(),
            Self::Pending(handle) => match tokio::time::timeout(timeout, &mut *handle).await {
                Err(_) => Err("join timed out".into()),
                Ok(Ok(_)) => {
                    *self = Self::Joined(Ok(()));
                    Ok(())
                }
                Ok(Err(error)) => {
                    let message = format!("join: {error}");
                    *self = Self::Joined(Err(message.clone()));
                    Err(message)
                }
            },
        }
    }
}

pub(crate) struct Inner {
    pub options: FeishuPeerOptions,
    pub origin: String,
    pub ws_origin: String,
    pub calls: Vec<RecordedCall>,
    pub polls: Vec<PollObservation>,
    pub acks: Vec<AckObservation>,
    pub violations: Vec<String>,
    pub bounds: Vec<CallBound>,
    pub forbidden: HashSet<CallKind>,
    pub registration: RegistrationState,
    pub token: TokenState,
    pub ws: WsRuntime,
    pub im: ImState,
}

pub(crate) struct RegistrationState {
    pub generation: u64,
    pub cancelled: HashSet<u64>,
    pub device_code: Option<String>,
    pub script: VecDeque<RegistrationPollScript>,
    pub hang: HangGate,
    pub begin_hang: HangGate,
    pub begin_options: RegistrationBeginOptions,
    pub tenant_brand: Option<RegistrationTenantBrand>,
    pub poll_in_flight: Arc<AtomicUsize>,
    pub begin_in_flight: Arc<AtomicUsize>,
}

pub(crate) struct TokenState {
    pub script: TokenScript,
    pub calls: usize,
    pub in_flight: usize,
    pub max_in_flight: usize,
    pub hang: HangGate,
}

pub(crate) struct WsRuntime {
    pub discovery: WsDiscoveryScript,
    pub upgrade: WsUpgradeScript,
    pub client_config: ClientConfig,
    pub connections: usize,
    pub active: usize,
    pub pings: usize,
    pub next_id: u64,
    pub sockets: Vec<WsConn>,
}

pub(crate) struct ImState {
    pub groups: Vec<GroupChat>,
    pub history: Vec<HistoryMessage>,
    pub send: VecDeque<SendDisposition>,
    pub send_seq: u64,
    pub hang: HangGate,
    /// Directory response timing only. Independent from the send and token
    /// gates, so suspending the catalog cannot stall token or message paths.
    pub chat_list_hang: HangGate,
}

/// Watch-based hang/release. A generation is released before waiters are
/// notified, so an early `release_*` cannot be lost and concurrent waiters
/// all observe the same predicate.
///
/// `arm` / `release` publish through [`watch::Sender::send_replace`] so the
/// latest `(generation, released)` remains visible even when every HTTP
/// waiter has already dropped. [`Self::clear`] still only flips the local
/// `released` flag and must not notify in-flight waiters of the current
/// generation.
#[derive(Clone)]
pub(crate) struct HangGate {
    generation: u64,
    released: bool,
    tx: watch::Sender<(u64, bool)>,
}

impl HangGate {
    pub fn new() -> Self {
        let (tx, _) = watch::channel((0, true));
        Self {
            generation: 0,
            released: true,
            tx,
        }
    }

    pub fn arm(&mut self) {
        self.generation = self.generation.saturating_add(1);
        self.released = false;
        // Preserve the armed generation with no live receiver. `send` would
        // drop this value and leave a later subscribe on the previous mark.
        self.tx.send_replace((self.generation, false));
    }

    pub fn clear(&mut self) {
        self.released = true;
        // Do not notify the current generation. In-flight hang waiters must
        // be released explicitly so a script change cannot drop a late result.
        // New waiters still snapshot this local `released` flag and return
        // immediately without waiting on the unchanged watch mark.
    }

    pub fn release(&mut self) {
        self.released = true;
        // Preserve the released generation with no live receiver so a later
        // waiter of this generation does not wait for a second release.
        self.tx.send_replace((self.generation, true));
    }

    pub fn waiter(&self) -> HangWaiter {
        HangWaiter {
            generation: self.generation,
            released: self.released,
            rx: self.tx.subscribe(),
        }
    }
}

pub(crate) struct HangWaiter {
    generation: u64,
    released: bool,
    rx: watch::Receiver<(u64, bool)>,
}

impl HangWaiter {
    pub async fn wait(mut self, cancel: &CancellationToken) {
        {
            let (generation, released) = *self.rx.borrow();
            if (generation > self.generation)
                || (generation == self.generation && (released || self.released))
            {
                return;
            }
        }
        loop {
            tokio::select! {
                            () = cancel.cancelled() => return,
                            changed = self.rx.changed() => {
                                if changed.is_err() {
                                    return;
                        }
                                let (generation, released) = *self.rx.borrow();
                                if generation > self.generation || (generation == self.generation && released)
                                {
                                    return;
                    }
                }
            }
        }
    }
}

/// Private owner of one registration begin/poll in-flight count.
///
/// Increment happens in [`Self::enter`]; decrement happens in [`Drop`].
/// The guard is not [`Clone`], so a request cannot duplicate the decrement
/// owner. Relaxed atomics only carry this independent observation count;
/// generation, options freeze, and hang gates stay under the shared mutex.
#[must_use]
pub(crate) struct InFlightGuard {
    count: Arc<AtomicUsize>,
}

impl InFlightGuard {
    pub fn enter(count: &Arc<AtomicUsize>) -> Self {
        count.fetch_add(1, Ordering::Relaxed);
        Self {
            count: Arc::clone(count),
        }
    }

    pub fn current(&self) -> usize {
        self.count.load(Ordering::Relaxed)
    }
}

impl Drop for InFlightGuard {
    fn drop(&mut self) {
        self.count.fetch_sub(1, Ordering::Relaxed);
    }
}

impl Inner {
    pub fn new(options: FeishuPeerOptions, origin: String, ws_origin: String) -> Self {
        Self {
            options,
            origin,
            ws_origin,
            calls: Vec::new(),
            polls: Vec::new(),
            acks: Vec::new(),
            violations: Vec::new(),
            bounds: Vec::new(),
            forbidden: HashSet::new(),
            registration: RegistrationState {
                generation: 0,
                cancelled: HashSet::new(),
                device_code: None,
                script: VecDeque::from([RegistrationPollScript::Pending]),
                hang: HangGate::new(),
                begin_hang: HangGate::new(),
                begin_options: RegistrationBeginOptions::default(),
                tenant_brand: None,
                poll_in_flight: Arc::new(AtomicUsize::new(0)),
                begin_in_flight: Arc::new(AtomicUsize::new(0)),
            },
            token: TokenState {
                script: TokenScript::Success {
                    expire_seconds: 7200,
                },
                calls: 0,
                in_flight: 0,
                max_in_flight: 0,
                hang: HangGate::new(),
            },
            ws: WsRuntime {
                discovery: WsDiscoveryScript::Success,
                upgrade: WsUpgradeScript::Accept,
                client_config: ClientConfig::default(),
                connections: 0,
                active: 0,
                pings: 0,
                next_id: 1,
                sockets: Vec::new(),
            },
            im: ImState {
                groups: vec![GroupChat {
                    chat_id: GROUP_CHAT_ID.to_owned(),
                    name: "fixture-group".into(),
                    member_open_ids: vec![TRUSTED_USER_OPEN_ID.to_owned(), BOT_OPEN_ID.to_owned()],
                    history_allowed: true,
                }],
                history: vec![HistoryMessage {
                    message_id: "om_anywork_fixture_history_1".into(),
                    chat_id: GROUP_CHAT_ID.to_owned(),
                    msg_type: "text".into(),
                    content: serde_json::json!({"text":"fixture history"}).to_string(),
                    create_time_ms: "1710000000000".into(),
                    sender_id: TRUSTED_USER_OPEN_ID.to_owned(),
                    sender_type: "user".into(),
                    sender_id_type: "open_id".into(),
                }],
                send: VecDeque::from([SendDisposition::Succeed]),
                send_seq: 0,
                hang: HangGate::new(),
                chat_list_hang: HangGate::new(),
            },
        }
    }

    pub fn kind_forbidden_or_excess(&self, kind: CallKind) -> Option<String> {
        if self.forbidden.contains(&kind) {
            return Some(format!("forbidden call {kind:?}"));
        }
        let count = self
            .calls
            .iter()
            .filter(|call| call.kind == Some(kind) && call.accepted)
            .count();
        for bound in &self.bounds {
            if bound.kind == kind
                && let Some(max) = bound.max
                && count >= max
            {
                return Some(format!("{kind:?} exceeds max {max}"));
            }
        }
        None
    }

    pub fn record(
        &mut self,
        method: &str,
        path: &str,
        kind: Option<CallKind>,
        accepted: bool,
        diagnostic: Option<String>,
    ) -> RecordedCall {
        let call = RecordedCall {
            method: method.to_owned(),
            path: path.to_owned(),
            kind,
            accepted,
            diagnostic,
            unix_millis: unix_millis(),
            send_body: None,
            assigned_message_id: None,
            uuid: None,
            owned_reject: false,
        };
        self.calls.push(call.clone());
        call
    }

    pub fn report(
        &self,
        listener_joined: bool,
        sockets_joined: bool,
        join_error: Option<String>,
    ) -> FeishuReport {
        let mut unconsumed = Vec::new();
        let mut violations = self.violations.clone();
        for bound in &self.bounds {
            let count = self
                .calls
                .iter()
                .filter(|call| call.kind == Some(bound.kind) && call.accepted)
                .count();
            if count < bound.min {
                unconsumed.push(format!("{:?} consumed {count}/{}", bound.kind, bound.min));
            }
        }
        for call in &self.calls {
            if !call.accepted && !call.owned_reject {
                violations.push(format!(
                    "rejected {} {} {}",
                    call.method,
                    call.path,
                    call.diagnostic.as_deref().unwrap_or("unspecified")
                ));
            }
        }
        let complete = unconsumed.is_empty() && violations.is_empty() && join_error.is_none();
        FeishuReport {
            complete,
            origin: self.origin.clone(),
            calls: self.calls.clone(),
            polls: self.polls.clone(),
            acks: self.acks.clone(),
            violations,
            unconsumed,
            token_calls: self.token.calls,
            token_max_in_flight: self.token.max_in_flight,
            ws_connections: self.ws.connections,
            pings: self.ws.pings,
            listener_joined,
            sockets_joined,
            join_error,
        }
    }

    pub fn live_status(&self) -> FeishuLiveStatus {
        let accepted = self.calls.iter().filter(|call| call.accepted).count();
        FeishuLiveStatus {
            origin: self.origin.clone(),
            ws_origin: self.ws_origin.clone(),
            accepted,
            rejected: self.calls.len() - accepted,
            token_calls: self.token.calls,
            token_in_flight: self.token.in_flight,
            token_max_in_flight: self.token.max_in_flight,
            ws_connections: self.ws.connections,
            ws_active: self.ws.active,
            pings: self.ws.pings,
            acks: self.acks.len(),
            remaining_required: self.bounds.iter().any(|bound| {
                self.calls
                    .iter()
                    .filter(|call| call.kind == Some(bound.kind) && call.accepted)
                    .count()
                    < bound.min
            }),
        }
    }

    pub fn next_send(&mut self) -> SendDisposition {
        self.im.send.pop_front().unwrap_or(SendDisposition::Succeed)
    }

    pub fn next_poll_script(&mut self) -> RegistrationPollScript {
        if self.registration.script.len() > 1 {
            self.registration
                .script
                .pop_front()
                .unwrap_or(RegistrationPollScript::Pending)
        } else {
            self.registration
                .script
                .front()
                .cloned()
                .unwrap_or(RegistrationPollScript::Pending)
        }
    }

    pub fn group(&self, chat_id: &str) -> Option<&GroupChat> {
        self.im.groups.iter().find(|group| group.chat_id == chat_id)
    }

    pub fn is_known_chat(&self, chat_id: &str) -> bool {
        chat_id == DIRECT_CHAT_ID
            || chat_id == PAIRING_DIRECT_CHAT_ID
            || self.group(chat_id).is_some()
    }
}

pub(crate) type Shared = std::sync::Arc<Mutex<Inner>>;

pub(crate) fn unix_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

pub(crate) fn app_id_ok(value: &str) -> bool {
    value.starts_with(super::types::APP_ID_PREFIX)
}

pub(crate) async fn close_sockets(shared: &Shared, cancel: &CancellationToken) {
    cancel.cancel();
    let senders: Vec<_> = {
        let inner = shared.lock().await;
        inner
            .ws
            .sockets
            .iter()
            .map(|conn| conn.tx.clone())
            .collect()
    };
    for tx in senders {
        let _ = tx.try_send(OutboundWs::Close {
            code: 1000,
            reason: "fixture shutdown".into(),
        });
    }
}

pub(crate) async fn record_ack(shared: &Shared, frame: &Pbbp2Frame) {
    let payload = frame.payload.as_deref().unwrap_or(&[]);
    let code = serde_json::from_slice::<serde_json::Value>(payload)
        .ok()
        .and_then(|value| value.get("code").and_then(|code| code.as_i64()))
        .map(|code| code as i32);
    let mut inner = shared.lock().await;
    inner.acks.push(AckObservation {
        message_id: frame
            .header(super::wire::HEADER_MESSAGE_ID)
            .map(str::to_owned),
        code,
        biz_rt: frame.header(super::wire::HEADER_BIZ_RT).map(str::to_owned),
        unix_millis: unix_millis(),
    });
}

pub(crate) async fn note_ping(shared: &Shared) {
    let mut inner = shared.lock().await;
    inner.ws.pings += 1;
}

pub(crate) fn credentials_match(inner: &Inner, app_id: &str, app_secret: &str) -> bool {
    (app_id == inner.options.app_id && app_secret == inner.options.app_secret)
        || (app_id == inner.options.registered_app_id
            && app_secret == inner.options.registered_app_secret)
}

pub(crate) fn bearer_ok(_inner: &Inner, header: Option<&str>) -> bool {
    header.is_some_and(|value| {
        let token = value.strip_prefix("Bearer ").unwrap_or(value);
        token == super::types::TENANT_ACCESS_TOKEN
    })
}

pub(crate) async fn push_outbound(shared: &Shared, outbound: OutboundWs) -> Result<()> {
    let senders: Vec<_> = {
        let inner = shared.lock().await;
        if inner.ws.sockets.is_empty() {
            bail!("no active Feishu websocket");
        }
        inner
            .ws
            .sockets
            .iter()
            .filter(|conn| !conn.closed)
            .map(|conn| conn.tx.clone())
            .collect()
    };
    let mut any = false;
    for tx in senders {
        if tx.try_send(outbound.clone()).is_ok() {
            any = true;
        }
    }
    if any {
        Ok(())
    } else {
        bail!("no live Feishu websocket accepted outbound")
    }
}

pub(crate) async fn retire_socket(shared: &Shared, id: u64) {
    let mut inner = shared.lock().await;
    if let Some(conn) = inner.ws.sockets.iter_mut().find(|conn| conn.id == id) {
        conn.closed = true;
    }
    inner.ws.active = inner.ws.sockets.iter().filter(|conn| !conn.closed).count();
}

pub(crate) async fn join_sockets_in_place(shared: &Shared) -> Result<()> {
    let owners: Vec<(u64, std::sync::Arc<Mutex<JoinSlot<()>>>)> = {
        let inner = shared.lock().await;
        inner
            .ws
            .sockets
            .iter()
            .map(|conn| (conn.id, conn.join.clone()))
            .collect()
    };
    let mut failed = Vec::new();
    let mut joined_ids = Vec::new();
    for (id, owner) in owners {
        let result = {
            let mut slot = owner.lock().await;
            slot.join_with_timeout(Duration::from_secs(5)).await
        };
        if let Err(error) = result {
            failed.push(format!("socket {id}: {error}"));
        } else {
            joined_ids.push(id);
        }
    }
    if !joined_ids.is_empty() {
        let mut inner = shared.lock().await;
        inner
            .ws
            .sockets
            .retain(|conn| !(conn.closed && joined_ids.contains(&conn.id)));
        inner.ws.active = inner.ws.sockets.iter().filter(|conn| !conn.closed).count();
    }
    if failed.is_empty() {
        Ok(())
    } else {
        bail!(failed.join("; "))
    }
}
