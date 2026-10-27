//! Observe canonical facts, not model prose. All subscriptions have retained join ownership.
#[path = "decisions.rs"]
mod decisions;
#[path = "export.rs"]
mod export;

use super::Boundary;
use super::{
    evidence::{
        EventWriter, Evidence, MAX_THREADS, Manifest, MemberIdentity, RetiredOwedWork, Termination,
        TurnAnchor,
    },
    inputs::Inputs,
};
use anyhow::{Context, Result};
use pl_protocol::{InteractionStatus, ThreadSnapshot, WorkflowRunLifecycle};
use pl_studio_runtime::{StudioAgentDirectoryEntry, StudioRuntime};
use std::{
    collections::{BTreeMap, BTreeSet},
    time::Duration,
};

pub struct Collection {
    evidence: Evidence,
    threads: BTreeMap<String, usize>,
    writers: Vec<EventWriter>,
    decisions: decisions::Decisions,
    samples: BTreeMap<String, String>,
    sample_index: usize,
    pending: BTreeSet<(String, u64)>,
    directory_index: usize,
    directory_hash: String,
}

struct CompletionCandidate<'a> {
    root: &'a str,
    mode: &'a str,
    members: &'a [StudioAgentDirectoryEntry],
    samples: &'a BTreeMap<String, MemberSample>,
    scene: &'a Boundary,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MemberSample {
    snapshot: ThreadSnapshot,
    persistence: Option<PersistenceProof>,
    unfinished: Vec<String>,
}

#[derive(PartialEq, Eq, serde::Serialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
enum PersistenceProof {
    Live {
        accepted_sequence: u64,
        durable_sequence: u64,
        terminal: TurnAnchor,
    },
    ClosedHistory {
        history_checkpoint_validated: bool,
        terminal: TurnAnchor,
    },
}

impl Collection {
    pub fn new(evidence: Evidence) -> Self {
        Self {
            evidence,
            threads: BTreeMap::new(),
            writers: Vec::new(),
            decisions: decisions::Decisions::default(),
            samples: BTreeMap::new(),
            sample_index: 0,
            pending: BTreeSet::new(),
            directory_index: 0,
            directory_hash: String::new(),
        }
    }

