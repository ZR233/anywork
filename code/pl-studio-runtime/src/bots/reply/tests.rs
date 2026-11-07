//! Reply-consumer regressions: real read leases/provider execution, plus local envelope boundaries.

use super::super::content::{
    FinalText, MAX_TURN_BODY_BYTES, MAX_TURN_CONTENT_ITEMS, collect_complete_turn_text,
};
use super::*;
use crate::bots::commands::archive_tests::Fixture;
use pl_protocol::{
    ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatEntry,
    ChatSourceId, ChatSourceLifecycle, ChatSourceState, ChatTerminalOutcome, ContentOwner,
    ContentRef, ContentTarget, CurrentContentPreview, CurrentContentRole, CurrentProjection,
    CurrentTurnHead, PayloadData, ThreadStatus, ThreadTextChannel, TurnPhase,
};
use std::time::Duration;

fn message(
    id: &str,
    turn: Option<&str>,
    kind: &str,
    data: serde_json::Value,
    bodies: serde_json::Value,
) -> ChatEntry {
    let domain = match kind {
        "text" => ChatAtomKind::Text,
        "turn" => ChatAtomKind::TurnReceipt,
        "tool" => ChatAtomKind::Interaction,
        "plan" => ChatAtomKind::Plan,
        _ => ChatAtomKind::Unknown,
    };
    let channel = data
        .get("channel")
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok());
    let mut entry = atom(id, turn, domain, PayloadData::Inline { bytes: serde_json::to_vec(&serde_json::json!({
        "contract":"anywork.chat/1", "type":kind, "turnId":turn, "data":data, "bodies":bodies,
    })).unwrap() });
    if let ChatEntry::Atom(atom) = &mut entry {
        atom.text_channel = channel;
    }
    entry
}

fn atom(id: &str, turn: Option<&str>, kind: ChatAtomKind, payload: PayloadData) -> ChatEntry {
    ChatEntry::Atom(Box::new(ChatAtom {
        id: id.into(),
        completion_item_id: Some(id.into()),
        content_present: None,
        completion_seq: Some(1),
        source: turn.map_or_else(
            || ChatSourceId::Receipt {
                receipt_id: id.into(),
            },
            |turn| ChatSourceId::ForegroundTurn {
                turn_id: turn.into(),
            },
        ),
        source_state: None,
        source_order: None,
        kind,
        delivery: ChatDeliveryKind::Foreground,
        lifecycle: ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: ChatTerminalOutcome::Completed,
        },
        turn_id: turn.map(str::to_owned),
        attempt_id: None,
        tool: None,
        wait: None,
        text_channel: None,
        started_at: None,
        finished_at: None,
        contents: Vec::new(),
        payload: Some(payload),
    }))
}

fn text(id: &str, turn: Option<&str>, channel: &str, value: &str) -> ChatEntry {
    message(
        id,
        turn,
        "text",
        serde_json::json!({"channel":channel}),
        serde_json::json!([{"key":"body", "byteLength":value.len(), "inline":value.as_bytes()}]),
    )
}

fn ended_source() -> ChatEntry {
    ChatEntry::Source(ChatSourceState {
        source: ChatSourceId::ForegroundTurn {
            turn_id: "target".into(),
        },
        lifecycle: ChatSourceLifecycle::Ended {
            outcome: ChatTerminalOutcome::Completed,
        },
        started: None,
        ended: None,
    })
}

fn current(
    turn: &str,
    item: &str,
    role: CurrentContentRole,
    text_channel: Option<ThreadTextChannel>,
    value: &str,
) -> CurrentProjection {
    let mut current = CurrentProjection::empty(1, ThreadStatus::Idle);
    current.execution_present = true;
    current.active_turn = Some(CurrentTurnHead {
        id: turn.into(),
        phase: TurnPhase::Responding,
    });
    current.previews.push(CurrentContentPreview {
        id: item.into(),
        role,
        text_channel,
        text: value.into(),
        reference: ContentRef {
            database_id: "fixture".into(),
            target: ContentTarget::Body {
                owner: ContentOwner::Item {
                    item_id: item.into(),
                },
                key: "body".into(),
            },
        },
    });
    current
}

