use super::super::*;
use super::{record, require_stopped, wait_initial_turn, wait_notified_turn};
use pl_provider_fixture::{
    FixtureOptions, GUI_TIMELINE_HISTORY_20K_REQUEST_BODY_BYTES,
    GUI_TIMELINE_READ_PROFILE_MODEL_TEXT_ITEMS, GUI_TIMELINE_READ_PROFILE_SEED_BATCHES,
    gui_timeline_read_profile_seed_prompt, gui_timeline_read_profile_seed_script,
};
use pl_studio_runtime::history::{HISTORY_PROTOCOL_VERSION, HistoryDemand, HistoryRowHead};
use pl_studio_runtime::{ChatAtomKind, ChatSourceId, mode::ThreadModeId};
use serde_json::json;
use std::collections::BTreeSet;
use std::future::Future;

#[derive(Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Inventory {
    pub project_id: Option<String>,
    pub thread_id: Option<String>,
    pub main_items: Option<usize>,
    model_text_items: Option<usize>,
    normal_input_turns: Option<usize>,
    batches: Vec<BatchReceipt>,
}

struct MainInventory {
    main_items: usize,
    model_text_items: usize,
    normal_input_turns: usize,
}

#[derive(Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct BatchReceipt {
    input_id: String,
    turn_id: String,
    snapshot_revision: Option<u64>,
    history_admitted_sequence: Option<u64>,
    history_durable_sequence: Option<u64>,
    current_saved_revision: Option<u64>,
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
        if let Some(source) = context.profile_read_seed {
            let report = super::read_json(&source.join("profile-read-report.json"))?;
            *inventories = serde_json::from_value(report["seed"].clone())?;
            ensure!(inventories.len() == 2, "Profile seed requires two Threads");
            for inventory in inventories.iter() {
                ensure!(
                    inventory.batches.len() == GUI_TIMELINE_READ_PROFILE_SEED_BATCHES
                        && inventory.batches.iter().all(|batch| batch.completed),
                    "Profile seed has incomplete normal input turns"
                );
            }
            let retained = super::read_json(&source.join("retained-environment.json"))?;
            let home = retained["home"]
                .as_str()
                .context("Profile seed home missing")?;
            // The supplied synthetic home is closed. WAL may persist after
            // closure and is part of the database, so preserve it in the copy.
            copy_startup_evidence(Path::new(home), context.home)?;
        } else {
            let project = context.working.join("conversation-read-profile-project");
            init_git_project(&project)?;
            for index in 0..2 {
                checkpoint(context.interrupt)?;
                let mut inventory = Inventory {
                    project_id: None,
                    thread_id: None,
                    main_items: None,
                    model_text_items: None,
                    normal_input_turns: None,
                    batches: Vec::with_capacity(GUI_TIMELINE_READ_PROFILE_SEED_BATCHES),
                };
                let result = Box::pin(write_one(context, &project, index, &mut inventory)).await;
                inventories.push(inventory);
                result?;
            }
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
            if let Some(counts) = record(&mut errors, "Main inventory", counted) {
                inventory.main_items = Some(counts.main_items);
                inventory.model_text_items = Some(counts.model_text_items);
                inventory.normal_input_turns = Some(counts.normal_input_turns);
                if counts.model_text_items != GUI_TIMELINE_READ_PROFILE_MODEL_TEXT_ITEMS {
                    errors.push(format!(
                        "{:?} has {} model text items, expected {}",
                        inventory.thread_id,
                        counts.model_text_items,
                        GUI_TIMELINE_READ_PROFILE_MODEL_TEXT_ITEMS
                    ));
                }
                if counts.normal_input_turns != GUI_TIMELINE_READ_PROFILE_SEED_BATCHES {
                    errors.push(format!(
                        "{:?} has {} normal input turns, expected {}",
                        inventory.thread_id,
                        counts.normal_input_turns,
                        GUI_TIMELINE_READ_PROFILE_SEED_BATCHES
                    ));
                }
            }
            if inventory.main_items.is_some_and(|count| count <= 40) {
                errors.push(format!(
                    "{:?} has too few Main rows to exercise bounded pagination",
                    inventory.thread_id
                ));
            }
        }
        record(
            &mut errors,
            "audit runtime shutdown",
            runtime.shutdown_runtime().await.and_then(require_stopped),
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
        gui_timeline_read_profile_seed_script(),
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
            runtime.shutdown_runtime().await.and_then(require_stopped),
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
                    text: gui_timeline_read_profile_seed_prompt(1),
                    attachment_draft_ids: Vec::new(),
                },
                mode: ThreadModeId::simple().label().into(),
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
    let demand = current_demand();
    let current = runtime
        .open_current_reader(&id, pl_studio_runtime::CURRENT_PROTOCOL_VERSION, demand)
        .await?;
    let mut watch = match current.watch(None, demand).await {
        Ok(watch) => watch,
        Err(error) => {
            return match current.close().await {
                Ok(()) => Err(error),
                Err(close_error) => {
                    Err(error.context(format!("Current close also failed: {close_error:#}")))
                }
            };
        }
    };
    let mut saw_baseline = false;
    let first_input = input_id(1);
    let outcome: Result<()> = async {
        let first = Box::pin(wait_initial_turn(
            runtime,
            &current,
            &mut watch,
            &mut saw_baseline,
            &id,
            first_input.as_str(),
        ))
        .await?;
        let mut revision = first.route_revision;
        persist_completed_batch(
            runtime,
            &id,
            first.turn_id,
            first.snapshot_revision,
            &first_input,
            interrupt,
            &mut inventory.batches,
        )
        .await?;
        for batch in 2..=GUI_TIMELINE_READ_PROFILE_SEED_BATCHES {
            checkpoint(interrupt)?;
            runtime
                .submit_prompt_command(
                    id.clone(),
                    SubmitPromptRequest {
                        input: StudioPromptInput {
                            input_id: input_id(batch),
                            text: gui_timeline_read_profile_seed_prompt(batch),
                            attachment_draft_ids: Vec::new(),
                        },
                        expected_model_route_revision: revision,
                    },
                )
                .await?;
            let current_input = input_id(batch);
            let observed = Box::pin(wait_notified_turn(
                &current,
                &mut watch,
                &mut saw_baseline,
                &id,
                current_input.as_str(),
            ))
            .await?;
            revision = observed.route_revision;
            persist_completed_batch(
                runtime,
                &id,
                observed.turn_id,
                observed.snapshot_revision,
                &current_input,
                interrupt,
                &mut inventory.batches,
            )
            .await?;
        }
        Ok(())
    }
    .await;
    let closed_watch = watch.close().await;
    let closed_current = current.close().await;
    let mut close_errors = Vec::new();
    if let Err(error) = closed_watch {
        close_errors.push(format!("watch: {error:#}"));
    }
    if let Err(error) = closed_current {
        close_errors.push(format!("reader: {error:#}"));
    }
    match outcome {
        Ok(()) if close_errors.is_empty() => Ok(id),
        Err(error) => {
            let mut message = format!("{error:#}");
            if !close_errors.is_empty() {
                message.push_str(&format!(
                    "; Current close also failed: {}",
                    close_errors.join("; ")
                ));
            }
            Err(anyhow::anyhow!(message))
        }
        Ok(()) => Err(anyhow::anyhow!(
            "Current close failed: {}",
            close_errors.join("; ")
        )),
    }
}