    pub async fn run(
        &mut self,
        runtime: &StudioRuntime,
        inputs: &Inputs,
        manifest: &mut Manifest,
        scene: &Boundary,
    ) -> Result<()> {
        scene.check()?;
        anyhow::ensure!(
            scene
                .read(runtime.runtime_snapshot())
                .await?
                .startup_recovery
                .is_none(),
            "isolated startup reset configuration; refusing to submit a model task"
        );
        scene.check()?;
        let admitted = std::time::Instant::now();
        let project = runtime.open_project(&inputs.workspace).await;
        scene.returned("open_project", admitted, manifest);
        let project = project?;
        scene.check()?;
        let configured = runtime
            .read_settings()?
            .config
            .settings
            .mode_model_routes
            .into_iter()
            .find(|route| route.mode_id == inputs.mode)
            .context("configured builtin mode route unavailable")?;
        let mut route = pl_protocol::studio::NewThreadModelRoute {
            account_id: configured.account_id,
            model_id: configured.model_id,
            effort: Some(configured.effort).filter(|value| !value.trim().is_empty()),
        };
        if let Some(selected) = &inputs.route_override {
            route = selected.clone();
        }
        manifest.root_route = Some(route.clone());
        scene.check()?;
        let admitted = std::time::Instant::now();
        let created = runtime
            .create_thread_command(
                project.id,
                pl_protocol::studio::CreateThreadRequest {
                    title: Some("真实协作过程观察".into()),
                    input: pl_protocol::studio::StudioPromptInput {
                        input_id: format!("observation-{}", std::process::id()),
                        text: inputs.prompt.clone(),
                        attachment_draft_ids: vec![],
                    },
                    mode: inputs.mode.clone(),
                    route,
                    workspace_mode: inputs.workspace_mode,
                    delegation_mode: inputs.delegation_mode,
                    delegation_preference: inputs.delegation_preference,
                },
                None,
            )
            .await;
        scene.returned("create_thread", admitted, manifest);
        let created = created?;
        let root = created.thread;
        manifest.root = Some(root.clone().into());
        self.evidence.json("root-thread.json", &root.id, &root)?;
        scene.check()?;
        self.subscribe(runtime, &root.id, scene, manifest).await?;
        println!(
            "正在观察 {}；证据目录：{}。仅处理 decisions/ 内操作者明确提交的决议。",
            root.id,
            self.evidence.root().display()
        );
        loop {
            scene.check()?;
            self.evidence.check_disk_budget()?;
            anyhow::ensure!(
                !self.evidence.exhausted(),
                "evidence writer exhausted budget"
            );
            for writer in &self.writers {
                if let Some(error) = writer.failure()? {
                    anyhow::bail!("event writer {}: {error}", writer.thread_id);
                }
            }
            let state = scene.read(runtime.read_state()).await?;
            if !matches!(
                state.agent_directory.state,
                pl_protocol::ObservedResource::Ready(_)
            ) {
                self.evidence.json(
                    &format!("directory/unavailable-{:06}.json", self.directory_index),
                    "actual agentDirectory resource state",
                    &state.agent_directory,
                )?;
                self.directory_index += 1;
                manifest.unfinished = vec!["canonical agentDirectory is unavailable".into()];
                if matches!(
                    state.agent_directory.state,
                    pl_protocol::ObservedResource::Failed(_)
                        | pl_protocol::ObservedResource::Stopped(_)
                        | pl_protocol::ObservedResource::Stale(_)
                        | pl_protocol::ObservedResource::Degraded(_)
                ) {
                    manifest.termination = Termination::EvidenceIncomplete;
                    return Ok(());
                }
                wait_tick(scene).await?;
                continue;
            }
            let directory = state
                .agent_directory
                .state
                .value()
                .context("Ready directory has no value")?;
            let members: Vec<_> = directory
                .agents
                .iter()
                .filter(|agent| agent.root_thread_id == root.id)
                .cloned()
                .collect();
            self.evidence
                .check_limit(members.len() <= MAX_THREADS, "thread budget exceeded")?;
            let directory_hash = super::evidence::sha256(&serde_json::to_vec(&members)?);
            if self.directory_hash != directory_hash {
                self.evidence.json(
                    &format!("directory/{:06}.json", self.directory_index),
                    "canonical complete root membership",
                    &members,
                )?;
                self.directory_index += 1;
                manifest.members = members.iter().map(MemberIdentity::from).collect();
                self.directory_hash = directory_hash;
            }
            let mut unfinished = Vec::new();
            if !members.iter().any(|agent| agent.thread_id == root.id) {
                unfinished.push("root is absent from canonical agentDirectory".into());
            }
            let mut samples = BTreeMap::new();
            for agent in &members {
                if !self.threads.contains_key(&agent.thread_id) {
                    // Directory reservation precedes publication. Defer only a typed NotFound;
                    // permission/storage/protocol failures are not treated as child preparation.
                    match self
                        .subscribe(runtime, &agent.thread_id, scene, manifest)
                        .await
                    {
                        Ok(()) => (),
                        Err(error) if is_not_found(&error) => {
                            unfinished
                                .push(format!("{} reserved but not published", agent.thread_id));
                            continue;
                        }
                        Err(error) => return Err(error),
                    }
                }
                let sample = sample_member(runtime, agent, &root.id, scene).await?;
                self.sample(&sample.snapshot)?;
                self.write_pending(&sample.snapshot)?;
                unfinished.extend(sample.unfinished.iter().cloned());
                if agent.thread_id == root.id {
                    record_root_snapshot(manifest, &sample.snapshot);
                }
                samples.insert(agent.thread_id.clone(), sample);
            }
            self.decisions
                .process(runtime, &root.id, &self.evidence, scene, manifest)
                .await?;
            // A decision can admit work. Never conclude from the pre-decision snapshots this tick.
            if self.decisions.applied_this_tick() {
                unfinished.push("explicit decision applied; resample canonical state".into());
            }
            let workflow = samples
                .get(&root.id)
                .and_then(|sample| sample.snapshot.runtime.as_ref())
                .and_then(|runtime| runtime.workflow.as_ref())
                .and_then(|workflow| workflow.current_run.as_ref());
            manifest.unfinished = unfinished;
            scene.check()?;
            if inputs.mode == "mode.task" {
                match workflow {
                    Some(run)
                        if run.lifecycle == WorkflowRunLifecycle::Terminal
                            && run.current_state_id == "stopped" =>
                    {
                        manifest.termination = Termination::TaskStopped;
                        return Ok(());
                    }
                    Some(run)
                        if run.lifecycle == WorkflowRunLifecycle::Terminal
                            && run.current_state_id == "completed" =>
                    {
                        if manifest.unfinished.is_empty() {
                            let candidate = CompletionCandidate {
                                root: &root.id,
                                mode: &inputs.mode,
                                members: &members,
                                samples: &samples,
                                scene,
                            };
                            if let Some(termination) =
                                self.confirm_idle(runtime, candidate, manifest).await?
                            {
                                scene.check()?;
                                manifest.termination = termination;
                                return Ok(());
                            }
                        } else {
                            manifest.unfinished.push(
                                "Task workflow is terminal/completed; collector evidence remains incomplete".into(),
                            );
                        }
                    }
                    None => manifest
                        .unfinished
                        .push("Task workflow current_run is unavailable (not completion)".into()),
                    _ => manifest
                        .unfinished
                        .push("Task workflow is not terminal/completed".into()),
                }
            } else if manifest.unfinished.is_empty() {
                let candidate = CompletionCandidate {
                    root: &root.id,
                    mode: &inputs.mode,
                    members: &members,
                    samples: &samples,
                    scene,
                };
                if let Some(termination) = self.confirm_idle(runtime, candidate, manifest).await? {
                    scene.check()?;
                    manifest.termination = termination;
                    return Ok(());
                }
            }
            wait_tick(scene).await?;
        }
    }

