//! Ordinary reliable backlog preserves immutable completions through the original writer.
use super::*;
use crate::runtime_test_support as support;
use anyhow::{Context, Result, bail, ensure};
use futures::FutureExt as _;
use pl_core::{
    context::OpaquePayload,
    model::{
        DynModelSession, Model, ModelError, ModelFactory, ModelFailureKind, ModelMemberSender,
        ModelRequest, ModelSession, ModelStepOutput, ModelTextChannel, ObservedItemKind,
        ObservedPartIdentity, ObservedPartKind, PreparedModelCall, ProviderPartIdentity,
    },
    thread::{ModelStepLimit, ThreadHandle, TurnInput, TurnOutcome},
};
use pl_model::{
    completion::{
        CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
        CompletionPresentationPartKind,
    },
    runtime::{ModelMemberReceipt, ModelMemberState},
};
use pl_protocol::*;
use sea_orm::{ConnectionTrait, Database, DatabaseConnection, DbBackend, Statement};
use std::{
    panic::AssertUnwindSafe,
    sync::{Arc, Mutex},
};
use tokio::sync::{Semaphore, watch};
use tokio_util::sync::CancellationToken;

const WINDOW: usize = 128;
const PREFIX_MEMBERS: usize = 2 * WINDOW;
// Cross several ordinary credit windows without claiming to exercise the writer's capacity limit.
const SUFFIX_MEMBERS: usize = 2 * WINDOW;
const TEXT: &str = "T completed before R; 正文与附件所有权不能随普通积压中断";
const R: &str = "a34-r";
const T: &str = "a34-t";
const U: &str = "a34-u";

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Stage {
    Initial,
    FirstWindow,
    Cut,
    SuffixReady,
}

/// Only a model environment: it emits canonical starts/receipts through Core's
/// original one-slot member port. It has no projection, storage or maintenance logic.
struct Script {
    stage: watch::Sender<Stage>,
    next: Semaphore,
    diagnostic: Mutex<ProducerDiagnostic>,
}
#[derive(Debug, Default)]
struct ProducerDiagnostic {
    operation: String,
    acknowledged: u64,
    finished: Option<String>,
}
impl Script {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            stage: watch::channel(Stage::Initial).0,
            next: Semaphore::new(0),
            diagnostic: Mutex::new(ProducerDiagnostic::default()),
        })
    }
    async fn reached(&self, target: Stage) -> Result<()> {
        let mut stage = self.stage.subscribe();
        loop {
            if *stage.borrow_and_update() >= target {
                return Ok(());
            }
            if let Some(finished) = &self.diagnostic.lock().unwrap().finished {
                bail!("producer ended before {target:?}: {finished}");
            }
            stage.changed().await?;
        }
    }
    fn operation(&self, operation: String) {
        self.diagnostic.lock().unwrap().operation = operation;
    }
    fn acknowledged(&self) {
        self.diagnostic.lock().unwrap().acknowledged += 1;
    }
    fn finished(&self, result: String) {
        self.diagnostic.lock().unwrap().finished = Some(result);
        // A retained sender is not proof the producer can still reach its next
        // boundary. Wake reached() on the producer's actual exit, too.
        self.stage.send_modify(|_| {});
    }
    fn release(&self) {
        self.next.add_permits(1);
    }
    async fn boundary(&self, stage: Stage, cancel: &CancellationToken) -> Result<()> {
        self.operation(format!("boundary {stage:?}"));
        self.stage.send_replace(stage);
        tokio::select! {
            biased;
            () = cancel.cancelled() => bail!("A34 model cancelled at {stage:?}"),
            permit = self.next.acquire() => permit?.forget(),
        }
        Ok(())
    }
}

struct ScriptModel(Arc<Script>);
impl Model for ScriptModel {
    async fn open_session(&self) -> std::result::Result<DynModelSession, ModelError> {
        Ok(DynModelSession::new(ScriptSession(self.0.clone())))
    }
}
struct ScriptSession(Arc<Script>);
impl ModelSession for ScriptSession {
    async fn prepare(
        &mut self,
        request: ModelRequest,
    ) -> std::result::Result<PreparedModelCall, ModelError> {
        let script = self.0.clone();
        Ok(PreparedModelCall::new(async move {
            emit(&script, &request).await.map_err(|error| {
                script.finished(format!("model emitter: {error:#}"));
                ModelError {
                    kind: ModelFailureKind::InvalidResponse,
                    details: None,
                    usage: Box::default(),
                    source: Some(error.into_boxed_dyn_error()),
                }
            })?;
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                // T was independently completed through the member port already.
                // Do not synthesize a second final message at response completion.
                content: vec![],
                tool_calls: vec![],
                private_context: None,
                usage: Default::default(),
            })
        }))
    }
    async fn close(&mut self) -> std::result::Result<(), ModelError> {
        Ok(())
    }
}

