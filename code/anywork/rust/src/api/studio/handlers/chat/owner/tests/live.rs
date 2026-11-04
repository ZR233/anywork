//! Real provider barriers drive the production FRB producer and native range watch.
use std::collections::HashSet;

use super::*;
use crate::api::studio::{
    handlers::chat::tests::MODEL,
    types::{BridgeChatBatch, BridgeChatPlacement, BridgeContentRange, BridgeCurrentContentRole},
};
use pl_provider_fixture::{ReplyStage, responses_text_chunks};

async fn chat(
    owner: &ConversationOwner,
    port: &mut mpsc::Receiver<BridgeConversationFrame>,
    sent: &mut u64,
) -> Result<(u64, BridgeChatBatch)> {
    loop {
        let frame = receive(port).await?;
        ensure!(frame.thread_id == owner.thread_id);
        ensure!(frame.subscription_id == owner.subscription_id);
        ensure!(
            frame.delivery_sequence == *sent + 1,
            "duplicated or skipped sent prefix"
        );
        *sent = frame.delivery_sequence;
        match frame.event {
            BridgeConversationEvent::State { .. } => {
                owner.acknowledge(&owner.subscription_id, *sent)?
            }
            BridgeConversationEvent::Chat { batch } => return Ok((*sent, *batch)),
            event => anyhow::bail!("unexpected live terminal: {event:?}"),
        }
    }
}

async fn window(
    facade: &BridgeConversationFeed,
    id: &str,
    stage: &str,
) -> Result<crate::api::studio::types::BridgeContentWindow> {
    tokio::time::timeout(
        Duration::from_secs(5),
        facade.next_content_window(id.to_owned()),
    )
    .await
    .map_err(|error| {
        anyhow::anyhow!("{stage}: next_content_window timeout; watch={id}: {error:?}")
    })?
    .map_err(|error| anyhow::anyhow!("{stage}: next_content_window; watch={id}: {error:?}"))?
    .with_context(|| format!("{stage}: live watch ended before its window; watch={id}"))
}