#[test]
fn only_canonical_final_response_current_can_authorize_outbound_preview() -> anyhow::Result<()> {
    let mut projection = ReplyProjection::new("target");
    projection.mark_covered();
    for channel in [
        None,
        Some(ThreadTextChannel::Commentary),
        Some(ThreadTextChannel::User),
        Some(ThreadTextChannel::ParentAgent),
    ] {
        projection.set_current(current(
            "target",
            "part",
            CurrentContentRole::Response,
            channel,
            "must stay local",
        ))?;
        assert!(projection.active(), "the target remains live");
        assert!(
            projection.preview().is_none(),
            "role alone cannot authorize outbound text"
        );
    }
    for role in [
        CurrentContentRole::Reasoning,
        CurrentContentRole::ToolArguments,
        CurrentContentRole::ToolOutput,
    ] {
        projection.set_current(current(
            "target",
            "part",
            role,
            Some(ThreadTextChannel::Final),
            "not response",
        ))?;
        assert!(projection.preview().is_none());
    }
    projection.set_current(current(
        "target",
        "part",
        CurrentContentRole::Response,
        Some(ThreadTextChannel::Final),
        "answer",
    ))?;
    assert_eq!(projection.preview().as_deref(), Some("answer"));
    Ok(())
}

#[test]
fn typed_turn_terminal_waits_for_the_delivered_item_cut_not_just_state() -> anyhow::Result<()> {
    let mut projection = ReplyProjection::new("target");
    projection.mark_covered();
    let terminal = TurnState::Completed(pl_protocol::CompletedTurnState::new(
        Some(1),
        3,
        pl_protocol::TurnCompletion::Normal,
    ));
    projection.observe_terminal(&terminal);
    assert!(
        projection.terminal().is_none(),
        "State alone authorized final delivery"
    );
    let mut cut = CurrentProjection::empty(3, ThreadStatus::Idle);
    let ChatEntry::Source(source) = ended_source() else {
        unreachable!()
    };
    cut.sources = vec![source];
    cut.items = vec![pl_protocol::TimelineItem {
        id: "text:part".into(),
        kind: pl_protocol::TimelineItemKind::Text,
        source: ChatSourceId::ForegroundTurn {
            turn_id: "target".into(),
        },
        atom_kind: Some(ChatAtomKind::Text),
        delivery: ChatDeliveryKind::Foreground,
        text_channel: Some(ThreadTextChannel::Final),
        turn_id: Some("target".into()),
        started_at: None,
        finished_at: None,
        outcome: Some(ChatTerminalOutcome::Completed),
        summary: None,
        members: None,
        contents: Vec::new(),
        payload: None,
        content_item_id: Some("original-part".into()),
        position: None,
        admission_closed: true,
    }];
    projection.set_current(cut.clone())?;
    assert!(
        projection.terminal().is_none(),
        "undelivered Final suffix was ignored"
    );
    assert!(projection.terminal_cut_to_qualify().is_none());
    cut.items.clear();
    projection.set_current(cut)?;
    assert_eq!(projection.terminal(), Some(terminal));
    assert!(
        projection.completed()?.is_empty(),
        "a synthetic success receipt was inserted into Main"
    );
    Ok(())
}

/// Observe the real provider/Model -> current snapshot before passing its exact
/// ChatBatch through ReplyWatch's production reducer. The taken batch is staged
/// before any await, preserving the normal pending-owner cancellation boundary.
async fn receive_production_current(
    watch: &mut ReplyWatch,
    target: &str,
    channel: ThreadTextChannel,
    value: &str,
) -> anyhow::Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let event = watch
                .feed
                .recv()
                .await?
                .ok_or_else(|| anyhow::anyhow!("feed ended before the staged current"))?;
            match event {
                ConversationEvent::State { update } => watch.state(*update)?,
                ConversationEvent::Chat { batch } => {
                    let found = batch.current.as_ref().is_some_and(|current| {
                        current.execution_present
                            && current
                                .active_turn
                                .as_ref()
                                .is_some_and(|turn| turn.id == target)
                            && current.previews.iter().any(|part| {
                                part.role == CurrentContentRole::Response
                                    && part.text_channel == Some(channel)
                                    && part.text == value
                            })
                    });
                    watch.stage(*batch)?;
                    watch.finish_pending().await?;
                    if found {
                        return Ok::<_, anyhow::Error>(());
                    }
                }
            }
        }
    })
    .await?
}

