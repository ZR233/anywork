//! Real provider barriers drive the production FRB producer and native range watch.
use std::{collections::HashSet, io::Write};

use super::*;
use crate::api::studio::{
    handlers::chat::tests::MODEL,
    types::{BridgeChatBatch, BridgeChatPlacement, BridgeContentRange},
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
            "duplicated or skipped delivery prefix"
        );
        *sent = frame.delivery_sequence;
        match frame.event {
            BridgeConversationEvent::State { .. } | BridgeConversationEvent::Activity { .. } => {
                owner.acknowledge(&owner.subscription_id, *sent)?;
            }
            BridgeConversationEvent::Chat { batch } => return Ok((*sent, *batch)),
            event => anyhow::bail!("unexpected live terminal: {event:?}"),
        }
    }
}

async fn activity(
    owner: &ConversationOwner,
    port: &mut mpsc::Receiver<BridgeConversationFrame>,
    sent: &mut u64,
) -> Result<(u64, crate::api::studio::types::BridgeActivitySnapshot)> {
    loop {
        let frame = receive(port).await?;
        ensure!(frame.thread_id == owner.thread_id);
        ensure!(frame.subscription_id == owner.subscription_id);
        ensure!(
            frame.delivery_sequence == *sent + 1,
            "duplicated or skipped delivery prefix"
        );
        *sent = frame.delivery_sequence;
        match frame.event {
            BridgeConversationEvent::State { .. } => {
                owner.acknowledge(&owner.subscription_id, *sent)?;
            }
            BridgeConversationEvent::Activity { snapshot } => return Ok((*sent, *snapshot)),
            BridgeConversationEvent::Chat { .. } => {
                anyhow::bail!("unexpected Chat before Activity cut")
            }
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
        ensure!(initial.from_seq.is_none());
        let before = initial.before.context("nonempty fixture must have an older page")?;
        let old = facade.load_older(before.clone(), BridgeReadDemand {
            max_items: 16, max_bytes: 64 * 1024,
        }).await.map_err(|error| anyhow::anyhow!("history.load_older.initial: {error:?}"))?;
        ensure!(old.placement == BridgeChatPlacement::Prepend && !old.entries.is_empty());
        let historical_record_id = old.entries[0].record_id.clone();
        let mut completed_records = HashSet::new();
        for entry in &initial.entries {
            ensure!(completed_records.insert(entry.record_id.clone()));
            if let Some(run) = entry.run {
                ensure!(run.start_seq > 0 && run.ordinal > 0);
            }
        }
        let mut historical = None;
        for entry in old.entries {
            ensure!(completed_records.insert(entry.record_id.clone()));
            if entry.atom.payload.is_some() || !entry.atom.contents.is_empty() {
                let manifest = facade.list_contents(entry.record_id.clone(), None, BridgeReadDemand {
                    max_items: 16, max_bytes: 64 * 1024,
                }).await.map_err(|error| anyhow::anyhow!(
                    "history.list_contents: record_id={}: {error:?}", entry.record_id
                ))?;
                if let Some(manifest_entry) = manifest.entries.into_iter().next() {
                    historical = Some(manifest_entry.reference);
                    break;
                }
            }
        }
        let historical = historical.context("real completed body manifest")?;
        let range = BridgeContentRange { offset: 3, max_bytes: 12 };
        let old_window = facade.read_content(historical.clone(), range.clone()).await
            .map_err(|error| anyhow::anyhow!("history.read_content.initial: {error:?}"))?;
        ensure!(old_window.sealed && old_window.offset == range.offset && !old_window.bytes.is_empty());
        owner.acknowledge(&owner.subscription_id, set_seq)?;
        env.submit_followup().await?;
        tokio::time::timeout(Duration::from_secs(5), head.wait_reached()).await?;

        // Chat completion and Activity are separate credit-bearing events. ACK each preceding
        // Chat; hold the exact Activity snapshot that carries the live body owner.
        let (held_seq, reference, activity_id, turn_id, held_snapshot) = loop {
            let (chat_seq, batch) = chat(&owner, &mut port, &mut sent).await?;
            ensure!(batch.placement == BridgeChatPlacement::Append
                && batch.before.is_none()
                && batch.from_seq.is_some_and(|from| from < batch.through_seq));
            let accepted_through = batch.through_seq;
            for entry in batch.entries {
                ensure!(completed_records.insert(entry.record_id));
            }
            owner.acknowledge(&owner.subscription_id, chat_seq)?;
            let (sequence, snapshot) = activity(&owner, &mut port, &mut sent).await?;
            ensure!(snapshot.revision > 0);
            ensure!(snapshot.completed_through == accepted_through,
                "Activity arrived ahead of or behind the accepted completion prefix");
            let Some(entry) = snapshot.entries.iter().find(|entry|
                entry.atom.kind == crate::api::studio::types::BridgeChatAtomKind::Text
                    && matches!(&entry.atom.lifecycle, crate::api::studio::types::BridgeChatAtomLifecycle::Active { .. })
                    && entry.atom.contents.iter().any(|content|
                        content.role == crate::api::studio::types::BridgeChatContentRole::Body))
            else {
                owner.acknowledge(&owner.subscription_id, sequence)?;
                continue;
            };
            ensure!(snapshot.execution_present);
            let body = entry.atom.contents.iter()
                .find(|content| content.role == crate::api::studio::types::BridgeChatContentRole::Body)
                .context("Activity omitted Body reference")?;
            let identity = match &entry.identity {
                crate::api::studio::types::BridgeActivityIdentity::ModelPart { atom_id } => atom_id,
                other => anyhow::bail!("text body has unexpected activity identity: {other:?}"),
            };
            ensure!(identity == &entry.atom.id);
            let prefix_window = facade.read_content(body.reference.clone(), range.clone()).await
                .map_err(|error| anyhow::anyhow!("Activity body read while credit held: {error:?}"))?;
            if prefix_window.bytes != prefix.as_bytes()[3..15] {
                owner.acknowledge(&owner.subscription_id, sequence)?;
                continue;
            }
            let reference = body.reference.clone();
            let activity_id = identity.clone();
            let turn_id = entry.atom.turn_id.clone().context("Activity omitted Turn identity")?;
            break (sequence, reference, activity_id, turn_id, snapshot);
        };
        ensure!(held_snapshot.execution_present && held_snapshot.revision > 0);
        ensure!(owner.native.try_lock().is_err(), "producer owns native recv while credit is held");
        let mut credit = Box::pin(owner.wait_credit());
        ensure!(futures::poll!(credit.as_mut()).is_pending());
        let watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        let first = window(&facade, &watch, "watch.primary.initial").await?;
        ensure!(first.offset == 3 && !first.sealed && first.available_through == prefix.len() as u64);
        ensure!(first.bytes == prefix.as_bytes()[3..15]);
        let cancelled_watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        window(&facade, &cancelled_watch, "watch.cancelled.initial").await?;
        let mut waiting = Box::pin(async { facade.next_content_window(cancelled_watch.clone()).await });
        ensure!(futures::poll!(waiting.as_mut()).is_pending(), "unchanged watch should wait");
        facade.request_close_content_watch(cancelled_watch.clone())?;
        let (next, close) = tokio::time::timeout(Duration::from_secs(5), async {
            tokio::join!(waiting, facade.close_content_watch(cancelled_watch.clone()))
        }).await?;
        ensure!(next?.is_none());
        close?;
        let page = tokio::time::timeout(Duration::from_secs(5), facade.load_older(before.clone(),
            BridgeReadDemand { max_items: 16, max_bytes: 64 * 1024 })).await??;
        ensure!(!page.entries.is_empty());
        let historical_entry = facade.read_completed(
            historical_record_id.clone(),
            BridgeReadDemand { max_items: 1, max_bytes: 64 * 1024 },
        ).await?;
        ensure!(historical_entry.record_id == historical_record_id);
        ensure!(facade.read_content(historical, range.clone()).await?.bytes == old_window.bytes);
        ensure!(port.try_recv().is_err(), "queries/watch must not bypass occupied feed credit");

        head.release();
        tokio::time::timeout(Duration::from_secs(5), appended.wait_reached()).await?;
        let second = window(&facade, &watch, "watch.primary.append").await?;
        ensure!(second.generation == first.generation);
        ensure!(second.available_through == (prefix.len() + suffix.len()) as u64 && !second.sealed);
        ensure!(second.bytes == first.bytes);
        owner.acknowledge(&owner.subscription_id, held_seq)?;
        drop(credit);
        appended.release();
        let final_window = loop {
            let next = window(&facade, &watch, "watch.primary.replacement").await?;
            if next.sealed { break next; }
        };
        ensure!(final_window.bytes == replacement.as_bytes()[3..15]);
        ensure!(final_window.available_through == replacement.len() as u64);
        ensure!(final_window.generation != first.generation);
        ensure!(facade.next_content_window(watch.clone()).await?.is_none());
        facade.close_content_watch(watch).await?;

        let mut completed_body = None;
        let mut retired = false;
        for _ in 0..64 {
            let (chat_seq, batch) = chat(&owner, &mut port, &mut sent).await?;
            ensure!(batch.placement == BridgeChatPlacement::Append && batch.before.is_none());
            for entry in batch.entries {
                ensure!(completed_records.insert(entry.record_id.clone()));
                if entry.record_id == match &reference.target {
                    crate::api::studio::types::BridgeContentTarget::Body {
                        owner: crate::api::studio::types::BridgeContentOwner::Item { item_id }, ..
                    } => item_id.clone(),
                    _ => String::new(),
                } {
                    ensure!(entry.atom.id == activity_id);
                    ensure!(entry.atom.turn_id.as_deref() == Some(turn_id.as_str()));
                    completed_body = Some(entry.record_id.clone());
                }
            }
            owner.acknowledge(&owner.subscription_id, chat_seq)?;
            let (activity_seq, snapshot) = activity(&owner, &mut port, &mut sent).await?;
            retired = !snapshot.execution_present && snapshot.entries.is_empty();
            owner.acknowledge(&owner.subscription_id, activity_seq)?;
            if retired {
                ensure!(completed_body.is_some(), "Activity retired before response completion appeared");
                break;
            }
        }
        ensure!(retired);
        let record_id = completed_body.context("completion record ID")?;
        let point_read = facade.read_completed(record_id.clone(), BridgeReadDemand {
            max_items: 1, max_bytes: 64 * 1024,
        }).await?;
        ensure!(point_read.record_id == record_id && point_read.atom.id == activity_id);

        env.runtime.synchronize_thread_observation(&env.thread_id).await?;
        let replacement_owner = managed(env.feed().await?);
        let replacement_facade = BridgeConversationFeed { inner: replacement_owner };
        ensure!(replacement_facade.load_older(before.clone(),
            BridgeReadDemand { max_items: 2, max_bytes: 64 * 1024 }).await.is_err());
        let late_watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        facade.request_close();
        ensure!(facade.next_content_window(late_watch.clone()).await?.is_none());
        facade.close().await?;
        ensure!(owner.is_settled() && owner.native.lock().await.is_none());
        ensure!(owner.producer.lock().await.task.is_none());
        ensure!(facade.read_completed(record_id, BridgeReadDemand {
            max_items: 1, max_bytes: 64 * 1024,
        }).await.is_err());
        ensure!(replacement_facade.read_content(reference, range).await?.bytes == final_window.bytes);
        replacement_facade.close().await?;
        writeln!(std::io::stdout(), "typed Activity→CompletedEntry lifecycle; ACK held at Activity revision {}; independent older/read/watch while credit occupied; final watch close, point read, lease retirement and replacement qualification verified", held_snapshot.revision)?;
        Ok(())
    }).await.context("live FRB lifecycle exceeded its bounded test budget").and_then(|result| result);
    head.release();
    appended.release();
    env.finish(result).await
}