    async fn confirm_idle(
        &mut self,
        runtime: &StudioRuntime,
        candidate: CompletionCandidate<'_>,
        manifest: &mut Manifest,
    ) -> Result<Option<Termination>> {
        for member in candidate.members {
            // This only cancels a projection-barrier waiter. The runtime retains the observation
            // workers and writer ownership; no decision, shutdown or owned handle is abandoned.
            candidate
                .scene
                .read(runtime.synchronize_thread_observation(&member.thread_id))
                .await?;
        }
        let Some(members) = current_members(runtime, candidate.root, candidate.scene).await? else {
            manifest.unfinished = vec!["agentDirectory is not Ready after synchronization".into()];
            return Ok(None);
        };
        if members != candidate.members {
            manifest.unfinished =
                vec!["canonical directory changed during synchronization; observe again".into()];
            return Ok(None);
        }
        let mut unfinished = Vec::new();
        let mut refreshed = BTreeMap::new();
        for member in &members {
            let sample = sample_member(runtime, member, candidate.root, candidate.scene).await?;
            self.sample(&sample.snapshot)?;
            self.write_pending(&sample.snapshot)?;
            if candidate
                .samples
                .get(&member.thread_id)
                .is_none_or(|before| {
                    before.snapshot != sample.snapshot || before.persistence != sample.persistence
                })
            {
                unfinished.push(format!(
                    "{} snapshot or terminal persistence proof changed during synchronization",
                    member.thread_id
                ));
            }
            unfinished.extend(sample.unfinished.iter().cloned());
            if member.thread_id == candidate.root {
                record_root_snapshot(manifest, &sample.snapshot);
            }
            refreshed.insert(member.thread_id.clone(), sample);
        }
        let completed = refreshed
            .get(candidate.root)
            .and_then(|sample| sample.snapshot.runtime.as_ref())
            .and_then(|runtime| runtime.workflow.as_ref())
            .and_then(|workflow| workflow.current_run.as_ref())
            .is_some_and(|run| {
                run.lifecycle == WorkflowRunLifecycle::Terminal
                    && run.current_state_id == "completed"
            });
        if candidate.mode == "mode.task" && !completed {
            unfinished
                .push("root workflow is no longer terminal/completed after synchronization".into());
        }
        if current_members(runtime, candidate.root, candidate.scene)
            .await?
            .as_deref()
            != Some(members.as_slice())
        {
            unfinished.push(
                "canonical directory changed while rechecking snapshots; observe again".into(),
            );
        }
        candidate.scene.check()?;
        manifest.unfinished = unfinished;
        if !manifest.unfinished.is_empty() {
            return Ok(None);
        }
        manifest.retired_owed_work = retired_owed_work(&members, &refreshed, candidate.root);
        #[derive(serde::Serialize)]
        #[serde(rename_all = "camelCase")]
        struct MemberComparison<'a> {
            before_synchronization: &'a MemberSample,
            after_synchronization: &'a MemberSample,
        }
        #[derive(serde::Serialize)]
        #[serde(rename_all = "camelCase")]
        struct CompletionObservation<'a> {
            root_thread_id: &'a str,
            members: &'a [StudioAgentDirectoryEntry],
            snapshot_revisions: BTreeMap<&'a str, u64>,
            member_proofs: BTreeMap<&'a str, MemberComparison<'a>>,
            atomic_snapshot: bool,
        }
        // Separate per-Thread barriers and repeated reads prove an observed quiet interval, never
        // a transaction over the whole tree. Content export still reports any later unknown facts.
        self.evidence.json(
            "completion-observed.json",
            candidate.root,
            &CompletionObservation {
                root_thread_id: candidate.root,
                members: &members,
                snapshot_revisions: refreshed
                    .iter()
                    .map(|(id, sample)| (id.as_str(), sample.snapshot.revision))
                    .collect(),
                member_proofs: refreshed
                    .iter()
                    .map(|(id, after)| {
                        Ok((
                            id.as_str(),
                            MemberComparison {
                                before_synchronization: candidate
                                    .samples
                                    .get(id)
                                    .context("missing candidate member")?,
                                after_synchronization: after,
                            },
                        ))
                    })
                    .collect::<Result<_>>()?,
                atomic_snapshot: false,
            },
        )?;
        candidate.scene.check()?;
        Ok(Some(if candidate.mode == "mode.task" {
            Termination::TaskCompletedObserved
        } else {
            Termination::SimpleTreeIdleObserved
        }))
    }

    async fn subscribe(
        &mut self,
        runtime: &StudioRuntime,
        id: &str,
        scene: &Boundary,
        manifest: &mut Manifest,
    ) -> Result<()> {
        self.evidence
            .check_limit(self.threads.len() < MAX_THREADS, "thread budget exceeded")?;
        scene.check()?;
        let admitted = std::time::Instant::now();
        let stream = runtime
            .subscribe_thread(pl_protocol::ThreadSubscriptionRequest {
                thread_id: id.into(),
            })
            .await;
        scene.returned("subscribe_thread", admitted, manifest);
        let stream = match stream {
            Ok(stream) => stream,
            Err(error) => {
                return Err(match scene.check() {
                    Err(stopped) => stopped.context(format!("subscription also failed: {error:#}")),
                    Ok(()) => error,
                });
            }
        };
        if let Err(error) = scene.check() {
            drop(stream);
            return Err(error);
        }
        let index = self.threads.len();
        let writer = EventWriter::start(stream, &self.evidence, id, index)?;
        self.threads.insert(id.into(), index);
        self.writers.push(writer);
        scene.check()?;
        Ok(())
    }

    fn sample(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        let hash = super::evidence::sha256(&serde_json::to_vec(snapshot)?);
        if self.samples.get(&snapshot.thread.id) != Some(&hash) {
            self.evidence.json(
                &format!("samples/{:06}.json", self.sample_index),
                &snapshot.thread.id,
                snapshot,
            )?;
            self.samples.insert(snapshot.thread.id.clone(), hash);
            self.sample_index += 1;
        }
        Ok(())
    }

    fn write_pending(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        for interaction in snapshot
            .interactions
            .iter()
            .filter(|interaction| interaction.status() == InteractionStatus::Pending)
        {
            if self
                .pending
                .insert((interaction.interaction_id.clone(), interaction.revision))
            {
                let name = format!(
                    "pending/{}-{}.json",
                    super::evidence::sha256(interaction.interaction_id.as_bytes()),
                    interaction.revision
                );
                // Includes scope, content, actual interaction revision and canonical full Plan.
                self.evidence
                    .json(&name, &interaction.interaction_id, snapshot)?;
                println!(
                    "待操作者决议：{}；快照：{}",
                    interaction.interaction_id,
                    self.evidence.root().join(name).display()
                );
            }
        }
        Ok(())
    }

    pub async fn finish_writers(
        &mut self,
        runtime: &StudioRuntime,
        manifest: &mut Manifest,
        cleanup: &Boundary,
    ) {
        for writer in self.writers.drain(..) {
            let id = writer.thread_id.clone();
            // Every indexed Thread completed subscription preparation before these read-only queries.
            let target = async {
                let page = cleanup
                    .read(runtime.list_thread_turns(&id, None, 1))
                    .await?;
                TurnAnchor::from_turn(
                    &page
                        .turns
                        .first()
                        .context("no durable terminal Turn anchor")?
                        .turn,
                )
            }
            .await;
            match writer.finish(target, cleanup).await {
                Ok(coverage) => {
                    if !coverage.complete {
                        manifest
                            .unfinished
                            .push(format!("{id} event interval unknown: {:?}", coverage.error));
                    }
                    manifest.events.push(coverage);
                }
                Err(error) => manifest
                    .issues
                    .push(format!("event writer {id}: {error:#}")),
            }
            manifest.writers_joined += 1;
        }
    }

    pub async fn export(
        &self,
        runtime: &StudioRuntime,
        manifest: &mut Manifest,
        cleanup: &Boundary,
    ) -> Result<()> {
        for (id, index) in &self.threads {
            if self.evidence.exhausted() || cleanup.check().is_err() {
                manifest.unfinished.push(format!(
                    "{id} final export prevented by evidence/cleanup budget"
                ));
                continue;
            }
            if let Err(error) =
                export::thread(runtime, &self.evidence, id, *index, manifest, cleanup).await
            {
                manifest
                    .issues
                    .push(format!("thread {id} final export: {error:#}"));
                manifest
                    .unfinished
                    .push(format!("{id} final export incomplete"));
            }
        }
        if let Some(workspace) = &manifest.workspace {
            super::git::capture_git(&self.evidence, workspace, "after", cleanup).await?;
        }
        self.evidence.check_disk_budget()
    }
}

