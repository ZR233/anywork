use super::*;
use crate::studio::thread_projection::{LiveProjection, PreparedEffect};
use pl_core::{
    context::OpaquePayload,
    model::{
        ModelCompletedMember, ModelStartedMember, ModelTextChannel, ObservedItemKind,
        ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
    },
    thread::{
        ThreadEffectBatch, ThreadSnapshot as CoreSnapshot, TurnRecord, TurnState as CoreTurnState,
    },
};
use pl_model::{
    completion::{
        CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
        CompletionPresentationPartKind,
    },
    runtime::{ModelMemberReceipt, ModelMemberState},
};

pub(super) fn start(id: &str, reasoning: bool) -> ModelStartedMember {
    ModelStartedMember {
        turn_id: "atomic-turn".into(),
        attempt_id: "atomic-attempt".into(),
        generation: 0,
        identity: ObservedPartIdentity::Provider(ProviderPartIdentity {
            item_id: id.into(),
            output_index: None,
            content_index: 0,
            item_kind: if reasoning {
                ObservedItemKind::Reasoning
            } else {
                ObservedItemKind::Text(ModelTextChannel::Final)
            },
            part: if reasoning {
                ObservedPartKind::ReasoningText
            } else {
                ObservedPartKind::OutputText
            },
        }),
    }
}

pub(super) fn finish(id: &str, reasoning: bool, text: &str) -> Result<ModelCompletedMember> {
    let receipt = ModelMemberReceipt {
        item: CompletionPresentationItem {
            provider_item_id: id.into(),
            output_index: None,
            kind: if reasoning {
                CompletionPresentationItemKind::Reasoning
            } else {
                CompletionPresentationItemKind::Text(pl_protocol::trace::TraceTextChannel::Final)
            },
            parts: vec![CompletionPresentationPart {
                content_index: 0,
                provider_part_id: None,
                text: text.into(),
                kind: if reasoning {
                    CompletionPresentationPartKind::ReasoningText
                } else {
                    CompletionPresentationPartKind::OutputText
                },
            }],
        },
        state: ModelMemberState::Completed,
    };
    Ok(ModelCompletedMember {
        turn_id: "atomic-turn".into(),
        attempt_id: "atomic-attempt".into(),
        generation: 0,
        member_id: id.into(),
        payload: OpaquePayload::new(
            "pl.model.completed-member",
            1,
            serde_json::to_string(&receipt)?,
        )?,
    })
}

fn publish(
    source: &super::super::super::thread_observation::ThreadLiveFeed,
    session: &core::Session,
    prepared: &Arc<PreparedEffect>,
) -> Result<()> {
    source.publish_test_conversation(
        session,
        prepared.current_state.clone().context("prepared current")?,
        prepared.current_handoff.clone(),
        prepared.current.timeline_update.generation(),
    )
}

pub(super) struct Harness {
    pub thread: Thread,
    pub history: crate::studio::storage::history::HistoryStore,
    pub session: core::Session,
    pub projection: LiveProjection,
    pub source: Arc<super::super::super::thread_observation::ThreadLiveFeed>,
    pub sequence: u64,
    _owner: watch::Sender<super::super::super::thread_observation::Progress>,
}
impl Harness {
    pub async fn new(env: &support::Environment) -> Result<Self> {
        let (delta, directory_session, agent) =
            crate::studio::store::directory::DirectoryDelta::register_session(
                crate::studio::ids::new_id("timeline-fixture"),
                &env.project.id,
                "timeline fixture",
                ThreadModeId::simple(),
                ThreadWorkspaceMode::Local,
                env.project.path.clone(),
                crate::config::ROOT_AGENT_ROUTE_KEY,
            );
        let thread = crate::studio::records::thread_projection(&directory_session, &agent);
        env.runtime
            .agent_facility
            .product_events
            .commit_directory(delta)
            .await?;
        assert!(env.runtime.threads.observed_thread(&thread.id).is_none());
        let history = env.runtime.store.history(&thread.id).await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let session = env.runtime.store.chat_session(&thread.id).await?;
        let channel = env
            .runtime
            .store
            .thread_persistence()
            .history_channel(&thread.id);
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database)?;
        projection.observe_test_current(&thread, Vec::new())?;
        let (owner, progress) = watch::channel(Default::default());
        let source =
            Arc::new(super::super::super::thread_observation::ThreadLiveFeed::new(None, progress));
        env.runtime
            .thread_observations
            .observation_slot(&thread.id)
            .install(source.clone());
        source.publish_test_conversation(
            &session,
            projection.current_state().context("initial")?,
            None,
            projection.timeline_generation(),
        )?;
        Ok(Self {
            thread,
            history,
            session,
            projection,
            source,
            sequence: 0,
            _owner: owner,
        })
    }
    pub async fn effect(
        &mut self,
        starts: Vec<ModelStartedMember>,
        members: Vec<ModelCompletedMember>,
    ) -> Result<Arc<PreparedEffect>> {
        self.sequence += 1;
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let state = CoreSnapshot {
            turns: vec![turn.clone()].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: self.thread.id.clone(),
            sequence: self.sequence,
            committed_at: self.sequence as i64 + 10,
            turn: Some(turn),
            model_member_starts: starts.into(),
            model_members: members.into(),
            ..Default::default()
        };
        let (_, mut prepared) = self
            .projection
            .prepare(&self.thread, &effect, &state, false)
            .await?;
        self.projection
            .publish_prepared(&self.session, &mut prepared)
            .await?;
        publish(&self.source, &self.session, &prepared)?;
        Ok(prepared)
    }
    pub async fn save(&self, prepared: &PreparedEffect) -> Result<()> {
        save_effect(&self.history, &self.session, prepared).await
    }
}

