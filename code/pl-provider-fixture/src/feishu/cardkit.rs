//! CardKit surfaces of the isolated Feishu peer.
//!
//! One cohesive module owns the card entity lifecycle: creation, cumulative
//! element bodies, settings (stream/close/reopen), the single IM message that
//! publishes a card, the ordered platform observations and the per-card
//! serialization boundary that makes "read, validate, commit" atomic. The IM
//! message and registration surfaces stay in `http`; shared request guards live
//! in `guard`, and the wire shape itself is validated in `card`.

use axum::Json;
use axum::body::{Body, Bytes};
use axum::extract::{Path, State};
use axum::http::HeaderMap;
use axum::response::{IntoResponse, Response};
use serde::Deserialize;
use serde_json::json;

use super::card;
use super::guard::{HttpState, auth_ok, kind_blocked, record_reject};
use super::messages::{SendBody, send_ok_fields};
use super::state::{CardSendIdentity, Shared, unix_millis};
use super::types::{CallKind, CardDisposition, CardObservation, CardOperation, SendDisposition};

/// Official CardKit `create` request: one serialized JSON 2.0 card entity.
#[derive(Deserialize, serde::Serialize)]
pub(crate) struct CardCreateBody {
    #[serde(rename = "type")]
    pub kind: String,
    pub data: String,
}

/// Official CardKit element-content update: the cumulative full body.
#[derive(Deserialize, serde::Serialize)]
pub(crate) struct CardElementBody {
    pub content: String,
    pub sequence: i64,
    pub uuid: Option<String>,
}

/// Official CardKit settings update: a serialized settings object.
#[derive(Deserialize, serde::Serialize)]
pub(crate) struct CardSettingsBody {
    pub settings: String,
    pub sequence: i64,
    pub uuid: Option<String>,
}

const CARD_CREATE_PATH: &str = "/open-apis/cardkit/v1/cards";
const CARD_ELEMENT_PATH: &str =
    "/open-apis/cardkit/v1/cards/{card_id}/elements/{element_id}/content";
const CARD_SETTINGS_PATH: &str = "/open-apis/cardkit/v1/cards/{card_id}/settings";

pub(crate) async fn card_create(
    State(state): State<HttpState>,
    headers: HeaderMap,
    raw: Bytes,
) -> Response {
    let request_bytes = raw.len();
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "POST",
            CARD_CREATE_PATH,
            Some(CallKind::CardCreate),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::CardCreate).await {
        record_reject(
            &state.shared,
            "POST",
            CARD_CREATE_PATH,
            Some(CallKind::CardCreate),
            reason.clone(),
        )
        .await;
        return card_error(99991672, &reason);
    }
    if !card_scope(&state.shared).await {
        record_card(
            &state.shared,
            "POST",
            CARD_CREATE_PATH,
            CallKind::CardCreate,
            card_observation(
                CardOperation::Create,
                "".into(),
                request_bytes,
                false,
                card::CODE_NO_PERMISSION,
            ),
            true,
            Some("synthetic application lacks cardkit:card:write".into()),
        )
        .await;
        return card_error(card::CODE_NO_PERMISSION, "no card permission");
    }
    let body: CardCreateBody = match serde_json::from_slice(&raw) {
        Ok(body) => body,
        Err(error) => {
            record_reject(
                &state.shared,
                "POST",
                CARD_CREATE_PATH,
                Some(CallKind::CardCreate),
                format!("card create body json: {error}"),
            )
            .await;
            return card_error(232001, "card create body must be JSON");
        }
    };
    if body.kind != "card_json" {
        record_reject(
            &state.shared,
            "POST",
            CARD_CREATE_PATH,
            Some(CallKind::CardCreate),
            format!("card create type {} is not card_json", body.kind),
        )
        .await;
        return card_error(232001, "card create type must be card_json");
    }
    let parsed = match card::parse_card_json(&body.data) {
        Ok(parsed) => parsed,
        Err(error) => {
            record_reject(
                &state.shared,
                "POST",
                CARD_CREATE_PATH,
                Some(CallKind::CardCreate),
                format!("card data: {error:#}"),
            )
            .await;
            return card_error(232001, "invalid card data");
        }
    };
    if parsed.entity_bytes > card::MESSAGE_REQUEST_MAX_BYTES {
        // The documented entity limit is a platform fact; the product must keep
        // the card inside it or keep local history and report needs-attention.
        record_card(
            &state.shared,
            "POST",
            CARD_CREATE_PATH,
            CallKind::CardCreate,
            card_observation(
                CardOperation::Create,
                String::new(),
                request_bytes,
                false,
                card::CODE_CARD_TOO_LARGE,
            ),
            true,
            Some(format!(
                "card entity {} exceeds {} bytes",
                parsed.entity_bytes,
                card::MESSAGE_REQUEST_MAX_BYTES
            )),
        )
        .await;
        return card_error(card::CODE_CARD_TOO_LARGE, "card entity exceeds 30 KB");
    }
    let Some(disposition) = card_disposition(&state).await else {
        return Response::new(Body::empty());
    };
    match disposition {
        CardDisposition::Succeed | CardDisposition::Hang => {
            let card_id = allocate_card(
                &state.shared,
                &parsed,
                request_bytes,
                CardDisposition::Succeed,
            )
            .await;
            card_created(&card_id)
        }
        CardDisposition::Reject { code, msg } => {
            record_card(
                &state.shared,
                "POST",
                CARD_CREATE_PATH,
                CallKind::CardCreate,
                card_observation(
                    CardOperation::Create,
                    String::new(),
                    request_bytes,
                    false,
                    code,
                ),
                true,
                Some(format!("scripted reject: {msg}")),
            )
            .await;
            card_error(code, &msg)
        }
        CardDisposition::AcceptThenDrop => {
            allocate_card(
                &state.shared,
                &parsed,
                request_bytes,
                CardDisposition::AcceptThenDrop,
            )
            .await;
            state.cancel.cancelled().await;
            Response::new(Body::empty())
        }
    }
}

