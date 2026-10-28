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
    AckObservation, BOT_OPEN_ID, CallBound, CallKind, CardDisposition, CardEntityReport,
    CardObservation, CardOperation, ClientConfig, DIRECT_CHAT_ID, FeishuLiveStatus,
    FeishuPeerOptions, FeishuReport, GROUP_CHAT_ID, GroupChat, HistoryMessage,
    MessageSendObservation, OutboundWs, PAIRING_DIRECT_CHAT_ID, PollObservation, RecordedCall,
    RegistrationBeginOptions, RegistrationPollScript, RegistrationTenantBrand, SendDisposition,
    TRUSTED_USER_OPEN_ID, TokenScript, WsDiscoveryScript, WsUpgradeScript,
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
    pub closing: bool,
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
    pub media: super::media::state::MediaState,
    pub cards: CardState,
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
    pub sends: Vec<MessageSendObservation>,
    pub request_count: usize,
    pub hang: HangGate,
    /// Directory response timing only. Independent from the send and token
    /// gates, so suspending the catalog cannot stall token or message paths.
    pub chat_list_hang: HangGate,
}

/// Optional stop point between the uuid pre-check and the effect commit.
///
/// Acceptance arms it to place two requests on *different* cards at exactly the
/// same interleaving, so the uuid claim is observable instead of depending on
/// timing luck. Release is a persistent watch value, so a release that happens
/// before a request reaches the gate is never lost; the parked counter is RAII so
/// a cancelled request cannot leave it stuck.
#[derive(Clone)]
pub struct CardPrecommitGate {
    released: tokio::sync::watch::Sender<bool>,
    waiting: std::sync::Arc<std::sync::atomic::AtomicUsize>,
}

impl Default for CardPrecommitGate {
    fn default() -> Self {
        Self::new()
    }
}

struct WaitingGuard(std::sync::Arc<std::sync::atomic::AtomicUsize>);

impl WaitingGuard {
    fn new(counter: std::sync::Arc<std::sync::atomic::AtomicUsize>) -> Self {
        counter.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Self(counter)
    }
}

impl Drop for WaitingGuard {
    fn drop(&mut self) {
        self.0.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
    }
}

impl CardPrecommitGate {
    pub(crate) fn new() -> Self {
        let (released, _) = tokio::sync::watch::channel(false);
        Self {
            released,
            waiting: std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0)),
        }
    }

    pub(crate) fn waiting(&self) -> usize {
        self.waiting.load(std::sync::atomic::Ordering::SeqCst)
    }

    pub(crate) fn released(&self) -> bool {
        *self.released.borrow()
    }

    /// Parks until the release value is true; an already released gate never parks.
    pub(crate) async fn park(&self) {
        let mut released = self.released.subscribe();
        let _waiting = WaitingGuard::new(self.waiting.clone());
        if *released.borrow() {
            return;
        }
        // `wait_for` returns immediately when the current value already matches, so
        // a release between the check above and this await is not lost.
        let _ = released.wait_for(|released| *released).await;
    }

    /// Releases every parked and future waiter (sticky).
    pub(crate) fn release_all(&self) {
        let _ = self.released.send_replace(true);
    }

    /// Polls the parked counter; callers bound the wait with their own timeout.
    pub(crate) async fn wait_parked(&self, expected: usize) {
        while self.waiting() < expected {
            tokio::time::sleep(std::time::Duration::from_millis(1)).await;
        }
    }
}

/// Platform-side CardKit state: entities, ordered operations and the scripted
/// answer queue. It is a network counterpart, not another product ledger.
pub(crate) struct CardState {
    pub entities: Vec<CardEntity>,
    pub operations: Vec<CardObservation>,
    pub script: VecDeque<CardDisposition>,
    /// Armed stop point used by acceptance to create a deterministic interleaving.
    pub precommit_gate: Option<CardPrecommitGate>,
    /// Synthetic application scope sample. `false` answers the documented
    /// not-authorized business code instead of applying the operation.
    pub scope_allowed: bool,
    pub next_id: u64,
    pub next_ordinal: usize,
    pub uuids: Vec<CardUuidRecord>,
    pub hang: HangGate,
    /// Per-entity operation locks. A card's read-validate-commit sequence, its
    /// uuid registration and its single IM send identity all run under this lock,
    /// so two concurrent requests for the same card can never both observe an
    /// unsent entity, the same `sequence`, or apply one operation identity twice.
    /// The lock is per card, never the global shared state, so a hung request
    /// cannot stall control or shutdown.
    pub locks: std::collections::HashMap<String, Arc<CardLockEntry>>,
}

