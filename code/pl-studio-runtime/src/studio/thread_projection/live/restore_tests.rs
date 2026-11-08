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

pub(super) async fn save(
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

#[tokio::test]
async fn compaction_current_restores_without_an_item_and_settles_each_real_outcome()
-> anyhow::Result<()> {
    use anyhow::Context as _;
    use pl_core::thread::{ContextCompactionEvent as Event, ContextCompactionOutcome as Outcome};
    use pl_protocol::{
        ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind,
        ChatFactPosition, ChatSourceId, ChatSourceLifecycle, ChatTerminalOutcome,
    };

    let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime
                .create_thread(&env.project.id, "compaction restore")
                .await?,
        );
        for (case, outcome, terminal, associated) in [
            (
                "changed",
                Outcome::Changed {
                    context_revision: 9,
                },
                ChatTerminalOutcome::Completed,
                true,
            ),
            (
                "unchanged",
                Outcome::Unchanged,
                ChatTerminalOutcome::Completed,
                false,
            ),
            (
                "failed",
                Outcome::Failed {
                    message: "provider refused".into(),
                },
                ChatTerminalOutcome::Failed,
                true,
            ),
            (
                "cancelled",
                Outcome::Cancelled,
                ChatTerminalOutcome::Cancelled,
                false,
            ),
        ] {
            let history = HistoryStore::open(
                &env._temp.path().join(format!("compaction-{case}.sqlite")),
                &thread.id,
            )
            .await?;
            history.prepare_write().await?;
            let database = history
                .conversation_database_id()
                .await?
                .context("database")?;
            let session = Session::new(history.clone(), TimelineEpoch::new(case)?);
            let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
            let mut projection = LiveProjection::new();
            projection.bind_execution_history(channel.order_index(), history.clone())?;
            projection.bind_conversation_identity(database.clone())?;
            let state = ThreadSnapshot::default();
            let turn_id = associated.then(|| "actual-turn".to_owned());
            let attempt_id = associated.then(|| "actual-attempt".to_owned());
            let start_position = ChatFactPosition {
                effect_seq: 1,
                suborder: 1,
            };
            let source = ChatSourceId::Operation {
                operation_id: case.into(),
            };
            let effect = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 1,
                committed_at: 10,
                context_compactions: vec![Event::Started {
                    operation_id: case.into(),
                    turn_id: turn_id.clone(),
                    attempt_id: attempt_id.clone(),
                }]
                .into(),
                ..Default::default()
            };
            let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
            projection.publish_prepared(&session, &mut prepared).await?;
            assert_eq!(session.head_seq(), 0);
            assert!(prepared.items.is_empty() && prepared.completions.is_empty());
            let active = prepared
                .current
                .projection()
                .atoms
                .first()
                .context("active compaction")?
                .clone();
            assert_eq!(active.kind, ChatAtomKind::Compaction);
            assert_eq!(active.source, source);
            assert_eq!(active.delivery, ChatDeliveryKind::Independent);
            assert_eq!(active.turn_id, turn_id);
            assert_eq!(active.attempt_id, attempt_id);
            assert_eq!(
                active.lifecycle,
                ChatAtomLifecycle::Active {
                    started: Some(start_position),
                    status: ChatActiveStatus::Running,
                }
            );
            assert!(active.completion_seq.is_none() && active.payload.is_none());
            save(&history, &effect, &prepared).await?;
            drop(projection);
            // The reliable Started fact suffices; no current snapshot or business item was saved.
            let saved = history
                .conversation_current()
                .await?
                .context("saved current")?;
            assert_eq!(saved.atoms, vec![active.clone()]);
            assert!(!saved.execution_present);
            assert!(
                saved.active.is_none(),
                "cold facts do not claim a resident execution phase"
            );
            let mut restored = LiveProjection::new();
            restored.bind_execution_history(channel.order_index(), history.clone())?;
            restored.bind_conversation_identity(database)?;
            restored.restore_current(&session, &thread, &state).await?;
            assert_eq!(
                restored
                    .current_state()
                    .context("restored current")?
                    .projection()
                    .atoms,
                vec![active.clone()]
            );
            let unchanged = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 2,
                committed_at: 11,
                ..Default::default()
            };
            let mut prepared = restored
                .prepare_committed(&thread, &unchanged, &state)
                .await?;
            restored.publish_prepared(&session, &mut prepared).await?;
            assert!(
                prepared
                    .current_handoff
                    .as_ref()
                    .context("handoff")?
                    .entries()
                    .is_empty()
            );
            assert_eq!(prepared.current.projection().atoms, vec![active.clone()]);
            let effect = ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 3,
                committed_at: 12,
                context_compactions: vec![Event::Finished {
                    operation_id: case.into(),
                    outcome,
                }]
                .into(),
                ..Default::default()
            };
            let (_, mut prepared) = restored.prepare(&thread, &effect, &state, false).await?;
            restored.publish_prepared(&session, &mut prepared).await?;
            assert_eq!(session.head_seq(), 1);
            assert_eq!(prepared.completions.len(), 1);
            let atom: ChatAtom = serde_json::from_slice(&prepared.completions[0].header.metadata)?;
            assert_eq!(atom.id, active.id);
            assert_eq!(atom.source, source);
            assert_eq!(atom.delivery, ChatDeliveryKind::Independent);
            assert_eq!(atom.turn_id, turn_id);
            assert_eq!(atom.attempt_id, attempt_id);
            assert_eq!(atom.started_at, Some(10));
            let end_position = ChatFactPosition {
                effect_seq: 3,
                suborder: 1,
            };
            assert_eq!(
                atom.lifecycle,
                ChatAtomLifecycle::Terminal {
                    started: Some(start_position),
                    ended: Some(end_position),
                    outcome: terminal,
                }
            );
            assert!(prepared.current.projection().atoms.is_empty());
            assert!(prepared.current.projection().active.is_none());
            assert!(
                prepared
                    .current_handoff
                    .as_ref()
                    .context("end handoff")?
                    .sources()
                    .iter()
                    .any(|state| state.source == source
                        && state.lifecycle == ChatSourceLifecycle::Ended { outcome: terminal })
            );
            save(&history, &effect, &prepared).await?;
            assert!(
                history
                    .conversation_current()
                    .await?
                    .context("terminal saved current")?
                    .atoms
                    .is_empty()
            );
            let (_, mut repeated) = restored.prepare(&thread, &effect, &state, false).await?;
            restored.publish_prepared(&session, &mut repeated).await?;
            assert!(repeated.completions.is_empty());
            assert_eq!(session.head_seq(), 1);
        }
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[derive(Debug, Clone, Copy)]
enum Settlement {
    Completed,
    Failed,
    Cancelled,
}

