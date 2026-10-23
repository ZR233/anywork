//! Typed control surface for the isolated Feishu peer.

use anyhow::Result;
use tokio_util::sync::CancellationToken;

use super::state::{Shared, close_sockets, join_sockets_in_place, push_outbound};
use super::types::{
    CallBound, CallKind, CardDisposition, CardEntityReport, CardObservation, ClientConfig,
    FeishuLiveStatus, FeishuReport, GroupChat, HistoryMessage, OutboundWs,
    RegistrationBeginOptions, RegistrationPollScript, RegistrationTenantBrand, SendDisposition,
    SyntheticEvent, TokenScript, WsDiscoveryScript, WsUpgradeScript,
};
use super::wire::{decode_addons, encode_addons, required_addons, validate_required_addons};

/// Operator handle. Cheap to clone; does not own the listener.
#[derive(Clone)]
pub struct FeishuControl {
    pub(crate) shared: Shared,
}

impl FeishuControl {
    /// HTTP origin, e.g. `http://127.0.0.1:43123`.
    pub async fn origin(&self) -> String {
        self.shared.lock().await.origin.clone()
    }

    /// WebSocket origin, e.g. `ws://127.0.0.1:43123`. Same host and port as HTTP.
    pub async fn ws_origin(&self) -> String {
        self.shared.lock().await.ws_origin.clone()
    }

    pub async fn live_status(&self) -> FeishuLiveStatus {
        self.shared.lock().await.live_status()
    }

    pub async fn token_in_flight(&self) -> usize {
        self.shared.lock().await.token.in_flight
    }

    pub async fn poll_count(&self) -> usize {
        self.shared.lock().await.polls.len()
    }