async fn save_effect(
    history: &crate::studio::storage::history::HistoryStore,
    session: &core::Session,
    prepared: &PreparedEffect,
) -> Result<()> {
    use crate::studio::storage::history::EffectCommit;
    history
        .commit_effect(
            prepared.sequence,
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
                attempt: None,
            },
        )
        .await?;
    session.confirm_durable(
        prepared
            .completions
            .iter()
            .map(|item| item.header.append_seq)
            .max()
            .unwrap_or(session.durable_seq()),
    )?;
    Ok(())
}

async fn read_all_timeline(
    history: &crate::studio::storage::history::HistoryStore,
    scope: ChatScope,
    size: u32,
) -> Result<Vec<ChatEntry>> {
    let mut before = None;
    let mut result = Vec::new();
    loop {
        let page = history
            .timeline_page(
                &scope,
                before,
                i64::MAX as u64,
                4,
                ReadDemand {
                    max_items: size,
                    ..demand()
                },
                0,
            )
            .await?;
        let mut entries = page.entries;
        entries.extend(result);
        result = entries;
        let Some(next) = page.before else { break };
        ensure!(
            before.is_none_or(|old| next < old),
            "pagination did not advance"
        );
        before = Some(next);
    }
    Ok(result)
}

fn logical_timeline(mut entries: Vec<ChatEntry>) -> Vec<ChatEntry> {
    for entry in &mut entries {
        if let ChatEntry::Item(item) = entry
            && let Some(reference) = &mut item.members
        {
            reference.projection_generation = "logical".into();
        }
    }
    entries
}

#[tokio::test]
async fn failed_display_fold_retains_original_publication_for_retry_without_advancing_position()
-> Result<()> {
    use sea_orm::{ConnectionTrait, Database};
    let env = support::Environment::new(vec![], vec![]).await?;
    let result=async {
        let mut harness=Harness::new(&env).await?;
        let path=env.runtime.store.registered_session_paths(&harness.thread.id)?.history_database();
        let db=Database::connect(format!("sqlite://{}?mode=rw",path.display())).await?;
        db.execute_unprepared("UPDATE timeline_projection_state SET next_position=9223372036854775807 WHERE singleton_id=1").await?;
        db.close().await?;
        let turn=TurnRecord {elapsed_ms:None,input_id:None,turn_id:"atomic-turn".into(),state:CoreTurnState::Running,model_steps:1};
        let state=CoreSnapshot {turns:vec![turn.clone()].into(),..Default::default()};
        let effect=ThreadEffectBatch {thread_id:harness.thread.id.clone(),sequence:1,committed_at:11,turn:Some(turn),
            model_member_starts:vec![start("overflow-text",false)].into(),
            model_members:vec![finish("overflow-text",false,"must not disappear on retry")?].into(),..Default::default()};
        let (_,mut prepared)=harness.projection.prepare(&harness.thread,&effect,&state,false).await?;
        assert!(harness.projection.publish_prepared(&harness.session,&mut prepared).await.is_err());
        assert_eq!(prepared.completions.len(),1);
        let record=prepared.completions[0].clone();
        let head=harness.session.head_seq();
        assert!(prepared.completion_drafts.is_some());
        assert!(prepared.timeline.is_empty());
        assert!(harness.projection.publish_prepared(&harness.session,&mut prepared).await.is_err(),
            "retry filtered its own record and silently succeeded");
        assert_eq!(harness.session.head_seq(),head);
        assert!(Arc::ptr_eq(&prepared.completions[0],&record));
        assert!(prepared.timeline.is_empty());
        assert!(harness.projection.current_state().context("unchanged current")?.projection().items.is_empty());
        Ok::<_,anyhow::Error>(())
    }.await;
    env.finish(result).await
}

