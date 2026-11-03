//! Real provider barriers drive the production FRB producer and native range watch.
use std::collections::HashSet;

use super::*;
use crate::api::studio::{
    handlers::chat::tests::MODEL,
    types::{
        BridgeChatActiveStatus, BridgeChatAtom, BridgeChatAtomKind, BridgeChatAtomLifecycle,
        BridgeChatBatch, BridgeChatDeliveryKind, BridgeChatPlacement, BridgeChatSourceId,
        BridgeChatTerminalOutcome, BridgeContentRange, BridgeCurrentContentRole,
    },
};
use pl_provider_fixture::{ReplyStage, responses_text_chunks};

fn is_terminal(atom: &BridgeChatAtom) -> bool {
    matches!(&atom.lifecycle, BridgeChatAtomLifecycle::Terminal { .. })
}

fn completed_payload_item_id(atom: &BridgeChatAtom) -> Option<&str> {
    match (&atom.lifecycle, atom.completion_item_id.as_deref()) {
        (BridgeChatAtomLifecycle::Terminal { .. }, Some(item_id)) => Some(item_id),
        _ => None,
    }
}

fn record_member(
    atom: &BridgeChatAtom,
    active_members: &mut HashSet<String>,
    completed_members: &mut HashSet<String>,
) -> Result<()> {
    if is_terminal(atom) {
        active_members.remove(&atom.id);
        ensure!(
            completed_members.insert(atom.id.clone()),
            "repeated completed member identity"
        );
    } else {
        // Active snapshots can repeat and may transition to Terminal with this same member ID.
        active_members.insert(atom.id.clone());
    }
    Ok(())
}

