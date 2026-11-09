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

fn started_body(
    prepared: &PreparedEffect,
    kind: ChatAtomKind,
    database: &str,
) -> Result<pl_protocol::ChatAtomContent> {
    let atom = prepared
        .current
        .atom_facts
        .iter()
        .find(|atom| {
            atom.kind == kind && matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. })
        })
        .context("reliable active start")?;
    assert_eq!(
        atom.contents.len(),
        1,
        "start must carry its allocated body"
    );
    let content = &atom.contents[0];
    assert_eq!(content.reference.database_id, database);
    let pl_protocol::ContentTarget::Body { owner, key } = &content.reference.target else {
        anyhow::bail!("start content is not a canonical body");
    };
    assert_eq!(
        owner,
        &pl_protocol::ContentOwner::Item {
            item_id: atom.id.clone()
        }
    );
    let current_key = pl_core::chat::ChatContentKey {
        owner: crate::studio::conversation_identity::content_owner_key(owner)?,
        key: key.clone(),
    };
    let current = prepared
        .current_state
        .as_ref()
        .context("frozen current owner")?
        .contents()
        .get(&current_key)
        .context("start reference resolves to its real allocated body")?;
    assert_eq!(current.descriptor.byte_length, 0, "no token is required");
    assert_eq!(
        prepared
            .display
            .as_ref()
            .context("frozen display")?
            .members
            .iter()
            .find(|member| member.head.atom.id == atom.id)
            .context("display member")?
            .head
            .atom
            .contents,
        atom.contents
    );
    Ok(content.clone())
}