fn is_not_found(error: &anyhow::Error) -> bool {
    error
        .downcast_ref::<pl_protocol::studio::StudioError>()
        .is_some_and(|error| error.code == pl_protocol::studio::StudioErrorCode::NotFound)
}

async fn current_members(
    runtime: &StudioRuntime,
    root: &str,
    scene: &Boundary,
) -> Result<Option<Vec<StudioAgentDirectoryEntry>>> {
    let state = scene.read(runtime.read_state()).await?;
    if !matches!(
        state.agent_directory.state,
        pl_protocol::ObservedResource::Ready(_)
    ) {
        return Ok(None);
    }
    Ok(state.agent_directory.state.value().map(|directory| {
        directory
            .agents
            .iter()
            .filter(|member| member.root_thread_id == root)
            .cloned()
            .collect()
    }))
}

fn retired_child(member: &StudioAgentDirectoryEntry, root: &str) -> bool {
    member.thread_id != root && matches!(member.state, pl_protocol::AgentState::Closed(_))
}

fn retired_owed_work(
    members: &[StudioAgentDirectoryEntry],
    samples: &BTreeMap<String, MemberSample>,
    root: &str,
) -> Vec<RetiredOwedWork> {
    members
        .iter()
        .filter(|member| retired_child(member, root))
        .filter_map(|member| {
            samples
                .get(&member.thread_id)?
                .snapshot
                .runtime
                .as_ref()?
                .continuation
                .clone()
                .map(|continuation| RetiredOwedWork {
                    thread_id: member.thread_id.clone(),
                    continuation,
                })
        })
        .collect()
}

