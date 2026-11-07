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
        let source = Arc::new(
            super::super::super::thread_observation::ThreadLiveFeed::new(
                None,
                progress,
                Default::default(),
            ),
        );
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
                crate::studio::storage::history::TimelineReadCut {
                    ceiling: i64::MAX as u64,
                    effect: 4,
                    active_heads: &[],
                },
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

#[tokio::test]
async fn streamed_reasoning_summary_advances_current_group_without_a_new_effect() -> Result<()> {
    use pl_core::model::{ActiveModelProgress, ModelProgress, ObservedPart};
    let env = support::Environment::new(vec![], vec![]).await?;
    let mut h = Harness::new(&env).await?;
    let mut member = start("summary-stream", true);
    let ObservedPartIdentity::Provider(identity) = &mut member.identity else {
        unreachable!()
    };
    identity.part = ObservedPartKind::SummaryText;
    h.effect(vec![member.clone()], vec![]).await?;
    let attempt = serde_json::from_value(serde_json::json!({
        "turnId": "atomic-turn", "attemptId": "atomic-attempt",
        "retryOf": null, "inputRevision": 0, "status": {"kind": "running"}
    }))?;
    let mut state = CoreSnapshot {
        commit_sequence: 1,
        turns: vec![TurnRecord {
            turn_id: "atomic-turn".into(),
            input_id: None,
            state: CoreTurnState::Running,
            model_steps: 1,
            elapsed_ms: None,
        }]
        .into(),
        attempts: vec![attempt].into(),
        ..Default::default()
    };
    let mut part = ObservedPart::new(member.identity).appended("旧摘要");
    let mut group_id = None;
    for (suffix, expected) in [("", "旧摘要"), ("\r\n流式新摘要", "流式新摘要")] {
        if !suffix.is_empty() {
            part = part.appended(suffix);
        }
        state.model_progress = Some(ActiveModelProgress {
            attempt_id: "atomic-attempt".into(),
            progress: ModelProgress::new(0, vec![part.clone()]),
        });
        h.projection
            .stream(&h.session, &h.thread, &state, 1)
            .await?;
        let current = h.projection.current_state().context("streamed current")?;
        let group = &current.projection().items[0];
        if let Some(id) = &group_id {
            assert_eq!(&group.id, id);
        } else {
            group_id = Some(group.id.clone());
        }
        assert_eq!(
            group
                .summary
                .as_ref()
                .context("group summary")?
                .latest_thinking_summary
                .as_deref(),
            Some(expected)
        );
        assert_eq!(current.projection().source_effect_seq, 1);
        assert!(group.position.is_none());
    }
    let receipt = ModelMemberReceipt {
        item: CompletionPresentationItem {
            provider_item_id: "summary-stream".into(),
            output_index: None,
            kind: CompletionPresentationItemKind::Reasoning,
            parts: vec![CompletionPresentationPart {
                content_index: 0,
                provider_part_id: None,
                text: "旧摘要\r\n流式新摘要".into(),
                kind: CompletionPresentationPartKind::SummaryText,
            }],
        },
        state: ModelMemberState::Completed,
    };
    let completed = ModelCompletedMember {
        turn_id: "atomic-turn".into(),
        attempt_id: "atomic-attempt".into(),
        generation: 0,
        member_id: "summary-stream".into(),
        payload: OpaquePayload::new(
            "pl.model.completed-member",
            1,
            serde_json::to_string(&receipt)?,
        )?,
    };
    h.effect(vec![], vec![completed]).await?;
    let prepared = h
        .effect(
            vec![start("summary-boundary", false)],
            vec![finish("summary-boundary", false, "正文")?],
        )
        .await?;
    let group = prepared
        .timeline
        .iter()
        .find(|item| item.id == group_id.as_ref().unwrap().as_str())
        .context("same group at completion handoff")?;
    assert_eq!(
        group
            .summary
            .as_ref()
            .unwrap()
            .latest_thinking_summary
            .as_deref(),
        Some("流式新摘要")
    );
    assert!(group.position.is_some());
    Ok(())
}