#[tokio::test]
async fn reliable_permission_status_changes_update_display_without_rewriting_start() -> Result<()> {
    use pl_core::{
        context::{ContextRecord, ContextSource},
        model::ModelToolCall,
        thread::{
            journal::ContextChange,
            permissions::{PermissionRecord, PermissionState},
            task::{TaskRecord, TaskStatus},
        },
    };
    use pl_protocol::{ChatActiveStatus, DisplayBlockBody};

    let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime
                .create_thread(&env.project.id, "display permission changes")
                .await?,
        );
        let path = env._temp.path().join("display-permission.sqlite");
        let history = HistoryStore::open(&path, &thread.id).await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let sql = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("display-permission")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            turn_id: "boundary-turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let task = TaskRecord {
            id: "task:approval-call".into(),
            call_id: "approval-call".into(),
            tool_id: "exec".into(),
            turn_id: turn.turn_id.clone(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(1),
        };
        let record = ContextRecord {
            id: "call-record".into(),
            turn_id: Some(turn.turn_id.clone()),
            source: ContextSource::Assistant,
            content: Vec::new(),
            tool_calls: vec![ModelToolCall {
                call_id: task.call_id.clone(),
                tool_id: task.tool_id.clone(),
                arguments: OpaquePayload::new("pl.tool.input", 1, "{}")?,
                presentation_contract: None,
                rejection: None,
            }],
        };
        let mut state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            attempts: vec![RequestAttempt::new(
                "boundary-turn".into(),
                "boundary-attempt".into(),
                0,
                AttemptStatus::Running,
            )]
            .into(),
            ..Default::default()
        };
        state.context.revision = 1;
        state.context.records = vec![record.clone()].into();
        state
            .live_calls
            .insert(task.call_id.clone(), task.turn_id.clone());
        state.tasks.insert(task.id.clone(), task.clone());
        let effect = |sequence| ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence,
            committed_at: sequence as i64 + 10,
            ..Default::default()
        };
        let mut first = effect(1);
        first.turn = Some(turn);
        first.context = Some(ContextChange::Append {
            revision: 1,
            records: vec![record].into(),
        });
        first.tasks = vec![task.clone()].into();
        let prepared = publish(&mut projection, &history, &chat, &thread, &state, &first).await?;
        let tool_atom = prepared
            .current
            .atom_facts
            .iter()
            .find(|atom| atom.kind == ChatAtomKind::ToolCall)
            .context("original tool start")?
            .clone();
        let owner = projection.presentation();
        let first_cut = owner.lock().unwrap().capture(None, 1, 0, 1);
        let block_id = first_cut.open[0].id.clone();
        let structure_revision = first_cut.revision;
        let mut previous_revision = first_cut.open[0].revision;
        let mut changes = owner.lock().unwrap().subscribe_members();
        let start_row = || {
            sea_orm::Statement::from_sql_and_values(
                sea_orm::DbBackend::Sqlite,
                "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase='start'",
                vec![tool_atom.id.clone().into()],
            )
        };
        let original_start: Vec<u8> = sql
            .query_one_raw(start_row())
            .await?
            .context("start row")?
            .try_get("", "metadata")?;

        let mut permission = PermissionRecord {
            id: "approval".into(),
            task_id: task.id.clone(),
            call_id: task.call_id.clone(),
            turn_id: task.turn_id.clone(),
            tool_id: task.tool_id.clone(),
            revision: 1,
            created_at: 12,
            updated_at: 12,
            response: None,
            state: PermissionState::Pending,
            payload: OpaquePayload::new(
                "pl.studio.tool-approval",
                1,
                serde_json::to_string(&serde_json::json!({
                    "name": "exec",
                    "arguments": OpaquePayload::new("pl.tool.input", 1, "{}")?,
                    "workingDirectory": "/workspace",
                }))?,
            )?,
        };
        for (sequence, status, waiting, running) in [
            (2, PermissionState::Pending, 1, 0),
            (3, PermissionState::Allowed, 0, 1),
        ] {
            permission.state = status;
            permission.revision = sequence - 1;
            permission.updated_at = sequence as i64 + 10;
            state
                .permissions
                .insert(permission.id.clone(), permission.clone());
            state.interaction_collection_revision = sequence - 1;
            let mut update = effect(sequence);
            update.permissions = vec![permission.clone()].into();
            let prepared =
                publish(&mut projection, &history, &chat, &thread, &state, &update).await?;
            assert!(
                !prepared
                    .current
                    .atom_facts
                    .iter()
                    .any(|atom| atom.id == tool_atom.id),
                "a status transition is not a replacement start fact"
            );
            let cut = owner
                .lock()
                .unwrap()
                .member_cut(&block_id, None, 2)
                .context("hot member cut")?;
            let DisplayBlockBody::Work { summary, .. } = &cut.header.body else {
                panic!("work")
            };
            assert_eq!(
                (
                    summary.total,
                    summary.terminal,
                    summary.waiting,
                    summary.running
                ),
                (1, 0, waiting, running)
            );
            assert!(cut.header.revision > previous_revision);
            previous_revision = cut.header.revision;
            assert_eq!(
                owner.lock().unwrap().capture(None, 1, 0, 1).revision,
                structure_revision
            );
            assert!(changes.has_changed()?);
            changes.borrow_and_update();
            let expected = if waiting == 1 {
                ChatActiveStatus::Waiting
            } else {
                ChatActiveStatus::Running
            };
            assert!(matches!(cut.overlay[0].head.atom.lifecycle,
                ChatAtomLifecycle::Active { status, .. } if status == expected));
            let saved = history
                .display_member_page(&database, &block_id, None, 2)
                .await?;
            assert_eq!(saved.header.as_ref(), cut.header.as_ref());
            assert_eq!(saved.entries[0], *cut.overlay[0]);
            assert_eq!(
                sql.query_one_raw(start_row())
                    .await?
                    .context("preserved start")?
                    .try_get::<Vec<u8>>("", "metadata")?,
                original_start
            );
        }
        let before_token = history
            .display_member_page(&database, &block_id, None, 2)
            .await?;
        let mut part = ObservedPart::new(started("preview-only").identity);
        for version in 1..=2 {
            part = part.authorized(&"token".repeat(version as usize));
            state.model_progress = Some(ActiveModelProgress {
                attempt_id: "boundary-attempt".into(),
                progress: ModelProgress::new(version, vec![part.clone()]),
            });
            projection.stream(&chat, &thread, &state, 3).await?;
        }
        let after_token = owner
            .lock()
            .unwrap()
            .member_cut(&block_id, None, 2)
            .context("after token")?;
        assert_eq!(after_token.header.as_ref(), before_token.header.as_ref());
        assert!(!changes.has_changed()?);
        assert_eq!(
            history
                .display_member_page(&database, &block_id, None, 2)
                .await?
                .entries,
            before_token.entries
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn reliable_text_start_hands_off_work_without_a_new_atomic_completion() -> Result<()> {
    let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = pl_protocol::Thread::from(
            env.runtime
                .create_thread(&env.project.id, "display boundary")
                .await?,
        );
        let history = HistoryStore::open(
            &env._temp.path().join("display-boundary.sqlite"),
            &thread.id,
        )
        .await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let chat = Session::new(history.clone(), TimelineEpoch::new("display-start")?);
        let channel = HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        let turn = TurnRecord {
            turn_id: "boundary-turn".into(),
            input_id: None,
            state: TurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        };
        let mut state = ThreadSnapshot {
            turns: vec![turn.clone()].into(),
            attempts: vec![RequestAttempt::new("boundary-turn".into(), "boundary-attempt".into(), 0, AttemptStatus::Running)].into(),
            ..Default::default()
        };
        let effect = |sequence| ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence,
            committed_at: sequence as i64 + 10,
            ..Default::default()
        };
        let mut first = effect(1);
        first.turn = Some(turn);
        first.model_member_starts = vec![started("R")].into();
        let first_prepared = publish(&mut projection, &history, &chat, &thread, &state, &first).await?;
        started_body(&first_prepared, ChatAtomKind::Reasoning, &database)?;
        let mut second = effect(2);
        let receipt = ModelMemberReceipt {
            item: CompletionPresentationItem {
                provider_item_id: "R".into(),
                output_index: None,
                kind: CompletionPresentationItemKind::Reasoning,
                parts: vec![CompletionPresentationPart {
                    kind: CompletionPresentationPartKind::ReasoningText,
                    content_index: 0,
                    provider_part_id: None,
                    text: "完整思考".into(),
                }],
            },
            state: ModelMemberState::Completed,
        };
        second.model_members = vec![pl_core::model::ModelCompletedMember {
            turn_id: "boundary-turn".into(),
            attempt_id: "boundary-attempt".into(),
            generation: 0,
            member_id: "R".into(),
            payload: OpaquePayload::new(
                "pl.model.completed-member",
                1,
                serde_json::to_string(&receipt)?,
            )?,
        }]
        .into();
        publish(&mut projection, &history, &chat, &thread, &state, &second).await?;
        let h = chat.head_seq();
        let presentation = projection.presentation();
        {
            let owner = presentation.lock().unwrap();
            let cut = owner.capture(None, 8, 0, 8);
            assert_eq!(cut.published, 0);
            assert!(
                matches!(&cut.open[0].body, pl_protocol::DisplayBlockBody::Work { summary, .. }
                if summary.total == 1 && summary.terminal == 1)
            );
        }
        let mut text = started("T");
        text.identity = ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: "T".into(),
            output_index: None,
            content_index: 0,
            item_kind: ObservedItemKind::Text(pl_core::model::ModelTextChannel::Final),
            part: ObservedPartKind::OutputText,
        });
        let mut third = effect(3);
        third.model_member_starts = vec![text].into();
        let prepared = publish(&mut projection, &history, &chat, &thread, &state, &third).await?;
        let text_body = started_body(&prepared, ChatAtomKind::Text, &database)?;
        assert_eq!(chat.head_seq(), h);
        assert!(prepared.completions.is_empty());
        assert_eq!(prepared.display.as_ref().unwrap().published_through, 1);
        assert!(Arc::ptr_eq(
            prepared.display.as_ref().unwrap(),
            prepared.current.display.as_ref().unwrap()
        ));
        let cold = history
            .display_recovery()
            .await?
            .context("saved display cut")?;
        assert_eq!(cold.published, 1);
        assert_eq!(cold.open.len(), 1);
        assert_eq!(cold.unfinished.len(), 1);
        let mut recovered = super::super::presentation::PresentationState::default();
        recovered.restore(
            &database,
            cold.published,
            cold.last_order,
            cold.effect,
            cold.open,
            cold.unfinished,
        )?;
        assert!(
            !recovered
                .member_cut(
                    &prepared
                        .display
                        .as_ref()
                        .unwrap()
                        .blocks
                        .iter()
                        .find(|b| b.header.history_pos.is_none())
                        .unwrap()
                        .header
                        .id,
                    None,
                    8
                )
                .unwrap()
                .complete
        );
        let completed_id = &prepared.display.as_ref().unwrap().blocks.iter()
            .find(|block| block.header.history_pos.is_some()).context("completed work")?.header.id;
        assert!(presentation.lock().unwrap().member_cut(completed_id,None,8).context("retained completed member")?
            .overlay.iter().any(|member| member.terminal));
        presentation.lock().unwrap().begin_cost_observation();
        let mut part = ObservedPart::new(third.model_member_starts[0].identity.clone());
        for version in 1..=2 {
            part = part.authorized(&"正文 token".repeat(version as usize));
            state.model_progress = Some(ActiveModelProgress {
                attempt_id:"boundary-attempt".into(), progress:ModelProgress::new(version,vec![part.clone()]),
            });
            projection.stream(&chat,&thread,&state,3).await?;
        }
        let pl_protocol::ContentTarget::Body { owner, key } = &text_body.reference.target else {
            unreachable!("started_body checked the target");
        };
        let current_key = pl_core::chat::ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(owner)?,
            key: key.clone(),
        };
        assert!(
            projection.current.snapshot().context("streamed current")?
                .contents().get(&current_key).context("same body after tokens")?
                .descriptor.byte_length > 0
        );
        let visits = presentation.lock().unwrap().finish_cost_observation();
        assert_eq!((visits.members.reads,visits.members.writes,visits.heads.reads,visits.heads.writes),(0,0,0,0));
        eprintln!("PRESENTATION_COST {}",serde_json::json!({
            "event":"production_token_preview", "token_updates":2, "retained_completed_members_at_least":1,
            "member_reads":visits.members.reads, "member_writes":visits.members.writes,
            "head_reads":visits.heads.reads, "head_writes":visits.heads.writes,
        }));
        projection.confirm_sources(3);
        assert_eq!(
            presentation.lock().unwrap().capture(None, 8, 0, 8).durable,
            1
        );
        super::restore_tests::save(&history, &third, &prepared).await?; // exact lost-ACK replay
        Ok(())
    }
    .await;
    env.finish(result).await
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
