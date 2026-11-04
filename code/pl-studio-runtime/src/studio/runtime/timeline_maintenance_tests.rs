//! A34: the installed product owner, not a test projection worker, owns maintenance.
use super::*;
use crate::{
    runtime_test_support as support,
    studio::thread_projection::{
        TimelineProjection,
        timeline::{MemberChange, TimelineInput, lightweight},
    },
};
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
    collections::BTreeMap,
    panic::AssertUnwindSafe,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::sync::{Semaphore, watch};
use tokio_util::sync::CancellationToken;

const WINDOW: usize = 128;
const PREFIX_MEMBERS: usize = 2 * WINDOW;
// Exercise the existing record ceiling, rather than inventing a smaller queue or
// charging artificial resident bytes. Each suffix member makes two real effects.
const QUEUE_RECORDS: usize = 4096;
const SUFFIX_MEMBERS: usize = QUEUE_RECORDS / 2;
const TEXT: &str = "T completed before R; 正文与附件所有权不能随维护换代";
const R: &str = "a34-r";
const T: &str = "a34-t";
const U: &str = "a34-u";

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum Stage {
    Initial,
    FirstWindow,
    Cut,
    QueueFull,
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
    // The queue now owns exactly its existing record budget. This is a real
    // canonical terminal, ACKed by Core but owed behind the original full sink.
    complete(script, members, R, true, "R ended after T").await?;
    script
        .boundary(Stage::QueueFull, &request.cancellation)
        .await?;
    // A new producer fact naturally retries Core's retained R obligation when
    // capacity returns. No test reducer, reload, publish or replacement owner.
    complete(script, members, U, true, "U ended after maintenance").await?;
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
            ConversationEvent::State { .. } => {}
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
async fn saved_items(db: &DatabaseConnection) -> Result<Vec<TimelineItem>> {
    db.query_all_raw(sql(
        "SELECT metadata FROM timeline_items WHERE location='history' ORDER BY position",
        vec![],
    ))
    .await?
    .into_iter()
    .map(|row| {
        Ok(serde_json::from_slice(
            &row.try_get::<Vec<u8>>("", "metadata")?,
        )?)
    })
    .collect()
}
fn logical(mut item: TimelineItem) -> TimelineItem {
    if let Some(reference) = &mut item.members {
        reference.projection_generation = "logical-generation".into();
    }
    item
}

/// Postcondition oracle only: a fresh uninterrupted invocation of the production
/// fold over the exact canonical facts. Never drives the tested owner's readiness.
/// No legacy branch is appropriate: every fact in this fixture has real positions.
async fn uninterrupted(
    db: &DatabaseConnection,
    database: &str,
) -> Result<(Vec<TimelineItem>, BTreeMap<(String, u64), ChatAtom>)> {
    let mut inputs = Vec::new();
    for (_, phase, bytes) in facts(db, u64::try_from(i64::MAX)?).await? {
        ensure!(
            phase == "start" || phase == "terminal",
            "unexpected legacy input"
        );
        let atom: ChatAtom = serde_json::from_slice(&bytes)?;
        let payload = if let Some(id) = &atom.completion_item_id {
            let row = db
                .query_one_raw(sql(
                    "SELECT length(payload) AS bytes FROM conversation_items WHERE item_id=?",
                    vec![id.clone().into()],
                ))
                .await?
                .context("original completion owner")?;
            Some(PayloadData::Deferred {
                reference: ContentRef {
                    database_id: database.into(),
                    target: ContentTarget::ItemPayload {
                        item_id: id.clone(),
                    },
                },
                byte_length: u64::try_from(row.try_get::<i64>("", "bytes")?)?,
            })
        } else {
            None
        };
        inputs.push(TimelineInput::Atom {
            atom: Box::new(atom),
            payload,
        });
    }
    for row in db
        .query_all_raw(sql(
            "SELECT source_key,started_effect,started_suborder,ended_effect,ended_suborder,outcome
             FROM conversation_sources WHERE ended_effect IS NOT NULL",
            vec![],
        ))
        .await?
    {
        inputs.push(TimelineInput::SourceEnd {
            source: ChatSourceState {
                source: serde_json::from_str(&row.try_get::<String>("", "source_key")?)?,
                lifecycle: ChatSourceLifecycle::Ended {
                    outcome: serde_json::from_str(&row.try_get::<String>("", "outcome")?)?,
                },
                started: match row.try_get::<Option<i64>>("", "started_effect")? {
                    Some(effect) => Some(ChatFactPosition {
                        effect_seq: u64::try_from(effect)?,
                        suborder: u32::try_from(row.try_get::<i64>("", "started_suborder")?)?,
                    }),
                    None => None,
                },
                ended: Some(ChatFactPosition {
                    effect_seq: u64::try_from(row.try_get::<i64>("", "ended_effect")?)?,
                    suborder: u32::try_from(row.try_get::<i64>("", "ended_suborder")?)?,
                }),
            },
        });
    }
    let mut ordered = inputs
        .into_iter()
        .map(|input| Ok((input.order(0)?, input)))
        .collect::<Result<Vec<_>>>()?;
    ordered.sort_by(|left, right| left.0.cmp(&right.0));
    let mut projection = TimelineProjection::new(database.into(), "uninterrupted".into(), 0);
    let mut items = Vec::new();
    let mut members = BTreeMap::new();
    for (_, input) in ordered {
        projection.apply_input(input)?;
        items.extend(projection.take_committed().into_iter().map(logical));
        let update = projection.take_update()?;
        for MemberChange {
            item_id,
            member_order,
            atom,
            ..
        } in update.members().iter().cloned()
        {
            // A terminal updates its original member slot, not a second admission.
            members.insert((item_id, member_order), atom);
        }
    }
    ensure!(
        projection.current_items().is_empty(),
        "reference source was not really ended"
    );
    Ok((items, members))
}

async fn check_text(reader: &ConversationReader, item: &TimelineItem) -> Result<()> {
    let owner = item.content_item_id.as_ref().context("T original owner")?;
    ensure!(!item.contents.is_empty(), "T lost its body references");
    let body = &item.contents[0];
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
    reference: TimelineMembersRef,
    first_body: &str,
    last_body: &str,
) -> Result<Vec<ChatAtom>> {
    let scope = ChatScope::GroupMembers { reference };
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
            for entry in page.entries {
                match entry {
                    ChatEntry::Atom(atom) => prefix.push(lightweight(&atom)),
                    ChatEntry::Source(_) => {}
                    ChatEntry::Item(_) => bail!("GroupMembers returned Main items"),
                }
            }
            prefix.extend(atoms);
            atoms = prefix;
            let Some(before) = page.before else { break };
            page = feed.reader().load_older(&before, demand()).await?;
            page.validate_for(&scope)?;
        }
        for (atom, text) in [
            (atoms.first().context("first group member")?, first_body),
            (atoms.last().context("last group member")?, last_body),
        ] {
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
async fn a34_real_owner_rebuild_preserves_multifragment_cut_and_resumes_original_full_queue()
-> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = run_case(&env).await;
    env.finish(result).await
}

fn diagnostic(
    env: &support::Environment,
    id: &str,
    owner: &ThreadHandle,
    script: &Script,
    history: &crate::studio::storage::history::HistoryStore,
    phase: &str,
    gate_owned: bool,
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
                current.projection_generation.clone(),
                current.current.projection().source_effect_seq,
                current.current.projection().items.len(),
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
        "wait={phase}; gate_release_owned={gate_owned}; producer_stage={:?}; producer={:?}; \
         core_commit={}; core_lifecycle={:?}; core_model={:?}; persistence={:?}; \
         channel={status:?}; handoff={}; channel_stopping={}; timeline_paused={}; publication={publication:?}; \
         owner_finished/error={owner_status:?}; writer={writer:?}",
        *script.stage.borrow(),
        *script.diagnostic.lock().unwrap(),
        core.commit_sequence,
        core.lifecycle,
        core.model_execution,
        core.persistence,
        channel.handoff_ticket(),
        channel.is_stopping(),
        history.timeline_is_paused(),
    )
}

