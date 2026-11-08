use super::super::*;
use super::record;
use pl_provider_fixture::{
    FixtureOptions, GUI_TIMELINE_HISTORY_20K_REQUEST_BODY_BYTES,
    GUI_TIMELINE_HISTORY_20K_SEED_BATCHES, GUI_TIMELINE_HISTORY_20K_SEED_ITEMS,
    gui_timeline_history_20k_seed_prompt, gui_timeline_history_20k_seed_script,
};
use serde_json::json;
use std::collections::BTreeSet;
use std::future::Future;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Inventory {
    pub project_id: Option<String>,
    pub thread_id: Option<String>,
    pub main_items: Option<usize>,
    batches: Vec<BatchReceipt>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BatchReceipt {
    input_id: String,
    turn_id: String,
    target_sequence: Option<u64>,
    history_admitted_sequence: Option<u64>,
    history_durable_sequence: Option<u64>,
    state_durable_revision: Option<u64>,
    completed: bool,
}

pub(super) fn run(
    context: &ConversationReadWorkScenario<'_>,
    inventories: &mut Vec<Inventory>,
) -> Result<()> {
    let executor = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    executor.block_on(Box::pin(async {
        let project = context.working.join("conversation-read-profile-project");
        init_git_project(&project)?;
        for index in 0..2 {
            checkpoint(context.interrupt)?;
            let mut inventory = Inventory {
                project_id: None,
                thread_id: None,
                main_items: None,
                batches: Vec::with_capacity(GUI_TIMELINE_HISTORY_20K_SEED_BATCHES),
            };
            let result = Box::pin(write_one(context, &project, index, &mut inventory)).await;
            inventories.push(inventory);
            result?;
        }
        // Both real writers and both fixture listeners are closed before the
        // preparation/read audit opens a fresh runtime on the saved home.
        let runtime = Box::pin(StudioRuntime::initialize(runtime_options(context.home))).await?;
        let mut errors = Vec::new();
        for inventory in inventories.iter_mut() {
            let counted = match inventory.thread_id.as_deref() {
                Some(id) => Box::pin(count(&runtime, id, context.interrupt)).await,
                None => Err(anyhow::anyhow!("seed has no Thread identity")),
            };
            inventory.main_items = record(&mut errors, "Main inventory", counted);
            if inventory.main_items.is_some_and(|count| {
                count < GUI_TIMELINE_HISTORY_20K_SEED_BATCHES * GUI_TIMELINE_HISTORY_20K_SEED_ITEMS
            }) {
                errors.push(format!(
                    "{:?} has fewer than 20,000 Main items",
                    inventory.thread_id
                ));
            }
        }
        record(
            &mut errors,
            "audit runtime shutdown",
            runtime.shutdown_runtime().await,
        );
        ensure!(errors.is_empty(), "{}", errors.join("\n"));
        Ok(())
    }))
}

async fn write_one(
    context: &ConversationReadWorkScenario<'_>,
    project: &Path,
    index: usize,
    inventory: &mut Inventory,
) -> Result<()> {
    let fixture = FixtureServer::start_with_options(
        gui_timeline_history_20k_seed_script(),
        FixtureOptions {
            request_body_limit: Some(GUI_TIMELINE_HISTORY_20K_REQUEST_BODY_BYTES),
            ..FixtureOptions::default()
        },
    )
    .await?;
    let mut errors = Vec::new();
    let write = Box::pin(async {
        write_seed_config(context.home, &fixture.base_url())?;
        let runtime = Box::pin(StudioRuntime::initialize(runtime_options(context.home))).await?;
        let result = Box::pin(seed_batches(
            &runtime,
            project,
            index,
            context.interrupt,
            inventory,
        ))
        .await;
        let mut runtime_errors = Vec::new();
        let id = record(&mut runtime_errors, "seed batches", result);
        record(
            &mut runtime_errors,
            "seed runtime shutdown",
            runtime.shutdown_runtime().await,
        );
        ensure!(runtime_errors.is_empty(), "{}", runtime_errors.join("\n"));
        id.context("seed produced no Thread")
    })
    .await;
    let id = record(&mut errors, "seed", write);
    // shutdown + verify is finish's exact public implementation, while retaining
    // the partial strict-match evidence even when seeding failed.
    if let Some(report) = record(
        &mut errors,
        "fixture shutdown/join",
        fixture.shutdown().await,
    ) {
        record(
            &mut errors,
            "fixture evidence",
            serde_json::to_vec_pretty(&json!({
                "consumedSteps": report.consumed_steps,
                "expectedSteps": report.expected_steps,
                "remainingOptional": report.remaining_optional,
                "requests": &report.requests,
            }))
            .context("encode fixture evidence")
            .and_then(|bytes| {
                fs::write(
                    context
                        .output
                        .join(format!("profile-seed-{index}-fixture.json")),
                    bytes,
                )
                .context("save fixture evidence")
            }),
        );
        record(&mut errors, "fixture script verification", report.verify());
    }
    ensure!(errors.is_empty(), "{}", errors.join("\n"));
    id.context("seed produced no Thread")?;
    Ok(())
}

async fn seed_batches(
    runtime: &StudioRuntime,
    project: &Path,
    index: usize,
    interrupt: &mpsc::Receiver<()>,
    inventory: &mut Inventory,
) -> Result<String> {
    let workspace = runtime.open_project(project).await?;
    inventory.project_id = Some(workspace.id.clone());
    let input_id = |batch| format!("profile-read-{index}-{batch:02}");
    let created = runtime
        .create_thread_command(
            workspace.id,
            CreateThreadRequest {
                title: Some(format!("conversation-read-profile-{index}")),
                input: StudioPromptInput {
                    input_id: input_id(1),
                    text: gui_timeline_history_20k_seed_prompt(1),
                    attachment_draft_ids: Vec::new(),
                },
                mode: pl_protocol::ThreadModeId::simple().label().into(),
                route: NewThreadModelRoute {
                    account_id: ACCOUNT.into(),
                    model_id: MODEL.into(),
                    effort: None,
                },
                delegation_mode: None,
                delegation_preference: None,
                workspace_mode: ThreadWorkspaceMode::Local,
            },
            None,
        )
        .await?;
    let id = created.thread.id;
    inventory.thread_id = Some(id.clone());
    let mut subscription = runtime
        .subscribe_thread(ThreadSubscriptionRequest {
            thread_id: id.clone(),
        })
        .await?;
    // One State baseline belongs to this subscription, not to each seeded Turn.
    let mut saw_snapshot = false;
    let mut revision = completed(
        runtime,
        &mut subscription,
        &mut saw_snapshot,
        &id,
        &input_id(1),
        interrupt,
        &mut inventory.batches,
    )
    .await?;
    for batch in 2..=GUI_TIMELINE_HISTORY_20K_SEED_BATCHES {
        checkpoint(interrupt)?;
        runtime
            .submit_prompt_command(
                id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: input_id(batch),
                        text: gui_timeline_history_20k_seed_prompt(batch),
                        attachment_draft_ids: Vec::new(),
                    },
                    expected_model_route_revision: revision,
                },
            )
            .await?;
        revision = completed(
            runtime,
            &mut subscription,
            &mut saw_snapshot,
            &id,
            &input_id(batch),
            interrupt,
            &mut inventory.batches,
        )
        .await?;
    }
    Ok(id)
}