#[tokio::test]
async fn progress_cannot_skip_a_work_group_handoff_at_the_same_completion_head() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let mut h = Harness::new(&env).await?;
    h.effect(vec![start("reasoning", true)], vec![]).await?;
    h.effect(vec![], vec![finish("reasoning", true, "work complete")?])
        .await?;
    let mut feed = env
        .runtime
        .open_conversation_feed(
            &h.thread.id,
            ChatScope::Main,
            ReadDemand {
                max_items: 4,
                max_bytes: CHAT_BATCH_MAX_BYTES,
            },
        )
        .await?;
    let initial = chat(&mut feed).await?;
    assert_eq!(initial.current.as_ref().unwrap().items.len(), 1);
    let completion_head = h.session.head_seq();
    h.effect(vec![start("answer", false)], vec![]).await?;
    h.effect(vec![], vec![]).await?;
    assert_eq!(h.session.head_seq(), completion_head);
    // This is the scheduling gap after an empty reliable poll and before reading progress.
    assert!(!feed.take_progress()?);
    let group = chat(&mut feed).await?;
    assert!(
        matches!(group.entries.as_slice(), [ChatEntry::Item(item)] if item.kind == TimelineItemKind::WorkGroup)
    );
    assert!(
        group
            .current
            .as_ref()
            .unwrap()
            .items
            .iter()
            .all(|item| item.kind != TimelineItemKind::WorkGroup)
    );
    feed.close().await?;
    env.finish(Ok(())).await
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
async fn opened_member_window_appends_later_members_and_reliable_source_end_across_save()
-> Result<()> {
    async fn member_cut(feed: &mut ConversationFeed, serial: u64) -> Result<Vec<ChatEntry>> {
        let mut entries = Vec::new();
        // Consume the original feed's bounded frames through the published
        // cut. Active head updates can share a cut with new member admissions.
        while feed.seen_serial < serial {
            let batch = chat(feed).await?;
            assert_eq!(batch.placement, ChatPlacement::Append);
            assert!(batch.before.is_none() && batch.current.is_none());
            entries.extend(batch.entries);
        }
        assert_eq!(feed.seen_serial, serial);
        Ok(entries)
    }

    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = Harness::new(&env).await?;
        let window = ReadDemand {
            max_items: 3,
            ..demand()
        };
        let started = harness
            .effect(
                (0..4)
                    .map(|index| start(&format!("work-{index}"), true))
                    .collect(),
                vec![],
            )
            .await?;
        harness.save(&started).await?;
        let reference = started.current.projection().items[0]
            .members
            .clone()
            .context("live group")?;
        let mut group = env
            .runtime
            .open_conversation_feed(
                &harness.thread.id,
                ChatScope::GroupMembers { reference },
                window,
            )
            .await?;
        let subscription = group.reader().subscription_id().to_owned();
        let initial = chat(&mut group).await?;
        let before = initial.before.context("older hidden member")?;
        assert_eq!(initial.placement, ChatPlacement::Set);
        assert!(initial.current.is_none());
        assert_eq!(initial.entries.len(), 3);
        let initial_ids = initial
            .entries
            .iter()
            .map(|entry| match entry {
                ChatEntry::Atom(atom) => Ok(atom.id.clone()),
                _ => bail!("member Set returned a non-atom"),
            })
            .collect::<Result<Vec<_>>>()?;

        let later = harness
            .effect(vec![start("work-4", true), start("work-5", true)], vec![])
            .await?;
        let serial = harness
            .source
            .current_conversation()
            .context("live cut")?
            .serial;
        let new = member_cut(&mut group, serial).await?;
        let new_ids = new
            .iter()
            .filter_map(|entry| match entry {
                ChatEntry::Atom(atom) => {
                    assert!(matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }));
                    (!initial_ids.contains(&atom.id)).then(|| atom.id.clone())
                }
                ChatEntry::Source(_) => None,
                ChatEntry::Item(_) => panic!("member admission returned a Main item"),
            })
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        assert_eq!(new_ids.len(), 2, "same window lost later member admission");
        harness.save(&later).await?;

        // A hidden older member also completes, but must not be pulled into
        // the opened window. Reverse completion does not change membership.
        let partial = harness
            .effect(
                vec![],
                vec![
                    finish("work-5", true, "five")?,
                    finish("work-3", true, "three")?,
                    finish("work-1", true, "one")?,
                    finish("work-0", true, "hidden")?,
                ],
            )
            .await?;
        harness.save(&partial).await?;
        let serial = harness
            .source
            .current_conversation()
            .context("live cut")?
            .serial;
        let completed = member_cut(&mut group, serial).await?;
        let completed_ids = completed
            .iter()
            .filter_map(|entry| match entry {
                ChatEntry::Atom(atom) => {
                    matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. })
                        .then(|| atom.id.clone())
                }
                ChatEntry::Source(_) => None,
                ChatEntry::Item(_) => panic!("member completion returned a Main item"),
            })
            .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(
            completed_ids,
            [
                initial_ids[0].clone(),
                initial_ids[2].clone(),
                new_ids[1].clone(),
            ]
            .into_iter()
            .collect()
        );

        // The original reliable effect ends both remaining loaded members and
        // their source. With max_items=3 this is one real mixed Atom/Source
        // batch, not an ordinary page and not a synthesized terminal state.
        harness.sequence += 1;
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: None,
            turn_id: "atomic-turn".into(),
            state: CoreTurnState::Finished(pl_core::thread::TurnOutcome::Completed),
            model_steps: 1,
        };
        let state = CoreSnapshot {
            turns: vec![turn.clone()].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: harness.thread.id.clone(),
            sequence: harness.sequence,
            committed_at: 100,
            turn: Some(turn),
            model_members: vec![
                finish("work-4", true, "four")?,
                finish("work-2", true, "two")?,
            ]
            .into(),
            ..Default::default()
        };
        let (_, mut end) = harness
            .projection
            .prepare(&harness.thread, &effect, &state, false)
            .await?;
        harness
            .projection
            .publish_prepared(&harness.session, &mut end)
            .await?;
        publish(&harness.source, &harness.session, &end)?;
        harness.save(&end).await?;
        let serial = harness
            .source
            .current_conversation()
            .context("live cut")?
            .serial;
        let terminal = member_cut(&mut group, serial).await?;
        assert_eq!(terminal.len(), 3);
        let mut terminal_ids = std::collections::BTreeSet::new();
        let mut source_ends = 0;
        for entry in terminal {
            match entry {
                ChatEntry::Atom(atom) => {
                    assert!(matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }));
                    let source = atom.source_state.context("same-cut source annotation")?;
                    assert!(matches!(
                        source.lifecycle,
                        ChatSourceLifecycle::Ended { .. }
                    ));
                    assert_eq!(
                        source.ended.context("source end cut")?.effect_seq,
                        effect.sequence
                    );
                    terminal_ids.insert(atom.id);
                }
                ChatEntry::Source(source) => {
                    assert!(matches!(
                        source.lifecycle,
                        ChatSourceLifecycle::Ended { .. }
                    ));
                    assert_eq!(
                        source.ended.context("reliable source end")?.effect_seq,
                        effect.sequence
                    );
                    source_ends += 1;
                }
                ChatEntry::Item(_) => bail!("GroupMembers delivered a Main item"),
            }
        }
        assert_eq!(
            terminal_ids,
            [initial_ids[1].clone(), new_ids[0].clone()]
                .into_iter()
                .collect()
        );
        assert_eq!(source_ends, 1);
        assert_eq!(group.reader().subscription_id(), subscription);
        let older = group.reader().load_older(&before, window).await?;
        assert!(older.before.is_none() && older.current.is_none());
        let [ChatEntry::Atom(hidden)] = older.entries.as_slice() else {
            bail!("old member continuation changed its original boundary");
        };
        assert!(
            matches!(hidden.lifecycle, ChatAtomLifecycle::Active { .. }),
            "new durable head leaked into the original older-page cut"
        );
        assert!(matches!(
            hidden
                .source_state
                .as_ref()
                .context("old source")?
                .lifecycle,
            ChatSourceLifecycle::Active
        ));
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
            Arc::new(super::super::super::thread_observation::ThreadLiveFeed::new(None, progress, Default::default()));
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
                vec![TimelineItemKind::WorkGroup,TimelineItemKind::WorkGroup,TimelineItemKind::Status]);
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
                .context("saved G")? else {unreachable!()};
            let members_before=read_all_timeline(&history,ChatScope::GroupMembers {reference:group.members.clone().context("G ref")?},1).await?;
            use sea_orm::{ConnectionTrait,Database,Statement,DatabaseBackend};
            let path=env.runtime.store.registered_session_paths(&thread.id)?.history_database();
            let db=Database::connect(format!("sqlite://{}?mode=rw",path.display())).await?;
            let source_key=serde_json::to_string(&source_end.source)?;
            let end=db.query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
                "SELECT ended_effect,ended_suborder FROM conversation_sources WHERE source_key=?",vec![source_key.into()])).await?.context("stored V end")?;
            assert_eq!(end.try_get::<i64>("","ended_effect")?,4);
            assert_eq!(end.try_get::<i64>("","ended_suborder")?,0);
            db.close().await?;
            for size in [1,2,17] {
                let after=read_all_timeline(&history,ChatScope::Main,size).await?;
                assert_eq!(logical_timeline(before.clone()),logical_timeline(after.clone()));
                let ChatEntry::Item(group)=after.iter().find(|entry|matches!(entry,ChatEntry::Item(item) if item.kind==TimelineItemKind::WorkGroup))
                    .context("saved G at page size")? else {unreachable!()};
                assert_eq!(members_before,read_all_timeline(&history,ChatScope::GroupMembers {reference:group.members.clone().context("rebuilt G ref")?},size).await?);
            }
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
        let b = set.entries.iter().filter_map(|entry| match entry {
            ChatEntry::Item(item) if item.position.is_some() => Some(item.as_ref()),
            _ => None,
        })
            .find(|atom| matches!(atom.source, ChatSourceId::BackgroundResult { .. }))
            .context("independent B result in Set")?;
        assert_eq!(b.kind, TimelineItemKind::WorkGroup);
        assert!(b.payload.is_none());
        assert_eq!(b.summary.as_ref().context("B summary")?.member_count, 1);
        assert!(b.members.is_some());
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
        let preceding = older.entries.iter().find_map(|entry| match entry {
            ChatEntry::Item(item) if item.position.is_some() => Some(item.as_ref()),
            _ => None,
        }).context("preceding B")?;
        assert_eq!(preceding.source,b.source);
        assert_eq!(preceding.kind,TimelineItemKind::WorkGroup);
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