pub(crate) async fn card_element_content(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Path((card_id, element_id)): Path<(String, String)>,
    raw: Bytes,
) -> Response {
    let request_bytes = raw.len();
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "PUT",
            CARD_ELEMENT_PATH,
            Some(CallKind::CardUpdate),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::CardUpdate).await {
        record_reject(
            &state.shared,
            "PUT",
            CARD_ELEMENT_PATH,
            Some(CallKind::CardUpdate),
            reason.clone(),
        )
        .await;
        return card_error(99991672, &reason);
    }
    if !card_scope(&state.shared).await {
        record_card(
            &state.shared,
            "PUT",
            CARD_ELEMENT_PATH,
            CallKind::CardUpdate,
            CardObservation {
                element_id: Some(element_id.clone()),
                ..card_observation(
                    CardOperation::Update,
                    card_id.clone(),
                    request_bytes,
                    false,
                    card::CODE_NO_PERMISSION,
                )
            },
            true,
            Some("synthetic application lacks cardkit:card:write".into()),
        )
        .await;
        return card_error(card::CODE_NO_PERMISSION, "no card permission");
    }
    let body: CardElementBody = match serde_json::from_slice(&raw) {
        Ok(body) => body,
        Err(error) => {
            record_reject(
                &state.shared,
                "PUT",
                CARD_ELEMENT_PATH,
                Some(CallKind::CardUpdate),
                format!("card element body json: {error}"),
            )
            .await;
            return card_error(232001, "card element body must be JSON");
        }
    };
    // One card has exactly one managed operation at a time. Reading the entity,
    // answering a scripted gate, registering the operation identity and
    // committing the new body all happen under this per-card lock, so an older
    // `sequence` or a repeated `uuid` can never slip in between them.
    let Some(_guard) = lock_card(&state, &card_id).await else {
        return Response::new(Body::empty());
    };
    let mut observation = CardObservation {
        element_id: Some(element_id.clone()),
        sequence: Some(body.sequence),
        uuid: body.uuid.clone(),
        content: Some(body.content.clone()),
        ..card_observation(
            CardOperation::Update,
            card_id.clone(),
            request_bytes,
            false,
            0,
        )
    };
    let uuid_payload =
        json!({"element_id": element_id, "content": body.content, "sequence": body.sequence})
            .to_string();
    if let Some(uuid) = &body.uuid
        && let Some(response) = replay_card_uuid(
            &state.shared,
            "PUT",
            CARD_ELEMENT_PATH,
            CallKind::CardUpdate,
            uuid,
            &card_id,
            CardOperation::Update,
            &uuid_payload,
            &observation,
        )
        .await
    {
        return response;
    }
    if let Some(response) = validate_card_operation(
        &state.shared,
        "PUT",
        CARD_ELEMENT_PATH,
        CallKind::CardUpdate,
        &card_id,
        &element_id,
        body.sequence,
        body.uuid.as_deref(),
        false,
        &mut observation,
    )
    .await
    {
        return response;
    }
    let Some(disposition) = card_disposition(&state).await else {
        return Response::new(Body::empty());
    };
    if let CardDisposition::Reject { code, msg } = disposition {
        // A documented stream timeout closes the platform stream: the product
        // must reopen it through the official settings surface before it can
        // continue, so the peer records that real state change too.
        if code == CARD_STREAM_TIMEOUT_CODE {
            mark_stream_closed(&state.shared, &card_id).await;
        }
        observation.accepted = false;
        observation.code = code;
        record_card(
            &state.shared,
            "PUT",
            CARD_ELEMENT_PATH,
            CallKind::CardUpdate,
            observation,
            true,
            Some(format!("scripted reject: {msg}")),
        )
        .await;
        return card_error(code, &msg);
    }
    if body.content.chars().count() > card::CARD_CONTENT_MAX_CHARS {
        let mut observation = observation;
        observation.accepted = false;
        observation.code = card::CODE_CARD_TOO_LARGE;
        record_card(
            &state.shared,
            "PUT",
            CARD_ELEMENT_PATH,
            CallKind::CardUpdate,
            observation,
            true,
            Some(format!(
                "content {} exceeds {} characters",
                body.content.chars().count(),
                card::CARD_CONTENT_MAX_CHARS
            )),
        )
        .await;
        return card_error(
            card::CODE_CARD_TOO_LARGE,
            "content exceeds 100,000 characters",
        );
    }
    // Armed by acceptance only: park between "uuid not seen" and the effect
    // commit so two cards can be put in the same interleaving deterministically.
    let precommit_gate = state.shared.lock().await.cards.precommit_gate.clone();
    if let Some(gate) = precommit_gate {
        tokio::select! {
            () = state.cancel.cancelled() => return Response::new(Body::empty()),
            () = gate.park() => {}
        }
    }
    let dropped = matches!(disposition, CardDisposition::AcceptThenDrop);
    // The whole decision and commit happen under the platform lock: the uuid
    // claim, the size guard and the entity mutation cannot interleave with a
    // concurrent request on another card.
    let outcome = {
        let mut inner = state.shared.lock().await;
        let index = inner
            .cards
            .entities
            .iter()
            .position(|entity| entity.card_id == card_id)
            .expect("card entity existed before the update");
        let mut data = inner.cards.entities[index].data.clone();
        let bytes = card::replace_element_content(&mut data, &element_id, &body.content)
            .expect("validated markdown element must still resolve");
        if bytes > card::MESSAGE_REQUEST_MAX_BYTES {
            Applied::TooLarge
        } else {
            match claim_card_uuid(
                &mut inner,
                body.uuid.as_deref(),
                &card_id,
                CardOperation::Update,
                &uuid_payload,
            ) {
                UuidClaim::Conflict => Applied::Conflict,
                UuidClaim::Replay => Applied::Replay,
                UuidClaim::Fresh => {
                    let entity = &mut inner.cards.entities[index];
                    entity.data = data;
                    if entity.element_id == element_id {
                        entity.content = body.content.clone();
                    }
                    entity.last_sequence = body.sequence;
                    entity.entity_bytes = bytes;
                    entity.updates += 1;
                    Applied::Composed
                }
            }
        }
    };
    match outcome {
        Applied::Conflict => {
            let mut conflict = observation;
            conflict.accepted = false;
            conflict.code = card::CODE_UUID_CONFLICT;
            record_card(
                &state.shared,
                "PUT",
                CARD_ELEMENT_PATH,
                CallKind::CardUpdate,
                conflict,
                true,
                Some("uuid reused concurrently for another operation, payload or card".to_owned()),
            )
            .await;
            card_error(card::CODE_UUID_CONFLICT, "uuid payload conflict")
        }
        Applied::Replay => {
            let mut replay = observation;
            replay.accepted = true;
            replay.idempotent = true;
            replay.code = 0;
            record_card(
                &state.shared,
                "PUT",
                CARD_ELEMENT_PATH,
                CallKind::CardUpdate,
                replay,
                true,
                Some("idempotent replay of the same uuid payload".to_owned()),
            )
            .await;
            card_ok()
        }
        Applied::TooLarge => {
            let mut too_large = observation;
            too_large.accepted = false;
            too_large.code = card::CODE_CARD_TOO_LARGE;
            record_card(
                &state.shared,
                "PUT",
                CARD_ELEMENT_PATH,
                CallKind::CardUpdate,
                too_large,
                true,
                Some("updated card exceeds the 30000 byte entity limit".to_owned()),
            )
            .await;
            card_error(card::CODE_CARD_TOO_LARGE, "card entity exceeds 30000 bytes")
        }
        Applied::Composed => {
            let mut observation = observation;
            observation.accepted = true;
            observation.code = 0;
            observation.response_dropped = dropped;
            record_card(
                &state.shared,
                "PUT",
                CARD_ELEMENT_PATH,
                CallKind::CardUpdate,
                observation,
                true,
                None,
            )
            .await;
            if dropped {
                // The platform applied the body; the product never learns the
                // answer. Hold the request like the create path until the peer
                // stops, so the real uncertainty is observable and the handler
                // has no detached life.
                state.cancel.cancelled().await;
                return Response::new(Body::empty());
            }
            card_ok()
        }
    }
}