fn identity(id: &str, reasoning: bool) -> ObservedPartIdentity {
    ObservedPartIdentity::Provider(ProviderPartIdentity {
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
    })
}
fn receipt(id: &str, reasoning: bool, text: &str) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        "pl.model.completed-member",
        1,
        serde_json::to_string(&ModelMemberReceipt {
            item: CompletionPresentationItem {
                provider_item_id: id.into(),
                output_index: None,
                kind: if reasoning {
                    CompletionPresentationItemKind::Reasoning
                } else {
                    CompletionPresentationItemKind::Text(
                        pl_protocol::trace::TraceTextChannel::Final,
                    )
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
        })?,
    )?)
}
async fn complete(
    script: &Script,
    members: &ModelMemberSender,
    id: &str,
    reasoning: bool,
    text: &str,
) -> Result<()> {
    script.operation(format!("terminal {id}"));
    members
        .submit(0, id.into(), receipt(id, reasoning, text)?)
        .await
        .with_context(|| format!("canonical terminal {id}"))?;
    script.acknowledged();
    Ok(())
}
async fn start(
    script: &Script,
    members: &ModelMemberSender,
    id: &str,
    reasoning: bool,
) -> Result<()> {
    script.operation(format!("start {id}"));
    members
        .start(0, identity(id, reasoning))
        .await
        .with_context(|| format!("canonical start {id}"))?;
    script.acknowledged();
    Ok(())
}
async fn emit(script: &Script, request: &ModelRequest) -> Result<()> {
    let members = request.members.as_ref().context("real Core member port")?;
    start(script, members, R, true).await?;
    for index in 0..PREFIX_MEMBERS {
        ensure!(!request.cancellation.is_cancelled(), "A34 model cancelled");
        let id = format!("a34-prefix-{index:04}");
        start(script, members, &id, true).await?;
        complete(script, members, &id, true, &format!("prefix body {index}")).await?;
        if index + 1 == WINDOW {
            script
                .boundary(Stage::FirstWindow, &request.cancellation)
                .await?;
        }
    }
    start(script, members, T, false).await?;
    complete(script, members, T, false, TEXT).await?;
    start(script, members, U, true).await?;
    script.boundary(Stage::Cut, &request.cancellation).await?;
    for index in 0..SUFFIX_MEMBERS {
        ensure!(!request.cancellation.is_cancelled(), "A34 model cancelled");
        let id = format!("a34-suffix-{index:04}");
        start(script, members, &id, true).await?;
        complete(script, members, &id, true, &format!("suffix body {index}")).await?;
    }
    complete(script, members, R, true, "R ended after T").await?;
    script
        .boundary(Stage::SuffixReady, &request.cancellation)
        .await?;
    complete(script, members, U, true, "U ended after backlog").await?;
    Ok(())
}

fn demand() -> ReadDemand {
    ReadDemand {
        max_items: 16,
        max_bytes: 128 * 1024,
    }
}
async fn chat(feed: &mut ConversationFeed, scope: &ChatScope) -> Result<ChatBatch> {
    loop {
        match feed.recv().await?.context("A34 feed ended")? {
            ConversationEvent::Chat { batch } => {
                batch.validate_for(scope)?;
                return Ok(*batch);
            }
            ConversationEvent::Activity { .. } => {}
        }
    }
}