fn a14_atom_metadata(atom: &ChatAtom) -> serde_json::Value {
    serde_json::json!({
        "id": atom.id, "kind": atom.kind, "source": atom.source,
        "sourceOrder": atom.source_order, "turnId": atom.turn_id,
        "attemptId": atom.attempt_id, "lifecycle": atom.lifecycle,
        "completionItemId": atom.completion_item_id, "completionSeq": atom.completion_seq,
        "contentPresent": atom.content_present, "sourceState": atom.source_state,
    })
}

struct A14MemberRead {
    reference: TimelineMembersRef,
    feed: ConversationFeed,
    atoms: Vec<ChatAtom>,
    source: Option<ChatSourceState>,
}

struct A14DurableRead {
    atom: ChatAtom,
    item_id: String,
    append_seq: u64,
}

#[derive(Default)]
struct A14Reads {
    main: Vec<TimelineItem>,
    current: Option<CurrentProjection>,
    members: Vec<A14MemberRead>,
    durable: Vec<A14DurableRead>,
    before: Option<TimelineMembersRef>,
    after: Option<TimelineMembersRef>,
    source: Option<ChatSourceId>,
    attempt: Option<String>,
    empty_start: Option<ChatAtom>,
    body: Option<ContentWindow>,
}

impl A14Reads {
    fn main_batch(&mut self, batch: ChatBatch) -> Result<()> {
        batch.validate_for(&ChatScope::Main)?;
        match batch.placement {
            ChatPlacement::Set => self.main.clear(),
            ChatPlacement::Append => {}
            ChatPlacement::Prepend => bail!("A14 unexpectedly paged Main"),
        }
        for entry in batch.entries {
            let ChatEntry::Item(item) = entry else {
                bail!("Main returned a member atom");
            };
            ensure!(
                self.main.iter().all(|old| old.id != item.id),
                "A14 duplicated a Main item"
            );
            self.main.push(*item);
        }
        if batch.current.is_some() {
            self.current = batch.current;
        }
        Ok(())
    }