pub(crate) async fn card_settings(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Path(card_id): Path<String>,
    raw: Bytes,
) -> Response {
    let request_bytes = raw.len();
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "PATCH",
            CARD_SETTINGS_PATH,
            Some(CallKind::CardSettings),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::CardSettings).await {
        record_reject(
            &state.shared,
            "PATCH",
            CARD_SETTINGS_PATH,
            Some(CallKind::CardSettings),
            reason.clone(),
        )
        .await;
        return card_error(99991672, &reason);
    }
    if !card_scope(&state.shared).await {
        record_card(
            &state.shared,
            "PATCH",
            CARD_SETTINGS_PATH,
            CallKind::CardSettings,
            card_observation(
                CardOperation::Settings,
                card_id.clone(),
                request_bytes,
                false,
                card::CODE_NO_PERMISSION,
            ),
            true,
            Some("synthetic application lacks cardkit:card:write".into()),
        )
        .await;
        return card_error(card::CODE_NO_PERMISSION, "no card permission");
    }
    let body: CardSettingsBody = match serde_json::from_slice(&raw) {
        Ok(body) => body,
        Err(error) => {
            record_reject(
                &state.shared,
                "PATCH",
                CARD_SETTINGS_PATH,
                Some(CallKind::CardSettings),
                format!("card settings body json: {error}"),
            )
            .await;
            return card_error(232001, "card settings body must be JSON");
        }
    };
    let parsed = match card::parse_card_settings(&body.settings) {
        Ok(parsed) => parsed,
        Err(error) => {
            record_reject(
                &state.shared,
                "PATCH",
                CARD_SETTINGS_PATH,
                Some(CallKind::CardSettings),
                format!("card settings: {error:#}"),
            )
            .await;
            return card_error(232001, "invalid card settings");
        }
    };
    let operation = match parsed.streaming_mode {
        Some(false) => CardOperation::Close,
        Some(true) => CardOperation::Reopen,
        None => CardOperation::Settings,
    };
    let Some(_guard) = lock_card(&state, &card_id).await else {
        return Response::new(Body::empty());
    };
    let mut observation = CardObservation {
        sequence: Some(body.sequence),
        uuid: body.uuid.clone(),
        streaming_mode: parsed.streaming_mode,
        summary: parsed.summary.clone(),
        ..card_observation(operation, card_id.clone(), request_bytes, false, 0)
    };
    let uuid_payload = json!({"settings": body.settings, "sequence": body.sequence}).to_string();
    if let Some(uuid) = &body.uuid
        && let Some(response) = replay_card_uuid(
            &state.shared,
            "PATCH",
            CARD_SETTINGS_PATH,
            CallKind::CardSettings,
            uuid,
            &card_id,
            operation,
            &uuid_payload,
            &observation,
        )
        .await
    {
        return response;
    }
    if let Some(response) = validate_card_operation(
        &state.shared,
        "PATCH",
        CARD_SETTINGS_PATH,
        CallKind::CardSettings,
        &card_id,
        "",
        body.sequence,
        body.uuid.as_deref(),
        parsed.streaming_mode == Some(true),
        &mut observation,
    )
    .await
    {
        return response;
    }
    let Some(disposition) = card_disposition(&state).await else {
        return Response::new(Body::empty());
    };
    match disposition {
        CardDisposition::Reject { code, msg } => {
            if code == CARD_STREAM_TIMEOUT_CODE {
                mark_stream_closed(&state.shared, &card_id).await;
            }
            observation.accepted = false;
            observation.code = code;
            record_card(
                &state.shared,
                "PATCH",
                CARD_SETTINGS_PATH,
                CallKind::CardSettings,
                observation,
                true,
                Some(format!("scripted reject: {msg}")),
            )
            .await;
            card_error(code, &msg)
        }
        CardDisposition::Succeed | CardDisposition::Hang | CardDisposition::AcceptThenDrop => {
            let dropped = matches!(disposition, CardDisposition::AcceptThenDrop);
            // The uuid claim and the settings commit share one critical section,
            // so a concurrent request on another card cannot apply the same uuid.
            let applied = {
                let mut inner = state.shared.lock().await;
                match claim_card_uuid(
                    &mut inner,
                    body.uuid.as_deref(),
                    &card_id,
                    operation,
                    &uuid_payload,
                ) {
                    UuidClaim::Conflict => false,
                    UuidClaim::Replay => {
                        let mut replay = observation.clone();
                        replay.card_id = card_id.clone();
                        replay.accepted = true;
                        replay.idempotent = true;
                        replay.code = 0;
                        record_card(
                            &state.shared,
                            "PATCH",
                            CARD_SETTINGS_PATH,
                            CallKind::CardSettings,
                            replay,
                            true,
                            Some("idempotent replay of the same uuid settings payload".to_owned()),
                        )
                        .await;
                        return card_ok();
                    }
                    UuidClaim::Fresh => {
                        let index = inner
                            .cards
                            .entities
                            .iter()
                            .position(|entity| entity.card_id == card_id)
                            .expect("card entity existed before the settings update");
                        let entity = &mut inner.cards.entities[index];
                        if let Some(mode) = parsed.streaming_mode {
                            entity.streaming_closed = !mode;
                        }
                        entity.last_sequence = body.sequence;
                        entity.settings_updates += 1;
                        true
                    }
                }
            };
            if !applied {
                let mut conflict = observation;
                conflict.accepted = false;
                conflict.code = card::CODE_UUID_CONFLICT;
                record_card(
                    &state.shared,
                    "PATCH",
                    CARD_SETTINGS_PATH,
                    CallKind::CardSettings,
                    conflict,
                    true,
                    Some(
                        "uuid reused concurrently for another settings payload or card".to_owned(),
                    ),
                )
                .await;
                return card_error(card::CODE_UUID_CONFLICT, "uuid payload conflict");
            }
            let mut observation = observation;
            observation.accepted = true;
            observation.code = 0;
            observation.response_dropped = dropped;
            record_card(
                &state.shared,
                "PATCH",
                CARD_SETTINGS_PATH,
                CallKind::CardSettings,
                observation,
                true,
                None,
            )
            .await;
            if dropped {
                state.cancel.cancelled().await;
                return Response::new(Body::empty());
            }
            card_ok()
        }
    }
}

