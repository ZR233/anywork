//! Explicit operator observation of the peer's Markdown and CardKit surfaces.
//!
//! Two entry points keep the concerns apart: `observe_markdown_and_cards` runs
//! against the main peer and must leave a verifiable report (positive flows,
//! documented business answers, gate lifecycles), while
//! `observe_card_protocol_invariants` deliberately abuses the protocol on its own
//! peer to prove the boundary itself (stale sequence interleaving, uuid identity,
//! encoded sizes, per-target rate). Neither function is a product test and
//! neither stands in for a production pass.

use std::time::Duration;

use anyhow::{Context, Result, ensure};
use reqwest::Client;

use super::observe::observe_http_client;
use super::types::{DIRECT_CHAT_ID, GROUP_CHAT_ID, PAIRING_DIRECT_CHAT_ID, TENANT_ACCESS_TOKEN};
use super::{CardDisposition, CardObservation, CardOperation, FeishuPeer};

pub(super) async fn observe_markdown_and_cards(
    client: &Client,
    origin: &str,
    control: &super::FeishuControl,
) -> Result<()> {
    let card_json = serde_json::json!({
        "schema": "2.0",
        "config": {
            "streaming_mode": true,
            "update_multi": true,
            "wide_screen_mode": true
        },
        "body": {
            "elements": [
                { "tag": "markdown", "element_id": "fixture_body", "content": "" },
                { "tag": "hr" }
            ]
        }
    })
    .to_string();
    let created: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": card_json }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(created["code"] == 0, "card create {created}");
    let card_id = created["data"]["card_id"]
        .as_str()
        .context("card id")?
        .to_owned();
    ensure!(
        !card_id.is_empty() && card_id.chars().count() <= 20,
        "card id shape"
    );

    let element_path =
        format!("{origin}/open-apis/cardkit/v1/cards/{card_id}/elements/fixture_body/content");
    let first = serde_json::json!({ "content": "# 标题\n\n- 一", "sequence": 1, "uuid": "uuid-card-fixture-1" });
    let updated: serde_json::Value = client
        .put(&element_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&first)
        .send()
        .await?
        .json()
        .await?;
    ensure!(updated["code"] == 0, "card update {updated}");
    // Same identity and payload: answered again, applied once.
    let replay: serde_json::Value = client
        .put(&element_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&first)
        .send()
        .await?
        .json()
        .await?;
    ensure!(replay["code"] == 0, "card update replay {replay}");

    let sent: serde_json::Value = client
        .post(format!(
            "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "receive_id": GROUP_CHAT_ID,
            "msg_type": "interactive",
            "content": serde_json::json!({
                "type": "card",
                "data": { "card_id": card_id }
            })
            .to_string(),
            "uuid": "uuid-card-fixture-send"
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(sent["code"] == 0, "card send {sent}");

    // Official whole-card update: the same entity is replaced in place with the
    // complete JSON 2.0 document (answer body plus a separate host notice), and
    // its sequence shares the one counter with element content and settings.
    let host_notice =
        "内容已截断，以下不是完整答复或代码；全文保留在 Studio，可要求导出 Markdown 文件";
    let whole_card = serde_json::json!({
        "schema": "2.0",
        "config": {
            "streaming_mode": true,
            "update_multi": true,
            "wide_screen_mode": true
        },
        "body": {
            "elements": [
                {
                    "tag": "markdown",
                    "element_id": "fixture_body",
                    "content": "# 标题\n\n- 一\n\n- 二（全卡更新正文）"
                },
                { "tag": "hr" },
                { "tag": "plain_text", "content": host_notice }
            ]
        }
    })
    .to_string();
    let whole_bytes = whole_card.len();
    let whole_path = format!("{origin}/open-apis/cardkit/v1/cards/{card_id}");
    let whole_body = serde_json::json!({
        "card": { "type": "card_json", "data": whole_card },
        "sequence": 2,
        "uuid": "uuid-card-fixture-whole-1"
    });
    let whole_request_bytes = serde_json::to_vec(&whole_body)?.len();
    let whole: serde_json::Value = client
        .put(&whole_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&whole_body)
        .send()
        .await?
        .json()
        .await?;
    ensure!(whole["code"] == 0, "whole card update {whole}");
    // Same identity and payload: answered again, applied once.
    let whole_replay: serde_json::Value = client
        .put(&whole_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&whole_body)
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        whole_replay["code"] == 0,
        "whole card replay {whole_replay}"
    );
    // The documented 30 KB budget is a property of the submitted request, so it
    // is answered before any uuid replay: an over-budget retry that reuses the
    // applied uuid, sequence and inner document must not be reported as an
    // idempotent success. Only outer JSON whitespace changes here, so the parsed
    // document and the uuid payload stay byte-identical to the applied update.
    let compact_body = serde_json::to_string(&whole_body)?;
    let padded_body = compact_body.replacen('{', &format!("{{{}", " ".repeat(30_000)), 1);
    ensure!(
        compact_body.len() <= 30_000 && padded_body.len() > 30_000,
        "the padded replay must exceed the 30000-byte request budget while its document stays inside it"
    );
    let padded_replay: serde_json::Value = client
        .put(&whole_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .header("content-type", "application/json")
        .body(padded_body)
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        padded_replay["code"] == 200_860,
        "an over-budget replay of an applied uuid must be refused by the request budget, got {padded_replay}"
    );
    let after_padded = control
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == card_id)
        .context("card entity after the over-budget replay")?;
    ensure!(
        after_padded.whole_card_updates == 1
            && after_padded.last_sequence == 2
            && after_padded.entity_json.contains(host_notice),
        "a refused over-budget replay must keep the applied whole-card state (updates={}, sequence={})",
        after_padded.whole_card_updates,
        after_padded.last_sequence
    );

    let settings_path = format!("{origin}/open-apis/cardkit/v1/cards/{card_id}/settings");
    let closed: serde_json::Value = client
        .patch(&settings_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "settings": serde_json::json!({
                "config": { "streaming_mode": false },
                "summary": { "content": "fixture finished" }
            })
            .to_string(),
            "sequence": 3
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(closed["code"] == 0, "card settings {closed}");

    let entities = control.card_entities().await;
    let entity = entities
        .iter()
        .find(|entity| entity.card_id == card_id)
        .context("card entity report")?;
    ensure!(
        entity.updates == 1,
        "idempotent replay must not count as an update"
    );
    ensure!(
        entity.whole_card_updates == 1,
        "idempotent whole-card replay must not count as an update"
    );
    ensure!(
        entity.last_sequence == 3,
        "element content, whole card and settings must share one sequence counter"
    );
    ensure!(
        entity.entity_json.contains(host_notice)
            && entity.entity_json.contains("二（全卡更新正文）"),
        "the replaced entity must hold the whole-card body and the separate host notice"
    );
    ensure!(
        entity.entity_bytes == whole_bytes,
        "the stored entity must be the exact submitted whole-card document"
    );
    ensure!(entity.settings_updates == 1, "settings count");
    ensure!(
        entity.streaming_closed,
        "settings close must close the stream"
    );
    ensure!(entity.sent_message_id.is_some(), "send identity");
    let observations = control.card_observations().await;
    let ordinals: Vec<usize> = observations.iter().map(|item| item.ordinal).collect();
    ensure!(
        ordinals.windows(2).all(|pair| pair[0] < pair[1]),
        "card operation ordinals must increase"
    );
    let whole_ops: Vec<&CardObservation> = observations
        .iter()
        .filter(|item| item.operation == CardOperation::WholeCard)
        .collect();
    let applied_count = whole_ops
        .iter()
        .filter(|item| item.accepted && !item.idempotent)
        .count();
    let replay_count = whole_ops
        .iter()
        .filter(|item| item.accepted && item.idempotent)
        .count();
    let refused_count = whole_ops.iter().filter(|item| !item.accepted).count();
    ensure!(
        applied_count == 1 && replay_count == 1 && refused_count == 1,
        "the whole-card log must hold one applied update, one idempotent replay and one over-budget refusal, got applied={applied_count} replay={replay_count} refused={refused_count}"
    );
    let applied = whole_ops
        .iter()
        .find(|item| item.accepted && !item.idempotent)
        .context("applied whole-card observation")?;
    ensure!(
        applied.card_id == card_id
            && applied.uuid.as_deref() == Some("uuid-card-fixture-whole-1")
            && applied.sequence == Some(2)
            && applied.card_bytes == Some(whole_bytes)
            && applied.request_bytes == whole_request_bytes
            && applied.request_bytes > whole_bytes,
        "the whole-card observation must keep the real entity and nested request bytes"
    );
    ensure!(
        whole_ops
            .iter()
            .any(|item| item.idempotent && item.accepted),
        "the replay must be recorded as an idempotent whole-card fact"
    );
    // The refused over-budget replay keeps the documented answer and the real
    // byte split: the nested document stays inside the budget while the padded
    // request bytes exceed it, and the applied state is untouched.
    let refused = whole_ops
        .iter()
        .find(|item| !item.accepted)
        .context("refused whole-card observation")?;
    ensure!(
        refused.code == 200_860
            && refused.card_id == card_id
            && refused.uuid.as_deref() == Some("uuid-card-fixture-whole-1")
            && refused.sequence == Some(2)
            && refused.card_bytes == Some(whole_bytes)
            && refused.request_bytes > 30_000
            && refused.card_bytes.is_some_and(|bytes| bytes <= 30_000),
        "an over-budget replay must be refused by the request budget only (code {}, request {} bytes, entity {:?} bytes)",
        refused.code,
        refused.request_bytes,
        refused.card_bytes
    );
    ensure!(
        !refused.idempotent,
        "a refused over-budget replay must never be counted as an idempotent success"
    );

    // A reused sequence and an invalid JSON 2.0 document are wire violations of
    // the official contract, not scripted platform answers. They belong to the
    // explicit invariant peer (`observe_card_protocol_invariants`), which owns
    // those rejections, so this journey's report stays free of self-inflicted
    // violations.
    // Operator-set 14-day window: an explicit documented rejection.
    let second: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": card_json }))
        .send()
        .await?
        .json()
        .await?;
    let expired_id = second["data"]["card_id"]
        .as_str()
        .context("second card id")?
        .to_owned();
    ensure!(control.expire_card(&expired_id).await, "expire card");
    let expired: serde_json::Value = client
        .put(format!(
            "{origin}/open-apis/cardkit/v1/cards/{expired_id}/elements/fixture_body/content"
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "content": "late", "sequence": 1 }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(expired["code"] == 200_750, "expired card {expired}");
    let expired_whole: serde_json::Value = client
        .put(format!("{origin}/open-apis/cardkit/v1/cards/{expired_id}"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "card": { "type": "card_json", "data": card_json },
            "sequence": 1
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        expired_whole["code"] == 200_750,
        "expired whole-card {expired_whole}"
    );

    // Synthetic application scope sample: documented not-authorized answer.
    control.set_card_scope_allowed(false).await;
    let denied: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": card_json }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(denied["code"] == 300_311, "card scope {denied}");
    let denied_whole: serde_json::Value = client
        .put(format!("{origin}/open-apis/cardkit/v1/cards/{card_id}"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "card": { "type": "card_json", "data": whole_card },
            "sequence": 9,
            "uuid": "uuid-card-fixture-whole-scope"
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        denied_whole["code"] == 300_311,
        "cross-application whole-card {denied_whole}"
    );
    control.set_card_scope_allowed(true).await;

    // Real encoded entity sizes: the acceptance must not be a scripted code.
    // 30,720 bytes is accepted, one more byte is rejected by the peer itself.
    for (target, expected) in [(30_720usize, 0), (30_721usize, 200_860)] {
        let sized = card_json_with_len(target);
        ensure!(
            sized.len() == target,
            "synthetic card entity must have the exact target length"
        );
        let answer: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": sized }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            answer["code"].as_i64() == Some(expected),
            "entity size {target} expected code {expected}, got {answer}"
        );
    }
    // Official whole-card budget: a nested document of 30,001 bytes is refused,
    // and so is a document whose real request bytes (escaping included) exceed
    // 30,000 even though its entity fits. Neither changes the stored card.
    let sized_card: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": card_json }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(sized_card["code"] == 0, "sized whole card {sized_card}");
    let sized_id = sized_card["data"]["card_id"]
        .as_str()
        .context("sized card id")?
        .to_owned();
    let sized_path = format!("{origin}/open-apis/cardkit/v1/cards/{sized_id}");
    let mut over_entity = card_json_with_len(30_001);
    let over_entity_body = serde_json::json!({
        "card": { "type": "card_json", "data": over_entity },
        "sequence": 1
    });
    let rejected_entity: serde_json::Value = client
        .put(&sized_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&over_entity_body)
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        rejected_entity["code"] == 200_860,
        "over-budget whole-card entity {rejected_entity}"
    );
    // 14,000 quotes escape to a 28 KB entity; nested inside the whole-card body
    // they escape again and push the real request beyond 30,000 bytes.
    over_entity = card_json_with_content(&"\"".repeat(14_000));
    ensure!(
        over_entity.len() <= 30_000,
        "the escaped request sample must still fit the entity budget"
    );
    let escaped_body = serde_json::json!({
        "card": { "type": "card_json", "data": over_entity },
        "sequence": 2
    });
    ensure!(
        serde_json::to_vec(&escaped_body)?.len() > 30_000,
        "the escaped whole-card request must exceed the request budget"
    );
    let rejected_request: serde_json::Value = client
        .put(&sized_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&escaped_body)
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        rejected_request["code"] == 200_860,
        "over-budget whole-card request {rejected_request}"
    );
    let sized_entity = control
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == sized_id)
        .context("sized card entity")?;
    ensure!(
        sized_entity.last_sequence == 0 && sized_entity.whole_card_updates == 0,
        "rejected whole-card requests must not change the stored card"
    );

    // A closed stream rejects further content with the documented code, and a
    // settings reopen is the only bounded way back.
    let scoped: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": card_json }))
        .send()
        .await?
        .json()
        .await?;
    let scoped_id = scoped["data"]["card_id"]
        .as_str()
        .context("stream card id")?
        .to_owned();
    let scoped_path =
        format!("{origin}/open-apis/cardkit/v1/cards/{scoped_id}/elements/fixture_body/content");
    let scoped_settings = format!("{origin}/open-apis/cardkit/v1/cards/{scoped_id}/settings");
    // Scripted stream timeout: the platform closes the stream, the product may
    // reopen it only through the official settings surface.
    control
        .set_card_script(vec![CardDisposition::Reject {
            code: 200_850,
            msg: "stream update timed out".into(),
        }])
        .await;
    let timed_out: serde_json::Value = client
        .put(&scoped_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "content": "timeout", "sequence": 1, "uuid": "uuid-scope-update-1" }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(timed_out["code"] == 200_850, "timeout {timed_out}");
    let still_closed: serde_json::Value = client
        .put(&scoped_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "content": "after timeout", "sequence": 2, "uuid": "uuid-scope-update-2" }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        still_closed["code"] == 300_309,
        "a stream timeout must leave the stream closed, got {still_closed}"
    );
    let reopened: serde_json::Value = client
        .patch(&scoped_settings)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "settings": serde_json::json!({ "config": { "streaming_mode": true } }).to_string(),
            "sequence": 3,
            "uuid": "uuid-scope-reopen-3"
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(reopened["code"] == 0, "reopen {reopened}");
    let continued: serde_json::Value = client
        .put(&scoped_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "content": "continued", "sequence": 4, "uuid": "uuid-scope-update-4" }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(continued["code"] == 0, "continued {continued}");
    let final_close: serde_json::Value = client
        .patch(&scoped_settings)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "settings": serde_json::json!({ "config": { "streaming_mode": false } }).to_string(),
            "sequence": 5,
            "uuid": "uuid-scope-close-5"
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(final_close["code"] == 0, "final close {final_close}");
    // A closed stream rejects further content with the documented code.
    let after_close: serde_json::Value = client
        .put(&scoped_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "content": "after close", "sequence": 6, "uuid": "uuid-scope-update-6" }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        after_close["code"] == 300_309,
        "a closed stream must reject content, got {after_close}"
    );

    // Reopen for the controlled gate lifecycle; the closed-stream fact above is
    // already proven, and content updates require an open stream.
    let reopen_for_gate: serde_json::Value = client
        .patch(&scoped_settings)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "settings": serde_json::json!({ "config": { "streaming_mode": true } }).to_string(),
            "sequence": 7,
            "uuid": "uuid-scope-reopen-7"
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        reopen_for_gate["code"] == 0,
        "gate reopen {reopen_for_gate}"
    );

    // Controlled hang: the gate really blocks the response and the release
    // really completes it; cancelling the client must not poison the gate.
    control.hang_card().await;
    let hung = tokio::spawn({
        let client = client.clone();
        let path = scoped_path.clone();
        async move {
            client
                .put(&path)
                .bearer_auth(TENANT_ACCESS_TOKEN)
                .json(&serde_json::json!({ "content": "hung body", "sequence": 8, "uuid": "uuid-scope-update-8" }))
                .send()
                .await
                .map(|response| response.status().as_u16())
        }
    });
    wait_script_consumed(control, Duration::from_secs(5)).await?;
    ensure!(
        !hung.is_finished(),
        "the armed card gate must really hold the response"
    );
    control.release_card().await;
    let hung_status = tokio::time::timeout(Duration::from_secs(10), hung)
        .await
        .context("the released card request never finished")??;
    ensure!(
        hung_status
            .as_ref()
            .map(|status| *status == 200)
            .unwrap_or(false),
        "the released card request must succeed"
    );
    control.hang_card().await;
    let cancelled = tokio::spawn({
        let client = client.clone();
        let path = scoped_path.clone();
        async move {
            client
                .put(&path)
                .bearer_auth(TENANT_ACCESS_TOKEN)
                .json(&serde_json::json!({ "content": "cancelled body", "sequence": 9, "uuid": "uuid-scope-update-9" }))
                .send()
                .await
                .map(|response| response.status().as_u16())
        }
    });
    wait_script_consumed(control, Duration::from_secs(5)).await?;
    cancel_probe_task(cancelled, "cancelled").await?;
    control.release_card().await;
    http_wait(std::time::Duration::from_millis(200)).await;
    let after_cancel: serde_json::Value = client
        .put(&scoped_path)
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "content": "after cancel", "sequence": 10, "uuid": "uuid-scope-update-10" }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(
        after_cancel["code"] == 0,
        "a cancelled client must not poison the card gate, got {after_cancel}"
    );

    // Unknown update and unknown close: the platform applies the state change,
    // the answer is lost, and the observation keeps that real fact.
    let unknown_card: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": card_json }))
        .send()
        .await?
        .json()
        .await?;
    let unknown_id = unknown_card["data"]["card_id"]
        .as_str()
        .context("unknown card id")?
        .to_owned();
    let unknown_path =
        format!("{origin}/open-apis/cardkit/v1/cards/{unknown_id}/elements/fixture_body/content");
    let unknown_settings = format!("{origin}/open-apis/cardkit/v1/cards/{unknown_id}/settings");
    control
        .set_card_script(vec![CardDisposition::AcceptThenDrop])
        .await;
    let dropped_update = tokio::spawn({
        let client = client.clone();
        let path = unknown_path.clone();
        async move {
            client
                .put(&path)
                .bearer_auth(TENANT_ACCESS_TOKEN)
                .json(&serde_json::json!({ "content": "dropped body", "sequence": 1, "uuid": "uuid-unknown-update" }))
                .send()
                .await
                .map(|response| response.status().as_u16())
        }
    });
    wait_dropped(control, CardOperation::Update).await?;
    cancel_probe_task(dropped_update, "unknown-update").await?;
    control
        .set_card_script(vec![CardDisposition::AcceptThenDrop])
        .await;
    let dropped_close = tokio::spawn({
        let client = client.clone();
        let path = unknown_settings.clone();
        async move {
            client
                .patch(&path)
                .bearer_auth(TENANT_ACCESS_TOKEN)
                .json(&serde_json::json!({
                    "settings": serde_json::json!({ "config": { "streaming_mode": false } }).to_string(),
                    "sequence": 2,
                    "uuid": "uuid-unknown-close"
                }))
                .send()
                .await
                .map(|response| response.status().as_u16())
        }
    });
    wait_dropped(control, CardOperation::Close).await?;
    cancel_probe_task(dropped_close, "unknown-close").await?;
    let unknown_state = control
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == unknown_id)
        .context("unknown update entity")?;
    ensure!(
        unknown_state.content == "dropped body" && unknown_state.streaming_closed,
        "an unconfirmed update/close must still be visible as applied platform state"
    );
    let observations = control.card_observations().await;
    ensure!(
        observations
            .iter()
            .any(|item| item.operation == CardOperation::Update && item.response_dropped),
        "the unconfirmed update must be recorded"
    );
    ensure!(
        observations
            .iter()
            .any(|item| item.operation == CardOperation::Close && item.response_dropped),
        "the unconfirmed close must be recorded"
    );
    control.set_card_script(Vec::new()).await;

    // Full-document evidence: a header and a second element are visible payloads
    // too, so the report must expose the whole card JSON instead of only the
    // selected markdown element.
    let rich = serde_json::json!({
        "schema": "2.0",
        "config": { "streaming_mode": true, "update_multi": true },
        "header": { "title": { "tag": "plain_text", "content": "HEADER_VISIBLE_MARKER" } },
        "body": { "elements": [
            { "tag": "markdown", "element_id": "fixture_body", "content": "selected body" },
            { "tag": "markdown", "element_id": "second_body", "content": "SECOND_ELEMENT_MARKER" }
        ]}
    })
    .to_string();
    let rich_created: serde_json::Value = client
        .post(format!("{origin}/open-apis/cardkit/v1/cards"))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({ "type": "card_json", "data": rich }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(rich_created["code"] == 0, "rich card {rich_created}");
    let rich_id = rich_created["data"]["card_id"]
        .as_str()
        .context("rich card id")?
        .to_owned();
    let rich_entity = control
        .card_entities()
        .await
        .into_iter()
        .find(|entity| entity.card_id == rich_id)
        .context("rich entity")?;
    ensure!(
        rich_entity.entity_json.contains("HEADER_VISIBLE_MARKER")
            && rich_entity.entity_json.contains("SECOND_ELEMENT_MARKER")
            && rich_entity.entity_json.contains("selected body"),
        "the peer report must expose the complete card JSON (header and every element)"
    );

    // Unknown creation: the platform applies the entity, then the answer is
    // lost. The operator never learns a card id, which is exactly the fact the
    // product must keep as unknown instead of retrying.
    control
        .set_card_script(vec![CardDisposition::AcceptThenDrop])
        .await;
    let request_client = client.clone();
    let request_origin = origin.to_owned();
    let request_body = serde_json::json!({ "type": "card_json", "data": card_json });
    let pending = tokio::spawn(async move {
        request_client
            .post(format!("{request_origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&request_body)
            .send()
            .await
            .map(|response| response.status().as_u16())
    });
    let unknown = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let observations = control.card_observations().await;
            if observations
                .iter()
                .any(|item| item.operation == CardOperation::Create && item.response_dropped)
            {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap_or(false);
    cancel_probe_task(pending, "unknown-create").await?;
    ensure!(unknown, "the unconfirmed card creation was never observed");
    let entities = control.card_entities().await;
    ensure!(
        entities
            .iter()
            .any(|entity| entity.sent_message_id.is_none() && entity.updates == 0),
        "an unconfirmed creation must leave one entity without any send identity"
    );
    control.set_card_script(Vec::new()).await;
    Ok(())
}
fn card_json_with_len(target: usize) -> String {
    let skeleton = serde_json::json!({
        "schema": "2.0",
        "config": { "streaming_mode": true, "update_multi": true },
        "body": { "elements": [{ "tag": "markdown", "element_id": "fixture_body", "content": "" }] }
    })
    .to_string();
    let overhead = skeleton.len();
    assert!(target > overhead, "target must exceed the entity skeleton");
    let mut padding = String::new();
    let mut remaining = target - overhead;
    while remaining >= 3 {
        padding.push('中');
        remaining -= 3;
    }
    while remaining > 0 {
        padding.push('a');
        remaining -= 1;
    }
    let sized = serde_json::json!({
        "schema": "2.0",
        "config": { "streaming_mode": true, "update_multi": true },
        "body": { "elements": [{ "tag": "markdown", "element_id": "fixture_body", "content": padding }] }
    })
    .to_string();
    assert_eq!(sized.len(), target, "exact encoded entity length");
    sized
}

/// Card entity with an exact markdown body, used for the update-path size
/// boundary (creation and content update measure the same serialized document).
fn card_json_with_content(content: &str) -> String {
    serde_json::json!({
        "schema": "2.0",
        "config": { "streaming_mode": true, "update_multi": true },
        "body": { "elements": [{ "tag": "markdown", "element_id": "fixture_body", "content": content }] }
    })
    .to_string()
}

async fn http_wait(duration: Duration) {
    tokio::time::sleep(duration).await;
}

async fn wait_script_consumed(control: &super::FeishuControl, budget: Duration) -> Result<()> {
    tokio::time::timeout(budget, async {
        loop {
            if control.pending_card_script().await == 0 {
                return;
            }
            http_wait(Duration::from_millis(10)).await;
        }
    })
    .await
    .context("the scripted card gate was never consumed")?;
    Ok(())
}

/// Waits until the per-card boundary really holds `holders` requests with
/// `waiting` more queued on it. This replaces any arbitrary delay: the released
/// request can only commit after both facts are true.
async fn wait_lock(
    control: &super::FeishuControl,
    card_id: &str,
    holders: usize,
    waiting: usize,
) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let (queued, inside) = control.card_lock_counters(card_id).await;
            if inside == holders && queued >= waiting {
                return;
            }
            http_wait(Duration::from_millis(5)).await;
        }
    })
    .await
    .with_context(|| {
        format!(
            "card {card_id} never reached holders={holders} waiting>={waiting} on its serialization boundary"
        )
    })?;
    Ok(())
}