#[tokio::test]
async fn cold_completion_uses_its_full_receipt_without_restoring_progress() -> anyhow::Result<()> {
    immediate_settlement(Settlement::Completed).await
}

#[tokio::test]
async fn resident_failure_freezes_its_accepted_prefix_only_at_terminal() -> anyhow::Result<()> {
    immediate_settlement(Settlement::Failed).await
}

#[tokio::test]
async fn resident_cancellation_freezes_its_accepted_prefix_only_at_terminal() -> anyhow::Result<()>
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
        let saved_atom = prepared.current.projection().atoms[0].clone();
        assert!(prepared.current.contents.is_empty());
        let saved_content = prepared.current_state.as_ref().context("current owner")?
            .contents().values().find(|content| content.descriptor.key.key == "body")
            .context("active body")?.content();
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
        let mut restored = if matches!(settlement, Settlement::Completed) {
            let mut owner = LiveProjection::new();
            // The Runtime's original index owns execution placement, independently of
            // this dropped/re-created product projection and its discarded progress.
            owner.bind_execution_history(channel.order_index(), history.clone())?;
            owner.bind_conversation_identity(database)?;
            owner.restore_current(&restored_chat, &thread, &state).await?;
            assert!(owner.current_state().context("restored current")?.contents().is_empty());
            owner
        } else {
            projection
        };
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
        let expected_generation = if matches!(settlement, Settlement::Completed) { 1 } else { 3 };
        assert_eq!(content.descriptor.generation, expected_generation);
        assert_eq!(content.data.range(0, 150_000)?.as_bytes(), body.as_bytes());
        let completed_atom = completed.completions.iter()
            .map(|record| serde_json::from_slice::<pl_protocol::ChatAtom>(&record.header.metadata))
            .collect::<Result<Vec<_>, _>>()?.into_iter()
            .find(|atom| atom.id == saved_atom.id).context("settled atom")?;
        assert_eq!(completed_atom.source, saved_atom.source);
        assert_eq!(completed_atom.source_order, saved_atom.source_order);
        assert!(matches!(completed_atom.lifecycle, pl_protocol::ChatAtomLifecycle::Terminal {outcome,..}
            if outcome == expected_outcome));
        assert!(completed_atom.source_state.is_none());
        if matches!(settlement, Settlement::Completed) {
            let snapshot = restored_snapshot.context("restored current")?;
            assert!(snapshot.projection().previews.is_empty());
            assert!(snapshot.contents().is_empty());
        }
        let mut bytes = Vec::new();
        while bytes.len() < body.len() {
            let window = ChatHistory::read_content(&history, &ContentReadRequest {
                epoch: restored_chat.epoch(), reference: pl_core::chat::ContentRef::Body(content.descriptor.key.clone()),
                offset: bytes.len() as u64, max_bytes: 64 * 1024, generation: Some(expected_generation),
            }).await?;
            assert_eq!(window.available_through, 150_000);
            assert!(window.sealed);
            assert!(!window.bytes.as_bytes().is_empty());
            bytes.extend_from_slice(window.bytes.as_bytes());
        }
        assert_eq!(bytes, body.as_bytes());
        Ok(())
    }
    .await;
    env.finish(result).await
}