/// Documented stream-timeout code; the platform also closes the stream.
const CARD_STREAM_TIMEOUT_CODE: i32 = 200_850;

/// Answers the next scripted card disposition. A `Hang` gate is waited on here,
/// under the caller's per-card lock and outside the shared state, so control and
/// shutdown stay responsive; a cancelled peer ends the request instead of
/// abandoning it.
async fn card_disposition(state: &HttpState) -> Option<CardDisposition> {
    if state.cancel.is_cancelled() {
        return None;
    }
    let disposition = {
        let mut inner = state.shared.lock().await;
        inner.next_card_disposition()
    };
    if matches!(disposition, CardDisposition::Hang) {
        let waiter = { state.shared.lock().await.cards.hang.waiter() };
        waiter.wait(&state.cancel).await;
        if state.cancel.is_cancelled() {
            return None;
        }
    }
    Some(disposition)
}

async fn mark_stream_closed(shared: &Shared, card_id: &str) {
    let mut inner = shared.lock().await;
    if let Some(entity) = inner
        .cards
        .entities
        .iter_mut()
        .find(|entity| entity.card_id == card_id)
    {
        entity.streaming_closed = true;
    }
}

/// Structural checks shared by content and settings updates.
///
/// The product's own wire violations are recorded as fixture failures: an
/// unknown entity, an element that is not the markdown body, a non-increasing
/// sequence, or a malformed identity. Documented platform conditions stay
/// explicit business answers (`accepted` request, non-zero code) so a scenario
/// can observe real handling: the operator-set 14-day window and a stream that
/// is already closed. A settings update that reopens the stream is allowed.
#[allow(clippy::too_many_arguments)]
async fn validate_card_operation(
    shared: &Shared,
    method: &str,
    path: &str,
    kind: CallKind,
    card_id: &str,
    element_id: &str,
    sequence: i64,
    uuid: Option<&str>,
    allow_reopen: bool,
    observation: &mut CardObservation,
) -> Option<Response> {
    if let Some(uuid) = uuid
        && (uuid.is_empty() || uuid.chars().count() > card::CARD_UUID_MAX_CHARS)
    {
        record_reject(
            shared,
            method,
            path,
            Some(kind),
            format!(
                "uuid must have 1..={} characters",
                card::CARD_UUID_MAX_CHARS
            ),
        )
        .await;
        return Some(card_error(232001, "uuid length is invalid"));
    }
    if sequence <= 0 || sequence > card::CARD_SEQUENCE_MAX {
        record_reject(
            shared,
            method,
            path,
            Some(kind),
            format!("sequence {sequence} is not a positive int32"),
        )
        .await;
        return Some(card_error(
            card::CODE_SEQUENCE_NOT_INCREASING,
            "sequence must be a positive int32",
        ));
    }
    let state = {
        let inner = shared.lock().await;
        match inner
            .cards
            .entities
            .iter()
            .find(|entity| entity.card_id == card_id)
        {
            None => Err(()),
            Some(entity) => Ok((
                entity
                    .data
                    .get("body")
                    .and_then(|body| body.get("elements"))
                    .and_then(serde_json::Value::as_array)
                    .is_some_and(|elements| {
                        elements.iter().any(|element| {
                            element.get("tag").and_then(serde_json::Value::as_str)
                                == Some("markdown")
                                && element
                                    .get("element_id")
                                    .and_then(serde_json::Value::as_str)
                                    == Some(element_id)
                        })
                    }),
                entity.expired,
                entity.streaming_closed,
                entity.last_sequence,
            )),
        }
    };
    let (known_element, expired, streaming_closed, last_sequence) = match state {
        Ok(state) => state,
        Err(()) => {
            record_reject(
                shared,
                method,
                path,
                Some(kind),
                format!("unknown card entity {card_id}"),
            )
            .await;
            return Some(card_error(card::CODE_NO_CARD, "card entity does not exist"));
        }
    };
    if !element_id.is_empty() && !known_element {
        record_reject(
            shared,
            method,
            path,
            Some(kind),
            format!("element {element_id} is not the markdown element"),
        )
        .await;
        return Some(card_error(
            card::CODE_ELEMENT_NOT_TEXT,
            "element is not a text element",
        ));
    }
    if expired {
        observation.accepted = false;
        observation.code = card::CODE_CARD_EXPIRED;
        record_card(
            shared,
            method,
            path,
            kind,
            observation.clone(),
            true,
            Some("card entity is past its 14-day window".into()),
        )
        .await;
        return Some(card_error(card::CODE_CARD_EXPIRED, "card entity expired"));
    }
    if streaming_closed && !allow_reopen {
        observation.accepted = false;
        observation.code = card::CODE_STREAM_CLOSED;
        record_card(
            shared,
            method,
            path,
            kind,
            observation.clone(),
            true,
            Some("stream is closed; only an explicit reopen may continue".into()),
        )
        .await;
        return Some(card_error(
            card::CODE_STREAM_CLOSED,
            "stream already closed",
        ));
    }
    if sequence <= last_sequence {
        record_reject(
            shared,
            method,
            path,
            Some(kind),
            format!("sequence {sequence} is not greater than {last_sequence}"),
        )
        .await;
        return Some(card_error(
            card::CODE_SEQUENCE_NOT_INCREASING,
            "sequence is not strictly increasing",
        ));
    }
    None
}