    fn member_batch(&mut self, index: usize, batch: ChatBatch) -> Result<()> {
        let group = &mut self.members[index];
        batch.validate_for(&ChatScope::GroupMembers {
            reference: group.reference.clone(),
        })?;
        ensure!(
            batch.before.is_none(),
            "A14 single member unexpectedly paged"
        );
        if batch.placement == ChatPlacement::Set {
            group.atoms.clear();
        }
        for entry in batch.entries {
            match entry {
                ChatEntry::Atom(atom) => {
                    if let Some(old) = group.atoms.iter_mut().find(|old| old.id == atom.id) {
                        *old = *atom;
                    } else {
                        group.atoms.push(*atom);
                    }
                }
                ChatEntry::Source(source) => group.source = Some(source),
                ChatEntry::Item(_) => bail!("GroupMembers returned a Main item"),
            }
        }
        Ok(())
    }

    fn reasoning(&self, reference: Option<&TimelineMembersRef>) -> Option<&ChatAtom> {
        let group = self
            .members
            .iter()
            .find(|group| Some(&group.reference) == reference)?;
        let [atom] = group.atoms.as_slice() else {
            return None;
        };
        (atom.kind == ChatAtomKind::Reasoning
            && Some(&atom.source) == self.source.as_ref()
            && atom.attempt_id.is_some()
            && atom.source_order.is_some()
            && atom.completion_item_id.is_some()
            && atom.completion_seq.is_some()
            && matches!(
                atom.lifecycle,
                ChatAtomLifecycle::Terminal {
                    ended: Some(_),
                    outcome: ChatTerminalOutcome::Completed,
                    ..
                }
            ))
        .then_some(atom)
    }