    pub async fn poll_in_flight(&self) -> usize {
        self.shared
            .lock()
            .await
            .registration
            .poll_in_flight
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    pub async fn begin_in_flight(&self) -> usize {
        self.shared
            .lock()
            .await
            .registration
            .begin_in_flight
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    /// gzip+base64url payload the product should attach to the verification URL.
    pub fn required_addons_encoding(&self) -> Result<String> {
        encode_addons(&required_addons())
    }

    /// Decode and require tenant scopes/events. Used to inspect the product's URL.
    pub fn validate_addons_encoding(&self, encoded: &str) -> Result<()> {
        let addons = decode_addons(encoded)?;
        validate_required_addons(&addons)
    }

    pub async fn set_registration_script(&self, steps: Vec<RegistrationPollScript>) {
        let mut inner = self.shared.lock().await;
        let hang = steps
            .iter()
            .any(|step| matches!(step, RegistrationPollScript::Hang));
        inner.registration.script = steps.into();
        if hang {
            inner.registration.hang.arm();
        } else {
            inner.registration.hang.clear();
        }
    }

    /// Replace the next begin response. Already-entered begin requests keep
    /// the snapshot taken at handler entry.
    pub async fn set_registration_begin_options(&self, options: RegistrationBeginOptions) {
        self.shared.lock().await.registration.begin_options = options;
    }

    /// Brand emitted with a later Completed poll. Read at Completed emission,
    /// not frozen onto the poll script. `None` restores historical wire.
    pub async fn set_registration_tenant_brand(&self, brand: Option<RegistrationTenantBrand>) {
        self.shared.lock().await.registration.tenant_brand = brand;
    }

    pub async fn hang_registration(&self) {
        let mut inner = self.shared.lock().await;
        inner.registration.script = vec![RegistrationPollScript::Hang].into();
        inner.registration.hang.arm();
    }

    pub async fn release_registration(&self) {
        self.shared.lock().await.registration.hang.release();
    }

    pub async fn hang_registration_begin(&self) {
        self.shared.lock().await.registration.begin_hang.arm();
    }

    pub async fn release_registration_begin(&self) {
        self.shared.lock().await.registration.begin_hang.release();
    }

    /// Local observation marker only. Scripted poll wire is unchanged, so an
    /// in-flight Completed still returns credentials.
    pub async fn cancel_registration_generation(&self) {
        let mut inner = self.shared.lock().await;
        let generation = inner.registration.generation;
        inner.registration.cancelled.insert(generation);
    }

    pub async fn set_token_script(&self, script: TokenScript) {
        let mut inner = self.shared.lock().await;
        let hang = matches!(script, TokenScript::Hang);
        inner.token.script = script;
        if hang {
            inner.token.hang.arm();
        } else {
            inner.token.hang.clear();
        }
    }

    pub async fn hang_token(&self) {
        let mut inner = self.shared.lock().await;
        inner.token.script = TokenScript::Hang;
        inner.token.hang.arm();
    }

    pub async fn release_token(&self) {
        self.shared.lock().await.token.hang.release();
    }

    pub async fn set_ws_discovery(&self, script: WsDiscoveryScript) {
        self.shared.lock().await.ws.discovery = script;
    }

    pub async fn set_ws_upgrade(&self, script: WsUpgradeScript) {
        self.shared.lock().await.ws.upgrade = script;
    }

    pub async fn set_client_config(&self, config: ClientConfig) {
        self.shared.lock().await.ws.client_config = config;
    }

    pub async fn send_event(&self, event: SyntheticEvent) -> Result<()> {
        push_outbound(&self.shared, OutboundWs::Event(event)).await
    }

    pub async fn send_event_fragments(&self, event: SyntheticEvent, parts: usize) -> Result<()> {
        push_outbound(&self.shared, OutboundWs::EventFragments { event, parts }).await
    }

    pub async fn send_duplicate_event(&self, event: SyntheticEvent) -> Result<()> {
        push_outbound(&self.shared, OutboundWs::DuplicateEvent(event)).await
    }

    pub async fn send_conflict_event(
        &self,
        event: SyntheticEvent,
        other_text: impl Into<String>,
    ) -> Result<()> {
        push_outbound(
            &self.shared,
            OutboundWs::ConflictEvent {
                event,
                other_text: other_text.into(),
            },
        )
        .await
    }

    /// Incomplete `sum > 1` fragment. Same seq/same payload is a retry;
    /// same seq/different payload is a cache-conflict stimulus. ACK is not
    /// expected for incomplete fragments.
    pub async fn send_incomplete_fragment(
        &self,
        event: SyntheticEvent,
        sum: u32,
        seq: u32,
        payload: Vec<u8>,
    ) -> Result<()> {
        push_outbound(
            &self.shared,
            OutboundWs::IncompleteFragment {
                event,
                sum,
                seq,
                payload,
            },
        )
        .await
    }

    pub async fn send_illegal_frame(&self) -> Result<()> {
        push_outbound(&self.shared, OutboundWs::IllegalBytes).await
    }

    pub async fn close_socket(&self, code: u16, reason: impl Into<String>) -> Result<()> {
        push_outbound(
            &self.shared,
            OutboundWs::Close {
                code,
                reason: reason.into(),
            },
        )
        .await
    }

    pub async fn set_groups(&self, groups: Vec<GroupChat>) {
        self.shared.lock().await.im.groups = groups;
    }

    pub async fn set_history(&self, history: Vec<HistoryMessage>) {
        self.shared.lock().await.im.history = history;
    }

    pub async fn set_send_script(&self, steps: Vec<SendDisposition>) {
        let mut inner = self.shared.lock().await;
        let hang = steps
            .iter()
            .any(|step| matches!(step, SendDisposition::Hang));
        inner.im.send = steps.into();
        if hang {
            inner.im.hang.arm();
        } else {
            inner.im.hang.clear();
        }
    }

    /// Scripts the answers of the next CardKit requests (create, element
    /// content, settings) in request order. An exhausted script succeeds.
    pub async fn set_card_script(&self, steps: Vec<CardDisposition>) {
        let mut inner = self.shared.lock().await;
        let hang = steps
            .iter()
            .any(|step| matches!(step, CardDisposition::Hang));
        inner.cards.script = steps.into();
        if hang {
            inner.cards.hang.arm();
        } else {
            inner.cards.hang.clear();
        }
    }

    /// Synthetic application scope sample: `false` answers the documented
    /// not-authorized business code without applying any card operation.
    /// Arms the deterministic pre-commit stop point and returns its handle.
    pub async fn arm_card_precommit_gate(&self) -> super::state::CardPrecommitGate {
        let gate = super::state::CardPrecommitGate::new();
        self.shared.lock().await.cards.precommit_gate = Some(gate.clone());
        gate
    }

    /// Disarms the stop point so no later request parks.
    pub async fn disarm_card_precommit_gate(&self) {
        self.shared.lock().await.cards.precommit_gate = None;
    }

    pub async fn set_card_scope_allowed(&self, allowed: bool) {
        self.shared.lock().await.cards.scope_allowed = allowed;
    }

    /// Marks one existing card entity as past its documented 14-day window.
    /// Returns `false` when no such entity exists.
    pub async fn expire_card(&self, card_id: &str) -> bool {
        self.shared.lock().await.expire_card(card_id)
    }

    /// Ordered CardKit facts observed so far, including rejected attempts.
    pub async fn card_observations(&self) -> Vec<CardObservation> {
        self.shared.lock().await.card_observations()
    }

    /// Current platform state of every card this peer created.
    pub async fn card_entities(&self) -> Vec<CardEntityReport> {
        self.shared.lock().await.card_entity_reports()
    }

    /// Suspends the next CardKit response by queueing a real `Hang` gate into
    /// the same script the other dispositions use, then arming that gate.
    ///
    /// One source of truth: the request that consumes this entry waits on the
    /// armed generation, and [`Self::release_card`] releases exactly that
    /// generation. Independent from the IM send gate.
    pub async fn hang_card(&self) {
        let mut inner = self.shared.lock().await;
        inner.cards.script.push_back(CardDisposition::Hang);
        inner.cards.hang.arm();
    }

    /// Releases the armed CardKit generation. Idempotent.
    pub async fn release_card(&self) {
        self.shared.lock().await.cards.hang.release();
    }

    /// Number of card dispositions still queued. A request that consumed the
    /// `Hang` entry has left the queue even though it is still waiting.
    pub async fn pending_card_script(&self) -> usize {
        self.shared.lock().await.cards.script.len()
    }

    /// `(waiting, holders)` of one card serialization boundary.
    ///
    /// An operator can wait until a request is *inside* the boundary and the
    /// next one is *queued on it*, instead of assuming an arbitrary delay means
    /// that. Peer-side observation only; the product never sees these counters.
    pub async fn card_lock_counters(&self, card_id: &str) -> (usize, usize) {
        self.shared.lock().await.card_lock_counters(card_id)
    }

    /// Cancels the requests currently queued on one card boundary.
    ///
    /// Private environment control: it ends the peer-side handler future that is
    /// waiting for the boundary, which is a different fact from a client abort
    /// (an HTTP client disappearing does not by itself cancel the server task).
    /// A later request gets a fresh generation and proceeds normally.
    pub async fn cancel_card_waiters(&self, card_id: &str) {
        self.shared.lock().await.cancel_card_waiters(card_id);
    }

    pub async fn hang_send(&self) {
        let mut inner = self.shared.lock().await;
        inner.im.send = vec![SendDisposition::Hang].into();
        inner.im.hang.arm();
    }

    pub async fn release_send(&self) {
        self.shared.lock().await.im.hang.release();
    }

    /// Suspend later chat-list responses of this peer. Only the response
    /// timing of accepted directory requests changes; credentials, scopes,
    /// paging and group data stay as configured. Not suspended by default.
    pub async fn hang_chat_list(&self) {
        self.shared.lock().await.im.chat_list_hang.arm();
    }

    /// Release the armed directory generation. Idempotent: a request accepted
    /// before this call returns the configured catalog, while a request
    /// accepted afterwards waits on its own generation instead.
    pub async fn release_chat_list(&self) {
        self.shared.lock().await.im.chat_list_hang.release();
    }

    pub async fn require_calls(&self, bounds: Vec<CallBound>) {
        self.shared.lock().await.bounds = bounds;
    }

    pub async fn forbid(&self, kinds: Vec<CallKind>) {
        self.shared.lock().await.forbidden = kinds.into_iter().collect();
    }

    pub async fn snapshot_report(&self) -> FeishuReport {
        self.shared.lock().await.report(false, false, None)
    }
}

pub(crate) async fn join_sockets(shared: &Shared, cancel: &CancellationToken) -> Result<()> {
    close_sockets(shared, cancel).await;
    join_sockets_in_place(shared).await
}