#[allow(clippy::too_many_arguments)]
async fn replay_card_uuid(
    shared: &Shared,
    method: &str,
    path: &str,
    kind: CallKind,
    uuid: &str,
    card_id: &str,
    operation: CardOperation,
    payload: &str,
    observation: &CardObservation,
) -> Option<Response> {
    let existing = {
        let inner = shared.lock().await;
        inner
            .cards
            .uuids
            .iter()
            .find(|record| record.uuid == uuid)
            .map(|record| {
                (
                    record.payload.clone(),
                    record.code,
                    record.operation,
                    record.card_id.clone(),
                )
            })
    };
    let (seen_payload, code, seen_operation, seen_card) = existing?;
    if seen_payload != payload || seen_operation != operation || seen_card != card_id {
        // A documented business answer, not a fixture failure: the platform
        // rejects the identity reuse and leaves the card state untouched.
        let mut conflict = observation.clone();
        conflict.card_id = card_id.to_owned();
        conflict.accepted = false;
        conflict.code = card::CODE_UUID_CONFLICT;
        record_card(
            shared,
            method,
            path,
            kind,
            conflict,
            true,
            Some(format!(
                "uuid {uuid} reused for another operation or payload (stored {} on {seen_card})",
                operation_label(seen_operation)
            )),
        )
        .await;
        return Some(card_error(
            card::CODE_UUID_CONFLICT,
            "uuid payload conflict",
        ));
    }
    let mut observation = observation.clone();
    observation.card_id = card_id.to_owned();
    observation.idempotent = true;
    observation.accepted = code == 0;
    observation.code = code;
    record_card(
        shared,
        method,
        path,
        kind,
        observation,
        true,
        Some(format!("idempotent replay of uuid {uuid}")),
    )
    .await;
    Some(if code == 0 {
        card_ok()
    } else {
        card_error(
            code,
            &format!("replayed {} for uuid {uuid}", operation_label(operation)),
        )
    })
}

/// Result of one locked content-update commit.
enum Applied {
    Composed,
    TooLarge,
    Replay,
    Conflict,
}

/// Outcome of claiming one card uuid at the side-effect boundary.
enum UuidClaim {
    /// The uuid was free and is now owned by this request.
    Fresh,
    /// The same card, operation and payload already own this uuid.
    Replay,
    /// Another card, operation or payload owns this uuid.
    Conflict,
}