    fn main_group(&self, reference: Option<&TimelineMembersRef>) -> bool {
        let Some(reference) = reference else {
            return false;
        };
        self.main.iter().any(|item| {
            item.members.as_ref() == Some(reference)
                && Some(&item.source) == self.source.as_ref()
                && item.position.is_some()
                && item.admission_closed
                && item
                    .summary
                    .as_ref()
                    .is_some_and(|summary| summary.member_count == 1 && summary.active_count == 0)
        }) && self.reasoning(Some(reference)).is_some()
    }

    fn empty_completion(&self) -> Option<&A14DurableRead> {
        self.durable.iter().find(|record| {
            let atom = &record.atom;
            atom.kind == ChatAtomKind::Text
                && atom.content_present == Some(false)
                && Some(&atom.source) == self.source.as_ref()
                && atom.attempt_id.as_ref() == self.attempt.as_ref()
                && atom.attempt_id.is_some()
                && atom.source_order.is_some()
                && self
                    .empty_start
                    .as_ref()
                    .is_none_or(|start| start.id == atom.id)
                && atom.completion_item_id.as_deref() == Some(record.item_id.as_str())
                && record.append_seq > 0
                && matches!(
                    atom.lifecycle,
                    ChatAtomLifecycle::Terminal {
                        ended: Some(_),
                        outcome: ChatTerminalOutcome::Completed,
                        ..
                    }
                )
        })
    }

    fn ready(&self, stage: usize) -> bool {
        let Some(current) = &self.current else {
            return false;
        };
        let before = self.reasoning(self.before.as_ref());
        let empty = self.empty_completion();
        let no_empty_main = empty.is_some_and(|record| {
            self.main
                .iter()
                .all(|item| item.content_item_id.as_deref() != Some(record.item_id.as_str()))
        });
        let expected = pl_provider_fixture::timeline_concept::EMPTY_TEXT_ANSWER.as_bytes();
        match stage {
            0 => {
                before.is_some()
                    && current.items.iter().any(|item| {
                        item.members.as_ref() == self.before.as_ref()
                            && !item.admission_closed
                            && item.summary.as_ref().is_some_and(|summary| {
                                summary.member_count == 1 && summary.active_count == 0
                            })
                    })
            }
            1 => {
                self.main_group(self.before.as_ref())
                    && self.empty_start.as_ref().is_some_and(|atom| {
                        Some(&atom.source) == self.source.as_ref()
                            && atom.attempt_id.as_ref() == self.attempt.as_ref()
                            && before.is_some_and(|reason| atom.source_order > reason.source_order)
                            && matches!(
                                atom.lifecycle,
                                ChatAtomLifecycle::Active {
                                    started: Some(_),
                                    ..
                                }
                            )
                    })
            }
            2 => {
                self.main_group(self.before.as_ref())
                    && no_empty_main
                    && empty.is_some_and(|record| {
                        let ChatAtomLifecycle::Terminal {
                            ended: Some(ended), ..
                        } = record.atom.lifecycle
                        else {
                            return false;
                        };
                        current.source_effect_seq >= ended.effect_seq
                            && before.is_some_and(|reason| {
                                record.atom.source_order > reason.source_order
                            })
                    })
            }
            3 => {
                self.main_group(self.before.as_ref())
                    && no_empty_main
                    && self.after != self.before
                    && self.reasoning(self.after.as_ref()).is_some_and(|atom| {
                        atom.attempt_id.as_ref() == self.attempt.as_ref()
                            && empty.is_some_and(|empty| {
                                atom.source_order > empty.atom.source_order
                                    && atom.completion_seq > Some(empty.append_seq)
                            })
                    })
                    && current.items.iter().any(|item| {
                        item.members.as_ref() == self.after.as_ref()
                            && !item.admission_closed
                            && item.summary.as_ref().is_some_and(|summary| {
                                summary.member_count == 1 && summary.active_count == 0
                            })
                    })
            }
            4 => {
                self.main_group(self.after.as_ref())
                    && no_empty_main
                    && current.items.iter().any(|item| {
                        item.atom_kind == Some(ChatAtomKind::Text)
                            && Some(&item.source) == self.source.as_ref()
                    })
                    && self
                        .body
                        .as_ref()
                        .is_some_and(|body| body.bytes == expected)
            }
            5 => {
                self.main_group(self.before.as_ref())
                    && self.main_group(self.after.as_ref())
                    && no_empty_main
                    && self.main.iter().any(|item| {
                        item.atom_kind == Some(ChatAtomKind::Text)
                            && Some(&item.source) == self.source.as_ref()
                            && item.position.is_some()
                            && item.admission_closed
                            && item.outcome == Some(ChatTerminalOutcome::Completed)
                    })
                    && self
                        .body
                        .as_ref()
                        .is_some_and(|body| body.sealed && body.bytes == expected)
            }
            _ => unreachable!(),
        }
    }

