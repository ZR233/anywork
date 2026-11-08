//! Real SQLite business references: same-cut heads, immutable documents and local invalidation.
use super::*;
use conversation::current::{CurrentContentWrite, PreparedCurrent};
use pl_core::{
    context::OpaquePayload,
    thread::{
        ThreadCheckpoint, ThreadEffectBatch, ThreadSnapshot,
        extensions::ExtensionRecord,
        interactions::{InteractionRecord, InteractionRequest, InteractionState},
    },
};
use pl_protocol::{ContentOwner, ContentTarget, ThreadBusinessRefs, UserQuestion};
use std::collections::BTreeSet;

const THREAD: &str = "cold-business-refs";

#[tokio::test]
async fn cold_state_and_business_refs_keep_one_snapshot_across_a_real_writer_commit() -> Result<()>
{
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    let writer = HistoryStore::open(&path, THREAD).await?;
    let old_state = state_with_plan("# 读取切面的计划")?;
    let old_refs = save(&writer, old_state.clone(), 1).await?;
    let cold = HistoryStore::open(&path, THREAD).await?;
    let (entered, release) = cold.arm_state_read_gate().await;
    let reading = {
        let cold = cold.clone();
        tokio::spawn(async move { cold.read_state_with_business_refs().await })
    };
    tokio::time::timeout(Duration::from_secs(10), entered).await??;
    let mut next_state = old_state.clone();
    replace_plan(&mut next_state, "# 并发提交的新计划")?;
    next_state
        .interactions
        .remove(&pl_core::tool::opaque::tool_interaction_id("first"));
    next_state.interaction_collection_revision += 1;
    let next_refs = save(&writer, next_state.clone(), 2).await?;
    release
        .send(())
        .map_err(|_| anyhow::anyhow!("state read ended before release"))?;
    let (state, refs) = tokio::time::timeout(Duration::from_secs(10), reading)
        .await???
        .context("captured State")?;
    assert_eq!(state.commit_sequence, 1);
    assert_eq!(state.interactions, old_state.interactions);
    assert_eq!(state.extensions, old_state.extensions);
    assert_eq!(refs, old_refs);
    let (state, refs) = cold
        .read_state_with_business_refs()
        .await?
        .context("new State")?;
    assert_eq!(state.commit_sequence, 2);
    assert_eq!(state.interactions, next_state.interactions);
    assert_eq!(state.extensions, next_state.extensions);
    assert_eq!(refs, next_refs);
    assert_ne!(refs.plan, old_refs.plan);
    assert_ne!(refs.interactions, old_refs.interactions);
    let old_revision = old_refs
        .interactions
        .as_ref()
        .context("old interactions")?
        .revision;
    let new_revision = refs
        .interactions
        .as_ref()
        .context("new interactions")?
        .revision;
    assert_eq!(old_revision, old_state.interaction_collection_revision);
    assert_eq!(new_revision, next_state.interaction_collection_revision);
    eprintln!(
        "cold business refs: old_state_seq=1 old_revision={old_revision} new_state_seq=2 new_revision={new_revision}"
    );
    assert!(
        cold.state.writer.get().is_none(),
        "cold State must not initialize a writer"
    );
    cold.close_for_deletion().await?;
    writer.close_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn cold_state_never_restores_context_but_execution_recovery_still_checks_it() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    let writer = HistoryStore::open(&path, THREAD).await?;
    let expected = save(&writer, state_with_plan("# 独立业务状态")?, 1).await?;
    writer
        .writer()
        .await?
        .db
        .execute_unprepared(
            "INSERT INTO current_context(ordinal,record_id,payload,payload_hash)
         VALUES(0,'poison','not a context record','invalid hash');
         UPDATE session_checkpoint SET context_count=1 WHERE id=1;",
        )
        .await?;
    let cold = HistoryStore::open(&path, THREAD).await?;
    let (state, refs) = cold
        .read_state_with_business_refs()
        .await?
        .context("cold State")?;
    assert!(state.context.records.is_empty());
    assert_eq!(refs, expected);
    let error = writer
        .checkpoint()
        .await
        .expect_err("execution recovery must inspect context");
    assert!(format!("{error:#}").contains("current context ordering or hash mismatch"));
    let reader = cold.reader().await?.context("read-only pool")?;
    assert!(
        reader
            .db
            .execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
            .await
            .is_err(),
        "State must use a strictly read-only connection"
    );
    assert!(cold.state.writer.get().is_none());
    cold.close_for_deletion().await?;
    writer.close_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn cold_state_preserves_envelope_and_plan_validation_and_reports_absence() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let absent_path = dir.path().join("absent.sqlite");
    let absent = HistoryStore::open(&absent_path, THREAD).await?;
    assert!(absent.read_state_with_business_refs().await?.is_none());
    assert!(!absent_path.exists());
    for damage in [
        "hash",
        "schema",
        "thread",
        "revision",
        "context_revision",
        "fence",
        "manifest",
        "unsealed",
        "no_checkpoint",
    ] {
        let case = tempfile::tempdir()?;
        let path = case.path().join("history.sqlite");
        let writer = HistoryStore::open(&path, THREAD).await?;
        save(&writer, state_with_plan("# 校验原件")?, 1).await?;
        let db = &writer.writer().await?.db;
        match damage {
            "hash" => {
                db.execute_unprepared("UPDATE session_checkpoint SET payload_hash='bad'")
                    .await?;
            }
            "revision" => {
                db.execute_unprepared("UPDATE session_checkpoint SET revision=2")
                    .await?;
            }
            "context_revision" => {
                db.execute_unprepared("UPDATE session_checkpoint SET context_revision=2")
                    .await?;
            }
            "manifest" => {
                db.execute_unprepared(
                    "DELETE FROM conversation_content_chunks; DELETE FROM conversation_contents",
                )
                .await?;
            }
            "unsealed" => {
                db.execute_unprepared(
                "UPDATE conversation_contents SET payload=CAST(json_set(CAST(payload AS TEXT),'$.sealed',json('false')) AS BLOB)"
            ).await?;
            }
            "no_checkpoint" => {
                db.execute_unprepared("DELETE FROM session_checkpoint")
                    .await?;
            }
            _ => {
                let row = db
                    .query_one_raw(statement(
                        "SELECT payload FROM session_checkpoint WHERE id=1",
                        vec![],
                    ))
                    .await?
                    .context("checkpoint")?;
                let mut payload: serde_json::Value =
                    serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
                match damage {
                    "schema" => payload["schemaVersion"] = 999.into(),
                    "thread" => payload["threadId"] = "another-thread".into(),
                    "fence" => payload["historyFence"] = 2.into(),
                    _ => unreachable!(),
                }
                let payload = serde_json::to_string(&payload)?;
                let hash = pl_core::context::content_hash(payload.as_bytes());
                db.execute_raw(statement(
                    "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
                    vec![payload.into(), hash.into()],
                ))
                .await?;
            }
        }
        let cold = HistoryStore::open(&path, THREAD).await?;
        let result = cold.read_state_with_business_refs().await;
        if damage == "no_checkpoint" {
            assert!(result?.is_none());
        } else {
            assert!(result.is_err(), "{damage}");
        }
        assert!(cold.state.writer.get().is_none());
        cold.close_for_deletion().await?;
        writer.close_for_deletion().await?;
    }
    Ok(())
}