async fn receive_while<T>(
    feed: &mut ConversationFeed,
    delivered: &mut Vec<CompletedEntry>,
    operation: impl std::future::Future<Output = Result<T>>,
) -> Result<T> {
    tokio::pin!(operation);
    loop {
        tokio::select! {
            result = &mut operation => return result,
            event = feed.recv() => {
                if let ConversationEvent::Chat { batch } = event?.context("A34 original feed ended")? {
                    batch.validate_for(&ChatScope::Main)?;
                    assert_eq!(batch.placement, ChatPlacement::Append);
                    assert!(batch.encoded_len()? <= demand().max_bytes as usize);
                    for entry in batch.entries {
                        if let Some(previous) = delivered.last() {
                            assert!(previous.completion_seq < entry.completion_seq);
                        }
                        delivered.push(entry);
                    }
                }
            }
        }
    }
}
fn sql(text: &str, values: Vec<sea_orm::Value>) -> Statement {
    Statement::from_sql_and_values(DbBackend::Sqlite, text, values)
}
async fn facts(db: &DatabaseConnection, through: u64) -> Result<Vec<(String, String, Vec<u8>)>> {
    db.query_all_raw(sql(
        "SELECT atom_id,phase,metadata FROM conversation_atom_facts WHERE effect_seq<=?
         ORDER BY effect_seq,suborder,fact_order,atom_id,phase",
        vec![i64::try_from(through)?.into()],
    ))
    .await?
    .into_iter()
    .map(|row| {
        Ok((
            row.try_get("", "atom_id")?,
            row.try_get("", "phase")?,
            row.try_get("", "metadata")?,
        ))
    })
    .collect()
}
#[derive(Debug, Clone, PartialEq, Eq)]
struct SavedCompletion {
    seq: u64,
    id: String,
    parent: Option<String>,
    payload: Vec<u8>,
    metadata: Vec<u8>,
    run: Option<CompletionRunPosition>,
}
async fn saved_items(db: &DatabaseConnection) -> Result<Vec<SavedCompletion>> {
    db.query_all_raw(sql("SELECT seq,item_id,parent_id,payload,metadata,display_run_start,display_run_ordinal FROM conversation_items ORDER BY seq", vec![]))
        .await?.into_iter().map(|row| {
            let start: Option<i64> = row.try_get("", "display_run_start")?;
            let ordinal: Option<i64> = row.try_get("", "display_run_ordinal")?;
            Ok(SavedCompletion {
                seq: u64::try_from(row.try_get::<i64>("", "seq")?)?,
                id: row.try_get("", "item_id")?, parent: row.try_get("", "parent_id")?,
                payload: row.try_get("", "payload")?, metadata: row.try_get("", "metadata")?,
                run: match (start, ordinal) {
                    (Some(start), Some(ordinal)) => Some(CompletionRunPosition { start_seq: u64::try_from(start)?, ordinal: u64::try_from(ordinal)? }),
                    (None, None) => None,
                    _ => bail!("half-written run position"),
                },
            })
        }).collect()
}
async fn saved_chunks(db: &DatabaseConnection) -> Result<Vec<(String, String, i64, Vec<u8>)>> {
    db.query_all_raw(sql("SELECT owner_key,content_key,byte_offset,data FROM conversation_content_chunks ORDER BY owner_key,content_key,byte_offset", vec![]))
        .await?.into_iter().map(|row| Ok((row.try_get("", "owner_key")?, row.try_get("", "content_key")?, row.try_get("", "byte_offset")?, row.try_get("", "data")?))).collect()
}

async fn check_text(reader: &ConversationReader, item: &CompletedEntry) -> Result<()> {
    let owner = &item.record_id;
    ensure!(!item.atom.contents.is_empty(), "T lost its body references");
    let body = &item.atom.contents[0];
    let bytes = reader
        .read_content(
            &body.reference,
            ContentRange {
                offset: 0,
                max_bytes: 4096,
            },
        )
        .await?;
    assert_eq!(bytes.bytes, TEXT.as_bytes());
    let ContentTarget::Body {
        owner: ContentOwner::Item { item_id },
        ..
    } = &body.reference.target
    else {
        bail!("T body has no original completion owner");
    };
    assert_eq!(item_id, owner);
    Ok(())
}

async fn all_members(
    runtime: &StudioRuntime,
    feeds: &mut Vec<ConversationFeed>,
    id: &str,
    reference: CompletionRunRef,
    expected_bodies: &[String],
) -> Result<Vec<CompletedEntry>> {
    let scope = ChatScope::Run { reference };
    feeds.push(
        runtime
            .open_conversation_feed(id, scope.clone(), demand())
            .await?,
    );
    // The outer cleanup retains this feed even if its deadline cancels this
    // helper during a member/content read.
    let feed = feeds.last_mut().context("owned members feed")?;
    let result = async {
        let mut page = chat(feed, &scope).await?;
        let mut atoms = Vec::new();
        loop {
            let mut prefix = Vec::new();
            prefix.extend(page.entries);
            prefix.extend(atoms);
            atoms = prefix;
            let Some(before) = page.before else { break };
            page = feed.reader().load_older(&before, demand()).await?;
            page.validate_for(&scope)?;
        }
        assert_eq!(atoms.len(), expected_bodies.len());
        for (entry, text) in atoms.iter().zip(expected_bodies) {
            let atom = &entry.atom;
            ensure!(
                matches!(
                    atom.lifecycle,
                    ChatAtomLifecycle::Terminal {
                        outcome: ChatTerminalOutcome::Completed,
                        ..
                    }
                ),
                "member lost its real terminal"
            );
            let body = atom.contents.first().context("member original body")?;
            let ContentTarget::Body {
                owner: ContentOwner::Item { item_id },
                ..
            } = &body.reference.target
            else {
                bail!("completed member retained a mutable content owner");
            };
            ensure!(
                Some(item_id) == atom.completion_item_id.as_ref(),
                "member body changed owner"
            );
            let content = feed
                .reader()
                .read_content(
                    &body.reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 4096,
                    },
                )
                .await?;
            ensure!(
                content.bytes == text.as_bytes(),
                "member body changed bytes"
            );
        }
        Ok(atoms)
    }
    .await;
    let close = feed.close().await;
    let reader = feed.reader().close().await;
    close?;
    reader?;
    result
}