#[tokio::test]
async fn first_tool_prepare_publishes_argument_head_but_preserves_original_start_bytes()
-> Result<()> {
    use pl_core::{
        context::{ContextRecord, ContextSnapshot, ContextSource},
        model::ModelToolCall,
        thread::{
            journal::ContextChange,
            task::{TaskRecord, TaskStatus},
        },
    };
    use sea_orm::{ConnectionTrait, Database, DatabaseBackend, Statement};
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = Harness::new(&env).await?;
        let arguments = r#"{"path":"sample.txt"}"#;
        let task = TaskRecord {
            id: "task-head".into(),
            call_id: "call-head".into(),
            tool_id: "unknown-head-tool".into(),
            turn_id: "atomic-turn".into(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(1),
        };
        let records = vec![ContextRecord {
            id: "request-head".into(),
            turn_id: Some("atomic-turn".into()),
            source: ContextSource::Assistant,
            content: vec![],
            tool_calls: vec![ModelToolCall {
                call_id: task.call_id.clone(),
                tool_id: task.tool_id.clone(),
                arguments: OpaquePayload::new("application/json", 1, arguments)?,
                presentation_contract: None,
                rejection: None,
            }],
        }];
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let state = CoreSnapshot {
            turns: vec![turn.clone()].into(),
            context: ContextSnapshot {
                revision: 1,
                records: records.clone().into(),
            },
            tasks: std::collections::BTreeMap::from([(task.id.clone(), task.clone())]),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: harness.thread.id.clone(),
            sequence: 1,
            committed_at: 11,
            turn: Some(turn),
            tasks: vec![task].into(),
            context: Some(ContextChange::Append {
                revision: 1,
                records: records.into(),
            }),
            ..Default::default()
        };
        let (_, mut prepared) = harness
            .projection
            .prepare(&harness.thread, &effect, &state, false)
            .await?;
        harness
            .projection
            .publish_prepared(&harness.session, &mut prepared)
            .await?;
        publish(&harness.source, &harness.session, &prepared)?;
        assert!(
            prepared.completions.is_empty(),
            "active tool manufactured a completion"
        );
        let frozen = prepared
            .current
            .timeline_update
            .facts()
            .iter()
            .find(|atom| atom.kind == ChatAtomKind::ToolCall)
            .context("original tool start")?;
        assert!(
            frozen.contents.is_empty(),
            "fixture did not exercise separate start/head stages"
        );
        let head = prepared
            .current
            .projection()
            .atoms
            .iter()
            .find(|atom| atom.id == frozen.id)
            .context("mutable tool head")?;
        let arguments_ref = head
            .contents
            .iter()
            .find(|content| content.role == ChatContentRole::ToolArguments)
            .context("current argument reference")?
            .reference
            .clone();
        let member = prepared
            .current
            .timeline_update
            .members()
            .iter()
            .rev()
            .find(|member| member.atom.id == frozen.id)
            .context("latest member head")?;
        assert_eq!(
            member.atom.contents, head.contents,
            "publication dropped the latest mutable head"
        );
        assert_eq!(member.atom.lifecycle, head.lifecycle);
        let reference = prepared
            .current
            .projection()
            .items
            .iter()
            .find_map(|item| item.members.clone())
            .context("group")?;
        let mut group = env
            .runtime
            .open_conversation_feed(
                &harness.thread.id,
                ChatScope::GroupMembers { reference },
                demand(),
            )
            .await?;
        let set = chat(&mut group).await?;
        let atom = set
            .entries
            .iter()
            .find_map(|entry| {
                if let ChatEntry::Atom(atom) = entry {
                    Some(atom)
                } else {
                    None
                }
            })
            .context("first member Set")?;
        assert_eq!(atom.id, frozen.id);
        assert_eq!(atom.contents, head.contents);
        assert_eq!(atom.lifecycle, head.lifecycle);
        let window = group
            .reader()
            .read_content(
                &arguments_ref,
                ContentRange {
                    offset: 0,
                    max_bytes: arguments.len() as u32,
                },
            )
            .await?;
        assert_eq!(window.bytes, arguments.as_bytes());
        harness.save(&prepared).await?;
        let path = env
            .runtime
            .store
            .registered_session_paths(&harness.thread.id)?
            .history_database();
        let db = Database::connect(format!("sqlite://{}?mode=ro", path.display())).await?;
        let row = db
            .query_one_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase='start'",
                vec![frozen.id.clone().into()],
            ))
            .await?
            .context("stored immutable start")?;
        assert_eq!(
            row.try_get::<Vec<u8>>("", "metadata")?,
            serde_json::to_vec(frozen)?
        );
        db.close().await?;
        group.close().await?;
        group.reader().close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&harness.thread.id)
            .retire(&harness.source);
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn reliable_starts_reverse_completion_and_member_window_use_real_item_feed() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = Harness::new(&env).await?;
        let one = ReadDemand {
            max_items: 1,
            ..demand()
        };
        let mut main = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, one)
            .await?;
        assert!(chat(&mut main).await?.entries.is_empty());
        let started = harness
            .effect(vec![start("reasoning", true), start("text", false)], vec![])
            .await?;
        assert_eq!(
            harness.session.head_seq(),
            0,
            "starts manufactured an atomic completion"
        );
        let current = chat(&mut main).await?;
        assert!(current.entries.is_empty(), "Main delivered start atoms");
        let current = current.current.context("current")?;
        assert_eq!(current.items.len(), 2);
        let reference = current.items[0]
            .members
            .clone()
            .context("group reference")?;
        assert_eq!(
            current.items[0]
                .summary
                .as_ref()
                .context("summary")?
                .active_count,
            1
        );
        let mut group = env
            .runtime
            .open_conversation_feed(
                &harness.thread.id,
                ChatScope::GroupMembers {
                    reference: reference.clone(),
                },
                one,
            )
            .await?;
        let initial = chat(&mut group).await?;
        assert!(initial.current.is_none());
        let [ChatEntry::Atom(reasoning)] = initial.entries.as_slice() else {
            bail!("member Set must contain an Atom");
        };
        assert!(matches!(
            reasoning.lifecycle,
            ChatAtomLifecycle::Active {
                started: Some(_),
                ..
            }
        ));
        assert!(
            !reasoning.contents.is_empty(),
            "first live part lost its mutable content reference"
        );
        let current_text = started
            .current
            .projection()
            .atoms
            .iter()
            .find(|atom| atom.kind == ChatAtomKind::Text)
            .context("live text head")?;
        let text_item = started
            .current
            .projection()
            .items
            .iter()
            .find(|item| item.kind == TimelineItemKind::Text)
            .context("live text Item")?;
        assert_eq!(text_item.contents, current_text.contents);
        assert!(
            !text_item.contents.is_empty(),
            "first live Text Item lost its content owner"
        );
        let member_id = reasoning.id.clone();
        harness.save(&started).await?;
        let text = harness
            .effect(
                vec![],
                vec![finish("text", false, "visible before reasoning ends")?],
            )
            .await?;
        let interim = chat(&mut main).await?;
        assert!(
            interim.entries.is_empty(),
            "text crossed its unfinished foreground prefix"
        );
        let text_current = interim.current.context("interim current")?;
        assert_eq!(text_current.items.len(), 2);
        assert_eq!(
            text_current.items[1].outcome,
            Some(ChatTerminalOutcome::Completed)
        );
        assert!(text_current.items[1].content_item_id.is_some());
        harness.save(&text).await?;
        let end = harness
            .effect(vec![], vec![finish("reasoning", true, "done")?])
            .await?;
        let first = chat(&mut main).await?;
        let [ChatEntry::Item(item)] = first.entries.as_slice() else {
            bail!("first frame is not one Item");
        };
        assert_eq!(item.kind, TimelineItemKind::WorkGroup);
        assert_eq!(item.position, Some(0));
        assert_eq!(item.outcome, None);
        let suffix = first.current.as_ref().context("split current")?;
        assert_eq!(
            suffix.items.len(),
            1,
            "undelivered text vanished from current"
        );
        assert_eq!(suffix.items[0].kind, TimelineItemKind::Text);
        let exact = ReadDemand {
            max_items: 1,
            max_bytes: u32::try_from(first.encoded_len()?)?,
        };
        main.reader().finish_batch(first.clone(), exact)?;
        assert!(
            main.reader()
                .finish_batch(
                    first,
                    ReadDemand {
                        max_bytes: exact.max_bytes - 1,
                        ..exact
                    }
                )
                .is_err()
        );
        let second = chat(&mut main).await?;
        let [ChatEntry::Item(text)] = second.entries.as_slice() else {
            bail!("second frame is not a text Item");
        };
        assert_eq!(text.kind, TimelineItemKind::Text);
        assert_eq!(text.position, Some(1));
        assert!(
            second
                .current
                .as_ref()
                .context("retired current")?
                .items
                .is_empty()
        );
        let terminal = tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                let update = chat(&mut group).await?;
                for entry in update.entries {
                    match entry {
                        ChatEntry::Atom(atom) => {
                            assert_eq!(atom.id, member_id, "opened member window changed identity");
                            if matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }) {
                                return Ok::<_, anyhow::Error>(atom);
                            }
                        }
                        ChatEntry::Source(state) => assert_eq!(state.source, reasoning.source),
                        ChatEntry::Item(_) => bail!("GroupMembers delivered a Main Item"),
                    }
                }
            }
        })
        .await??;
        let completed_atoms = end
            .completions
            .iter()
            .map(|record| serde_json::from_slice::<ChatAtom>(&record.header.metadata))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let completed = completed_atoms
            .iter()
            .find(|atom| atom.id == member_id)
            .context("R's original terminal")?;
        assert_eq!(terminal.completion_item_id, completed.completion_item_id);
        assert_eq!(terminal.lifecycle, completed.lifecycle);
        assert_eq!(terminal.contents, completed.contents);
        // The member window cursor cannot become a Main continuation, even when
        // both pages happened to contain one row at position zero.
        assert!(
            group
                .reader()
                .load_older("not a cursor", one)
                .await
                .is_err()
        );
        harness.save(&end).await?;
        let reader = main.reader().clone();
        let PayloadData::Inline { bytes: original } =
            text.payload.as_ref().context("inline text")?
        else {
            bail!("short text was not delivered typed");
        };
        let body = ContentRef {
            database_id: harness
                .history
                .conversation_database_id()
                .await?
                .context("database")?,
            target: ContentTarget::ItemPayload {
                item_id: text
                    .content_item_id
                    .clone()
                    .context("original content owner")?,
            },
        };
        main.close().await?;
        let bytes = reader
            .read_content(
                &body,
                ContentRange {
                    offset: 0,
                    max_bytes: u32::try_from(original.len())?,
                },
            )
            .await?;
        assert_eq!(
            &bytes.bytes, original,
            "closing delivery invalidated its independent reader"
        );
        reader.close().await?;
        assert!(
            reader
                .read_content(
                    &body,
                    ContentRange {
                        offset: 0,
                        max_bytes: 1
                    }
                )
                .await
                .is_err()
        );
        group.close().await?;
        group.reader().close().await?;
        env.runtime
            .thread_observations
            .observation_slot(&harness.thread.id)
            .retire(&harness.source);
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn source_rebuild_retires_old_ref_and_old_readers_without_changing_item_identity()
-> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = Harness::new(&env).await?;
        let first = harness.effect(vec![start("work", true)], vec![]).await?;
        harness.save(&first).await?;
        let second = harness
            .effect(vec![], vec![finish("work", true, "work")?])
            .await?;
        harness.save(&second).await?;
        let third = harness.effect(vec![start("text", false)], vec![]).await?;
        assert!(
            third.completions.is_empty(),
            "text-start invented an atom completion"
        );
        assert_eq!(
            third.timeline.len(),
            1,
            "text-start failed to commit its terminal work group"
        );
        harness.save(&third).await?;
        let mut old = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, demand())
            .await?;
        let initial = chat(&mut old).await?;
        let [ChatEntry::Item(item)] = initial.entries.as_slice() else {
            bail!("expected work item");
        };
        let old_reference = item.members.clone().context("reference")?;
        let id = item.id.clone();
        let generation = old_reference.projection_generation.clone();
        let slot = env
            .runtime
            .thread_observations
            .observation_slot(&harness.thread.id);
        slot.retire(&harness.source);
        harness.history.maintain_timeline().await?;
        assert_ne!(harness.history.timeline_generation().await?, generation);
        assert!(
            old.reader()
                .list_contents(&id, None, demand())
                .await
                .is_err()
        );
        let stale = env
            .runtime
            .open_conversation_feed(
                &harness.thread.id,
                ChatScope::GroupMembers {
                    reference: old_reference,
                },
                demand(),
            )
            .await;
        assert!(matches!(
            stale.unwrap_err().downcast_ref::<core::ChatError>(),
            Some(core::ChatError::StaleContent)
        ));
        let mut reopened = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, demand())
            .await?;
        let set = chat(&mut reopened).await?;
        let [ChatEntry::Item(item)] = set.entries.as_slice() else {
            bail!("rebuild changed the logical page");
        };
        assert_eq!(item.id, id);
        assert_eq!(item.summary.as_ref().context("summary")?.member_count, 1);
        assert!(
            !set.current
                .as_ref()
                .context("cold current")?
                .execution_present
        );
        assert_eq!(set.current.as_ref().context("cold current")?.items.len(), 1);
        old.close().await?;
        old.reader().close().await?;
        reopened.close().await?;
        reopened.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn background_result_precedes_unfinished_foreground_and_mid_set_preserves_both_sources()
