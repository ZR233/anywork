//! Activation must make saved content available before the next reliable effect is prepared.
use super::*;
use crate::studio::storage::{
    history::{EffectCommit, HistoryStore},
    thread_writer::HistoryChannel,
};
use pl_core::{
    chat::{ChatHistory, ContentReadRequest, TimelineEpoch},
    model::{
        ActiveModelProgress, ModelProgress, ModelStartedMember, ObservedPart, ProviderPartIdentity,
    },
    thread::{AttemptOutcome, AttemptStatus, RequestAttempt, TurnRecord, TurnState},
};

async fn save(
    history: &HistoryStore,
    effect: &ThreadEffectBatch,
    prepared: &PreparedEffect,
) -> anyhow::Result<()> {
    history
        .commit_effect(
            effect.sequence,
            EffectCommit {
                items: &prepared.items,
                completions: &prepared.completions,
                current: &prepared.current,
                rolled_back_turns: &Default::default(),
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: effect.attempt.as_ref(),
            },
        )
        .await
}

#[derive(Debug, Clone, Copy)]
enum Settlement {
    Completed,
    Failed,
    Cancelled,
}

#[tokio::test]
async fn restored_multiwindow_generation_is_ready_for_immediate_completion() -> anyhow::Result<()> {
    immediate_settlement(Settlement::Completed).await
}

#[tokio::test]
async fn restored_multiwindow_generation_is_ready_for_immediate_failure() -> anyhow::Result<()> {
    immediate_settlement(Settlement::Failed).await
}

#[tokio::test]
async fn restored_multiwindow_generation_is_ready_for_immediate_cancellation() -> anyhow::Result<()>
{
    immediate_settlement(Settlement::Cancelled).await
}