    async fn refresh(
        &mut self,
        env: &support::Environment,
        id: &str,
        stage: usize,
        reader: &ConversationReader,
    ) -> Result<()> {
        // A reference comes only from the original delivered current item. Each real group gets
        // one member feed, retained across all subsequent stages without reopening it.
        let group = self
            .current
            .as_ref()
            .and_then(|current| current.items.iter().find(|item| item.is_work_group()))
            .cloned();
        if let Some(group) = group {
            let reference = group.members.context("A14 group lacks its reference")?;
            if self.before.is_none() {
                self.source = Some(group.source.clone());
                self.before = Some(reference.clone());
            } else {
                ensure!(
                    Some(&group.source) == self.source.as_ref(),
                    "A14 changed source"
                );
                if Some(&reference) != self.before.as_ref() {
                    self.after = Some(reference.clone());
                }
            }
            if !self
                .members
                .iter()
                .any(|member| member.reference == reference)
            {
                ensure!(
                    self.members.len() < 2,
                    "A14 admitted an unexpected third work group"
                );
                let feed = env
                    .runtime
                    .open_conversation_feed(
                        id,
                        ChatScope::GroupMembers {
                            reference: reference.clone(),
                        },
                        demand(),
                    )
                    .await?;
                self.members.push(A14MemberRead {
                    reference,
                    feed,
                    atoms: Vec::new(),
                    source: None,
                });
            }
        }
        if let Some(atom) = self.reasoning(self.before.as_ref()) {
            self.attempt = atom.attempt_id.clone();
        }
        if stage == 1 {
            self.empty_start = self
                .current
                .as_ref()
                .and_then(|current| {
                    current.atoms.iter().find(|atom| {
                        atom.kind == ChatAtomKind::Text
                            && Some(&atom.source) == self.source.as_ref()
                            && atom.attempt_id.as_ref() == self.attempt.as_ref()
                            && atom.attempt_id.is_some()
                            && matches!(
                                atom.lifecycle,
                                ChatAtomLifecycle::Active {
                                    started: Some(_),
                                    ..
                                }
                            )
                    })
                })
                .cloned();
        }
        self.durable.clear();
        if let Some(ChatSourceId::ForegroundTurn { turn_id }) = &self.source {
            let history = env.runtime.store.history(id).await?;
            for item in history.items_for_turn(turn_id).await? {
                if let Some(frozen) = history.read_chat_item(&item.id).await? {
                    let atom: ChatAtom = serde_json::from_slice(&frozen.header.metadata)?;
                    ensure!(
                        atom.completion_item_id.as_deref() == Some(frozen.header.item_id.as_str())
                            && atom.completion_seq.is_none()
                            && atom.payload.is_none(),
                        "A14 frozen metadata/header mismatch"
                    );
                    self.durable.push(A14DurableRead {
                        atom,
                        item_id: frozen.header.item_id.clone(),
                        append_seq: frozen.header.append_seq,
                    });
                }
            }
        }
        ensure!(
            self.durable
                .iter()
                .filter(|record| {
                    record.atom.kind == ChatAtomKind::Text
                        && record.atom.content_present == Some(false)
                        && Some(&record.atom.source) == self.source.as_ref()
                        && record.atom.attempt_id.as_ref() == self.attempt.as_ref()
                })
                .count()
                <= 1,
            "A14 has ambiguous empty completion identities"
        );
        if stage >= 4 {
            let text = self
                .current
                .as_ref()
                .and_then(|current| {
                    current.items.iter().find(|item| {
                        item.atom_kind == Some(ChatAtomKind::Text)
                            && Some(&item.source) == self.source.as_ref()
                    })
                })
                .or_else(|| {
                    self.main.iter().find(|item| {
                        item.atom_kind == Some(ChatAtomKind::Text)
                            && Some(&item.source) == self.source.as_ref()
                    })
                });
            if let Some(body) = text.and_then(|item| {
                item.contents
                    .iter()
                    .find(|content| content.role == ChatContentRole::Body)
            }) {
                self.body = Some(
                    reader
                        .read_content(
                            &body.reference,
                            ContentRange {
                                offset: 0,
                                max_bytes: pl_provider_fixture::timeline_concept::EMPTY_TEXT_ANSWER
                                    .len() as u32,
                            },
                        )
                        .await?,
                );
            }
        }
        Ok(())
    }