/// One created JSON 2.0 card entity held by the peer.
pub(crate) struct CardEntity {
    pub card_id: String,
    pub element_id: String,
    pub data: serde_json::Value,
    pub created_unix_millis: u64,
    pub entity_bytes: usize,
    pub sent_message_id: Option<String>,
    pub sent_uuid: Option<String>,
    /// The complete identity of the one published message, if any. Replay and
    /// conflict decisions compare this identity, never the uuid alone.
    pub sent: Option<CardSendIdentity>,
    pub last_sequence: i64,
    pub content: String,
    pub streaming_closed: bool,
    pub expired: bool,
    pub updates: usize,
    /// Whole-card updates that replaced this same entity in place.
    pub whole_card_updates: usize,
    pub settings_updates: usize,
}

/// One per-card serialization boundary.
///
/// The counters are peer-side observation only: an operator can wait until a
/// request is inside the boundary or queued on it instead of sleeping. They are
/// independent atomics so a guard can release without awaiting.
pub(crate) struct CardLockEntry {
    pub mutex: Arc<Mutex<()>>,
    waiting: AtomicUsize,
    holders: AtomicUsize,
    /// Private cancellation signal for requests queued on this boundary. It is a
    /// peer-observation mechanism only: the product has no access to it, and a
    /// client-side abort is never assumed to end the server handler.
    abort: std::sync::Mutex<CancellationToken>,
}

impl CardLockEntry {
    fn new() -> Self {
        Self {
            mutex: Arc::new(Mutex::new(())),
            waiting: AtomicUsize::new(0),
            holders: AtomicUsize::new(0),
            abort: std::sync::Mutex::new(CancellationToken::new()),
        }
    }

    pub fn begin_wait(&self) {
        self.waiting.fetch_add(1, Ordering::SeqCst);
    }

    /// The waiter acquired the mutex: hand its registration to the holder count.
    pub fn handoff_to_holder(&self) {
        self.waiting.fetch_sub(1, Ordering::SeqCst);
        self.holders.fetch_add(1, Ordering::SeqCst);
    }

    /// The waiter gave up before acquiring the mutex.
    pub fn cancel_wait(&self) {
        self.waiting.fetch_sub(1, Ordering::SeqCst);
    }

    pub fn left(&self) {
        self.holders.fetch_sub(1, Ordering::SeqCst);
    }

    pub fn counters(&self) -> (usize, usize) {
        (
            self.waiting.load(Ordering::SeqCst),
            self.holders.load(Ordering::SeqCst),
        )
    }

    pub fn abort_token(&self) -> CancellationToken {
        self.abort
            .lock()
            .expect("card abort token poisoned")
            .clone()
    }

    /// Cancels requests currently queued on this boundary. A later request
    /// receives a fresh token, so one cancelled generation cannot poison the
    /// next one.
    pub fn cancel_waiters(&self) {
        let mut slot = self.abort.lock().expect("card abort token poisoned");
        let previous = std::mem::replace(&mut *slot, CancellationToken::new());
        previous.cancel();
    }
}

/// Complete identity of the single IM message that published a card entity.
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct CardSendIdentity {
    pub message_id: String,
    pub receive_id: String,
    pub msg_type: String,
    pub content: String,
    pub uuid: String,
}