#[tokio::test]
async fn live_append_range_watch_replacement_and_retired_facade_keep_original_qualification()
-> Result<()> {
    let prefix = "prefix 汉字🦀 live ".repeat(64);
    let suffix = " appended tail";
    let replacement = "authoritative replacement 汉字🦀 ".repeat(64);
    let frames = responses_text_chunks(&[&prefix, suffix], "bridge-live", MODEL);
    let head = ReplyStage::new();
    let appended = ReplyStage::new();
    let mut terminal = frames[4..].to_vec();
    terminal[0]["item"]["content"][0]["text"] = replacement.clone().into();
    terminal[1]["response"]["output"][0]["content"][0]["text"] = replacement.clone().into();
    let reply = ReplyStage::staged(
        vec![frames[..3].to_vec(), frames[3..4].to_vec(), terminal],
        &[&head, &appended],
    );
    let env = Environment::with_followup(Some(reply)).await?;
    let result = tokio::time::timeout(Duration::from_secs(30), async {
        let owner = managed(env.feed().await?);
        let facade = BridgeConversationFeed { inner: Arc::clone(&owner) };
        let mut port = start_port(&owner).await;
        let mut sent = 0;
        let (set_seq, initial) = chat(&owner, &mut port, &mut sent).await?;
        ensure!(initial.placement == BridgeChatPlacement::Set);
        ensure!(initial.current.is_some());
        let before = initial.before.context("nonempty fixture must have an older page")?;
        let old = facade.load_older(before.clone(), BridgeReadDemand {
            max_items: 16, max_bytes: 64 * 1024,
        }).await.map_err(|error| anyhow::anyhow!("history.load_older.initial: {error:?}"))?;
        ensure!(old.placement == BridgeChatPlacement::Prepend && old.current.is_none());
        let mut completed_items = HashSet::new();
        for entry in &initial.entries {
            let crate::api::studio::types::BridgeChatEntry::Item(item) = entry else {
                anyhow::bail!("Main must contain display items");
            };
            ensure!(completed_items.insert(item.id.clone()));
        }
        let mut historical = None;
        for entry in old.entries {
            let crate::api::studio::types::BridgeChatEntry::Item(item) = entry else {
                continue;
            };
            ensure!(completed_items.insert(item.id.clone()));
            if let Some(item_id) = item.content_item_id.as_deref() {
                let manifest = facade
                    .list_contents(
                        item_id.to_owned(),
                        None,
                        BridgeReadDemand {
                            max_items: 16,
                            max_bytes: 64 * 1024,
                        },
                    )
                    .await
                    .map_err(|error| anyhow::anyhow!(
                        "history.list_contents: item_id={item_id}: {error:?}"
                    ))?;
                if let Some(entry) = manifest.entries.into_iter().next() {
                    historical = Some(entry.reference);
                    break;
                }
            }
        }
        let historical = historical.context("real completed body manifest")?;
        let range = BridgeContentRange { offset: 3, max_bytes: 12 };
        let old_window = facade.read_content(historical.clone(), range.clone()).await
            .map_err(|error| anyhow::anyhow!(
                "history.read_content.initial: reference={historical:?}; range={range:?}: {error:?}"
            ))?;
        ensure!(old_window.sealed && old_window.offset == range.offset && !old_window.bytes.is_empty());
        ensure!(owner.state.lock().unwrap().sent == set_seq);
        owner.acknowledge(&owner.subscription_id, set_seq)?;
        env.submit_followup().await?;
        tokio::time::timeout(Duration::from_secs(5), head.wait_reached()).await?;

        let (held_seq, reference, preview_id, preview_bytes, preview_range_matches, held_cut) = loop {
            let (sequence, batch) = chat(&owner, &mut port, &mut sent).await?;
            ensure!(batch.placement == BridgeChatPlacement::Append && batch.before.is_none());
            for entry in batch.entries {
                let crate::api::studio::types::BridgeChatEntry::Item(item) = entry else {
                    anyhow::bail!("Main appended an atom instead of an item");
                };
                ensure!(completed_items.insert(item.id));
            }
            if let Some(preview) = batch.current.as_ref().and_then(|current| current.previews.iter()
                .find(|preview| preview.role == BridgeCurrentContentRole::Response))
            {
                let cut = batch.current.as_ref().map(|current| (
                    current.source_effect_seq,
                    current.execution_present,
                    current.active.as_ref().map(|active| active.id.clone()),
                    current.active_turn.clone(),
                ));
                break (
                    sequence,
                    preview.reference.clone(),
                    preview.id.clone(),
                    preview.text.len(),
                    preview.text.as_bytes().get(3..15) == Some(&prefix.as_bytes()[3..15]),
                    cut,
                );
            }
            owner.acknowledge(&owner.subscription_id, sequence)?;
        };
        // Do not ACK the live batch: the producer holds native recv and is genuinely credit-blocked.
        ensure!(owner.native.try_lock().is_err());
        let mut credit = Box::pin(owner.wait_credit());
        ensure!(futures::poll!(credit.as_mut()).is_pending());
        let held_context = || format!(
            "watch.primary held preview: thread_id={}; subscription_id={}; held_sequence={held_seq}; \
             preview_id={preview_id:?}; preview_text_bytes={preview_bytes}; \
             preview_range_matches={preview_range_matches}; \
             cut(source_effect_seq,execution_present,active_id,active_turn)={held_cut:?}; \
             reference={reference:?}; range={range:?}; expected_available_through={}; expected_window_bytes=12",
            owner.thread_id, owner.subscription_id, prefix.len(),
        );
        let watch = facade.open_content_watch(reference.clone(), range.clone()).await
            .map_err(|error| anyhow::anyhow!(
                "watch.primary.open: reference={reference:?}; range={range:?}: {error:?}"
            ))
            .with_context(&held_context)?;
        let first = window(&facade, &watch, "watch.primary.initial").await
            .with_context(&held_context)?;
        let held_context = held_context();
        ensure!(
            first.offset == 3 && !first.sealed && first.available_through == prefix.len() as u64,
            "{held_context}; actual_initial_window={first:?}"
        );
        ensure!(
            first.bytes == prefix.as_bytes()[3..15],
            "{held_context}; actual_initial_window={first:?}"
        );
        let cancelled_watch = facade.open_content_watch(reference.clone(), range.clone()).await
            .map_err(|error| anyhow::anyhow!(
                "watch.cancelled.open: reference={reference:?}; range={range:?}: {error:?}"
            ))?;
        window(&facade, &cancelled_watch, "watch.cancelled.initial").await?;
        let mut waiting = Box::pin(async {
            facade.next_content_window(cancelled_watch.clone()).await
                .map_err(|error| anyhow::anyhow!(
                    "watch.cancelled.wait_next: watch={cancelled_watch}: {error:?}"
                ))
        });
        let waiting_state = futures::poll!(waiting.as_mut());
        if let std::task::Poll::Ready(Err(error)) = waiting_state {
            return Err(error);
        }
        ensure!(waiting_state.is_pending(), "unchanged native source must wait");
        facade.request_close_content_watch(cancelled_watch.clone())?;
        let (next, close) = tokio::time::timeout(Duration::from_secs(5), async {
            tokio::join!(waiting, facade.close_content_watch(cancelled_watch.clone()))
        }).await
            .map_err(|error| anyhow::anyhow!(
                "watch.cancelled.close_join.timeout: watch={cancelled_watch}: {error:?}"
            ))?;
        ensure!(next?.is_none());
        close?;
        let page = tokio::time::timeout(Duration::from_secs(5), facade.load_older(before.clone(),
            BridgeReadDemand { max_items: 16, max_bytes: 64 * 1024 })).await
            .map_err(|error| anyhow::anyhow!("history.load_older.credit_blocked.timeout: {error:?}"))?
            .map_err(|error| anyhow::anyhow!("history.load_older.credit_blocked: {error:?}"))?;
        ensure!(!page.entries.is_empty() && page.current.is_none());
        ensure!(facade.read_content(historical, range.clone()).await
            .map_err(|error| anyhow::anyhow!(
                "history.read_content.credit_blocked: range={range:?}: {error:?}"
            ))?.bytes == old_window.bytes);
        ensure!(port.try_recv().is_err(), "query or watch must not bypass feed credit");
        // Only the real producer may consume the credit notification after ACK.
        drop(credit);
        head.release();
        tokio::time::timeout(Duration::from_secs(5), appended.wait_reached()).await?;
        let second = window(&facade, &watch, "watch.primary.append").await?;
        ensure!(second.generation == first.generation, "append-only content must retain its generation");
        ensure!(second.available_through == (prefix.len() + suffix.len()) as u64 && !second.sealed);
        ensure!(second.offset == first.offset && second.bytes == first.bytes);
        owner.acknowledge(&owner.subscription_id, held_seq)?;
        appended.release();
        let final_window = loop {
            let next = window(&facade, &watch, "watch.primary.replacement").await?;
            if next.sealed { break next; }
        };
        ensure!(final_window.bytes == replacement.as_bytes()[3..15]);
        ensure!(final_window.available_through == replacement.len() as u64);
        ensure!(final_window.generation != first.generation, "authoritative replacement must change generation");
        ensure!(facade.next_content_window(watch.clone()).await
            .map_err(|error| anyhow::anyhow!(
                "watch.primary.terminal_next: watch={watch}: {error:?}"
            ))?.is_none());
        facade.close_content_watch(watch).await?;

        let mut completed_body = false;
        loop {
            let (sequence, batch) = chat(&owner, &mut port, &mut sent).await?;
            ensure!(batch.placement == BridgeChatPlacement::Append && batch.before.is_none());
            for entry in batch.entries {
                let crate::api::studio::types::BridgeChatEntry::Item(item) = entry else {
                    continue;
                };
                ensure!(completed_items.insert(item.id.clone()));
                if let Some(item_id) = item.content_item_id.as_deref() {
                    let manifest = facade
                        .list_contents(
                            item_id.to_owned(),
                            None,
                            BridgeReadDemand {
                                max_items: 16,
                                max_bytes: 64 * 1024,
                            },
                        )
                        .await
                        .map_err(|error| anyhow::anyhow!(
                            "completion.list_contents: item_id={item_id}: {error:?}"
                        ))?;
                    completed_body |= manifest
                        .entries
                        .into_iter()
                        .any(|entry| entry.reference == reference);
                }
            }
            let retired = batch.current.is_some_and(|current|
                current.active.is_none() && current.active_turn.is_none());
            owner.acknowledge(&owner.subscription_id, sequence)?;
            if retired {
                ensure!(completed_body, "current retired before the completed body was queryable");
                break;
            }
        }
        env.runtime.synchronize_thread_observation(&env.thread_id).await?;
        // A new facade cannot accept the original cursor. Retiring the old facade cannot revoke it.
        let replacement_owner = managed(env.feed().await?);
        let replacement_facade = BridgeConversationFeed { inner: replacement_owner };
        ensure!(replacement_facade.load_older(before.clone(),
            BridgeReadDemand { max_items: 2, max_bytes: 64 * 1024 }).await.is_err());
        let late_watch = facade.open_content_watch(reference.clone(), range.clone()).await
            .map_err(|error| anyhow::anyhow!(
                "watch.late.open: reference={reference:?}; range={range:?}: {error:?}"
            ))?;
        facade.request_close();
        ensure!(facade.next_content_window(late_watch.clone()).await
            .map_err(|error| anyhow::anyhow!(
                "watch.late.retired_next: watch={late_watch}: {error:?}"
            ))?.is_none());
        facade.close().await?;
        ensure!(owner.is_settled() && owner.native.lock().await.is_none());
        ensure!(owner.producer.lock().await.task.is_none());
        ensure!(facade.read_content(reference.clone(), range.clone()).await.is_err());
        ensure!(replacement_facade.read_content(reference, range).await
            .map_err(|error| anyhow::anyhow!("replacement.read_content: {error:?}"))?
            .bytes == final_window.bytes);
        replacement_facade.close().await?;
        println!("live FRB: Set→Append ordered through {sent}; old-page/range during unacked #{held_seq}; append generation {}; replacement generation {}; native watches/feed/read closed; \
            {held_context}; actual_window_through(first,append,replacement)=({},{},{}); actual_initial_window={first:?}",
            first.generation, final_window.generation,
            first.available_through, second.available_through, final_window.available_through);
        Ok(())
    }).await.context("live FRB lifecycle exceeded its bounded test budget").and_then(|result| result);
    head.release();
    appended.release();
    env.finish(result).await
}
