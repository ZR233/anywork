use super::*;
use crate::bots::storage::{self, InboundAdmit, InboundClaim, WorkFinish};
use storage::card;
use storage::test_support::{v3_database, work_status};

#[tokio::test]
async fn migrated_card_intent_survives_reopen_and_fences_stale_writes() -> anyhow::Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("bot-state.sqlite");
    v3_database(&path).await.close().await?;
    let store = BotStateStore::new(path.clone());
    assert_eq!(
        store
            .claim_inbound_work("legacy", "chat", "m1", "w1")
            .await?,
        InboundClaim::Claimed
    );
    // The schema-6 card table coexists with every legacy fact. Its durable
    // pre-HTTP intent survives a reopen, while stale workers and stale card
    // versions cannot overwrite progress or turn an unknown into a retry.
    let card_binding = card::CardBinding {
        bot_id: "legacy".into(),
        chat_id: "chat".into(),
        message_id: "m1".into(),
        thread_id: "thread-1".into(),
        original_input: "bot:legacy:chat:m1".into(),
    };
    let mut card_state =
        card::CardStream::new(card_binding.clone(), "bot:legacy:chat:m1", "turn-1");
    card_state.reserve(card::CardAction::Create {
        text: "verified preview".into(),
    })?;
    assert_eq!(
        store.save_card(&mut card_state, "crashed-worker").await?,
        MarkOutcome::LostClaim
    );
    assert_eq!(
        store.save_card(&mut card_state, "w1").await?,
        MarkOutcome::Applied
    );
    let mut stale_card = card_state.clone();
    assert_eq!(
        store.save_card(&mut card_state, "w1").await?,
        MarkOutcome::Applied
    );
    assert_eq!(
        store.save_card(&mut stale_card, "w1").await?,
        MarkOutcome::LostClaim
    );
    assert_eq!(
        store
            .finish_inbound_work("legacy", "chat", "m1", "w1", WorkFinish::Completed)
            .await?,
        MarkOutcome::Applied
    );
    let (status, claimed_by) = work_status(&store, "legacy:chat:m1").await;
    assert_eq!(status, "completed");
    assert_eq!(claimed_by, "");
    assert_eq!(
        store.save_card(&mut card_state, "w1").await?,
        MarkOutcome::LostClaim
    );

    drop(store);
    let reopened = BotStateStore::new(path);
    let restored_card = reopened.load_card(&card_binding).await?.unwrap();
    assert!(restored_card.uncertain());
    assert_eq!(restored_card.version, card_state.version);
    assert!(restored_card.card_id.is_none());
    assert!(restored_card.platform_message_id.is_none());
    let operation = restored_card.last_operation.unwrap();
    assert!(matches!(
        operation.status,
        card::CardOperationStatus::Intent
    ));
    assert_eq!(operation.action.text(), Some("verified preview"));
    assert_eq!(
        operation.uuid,
        card_state.last_operation.as_ref().unwrap().uuid
    );
    Ok(())
}