/// Reserves one card uuid inside the same critical section that applies the
/// effect.
///
/// The pre-flight check and the commit are separate awaits, and the per-card
/// lock does not serialize two different cards. Checking and claiming here, under
/// the single platform lock, makes a cross-card reuse of one uuid unable to apply
/// twice: the loser sees the winner's reservation and answers with the documented
/// conflict (or an idempotent replay) instead of mutating platform state.
///
/// The peer's uuid scope is global, matching the official CardKit contract it
/// models; no extra lock, task or registry is introduced.
fn claim_card_uuid(
    inner: &mut super::state::Inner,
    uuid: Option<&str>,
    card_id: &str,
    operation: CardOperation,
    payload: &str,
) -> UuidClaim {
    let Some(uuid) = uuid else {
        return UuidClaim::Fresh;
    };
    match inner.cards.uuids.iter().find(|record| record.uuid == uuid) {
        None => {
            inner.cards.uuids.push(super::state::CardUuidRecord {
                uuid: uuid.to_owned(),
                card_id: card_id.to_owned(),
                operation,
                payload: payload.to_owned(),
                code: 0,
            });
            UuidClaim::Fresh
        }
        Some(record)
            if record.card_id == card_id
                && record.operation == operation
                && record.payload == payload =>
        {
            UuidClaim::Replay
        }
        Some(_) => UuidClaim::Conflict,
    }
}

fn operation_label(operation: CardOperation) -> &'static str {
    match operation {
        CardOperation::Create => "card create",
        CardOperation::Send => "card send",
        CardOperation::Update => "card element update",
        CardOperation::Settings => "card settings update",
        CardOperation::Close => "card stream close",
        CardOperation::Reopen => "card stream reopen",
    }
}

/// One observation skeleton; ordinal and card identity are filled by the caller.
fn card_observation(
    operation: CardOperation,
    card_id: String,
    request_bytes: usize,
    accepted: bool,
    code: i32,
) -> CardObservation {
    CardObservation {
        ordinal: 0,
        operation,
        card_id,
        unix_millis: unix_millis(),
        element_id: None,
        sequence: None,
        uuid: None,
        content: None,
        streaming_mode: None,
        summary: None,
        accepted,
        code,
        request_bytes,
        idempotent: false,
        response_dropped: false,
    }
}

async fn allocate_card(
    shared: &Shared,
    parsed: &card::CardJson,
    request_bytes: usize,
    disposition: CardDisposition,
) -> String {
    let mut inner = shared.lock().await;
    inner.cards.next_id += 1;
    let card_id = format!("card_fx_{:04}", inner.cards.next_id);
    assert!(
        card_id.chars().count() <= card::CARD_ID_MAX_CHARS,
        "synthetic card id must fit the documented id length"
    );
    inner.cards.entities.push(super::state::CardEntity {
        card_id: card_id.clone(),
        element_id: parsed.element_id.clone(),
        data: parsed.data.clone(),
        created_unix_millis: unix_millis(),
        entity_bytes: parsed.entity_bytes,
        sent_message_id: None,
        sent_uuid: None,
        sent: None,
        last_sequence: 0,
        content: parsed.content.clone(),
        streaming_closed: false,
        expired: false,
        updates: 0,
        settings_updates: 0,
    });
    let ordinal = inner.cards.next_ordinal;
    inner.cards.next_ordinal += 1;
    let dropped = matches!(disposition, CardDisposition::AcceptThenDrop);
    inner.cards.operations.push(CardObservation {
        ordinal,
        operation: CardOperation::Create,
        card_id: card_id.clone(),
        unix_millis: unix_millis(),
        element_id: Some(parsed.element_id.clone()),
        sequence: None,
        uuid: None,
        content: Some(parsed.content.clone()),
        streaming_mode: None,
        summary: None,
        accepted: true,
        code: 0,
        request_bytes,
        idempotent: false,
        response_dropped: dropped,
    });
    inner.record(
        "POST",
        CARD_CREATE_PATH,
        Some(CallKind::CardCreate),
        true,
        None,
    );
    if let Some(last) = inner.calls.last_mut() {
        last.request_bytes = request_bytes;
        last.card_id = Some(card_id.clone());
    }
    card_id
}

async fn card_scope(shared: &Shared) -> bool {
    shared.lock().await.cards.scope_allowed
}

#[allow(clippy::too_many_arguments)]
async fn record_card(
    shared: &Shared,
    method: &str,
    path: &str,
    kind: CallKind,
    mut observation: CardObservation,
    accepted: bool,
    diagnostic: Option<String>,
) {
    let mut inner = shared.lock().await;
    let ordinal = inner.cards.next_ordinal;
    inner.cards.next_ordinal += 1;
    observation.ordinal = ordinal;
    let request_bytes = observation.request_bytes;
    let card_id = observation.card_id.clone();
    inner.cards.operations.push(observation);
    inner.record(method, path, Some(kind), accepted, diagnostic);
    if let Some(last) = inner.calls.last_mut() {
        last.request_bytes = request_bytes;
        last.card_id = Some(card_id);
    }
}

fn card_error(code: i32, msg: &str) -> Response {
    Json(json!({ "code": code, "msg": msg })).into_response()
}

fn card_ok() -> Response {
    Json(json!({ "code": 0, "msg": "success", "data": {} })).into_response()
}

fn card_created(card_id: &str) -> Response {
    Json(json!({ "code": 0, "msg": "success", "data": { "card_id": card_id } })).into_response()
}

/// The one per-card serialization boundary.
///
/// `begin_wait` publishes the intent before the mutex is awaited, so an
/// observer can tell "queued behind another operation" apart from "not yet
/// arrived" without sleeping. Dropping the guard releases the mutex and the
/// holder count, including when the request is cancelled.
pub(crate) struct CardLockGuard {
    entry: std::sync::Arc<super::state::CardLockEntry>,
    /// Owned guard: releasing the boundary never needs an await, so it also
    /// releases when the request future is cancelled.
    _guard: tokio::sync::OwnedMutexGuard<()>,
}

impl Drop for CardLockGuard {
    fn drop(&mut self) {
        self.entry.left();
    }
}