#[tokio::test]
async fn ordinary_backlog_preserves_completion_order_runs_and_original_bytes() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = run_case(&env, false).await;
    eprintln!("ordinary backlog story before environment shutdown: {result:#?}");
    env.finish(result).await
}

#[tokio::test]
async fn backlog_save_failure_retains_pending_and_retries_original_completions() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = run_case(&env, true).await;
    eprintln!("failed-save backlog story before environment shutdown: {result:#?}");
    env.finish(result).await
}

fn diagnostic(
    env: &support::Environment,
    id: &str,
    owner: &ThreadHandle,
    script: &Script,
    phase: &str,
) -> String {
    let core = owner.snapshot();
    let channel = env.runtime.store.thread_persistence().history_channel(id);
    let status = channel.subscribe().borrow().clone();
    let live = env.runtime.thread_observations.live_feed(id);
    let publication = live
        .as_ref()
        .and_then(|live| live.current_conversation())
        .map(|current| {
            (
                current.head,
                current.session.durable_seq(),
                current.activity.revision,
                current.activity.entries.len(),
                current.serial,
            )
        });
    let owner_status = live.as_ref().map(|live| {
        let registration = live.conversation();
        let progress = registration.owner_progress.borrow();
        (
            progress.is_finished(),
            progress.retained_error().map(|error| format!("{error:#}")),
        )
    });
    let writer = env
        .runtime
        .persistence_queue_snapshot()
        .threads
        .into_iter()
        .find(|thread| thread.thread_id == id);
    format!(
        "wait={phase}; producer_stage={:?}; producer={:?}; \
         core_commit={}; core_lifecycle={:?}; core_model={:?}; persistence={:?}; \
         channel={status:?}; handoff={}; channel_stopping={}; publication={publication:?}; \
         owner_finished/error={owner_status:?}; writer={writer:?}",
        *script.stage.borrow(),
        *script.diagnostic.lock().unwrap(),
        core.commit_sequence,
        core.lifecycle,
        core.model_execution,
        core.persistence,
        channel.handoff_ticket(),
        channel.is_stopping(),
    )
}