fn state_with_plan(markdown: &str) -> Result<ThreadSnapshot> {
    let mut machine = crate::plan_tool::state::AgentSessionPlanMachine::new(Default::default())?;
    machine.submit(crate::plan_tool::state::AgentSessionPlanSubmitCommand {
        expected_revision: 0,
        plan: markdown.into(),
        interaction_id: "confirmation".into(),
        operation_id: "submit".into(),
        argument_hash: "hash".into(),
        submitted_at: 1,
    });
    let plan = machine.into_state();
    ensure!(
        plan.document.is_some(),
        "fixture did not submit a real Plan"
    );
    let mut state = ThreadSnapshot::default();
    state.extensions.insert(
        crate::plan_tool::PLAN_EXTENSION.into(),
        ExtensionRecord {
            revision: 1,
            payload: crate::plan_tool::encode_plan_state(&plan)?,
        },
    );
    for id in ["first", "second"] {
        let id = pl_core::tool::opaque::tool_interaction_id(id);
        state.interactions.insert(
            id.clone(),
            InteractionRecord {
                created_at: 1,
                updated_at: 1,
                continuation_id: None,
                revision: 1,
                state: InteractionState::Pending,
                extension_mutations: vec![],
                request: InteractionRequest {
                    id: id.clone(),
                    turn_id: "turn".into(),
                    payload: OpaquePayload::new(
                        "pl.tool.user-input",
                        1,
                        serde_json::to_string(&vec![UserQuestion {
                            id,
                            header: "问题".into(),
                            question: "继续吗？".into(),
                            is_other: true,
                            is_secret: false,
                            options: None,
                        }])?,
                    )?,
                },
            },
        );
        state.interaction_collection_revision += 1;
    }
    Ok(state)
}