/// Cancels one probe client task and awaits its real terminal state.
///
/// `abort` is only a request to stop: the probe must still observe the task end
/// (cancelled, or finished with the transport error the peer caused) so a
/// lingering client cannot be reported as "joined".
async fn cancel_probe_task<T>(
    handle: tokio::task::JoinHandle<std::result::Result<T, reqwest::Error>>,
    what: &str,
) -> Result<()> {
    handle.abort();
    let ended = tokio::time::timeout(Duration::from_secs(5), handle)
        .await
        .with_context(|| format!("the {what} client task never terminated after cancel"))?;
    match ended {
        Ok(Ok(_)) | Ok(Err(_)) => Ok(()),
        Err(error) => {
            ensure!(
                error.is_cancelled() || error.is_panic(),
                "the {what} client task ended without a cancelled or failed terminal state"
            );
            Ok(())
        }
    }
}

async fn wait_dropped(control: &super::FeishuControl, operation: CardOperation) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if control
                .card_observations()
                .await
                .iter()
                .any(|item| item.operation == operation && item.response_dropped)
            {
                return;
            }
            http_wait(Duration::from_millis(10)).await;
        }
    })
    .await
    .with_context(|| format!("the unconfirmed {operation:?} was never observed"))?;
    Ok(())
}

/// Peer-state invariants that require deliberate protocol abuse, on their own
/// peer instance: sequence interleaving, uuid identity, encoded-size accounting
/// and the documented per-chat send rate. The report of this instance is
/// expected to be incomplete; only the expected facts are asserted.
pub(super) async fn observe_card_protocol_invariants() -> Result<()> {
    let mut peer = FeishuPeer::start().await?;
    let drive = async {
        let origin = peer.origin().to_owned();
        let control = peer.control();
        let client = observe_http_client()?;
        let card_json = card_json_with_len(2_048);
        let created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": card_json }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(created["code"] == 0, "create {created}");
        let card_id = created["data"]["card_id"]
            .as_str()
            .context("card id")?
            .to_owned();
        let content_path =
            format!("{origin}/open-apis/cardkit/v1/cards/{card_id}/elements/fixture_body/content");

        // Whole-card document validation answers are documented codes, but a
        // reused sequence or a non-conforming JSON 2.0 document is still a wire
        // violation of the official contract. The observer keeps these probes on
        // this peer, whose report explicitly owns the rejections, and never on
        // the accepted journey peer.
        let whole_entity = |entities: Vec<super::CardEntityReport>, id: &str| {
            entities
                .into_iter()
                .find(|entity| entity.card_id == id)
                .map(|entity| {
                    (
                        entity.entity_json,
                        entity.last_sequence,
                        entity.whole_card_updates,
                    )
                })
        };
        let whole_card_json = card_json_with_len(1_024);
        let whole_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": whole_card_json }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            whole_created["code"] == 0,
            "invariant whole card {whole_created}"
        );
        let whole_id = whole_created["data"]["card_id"]
            .as_str()
            .context("invariant whole card id")?
            .to_owned();
        let whole_path = format!("{origin}/open-apis/cardkit/v1/cards/{whole_id}");
        let first_whole: serde_json::Value = client
            .put(&whole_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "card": { "type": "card_json", "data": whole_card_json },
                "sequence": 1,
                "uuid": "uuid-invariant-whole-first"
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            first_whole["code"] == 0,
            "invariant first whole card {first_whole}"
        );
        let whole_before = whole_entity(control.card_entities().await, &whole_id)
            .context("invariant whole entity before the rejections")?;
        let repeated_whole: serde_json::Value = client
            .put(&whole_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "card": { "type": "card_json", "data": whole_card_json },
                "sequence": 1,
                "uuid": "uuid-invariant-whole-repeat"
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            repeated_whole["code"] == 300_317,
            "a reused whole-card sequence must be rejected {repeated_whole}"
        );
        let invalid_document = serde_json::json!({
            "schema": "2.0",
            "config": { "streaming_mode": true, "update_multi": false },
            "body": { "elements": [{ "tag": "markdown", "element_id": "fixture_body", "content": "x" }] }
        })
        .to_string();
        let invalid_whole: serde_json::Value = client
            .put(&whole_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "card": { "type": "card_json", "data": invalid_document },
                "sequence": 2
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            invalid_whole["code"] == 232_001,
            "update_multi=false must be rejected on a whole-card update {invalid_whole}"
        );
        let whole_after = whole_entity(control.card_entities().await, &whole_id)
            .context("invariant whole entity after the rejections")?;
        ensure!(
            whole_after == whole_before,
            "rejected whole-card requests must not change the stored card, {whole_before:?} -> {whole_after:?}"
        );

        // Two writers, newest first: the older sequence must be rejected, and
        // the final state must be the accepted newer body.
        control.hang_card().await;
        let newer = tokio::spawn({
            let client = client.clone();
            let path = content_path.clone();
            async move {
                let response = client
                    .put(&path)
                    .bearer_auth(TENANT_ACCESS_TOKEN)
                    .json(&serde_json::json!({ "content": "newer body", "sequence": 2, "uuid": "uuid-interleave-2" }))
                    .send()
                    .await?;
                response.json::<serde_json::Value>().await
            }
        });
        wait_script_consumed(&control, Duration::from_secs(5)).await?;
        wait_lock(&control, &card_id, 1, 0).await?;
        let older = tokio::spawn({
            let client = client.clone();
            let path = content_path.clone();
            async move {
                let response = client
                    .put(&path)
                    .bearer_auth(TENANT_ACCESS_TOKEN)
                    .json(&serde_json::json!({ "content": "older body", "sequence": 1, "uuid": "uuid-interleave-1" }))
                    .send()
                    .await?;
                response.json::<serde_json::Value>().await
            }
        });
        wait_lock(&control, &card_id, 1, 1).await?;
        control.release_card().await;
        let newer_body = tokio::time::timeout(Duration::from_secs(10), newer)
            .await
            .context("the hung update never finished")???;
        let older_body = tokio::time::timeout(Duration::from_secs(10), older)
            .await
            .context("the queued older update never finished")???;
        ensure!(newer_body["code"] == 0, "newer update {newer_body}");
        ensure!(
            older_body["code"] == 300_317,
            "an older sequence must be rejected after the newer commit, got {older_body}"
        );
        let entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == card_id)
            .context("interleaved entity")?;
        ensure!(
            entity.content == "newer body" && entity.last_sequence == 2,
            "the committed body must be the newer one, got content={:?} sequence={}",
            entity.content,
            entity.last_sequence
        );

        // Same identity and payload: applied once, answered twice.
        let first: serde_json::Value = client
            .put(&content_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "content": "third body", "sequence": 3, "uuid": "uuid-replay-3" }))
            .send()
            .await?
            .json()
            .await?;
        let replay: serde_json::Value = client
            .put(&content_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "content": "third body", "sequence": 3, "uuid": "uuid-replay-3" }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            first["code"] == 0 && replay["code"] == 0,
            "replay must succeed"
        );
        let entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == card_id)
            .context("replayed entity")?;
        ensure!(
            entity.updates == 2,
            "an idempotent replay must not count as another update (updates={})",
            entity.updates
        );
        // Same identity, another payload: documented conflict, no state change.
        let conflict: serde_json::Value = client
            .put(&content_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "content": "different body", "sequence": 4, "uuid": "uuid-replay-3" }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(conflict["code"] == 200_770, "uuid conflict {conflict}");
        let entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == card_id)
            .context("conflicted entity")?;
        ensure!(
            entity.content == "third body" && entity.last_sequence == 3,
            "a uuid conflict must not change the card"
        );

        // One uuid, two different cards, two concurrent writers. The fixture's own
        // stop point parks both *after* their uuid pre-check and *before* the effect
        // commit, so the claim itself is what decides the interleaving.
        let second_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": card_json_with_len(2_048) }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            second_created["code"] == 0,
            "second create {second_created}"
        );
        let second_id = second_created["data"]["card_id"]
            .as_str()
            .context("second card id")?
            .to_owned();
        let second_path = format!(
            "{origin}/open-apis/cardkit/v1/cards/{second_id}/elements/fixture_body/content"
        );
        let entity_body = |entities: Vec<super::CardEntityReport>, id: &str| {
            entities
                .into_iter()
                .find(|entity| entity.card_id == id)
                .map(|entity| (entity.content, entity.last_sequence))
        };
        let shared_uuid = "uuid-cross-card-shared";

        // A released-before-await gate must never park: release is a sticky value.
        let sticky = control.arm_card_precommit_gate().await;
        sticky.release_all();
        ensure!(sticky.released(), "releasing the gate must be observable");
        control.disarm_card_precommit_gate().await;
        let sticky_body: serde_json::Value = client
            .put(&content_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "content": "released before await",
                "sequence": 5,
                "uuid": "uuid-released-before-await",
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            sticky_body["code"] == 0,
            "a gate released before the request arrived must not park it, got {sticky_body}"
        );

        // Snapshot both cards right before the race (the sticky check above wrote).
        let first_before = entity_body(control.card_entities().await, &card_id)
            .context("first card before the shared uuid race")?;
        let second_before = entity_body(control.card_entities().await, &second_id)
            .context("second card before the shared uuid race")?;

        // Both writers live in one JoinSet: every failure path aborts and drains both.
        let gate = control.arm_card_precommit_gate().await;
        let mut writers: tokio::task::JoinSet<(
            String,
            std::result::Result<serde_json::Value, reqwest::Error>,
        )> = tokio::task::JoinSet::new();
        for (card, path, content) in [
            ("first", content_path.clone(), "cross card A body"),
            ("second", second_path.clone(), "cross card B body"),
        ] {
            let client = client.clone();
            writers.spawn(async move {
                let outcome = async {
                    client
                        .put(&path)
                        .bearer_auth(TENANT_ACCESS_TOKEN)
                        .json(&serde_json::json!({
                            "content": content,
                            "sequence": if card == "first" { 6 } else { 1 },
                            "uuid": shared_uuid,
                        }))
                        .send()
                        .await?
                        .json::<serde_json::Value>()
                        .await
                }
                .await;
                (card.to_owned(), outcome)
            });
        }
        let parked = tokio::time::timeout(Duration::from_secs(10), gate.wait_parked(2)).await;
        // Disarm first: no later request may join the stop point.
        control.disarm_card_precommit_gate().await;
        gate.release_all();
        if parked.is_err() {
            writers.abort_all();
            while writers.join_next().await.is_some() {}
            anyhow::bail!("both cross-card writers must reach the pre-commit stop point");
        }
        let mut results: Vec<(String, serde_json::Value)> = Vec::new();
        let mut failure: Option<anyhow::Error> = None;
        while let Some(joined) = writers.join_next().await {
            match joined {
                Ok((card, Ok(body))) => results.push((card, body)),
                Ok((card, Err(error))) => {
                    failure.get_or_insert_with(|| {
                        anyhow::anyhow!("the {card} cross-card writer failed: {error}")
                    });
                }
                Err(error) => {
                    failure.get_or_insert_with(|| {
                        anyhow::anyhow!("a cross-card writer task did not finish: {error}")
                    });
                }
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        ensure!(
            results.len() == 2,
            "both cross-card writers must report one result each, got {}",
            results.len()
        );
        let code_of = |card: &str| {
            results
                .iter()
                .find(|(name, _)| name == card)
                .and_then(|(_, body)| body["code"].as_i64())
        };
        let (first_code, second_code) = (code_of("first"), code_of("second"));
        ensure!(
            first_code == Some(0) && second_code == Some(200_770)
                || first_code == Some(200_770) && second_code == Some(0),
            "one uuid on two cards must apply exactly once and conflict once, got [{first_code:?}, {second_code:?}]"
        );
        let first_after = entity_body(control.card_entities().await, &card_id)
            .context("cross-card first entity")?;
        let second_after = entity_body(control.card_entities().await, &second_id)
            .context("cross-card second entity")?;
        if first_code == Some(200_770) {
            ensure!(
                first_after == first_before,
                "the rejected first card must keep its committed body, {:?} -> {:?}",
                first_before,
                first_after
            );
            ensure!(
                second_after.0 == "cross card B body",
                "the applied second card must hold the new body"
            );
        } else {
            ensure!(
                second_after == second_before,
                "the rejected second card must keep its created body, {:?} -> {:?}",
                second_before,
                second_after
            );
            ensure!(
                first_after.0 == "cross card A body",
                "the applied first card must hold the new body"
            );
        }

        // Cancellation-safe queue registration: a request cancelled while it is
        // queued must release its `waiting` registration, and the next request
        // must still be served. The server-side handler is ended by the private
        // abort generation, not by assuming a client abort cancels it.
        let cancel_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": card_json_with_len(2_048) }))
            .send()
            .await?
            .json()
            .await?;
        let cancel_id = cancel_created["data"]["card_id"]
            .as_str()
            .context("cancel card id")?
            .to_owned();
        let cancel_path = format!(
            "{origin}/open-apis/cardkit/v1/cards/{cancel_id}/elements/fixture_body/content"
        );
        control.hang_card().await;
        let holder = tokio::spawn({
            let client = client.clone();
            let path = cancel_path.clone();
            async move {
                let response = client
                    .put(&path)
                    .bearer_auth(TENANT_ACCESS_TOKEN)
                    .json(&serde_json::json!({ "content": "holder", "sequence": 1, "uuid": "uuid-cancel-holder" }))
                    .send()
                    .await?;
                response.json::<serde_json::Value>().await
            }
        });
        wait_script_consumed(&control, Duration::from_secs(5)).await?;
        wait_lock(&control, &cancel_id, 1, 0).await?;
        let queued = tokio::spawn({
            let client = client.clone();
            let path = cancel_path.clone();
            async move {
                let response = client
                    .put(&path)
                    .bearer_auth(TENANT_ACCESS_TOKEN)
                    .json(&serde_json::json!({ "content": "queued", "sequence": 2, "uuid": "uuid-cancel-queued" }))
                    .send()
                    .await?;
                let body = response.bytes().await?;
                Ok::<_, anyhow::Error>(body.is_empty())
            }
        });
        wait_lock(&control, &cancel_id, 1, 1).await?;
        control.cancel_card_waiters(&cancel_id).await;
        wait_lock(&control, &cancel_id, 1, 0).await?;
        let queued_ended_empty = tokio::time::timeout(Duration::from_secs(10), queued)
            .await
            .context("the cancelled queue entry never ended")???;
        ensure!(
            queued_ended_empty,
            "a request cancelled while queued must end with an empty response"
        );
        control.release_card().await;
        let holder_body = tokio::time::timeout(Duration::from_secs(10), holder)
            .await
            .context("the holder never finished")???;
        ensure!(holder_body["code"] == 0, "holder update {holder_body}");
        let after_cancel: serde_json::Value = client
            .put(&cancel_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "content": "after cancel", "sequence": 2, "uuid": "uuid-cancel-after" }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            after_cancel["code"] == 0,
            "a cancelled queue entry must not poison the boundary, got {after_cancel}"
        );
        wait_lock(&control, &cancel_id, 0, 0).await?;

        // Encoded request accounting: 16,000 quotes are far below 30 KB raw but
        // exceed it once JSON-escaped.
        let escaped_text = "\"".repeat(16_000);
        let escaped: serde_json::Value = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "receive_id": GROUP_CHAT_ID,
                "msg_type": "post",
                "content": serde_json::json!({
                    "zh_cn": { "content": [[{ "tag": "md", "text": escaped_text }]] }
                }).to_string()
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            escaped["code"] == 230_025,
            "the escaped request must be rejected by real encoded size, got {escaped}"
        );

        // Creation-side boundary for the *content update* path: the same
        // serialized document is measured, so 30,720 bytes pass and one more
        // byte is refused with the documented code on the observation itself.
        let base_json = card_json_with_content("");
        let base_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": base_json }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(base_created["code"] == 0, "base card {base_created}");
        let base_id = base_created["data"]["card_id"]
            .as_str()
            .context("base card id")?
            .to_owned();
        let base_entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == base_id)
            .context("base entity")?;
        let base_bytes = base_entity.entity_bytes;
        let base_path =
            format!("{origin}/open-apis/cardkit/v1/cards/{base_id}/elements/fixture_body/content");
        let pass_len = 30_720 - base_bytes;
        let pass: serde_json::Value = client
            .put(&base_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "content": "a".repeat(pass_len),
                "sequence": 1,
                "uuid": "uuid-size-pass-1"
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(pass["code"] == 0, "exact-limit update must pass: {pass}");
        let base_entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == base_id)
            .context("base entity after pass")?;
        ensure!(
            base_entity.entity_bytes == 30_720,
            "the accepted update must hold exactly 30,720 bytes, got {}",
            base_entity.entity_bytes
        );
        let fail: serde_json::Value = client
            .put(&base_path)
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "content": "a".repeat(pass_len + 1),
                "sequence": 2,
                "uuid": "uuid-size-fail-2"
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            fail["code"] == 200_860,
            "one byte over the limit must be refused: {fail}"
        );
        let fail_observation = control
            .card_observations()
            .await
            .into_iter()
            .find(|item| {
                item.card_id == base_id
                    && item.operation == CardOperation::Update
                    && item.uuid.as_deref() == Some("uuid-size-fail-2")
            })
            .context("the refused size update observation")?;
        ensure!(
            !fail_observation.accepted && fail_observation.code == 200_860,
            "a refused update must record its real business code, got accepted={} code={}",
            fail_observation.accepted,
            fail_observation.code
        );
        let base_entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == base_id)
            .context("base entity after refusal")?;
        ensure!(
            base_entity.entity_bytes == 30_720 && base_entity.last_sequence == 1,
            "a refused oversize update must not change the held body"
        );

        // One entity, one published message: two different identities racing on
        // the same card must produce exactly one platform message and one side
        // effect. Both requests are held at the per-card boundary first, so the
        // outcome never depends on timing.
        let race_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": card_json_with_len(2_048) }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(race_created["code"] == 0, "race card {race_created}");
        let race_id = race_created["data"]["card_id"]
            .as_str()
            .context("race card id")?
            .to_owned();
        let race_body = serde_json::json!({
            "receive_id": GROUP_CHAT_ID,
            "msg_type": "interactive",
            "content": serde_json::json!({ "type": "card", "data": { "card_id": race_id } }).to_string(),
        });
        control.hang_send().await;
        let first_send = tokio::spawn({
            let client = client.clone();
            let origin = origin.to_owned();
            let mut body = race_body.clone();
            body["uuid"] = serde_json::json!("uuid-race-first");
            async move {
                let response = client
                    .post(format!(
                        "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
                    ))
                    .bearer_auth(TENANT_ACCESS_TOKEN)
                    .json(&body)
                    .send()
                    .await?;
                response.json::<serde_json::Value>().await
            }
        });
        wait_lock(&control, &race_id, 1, 0).await?;
        let second_send = tokio::spawn({
            let client = client.clone();
            let origin = origin.to_owned();
            let mut body = race_body.clone();
            body["uuid"] = serde_json::json!("uuid-race-second");
            async move {
                let response = client
                    .post(format!(
                        "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
                    ))
                    .bearer_auth(TENANT_ACCESS_TOKEN)
                    .json(&body)
                    .send()
                    .await?;
                response.json::<serde_json::Value>().await
            }
        });
        wait_lock(&control, &race_id, 1, 1).await?;
        control.release_send().await;
        let first = tokio::time::timeout(Duration::from_secs(10), first_send)
            .await
            .context("the held send never finished")???;
        let second = tokio::time::timeout(Duration::from_secs(10), second_send)
            .await
            .context("the queued send never finished")???;
        ensure!(first["code"] == 0, "first send {first}");
        ensure!(
            second["code"] == 232_009,
            "the second identity must be refused, got {second}"
        );
        let race_entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == race_id)
            .context("race entity")?;
        let race_sends: Vec<_> = control
            .card_observations()
            .await
            .into_iter()
            .filter(|item| item.card_id == race_id && item.operation == CardOperation::Send)
            .collect();
        ensure!(
            race_sends.len() == 1 && race_entity.sent_uuid.as_deref() == Some("uuid-race-first"),
            "two racing identities must leave exactly one published message, got {} observations",
            race_sends.len()
        );
        ensure!(
            race_entity.sent_message_id.is_some(),
            "the published entity must keep its single message id"
        );
        // The identical complete request retried: same message id, no new side
        // effect, and the observation records the replay.
        let mut retry_body = race_body.clone();
        retry_body["uuid"] = serde_json::json!("uuid-race-first");
        let retry: serde_json::Value = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&retry_body)
            .send()
            .await?
            .json()
            .await?;
        ensure!(retry["code"] == 0, "uuid retry must succeed: {retry}");
        ensure!(
            retry["data"]["message_id"] == race_entity.sent_message_id.clone().unwrap_or_default(),
            "a retried complete request must answer the same message id"
        );
        let race_sends_after: Vec<_> = control
            .card_observations()
            .await
            .into_iter()
            .filter(|item| item.card_id == race_id && item.operation == CardOperation::Send)
            .collect();
        ensure!(
            race_sends_after.len() == 1,
            "the uuid retry must not add another send side effect, got {}",
            race_sends_after.len()
        );
        let race_entity_after = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == race_id)
            .context("race entity after retry")?;
        ensure!(
            race_entity_after.sent_message_id == race_entity.sent_message_id,
            "the retried request must keep the original message id"
        );

        // Mutation requests must be refused without touching the published
        // facts: another chat or another body with the same uuid is a conflict.
        let mut other_chat = retry_body.clone();
        other_chat["receive_id"] = serde_json::json!(DIRECT_CHAT_ID);
        let chat_conflict: serde_json::Value = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&other_chat)
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            chat_conflict["code"] == 232_010,
            "the same uuid for another chat must be refused, got {chat_conflict}"
        );
        let mut other_body = retry_body.clone();
        other_body["content"] = serde_json::json!(
            serde_json::json!({
                "type": "card",
                "data": { "card_id": race_id, "mutated": true }
            })
            .to_string()
        );
        let body_conflict: serde_json::Value = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&other_body)
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            body_conflict["code"] == 232_010,
            "the same uuid for another body must be refused, got {body_conflict}"
        );
        let race_entity_after_mutations = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == race_id)
            .context("race entity after mutations")?;
        ensure!(
            race_entity_after_mutations.sent_message_id == race_entity.sent_message_id,
            "mutation requests must not change the published message identity"
        );

        // Observation contract: an interactive publish needs a stable uuid, so a
        // request without one is refused and leaves no published message.
        let uuidless_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": card_json_with_len(2_048) }))
            .send()
            .await?
            .json()
            .await?;
        let uuidless_id = uuidless_created["data"]["card_id"]
            .as_str()
            .context("uuidless card id")?
            .to_owned();
        let uuidless: serde_json::Value = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({
                "receive_id": GROUP_CHAT_ID,
                "msg_type": "interactive",
                "content": serde_json::json!({ "type": "card", "data": { "card_id": uuidless_id } }).to_string()
            }))
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            uuidless["code"] == 232_001,
            "an interactive send without a stable uuid must be refused, got {uuidless}"
        );
        let uuidless_entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == uuidless_id)
            .context("uuidless entity")?;
        ensure!(
            uuidless_entity.sent_message_id.is_none(),
            "a refused uuid-less publish must not bind any message"
        );

        // An unknown IM result (applied, answer lost) also binds the message
        // identity: the identical retry replays it and adds no side effect.
        let unknown_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": card_json_with_len(2_048) }))
            .send()
            .await?
            .json()
            .await?;
        let unknown_card = unknown_created["data"]["card_id"]
            .as_str()
            .context("unknown card id")?
            .to_owned();
        let unknown_body = serde_json::json!({
            "receive_id": GROUP_CHAT_ID,
            "msg_type": "interactive",
            "content": serde_json::json!({ "type": "card", "data": { "card_id": unknown_card } }).to_string(),
            "uuid": "uuid-unknown-send"
        });
        control
            .set_send_script(vec![super::SendDisposition::AcceptThenDrop])
            .await;
        let dropped = tokio::spawn({
            let client = client.clone();
            let origin = origin.to_owned();
            let body = unknown_body.clone();
            async move {
                let _ = client
                    .post(format!(
                        "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
                    ))
                    .bearer_auth(TENANT_ACCESS_TOKEN)
                    .json(&body)
                    .send()
                    .await;
            }
        });
        wait_dropped(&control, CardOperation::Send).await?;
        dropped.abort();
        control
            .set_send_script(vec![super::SendDisposition::Succeed])
            .await;
        let unknown_replay: serde_json::Value = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&unknown_body)
            .send()
            .await?
            .json()
            .await?;
        ensure!(
            unknown_replay["code"] == 0,
            "the identical retry of an unknown publish must replay, got {unknown_replay}"
        );
        let unknown_entity = control
            .card_entities()
            .await
            .into_iter()
            .find(|entity| entity.card_id == unknown_card)
            .context("unknown entity")?;
        ensure!(
            unknown_entity.sent_message_id.is_some()
                && unknown_replay["data"]["message_id"]
                    == unknown_entity.sent_message_id.clone().unwrap_or_default(),
            "the unknown publish must keep exactly one message identity"
        );
        let unknown_send_observations = control
            .card_observations()
            .await
            .into_iter()
            .filter(|item| item.card_id == unknown_card && item.operation == CardOperation::Send)
            .count();
        ensure!(
            unknown_send_observations == 1,
            "replaying an unknown publish must not add a send side effect"
        );

        // Card A retry and card B real send concurrently: the deduplication fact
        // must land on the exact call it belongs to, never on "the last record".
        let other_created: serde_json::Value = client
            .post(format!("{origin}/open-apis/cardkit/v1/cards"))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&serde_json::json!({ "type": "card_json", "data": card_json_with_len(2_048) }))
            .send()
            .await?
            .json()
            .await?;
        let other_card = other_created["data"]["card_id"]
            .as_str()
            .context("other card id")?
            .to_owned();
        let other_body = serde_json::json!({
            "receive_id": GROUP_CHAT_ID,
            "msg_type": "interactive",
            "content": serde_json::json!({ "type": "card", "data": { "card_id": other_card } }).to_string(),
            "uuid": "uuid-other-real-send"
        });
        let dedup_before = peer
            .control()
            .snapshot_report()
            .await
            .calls
            .iter()
            .filter(|call| call.deduplicated)
            .count();
        let replay_request = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&retry_body)
            .send();
        let real_request = client
            .post(format!(
                "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
            ))
            .bearer_auth(TENANT_ACCESS_TOKEN)
            .json(&other_body)
            .send();
        let (replay_answer, real_answer) = tokio::join!(replay_request, real_request);
        let replay_answer: serde_json::Value = replay_answer?.json().await?;
        let real_answer: serde_json::Value = real_answer?.json().await?;
        ensure!(
            replay_answer["code"] == 0 && real_answer["code"] == 0,
            "both concurrent requests must be answered: replay={replay_answer} real={real_answer}"
        );
        let calls = peer.control().snapshot_report().await.calls;
        let dedup_calls: Vec<_> = calls.iter().filter(|call| call.deduplicated).collect();
        ensure!(
            dedup_calls.len() == dedup_before + 1,
            "the concurrent pair must add exactly one deduplicated replay, got {} (before {dedup_before})",
            dedup_calls.len()
        );
        let added = dedup_calls.last().context("the concurrent replay call")?;
        ensure!(
            added.assigned_message_id.as_deref() == race_entity.sent_message_id.as_deref()
                && added.card_id.as_deref() == Some(race_id.as_str()),
            "the deduplicated fact must belong to the replayed message identity"
        );
        let real_call = calls
            .iter()
            .find(|call| {
                call.assigned_message_id.as_deref() == real_answer["data"]["message_id"].as_str()
            })
            .context("the real send call")?;
        ensure!(
            !real_call.deduplicated && real_call.card_id.as_deref() == Some(other_card.as_str()),
            "a real concurrent send must never inherit the deduplicated fact"
        );

        // Documented per-chat limit: five accepted sends are fine, six are not.
        // The boundary uses a target no earlier probe has written to.
        for _ in 0..5 {
            send_markdown(
                &client,
                &origin,
                PAIRING_DIRECT_CHAT_ID,
                "rate limit sample",
            )
            .await?;
        }
        let five = peer.control().snapshot_report().await;
        ensure!(
            !five.violations.iter().any(|item| item.contains("five")),
            "five sends within a second must not violate the rate limit: {:?}",
            five.violations
        );
        // Another target is independent.
        send_markdown(&client, &origin, GROUP_CHAT_ID, "rate limit sample").await?;
        let isolated = peer.control().snapshot_report().await;
        ensure!(
            !isolated.violations.iter().any(|item| item.contains("five")),
            "a send to another chat must not count against the first target: {:?}",
            isolated.violations
        );
        send_markdown(
            &client,
            &origin,
            PAIRING_DIRECT_CHAT_ID,
            "rate limit sample",
        )
        .await?;
        let six = peer.control().snapshot_report().await;
        ensure!(
            six.violations
                .iter()
                .any(|item| item.contains("five") && item.contains(PAIRING_DIRECT_CHAT_ID)),
            "six sends within a second must violate the documented limit: {:?}",
            six.violations
        );
        ensure!(
            !six.violations
                .iter()
                .any(|item| item.contains("five") && item.contains(GROUP_CHAT_ID)),
            "the other target must not be blamed: {:?}",
            six.violations
        );
        Ok::<(), anyhow::Error>(())
    };
    let drive_result = drive.await;
    let report = peer.shutdown().await?;
    drive_result?;
    ensure!(
        report.listener_joined && report.sockets_joined,
        "the invariant peer must still join its resources"
    );
    ensure!(
        report
            .violations
            .iter()
            .any(|item| item.contains("sequence")),
        "the stale-sequence attempts must be recorded as violations: {:?}",
        report.violations
    );
    ensure!(
        report
            .violations
            .iter()
            .any(|item| item.contains("update_multi")),
        "the invalid whole-card document must be recorded as a violation: {:?}",
        report.violations
    );
    println!(
        "feishu_card_invariants: stale_sequence=300317 double_send=one_id/one_side_effect \
         send_identity=mutation-refused/missing-uuid-refused/unknown-replay-one_id \
         dedup_flag=exact-call wait_cancel=released/next-ok uuid_retry=same_id uuid_conflict=200770 \
         update_size=30720-pass/30721-200860 whole_card=300317-sequence/232001-update_multi/entity-unchanged \
         qps=5-ok/6-violation target_isolation=ok join=ok"
    );
    Ok(())
}

async fn send_markdown(
    client: &Client,
    origin: &str,
    chat_id: &str,
    text: &str,
) -> Result<serde_json::Value> {
    let answer: serde_json::Value = client
        .post(format!(
            "{origin}/open-apis/im/v1/messages?receive_id_type=chat_id"
        ))
        .bearer_auth(TENANT_ACCESS_TOKEN)
        .json(&serde_json::json!({
            "receive_id": chat_id,
            "msg_type": "post",
            "content": serde_json::json!({
                "zh_cn": { "content": [[{ "tag": "md", "text": text }]] }
            }).to_string()
        }))
        .send()
        .await?
        .json()
        .await?;
    ensure!(answer["code"] == 0, "markdown send {answer}");
    Ok(answer)
}