async fn persist_completed_batch(
    runtime: &StudioRuntime,
    thread_id: &str,
    turn_id: String,
    snapshot_revision: u64,
    input_id: &str,
    interrupt: &mpsc::Receiver<()>,
    batches: &mut Vec<BatchReceipt>,
) -> Result<()> {
    // Seed work is excluded from performance samples. Keep cancellation live
    // while a large batch is processed rather than treating a timer as progress.
    cancellable(interrupt, async {
        ensure!(
            batches.len() < GUI_TIMELINE_READ_PROFILE_SEED_BATCHES,
            "seed batch evidence exceeded the required batch count"
        );
        // Retain the successful Turn even if the snapshot or save wait fails.
        let receipt_index = batches.len();
        batches.push(BatchReceipt {
            input_id: input_id.to_owned(),
            turn_id,
            snapshot_revision: None,
            history_admitted_sequence: None,
            history_durable_sequence: None,
            current_saved_revision: None,
            completed: false,
        });
        let receipt = &mut batches[receipt_index];
        ensure!(snapshot_revision != 0, "seed Current has no revision");
        receipt.snapshot_revision = Some(snapshot_revision);
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
                receipt.current_saved_revision = thread
                    .current
                    .as_ref()
                    .and_then(|current| current.saved_revision);
                ensure!(
                    thread.fault.is_none() && thread.last_error.is_none(),
                    "seed Thread persistence fault: {:?}; last error: {:?}",
                    thread.fault,
                    thread.last_error
                );
                // This per-batch fence is History-only. The independent Current writer is joined
                // and its complete final file is saved by shutdown before the subsequent audit.
                persistence.pending_bytes == 0
                    && persistence.in_flight_bytes == 0
                    && persistence.last_error.is_none()
                    && thread.pending_bytes == 0
                    && thread.in_flight_bytes == 0
                    && thread
                        .history_admitted_sequence
                        .zip(thread.history_durable_sequence)
                        .is_some_and(|(admitted, durable)| durable >= admitted)
            };
            if saved {
                receipt.completed = true;
                return Ok(());
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
) -> Result<MainInventory> {
    let demand = HistoryDemand {
        max_rows: 128,
        max_bytes: CHAT_BATCH_MAX_BYTES.min(64 * 1024),
    };
    let reader = cancellable(
        interrupt,
        runtime.open_history_reader(thread_id, HISTORY_PROTOCOL_VERSION),
    )
    .await?;
    let result = cancellable(interrupt, async {
        let mut inventory = InventoryScan::default();
        let mut cut = None;
        let mut cursor = None;
        loop {
            checkpoint(interrupt)?;
            let page = reader
                .timeline_page(cut.clone(), cursor.clone(), demand)
                .await?;
            for entry in &page.entries {
                count_head(&reader, &page.cut, entry, demand, &mut inventory, interrupt).await?;
            }
            let Some(next) = page.next else {
                break;
            };
            ensure!(
                cursor.as_deref() != Some(next.as_str()),
                "Main inventory cursor repeated"
            );
            cut = Some(page.cut);
            cursor = Some(next);
        }
        Ok(MainInventory {
            main_items: inventory.main_items,
            model_text_items: inventory.model_text_items,
            normal_input_turns: inventory.inputs.len(),
        })
    })
    .await;
    let mut errors = Vec::new();
    let total = record(&mut errors, "Main inventory read", result);
    reader.close().await;
    ensure!(errors.is_empty(), "{}", errors.join("\n"));
    total.context("missing Main inventory")
}

#[derive(Default)]
struct InventoryScan {
    main_items: usize,
    model_text_items: usize,
    inputs: BTreeSet<String>,
    groups: BTreeSet<String>,
}

async fn count_head(
    reader: &pl_studio_runtime::history::HistoryReader,
    cut: &pl_studio_runtime::history::HistoryCut,
    entry: &pl_studio_runtime::history::HistoryTimelineEntry,
    demand: HistoryDemand,
    inventory: &mut InventoryScan,
    interrupt: &mpsc::Receiver<()>,
) -> Result<()> {
    match &entry.head {
        HistoryRowHead::Single(head) => {
            inventory.main_items = inventory
                .main_items
                .checked_add(1)
                .context("Main count overflow")?;
            count_entity(head, inventory);
        }
        HistoryRowHead::Work(head) => {
            ensure!(
                inventory.groups.insert(head.group_id.clone()),
                "Main inventory repeated Work {}",
                head.group_id
            );
            inventory.main_items = inventory
                .main_items
                .checked_add(1)
                .context("Main count overflow")?;
            let mut group_cut = Some(cut.clone());
            let mut cursor = None;
            loop {
                checkpoint(interrupt)?;
                let page = reader
                    .group_page(
                        head.group_id.clone(),
                        group_cut.clone(),
                        cursor.clone(),
                        demand,
                    )
                    .await?;
                for member in &page.members {
                    let HistoryRowHead::Member(head) = &member.head else {
                        bail!("group page contained a non-member head");
                    };
                    count_entity(head, inventory);
                }
                let Some(next) = page.next else {
                    break;
                };
                ensure!(
                    cursor.as_deref() != Some(next.as_str()),
                    "member continuation did not advance"
                );
                group_cut = Some(page.cut);
                cursor = Some(next);
            }
        }
        _ => {
            bail!("timeline page contained a non-Main head");
        }
    }
    Ok(())
}

fn count_entity(
    head: &pl_studio_runtime::history::HistoryEntityHead,
    inventory: &mut InventoryScan,
) {
    match (&head.kind, &head.source) {
        (ChatAtomKind::Text, ChatSourceId::ForegroundTurn { .. }) => {
            inventory.model_text_items += 1;
        }
        (ChatAtomKind::Input, ChatSourceId::Input { input_id }) => {
            inventory.inputs.insert(input_id.clone());
        }
        _ => {}
    }
}

fn current_demand() -> ReadDemand {
    ReadDemand {
        max_items: 128,
        max_bytes: CHAT_BATCH_MAX_BYTES.min(64 * 1024),
    }
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