/// Cancellation-safe registration of one request waiting on the boundary.
///
/// The registration exists from before the mutex is awaited, so dropping the
/// wait (cancellation) always decrements `waiting`. On acquisition it hands the
/// registration over to the holder count instead of leaving two facts behind.
struct WaitingGuard {
    entry: std::sync::Arc<super::state::CardLockEntry>,
    armed: bool,
}

impl WaitingGuard {
    fn register(entry: std::sync::Arc<super::state::CardLockEntry>) -> Self {
        entry.begin_wait();
        Self { entry, armed: true }
    }

    fn handoff(mut self) {
        self.entry.handoff_to_holder();
        self.armed = false;
    }
}

impl Drop for WaitingGuard {
    fn drop(&mut self) {
        if self.armed {
            self.entry.cancel_wait();
        }
    }
}

/// Enters the per-card boundary. `None` means the request was cancelled while
/// queued (peer observation mechanism); the caller ends the response without a
/// record, and the registration is already released.
pub(crate) async fn lock_card(state: &HttpState, card_id: &str) -> Option<CardLockGuard> {
    let entry = {
        let mut inner = state.shared.lock().await;
        inner.card_lock(card_id)
    };
    let abort = entry.abort_token();
    let wait = WaitingGuard::register(std::sync::Arc::clone(&entry));
    let guard = tokio::select! {
        biased;
        () = state.cancel.cancelled() => return None,
        guard = std::sync::Arc::clone(&entry.mutex).lock_owned() => guard,
        () = abort.cancelled() => return None,
    };
    wait.handoff();
    Some(CardLockGuard {
        entry,
        _guard: guard,
    })
}

/// Publishes one created card entity as a single IM `interactive` message.
///
/// The entity identity, the sent-message identity, the scripted gate and the
/// commit all run inside the per-card boundary: two concurrent requests for the
/// same card can never both observe an unsent entity. Retrying the *complete*
/// request with the same uuid answers the same message id and applies nothing;
/// another uuid or another body is refused.
pub(crate) async fn send_card_message(
    state: &HttpState,
    body: &SendBody,
    request_bytes: usize,
) -> Response {
    let path = "/open-apis/im/v1/messages";
    let card_id = match card::parse_interactive_content(&body.content) {
        Ok(card_id) => card_id,
        Err(error) => {
            record_reject(
                &state.shared,
                "POST",
                path,
                Some(CallKind::MessageSend),
                format!("interactive content: {error:#}"),
            )
            .await;
            return Json(json!({"code": 232001, "msg": "invalid interactive content"}))
                .into_response();
        }
    };
    // Observation contract of this environment (stricter than the official
    // optional field): the product must publish a card entity with a stable
    // non-empty uuid, because that identity is what makes a retry auditable.
    let Some(uuid) = body.uuid.as_deref().filter(|uuid| !uuid.is_empty()) else {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            "interactive send without a stable uuid".into(),
        )
        .await;
        return Json(json!({
            "code": 232001,
            "msg": "interactive send requires a stable uuid"
        }))
        .into_response();
    };
    let request = CardSendIdentity {
        message_id: String::new(),
        receive_id: body.receive_id.clone(),
        msg_type: body.msg_type.clone(),
        content: body.content.clone(),
        uuid: uuid.to_owned(),
    };
    if !state.shared.lock().await.is_known_chat(&body.receive_id) {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            "unknown receive_id".into(),
        )
        .await;
        return Json(json!({"code": 232006, "msg": "invalid receive_id"})).into_response();
    }
    let Some(_guard) = lock_card(state, &card_id).await else {
        return Response::new(Body::empty());
    };
    let existing = {
        let inner = state.shared.lock().await;
        match inner
            .cards
            .entities
            .iter()
            .find(|entity| entity.card_id == card_id)
        {
            None => Err(()),
            Some(entity) => Ok((entity.expired, entity.sent.clone())),
        }
    };
    let (expired, sent) = match existing {
        Ok(state) => state,
        Err(()) => {
            record_reject(
                &state.shared,
                "POST",
                path,
                Some(CallKind::MessageSend),
                format!("unknown card entity {card_id}"),
            )
            .await;
            return card_error(card::CODE_NO_CARD, "card entity does not exist");
        }
    };
    if expired {
        record_send_attempt(
            state,
            body,
            request_bytes,
            None,
            Some("card entity expired"),
            false,
        )
        .await;
        return card_error(card::CODE_CARD_EXPIRED, "card entity expired");
    }
    if let Some(stored) = sent {
        // One entity, one published message. The *complete* identity decides:
        // identical retry replays the original answer, any other uuid/chat/type/
        // body is refused and changes nothing.
        let identical = stored.receive_id == request.receive_id
            && stored.msg_type == request.msg_type
            && stored.content == request.content
            && stored.uuid == request.uuid;
        if identical {
            record_replay(state, &stored, request_bytes).await;
            return Json(send_ok_fields(
                &stored.message_id,
                &stored.receive_id,
                &stored.msg_type,
                &stored.content,
            ))
            .into_response();
        }
        if stored.uuid == request.uuid {
            record_reject(
                &state.shared,
                "POST",
                path,
                Some(CallKind::MessageSend),
                format!(
                    "card {card_id} uuid {} reused with another chat/type/body",
                    request.uuid
                ),
            )
            .await;
            return card_error(
                CODE_SEND_IDENTITY_CONFLICT,
                "uuid reused for another message identity",
            );
        }
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            format!(
                "card {card_id} was already sent once; uuid {} refused",
                request.uuid
            ),
        )
        .await;
        return card_error(
            card::CODE_CARD_ALREADY_SENT,
            "card entity may be sent only once",
        );
    }
    let assigned = {
        let mut inner = state.shared.lock().await;
        inner.im.send_seq += 1;
        format!("om_anywork_send_{}", inner.im.send_seq)
    };
    let send_disposition = {
        let mut inner = state.shared.lock().await;
        inner.next_send()
    };
    match send_disposition {
        SendDisposition::Hang => {
            // The wait happens inside the per-card boundary: a second request for
            // the same card cannot pass the identity check while this one is
            // pending, which is what makes the double-send race unobservable.
            let waiter = { state.shared.lock().await.im.hang.waiter() };
            waiter.wait(&state.cancel).await;
            if state.cancel.is_cancelled() {
                return Response::new(Body::empty());
            }
            let identity =
                commit_card_send(state, &card_id, &assigned, &request, request_bytes, false).await;
            Json(send_ok_fields(
                &identity.message_id,
                &identity.receive_id,
                &identity.msg_type,
                &identity.content,
            ))
            .into_response()
        }
        SendDisposition::Succeed => {
            let identity =
                commit_card_send(state, &card_id, &assigned, &request, request_bytes, false).await;
            Json(send_ok_fields(
                &identity.message_id,
                &identity.receive_id,
                &identity.msg_type,
                &identity.content,
            ))
            .into_response()
        }
        SendDisposition::AcceptThenDrop => {
            commit_card_send(state, &card_id, &assigned, &request, request_bytes, true).await;
            state.cancel.cancelled().await;
            Response::new(Body::empty())
        }
        SendDisposition::Reject { code, msg } => {
            record_send_attempt(
                state,
                body,
                request_bytes,
                None,
                Some(&format!("scripted reject: {msg}")),
                false,
            )
            .await;
            card_error(code, &msg)
        }
    }
}