async fn immediate_settlement(settlement: Settlement) -> anyhow::Result<()> {
    use anyhow::Context as _;
    use pl_core::context::OpaquePayload;
    use pl_model::{
        completion::{
            CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
            CompletionPresentationPartKind,
        },
        runtime::{ModelMemberReceipt, ModelMemberState},
    };

    let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime
                .create_thread(&env.project.id, "restore immediate completion")
                .await?,
        );
        // Synthetic effects use a real, separate database, not the Runtime coordinator's clock.
        let history =
            HistoryStore::open(&env._temp.path().join("restore-content.sqlite"), &thread.id)
                .await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("before-activation")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            turn_id: "restore-turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let mut state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            attempts: vec![RequestAttempt::new(
                "restore-turn".into(),
                "restore-attempt".into(),
                0,
                AttemptStatus::Running,
            )]
            .into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(turn),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        save(&history, &effect, &prepared).await?;
        let start = ModelStartedMember {
            turn_id: "restore-turn".into(),
            attempt_id: "restore-attempt".into(),
            generation: 0,
            identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
                item_id: "restore-text".into(),
                output_index: None,
                content_index: 0,
                item_kind: ObservedItemKind::Text(ModelTextChannel::Final),
                part: ObservedPartKind::OutputText,
            }),
        };
        let mut part = ObservedPart::new(start.identity.clone());
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 11,
            model_member_starts: vec![start].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        save(&history, &effect, &prepared).await?;

        let body = "新".repeat(50_000);
        // Exercise the real observation path: two authoritative replacements advance the original
        // current owner's content generation to 3. No private preview/generation state is edited.
        for (sequence, text) in [(3, "old body"), (4, "replacement"), (5, body.as_str())] {
            part = part.authorized(text);
            state.commit_sequence = sequence;
            state.model_progress = Some(ActiveModelProgress {
                attempt_id: "restore-attempt".into(),
                progress: ModelProgress::new(sequence, vec![part.clone()]),
            });
            projection.stream(&chat, &thread, &state, sequence).await?;
            let effect = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence,
                committed_at: sequence as i64 + 10,
                ..Default::default()
            };
            let (_, mut next) = projection.prepare(&thread, &effect, &state, false).await?;
            projection.publish_prepared(&chat, &mut next).await?;
            save(&history, &effect, &next).await?;
            prepared = next;
        }
        let saved_atom = prepared.current.projection.atoms[0].clone();
        let saved_content = prepared
            .current
            .contents
            .iter()
            .find(|write| write.content.descriptor.key.key == "body")
            .context("saved body")?
            .content
            .clone();
        assert_eq!(saved_content.descriptor.generation, 3);
        assert_eq!(saved_content.descriptor.byte_length, 150_000);
        let receipt = ModelMemberReceipt {
            item: CompletionPresentationItem {
                provider_item_id: "restore-text".into(),
                output_index: None,
                kind: CompletionPresentationItemKind::Text(
                    pl_protocol::trace::TraceTextChannel::Final,
                ),
                parts: vec![CompletionPresentationPart {
                    content_index: 0,
                    provider_part_id: None,
                    text: body.clone(),
                    kind: CompletionPresentationPartKind::OutputText,
                }],
            },
            state: ModelMemberState::Completed,
        };
        let mut effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 6,
            committed_at: 20,
            model_members: vec![pl_core::model::ModelCompletedMember {
                turn_id: "restore-turn".into(),
                attempt_id: "restore-attempt".into(),
                generation: 0,
                member_id: "restore-text".into(),
                payload: OpaquePayload::new(
                    "pl.model.completed-member",
                    1,
                    serde_json::to_string(&receipt)?,
                )?,
            }]
            .into(),
            ..Default::default()
        };
        let expected_outcome = match settlement {
            Settlement::Completed => pl_protocol::ChatTerminalOutcome::Completed,
            Settlement::Failed | Settlement::Cancelled => {
                // A terminal attempt may have no member receipt: its admitted preview is finalized
                // through the original attempt path, preserving the same saved body and refs.
                let error = Arc::new(pl_core::model::ModelError {
                    details: None,
                    kind: match settlement {
                        Settlement::Cancelled => pl_core::model::ModelFailureKind::Cancelled,
                        _ => pl_core::model::ModelFailureKind::Unavailable,
                    },
                    usage: Box::default(),
                    source: None,
                });
                let (status, outcome, terminal) = match settlement {
                    Settlement::Failed => (
                        AttemptStatus::Failed,
                        AttemptOutcome::Failed(error),
                        pl_protocol::ChatTerminalOutcome::Failed,
                    ),
                    Settlement::Cancelled => (
                        AttemptStatus::Cancelled,
                        AttemptOutcome::Cancelled { result: Err(error) },
                        pl_protocol::ChatTerminalOutcome::Cancelled,
                    ),
                    Settlement::Completed => unreachable!(),
                };
                state.attempts = vec![RequestAttempt::new(
                    "restore-turn".into(),
                    "restore-attempt".into(),
                    0,
                    status,
                )]
                .into();
                state.model_progress = None;
                effect.model_members = Arc::from([]);
                effect.attempt = Some(pl_core::thread::journal::AttemptUpdate {
                    turn_id: "restore-turn".into(),
                    attempt_id: "restore-attempt".into(),
                    retry_of: None,
                    input_revision: 0,
                    request_metadata: None,
                    usage_binding: None,
                    tool_projection: None,
                    tools: Arc::from([]),
                    outcome,
                    input_estimate: None,
                });
                terminal
            }
        };
        state.commit_sequence = effect.sequence;
        let restored_chat = Session::new(history.clone(), TimelineEpoch::new("after-activation")?);
        let restored_channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut restored = LiveProjection::new();
        restored.bind_execution_history(restored_channel.order_index(), history.clone())?;
        restored.bind_conversation_identity(database)?;
        restored
            .restore_current(&restored_chat, &thread, &state)
            .await?;
        let restored_snapshot = restored.current_state();

        // Nothing warms the restored owner between restore_current and its first reliable effect.
        let (_, mut completed) = restored.prepare(&thread, &effect, &state, false).await?;
        let content = completed
            .completion_drafts
            .as_ref()
            .context("completion drafts")?
            .iter()
            .flat_map(|draft| draft.contents.values())
            .find(|content| content.descriptor.key == saved_content.descriptor.key)
            .context("completion body")?
            .clone();
        eprintln!(
            "restore immediate {settlement:?}: saved_generation={}, bytes={}, completion_generation={}",
            saved_content.descriptor.generation,
            saved_content.descriptor.byte_length,
            content.descriptor.generation
        );
        restored
            .publish_prepared(&restored_chat, &mut completed)
            .await?;
        save(&history, &effect, &completed).await?;
        assert_eq!(content.descriptor, saved_content.descriptor);
        assert_eq!(content.data.range(0, 150_000)?.as_bytes(), body.as_bytes());
        let snapshot = restored_snapshot.context("restore returned without a current snapshot")?;
        assert_eq!(snapshot.projection.source_effect_seq, 5);
        assert_eq!(
            snapshot.projection.atoms.as_slice(),
            std::slice::from_ref(&saved_atom)
        );
        let handoff = completed.current_handoff.as_ref().context("handoff")?;
        assert_eq!(handoff.before.as_ref(), &snapshot.projection);
        assert_eq!(handoff.after.source_effect_seq, 6);
        assert!(handoff.after.atoms.is_empty());
        assert!(handoff.entries.is_empty(), "activation fabricated a reliable start");
        let completed_atom = completed
            .completions
            .iter()
            .map(|record| serde_json::from_slice::<pl_protocol::ChatAtom>(&record.header.metadata))
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .find(|atom| atom.id == saved_atom.id)
            .context("settled atom")?;
        assert_eq!(completed_atom.contents, saved_atom.contents);
        assert_eq!(completed_atom.source, saved_atom.source);
        assert_eq!(completed_atom.source_order, saved_atom.source_order);
        assert_eq!(completed_atom.started_at, saved_atom.started_at);
        assert!(matches!(completed_atom.lifecycle,
            pl_protocol::ChatAtomLifecycle::Terminal { outcome, started, .. }
                if outcome == expected_outcome && matches!(saved_atom.lifecycle,
                    pl_protocol::ChatAtomLifecycle::Active { started: old, .. } if old == started)));
        assert!(completed_atom.source_state.is_none());
        let restored_content = snapshot
            .contents
            .get(&saved_content.descriptor.key)
            .context("restored owner body")?
            .content();
        assert_eq!(restored_content.descriptor, saved_content.descriptor);
        assert_eq!(
            restored_content.data.range(0, 150_000)?.as_bytes(),
            body.as_bytes()
        );
        let mut bytes = Vec::new();
        while bytes.len() < body.len() {
            let window = ChatHistory::read_content(
                &history,
                &ContentReadRequest {
                    epoch: restored_chat.epoch(),
                    reference: pl_core::chat::ContentRef::Body(
                        saved_content.descriptor.key.clone(),
                    ),
                    offset: bytes.len() as u64,
                    max_bytes: 64 * 1024,
                    generation: Some(3),
                },
            )
            .await?;
            assert_eq!(window.generation, 3);
            assert_eq!(window.available_through, 150_000);
            assert!(window.sealed);
            assert!(!window.bytes.as_bytes().is_empty());
            bytes.extend_from_slice(window.bytes.as_bytes());
        }
        assert_eq!(bytes, body.as_bytes());
        assert!(
            restored.restore_current(&restored_chat, &thread, &state).await.is_err(),
            "activation restored twice"
        );
        eprintln!("restore immediate {settlement:?}: publication=Ok commit=Ok bytes=150000 generation=3 refs=unchanged");
        Ok(())
    }
    .await;
    env.finish(result).await
}