#[test]
fn opaque_cursor_and_coverage_budgets_do_not_infer_eof_from_short_pages() {
    let mut coverage = Coverage::default();
    let fact = text("counted", Some("target"), "final", "x");
    assert!(coverage.page(std::slice::from_ref(&fact)).is_ok());
    assert!(coverage.cursor("opaque, not Core seq").is_ok());
    assert!(coverage.page(&[]).is_ok());
    assert!(coverage.cursor("another opaque cursor").is_ok());
    assert!(coverage.cursor("another opaque cursor").is_err());
    assert!(coverage.cursor("").is_err());
    assert!(coverage.page(&vec![fact; MAX_TURN_CONTENT_ITEMS]).is_err());
    let mut empty = Coverage::default();
    for _ in 0..MAX_TURN_CONTENT_ITEMS {
        assert!(empty.page(&[]).is_ok());
    }
    assert!(empty.page(&[]).is_err());
    let mut sources = Coverage::default();
    assert!(
        sources
            .admit(&vec![ended_source(); MAX_TURN_CONTENT_ITEMS])
            .is_ok()
    );
    assert!(
        sources.admit(&[ended_source()]).is_err(),
        "source facts cannot bypass admission"
    );
    let mut live = Coverage::default();
    for _ in 0..=MAX_TURN_CONTENT_ITEMS {
        assert!(
            live.admit(&[]).is_ok(),
            "preview-only updates are not recovery pages"
        );
    }
}

#[tokio::test]
async fn typed_atoms_preserve_payload_owner_final_qualification_and_unrelated_work_budget()
-> anyhow::Result<()> {
    use anyhow::Context;
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("reply-typed-atoms", true).await?;
    let runtime = &fixture.host.runtime;
    let mut watch = ReplyWatch::open(runtime, &inbound.creation_id).await?;
    watch
        .select_target(runtime, "input", Some("target"))
        .await?;
    let reader = watch.reader();
    let mut active = text("unfinished", Some("target"), "final", "not completed");
    if let ChatEntry::Atom(atom) = &mut active {
        atom.lifecycle = ChatAtomLifecycle::Active {
            started: None,
            status: ChatActiveStatus::Running,
        };
        atom.completion_item_id = None;
        atom.completion_seq = None;
        atom.payload = None;
    }
    assert!(decode_entry(&reader, &active, "target").await?.is_none());
    assert!(
        decode_entry(&reader, &ended_source(), "target")
            .await?
            .is_none()
    );
    for kind in [
        ChatAtomKind::Reasoning,
        ChatAtomKind::ToolCall,
        ChatAtomKind::FileChange,
        ChatAtomKind::Skill,
        ChatAtomKind::Compaction,
    ] {
        let mut work = atom(
            "receipt",
            Some("target"),
            kind,
            PayloadData::Deferred {
                reference: ContentRef {
                    database_id: "must-not-be-read".into(),
                    target: ContentTarget::ItemPayload {
                        item_id: "receipt".into(),
                    },
                },
                byte_length: MAX_TURN_BODY_BYTES as u64 + 1,
            },
        );
        if let ChatEntry::Atom(atom) = &mut work {
            atom.id = "stable-work-member".into();
        }
        assert!(decode_entry(&reader, &work, "target").await?.is_none());
    }
    for conflict in [
        "turn",
        "source",
        "channel",
        "unknown-channel",
        "domain",
        "payload-id",
        "completion-position",
        "body-owner",
    ] {
        let mut entry = text("answer", Some("target"), "final", "must not export");
        if let ChatEntry::Atom(atom) = &mut entry {
            match conflict {
                "turn" => {
                    atom.turn_id = Some("other".into());
                    atom.source = ChatSourceId::ForegroundTurn {
                        turn_id: "other".into(),
                    };
                }
                "source" => {
                    atom.source = ChatSourceId::ForegroundTurn {
                        turn_id: "other".into(),
                    }
                }
                "channel" => atom.text_channel = Some(ThreadTextChannel::Commentary),
                "unknown-channel" => atom.text_channel = None,
                "domain" => atom.kind = ChatAtomKind::Plan,
                "completion-position" => atom.completion_seq = None,
                "body-owner" => atom.contents.push(pl_protocol::ChatAtomContent {
                    role: pl_protocol::ChatContentRole::Body,
                    reference: ContentRef {
                        database_id: "fixture".into(),
                        target: ContentTarget::Body {
                            owner: ContentOwner::Item {
                                item_id: "other".into(),
                            },
                            key: "body".into(),
                        },
                    },
                }),
                _ => {
                    atom.payload = Some(PayloadData::Deferred {
                        reference: ContentRef {
                            database_id: "must-not-be-read".into(),
                            target: ContentTarget::ItemPayload {
                                item_id: "other".into(),
                            },
                        },
                        byte_length: 1,
                    })
                }
            }
        }
        assert!(
            decode_entry(&reader, &entry, "target").await.is_err(),
            "{conflict}"
        );
    }
    let mut completed = text("frozen-owner", Some("target"), "final", "answer");
    if let ChatEntry::Atom(atom) = &mut completed {
        atom.id = "stable-member".into();
    }
    let item = decode_entry(&reader, &completed, "target").await?.unwrap();
    assert_eq!(item.id, "frozen-owner");
    assert_eq!(item.member_id, "stable-member");
    let ChatEntry::Atom(atom) = completed.clone() else {
        unreachable!()
    };
    let display = ChatEntry::Item(Box::new(pl_protocol::TimelineItem {
        id: "display-identity-is-not-the-content-owner".into(),
        kind: pl_protocol::TimelineItemKind::Text,
        source: atom.source,
        atom_kind: Some(atom.kind),
        delivery: atom.delivery,
        text_channel: atom.text_channel,
        turn_id: atom.turn_id,
        started_at: None,
        finished_at: None,
        outcome: Some(ChatTerminalOutcome::Completed),
        summary: None,
        members: None,
        contents: atom.contents,
        payload: atom.payload,
        content_item_id: atom.completion_item_id,
        position: Some(7),
        admission_closed: true,
    }));
    let display_reply = decode_entry(&reader, &display, "target")
        .await?
        .context("Main Item final")?;
    assert_eq!(display_reply.id, "frozen-owner");
    assert_eq!(display_reply.member_id, "frozen-owner");
    watch.stage(ChatBatch {
        placement: ChatPlacement::Append,
        entries: vec![active, ended_source(), completed],
        before: None,
        current: Some(current(
            "target",
            "stable-member",
            CurrentContentRole::Response,
            Some(ThreadTextChannel::Final),
            "must not duplicate",
        )),
    })?;
    watch.finish_pending().await?;
    assert_eq!(watch.preview().as_deref(), Some("answer"));
    assert!(
        watch.terminal("target").is_none(),
        "source end is not a Turn receipt"
    );
    for entry in [
        message(
            "question",
            Some("target"),
            "tool",
            serde_json::json!({"userInput":{"interactionId":"question-interaction"}}),
            serde_json::json!([]),
        ),
        message(
            "plan",
            Some("target"),
            "plan",
            serde_json::json!({"interactionId":"plan-interaction"}),
            serde_json::json!([]),
        ),
    ] {
        assert!(matches!(
            decode_entry(&reader, &entry, "target").await?,
            Some(super::super::content::ReplyItem {
                kind: super::super::content::ReplyItemKind::Interaction(_),
                ..
            })
        ));
    }
    assert!(
        watch
            .stage(ChatBatch {
                placement: ChatPlacement::Append,
                entries: vec![ended_source(); demand().max_items as usize + 1],
                before: None,
                current: None,
            })
            .is_err()
    );
    watch.close().await?;
    fixture.shutdown().await
}