    fn snapshot(&self, stage: &str, result: &Result<()>, core: &CoreSnapshot) -> serde_json::Value {
        let item = |item: &TimelineItem| {
            serde_json::json!({"id":item.id,"kind":item.kind,"source":item.source,
            "position":item.position,"admissionClosed":item.admission_closed,"summary":item.summary,
            "contentItemId":item.content_item_id,"outcome":item.outcome})
        };
        serde_json::json!({
            "stage":stage,"admitted":result.is_ok(),"failure":result.as_ref().err().map(|error|format!("{error:#}")),
            "coreCommitSequence":core.commit_sequence,"coreDurableSequence":core.persistence.durable_sequence,
            "coreProgress":core.model_progress.as_ref().map(|active|serde_json::json!({"attemptId":active.attempt_id,
                "parts":active.progress.parts().iter().map(|part|serde_json::json!({"identity":part.identity(),"version":part.version(),"byteLength":part.content().len()})).collect::<Vec<_>>() })),
            "main":self.main.iter().map(item).collect::<Vec<_>>(),
            "current":self.current.as_ref().map(|current|serde_json::json!({"sourceEffectSeq":current.source_effect_seq,"sources":current.sources,
                "items":current.items.iter().map(item).collect::<Vec<_>>(),"atoms":current.atoms.iter().map(a14_atom_metadata).collect::<Vec<_>>()})),
            "members":self.members.iter().map(|group|serde_json::json!({"reference":group.reference,"subscriptionId":group.feed.reader().subscription_id(),
                "atoms":group.atoms.iter().map(a14_atom_metadata).collect::<Vec<_>>(),"source":group.source})).collect::<Vec<_>>(),
            "durable":self.durable.iter().map(|record|serde_json::json!({"completionItemId":record.item_id,"completionSeq":record.append_seq,
                "frozenAtom":a14_atom_metadata(&record.atom)})).collect::<Vec<_>>(),
            "emptyStart":self.empty_start.as_ref().map(a14_atom_metadata),
            "body":self.body.as_ref().map(|body|serde_json::json!({"byteLength":body.bytes.len(),"availableThrough":body.available_through,
                "sealed":body.sealed,"matchesFixture":body.bytes==pl_provider_fixture::timeline_concept::EMPTY_TEXT_ANSWER.as_bytes()})),
        })
    }
}

