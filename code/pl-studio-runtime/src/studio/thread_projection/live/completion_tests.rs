//! Producer ports → original projection → Session → real HistoryStore transaction.
use super::*;
use crate::studio::storage::{history::HistoryStore, thread_writer::HistoryChannel};
use anyhow::{Context, Result};
use pl_core::{
    chat::{ChatHistory, ContentReadRequest, TimelineEpoch},
    context::OpaquePayload,
    model::{
        ActiveModelProgress, ModelProgress, ModelStartedMember, ObservedItemKind, ObservedPart,
        ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
    },
    thread::{AttemptOutcome, AttemptStatus, RequestAttempt, TurnRecord, TurnState},
};
use pl_model::{
    completion::{
        CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
        CompletionPresentationPartKind,
    },
    runtime::{ModelMemberReceipt, ModelMemberState},
};
use pl_protocol::{ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatTerminalOutcome};
use sea_orm::{ConnectionTrait, Database};

fn started(id: &str) -> ModelStartedMember {
    ModelStartedMember {
        turn_id: "boundary-turn".into(),
        attempt_id: "boundary-attempt".into(),
        generation: 0,
        identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: id.into(),
            output_index: None,
            content_index: 0,
            item_kind: ObservedItemKind::Reasoning,
            part: ObservedPartKind::ReasoningText,
        }),
    }
}

async fn publish(
    projection: &mut LiveProjection,
    history: &HistoryStore,
    chat: &Session,
    thread: &pl_protocol::Thread,
    state: &ThreadSnapshot,
    effect: &ThreadEffectBatch,
) -> Result<Arc<PreparedEffect>> {
    let (_, mut prepared) = projection.prepare(thread, effect, state, false).await?;
    projection.publish_prepared(chat, &mut prepared).await?;
    super::restore_tests::save(history, effect, &prepared).await?;
    Ok(prepared)
}