#[test]
fn active_member_can_transition_to_terminal_but_duplicate_terminal_is_rejected() {
    let mut atom = BridgeChatAtom {
        id: "stable-member-id".into(),
        completion_item_id: None,
        completion_seq: None,
        source: BridgeChatSourceId::Input {
            input_id: "input-id".into(),
        },
        source_state: None,
        source_order: Some(1),
        kind: BridgeChatAtomKind::Input,
        delivery: BridgeChatDeliveryKind::Independent,
        lifecycle: BridgeChatAtomLifecycle::Active {
            started: None,
            status: BridgeChatActiveStatus::Waiting,
        },
        turn_id: None,
        attempt_id: None,
        tool: None,
        wait: None,
        text_channel: None,
        started_at: None,
        finished_at: None,
        contents: Vec::new(),
        payload: None,
    };
    let mut active_members = HashSet::new();
    let mut completed_members = HashSet::new();

    record_member(&atom, &mut active_members, &mut completed_members).unwrap();
    assert!(active_members.contains("stable-member-id"));
    assert!(completed_members.is_empty());

    atom.lifecycle = BridgeChatAtomLifecycle::Terminal {
        started: None,
        ended: None,
        outcome: BridgeChatTerminalOutcome::Completed,
    };
    record_member(&atom, &mut active_members, &mut completed_members).unwrap();
    assert!(active_members.is_empty());
    assert!(completed_members.contains("stable-member-id"));
    assert!(record_member(&atom, &mut active_members, &mut completed_members).is_err());
}

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
) -> Result<crate::api::studio::types::BridgeContentWindow> {
    tokio::time::timeout(
        Duration::from_secs(5),
        facade.next_content_window(id.to_owned()),
    )
    .await??
    .context("live watch ended before its window")
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
        }).await?;
        ensure!(old.placement == BridgeChatPlacement::Prepend && old.current.is_none());
        let mut active_members = HashSet::new();
        let mut completed_members = HashSet::new();
        for entry in &initial.entries {
            if let crate::api::studio::types::BridgeChatEntry::Atom(atom) = entry {
                record_member(atom, &mut active_members, &mut completed_members)?;
            }
        }
        if let Some(current) = &initial.current {
            for atom in &current.atoms {
                record_member(atom, &mut active_members, &mut completed_members)?;
            }
        }
        let mut historical = None;
        for entry in old.entries {
            let crate::api::studio::types::BridgeChatEntry::Atom(atom) = entry else {
                continue;
            };
            record_member(&atom, &mut active_members, &mut completed_members)?;
            if is_terminal(&atom)
                && let Some(item_id) = completed_payload_item_id(&atom)
            {
                let manifest = facade
                    .list_contents(
                        item_id.to_owned(),
                        None,
                        BridgeReadDemand {
                            max_items: 16,
                            max_bytes: 64 * 1024,
                        },
                    )
                    .await?;
                if let Some(entry) = manifest.entries.into_iter().next() {
                    historical = Some(entry.reference);
                    break;
                }
            }
        }
        let historical = historical.context("real completed body manifest")?;
        let range = BridgeContentRange { offset: 3, max_bytes: 12 };
        let old_window = facade.read_content(historical.clone(), range.clone()).await?;
        ensure!(old_window.sealed && old_window.offset == range.offset && !old_window.bytes.is_empty());
        ensure!(owner.state.lock().unwrap().sent == set_seq);
        owner.acknowledge(&owner.subscription_id, set_seq)?;
        env.submit_followup().await?;
        tokio::time::timeout(Duration::from_secs(5), head.wait_reached()).await?;

        let (held_seq, reference) = loop {
            let (sequence, batch) = chat(&owner, &mut port, &mut sent).await?;
            ensure!(batch.placement == BridgeChatPlacement::Append && batch.before.is_none());
            for entry in batch.entries {
                if let crate::api::studio::types::BridgeChatEntry::Atom(atom) = entry {
                    record_member(&atom, &mut active_members, &mut completed_members)?;
                }
            }
            if let Some(current) = &batch.current {
                for atom in &current.atoms {
                    record_member(atom, &mut active_members, &mut completed_members)?;
                }
            }
            if let Some(preview) = batch.current.as_ref().and_then(|current| current.previews.iter()
                .find(|preview| preview.role == BridgeCurrentContentRole::Response))
            {
                break (sequence, preview.reference.clone());
            }
            owner.acknowledge(&owner.subscription_id, sequence)?;
        };
        // Do not ACK the live batch: the producer holds native recv and is genuinely credit-blocked.
        ensure!(owner.native.try_lock().is_err());
        let mut credit = Box::pin(owner.wait_credit());
        ensure!(futures::poll!(credit.as_mut()).is_pending());
        let watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        let first = window(&facade, &watch).await?;
        ensure!(first.offset == 3 && !first.sealed && first.available_through == prefix.len() as u64);
        ensure!(first.bytes == prefix.as_bytes()[3..15]);
        let cancelled_watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        window(&facade, &cancelled_watch).await?;
        let mut waiting = Box::pin(facade.next_content_window(cancelled_watch.clone()));
        ensure!(futures::poll!(waiting.as_mut()).is_pending(), "unchanged native source must wait");
        facade.request_close_content_watch(cancelled_watch.clone())?;
        let (next, close) = tokio::time::timeout(Duration::from_secs(5), async {
            tokio::join!(waiting, facade.close_content_watch(cancelled_watch.clone()))
        }).await?;
        ensure!(next?.is_none());
        close?;
        let page = tokio::time::timeout(Duration::from_secs(5), facade.load_older(before.clone(),
            BridgeReadDemand { max_items: 16, max_bytes: 64 * 1024 })).await??;
        ensure!(!page.entries.is_empty() && page.current.is_none());
        ensure!(facade.read_content(historical, range.clone()).await?.bytes == old_window.bytes);
        ensure!(port.try_recv().is_err(), "query or watch must not bypass feed credit");
        // Only the real producer may consume the credit notification after ACK.
        drop(credit);
        head.release();
        tokio::time::timeout(Duration::from_secs(5), appended.wait_reached()).await?;
        let second = window(&facade, &watch).await?;
        ensure!(second.generation == first.generation, "append-only content must retain its generation");
        ensure!(second.available_through == (prefix.len() + suffix.len()) as u64 && !second.sealed);
        ensure!(second.offset == first.offset && second.bytes == first.bytes);
        owner.acknowledge(&owner.subscription_id, held_seq)?;
        appended.release();
        let final_window = loop {
            let next = window(&facade, &watch).await?;
            if next.sealed { break next; }
        };
        ensure!(final_window.bytes == replacement.as_bytes()[3..15]);
        ensure!(final_window.available_through == replacement.len() as u64);
        ensure!(final_window.generation != first.generation, "authoritative replacement must change generation");
        ensure!(facade.next_content_window(watch.clone()).await?.is_none());
        facade.close_content_watch(watch).await?;

        let mut completed_body = false;
        loop {
            let (sequence, batch) = chat(&owner, &mut port, &mut sent).await?;
            ensure!(batch.placement == BridgeChatPlacement::Append && batch.before.is_none());
            for entry in batch.entries {
                let crate::api::studio::types::BridgeChatEntry::Atom(atom) = entry else {
                    continue;
                };
                record_member(&atom, &mut active_members, &mut completed_members)?;
                if !is_terminal(&atom) {
                    continue;
                }
                if let Some(item_id) = completed_payload_item_id(&atom) {
                    let manifest = facade
                        .list_contents(
                            item_id.to_owned(),
                            None,
                            BridgeReadDemand {
                                max_items: 16,
                                max_bytes: 64 * 1024,
                            },
                        )
                        .await?;
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
        let late_watch = facade.open_content_watch(reference.clone(), range.clone()).await?;
        facade.request_close();
        ensure!(facade.next_content_window(late_watch).await?.is_none());
        facade.close().await?;
        ensure!(owner.is_settled() && owner.native.lock().await.is_none());
        ensure!(owner.producer.lock().await.task.is_none());
        ensure!(facade.read_content(reference.clone(), range.clone()).await.is_err());
        ensure!(replacement_facade.read_content(reference, range).await?.bytes == final_window.bytes);
        replacement_facade.close().await?;
        println!("live FRB: Set→Append ordered through {sent}; old-page/range during unacked #{held_seq}; append generation {}; replacement generation {}; native watches/feed/read closed",
            first.generation, final_window.generation);
        Ok(())
    }).await.context("live FRB lifecycle exceeded its bounded test budget").and_then(|result| result);
    head.release();
    appended.release();
    env.finish(result).await
}