#[tokio::test]
async fn fixture_empty_content_part_preserves_a14_start_and_reliable_handoff() -> Result<()> {
    const STAGES: [&str; 6] = [
        "a14-before-empty",
        "a14-empty-start",
        "a14-empty-terminal",
        "a14-after-empty",
        "a14-text-readable",
        "a14-before-turn-end",
    ];
    let mut step = pl_provider_fixture::timeline_concept::Control::default().script().into_iter()
        .find(|step| matches!(&step.request, RequestMatch::Prompt { text, .. } if text == pl_provider_fixture::timeline_concept::EMPTY_TEXT_PROMPT))
        .context("original A14 fixture step")?;
    let RequestMatch::Prompt {
        text: prompt,
        step: ordinal,
    } = &mut step.request
    else {
        bail!("A14 prompt shape changed");
    };
    *ordinal = 0;
    let prompt = prompt.clone();
    let Reply::SegmentedSse { segments, gates } = &step.reply else {
        bail!("A14 is not staged SSE");
    };
    ensure!(
        segments.len() == STAGES.len() + 1,
        "A14 fixture stages changed"
    );
    let gates = gates.clone();
    let env = support::Environment::new(vec![step], vec![]).await?;
    let mut reads = A14Reads::default();
    let mut result = async {
        let thread = env.start(ThreadWorkspaceMode::Local, &prompt).await?;
        let id = &thread.thread.id;
        let handle = env.runtime.threads.observed_thread(id).context("real Core owner")?;
        let mut owner = handle.subscribe();
        let mut feed = env.runtime.open_conversation_feed(id, ChatScope::Main, demand()).await?;
        let result = async {
            let mut failures = Vec::new();
            for (index, (reached, release)) in gates.iter().enumerate() {
                tokio::time::timeout(support::integration_test_deadline()?, reached.cancelled()).await?;
                reads.body = None;
                let admitted = tokio::time::timeout(Duration::from_secs(60), async {
                    loop {
                        reads.refresh(&env, id, index, feed.reader()).await?;
                        if reads.ready(index) { return Ok::<_, anyhow::Error>(()); }
                        // Owner progress wakes durable completion checks. Neither a wire gate nor
                        // a structurally empty current substitutes for the required completion.
                        enum Wake { Main(ConversationEvent), Member(usize, ConversationEvent), Owner }
                        let wake = {
                            let count = reads.members.len();
                            let (before, after) = reads.members.split_at_mut(count.min(1));
                            tokio::select! {
                                event = feed.recv() => Wake::Main(event?.context("A14 Main ended")?),
                                event = async { before[0].feed.recv().await }, if count >= 1 =>
                                    Wake::Member(0, event?.context("A14 before member feed ended")?),
                                event = async { after[0].feed.recv().await }, if count >= 2 =>
                                    Wake::Member(1, event?.context("A14 after member feed ended")?),
                                snapshot = owner.next() => { snapshot.context("A14 Core owner ended")?; Wake::Owner }
                            }
                        };
                        match wake {
                            Wake::Main(ConversationEvent::Chat { batch }) => reads.main_batch(*batch)?,
                            Wake::Member(member, ConversationEvent::Chat { batch }) => reads.member_batch(member, *batch)?,
                            _ => {}
                        }
                    }
                }).await.context("A14 stage lacks its required reliable facts").and_then(|result|result);
                // Print before any failure propagation and before releasing this exact gate.
                println!("A14_STAGE {}", reads.snapshot(STAGES[index], &admitted, &handle.snapshot()));
                for group in &reads.members {
                    for atom in &group.atoms { println!("A14_MEMBER {}", a14_atom_metadata(atom)); }
                }
                if let Err(error) = &admitted { failures.push(format!("{}: {error:#}", STAGES[index])); }
                release.cancel();
            }
            let turn = support::completed_prompt(&env.runtime, id, &prompt).await?;
            println!("A14_TURN {}", serde_json::json!({"id":turn.id,"threadId":turn.thread_id,"state":turn.state}));
            ensure!(reads.source == Some(ChatSourceId::ForegroundTurn { turn_id: turn.id.clone() }), "A14 terminal Turn changed identity");
            ensure!(matches!(turn.state, pl_protocol::TurnState::Completed(_)), "A14 Turn did not complete successfully");
            let positions = [&reads.before, &reads.after].into_iter().map(|reference| {
                reads.main.iter().find(|item| item.members.as_ref() == reference.as_ref()).and_then(|item| item.position)
            }).collect::<Option<Vec<_>>>().context("A14 work groups did not reach Main")?;
            ensure!(positions[0] < positions[1], "A14 before/after order changed");
            let text_position = reads.main.iter().find(|item| item.atom_kind == Some(ChatAtomKind::Text)
                && Some(&item.source) == reads.source.as_ref()).and_then(|item|item.position).context("A14 final Main position")?;
            ensure!(positions[1] < text_position, "A14 final text preceded its work group");
            ensure!(failures.is_empty(), "A14 admitted-stage failures: {failures:?}");
            Ok::<_, anyhow::Error>(())
        }.await;
        let closed = feed.close().await;
        let reader_closed = feed.reader().close().await;
        println!("A14_CLOSE main={} reader={}", closed.is_ok(), reader_closed.is_ok());
        result.and(closed).and(reader_closed)
    }.await;
    for (_, release) in &gates {
        release.cancel();
    }
    for mut group in reads.members {
        let closed = group.feed.close().await;
        let reader_closed = group.feed.reader().close().await;
        println!(
            "A14_CLOSE member={} feed={} reader={}",
            group.reference.item_id,
            closed.is_ok(),
            reader_closed.is_ok()
        );
        result = result.and(closed).and(reader_closed);
    }
    env.finish(result).await
}