async fn completed(
    runtime: &StudioRuntime,
    subscription: &mut StudioThreadSubscription,
    saw_snapshot: &mut bool,
    thread_id: &str,
    input_id: &str,
    interrupt: &mpsc::Receiver<()>,
    batches: &mut Vec<BatchReceipt>,
) -> Result<u64> {
    // Seed work is excluded from performance samples. Keep cancellation live
    // while a large batch is processed rather than treating a timer as progress.
    cancellable(interrupt, async {
        ensure!(
            batches.len() < GUI_TIMELINE_HISTORY_20K_SEED_BATCHES,
            "seed batch evidence exceeded the required batch count"
        );
        let turn_id = loop {
            let update = subscription.recv().await?;
            let Some(update) = update else {
                bail!("seed Thread stream ended");
            };
            match update {
                ThreadSubscriptionUpdate::Snapshot {
                    completed_history_version,
                    ..
                } => {
                    ensure!(
                        !*saw_snapshot,
                        "seed subscription repeated its initial State snapshot"
                    );
                    ensure!(
                        completed_history_version == pl_protocol::COMPLETED_HISTORY_VERSION,
                        "unsupported completed history version {completed_history_version}"
                    );
                    *saw_snapshot = true;
                }
                ThreadSubscriptionUpdate::Notification { notification } => {
                    ensure!(
                        *saw_snapshot,
                        "seed notification arrived before State snapshot"
                    );
                    if let ThreadNotification::TurnCompleted { turn } = notification.notification
                        && turn.input_id.as_deref() == Some(input_id)
                    {
                        ensure!(
                            matches!(turn.state, pl_protocol::TurnState::Completed(_)),
                            "seed Turn failed: {:?}",
                            turn.state
                        );
                        break turn.id;
                    }
                }
            }
        };
        // Retain the successful Turn even if the snapshot or save wait fails.
        let receipt_index = batches.len();
        batches.push(BatchReceipt {
            input_id: input_id.to_owned(),
            turn_id,
            target_sequence: None,
            history_admitted_sequence: None,
            history_durable_sequence: None,
            state_durable_revision: None,
            completed: false,
        });
        let receipt = &mut batches[receipt_index];
        let (target_sequence, revision) = {
            let snapshot = runtime.thread_snapshot(thread_id).await?;
            ensure!(
                snapshot.schema_version == pl_protocol::THREAD_SCHEMA_VERSION
                    && snapshot.thread.id == thread_id,
                "seed snapshot schema/Thread identity mismatch: schema={} thread={}",
                snapshot.schema_version,
                snapshot.thread.id
            );
            ensure!(
                snapshot.revision != 0,
                "seed snapshot has no commit revision"
            );
            receipt.target_sequence = Some(snapshot.revision);
            let revision = snapshot
                .model_route
                .map(|route| route.revision)
                .context("seed has no model route")?;
            (snapshot.revision, revision)
        };
        loop {
            let saved = {
                let persistence = runtime.persistence_queue_snapshot();
                let thread = persistence
                    .threads
                    .iter()
                    .find(|thread| thread.thread_id == thread_id)
                    .with_context(|| format!("seed persistence has no Thread {thread_id}"))?;
                receipt.history_admitted_sequence = thread.history_admitted_sequence;
                receipt.history_durable_sequence = thread.history_durable_sequence;
                receipt.state_durable_revision = thread.state_durable_revision;
                ensure!(
                    thread.fault.is_none() && thread.last_error.is_none(),
                    "seed Thread persistence fault: {:?}; last error: {:?}",
                    thread.fault,
                    thread.last_error
                );
                thread
                    .history_admitted_sequence
                    .is_some_and(|sequence| sequence >= target_sequence)
                    && thread
                        .history_durable_sequence
                        .is_some_and(|sequence| sequence >= target_sequence)
                    && thread
                        .state_durable_revision
                        .is_some_and(|revision| revision >= target_sequence)
            };
            if saved {
                receipt.completed = true;
                return Ok(revision);
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .with_context(|| format!("seed batch {input_id}"))
}

async fn count(
    runtime: &StudioRuntime,
    thread_id: &str,
    interrupt: &mpsc::Receiver<()>,
) -> Result<usize> {
    let demand = ReadDemand {
        max_items: 128,
        max_bytes: CHAT_BATCH_MAX_BYTES.min(64 * 1024),
    };
    let mut feed = cancellable(
        interrupt,
        runtime.open_conversation_feed(thread_id, ChatScope::Main, demand),
    )
    .await?;
    let result = cancellable(interrupt, async {
        let mut batch = loop {
            match feed.recv().await? {
                Some(ConversationEvent::Chat { batch })
                    if batch.placement == ChatPlacement::Set =>
                {
                    break *batch;
                }
                Some(_) => {}
                None => bail!("inventory feed ended before Set"),
            }
        };
        let reader = feed.reader().clone();
        let mut total = 0usize;
        let mut seen = BTreeSet::new();
        loop {
            checkpoint(interrupt)?;
            batch.validate_for(&ChatScope::Main)?;
            total = total
                .checked_add(batch.entries.len())
                .context("Main count overflow")?;
            let Some(before) = batch.before else {
                break;
            };
            ensure!(
                seen.insert(before.clone()),
                "Main inventory cursor repeated"
            );
            batch = reader.load_older(&before, demand).await?;
        }
        Ok(total)
    })
    .await;
    let mut errors = Vec::new();
    let total = record(&mut errors, "Main inventory read", result);
    record(&mut errors, "Main inventory feed close", feed.close().await);
    ensure!(errors.is_empty(), "{}", errors.join("\n"));
    total.context("missing Main inventory")
}

fn checkpoint(interrupt: &mpsc::Receiver<()>) -> Result<()> {
    ensure!(
        interrupt.try_recv().is_err(),
        "Profile seed/audit cancelled"
    );
    Ok(())
}

/// Keep one operation future alive across cancellation checks. Recreating
/// `recv()` on every timer tick could drop an in-progress subscription update.
async fn cancellable<T>(
    interrupt: &mpsc::Receiver<()>,
    work: impl Future<Output = Result<T>>,
) -> Result<T> {
    tokio::time::timeout(Duration::from_secs(900), async {
        tokio::pin!(work);
        loop {
            checkpoint(interrupt)?;
            tokio::select! {
                result = &mut work => return result,
                _ = tokio::time::sleep(Duration::from_millis(100)) => {}
            }
        }
    })
    .await
    .context("Profile seed/audit operation timed out")?
}