/// New card JSON states survive the real v3 -> current ledger migration and
/// reopen. Fixtures start from a known preview; this proves storage/lease
/// transitions, not platform HTTP acceptance (covered by the observer).
#[tokio::test]
async fn migrated_card_progress_preserves_no_final_and_continuation_targets()
-> Result<(), Box<dyn std::error::Error>> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("bot-state.sqlite");
    drop(v3_database(&path).await);
    let store = BotStateStore::new(path.clone());
    let seed = store.list_due_inbound("legacy").await?.remove(0);
    assert_eq!(
        store
            .claim_inbound_work("legacy", "chat", "m1", "w1")
            .await?,
        InboundClaim::Claimed
    );
    let binding = card_test_binding("m1");
    let mut no_final = card_test_preview(binding.clone());
    // Even a previously confirmed content hash cannot turn a remaining
    // preview into the final answer when canonical Final becomes empty.
    no_final.final_content_hash = Some(no_final.confirmed_content_hash.clone());
    no_final.reserve(card::CardAction::Settings {
        streaming: false,
        lifecycle: card::CardLifecycle::NoFinalReply,
        recovery: false,
    })?;
    assert!(no_final.final_content_hash.is_none());
    assert_eq!(
        store.save_card(&mut no_final, "w1").await?,
        MarkOutcome::Applied
    );
    let mut stale_intent = no_final.clone();
    assert!(stale_intent.reserve(card::CardAction::Send).is_err());
    confirm_card_test_settings(&mut no_final, card::CardLifecycle::NoFinalReply);
    assert_eq!(
        store.save_card(&mut no_final, "w1").await?,
        MarkOutcome::Applied
    );
    assert_eq!(
        store.save_card(&mut stale_intent, "w1").await?,
        MarkOutcome::LostClaim
    );
    assert_eq!(
        store.save_card(&mut stale_intent, "crashed-worker").await?,
        MarkOutcome::LostClaim
    );
    assert_eq!(
        store
            .finish_inbound_work(
                "legacy",
                "chat",
                "m1",
                "w1",
                WorkFinish::NeedsAttention(card::CardLifecycle::NoFinalReply.summary())
            )
            .await?,
        MarkOutcome::Applied
    );

    let mut expected = Vec::new();
    for (message_id, turn_id, lifecycle, unknown) in [
        (
            "failed-continuation",
            Some("canonical-failed-turn"),
            card::CardLifecycle::Failed,
            true,
        ),
        (
            "cancelled-continuation",
            Some("canonical-cancelled-turn"),
            card::CardLifecycle::Cancelled,
            false,
        ),
        (
            "discarded-continuation",
            None,
            card::CardLifecycle::InteractionEnded,
            false,
        ),
    ] {
        let mut inbound = seed.clone();
        inbound.message_id = message_id.to_string();
        inbound.content_hash = format!("hash:{message_id}");
        assert!(matches!(
            store.admit_inbound(inbound).await?,
            InboundAdmit::Fresh(_)
        ));
        assert_eq!(
            store
                .claim_inbound_work("legacy", "chat", message_id, "w1")
                .await?,
            InboundClaim::Claimed
        );
        let binding = card_test_binding(message_id);
        let mut state = card_test_preview(binding.clone());
        state.reserve(card::CardAction::Settings {
            streaming: false,
            lifecycle: card::CardLifecycle::Paused,
            recovery: false,
        })?;
        confirm_card_test_settings(&mut state, card::CardLifecycle::Paused);
        assert_eq!(
            store.save_card(&mut state, "w1").await?,
            MarkOutcome::Applied
        );
        let mut previous_target = state.clone();
        let continuation = format!("canonical-input:{message_id}");
        assert_eq!(
            store
                .save_inbound_watch_input("legacy", "chat", message_id, "w1", &continuation)
                .await?,
            MarkOutcome::Applied
        );
        assert!(state.bind_target(&continuation, turn_id)?);
        assert_eq!(
            store.save_card(&mut state, "w1").await?,
            MarkOutcome::Applied
        );
        assert_eq!(
            store.save_card(&mut previous_target, "w1").await?,
            MarkOutcome::LostClaim
        );
        assert_eq!(
            store
                .save_card(&mut previous_target, "crashed-worker")
                .await?,
            MarkOutcome::LostClaim
        );
        state.reserve(card::CardAction::Settings {
            streaming: false,
            lifecycle,
            recovery: false,
        })?;
        assert_eq!(
            store.save_card(&mut state, "w1").await?,
            MarkOutcome::Applied
        );
        if unknown {
            state.last_operation.as_mut().unwrap().status = card::CardOperationStatus::Unknown;
            state.lifecycle = card::CardLifecycle::NeedsAttention;
        } else {
            confirm_card_test_settings(&mut state, lifecycle);
        }
        assert_eq!(
            store.save_card(&mut state, "w1").await?,
            MarkOutcome::Applied
        );
        expected.push((binding, continuation, turn_id, unknown, lifecycle));
    }
    drop(store);

    let reopened = BotStateStore::new(path);
    let no_final = reopened.load_card(&binding).await?.unwrap();
    assert!(matches!(
        no_final.lifecycle,
        card::CardLifecycle::NoFinalReply
    ));
    assert!(no_final.final_content_hash.is_none());
    assert_eq!(no_final.confirmed_text, "last verified preview");
    assert_eq!(no_final.diagnostic.as_ref().unwrap().code, "noFinalReply");
    assert_eq!(
        no_final.diagnostic.as_ref().unwrap().message,
        "未生成最终答复，所示内容仅为未完成预览"
    );
    assert!(no_final.lifecycle.terminal());
    let (status, _) = work_status(&reopened, "legacy:chat:m1").await;
    assert_eq!(status, "needs_attention");
    for (binding, continuation, turn_id, unknown, lifecycle) in expected {
        let mut state = reopened.load_card(&binding).await?.unwrap();
        assert_eq!(state.watch_input, continuation);
        assert_eq!(state.turn_id.as_deref(), turn_id);
        assert_eq!(state.confirmed_text, "last verified preview");
        assert!(state.final_content_hash.is_none());
        assert_eq!(state.uncertain(), unknown);
        if unknown {
            assert!(matches!(
                state.lifecycle,
                card::CardLifecycle::NeedsAttention
            ));
            assert!(
                state
                    .reserve(card::CardAction::Settings {
                        streaming: false,
                        lifecycle: card::CardLifecycle::NoFinalReply,
                        recovery: false,
                    })
                    .is_err()
            );
        } else {
            assert!(state.lifecycle == lifecycle);
            assert!(state.lifecycle.terminal());
        }
    }
    Ok(())
}

fn card_test_binding(message_id: &str) -> card::CardBinding {
    card::CardBinding {
        bot_id: "legacy".into(),
        chat_id: "chat".into(),
        message_id: message_id.into(),
        thread_id: "thread-1".into(),
        original_input: format!("bot:legacy:chat:{message_id}"),
    }
}

fn card_test_preview(binding: card::CardBinding) -> card::CardStream {
    let original_input = binding.original_input.clone();
    let mut state = card::CardStream::new(binding, &original_input, "original-turn");
    state.card_id = Some("known-card".into());
    state.platform_message_id = Some("known-message".into());
    state.confirmed_text = "last verified preview".into();
    state.confirmed_content_hash = card::hash(state.confirmed_text.as_bytes());
    state.lifecycle = card::CardLifecycle::Streaming;
    state
}

fn confirm_card_test_settings(state: &mut card::CardStream, lifecycle: card::CardLifecycle) {
    state.lifecycle = lifecycle;
    state.confirmed_sequence = state.sequence;
    state.last_operation.as_mut().unwrap().status = card::CardOperationStatus::Confirmed;
}