-> Result<()> {
    background_order_case(false, false).await
}

#[tokio::test]
async fn recovery_settle_source_end_precedes_earlier_background_ordinal_in_both_prepare_paths()
-> Result<()> {
    for committed in [false, true] {
        background_order_case(true, committed).await?;
    }
    Ok(())
}

async fn background_order_case(recovered: bool, committed: bool) -> Result<()> {
    use pl_core::{
        context::{
            AgentMessageKind, ContextContent, ContextRecord, ContextSnapshot, ContextSource,
        },
        model::ModelToolCall,
        thread::{
            ToolDelivery, ToolOutcome,
            inbox::{InboxRecord, ThreadMessage},
            journal::ContextChange,
            task::{TaskAcknowledgement, TaskRecord, TaskStatus},
        },
    };
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        // This test owns the projection and its synthetic Core effects. Register only the durable
        // directory fact: create_thread also activates a real observation worker, which would race
        // this owner over the same execution index and overwrite its completion identity knowledge.
        let (delta, directory_session, agent) =
            crate::studio::store::directory::DirectoryDelta::register_session(
                "background-order".into(),
                &env.project.id,
                "background order",
                pl_protocol::ThreadModeId::simple(),
                pl_protocol::ThreadWorkspaceMode::Local,
                env.project.path.clone(),
                crate::config::ROOT_AGENT_ROUTE_KEY,
            );
        let thread = crate::studio::records::thread_projection(&directory_session, &agent);
        env.runtime
            .agent_facility
            .product_events
            .commit_directory(delta)
            .await?;
        assert!(env.runtime.threads.observed_thread(&thread.id).is_none());
        let history = env.runtime.store.history(&thread.id).await?;
        history.prepare_write().await?;
        let database = history
            .conversation_database_id()
            .await?
            .context("database")?;
        let session = env.runtime.store.chat_session(&thread.id).await?;
        let channel = env
            .runtime
            .store
            .thread_persistence()
            .history_channel(&thread.id);
        let mut projection = LiveProjection::new();
        projection.bind_execution_history(channel.order_index(), history.clone())?;
        projection.bind_conversation_identity(database)?;
        projection.observe_test_current(&thread, Vec::new())?;
        let (_owner, progress) = watch::channel(Default::default());
        let source =
            Arc::new(super::super::super::thread_observation::ThreadLiveFeed::new(None, progress));
        env.runtime
            .thread_observations
            .observation_slot(&thread.id)
            .install(source.clone());
        source.publish_test_conversation(
            &session,
            projection.current_state().context("initial")?,
            None,
            projection.timeline_generation(),
        )?;
        let background_turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "background-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let mut task = TaskRecord {
            id: "task-b".into(),
            call_id: "call-b".into(),
            tool_id: "arbitrary".into(),
            turn_id: "background-turn".into(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: Some(TaskAcknowledgement {
                record_id: "ack-b".into(),
                context_revision: 1,
            }),
            started_sequence: Some(1),
        };
        let records = vec![
            ContextRecord {
                id: "request-b".into(),
                turn_id: Some("background-turn".into()),
                source: ContextSource::Assistant,
                content: vec![],
                tool_calls: vec![ModelToolCall {
                    call_id: "call-b".into(),
                    tool_id: "arbitrary".into(),
                    arguments: OpaquePayload::new("application/json", 1, "{}")?,
                    presentation_contract: None,
                    rejection: None,
                }],
            },
            ContextRecord {
                id: "ack-b".into(),
                turn_id: Some("background-turn".into()),
                source: ContextSource::ToolResult {
                    call_id: "call-b".into(),
                    tool_id: "arbitrary".into(),
                },
                content: vec![ContextContent::Text {
                    text: "background accepted".into(),
                }],
                tool_calls: vec![],
            },
        ];
        let mut state = CoreSnapshot {
            turns: vec![background_turn.clone()].into(),
            context: ContextSnapshot {
                revision: 1,
                records: records.clone().into(),
            },
            ..Default::default()
        };
        state.tasks.insert(task.id.clone(), task.clone());
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            turn: Some(background_turn.clone()),
            tasks: vec![task.clone()].into(),
            context: Some(ContextChange::Append {
                revision: 1,
                records: records.into(),
            }),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        if recovered { save_effect(&history,&session,&prepared).await?; }
        let ack: ChatAtom = serde_json::from_slice(&prepared.completions[0].header.metadata)?;
        assert_eq!(ack.delivery, ChatDeliveryKind::BackgroundHandoff);
        assert!(matches!(
            ack.lifecycle,
            ChatAtomLifecycle::Terminal {
                outcome: ChatTerminalOutcome::Transferred,
                ..
            }
        ));
        publish(&source, &session, &prepared)?;
        let cancelled = TurnRecord {
            state: CoreTurnState::Cancelled,
            ..background_turn
        };
        state.turns = vec![cancelled.clone()].into();
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 11,
            turn: Some(cancelled),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        if recovered { save_effect(&history,&session,&prepared).await?; }
        publish(&source, &session, &prepared)?;
        let foreground = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Running,
            model_steps: 1,
        };
        let mut turns = state.turns.to_vec();
        turns.push(foreground.clone());
        state.turns = turns.into();
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 3,
            committed_at: 12,
            turn: Some(foreground.clone()),
            model_member_starts: vec![if recovered { start("ready-work",true) } else { start("unfinished-t", false) }].into(),
            model_members: if recovered { vec![finish("ready-work",true,"done before recovery")?].into() } else { Default::default() },
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        if recovered {
            save_effect(&history,&session,&prepared).await?;
            assert!(prepared.timeline.is_empty());
            let group=prepared.current.projection().items.first().context("open G")?;
            assert!(!group.admission_closed);
            assert_eq!(group.summary.as_ref().context("G summary")?.active_count,0);
        }
        publish(&source, &session, &prepared)?;
        if recovered {
            // Frozen complete ThreadWrite shape produced by Core recovery::settle
            // (recovery.rs:115-163 / background::append_result_message). Task b
            // was admitted before turn V, and retains that execution ordinal.
            let payload=OpaquePayload::text("Task interrupted by runtime restart.");
            let output_context=vec![ContextContent::Text {text:"Task interrupted by runtime restart; it was not re-executed.".into()}];
            let mut context=output_context.clone();
            context.insert(0,ContextContent::Text {text:format!("Task {} for tool {} finished: Interrupted.",task.id,task.tool_id).into()});
            let inbox=InboxRecord {sequence:1,message:ThreadMessage {id:"task-result:1".into(),source_id:task.id.clone(),
                kind:AgentMessageKind::Report,payload:payload.clone(),context:context.clone()}};
            let delivery=ToolDelivery {
                target:pl_core::thread::ToolDeliveryTarget::Inbox {message_id:inbox.message.id.clone()},
                call_id:task.call_id.clone(),tool_id:task.tool_id.clone(),
                output:pl_core::tool::ToolOutput::new(payload,output_context),
                delivered_context:context,outcome:ToolOutcome::Interrupted,
            };
            task.status=TaskStatus::Interrupted;task.revision+=1;
            let interrupted=TurnRecord {state:CoreTurnState::Interrupted,..foreground};
            let mut turns=state.turns.to_vec();*turns.last_mut().context("V")?=interrupted.clone();state.turns=turns.into();
            state.tasks.insert(task.id.clone(),task.clone());
            state.deliveries=vec![delivery.clone()].into();state.inbox=vec![inbox.clone()].into();
            let effect=ThreadEffectBatch {thread_id:thread.id.clone(),sequence:4,committed_at:13,
                turn:Some(interrupted),tasks:vec![task].into(),deliveries:vec![delivery].into(),inbox:vec![inbox].into(),..Default::default()};
            let mut prepared=if committed {projection.prepare_committed(&thread,&effect,&state).await?}
                else {projection.prepare(&thread,&effect,&state,false).await?.1};
            assert!(prepared.timeline.is_empty(),"prepare exposed a different commit partition");
            projection.publish_prepared(&session,&mut prepared).await?;
            let original_u=history.item(&crate::studio::thread_projection::order::turn_id("background-turn")).await?
                .context("original terminal U")?;
            if let Some(reobserved)=prepared.items.iter().find(|item|item.id==original_u.id) {
                assert_eq!(reobserved,&original_u,"B's effect restamped a sealed old Turn");
            }
            assert_eq!(prepared.timeline.iter().map(|item|item.kind).collect::<Vec<_>>(),
                vec![TimelineItemKind::WorkGroup,TimelineItemKind::Status,TimelineItemKind::Status]);
            assert!(matches!(prepared.timeline[1].source,ChatSourceId::BackgroundResult {..}));
            assert_eq!(prepared.timeline[2].outcome,Some(ChatTerminalOutcome::Cancelled));
            let terminals=prepared.completions.iter().filter(|record|record.header.query_class=="conversation")
                .map(|record|serde_json::from_slice::<ChatAtom>(&record.header.metadata)).collect::<std::result::Result<Vec<_>,_>>()?;
            assert!(matches!(terminals[0].source,ChatSourceId::BackgroundResult {..}),"fixture lost original b ordinal");
            let source_end=prepared.current.source_changes.iter().find(|source|source.source==(ChatSourceId::ForegroundTurn {turn_id:"atomic-turn".into()}))
                .context("V source end")?;
            assert_eq!(source_end.ended,Some(ChatFactPosition {effect_seq:4,suborder:0}));
            save_effect(&history,&session,&prepared).await?;
            publish(&source,&session,&prepared)?;
            let before=read_all_timeline(&history,ChatScope::Main,1).await?;
            let ChatEntry::Item(group)=before.iter().find(|entry|matches!(entry,ChatEntry::Item(item) if item.kind==TimelineItemKind::WorkGroup))
                .context("G before rebuild")? else {unreachable!()};
            let members_before=read_all_timeline(&history,ChatScope::GroupMembers {reference:group.members.clone().context("G ref")?},1).await?;
            use sea_orm::{ConnectionTrait,Database,Statement,DatabaseBackend};
            let path=env.runtime.store.registered_session_paths(&thread.id)?.history_database();
            let db=Database::connect(format!("sqlite://{}?mode=rw",path.display())).await?;
            let source_key=serde_json::to_string(&source_end.source)?;
            let end=db.query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
                "SELECT ended_effect,ended_suborder FROM conversation_sources WHERE source_key=?",vec![source_key.into()])).await?.context("stored V end")?;
            assert_eq!(end.try_get::<i64>("","ended_effect")?,4);
            assert_eq!(end.try_get::<i64>("","ended_suborder")?,0);
            // Rebuild from source facts, not a copy of the old derived snapshot.
            db.execute_unprepared("DROP TABLE timeline_item_members;DROP TABLE timeline_items;DROP TABLE timeline_projection_state;").await?;
            db.close().await?;
            history.maintain_timeline().await?;
            for size in [1,2,17] {
                let after=read_all_timeline(&history,ChatScope::Main,size).await?;
                assert_eq!(logical_timeline(before.clone()),logical_timeline(after.clone()));
                let ChatEntry::Item(group)=after.iter().find(|entry|matches!(entry,ChatEntry::Item(item) if item.kind==TimelineItemKind::WorkGroup))
                    .context("rebuilt G")? else {unreachable!()};
                assert_eq!(members_before,read_all_timeline(&history,ChatScope::GroupMembers {reference:group.members.clone().context("rebuilt G ref")?},size).await?);
            }
            // Also vary the SQL replay window itself, not just Main page sizes.
            // Each candidate remains inside its owner transaction and rolls back.
            use sea_orm::TransactionTrait;
            use crate::studio::storage::history::conversation::timeline;
            let db=Database::connect(format!("sqlite://{}?mode=rw",path.display())).await?;
            let database=history.conversation_database_id().await?.context("original database")?;
            for size in [1,2,17] {
                let tx=db.begin().await?;
                timeline::rebuild_batched(&tx,&database,size).await?;
                let rows=timeline::page_rows(&tx,&ChatScope::Main,None,100,4,100).await?;
                let after=rows.into_iter().rev().map(|(_,entry)|entry).collect::<Vec<_>>();
                assert_eq!(logical_timeline(before.clone()),logical_timeline(after.clone()));
                let ChatEntry::Item(group)=after.iter().find(|entry|matches!(entry,ChatEntry::Item(item) if item.kind==TimelineItemKind::WorkGroup))
                    .context("G at SQL replay cut")? else {unreachable!()};
                let members=timeline::page_rows(&tx,&ChatScope::GroupMembers {reference:group.members.clone().context("SQL replay G ref")?},None,100,4,100)
                    .await?.into_iter().rev().map(|(_,entry)|entry).collect::<Vec<_>>();
                assert_eq!(members_before,members);
                tx.rollback().await?;
            }
            db.close().await?;
            env.runtime.thread_observations.observation_slot(&thread.id).retire(&source);
            return Ok::<_,anyhow::Error>(());
        }
        let payload = OpaquePayload::new("application/json", 1, "{\"answer\":\"B\"}")?;
        let delivery = ToolDelivery {
            target: Default::default(),
            call_id: "call-b".into(),
            tool_id: "arbitrary".into(),
            output: pl_core::tool::ToolOutput::new(payload.clone(), vec![]),
            delivered_context: vec![ContextContent::Text {
                text: "B result".into(),
            }],
            outcome: ToolOutcome::Succeeded,
        };
        let inbox = InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                id: "result-b".into(),
                source_id: task.id.clone(),
                kind: AgentMessageKind::Report,
                payload,
                context: vec![],
            },
        };
        task.status = TaskStatus::Succeeded;
        task.revision = 2;
        state.tasks.insert(task.id.clone(), task.clone());
        state.deliveries = vec![delivery.clone()].into();
        state.inbox = vec![inbox.clone()].into();
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 4,
            committed_at: 13,
            tasks: vec![task].into(),
            deliveries: vec![delivery].into(),
            inbox: vec![inbox].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        let b_seq = session.head_seq();
        publish(&source, &session, &prepared)?;
        let one = ReadDemand {
            max_items: 1,
            ..demand()
        };
        let mut feed = env
            .runtime
            .open_conversation_feed(&thread.id, ChatScope::Main, one)
            .await?;
        let set = chat(&mut feed).await?;
        let b = completed_items(&set)
            .find(|atom| matches!(atom.source, ChatSourceId::BackgroundResult { .. }))
            .context("independent B result in Set")?;
        assert_eq!(
            b.source,
            ChatSourceId::BackgroundResult {
                message_id: "result-b".into()
            }
        );
        let b_order=b.position.context("B display order")?;
        assert!(b_seq>0);
        assert_eq!(b.delivery, ChatDeliveryKind::Independent);
        assert_ne!(
            b.id, ack.id,
            "independent result resurrected transferred foreground member"
        );
        assert_eq!(
            set.current.as_ref().context("mid Set current")?.atoms.len(),
            1
        );
        assert_eq!(set.entries.len(), 1);
        assert!(set.current.as_ref().context("source cut")?.sources.iter()
            .any(|state|state.source==b.source && matches!(state.lifecycle,ChatSourceLifecycle::Ended{..})));
        assert!(
            set.current
                .as_ref()
                .context("current-only source")?
                .sources
                .iter()
                .any(|source| source.source
                    == (ChatSourceId::ForegroundTurn {
                        turn_id: "atomic-turn".into()
                    })
                    && source.lifecycle == ChatSourceLifecycle::Active)
        );
        let mut before = set.before.clone();
        let mut older_seqs = Vec::new();
        while let Some(cursor) = before {
            let page = feed.reader().load_older(&cursor, one).await?;
            assert!(page.current.is_none());
            assert!(page.entries.len() <= 1);
            assert!(
                page.entries
                    .iter()
                    .all(|entry| matches!(entry, ChatEntry::Item(_)))
            );
            older_seqs.extend(page.entries.iter().filter_map(|entry| {
                if let ChatEntry::Item(item)=entry {item.position} else {None}
            }));
            before = page.before;
        }
        assert_eq!(older_seqs, vec![1, 0]);
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 5,
            committed_at: 14,
            model_members: vec![finish("unfinished-t", false, "T")?].into(),
            ..Default::default()
        };
        let (_, mut prepared) = projection.prepare(&thread, &effect, &state, false).await?;
        projection.publish_prepared(&session, &mut prepared).await?;
        publish(&source, &session, &prepared)?;
        let append = chat(&mut feed).await?;
        let t = completed_items(&append).next().context("T completion")?;
        assert!(t.position.context("T item_order")? > b_order);
        assert_eq!(
            t.source,
            ChatSourceId::ForegroundTurn {
                turn_id: "atomic-turn".into()
            }
        );
        let mut reopened=env.runtime.open_conversation_feed(&thread.id,ChatScope::Main,one).await?;
        let latest=chat(&mut reopened).await?;
        assert_eq!(completed_items(&latest).next().context("latest T")?.id,t.id);
        let older=reopened.reader().load_older(latest.before.as_deref().context("older B cursor")?,one).await?;
        assert_eq!(completed_items(&older).next().context("preceding B")?.source,b.source);
        feed.close().await?;feed.reader().close().await?;
        reopened.close().await?;reopened.reader().close().await?;
        env.runtime.thread_observations.observation_slot(&thread.id).retire(&source);
        Ok::<_,anyhow::Error>(())
    }.await;
    env.finish(result).await
}

