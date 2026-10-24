use super::super::Session;
use super::{requests, write_json};
use crate::{http, sqlite};
use anyhow::{Context, Result, ensure};
use pl_protocol::studio::SetBotTrustedChatRequest;
use pl_provider_fixture::{
    bots_observe as model,
    feishu::{
        BOT_OPEN_ID, ChatType, DIRECT_CHAT_ID, GROUP_CHAT_ID, PAIRING_DIRECT_CHAT_ID, SenderKind,
        TRUSTED_USER_OPEN_ID, UNKNOWN_USER_OPEN_ID, text_event, trusted_user_mention,
    },
};
use std::collections::BTreeSet;

pub(super) async fn run(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let (bot_id, _) = session.ensure_trusted_direct().await?;
    session.wait_connected(&bot_id).await?;
    let bot = session.bot(&bot_id).await?;
    session
        .http()?
        .set_trusted_chat(&SetBotTrustedChatRequest {
            operation_id: "isolation-trust-group".into(),
            bot_id: bot_id.clone(),
            expected_config_revision: bot.config_revision,
            chat_id: GROUP_CHAT_ID.into(),
            trusted: true,
        })
        .await?;
    session.wait_connected(&bot_id).await?;

    // Unauthorized DM and group without a real mention are followed by a
    // positive event on the same socket. ACK alone is never our model oracle.
    for event in [
        text_event(
            "om_iso_untrusted",
            "oc_anywork_fixture_unknown_dm",
            ChatType::P2p,
            SenderKind::User,
            UNKNOWN_USER_OPEN_ID,
            "isolation unauthorized must never execute",
            vec![],
        ),
        text_event(
            "om_iso_no_mention",
            GROUP_CHAT_ID,
            ChatType::Group,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            "isolation @bot plain text must never execute",
            vec![],
        ),
        text_event(
            "om_iso_untrusted_group",
            "oc_anywork_fixture_untrusted_group",
            ChatType::Group,
            SenderKind::User,
            TRUSTED_USER_OPEN_ID,
            "isolation untrusted group must never execute",
            vec![trusted_user_mention(BOT_OPEN_ID)],
        ),
    ] {
        session.control()?.send_event(event).await?;
    }

    let journeys = [
        (
            "om_iso_a",
            DIRECT_CHAT_ID,
            ChatType::P2p,
            TRUSTED_USER_OPEN_ID,
        ),
        (
            "om_iso_b",
            PAIRING_DIRECT_CHAT_ID,
            ChatType::P2p,
            TRUSTED_USER_OPEN_ID,
        ),
        (
            "om_iso_group_first",
            GROUP_CHAT_ID,
            ChatType::Group,
            TRUSTED_USER_OPEN_ID,
        ),
        (
            "om_iso_group_second",
            GROUP_CHAT_ID,
            ChatType::Group,
            UNKNOWN_USER_OPEN_ID,
        ),
        (
            "om_iso_a_follow",
            DIRECT_CHAT_ID,
            ChatType::P2p,
            TRUSTED_USER_OPEN_ID,
        ),
    ];
    for (index, ((message_id, chat_id, kind, sender), prompt)) in
        journeys.into_iter().zip(model::CHAT_PROMPTS).enumerate()
    {
        let event = text_event(
            message_id,
            chat_id,
            kind,
            SenderKind::User,
            sender,
            prompt,
            if kind == ChatType::Group {
                vec![trusted_user_mention(BOT_OPEN_ID)]
            } else {
                vec![]
            },
        );
        session.control()?.send_event(event.clone()).await?;
        session.wait_inbound_completed(&bot_id, message_id).await?;
        requests::wait_executions(session, index + 1).await?;
        // Replay the already completed identity. The next positive input plus
        // strict script closure exposes any duplicate model attempt.
        session.control()?.send_event(event).await?;
        evidence.push(format!(
            "completed {message_id}: chat={chat_id} sender={sender}"
        ));
    }
    let rows = sqlite::thread_bindings(&session.home, &bot_id).await?;
    ensure!(
        rows.len() == 3,
        "expected exactly three chat bindings, got {rows:?}"
    );
    let threads: BTreeSet<_> = rows.iter().map(|row| row.thread_id.as_str()).collect();
    ensure!(
        threads.len() == 3 && rows.iter().all(|row| row.status == "bound"),
        "chat bindings are not three distinct bound Threads: {rows:?}"
    );
    ensure!(
        rows.iter()
            .map(|row| row.chat_id.as_str())
            .collect::<BTreeSet<_>>()
            == BTreeSet::from([DIRECT_CHAT_ID, PAIRING_DIRECT_CHAT_ID, GROUP_CHAT_ID]),
        "an unauthorized chat acquired a Thread"
    );
    for row in &rows {
        evidence.push(format!(
            "DB chat={} thread={} creation={} status={}",
            row.chat_id, row.thread_id, row.creation_id, row.status
        ));
    }
    let inbound = sqlite::inbound(&session.home, &bot_id).await?;
    for (message_id, _, _, _) in journeys {
        ensure!(
            inbound
                .iter()
                .filter(|row| row.message_id == message_id && row.status == "completed")
                .count()
                == 1,
            "duplicate message has multiple or incomplete inbound identities: {message_id}"
        );
    }
    let requests = requests::execution_requests(session);
    ensure!(
        requests.len() == 5,
        "unauthorized or duplicated events reached the model: {}",
        requests.len()
    );
    for (index, request) in requests.iter().enumerate() {
        let text = requests::user_texts(request)?.join("\n");
        let allowed: &[usize] = match index {
            0 => &[0],
            1 => &[1],
            2 => &[2],
            3 => &[2, 3],
            _ => &[0, 4],
        };
        for (other, marker) in model::CHAT_PROMPTS.iter().enumerate() {
            ensure!(
                text.contains(marker) == allowed.contains(&other),
                "request {index} lost its own context or mixed another chat's marker {other}"
            );
        }
        ensure!(
            !text.contains("must never execute"),
            "an untrusted source reached model context"
        );
    }
    let status = session
        .model
        .as_ref()
        .context("model missing")?
        .live_status();
    ensure!(
        status.rejected == 0 && status.remaining_optional,
        "strict isolation script is incomplete: {status:?}"
    );
    write_json(
        session,
        "isolation-bindings.json",
        &rows
            .iter()
            .map(|row| (&row.chat_id, &row.thread_id, &row.status, &row.creation_id))
            .collect::<Vec<_>>(),
    )?;
    // Explicitly check the final duplicate's ACK and durable identities after
    // all five completions, not only the peer's websocket write count.
    http::wait_until(http::ACK_BUDGET, || async {
        Ok(session.ack_count().await? >= 13)
    })
    .await?;
    ensure!(
        requests::execution_requests(session).len() == 5,
        "last duplicate reached the model"
    );
    Ok("two p2p chats and one authorized group kept three distinct Threads; same-chat/group-member inputs reused their Thread; five completed message identities produced exactly five isolated model requests, with duplicate/untrusted/no-mention events excluded".into())
}