#[tokio::test]
async fn exact_target_envelope_and_current_retirement_never_mix_other_turns_or_tools()
-> anyhow::Result<()> {
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("reply-envelope", true).await?;
    let runtime = &fixture.host.runtime;
    let mut watch = ReplyWatch::open(runtime, &inbound.creation_id).await?;
    watch
        .select_target(runtime, "input", Some("target"))
        .await?;
    let reader = watch.reader();
    for other in [
        text("other", Some("other-turn"), "final", "foreign"),
        text("unbound", None, "final", "unknown"),
        text("commentary", Some("target"), "commentary", "commentary"),
    ] {
        assert!(decode_entry(&reader, &other, "target").await?.is_none());
    }
    watch.stage(ChatBatch {
        placement: ChatPlacement::Append,
        entries: vec![text("done", Some("target"), "final", "completed")],
        before: None,
        current: Some(current(
            "target",
            "done",
            CurrentContentRole::Response,
            Some(ThreadTextChannel::Final),
            "duplicate",
        )),
    })?;
    watch.finish_pending().await?;
    assert_eq!(watch.preview().as_deref(), Some("completed"));
    watch.stage(ChatBatch {
        placement: ChatPlacement::Append,
        entries: vec![],
        before: None,
        current: Some(current(
            "target",
            "live",
            CurrentContentRole::Response,
            Some(ThreadTextChannel::Final),
            "+live",
        )),
    })?;
    watch.finish_pending().await?;
    assert_eq!(watch.preview().as_deref(), Some("completed+live"));
    // None keeps current; a concrete empty snapshot retires it without losing completion.
    watch.stage(ChatBatch {
        placement: ChatPlacement::Append,
        entries: vec![],
        before: None,
        current: None,
    })?;
    watch.finish_pending().await?;
    assert_eq!(watch.preview().as_deref(), Some("completed+live"));
    for snapshot in [
        current(
            "other-turn",
            "live",
            CurrentContentRole::Response,
            Some(ThreadTextChannel::Final),
            "foreign",
        ),
        current(
            "target",
            "tool",
            CurrentContentRole::ToolOutput,
            None,
            "tool",
        ),
        CurrentProjection::empty(2, ThreadStatus::Idle),
    ] {
        watch.stage(ChatBatch {
            placement: ChatPlacement::Append,
            entries: vec![],
            before: None,
            current: Some(snapshot),
        })?;
        watch.finish_pending().await?;
        assert_eq!(watch.preview().as_deref(), Some("completed"));
    }
    assert!(watch.terminal("target").is_none());
    assert!(watch.projection().unwrap().completed().is_err());
    watch.select_target(runtime, "unknown-input", None).await?;
    assert!(watch.preview().is_none());
    assert!(watch.terminal("target").is_none());
    watch.close().await?;
    fixture.shutdown().await
}