async fn run_case(env: &support::Environment, fail_final_save: bool) -> Result<()> {
    let thread = env
        .runtime
        .create_thread(&env.project.id, "ordinary backlog owner")
        .await?;
    let id = thread.id.clone();
    let owner: ThreadHandle = env.runtime.ensure_thread_owner(&id).await?;
    let script = Script::new();
    owner
        .replace_model(ModelFactory::new(ScriptModel(script.clone())))
        .await?;
    let history = env.runtime.store.history(&id).await?;
    let channel = env.runtime.store.thread_persistence().history_channel(&id);
    let cancel = CancellationToken::new();
    let mut run = tokio::spawn({
        let owner = owner.clone();
        let cancel = cancel.clone();
        let script = script.clone();
        async move {
            let result = owner
                .run_turn(TurnInput {
                    turn_id: "a34-turn".into(),
                    attempt_prefix: "a34-attempt".into(),
                    content: vec![],
                    max_model_steps: ModelStepLimit::Limited(1.try_into().expect("one model step")),
                    cancellation: cancel,
                })
                .await;
            script.finished(format!("Core run_turn: {result:?}"));
            result
        }
    });
    // Preserve the original typed reply once consumed. Cleanup must not poll a
    // completed JoinHandle again, including when the reply reports a failure.
    let mut producer_join = None;
    let mut feeds = Vec::new();
    let mut delivered = Vec::new();
    let mut database_connection = None;
    let mut fault_trigger_installed = false;
    let mut phase = "first-window producer ACKs";
    let story_started = std::time::Instant::now();
    let trace_phase = |phase: &str| {
        eprintln!("A34 elapsed={:?}; phase={phase}", story_started.elapsed());
    };
    trace_phase(phase);
    let story = async {
        script.reached(Stage::FirstWindow).await?;
        phase = "first-window observation/durable barrier";
        env.runtime.synchronize_thread_observation(&id).await?;
        channel
            .await_handoff_durable(&id, channel.handoff_ticket())
            .await?;
        let source = env
            .runtime
            .thread_observations
            .live_feed(&id)
            .context("original live owner")?;
        let first = source.current_conversation().context("first publication")?;
        assert_eq!(first.head, WINDOW as u64);
        assert_eq!(first.session.durable_seq(), first.head);
        assert_eq!(first.activity.entries.len(), 1, "only R is still active");
        script.release();
        phase = "second-window / R-T-U producer ACKs";
        script.reached(Stage::Cut).await?;
        phase = "R-T-U observation/durable barrier";
        env.runtime.synchronize_thread_observation(&id).await?;
        channel
            .await_handoff_durable(&id, channel.handoff_ticket())
            .await?;
        let slot = env.runtime.thread_observations.observation_slot(&id);
        let (position, _) = slot.capture();
        let installed = position.source.context("installed original owner")?;
        let live = installed
            .current_conversation()
            .context("cut publication")?;
        let cut = live.current.projection().source_effect_seq;
        let cut_head = live.head;
        assert_eq!(cut_head, (PREFIX_MEMBERS + 1) as u64);
        assert_eq!(live.session.durable_seq(), cut_head);
        assert_eq!(live.activity.completed_through, cut_head);
        assert_eq!(
            live.activity.entries.len(),
            2,
            "R and U remain active after T completed"
        );
        assert!(
            live.activity
                .entries
                .iter()
                .all(|entry| matches!(entry.atom.lifecycle, ChatAtomLifecycle::Active { .. }))
        );
        let database = history
            .conversation_database_id()
            .await?
            .context("database identity")?;
        phase = "original Main Set and T range";
        feeds.push(
            env.runtime
                .open_conversation_feed(&id, ChatScope::Main, demand())
                .await?,
        );
        let initial = chat(&mut feeds[0], &ChatScope::Main).await?;
        assert_eq!(initial.placement, ChatPlacement::Set);
        assert_eq!(initial.through_seq, cut_head);
        assert_eq!(
            initial.entries.len(),
            2,
            "prefix work representative followed by completed T"
        );
        let prefix_head = initial.entries[0].clone();
        assert_eq!(
            prefix_head.main_presentation,
            MainPresentation::ForegroundWork
        );
        assert_eq!(
            prefix_head.run,
            Some(CompletionRunPosition {
                start_seq: 1,
                ordinal: PREFIX_MEMBERS as u64
            })
        );
        assert!(matches!(
            prefix_head.atom.payload,
            Some(PayloadData::Deferred { .. })
        ));
        let text = initial.entries[1].clone();
        assert_eq!(text.main_presentation, MainPresentation::Single);
        assert_eq!(text.completion_seq, cut_head);
        check_text(feeds[0].reader(), &text).await?;
        let mut status = channel.subscribe();
        assert_eq!(channel.handoff_ticket(), cut);
        assert_eq!(status.borrow().committed_sequence, cut);
        assert_eq!(status.borrow().queued_records, 0);
        assert!(!channel.is_stopping());
        let path = env
            .runtime
            .store
            .registered_session_paths(&id)?
            .history_database();
        let mode = if fail_final_save { "rw" } else { "ro" };
        database_connection =
            Some(Database::connect(format!("sqlite://{}?mode={mode}", path.display())).await?);
        let db = database_connection
            .as_ref()
            .context("test read connection")?;
        let prefix = facts(db, cut).await?;
        assert!(prefix.len() > PREFIX_MEMBERS * 2);
        let originals = saved_items(db).await?;
        assert_eq!(originals.len(), cut_head as usize);
        let chunks = saved_chunks(db).await?;
        assert!(!chunks.is_empty(), "fixture did not save original bodies");

        script.release();
        phase = "ordinary suffix producer ACKs";
        trace_phase(phase);
        // The original consumer keeps reading while the original publisher
        // applies backpressure; a save barrier is not a substitute for reads.
        receive_while(
            &mut feeds[0],
            &mut delivered,
            script.reached(Stage::SuffixReady),
        )
        .await?;
        let suffix_target = owner.snapshot().commit_sequence;
        phase = "ordinary suffix fixed-target observation/durable barrier";
        trace_phase(phase);
        receive_while(
            &mut feeds[0],
            &mut delivered,
            env.runtime.synchronize_thread_observation(&id),
        )
        .await?;
        channel
            .await_handoff_durable(&id, channel.handoff_ticket())
            .await?;
        let suffix_status = status.borrow_and_update().clone();
        ensure!(
            suffix_status.fault.is_none(),
            "ordinary backlog faulted: {suffix_status:?}"
        );
        ensure!(
            suffix_status.error.is_none(),
            "ordinary backlog save failed: {suffix_status:?}"
        );
        assert!(suffix_status.admitted_sequence >= suffix_target);
        assert!(suffix_status.committed_sequence >= suffix_target);
        assert_eq!(suffix_status.queued_records, 0);
        assert!(!channel.is_stopping());
        assert_eq!(
            facts(db, cut).await?,
            prefix,
            "durable prefix changed while suffix drained"
        );
        assert!(Arc::ptr_eq(
            &channel,
            &env.runtime.store.thread_persistence().history_channel(&id)
        ));
        let (after_suffix, _) = slot.capture();
        assert!(Arc::ptr_eq(
            after_suffix.source.as_ref().context("owner after suffix")?,
            &installed
        ));
        assert_eq!(
            history.conversation_database_id().await?.as_deref(),
            Some(database.as_str())
        );
        let suffix_live = installed
            .current_conversation()
            .context("suffix publication")?;
        assert_eq!(
            suffix_live.current.projection().source_effect_seq,
            suffix_target
        );
        assert!(suffix_target > cut);
        assert_eq!(
            suffix_live.head,
            (PREFIX_MEMBERS + 1 + SUFFIX_MEMBERS + 1) as u64
        );
        assert_eq!(suffix_live.session.durable_seq(), suffix_live.head);
        assert_eq!(
            suffix_live.activity.entries.len(),
            1,
            "only U remains active"
        );
        assert_eq!(
            saved_items(db)
                .await?
                .into_iter()
                .filter(|row| row.seq <= cut_head)
                .collect::<Vec<_>>(),
            originals,
            "later saves changed immutable payload/metadata/run bytes"
        );

        if fail_final_save {
            db.execute_unprepared(
                "CREATE TRIGGER reject_backlog_completion BEFORE INSERT ON conversation_items
                 BEGIN SELECT RAISE(ABORT,'injected backlog completion failure'); END",
            )
            .await?;
            fault_trigger_installed = true;
        }
        script.release();
        phase = "same producer U terminal";
        trace_phase(phase);
        if fail_final_save {
            phase = "real writer fault and retained pending completion";
            receive_while(&mut feeds[0], &mut delivered, async {
                while status.borrow_and_update().fault.is_none() {
                    status.changed().await?;
                }
                Ok(())
            })
            .await?;
            let failed = status.borrow().clone();
            assert!(failed.queued_records > 0);
            assert!(
                failed
                    .error
                    .as_deref()
                    .is_some_and(|error| error.contains("injected backlog completion failure"))
            );
            // The failed transaction cannot confirm the newly published U.
            assert_eq!(live.session.durable_seq(), suffix_live.head);
            assert!(live.session.head_seq() > live.session.durable_seq());
            assert_eq!(
                saved_items(db).await?.last().context("saved prefix")?.seq,
                suffix_live.head
            );
            let pending_feed = feeds.len();
            feeds.push(
                env.runtime
                    .open_conversation_feed(&id, ChatScope::Main, demand())
                    .await?,
            );
            let set = chat(&mut feeds[pending_feed], &ChatScope::Main).await?;
            let pending = set.entries.last().context("pending U representative")?;
            assert!(pending.completion_seq > live.session.durable_seq());
            let original = feeds[pending_feed]
                .reader()
                .read_completed(&pending.record_id, demand())
                .await?;
            let body = original
                .atom
                .contents
                .first()
                .context("pending original U body")?;
            let bytes = feeds[pending_feed]
                .reader()
                .read_content(
                    &body.reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 4096,
                    },
                )
                .await?;
            assert_eq!(bytes.bytes, b"U ended after backlog");
            db.execute_unprepared("DROP TRIGGER reject_backlog_completion")
                .await?;
            fault_trigger_installed = false;
            env.runtime
                .retry_thread_history(&id, failed.fault_generation)
                .await?;
            env.runtime
                .resume_thread_history(&id, failed.fault_generation)
                .await?;
            let durable = feeds[pending_feed]
                .reader()
                .read_completed(&original.record_id, demand())
                .await?;
            assert_eq!(durable.record_id, original.record_id);
            assert_eq!(durable.completion_seq, original.completion_seq);
            assert_eq!(durable.run, original.run);
            assert_eq!(durable.atom.payload, original.atom.payload);
            assert_eq!(durable.atom.contents, original.atom.contents);
        }
        let joined = receive_while(&mut feeds[0], &mut delivered, async {
            (&mut run)
                .await
                .context("ordinary backlog producer join")
                .and_then(|joined| Ok(joined?))
        })
        .await;
        let completed = joined
            .as_ref()
            .is_ok_and(|completion| completion.outcome == TurnOutcome::Completed);
        let terminal = format!("{joined:?}");
        producer_join = Some(joined);
        ensure!(
            completed,
            "original Core producer ended unexpectedly: {terminal}; persistence={:?}",
            owner.snapshot().persistence
        );
        let target = owner.snapshot().commit_sequence;
        phase = "final observation/durable barrier";
        trace_phase(phase);
        receive_while(
            &mut feeds[0],
            &mut delivered,
            env.runtime.synchronize_thread_observation(&id),
        )
        .await?;
        channel
            .await_handoff_durable(&id, channel.handoff_ticket())
            .await?;
        assert_eq!(
            facts(db, cut).await?,
            prefix,
            "C facts changed while ordinary backlog drained"
        );
        let latest = installed
            .current_conversation()
            .context("final publication")?;
        assert_eq!(latest.current.projection().source_effect_seq, target);
        assert!(target > suffix_target);
        let final_status = status.borrow_and_update().clone();
        assert_eq!(final_status.queued_records, 0);
        assert_eq!(final_status.admitted_sequence, target);
        assert_eq!(final_status.committed_sequence, target);
        assert!(final_status.fault.is_none() && final_status.error.is_none());
        assert_eq!(latest.session.durable_seq(), latest.head);
        assert!(latest.activity.entries.is_empty());
        let (final_position, _) = slot.capture();
        assert!(Arc::ptr_eq(
            final_position
                .source
                .as_ref()
                .context("final original owner")?,
            &installed
        ));
        phase = "final immutable completion inventory and raw bytes";
        let saved = saved_items(db).await?;
        assert_eq!(saved.last().context("final completion")?.seq, latest.head);
        assert_eq!(
            saved
                .iter()
                .filter(|row| row.seq <= cut_head)
                .cloned()
                .collect::<Vec<_>>(),
            originals
        );
        let final_chunks = saved_chunks(db).await?;
        for chunk in &chunks {
            assert!(
                final_chunks.contains(chunk),
                "a durable original body chunk changed"
            );
        }
        let visible = saved
            .iter()
            .filter(|row| row.run.is_some())
            .collect::<Vec<_>>();
        assert_eq!(visible.len(), PREFIX_MEMBERS + SUFFIX_MEMBERS + 3);
        let suffix = visible
            .iter()
            .filter(|row| row.seq > cut_head)
            .collect::<Vec<_>>();
        while delivered.len() < suffix.len() {
            let batch = chat(&mut feeds[0], &ChatScope::Main).await?;
            assert_eq!(batch.placement, ChatPlacement::Append);
            delivered.extend(batch.entries);
        }
        assert_eq!(
            delivered
                .iter()
                .map(|entry| (&entry.record_id, entry.completion_seq, entry.run))
                .collect::<Vec<_>>(),
            suffix
                .iter()
                .map(|row| (&row.id, row.seq, row.run))
                .collect::<Vec<_>>()
        );
        // The emitter starts R before the prefix and U before the suffix. Neither
        // may move backwards in completed history when its terminal finally arrives.
        let suffix_start = cut_head + 1;
        for (index, row) in suffix.iter().enumerate() {
            assert_eq!(
                row.run,
                Some(CompletionRunPosition {
                    start_seq: suffix_start,
                    ordinal: index as u64 + 1
                })
            );
        }
        phase = "real Run pages and original body ranges";
        let prefix_bodies = (0..PREFIX_MEMBERS)
            .map(|index| format!("prefix body {index}"))
            .collect::<Vec<_>>();
        let mut suffix_bodies = (0..SUFFIX_MEMBERS)
            .map(|index| format!("suffix body {index}"))
            .collect::<Vec<_>>();
        suffix_bodies.extend(["R ended after T".into(), "U ended after backlog".into()]);
        for (start, expected_bodies) in [(1, prefix_bodies), (suffix_start, suffix_bodies)] {
            let actual = all_members(
                &env.runtime,
                &mut feeds,
                &id,
                CompletionRunRef {
                    database_id: database.clone(),
                    index_version: COMPLETED_READ_INDEX_VERSION,
                    start_seq: start,
                },
                &expected_bodies,
            )
            .await?;
            assert_eq!(actual.len(), expected_bodies.len());
            let expected = saved
                .iter()
                .filter(|row| row.run.is_some_and(|run| run.start_seq == start))
                .collect::<Vec<_>>();
            for (entry, row) in actual.iter().zip(expected) {
                assert_eq!(
                    (&entry.record_id, entry.completion_seq, entry.run),
                    (&row.id, row.seq, row.run)
                );
                let atom: ChatAtom = serde_json::from_slice(&row.metadata)?;
                assert_eq!(entry.atom.id, atom.id);
                assert_eq!(entry.atom.contents, atom.contents);
            }
        }
        phase = "final Main representatives and real Hidden Children";
        let final_feed = feeds.len();
        feeds.push(
            env.runtime
                .open_conversation_feed(&id, ChatScope::Main, demand())
                .await?,
        );
        let set = chat(&mut feeds[final_feed], &ChatScope::Main).await?;
        assert_eq!(set.placement, ChatPlacement::Set);
        assert_eq!(set.through_seq, latest.head);
        assert_eq!(set.entries.len(), 3);
        assert_eq!(
            set.entries
                .iter()
                .map(|entry| entry.run.context("Main run").map(|run| run.start_seq))
                .collect::<Result<Vec<_>>>()?,
            vec![1, cut_head, suffix_start]
        );
        let fresh_text = &set.entries[1];
        assert_eq!(fresh_text.record_id, text.record_id);
        assert_eq!(fresh_text.atom.contents, text.atom.contents);
        check_text(feeds[final_feed].reader(), fresh_text).await?;
        let hidden = saved
            .iter()
            .find(|row| {
                serde_json::from_slice::<ChatAtom>(&row.metadata)
                    .is_ok_and(|atom| atom.kind == ChatAtomKind::TurnReceipt)
            })
            .context("real successful Turn receipt")?;
        assert!(hidden.run.is_none());
        let scope = ChatScope::Children {
            parent_id: hidden.parent.clone().context("real receipt parent")?,
        };
        let children_feed = feeds.len();
        feeds.push(
            env.runtime
                .open_conversation_feed(&id, scope.clone(), demand())
                .await?,
        );
        let mut page = chat(&mut feeds[children_feed], &scope).await?;
        let mut found = false;
        loop {
            for entry in page.entries {
                if entry.record_id == hidden.id {
                    assert_eq!(entry.main_presentation, MainPresentation::Hidden);
                    assert!(entry.run.is_none());
                    assert_eq!(entry.completion_seq, hidden.seq);
                    found = true;
                }
            }
            let Some(before) = page.before else {
                break;
            };
            page = feeds[children_feed]
                .reader()
                .load_older(&before, demand())
                .await?;
            page.validate_for(&scope)?;
        }
        assert!(found, "Children suppressed its real successful receipt");
        Ok::<_, anyhow::Error>(())
    };
    // Assertion failures must also reach the owned resource cleanup below.
    let deadline = support::integration_test_deadline()?;
    let result = match tokio::time::timeout(deadline, AssertUnwindSafe(story).catch_unwind()).await
    {
        Ok(Ok(result)) => result,
        Ok(Err(panic)) => Err(anyhow::anyhow!(
            "A34 assertion: {}",
            panic
                .downcast_ref::<String>()
                .map(String::as_str)
                .or_else(|| panic.downcast_ref::<&str>().copied())
                .unwrap_or("non-string panic")
        )),
        Err(error) => Err(anyhow::Error::new(error).context("A34 owner/queue deadline")),
    }
    .with_context(|| diagnostic(env, &id, &owner, &script, phase));
    // End all environment waits before runtime close/join, including a failed
    // assertion path. A test-owned JoinHandle is always observed, never detached.
    trace_phase("cleanup begins");
    let mut cleanup_errors = Vec::new();
    if fault_trigger_installed {
        if let Some(db) = &database_connection
            && let Err(error) = db
                .execute_unprepared("DROP TRIGGER IF EXISTS reject_backlog_completion")
                .await
        {
            cleanup_errors.push(format!("fault trigger cleanup: {error:#}"));
        }
        if let Err(error) = env.runtime.retry_persistence().await {
            cleanup_errors.push(format!("fault retry cleanup: {error:#}"));
        }
    }
    cancel.cancel();
    script.next.add_permits(3);
    let joined = if let Some(joined) = producer_join {
        joined
    } else {
        match tokio::time::timeout(deadline, &mut run).await {
            Ok(joined) => joined
                .context("A34 producer join")
                .and_then(|joined| Ok(joined?)),
            Err(error) => {
                run.abort();
                let cancelled = run.await;
                Err(anyhow::Error::new(error).context(format!(
                    "A34 producer join deadline; abort receipt={cancelled:?}"
                )))
            }
        }
    };
    for feed in &mut feeds {
        if let Err(error) = feed.close().await {
            cleanup_errors.push(format!("feed close: {error:#}"));
        }
        if let Err(error) = feed.reader().close().await {
            cleanup_errors.push(format!("reader close: {error:#}"));
        }
    }
    if let Some(db) = database_connection
        && let Err(error) = db.close().await
    {
        cleanup_errors.push(format!("readonly database close: {error:#}"));
    }
    let cleanup_context = format!(
        "A34 cleanup: producer_join={joined:?}; resource_errors={cleanup_errors:?}; after={}",
        diagnostic(env, &id, &owner, &script, phase),
    );
    trace_phase("owned producer/feed/reader/database cleanup complete");
    let result = result.and_then(|()| {
        let completion = joined?;
        ensure!(
            completion.outcome == TurnOutcome::Completed,
            "A34 producer failed"
        );
        ensure!(cleanup_errors.is_empty(), "A34 resource cleanup failed");
        Ok(())
    });
    result.context(cleanup_context)
}