#[tokio::test]
async fn real_empty_part_closes_work_but_whitespace_remains_a_message() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result=async {
        let mut harness=Harness::new(&env).await?;
        let start_work=harness.effect(vec![start("work",true)],vec![]).await?;harness.save(&start_work).await?;
        let finish_work=harness.effect(vec![],vec![finish("work",true,"work")?]).await?;
        assert!(finish_work.timeline.is_empty(),"running=0 sealed admission");
        harness.save(&finish_work).await?;
        let empty=harness.effect(vec![start("empty",false)],vec![finish("empty",false,"")?]).await?;
        assert_eq!(empty.timeline.len(),1);
        assert_eq!(empty.timeline[0].kind,TimelineItemKind::WorkGroup);
        assert!(empty.current.projection().items.is_empty());
        let empty_atom:ChatAtom=serde_json::from_slice(&empty.completions[0].header.metadata)?;
        assert_eq!(empty_atom.content_present,Some(false));
        assert!(matches!(empty_atom.lifecycle,ChatAtomLifecycle::Terminal{..}));
        harness.save(&empty).await?;
        let whitespace=harness.effect(vec![start("space",false)],vec![finish("space",false," \n\t")?]).await?;
        let space:ChatAtom=serde_json::from_slice(&whitespace.completions[0].header.metadata)?;
        assert_eq!(space.content_present,Some(true));
        assert_eq!(whitespace.timeline.len(),1);
        assert_eq!(whitespace.timeline[0].kind,TimelineItemKind::Text);
        harness.save(&whitespace).await?;
        let mut feed=env.runtime.open_conversation_feed(&harness.thread.id,ChatScope::Main,demand()).await?;
        let set=chat(&mut feed).await?;
        assert_eq!(set.entries.len(),2);
        assert!(set.entries.iter().all(|entry|matches!(entry,ChatEntry::Item(item) if item.content_item_id!=empty_atom.completion_item_id)));
        feed.close().await?;feed.reader().close().await?;
        env.runtime.thread_observations.observation_slot(&harness.thread.id).retire(&harness.source);
        Ok::<_,anyhow::Error>(())
    }.await;
    env.finish(result).await
}