#[tokio::test]
async fn malformed_or_unknown_final_and_oversized_deferred_payload_are_errors() -> anyhow::Result<()>
{
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("reply-invalid", true).await?;
    let mut watch = ReplyWatch::open(&fixture.host.runtime, &inbound.creation_id).await?;
    let reader = watch.reader();
    for invalid in [
        message(
            "missing",
            Some("target"),
            "text",
            serde_json::json!({"channel":"final"}),
            serde_json::json!([]),
        ),
        message(
            "unknown",
            Some("target"),
            "future-final",
            serde_json::json!({}),
            serde_json::json!([]),
        ),
        message(
            "unknown-raw",
            Some("target"),
            "raw",
            serde_json::json!({}),
            serde_json::json!([]),
        ),
        message(
            "length",
            Some("target"),
            "text",
            serde_json::json!({"channel":"final"}),
            serde_json::json!([{"key":"body","byteLength":5,"inline":[65]}]),
        ),
        message(
            "ref",
            Some("target"),
            "text",
            serde_json::json!({"channel":"final"}),
            serde_json::json!([{"key":"body","byteLength":1,"reference":{"databaseId":"fixture","target":{"kind":"body","owner":{"kind":"item","itemId":"different"},"key":"body"}}}]),
        ),
        atom(
            "bad-json",
            Some("target"),
            ChatAtomKind::Unknown,
            PayloadData::Inline {
                bytes: b"{".to_vec(),
            },
        ),
    ] {
        assert!(decode_entry(&reader, &invalid, "target").await.is_err());
    }
    let mut oversized = atom(
        "large",
        Some("target"),
        ChatAtomKind::Unknown,
        PayloadData::Deferred {
            byte_length: MAX_TURN_BODY_BYTES as u64 + 1,
            reference: ContentRef {
                database_id: "does-not-exist".into(),
                target: ContentTarget::ItemPayload {
                    item_id: "large".into(),
                },
            },
        },
    );
    if let ChatEntry::Atom(atom) = &mut oversized {
        atom.id = "stable-member".into();
    }
    // The nonexistent IO target must not be read before enforcing the bot budget.
    assert!(
        matches!(decode_entry(&reader, &oversized, "target").await, Err(FinalError::Attention(message)) if message.contains("800000"))
    );
    let cancelled = TurnState::Cancelled(pl_protocol::CancelledTurnState::new(
        Some(1),
        2,
        3,
        pl_protocol::TurnCancellationCause::Interrupted,
    ));
    let receipt = message(
        "cancelled",
        Some("target"),
        "turn",
        serde_json::json!({"outcome":cancelled}),
        serde_json::json!([]),
    );
    assert!(matches!(
        decode_entry(&reader, &receipt, "target").await?,
        Some(super::super::content::ReplyItem {
            kind: super::super::content::ReplyItemKind::Terminal(state), ..
        }) if state == cancelled
    ));
    watch.close().await?;
    fixture.shutdown().await
}

#[tokio::test]
async fn real_feed_reconnect_rebuilds_set_and_closes_both_original_owners() -> anyhow::Result<()> {
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("reply-reconnect", true).await?;
    let runtime = &fixture.host.runtime;
    let mut watch = ReplyWatch::open(runtime, &inbound.creation_id).await?;
    watch
        .select_target(runtime, "input", Some("target"))
        .await?;
    let old_reader = watch.reader();
    let old_subscription = watch.feed.subscription_id().to_owned();
    let mut cancelled = false;
    for _ in 0..20 {
        match tokio::time::timeout(Duration::from_millis(50), watch.receive()).await {
            Err(_) => {
                cancelled = true;
                break;
            }
            Ok(result) => result?,
        }
    }
    assert!(cancelled, "real receive never became pending");
    watch.reconnect(runtime).await?;
    assert_ne!(watch.feed.subscription_id(), old_subscription);
    assert!(!watch.chat_ready);
    assert!(watch.projection.is_none());
    assert!(
        old_reader
            .list_contents("any", None, demand())
            .await
            .is_err()
    );
    watch.ensure_coverage().await?;
    assert!(watch.chat_ready);
    assert!(watch.terminal("target").is_none());
    let reader = watch.reader();
    watch.close().await?;
    assert!(reader.list_contents("any", None, demand()).await.is_err());
    assert!(watch.receive().await.is_err());
    watch.close().await?;
    fixture.shutdown().await
}