/// Synthetic business code for reusing one uuid with another message identity.
const CODE_SEND_IDENTITY_CONFLICT: i32 = 232_010;

/// Binds one card entity to exactly one platform message and records the send.
async fn commit_card_send(
    state: &HttpState,
    card_id: &str,
    message_id: &str,
    request: &CardSendIdentity,
    request_bytes: usize,
    response_dropped: bool,
) -> super::state::CardSendIdentity {
    let identity = super::state::CardSendIdentity {
        message_id: message_id.to_owned(),
        ..request.clone()
    };
    let mut inner = state.shared.lock().await;
    let index = inner
        .cards
        .entities
        .iter()
        .position(|entity| entity.card_id == card_id)
        .expect("card entity existed before the send");
    inner.cards.entities[index].sent_message_id = Some(message_id.to_owned());
    inner.cards.entities[index].sent_uuid = Some(identity.uuid.clone());
    inner.cards.entities[index].sent = Some(identity.clone());
    let ordinal = inner.cards.next_ordinal;
    inner.cards.next_ordinal += 1;
    inner.record(
        "POST",
        "/open-apis/im/v1/messages",
        Some(CallKind::MessageSend),
        true,
        None,
    );
    if let Some(last) = inner.calls.last_mut() {
        record_call_facts(
            last,
            &identity.receive_id,
            &identity.msg_type,
            &identity.content,
            &identity.uuid,
            message_id,
            request_bytes,
            false,
        );
    }
    inner.cards.operations.push(CardObservation {
        ordinal,
        operation: CardOperation::Send,
        card_id: card_id.to_owned(),
        unix_millis: unix_millis(),
        element_id: None,
        sequence: None,
        uuid: Some(identity.uuid.clone()),
        content: None,
        streaming_mode: None,
        summary: None,
        accepted: true,
        code: 0,
        request_bytes,
        idempotent: false,
        response_dropped,
    });
    identity
}

/// Records the idempotent replay of the one published message, keeping the
/// original identity facts (chat, type, body, card) instead of the retried ones.
async fn record_replay(
    state: &HttpState,
    stored: &super::state::CardSendIdentity,
    request_bytes: usize,
) {
    let mut inner = state.shared.lock().await;
    inner.record(
        "POST",
        "/open-apis/im/v1/messages",
        Some(CallKind::MessageSend),
        true,
        Some("identical retry of the published card message".into()),
    );
    if let Some(last) = inner.calls.last_mut() {
        record_call_facts(
            last,
            &stored.receive_id,
            &stored.msg_type,
            &stored.content,
            &stored.uuid,
            &stored.message_id,
            request_bytes,
            true,
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn record_call_facts(
    call: &mut super::types::RecordedCall,
    receive_id: &str,
    msg_type: &str,
    content: &str,
    uuid: &str,
    message_id: &str,
    request_bytes: usize,
    deduplicated: bool,
) {
    call.send_body = Some(json!({
        "receive_id": receive_id,
        "msg_type": msg_type,
        "content": content,
        "uuid": uuid,
    }));
    call.assigned_message_id = Some(message_id.to_owned());
    call.uuid = Some(uuid.to_owned());
    call.request_bytes = request_bytes;
    call.msg_type = Some(msg_type.to_owned());
    call.card_id = card::parse_interactive_content(content).ok();
    call.deduplicated = deduplicated;
}

async fn record_send_attempt(
    state: &HttpState,
    body: &SendBody,
    request_bytes: usize,
    message_id: Option<&str>,
    diagnostic: Option<&str>,
    deduplicated: bool,
) {
    let mut inner = state.shared.lock().await;
    inner.record(
        "POST",
        "/open-apis/im/v1/messages",
        Some(CallKind::MessageSend),
        true,
        diagnostic.map(str::to_owned),
    );
    if let Some(last) = inner.calls.last_mut() {
        // One critical section: the recorded call and its deduplication fact can
        // never be split by another card's send.
        record_call_facts(
            last,
            &body.receive_id,
            &body.msg_type,
            &body.content,
            body.uuid.as_deref().unwrap_or_default(),
            message_id.unwrap_or_default(),
            request_bytes,
            deduplicated,
        );
    }
}