async fn run_case(env: &support::Environment) -> Result<()> {
    let thread = env
        .runtime
        .create_thread(&env.project.id, "A34 maintenance owner")
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
    let mut database_connection = None;
    // A timeout cancels the story, not the real maintenance owner. Keep its
    // normal-success release responsibility outside that cancellable future.
    let mut gate_release = None;
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
        let first = history
            .conversation_current()
            .await?
            .context("first durable window")?;
        assert_eq!(first.items.len(), 1);
        assert_eq!(
            first.items[0]
                .summary
                .as_ref()
                .context("open group")?
                .member_count,
            (WINDOW + 1) as u32
        );
        script.release();
        phase = "second-window / R-T-U producer ACKs";
        script.reached(Stage::Cut).await?;
        phase = "R-T-U observation/durable barrier";
        env.runtime.synchronize_thread_observation(&id).await?;
        let slot = env.runtime.thread_observations.observation_slot(&id);
        let (position, _) = slot.capture();
        let source = position.source.context("installed original owner")?;
        let registration = source.conversation();
        let mut publication = registration.progress;
        let mut owner_progress = registration.owner_progress;
        let live = source
            .current_conversation()
            .context("original publication")?;
        let old_generation = live.projection_generation.clone();
        let cut_current = live.current.projection().clone();
        assert_eq!(cut_current.items.len(), 3, "R / completed T / active U");
        let r_group = &cut_current.items[0];
        let text = &cut_current.items[1];
        let u_group = &cut_current.items[2];
        assert_eq!(r_group.kind, TimelineItemKind::WorkGroup);
        assert_eq!(
            r_group.summary.as_ref().context("R summary")?.member_count,
            (PREFIX_MEMBERS + 1) as u32
        );
        assert!(r_group.admission_closed);
        assert_eq!(text.kind, TimelineItemKind::Text);
        assert_eq!(text.outcome, Some(ChatTerminalOutcome::Completed));
        assert_eq!(u_group.kind, TimelineItemKind::WorkGroup);
        assert!(cut_current.items.iter().all(|item| item.position.is_none()));
        assert!(r_group.source == text.source && text.source == u_group.source);
        assert_eq!(
            cut_current
                .atoms
                .iter()
                .filter(|atom| matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }))
                .count(),
            2
        );
        assert!(
            cut_current.atoms.len() < WINDOW,
            "completed group was mirrored into active current"
        );
        let old_ref = r_group.members.clone().context("old typed R ref")?;
        phase = "original Main Set and T range";
        feeds.push(
            env.runtime
                .open_conversation_feed(&id, ChatScope::Main, demand())
                .await?,
        );
        let initial = chat(&mut feeds[0], &ChatScope::Main).await?;
        assert_eq!(initial.placement, ChatPlacement::Set);
        check_text(feeds[0].reader(), text).await?;
        let old_reader = feeds[0].reader().clone();
        let (entered, release) = history.arm_timeline_rebuild_gate().await;
        gate_release = Some(release);
        history.request_timeline_maintenance();
        phase = "owner maintenance gate after durable C";
        trace_phase(phase);
        entered.await?;
        phase = "durable C current/recovery/readonly facts";
        trace_phase(phase);
        let durable = history.conversation_current().await?.context("durable C")?;
        let cut = durable.source_effect_seq;
        assert_eq!(cut, cut_current.source_effect_seq);
        assert_eq!(durable.items, cut_current.items);
        assert_eq!(channel.handoff_ticket(), cut);
        let mut status = channel.subscribe();
        assert_eq!(status.borrow().committed_sequence, cut);
        assert_eq!(status.borrow().queued_records, 0);
        assert!(!channel.is_stopping());
        assert!(history.timeline_is_paused());
        let (database, generation, _, recovery) =
            history.timeline_snapshot().await?.context("C recovery")?;
        assert_eq!(generation, old_generation);
        let recovery: serde_json::Value = serde_json::from_slice(&recovery)?;
        assert_eq!(
            recovery["items"]
                .as_array()
                .context("recovery fragments")?
                .len(),
            3
        );
        assert_eq!(
            recovery["active"]
                .as_object()
                .context("recovery active")?
                .len(),
            2
        );
        let recovery_bytes = serde_json::to_vec(&recovery)?;
        assert!(
            !String::from_utf8_lossy(&recovery_bytes).contains("prefix body"),
            "recovery retained finished member bodies"
        );
        let path = env
            .runtime
            .store
            .registered_session_paths(&id)?
            .history_database();
        database_connection =
            Some(Database::connect(format!("sqlite://{}?mode=ro", path.display())).await?);
        let db = database_connection
            .as_ref()
            .context("test read connection")?;
        let prefix = facts(db, cut).await?;
        assert!(prefix.len() > PREFIX_MEMBERS * 2);
        script.release();
        phase = "C suffix producer / real QueueFull";
        trace_phase(phase);
        script.reached(Stage::QueueFull).await?;
        // Do not infer pressure from one Pending poll: the original sink reports
        // its classified ceiling and still owns the complete accepted prefix.
        let full = status.borrow_and_update().clone();
        assert_eq!(
            full.fault,
            Some(pl_protocol::studio::HistoryFault::QueueFull)
        );
        assert_eq!(full.queued_records, QUEUE_RECORDS as u64);
        assert!(full.queued_bytes > 0);
        assert_eq!(full.admitted_sequence, cut + QUEUE_RECORDS as u64);
        assert_eq!(full.committed_sequence, cut);
        assert!(!channel.is_stopping());
        assert_eq!(
            owner.snapshot().lifecycle,
            pl_core::thread::ThreadLifecycle::Open
        );
        assert_eq!(
            owner.snapshot().persistence.admitted_sequence,
            full.admitted_sequence
        );
        let queued = channel.unprojected_writes();
        assert_eq!(queued.len(), QUEUE_RECORDS);
        for (offset, write) in queued.iter().enumerate() {
            assert_eq!(write.effect.sequence, cut + 1 + offset as u64);
            assert_eq!(write.effect.sequence, write.checkpoint.state_revision);
        }
        drop(queued);
        let owed = owner
            .effects()
            .await?
            .into_iter()
            .find(|effect| effect.sequence == full.admitted_sequence + 1)
            .context("Core's original refused obligation")?;
        assert_eq!(owed.model_members.len(), 1);
        assert_eq!(owed.model_members[0].member_id, R);
        assert_eq!(
            owed.model_members[0].payload,
            receipt(R, true, "R ended after T")?
        );
        phase = "original Core flush at classified full sink";
        trace_phase(phase);
        assert!(
            owner.flush().await.is_err(),
            "full sink accepted the owed producer fence"
        );
        assert_eq!(
            history
                .conversation_current()
                .await?
                .context("paused current")?
                .source_effect_seq,
            cut
        );
        assert_eq!(history.timeline_generation().await?, old_generation);
        assert_eq!(facts(db, cut).await?, prefix);
        gate_release
            .take()
            .context("owned maintenance release")?
            .send(())
            .map_err(|_| anyhow::anyhow!("original maintenance owner disappeared"))?;
        phase = "same owner new-generation publication";
        trace_phase(phase);
        let new_generation = loop {
            if let Some(error) = owner_progress.borrow_and_update().retained_error() {
                return Err(anyhow::anyhow!(
                    "original maintenance owner failed: {error:#}"
                ));
            }
            if let Some(current) = publication.borrow_and_update().clone()
                && current.projection_generation != old_generation
            {
                break current.projection_generation.clone();
            }
            tokio::select! {
                changed = publication.changed() => changed.context("owner publication closed")?,
                changed = owner_progress.changed() => changed.context("projection owner ended")?,
            }
        };
        assert_ne!(new_generation, old_generation);
        assert_eq!(history.timeline_generation().await?, new_generation);
        assert!(Arc::ptr_eq(
            &channel,
            &env.runtime.store.thread_persistence().history_channel(&id)
        ));
        let (after, _) = slot.capture();
        assert!(Arc::ptr_eq(
            after.source.as_ref().context("owner after rebuild")?,
            &source
        ));
        assert_eq!(
            history.conversation_database_id().await?.as_deref(),
            Some(database.as_str())
        );
        phase = "old reader/feed/membersRef revocation";
        assert!(
            old_reader
                .list_contents(
                    text.content_item_id.as_deref().context("T owner")?,
                    None,
                    demand()
                )
                .await
                .is_err()
        );
        assert!(feeds[0].recv().await.is_err());
        let stale = env
            .runtime
            .open_conversation_feed(
                &id,
                ChatScope::GroupMembers { reference: old_ref },
                demand(),
            )
            .await;
        let stale_error = match stale {
            Err(error) => error,
            Ok(feed) => {
                feeds.push(feed);
                bail!("old members ref remained valid");
            }
        };
        assert!(matches!(
            stale_error.downcast_ref::<pl_core::chat::ChatError>(),
            Some(pl_core::chat::ChatError::StaleContent)
        ));
        phase = "new-generation Main Set / recovered R-T-U";
        feeds.push(
            env.runtime
                .open_conversation_feed(&id, ChatScope::Main, demand())
                .await?,
        );
        let rebuilt_set = chat(&mut feeds[1], &ChatScope::Main).await?;
        assert_eq!(rebuilt_set.placement, ChatPlacement::Set);
        assert_eq!(
            feeds[1].reader().inner.projection_generation,
            new_generation
        );
        let rebuilt_current = rebuilt_set
            .current
            .as_ref()
            .context("new-generation current")?;
        assert_eq!(
            rebuilt_current
                .items
                .iter()
                .map(|item| &item.id)
                .collect::<Vec<_>>(),
            vec![&r_group.id, &text.id, &u_group.id]
        );
        assert!(
            rebuilt_current
                .items
                .iter()
                .all(|item| item.position.is_none())
        );
        assert_eq!(rebuilt_current.items[0].summary, r_group.summary);
        check_text(feeds[1].reader(), &rebuilt_current.items[1]).await?;
        // QueueFull is a classified save fault, so use its real explicit retry.
        // Never clear the latch, lower a watermark or replace the producer.
        channel.retry(full.fault_generation)?;
        phase = "original writer committed accepted work after C";
        trace_phase(phase);
        let mut observed_durable = cut;
        loop {
            let state = status.borrow_and_update().clone();
            ensure!(
                state.admitted_sequence == full.admitted_sequence,
                "original admission changed while the producer was held: {state:?}"
            );
            ensure!(
                state.committed_sequence >= observed_durable
                    && state.committed_sequence <= full.admitted_sequence,
                "original accepted prefix lost its durable ordering: {state:?}"
            );
            ensure!(
                state.queued_records == full.admitted_sequence - state.committed_sequence,
                "original accepted prefix has a queue hole: {state:?}"
            );
            ensure!(
                state.fault.is_none()
                    || state.fault == Some(pl_protocol::studio::HistoryFault::QueueFull),
                "original writer failed after maintenance: {state:?}"
            );
            if state.committed_sequence > cut {
                break;
            }
            observed_durable = state.committed_sequence;
            status.changed().await?;
        }
        let still_owed = owner
            .effects()
            .await?
            .into_iter()
            .find(|effect| effect.sequence == owed.sequence)
            .context("refused producer responsibility disappeared after writer progress")?;
        assert!(Arc::ptr_eq(&still_owed, &owed));
        assert!(status.borrow().admitted_sequence < owed.sequence);
        // This proves resumed writer progress, not enough record/byte budget
        // for R at this instant. The same producer's next canonical input lets
        // the original Core/sink admission decide when its retained R can move.
        // Full drain and recovery remain required below, after that continuation.
        script.release();
        phase = "same producer U / original R owed responsibility / Core terminal";
        trace_phase(phase);
        // Core removes terminal Turns before publishing its live snapshot; a
        // subscription is not a terminal journal. The original run_turn reply
        // proves execution completion, not sink admission or durable settlement.
        let joined = (&mut run)
            .await
            .context("A34 producer join")
            .and_then(|joined| Ok(joined?));
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
        phase = "original R admitted/durable and final suffix QueueFull recovery";
        trace_phase(phase);
        loop {
            let state = status.borrow_and_update().clone();
            if state.admitted_sequence >= owed.sequence
                && state.committed_sequence >= target
                && state.queued_records == 0
                && state.fault.is_none()
                && state.error.is_none()
            {
                assert!(state.committed_sequence >= owed.sequence);
                break;
            }
            ensure!(
                state.fault.is_none()
                    || state.fault == Some(pl_protocol::studio::HistoryFault::QueueFull),
                "original suffix save failed: {state:?}"
            );
            status.changed().await?;
        }
        phase = "final observation/durable barrier";
        trace_phase(phase);
        env.runtime.synchronize_thread_observation(&id).await?;
        channel
            .await_handoff_durable(&id, channel.handoff_ticket())
            .await?;
        assert_eq!(
            facts(db, cut).await?,
            prefix,
            "C facts changed during successful replacement"
        );
        let latest = history
            .conversation_current()
            .await?
            .context("resumed durable current")?;
        assert_eq!(latest.source_effect_seq, owner.snapshot().commit_sequence);
        assert!(latest.source_effect_seq > owed.sequence);
        assert_eq!(status.borrow().queued_records, 0);
        assert_eq!(status.borrow().admitted_sequence, latest.source_effect_seq);
        assert_eq!(status.borrow().committed_sequence, latest.source_effect_seq);
        assert_eq!(history.timeline_generation().await?, new_generation);
        let (final_position, _) = slot.capture();
        assert!(Arc::ptr_eq(
            final_position
                .source
                .as_ref()
                .context("final original owner")?,
            &source
        ));
        assert!(latest.items.is_empty());
        phase = "final canonical facts and logical uninterrupted fold";
        let saved = saved_items(db).await?;
        assert_eq!(saved.len(), 3);
        assert_eq!(
            saved.iter().map(|item| &item.id).collect::<Vec<_>>(),
            vec![&r_group.id, &text.id, &u_group.id]
        );
        assert_eq!(
            saved.iter().map(|item| item.position).collect::<Vec<_>>(),
            vec![Some(0), Some(1), Some(2)]
        );
        assert_eq!(
            saved[2].summary.as_ref().context("U summary")?.member_count,
            (SUFFIX_MEMBERS + 1) as u32
        );
        let (expected, expected_members) = uninterrupted(db, &database).await?;
        assert_eq!(
            saved.clone().into_iter().map(logical).collect::<Vec<_>>(),
            expected
        );
        for group in saved.iter().filter(|item| item.is_work_group()) {
            phase = "final real GroupMembers inventory / original body ranges";
            let reference = group.members.clone().context("new typed ref")?;
            assert_eq!(reference.projection_generation, new_generation);
            let (first_body, last_body) = if group.id == r_group.id {
                (
                    "R ended after T",
                    format!("prefix body {}", PREFIX_MEMBERS - 1),
                )
            } else {
                (
                    "U ended after maintenance",
                    format!("suffix body {}", SUFFIX_MEMBERS - 1),
                )
            };
            let actual = all_members(
                &env.runtime,
                &mut feeds,
                &id,
                reference,
                first_body,
                &last_body,
            )
            .await?;
            let expected = expected_members
                .iter()
                .filter(|((item, _), _)| item == &group.id)
                .map(|(_, atom)| atom.clone())
                .collect::<Vec<_>>();
            assert_eq!(
                actual, expected,
                "member admission/order/completion owner changed"
            );
        }
        phase = "final Main Set / original T range";
        let final_feed = feeds.len();
        feeds.push(
            env.runtime
                .open_conversation_feed(&id, ChatScope::Main, demand())
                .await?,
        );
        let set = chat(&mut feeds[final_feed], &ChatScope::Main).await?;
        assert_eq!(set.placement, ChatPlacement::Set);
        assert!(
            set.current
                .as_ref()
                .context("fresh current")?
                .items
                .is_empty()
        );
        assert_eq!(
            feeds[final_feed].reader().inner.projection_generation,
            new_generation
        );
        assert!(
            set.entries
                .iter()
                .all(|entry| matches!(entry, ChatEntry::Item(_)))
        );
        let fresh_text = set
            .entries
            .iter()
            .find_map(|entry| match entry {
                ChatEntry::Item(item) if item.id == text.id => Some(item.as_ref()),
                _ => None,
            })
            .context("fresh T")?;
        assert_eq!(fresh_text.content_item_id, text.content_item_id);
        assert_eq!(fresh_text.contents, text.contents);
        check_text(feeds[final_feed].reader(), fresh_text).await?;
        old_reader.close().await?;
        Ok::<_, anyhow::Error>(())
    };
    // Assertion failures must also reach the owned resource cleanup below.
    let result = match tokio::time::timeout(
        Duration::from_secs(20),
        AssertUnwindSafe(story).catch_unwind(),
    )
    .await
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
    .with_context(|| {
        diagnostic(
            env,
            &id,
            &owner,
            &script,
            &history,
            phase,
            gate_release.is_some(),
        )
    });
    // End all environment waits before runtime close/join, including a failed
    // assertion path. A test-owned JoinHandle is always observed, never detached.
    trace_phase("cleanup begins");
    let mut cleanup_errors = Vec::new();
    // Release the held gate normally even after a cancelled assertion/read.
    // Dropping its Sender would deliberately inject maintenance cancellation,
    // latch a repair failure, and prevent the original owner from draining.
    if let Some(release) = gate_release.take()
        && release.send(()).is_err()
    {
        cleanup_errors.push("maintenance release receiver disappeared".to_owned());
    }
    let status = channel.subscribe().borrow().clone();
    if status.fault == Some(pl_protocol::studio::HistoryFault::QueueFull)
        && let Err(error) = channel.retry(status.fault_generation)
    {
        cleanup_errors.push(format!("original queue retry: {error:#}"));
    }
    cancel.cancel();
    script.next.add_permits(3);
    let joined = if let Some(joined) = producer_join {
        joined
    } else {
        match tokio::time::timeout(Duration::from_secs(20), &mut run).await {
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
        diagnostic(
            env,
            &id,
            &owner,
            &script,
            &history,
            phase,
            gate_release.is_some()
        ),
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