#[tokio::test]
async fn observation_failure_drains_the_owned_action_after_cancelling_new_admission()
-> anyhow::Result<()> {
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("reply-drain", true).await?;
    let mut watch = ReplyWatch::open(&fixture.host.runtime, &inbound.creation_id).await?;
    watch.reader().close().await?;
    let action_cancel = CancellationToken::new();
    let action = async {
        action_cancel.cancelled().await;
        // This continuation models an already-owned operation's real completion,
        // not a platform fake. Returning early would drop its observed result.
        tokio::task::yield_now().await;
        17
    };
    let (result, failure) = tokio::time::timeout(
        Duration::from_secs(2),
        watch.during(action, Some(&action_cancel)),
    )
    .await?;
    assert_eq!(result, 17);
    assert!(failure.is_some());
    assert!(action_cancel.is_cancelled());
    watch.close().await?;
    fixture.shutdown().await
}

#[tokio::test]
async fn prepend_empty_pages_preserve_coverage_and_append_does_not_replace_before()
-> anyhow::Result<()> {
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("reply-prefix", true).await?;
    let runtime = &fixture.host.runtime;
    let mut watch = ReplyWatch::open(runtime, &inbound.creation_id).await?;
    watch
        .select_target(runtime, "input", Some("target"))
        .await?;
    watch.stage(ChatBatch {
        placement: ChatPlacement::Set,
        entries: vec![text("newer", Some("target"), "final", "B")],
        before: Some("opaque-one".into()),
        current: Some(CurrentProjection::empty(1, ThreadStatus::Idle)),
    })?;
    watch.finish_pending().await?;
    assert!(watch.preview().is_none());
    let terminal = TurnState::Completed(pl_protocol::CompletedTurnState::new(
        None,
        1,
        pl_protocol::TurnCompletion::Normal,
    ));
    watch.stage(ChatBatch {
        placement: ChatPlacement::Append,
        entries: vec![message(
            "terminal",
            Some("target"),
            "turn",
            serde_json::json!({"outcome":terminal}),
            serde_json::json!([]),
        )],
        before: None,
        current: None,
    })?;
    watch.finish_pending().await?;
    assert_eq!(watch.before.as_deref(), Some("opaque-one"));
    assert!(matches!(
        watch.terminal("target"),
        Some(TurnState::Completed(_))
    ));
    assert!(watch.terminal("unknown").is_none());
    assert!(watch.projection().unwrap().completed().is_err());
    watch.stage(ChatBatch {
        placement: ChatPlacement::Prepend,
        entries: vec![],
        before: Some("opaque-two".into()),
        current: None,
    })?;
    watch.finish_pending().await?;
    assert_eq!(watch.before.as_deref(), Some("opaque-two"));
    assert!(watch.projection().unwrap().completed().is_err());
    watch.stage(ChatBatch {
        placement: ChatPlacement::Prepend,
        entries: vec![text("older", Some("target"), "final", "A")],
        before: None,
        current: None,
    })?;
    watch.finish_pending().await?;
    assert_eq!(watch.preview().as_deref(), Some("AB"));
    assert!(watch.projection().unwrap().completed().is_ok());
    watch.close().await?;
    fixture.shutdown().await
}