/// One already-applied CardKit operation identity.
///
/// The platform uses this only to answer a repeated `uuid` with the same
/// payload idempotently and to reject the same `uuid` carrying another payload.
pub(crate) struct CardUuidRecord {
    pub uuid: String,
    pub card_id: String,
    pub operation: CardOperation,
    pub payload: String,
    pub code: i32,
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
            closing: false,
            options,
            origin,
            ws_origin,
            calls: Vec::new(),
            polls: Vec::new(),
            acks: Vec::new(),
            violations: Vec::new(),
            bounds: Vec::new(),
            forbidden: HashSet::new(),
            media: super::media::state::MediaState::new(),
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
                sends: Vec::new(),
                request_count: 0,
                hang: HangGate::new(),
                chat_list_hang: HangGate::new(),
            },
            cards: CardState {
                entities: Vec::new(),
                operations: Vec::new(),
                script: VecDeque::from([CardDisposition::Succeed]),
                precommit_gate: None,
                scope_allowed: true,
                next_id: 0,
                next_ordinal: 1,
                uuids: Vec::new(),
                hang: HangGate::new(),
                locks: std::collections::HashMap::new(),
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
            request_bytes: 0,
            msg_type: None,
            md_text: None,
            card_id: None,
            deduplicated: false,
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
        // Documented per-chat limit: at most five accepted sends in one second.
        // The peer only reports the rule; it never invents pacing for the product.
        let mut sent: Vec<(&str, u64)> = self
            .calls
            .iter()
            .filter(|call| {
                call.accepted
                    && !call.deduplicated
                    && call.kind == Some(CallKind::MessageSend)
                    && call
                        .assigned_message_id
                        .as_ref()
                        .is_some_and(|id| !id.is_empty())
            })
            .filter_map(|call| {
                let chat = call
                    .send_body
                    .as_ref()
                    .and_then(|body| body.get("receive_id"))
                    .and_then(serde_json::Value::as_str)?;
                Some((chat, call.unix_millis))
            })
            .collect();
        sent.sort_by_key(|(_, millis)| *millis);
        for (index, (chat, millis)) in sent.iter().enumerate() {
            let window = sent[index..]
                .iter()
                .take_while(|(_, later)| *later < millis.saturating_add(1_000))
                .filter(|(other, _)| other == chat)
                .count();
            if window > 5 {
                violations.push(format!(
                    "more than five accepted sends to {chat} within one second at {millis}"
                ));
                break;
            }
        }
        let complete = unconsumed.is_empty() && violations.is_empty() && join_error.is_none();
        FeishuReport {
            complete,
            origin: self.origin.clone(),
            calls: self.calls.clone(),
            polls: self.polls.clone(),
            acks: self.acks.clone(),
            uploads: self.media.uploads.clone(),
            resource_downloads: self.media.downloads.clone(),
            message_sends: self.im.sends.clone(),
            resources: {
                let mut resources: Vec<_> = self
                    .media
                    .resources
                    .values()
                    .map(|resource| resource.summary.clone())
                    .collect();
                resources.sort_by(|a, b| a.file_key.cmp(&b.file_key));
                resources
            },
            media_status: self.media.status(),
            cards: self.card_observations(),
            card_entities: self.card_entity_reports(),
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

    /// Next scripted answer for one CardKit request.
    pub fn next_card_disposition(&mut self) -> CardDisposition {
        self.cards
            .script
            .pop_front()
            .unwrap_or(CardDisposition::Succeed)
    }

    /// Ordered platform card facts as observed so far.
    pub fn card_observations(&self) -> Vec<CardObservation> {
        self.cards.operations.clone()
    }

    /// Current platform state of every created card entity.
    pub fn card_entity_reports(&self) -> Vec<CardEntityReport> {
        self.cards
            .entities
            .iter()
            .map(|entity| CardEntityReport {
                card_id: entity.card_id.clone(),
                element_id: entity.element_id.clone(),
                entity_bytes: entity.entity_bytes,
                entity_json: serde_json::to_string(&entity.data).unwrap_or_default(),
                created_unix_millis: entity.created_unix_millis,
                sent_message_id: entity.sent_message_id.clone(),
                sent_uuid: entity.sent_uuid.clone(),
                last_sequence: entity.last_sequence,
                content: entity.content.clone(),
                streaming_closed: entity.streaming_closed,
                expired: entity.expired,
                updates: entity.updates,
                whole_card_updates: entity.whole_card_updates,
                settings_updates: entity.settings_updates,
            })
            .collect()
    }

    /// Marks one existing card entity as past its documented 14-day window.
    pub fn expire_card(&mut self, card_id: &str) -> bool {
        match self
            .cards
            .entities
            .iter_mut()
            .find(|entity| entity.card_id == card_id)
        {
            Some(entity) => {
                entity.expired = true;
                true
            }
            None => false,
        }
    }

    /// Lock identity of one card entity. Callers await this lock outside the
    /// shared state and release it by dropping the guard.
    pub fn card_lock(&mut self, card_id: &str) -> Arc<CardLockEntry> {
        Arc::clone(
            self.cards
                .locks
                .entry(card_id.to_owned())
                .or_insert_with(|| Arc::new(CardLockEntry::new())),
        )
    }

    /// `(waiting, holders)` of one card serialization boundary.
    pub fn card_lock_counters(&self, card_id: &str) -> (usize, usize) {
        self.cards
            .locks
            .get(card_id)
            .map_or((0, 0), |entry| entry.counters())
    }

    /// Cancels every request currently queued on one card boundary.
    pub fn cancel_card_waiters(&self, card_id: &str) {
        if let Some(entry) = self.cards.locks.get(card_id) {
            entry.cancel_waiters();
        }
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
        .and_then(|code| i32::try_from(code).ok());
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