fn replace_plan(state: &mut ThreadSnapshot, markdown: &str) -> Result<()> {
    use crate::plan_tool::state::*;
    let record = state
        .extensions
        .get_mut(crate::plan_tool::PLAN_EXTENSION)
        .context("Plan")?;
    let plan = crate::plan_tool::decode_plan_state(&record.payload)?;
    let mut machine = AgentSessionPlanMachine::new(plan)?;
    let pending = machine
        .state()
        .pending_interaction_id
        .clone()
        .context("pending confirmation")?;
    machine.resolve(AgentSessionPlanResolveCommand {
        expected_revision: machine.state().revision,
        interaction_id: pending,
        operation_id: "revise".into(),
        argument_hash: "revise-hash".into(),
        decision: AgentSessionPlanConfirmationDecision::RequestRevision {
            feedback: "修改计划".into(),
        },
        resolved_at: 2,
    });
    machine.submit(AgentSessionPlanSubmitCommand {
        expected_revision: machine.state().revision,
        plan: markdown.into(),
        interaction_id: "next-confirmation".into(),
        operation_id: "resubmit".into(),
        argument_hash: "resubmit-hash".into(),
        submitted_at: 3,
    });
    let plan = machine.into_state();
    ensure!(
        plan.document
            .as_ref()
            .is_some_and(|document| document.markdown == markdown),
        "Plan fixture failed to resubmit"
    );
    record.revision += 1;
    record.payload = crate::plan_tool::encode_plan_state(&plan)?;
    Ok(())
}

/// The actual existing completion/checkpoint transaction, including independent Plan material.
async fn save(
    store: &HistoryStore,
    mut state: ThreadSnapshot,
    seq: u64,
) -> Result<ThreadBusinessRefs> {
    store.prepare_write().await?;
    state.commit_sequence = seq;
    let database = store
        .conversation_database_id()
        .await?
        .context("database")?;
    let current =
        crate::studio::thread_projection::CurrentState::cold(database, THREAD.into(), seq, &state)?;
    let refs = current.business_refs();
    let contents = current.contents().values().filter(|content| {
        conversation::content::current_owner(&content.descriptor.key.owner).ok().flatten()
            .is_some_and(|owner| matches!(owner, ContentOwner::Current { domain, .. } if domain == "plan"))
    }).map(|content| CurrentContentWrite { content: content.content(), sealed: true }).collect::<Vec<_>>();
    let prepared = PreparedCurrent::new(current.frozen_projection().clone(), contents.into());
    let checkpoint = ThreadCheckpoint::capture(THREAD.into(), seq, state)?;
    let effect = ThreadEffectBatch {
        thread_id: THREAD.into(),
        sequence: seq,
        committed_at: seq as i64,
        ..Default::default()
    };
    let accounting = crate::studio::thread_projection::PreparedAccounting::prepare(&effect)?;
    store
        .commit_checkpoint_effects(&[CheckpointEffect {
            checkpoint: &checkpoint,
            effect: &effect,
            history: EffectCommit {
                items: &[],
                completions: &[],
                current: &prepared,
                rolled_back_turns: &BTreeSet::new(),
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            },
            accounting: AccountingCommit {
                facts: &accounting,
                material_changed: false,
            },
        }])
        .await?;
    Ok(refs)
}

fn content_request(reference: &pl_protocol::ContentRef) -> Result<ContentReadRequest> {
    let ContentTarget::Body { owner, key } = &reference.target else {
        anyhow::bail!("body ref required");
    };
    Ok(ContentReadRequest {
        epoch: pl_core::chat::TimelineEpoch::new("business")?,
        reference: pl_core::chat::ContentRef::Body(pl_core::chat::ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(owner)?,
            key: key.clone(),
        }),
        offset: 0,
        max_bytes: 4096,
        generation: None,
    })
}