#[tokio::test]
async fn real_model_completion_reads_long_final_ranges_and_rebuilds_on_a_new_lease()
-> anyhow::Result<()> {
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use pl_core::thread::input::InputState;
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::{ModelInfo, ModelTransportProfile},
        protocol::ProtocolEndpoint,
    };
    use pl_protocol::studio::{CreateThreadRequest, NewThreadModelRoute, StudioPromptInput};
    use pl_provider_fixture::{FixtureServer, Protocol, ReplyStage, Step};

    const MODEL: &str = "reply-range-model";
    const PROMPT: &str = "reply-range-prompt";
    const COMMENTARY: &str = "local commentary before the answer";
    const LATE_COMMENTARY: &str = "local commentary after an existing answer";
    const HEAD: &str = "live Final answer: ";
    let tail = format!("{}END", "正文🙂\n".repeat(18_000));
    let expected = format!("{HEAD}{tail}");
    let start_stage = ReplyStage::new();
    let commentary_stage = ReplyStage::new();
    let final_stage = ReplyStage::new();
    let late_commentary_stage = ReplyStage::new();
    let mut segments = pl_provider_fixture::responses_reasoning_commentary_text_segments(
        &[],
        &[COMMENTARY],
        HEAD,
        &tail,
        "range-response",
        MODEL,
    )
    .into_iter();
    let mut commentary = segments.next().expect("provider prefix");
    let commentary_done = commentary
        .iter()
        .position(|event| {
            event["type"] == "response.output_item.done" && event["item"]["phase"] == "commentary"
        })
        .expect("explicit commentary item completion");
    // Hold actual Commentary current before its item completes; then hold Final
    // current before either the Final member or the Turn has completed.
    let final_head = commentary.split_off(commentary_done);
    let created = commentary.drain(..1).collect();
    let mut final_done_and_commentary = segments.next().expect("provider tail");
    final_done_and_commentary.extend(segments.next().expect("provider Final member completion"));
    final_done_and_commentary.extend([
        serde_json::json!({"type":"response.output_item.added","output_index":3,"item":{
            "id":"late-commentary","type":"message","role":"assistant","phase":"commentary","content":[]}}),
        serde_json::json!({"type":"response.output_text.delta","output_index":3,
            "item_id":"late-commentary","content_index":0,"delta":LATE_COMMENTARY}),
    ]);
    let late_item = serde_json::json!({
        "id":"late-commentary","type":"message","role":"assistant","phase":"commentary",
        "content":[{"type":"output_text","text":LATE_COMMENTARY}]
    });
    let mut terminal = segments.next().expect("provider Turn completion");
    terminal[0]["response"]["output"]
        .as_array_mut()
        .expect("response output")
        .push(late_item.clone());
    terminal.insert(
        0,
        serde_json::json!({"type":"response.output_item.done",
        "output_index":3,"item":late_item}),
    );
    let provider = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT,
        0,
        ReplyStage::staged(
            vec![
                created,
                commentary,
                final_head,
                final_done_and_commentary,
                terminal,
            ],
            &[
                &start_stage,
                &commentary_stage,
                &final_stage,
                &late_commentary_stage,
            ],
        ),
    )])
    .await?;
    let result = async {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let account = AccountId::new("reply-range-account")?;
    let mut model = ModelInfo::compatible(MODEL);
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.capabilities.instruction_snapshot_overrides = true;
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account.clone(),
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible("Reply range fixture", provider.base_url()),
            vec![model],
        ),
    );
    let route = ModelRouteConfig {
        account_id: account,
        model_id: MODEL.into(),
        effort: None,
    };
    for selected in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        *selected = route.clone();
    }
    ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
    let runtime = Box::pin(StudioRuntime::initialize(crate::StudioRuntimeOptions {
        studio_home: Some(home),
        host: crate::StudioHostKind::Test,
        ..crate::StudioRuntimeOptions::desktop()
    }))
    .await?;
    let result = async {
        let project = runtime.open_project(&workspace).await?;
        let started = Box::pin(runtime.create_thread_command(project.id, CreateThreadRequest {
            title:Some("Reply ranges".into()), input:StudioPromptInput { input_id:"range-input".into(), text:PROMPT.into(), attachment_draft_ids:vec![] },
            mode:pl_protocol::ThreadModeId::simple().to_string(), route:NewThreadModelRoute {
                account_id:"reply-range-account".into(), model_id:MODEL.into(), effort:None },
            delegation_mode:None, delegation_preference:None, workspace_mode:pl_protocol::ThreadWorkspaceMode::Local,
        }, None)).await?;
        let thread_id = started.thread.id;
        tokio::time::timeout(Duration::from_secs(20), start_stage.wait_reached()).await?;
        let target = tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                if let crate::bots::BotInputRead::Ready { state:InputState::Consumed { turn_id, .. }, .. } = runtime.bot_input_fact(&thread_id, "range-input").await? {
                    return Ok::<_, anyhow::Error>(turn_id);
                }
                tokio::task::yield_now().await;
            }
        }).await??;
        let mut watch = ReplyWatch::open(&runtime, &thread_id).await?;
        let observed = async {
            watch.select_target(&runtime, "range-input", Some(&target)).await?;
            anyhow::ensure!(watch.terminal(&target).is_none(), "target completed before its staged response");
            start_stage.release();
            tokio::time::timeout(Duration::from_secs(20), commentary_stage.wait_reached()).await?;
            receive_production_current(&mut watch, &target, ThreadTextChannel::Commentary, COMMENTARY).await?;
            anyhow::ensure!(watch.preview().is_none(), "Commentary must not authorize card creation");
            commentary_stage.release();
            tokio::time::timeout(Duration::from_secs(20), final_stage.wait_reached()).await?;
            receive_production_current(&mut watch, &target, ThreadTextChannel::Final, HEAD).await?;
            anyhow::ensure!(watch.terminal(&target).is_none(), "Final must be visible while the Turn is still live");
            anyhow::ensure!(watch.preview().as_deref() == Some(HEAD), "Final current did not produce its live preview");
            final_stage.release();
            tokio::time::timeout(Duration::from_secs(20), late_commentary_stage.wait_reached()).await?;
            receive_production_current(&mut watch, &target, ThreadTextChannel::Commentary, LATE_COMMENTARY).await?;
            anyhow::ensure!(watch.terminal(&target).is_none(), "Turn completed before late Commentary current");
            let card_preview = watch.preview().ok_or_else(|| anyhow::anyhow!("existing Final answer was lost"))?;
            anyhow::ensure!(expected.starts_with(&card_preview), "existing answer preview contains non-Final content");
            anyhow::ensure!(card_preview.starts_with(HEAD), "existing Final prefix changed");
            anyhow::ensure!(!card_preview.contains(COMMENTARY), "initial Commentary polluted the existing answer");
            anyhow::ensure!(!card_preview.contains(LATE_COMMENTARY), "live Commentary polluted the existing answer");
            // owner::advance_turn passes this exact preview to progress_card:
            // None cannot create a card; existing-card Content is built only from
            // Some(text). No fake platform counter or invented network result.
            late_commentary_stage.release();
            tokio::time::timeout(Duration::from_secs(20), async {
                while watch.terminal(&target).is_none() { watch.receive().await?; }
                Ok::<_, FinalError>(())
            }).await??;
            anyhow::ensure!(matches!(watch.terminal(&target), Some(TurnState::Completed(_))), "target did not complete normally");
            anyhow::ensure!(watch.terminal("other-turn").is_none(), "terminal leaked to another Turn");
            let projection = watch.projection().ok_or_else(|| anyhow::anyhow!("missing completed target projection"))?;
            let reader = watch.reader();
            let text = collect_complete_turn_text(&runtime, &reader, &projection).await?;
            anyhow::ensure!(matches!(text, FinalText::CompleteText(text) if text == expected), "canonical final text differs from the full answer");
            // Closing the original qualification must reject even a fully collected
            // projection, rather than publishing success from its cached preview.
            reader.close().await?;
            anyhow::ensure!(collect_complete_turn_text(&runtime, &reader, &projection).await.is_err(), "closed read qualification authorized final collection");
            watch.reconnect(&runtime).await?;
            watch.ensure_coverage().await?;
            // Coverage recovers only Main's prefix. The new lease must still
            // consume its queued typed State terminal and qualify the delivered
            // current/source cut; success has no synthetic Main receipt.
            tokio::time::timeout(Duration::from_secs(20), async {
                while watch.terminal(&target).is_none() { watch.receive().await?; }
                Ok::<_,FinalError>(())
            }).await??;
            anyhow::ensure!(matches!(watch.terminal(&target),Some(TurnState::Completed(_))),
                "new lease did not observe the real successful target terminal");
            let rebuilt = watch.projection().ok_or_else(|| anyhow::anyhow!("missing rebuilt target projection"))?;
            anyhow::ensure!(matches!(collect_complete_turn_text(&runtime, &watch.reader(), &rebuilt).await?, FinalText::CompleteText(text) if text == expected), "rebuilt final text differs from the full answer");
            Ok::<_, anyhow::Error>(())
        }.await;
        let closed = watch.close().await;
        observed?;
        closed?;
        Ok::<_, anyhow::Error>(())
    }.await;
    start_stage.release();
    commentary_stage.release();
    final_stage.release();
    late_commentary_stage.release();
    let shutdown = runtime.shutdown_runtime().await;
    result?;
    shutdown?;
    Ok::<_, anyhow::Error>(())
    }.await;
    start_stage.release();
    commentary_stage.release();
    final_stage.release();
    late_commentary_stage.release();
    let finished = provider.finish().await;
    result?;
    finished?;
    Ok(())
}