async fn sample_member(
    runtime: &StudioRuntime,
    member: &StudioAgentDirectoryEntry,
    root: &str,
    scene: &Boundary,
) -> Result<MemberSample> {
    let snapshot = scene
        .read(runtime.thread_snapshot(&member.thread_id))
        .await?;
    let id = &snapshot.thread.id;
    anyhow::ensure!(
        id == &member.thread_id
            && snapshot.thread.root_thread_id == root
            && member.root_thread_id == root,
        "member snapshot identity/root mismatch"
    );
    let mut unfinished = Vec::new();
    if !member.state.is_settled()
        || member.execution.is_some()
        || member.can_stop
        || member.awaiting_scheduling
        || member.state.is_budget_paused()
    {
        unfinished.push(format!("{id} has unsettled directory execution/scheduling"));
    }
    let retired = retired_child(member, root);
    // Activity is projected from every Running task, including background calls of finished Turns.
    // Its absence is a snapshot fact, unlike a missing stream frame or a directory Idle label.
    if snapshot.active_turn.is_some()
        || snapshot.activity.is_some()
        || snapshot
            .interactions
            .iter()
            .any(|interaction| interaction.status() == InteractionStatus::Pending)
    {
        unfinished.push(format!("{id} has active Turn/activity/pending interaction"));
    }
    match &snapshot.runtime {
        Some(runtime)
            if runtime.execution.is_none() && (retired || runtime.continuation.is_none()) => {}
        Some(_) => unfinished.push(format!("{id} has execution or continuation")),
        None => unfinished.push(format!("{id} runtime projection unavailable")),
    }
    let live_watermarks = snapshot.storage.as_ref().and_then(|storage| {
        match (storage.accepted_sequence, storage.durable_sequence) {
            (Some(accepted), Some(durable))
                if storage.fault.is_none()
                    && !storage.pressure_paused
                    && !storage.resume_required
                    && durable >= accepted =>
            {
                Some((accepted, durable))
            }
            _ => None,
        }
    });
    // Missing storage is not owner absence. Only this closed, idle non-root may instead
    // prove persisted terminal history through the public checkpoint-gated query.
    let closed_history = snapshot.storage.is_none()
        && retired
        && snapshot.thread.status == pl_protocol::ThreadStatus::Closed
        && unfinished.is_empty();
    if live_watermarks.is_none() && !closed_history {
        unfinished.push(format!(
            "{id} storage watermark missing, pending or faulted"
        ));
    }
    let mut persistence = None;
    if unfinished.is_empty() {
        match scene.read(runtime.list_thread_turns(id, None, 1)).await {
            Ok(page) => match page.turns.first() {
                Some(history) => {
                    anyhow::ensure!(
                        history.turn.thread_id == *id,
                        "history Turn belongs to another Thread"
                    );
                    if history.turn.state.is_terminal() {
                        let terminal = TurnAnchor::from_turn(&history.turn)?;
                        persistence = Some(match live_watermarks {
                            Some((accepted_sequence, durable_sequence)) => PersistenceProof::Live {
                                accepted_sequence,
                                durable_sequence,
                                terminal,
                            },
                            None => PersistenceProof::ClosedHistory {
                                history_checkpoint_validated: true,
                                terminal,
                            },
                        });
                    } else {
                        unfinished.push(format!("{id} latest durable Turn is nonterminal"));
                    }
                }
                None => unfinished.push(format!("{id} latest durable Turn is missing")),
            },
            Err(error)
                if error
                    .downcast_ref::<pl_protocol::studio::StudioError>()
                    .is_some_and(|error| {
                        error.code == pl_protocol::studio::StudioErrorCode::Busy
                    }) =>
            {
                unfinished.push(format!("{id} history checkpoint pending (Busy): {error:#}"));
            }
            Err(error) => return Err(error).context(format!("validate terminal history for {id}")),
        }
    }
    Ok(MemberSample {
        snapshot,
        persistence,
        unfinished,
    })
}

fn record_root_snapshot(manifest: &mut Manifest, snapshot: &ThreadSnapshot) {
    manifest.root_model_route = snapshot
        .runtime
        .as_ref()
        .and_then(|runtime| runtime.model_route.clone());
    manifest.root_workflow = snapshot
        .runtime
        .as_ref()
        .and_then(|runtime| runtime.workflow.clone());
    manifest.root_workflow_snapshot_revision = Some(snapshot.revision);
}

async fn wait_tick(scene: &Boundary) -> Result<()> {
    scene
        .read(async {
            tokio::time::sleep(Duration::from_millis(500)).await;
            Ok(())
        })
        .await
}