#[tokio::test]
async fn cold_reopen_keeps_plan_document_and_pending_interaction_refs_without_execution()
-> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    let store = HistoryStore::open(&path, THREAD).await?;
    let hot = save(&store, state_with_plan("# 完整计划\n\n- 保留原文")?, 1).await?;
    store.close_for_deletion().await?;
    let cold = HistoryStore::open(&path, THREAD).await?;
    let refs = cold.read_business_refs().await?.context("business refs")?;
    assert_eq!(refs, hot);
    let state = cold.cold_current_state().await?.context("cold state")?;
    assert!(!state.projection().execution_present);
    assert!(state.projection().atoms.is_empty());
    let document = refs.plan.as_ref().unwrap().document.as_ref().unwrap();
    let window = ChatHistory::read_content(&cold, &content_request(document)?).await?;
    assert_eq!(
        window.bytes.as_bytes(),
        "# 完整计划\n\n- 保留原文".as_bytes()
    );
    assert!(window.sealed);
    let reference = refs.interactions.as_ref().context("interactions")?;
    let page = cold
        .page_current(
            reference,
            None,
            pl_protocol::ReadDemand {
                max_items: 1,
                max_bytes: 16384,
            },
            &|token| Ok(token),
        )
        .await?;
    assert_eq!(page.entries.len(), 1);
    let second = cold
        .page_current(
            reference,
            page.continuation.as_deref(),
            pl_protocol::ReadDemand {
                max_items: 1,
                max_bytes: 16384,
            },
            &|token| Ok(token),
        )
        .await?;
    assert_eq!(second.entries.len(), 1);
    assert_ne!(page.entries[0].id, second.entries[0].id);
    let mut wrong = reference.clone();
    wrong.database_id = "other-db".into();
    assert!(
        cold.page_current(
            &wrong,
            None,
            pl_protocol::ReadDemand {
                max_items: 1,
                max_bytes: 16384
            },
            &|token| Ok(token)
        )
        .await
        .is_err()
    );
    wrong = reference.clone();
    wrong.collection = "members".into();
    assert!(
        cold.page_current(
            &wrong,
            None,
            pl_protocol::ReadDemand {
                max_items: 1,
                max_bytes: 16384
            },
            &|token| Ok(token)
        )
        .await
        .is_err()
    );
    wrong = reference.clone();
    wrong.revision = wrong.revision.checked_add(1).unwrap();
    assert!(
        cold.page_current(
            &wrong,
            None,
            pl_protocol::ReadDemand {
                max_items: 1,
                max_bytes: 16384
            },
            &|token| Ok(token)
        )
        .await
        .is_err()
    );
    cold.close_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn failed_business_transaction_preserves_previous_refs_and_retry_uses_same_document()
-> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
    let old_state = state_with_plan("# 旧计划")?;
    let old = save(&store, old_state.clone(), 1).await?;
    let mut next = old_state;
    replace_plan(&mut next, "# 新计划")?;
    let db = &store.writer().await?.db;
    db.execute_unprepared(
        "CREATE TRIGGER fail_business BEFORE UPDATE ON history_meta
        WHEN NEW.applied_write_seq=2 BEGIN SELECT RAISE(ABORT,'business commit failure'); END;",
    )
    .await?;
    assert!(save(&store, next.clone(), 2).await.is_err());
    assert_eq!(store.read_business_refs().await?.unwrap(), old);
    db.execute_unprepared("DROP TRIGGER fail_business").await?;
    let new = save(&store, next, 2).await?;
    assert_ne!(new.plan, old.plan);
    assert_eq!(
        new.interactions, old.interactions,
        "Plan must not invalidate interactions"
    );
    assert_eq!(store.read_business_refs().await?.unwrap(), new);
    let old_window = ChatHistory::read_content(
        &store,
        &content_request(old.plan.as_ref().unwrap().document.as_ref().unwrap())?,
    )
    .await?;
    assert_eq!(old_window.bytes.as_bytes(), "# 旧计划".as_bytes());
    store.close_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn a_captured_cold_snapshot_never_pairs_old_plan_with_new_refs() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
    let first_state = state_with_plan("# 第一个切面")?;
    let first = save(&store, first_state.clone(), 1).await?;
    let reader = store.reader().await?.context("reader")?;
    let tx = reader.db.begin().await?;
    let captured = conversation::completed::cold(&tx).await?;
    let mut next = first_state;
    replace_plan(&mut next, "# 第二个切面")?;
    let new = save(&store, next, 2).await?;
    assert_eq!(captured.business_refs(), first);
    let same_snapshot = conversation::completed::cold(&tx).await?;
    assert_eq!(same_snapshot.business_refs(), first);
    tx.commit().await?;
    assert_eq!(store.read_business_refs().await?.unwrap(), new);
    store.close_for_deletion().await?;
    Ok(())
}

#[tokio::test]
async fn missing_plan_manifest_or_chunk_is_an_error_and_never_a_checkpoint_text_fallback()
-> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
    let refs = save(&store, state_with_plan("# 不能从 checkpoint 伪造正文")?, 1).await?;
    let document = refs.plan.unwrap().document.unwrap();
    let ContentTarget::Body {
        owner: ContentOwner::Current { .. },
        ..
    } = &document.target
    else {
        anyhow::bail!("versioned current Plan document expected");
    };
    let request = content_request(&document)?;
    let db = &store.writer().await?.db;
    db.execute_unprepared("DELETE FROM conversation_content_chunks")
        .await?;
    assert!(ChatHistory::read_content(&store, &request).await.is_err());
    db.execute_unprepared("DELETE FROM conversation_contents")
        .await?;
    assert!(store.read_business_refs().await.is_err());
    store.close_for_deletion().await?;
    Ok(())
}