#[tokio::test]
async fn progress_never_writes_prefix_and_real_restart_interrupt_preserves_completed_member()
-> Result<()> {
    let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = pl_protocol::Thread::from(env.runtime.create_thread(
            &env.project.id, "completion boundary",
        ).await?);
        let path = env._temp.path().join("completion-boundary.sqlite");
        let history = HistoryStore::open(&path, &thread.id).await?;
        history.prepare_write().await?;
        let database = history.conversation_database_id().await?.context("database")?;
        let sql = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("before-restart")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord { turn_id:"boundary-turn".into(),input_id:None,
            state:TurnState::Running,elapsed_ms:None,model_steps:1 };
        let mut state = ThreadSnapshot { turns:vec![turn.clone()].into(),
            attempts:vec![RequestAttempt::new("boundary-turn".into(),"boundary-attempt".into(),0,AttemptStatus::Running)].into(), ..Default::default() };
        let effect = |sequence| ThreadEffectBatch { thread_id:thread.id.clone(),sequence,
            committed_at:sequence as i64 + 10, ..Default::default() };
        let mut first = effect(1);
        first.turn = Some(turn);
        first.model_member_starts = vec![started("A")].into();
        publish(&mut projection,&history,&chat,&thread,&state,&first).await?;
        let mut part = ObservedPart::new(started("A").identity);
        for sequence in 2..=5 {
            let prefix = "流式前缀".repeat(sequence as usize * 4096);
            part = part.authorized(&prefix);
            state.model_progress = Some(ActiveModelProgress {
                attempt_id:"boundary-attempt".into(),
                progress:ModelProgress::new(sequence,vec![part.clone()]),
            });
            state.commit_sequence = sequence;
            projection.stream(&chat,&thread,&state,sequence).await?;
            let prepared = publish(&mut projection,&history,&chat,&thread,&state,&effect(sequence)).await?;
            assert!(prepared.current.contents.is_empty(), "progress prepared a body write");
            let row=sql.query_one_raw(sea_orm::Statement::from_string(sea_orm::DbBackend::Sqlite,
                "SELECT (SELECT COUNT(*) FROM conversation_contents) AS bodies,
                        (SELECT COUNT(*) FROM conversation_items) AS items".to_owned()))
                .await?.context("counts")?;
            assert_eq!(row.try_get::<i64>("","bodies")?,0);
            assert_eq!(row.try_get::<i64>("","items")?,0);
        }
        let full = "完整思考".repeat(40_000);
        let receipt=ModelMemberReceipt { item:CompletionPresentationItem {
            provider_item_id:"A".into(),output_index:None,kind:CompletionPresentationItemKind::Reasoning,
            parts:vec![CompletionPresentationPart {content_index:0,provider_part_id:None,text:full.clone(),
                kind:CompletionPresentationPartKind::ReasoningText}],
        },state:ModelMemberState::Completed };
        let mut complete=effect(6);
        complete.model_members=vec![pl_core::model::ModelCompletedMember {
            turn_id:"boundary-turn".into(),attempt_id:"boundary-attempt".into(),generation:0,
            member_id:"A".into(),payload:OpaquePayload::new("pl.model.completed-member",1,
                serde_json::to_string(&receipt)?)?,
        }].into();
        state.model_progress=None;
        let saved=publish(&mut projection,&history,&chat,&thread,&state,&complete).await?;
        let record=saved.completions.iter().find(|record| record.contents.values()
            .any(|content| content.descriptor.byte_length==full.len() as u64)).context("A record")?;
        let a_id=record.header.item_id.clone();
        let content=record.contents.values().find(|content| content.descriptor.byte_length==full.len() as u64)
            .context("A body")?;
        let window=ChatHistory::read_content(&history,&ContentReadRequest {
            epoch:chat.epoch(),reference:pl_core::chat::ContentRef::Body(content.descriptor.key.clone()),
            offset:0,max_bytes:64*1024,generation:Some(content.descriptor.generation),
        }).await?;
        assert!(window.sealed);
        assert_eq!(window.available_through,full.len() as u64);
        assert_eq!(window.bytes.as_bytes(),&full.as_bytes()[..64*1024]);
        assert_eq!(record.header.append_seq, 1, "a completed member must publish immediately");
        let mut second=effect(7);
        second.model_member_starts=vec![started("B")].into();
        publish(&mut projection,&history,&chat,&thread,&state,&second).await?;
        drop(projection);
        drop(chat);
        drop(channel);
        // A passive cold read does not manufacture an interruption or restore a preview.
        let current=history.conversation_current().await?.context("cold current")?;
        assert!(!current.execution_present);
        assert!(current.previews.is_empty());
        let restored_chat=Session::new(history.clone(),TimelineEpoch::new("after-restart")?);
        let restored_channel=HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut restored=LiveProjection::new();
        restored.bind_execution_history(restored_channel.order_index(),history.clone())?;
        restored.bind_conversation_identity(database.clone())?;
        state.attempts=vec![RequestAttempt::new("boundary-turn".into(),"boundary-attempt".into(),
            0,AttemptStatus::Interrupted)].into();
        restored.restore_current(&restored_chat,&thread,&state).await?;
        assert!(restored.current_state().context("restored current")?.contents().is_empty());
        let mut interrupted=effect(8);
        interrupted.turn=Some(TurnRecord {turn_id:"boundary-turn".into(),input_id:None,
            state:TurnState::Interrupted,elapsed_ms:None,model_steps:1});
        interrupted.attempt=Some(pl_core::thread::journal::AttemptUpdate {
            turn_id:"boundary-turn".into(),attempt_id:"boundary-attempt".into(),retry_of:None,
            input_revision:0,request_metadata:None,usage_binding:None,tool_projection:None,
            tools:Arc::from([]),outcome:AttemptOutcome::Interrupted,input_estimate:None,
        });
        state.turns=vec![interrupted.turn.clone().unwrap()].into();
        state.commit_sequence=8;
        let settled=publish(&mut restored,&history,&restored_chat,&thread,&state,&interrupted).await?;
        assert!(settled.completions.iter().all(|record| record.header.item_id!=a_id));
        assert!(settled.current.projection().atoms.is_empty());
        let members=sql.query_all_raw(sea_orm::Statement::from_string(sea_orm::DbBackend::Sqlite,
            "SELECT atom_id,phase,metadata FROM conversation_atom_facts WHERE phase='terminal'".to_owned())).await?;
        let metadata=members.iter().find_map(|row| {
            let atom:ChatAtom=serde_json::from_slice(&row.try_get::<Vec<u8>>("","metadata").ok()?).ok()?;
            (atom.id != a_id && atom.kind==ChatAtomKind::Reasoning).then_some(atom)
        }).context("interrupted B fact")?;
        assert!(matches!(metadata.lifecycle,ChatAtomLifecycle::Terminal {outcome:ChatTerminalOutcome::Cancelled,
            started:Some(_),ended:Some(at)} if at.effect_seq==8));
        assert!(metadata.completion_item_id.is_none() && metadata.completion_seq.is_none()
            && metadata.payload.is_none() && metadata.contents.is_empty());
        assert!(history.recovery_atom_starts(None,128).await?.is_empty());
        Ok(())
    }.await;
    env.finish(result).await
}
