//! Official, ordered history migrations. Format numbers are only legacy import markers.
use super::*;
mod atom_metadata;
mod background_results;
pub(super) mod completion_boundary;
mod conversion;
mod demand_conversation;
mod display_block_order;
pub(in crate::studio::storage::history) mod immutable_completion_runs;
pub(in crate::studio::storage::history) mod legacy_completion_projection;
mod legacy_completion_types;
pub(in crate::studio::storage::history) mod legacy_content;
pub(in crate::studio::storage::history) mod legacy_current;
pub(in crate::studio::storage::history) mod legacy_timeline_projection;
mod legacy_timeline_store;
pub(in crate::studio::storage::history) mod legacy_timeline_types;
mod member_read_metadata;
mod model_route_head;
mod source_classification;
mod sqlite_metadata;
mod timeline_background_tail;
mod timeline_items;
mod timeline_thinking_summary;
pub(in crate::studio::storage::history) mod work_snapshots;
use conversion::{
    backfill_legacy_hidden_inputs, backfill_tool_user_input, migrate_context_sources,
    migrate_unconsumed_input_bindings,
};
#[cfg(test)]
pub(super) use demand_conversation::seed_current;
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

/// Frozen pre-head fixture encoder, not an alternate production checkpoint writer.
#[cfg(test)]
async fn write_published_checkpoint(
    db: &impl ConnectionTrait,
    checkpoint: &pl_core::thread::ThreadCheckpoint,
) -> Result<()> {
    use pl_core::context::content_hash;
    for (ordinal, record) in checkpoint.state.context.records.iter().enumerate() {
        let payload = serde_json::to_string(record)?;
        db.execute_raw(statement(
            "INSERT INTO current_context(ordinal,record_id,payload,payload_hash) VALUES(?,?,?,?)",
            vec![
                integer(ordinal)?.into(),
                record.id.clone().into(),
                payload.clone().into(),
                content_hash(payload.as_bytes()).into(),
            ],
        ))
        .await?;
    }
    let mut metadata = checkpoint.pruned()?;
    metadata.state.context.records = Default::default();
    let payload = serde_json::to_string(&metadata)?;
    db.execute_raw(statement(
        "INSERT INTO session_checkpoint(id,revision,context_revision,context_count,payload,payload_hash)
         VALUES(1,?,?,?,?,?)",
        vec![
            integer(checkpoint.state_revision)?.into(),
            integer(checkpoint.state.context.revision)?.into(),
            integer(checkpoint.state.context.records.len())?.into(),
            payload.clone().into(),
            content_hash(payload.as_bytes()).into(),
        ],
    ))
    .await?;
    Ok(())
}

const DISPLAY_BLOCK_ORDER: &str = "m20261113_000002_display_block_order";
const WORK_SNAPSHOTS: &str = "m20261113_000001_work_snapshots";

struct Migrator {
    thread_id: String,
    bot_root: Option<crate::studio::startup::storage_layout::bot_roots::BotRootMove>,
    // Immutable recovery candidates are shared by the migrator's repeated pending-step queries.
    // An inline pair also bloats content-only preparation, even when this option is None.
    execution_identity: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
}

impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(CreateHistory {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(InputPresentation),
            Box::new(InputBindings),
            Box::new(ContextSources {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ToolAnswers {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(CheckpointV5 {
                thread_id: self.thread_id.clone(),
            }),
            // This content-only step precedes the lifecycle-gated recovery steps. SeaORM
            // preserves vector order and skips applied names, including on fully recovered v8 DBs.
            Box::new(RetireOrdinals),
            // Published v8/v9 databases may still have a schema-5 checkpoint even when the
            // original checkpoint step is applied. Upgrade it before any current-only reader.
            Box::new(MeteringFacts {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ProducerPayloads {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ReviewReceipt {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(AtomicTimeline {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(CombinedContent {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(demand_conversation::DemandConversation {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(model_route_head::RootModelRouteHead {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(atom_metadata::AtomMetadata),
            Box::new(member_read_metadata::MemberReadMetadata),
            Box::new(background_results::BackgroundResults),
            Box::new(timeline_items::TimelineItems),
            Box::new(timeline_thinking_summary::TimelineThinkingSummary),
            Box::new(source_classification::SourceClassification),
            Box::new(timeline_background_tail::TimelineBackgroundTail),
            Box::new(completion_boundary::CompletionBoundary),
            Box::new(immutable_completion_runs::ImmutableCompletionRuns),
            Box::new(work_snapshots::LegacyDisplayMarker(
                "m20261109_000001_display_snapshots",
            )),
            Box::new(work_snapshots::LegacyDisplayMarker(
                "m20261111_000001_display_observations",
            )),
            Box::new(work_snapshots::LegacyDisplayMarker(
                "m20261112_000001_history_tool_work",
            )),
            Box::new(work_snapshots::LegacyDisplayMarker(
                "m20261112_000001_visible_tail_workgroups",
            )),
            Box::new(work_snapshots::WorkSnapshots),
            Box::new(display_block_order::DisplayBlockOrder),
            Box::new(ProjectKind {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ModelAccess {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(WorkspaceReceipt {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(BotRootRelocation {
                thread_id: self.thread_id.clone(),
                mapping: self.bot_root.clone(),
            }),
            Box::new(ExecutionIdentity {
                thread_id: self.thread_id.clone(),
                candidate: self.execution_identity.clone(),
            }),
        ]
    }
}

/// Lifecycle phases select how far to advance the one official sequence. SeaORM owns ordering,
/// pending-step detection, transactions and completion records for every phase.
pub(super) enum Preparation {
    Schema,
    ModelAccess,
    ExecutionIdentity,
}
const MODEL_ACCESS: &str = "m20261026_000007_history_model_access";
// Ordered between model-access and execution identity: cold close needs representation maintenance
// without requiring (or activating) a Mode/model/tool execution owner.
const WORKSPACE_RECEIPT: &str = "m20261026_000007a_history_workspace_receipt";
const BOT_ROOT: &str = "m20261026_000007b_history_bot_root_relocation";
pub(super) const EXECUTION_IDENTITY: &str = "m20261026_000008_history_execution_identity";
const RETIRE_ORDINALS: &str = "m20261027_000001_history_retire_ordinals";
const PRODUCER_PAYLOADS: &str = "m20261027_000002_history_producer_payloads";
const REVIEW_RECEIPT: &str = "m20261027_000003_history_review_receipt";
const ATOMIC_TIMELINE: &str = "m20261027_000004_history_atomic_timeline";
const METERING_FACTS: &str = "m20261028_000001_history_metering_facts";
const COMBINED_CONTENT: &str = "m20261028_000002_history_combined_content";
const DEMAND_CONVERSATION: &str = "m20261029_000001_history_demand_conversation";
const MODEL_ROUTE_HEAD: &str = "m20261101_000010_history_model_route_head";
const ATOM_METADATA: &str = "m20261102_000001_history_atom_metadata";
const BACKGROUND_RESULTS: &str = "m20261104_000001_history_background_results";
const TIMELINE_ITEMS: &str = "m20261103_000001_history_timeline_items";
const TIMELINE_THINKING_SUMMARY: &str = "m20261108_000001_history_timeline_thinking_summary";
const TIMELINE_BACKGROUND_TAIL: &str = "m20261109_000001_history_timeline_background_tail";
const MEMBER_READ_METADATA: &str = "m20261107_000001_history_member_read_metadata";
const SOURCE_CLASSIFICATION: &str = "m20261108_000001_history_source_classification";
const COMPLETION_BOUNDARY: &str = "m20261109_000001_history_completion_boundary";
const IMMUTABLE_COMPLETION_RUNS: &str = "m20261110_000001_history_immutable_completion_runs";
const PROJECT_KIND: &str = "m20261027_000004_history_project_kind";

#[cfg(test)]
pub(super) async fn prepare_published17_fixture(
    db: &DatabaseConnection,
    thread_id: &str,
) -> Result<()> {
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity: None,
        bot_root: None,
    };
    let steps = migrator
        .migrations()
        .iter()
        .take_while(|step| step.name() != COMPLETION_BOUNDARY)
        .count();
    migrator.up(db, Some(u32::try_from(steps)?)).await?;
    ensure!(
        version(db).await? == 17,
        "fixture must stop at published schema 17"
    );
    Ok(())
}

// Content preparation and current-only readers share the same lifecycle boundary.
fn is_lifecycle_migration(name: &str) -> bool {
    matches!(
        name,
        PROJECT_KIND | MODEL_ACCESS | WORKSPACE_RECEIPT | BOT_ROOT | EXECUTION_IDENTITY
    )
}

pub(super) async fn needs_content_preparation(
    db: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<bool> {
    Ok(Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity: None,
        bot_root: None,
    }
    .get_pending_migrations_read_only(db)
    .await?
    .iter()
    .any(|step| !is_lifecycle_migration(step.name())))
}

pub(super) async fn prepare(
    db: &DatabaseConnection,
    thread_id: &str,
    phase: Preparation,
    execution_identity: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
) -> Result<()> {
    prepare_with_bot_root(db, thread_id, phase, execution_identity, None).await
}

pub(super) async fn prepare_with_bot_root(
    db: &DatabaseConnection,
    thread_id: &str,
    phase: Preparation,
    execution_identity: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
    bot_root: Option<crate::studio::startup::storage_layout::bot_roots::BotRootMove>,
) -> Result<()> {
    preflight(db, thread_id)
        .await
        .map_err(|error| crate::studio::startup::migration_error("history", "preflight", error))?;
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity,
        bot_root,
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    let steps = match phase {
        Preparation::Schema => pending
            .iter()
            .take_while(|step| !is_lifecycle_migration(step.name()))
            .count(),
        Preparation::ModelAccess => pending
            .iter()
            .take_while(|step| step.name() != EXECUTION_IDENTITY)
            .count(),
        Preparation::ExecutionIdentity => pending.len(),
    };
    let steps = u32::try_from(steps)?;
    if steps == 0 {
        return Ok(());
    }
    let started = std::time::Instant::now();
    let result = migrator.up(db, Some(steps)).await;
    tracing::debug!(
        target: "conversation_work",
        thread_id,
        migration_steps = steps,
        success = result.is_ok(),
        elapsed_us = started.elapsed().as_micros() as u64,
        "history migration completed"
    );
    if let Err(error) = result {
        let pending = migrator
            .get_pending_migrations_read_only(db)
            .await
            .unwrap_or_default();
        let step = pending
            .first()
            .map_or("migration bookkeeping", |migration| migration.name());
        return Err(crate::studio::startup::migration_error(
            "history", step, error,
        ));
    }
    Ok(())
}

pub(super) async fn initialize(db: &DatabaseConnection, thread_id: &str) -> Result<(String, i64)> {
    prepare(db, thread_id, Preparation::Schema, None).await?;
    // Publish only the actual identity/format verified after the content migrations, never an
    // assumed current version derived from a successful (possibly zero-step) preparation.
    validate_existing(db, thread_id).await
}

pub(super) async fn inspect_existing(path: &Path, thread_id: &str) -> Result<()> {
    if !tokio::fs::try_exists(path).await? {
        return Ok(());
    }
    let db = connect_read_only(path).await?;
    let result = preflight(&db, thread_id)
        .await
        .map_err(|error| crate::studio::startup::migration_error("history", "preflight", error));
    let close = db.close().await;
    result?;
    close?;
    Ok(())
}

/// Layout evidence may consult TOML only after proving this is an initialized, supported history
/// family for the same Thread. An arbitrary empty/unversioned SQLite file is not that window.
pub(crate) async fn validate_layout_source(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    preflight(db, thread_id).await?;
    ensure!(
        db.query_one_raw(statement(
            "SELECT thread_id FROM history_meta WHERE id=1",
            vec![]
        ))
        .await?
        .is_some(),
        "layout source has no initialized history identity"
    );
    Ok(())
}

async fn preflight(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity: None,
        bot_root: None,
    };
    let meta = db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='history_meta'",
            vec![],
        ))
        .await?;
    if meta.is_none() {
        ensure!(db.query_one_raw(statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_none(),
            "unversioned nonempty history database; existing data preserved");
        ensure!(
            migrator
                .get_applied_migrations_read_only(db)
                .await?
                .is_empty(),
            "history schema is missing; existing data preserved"
        );
        return Ok(());
    }
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version,thread_id,database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("missing history identity; existing data preserved")?;
    let version: i64 = row.try_get("", "schema_version")?;
    ensure!(
        (1..=HISTORY_SCHEMA_VERSION).contains(&version),
        "unsupported history schema {version}; existing data preserved"
    );
    let pending = migrator
        .get_pending_migrations_read_only(db)
        .await?
        .into_iter()
        .filter(|step| {
            !work_snapshots::is_legacy_marker(step.name()) && step.name() != DISPLAY_BLOCK_ORDER
        })
        .collect::<Vec<_>>();
    let order_pending = migrator
        .get_pending_migrations_read_only(db)
        .await?
        .iter()
        .any(|step| step.name() == DISPLAY_BLOCK_ORDER);
    ensure!(
        order_pending == (version < 23),
        "display format conflicts with migration record; original history preserved"
    );
    let atomic_pending = pending.iter().any(|step| step.name() == ATOMIC_TIMELINE);
    let metering_pending = pending.iter().any(|step| step.name() == METERING_FACTS);
    let combined_pending = pending.iter().any(|step| step.name() == COMBINED_CONTENT);
    let retire_pending = pending.iter().any(|step| step.name() == RETIRE_ORDINALS);
    let demand_pending = pending
        .iter()
        .any(|step| step.name() == DEMAND_CONVERSATION);
    let model_route_head_pending = pending.iter().any(|step| step.name() == MODEL_ROUTE_HEAD);
    let metadata_pending = pending.iter().any(|step| step.name() == ATOM_METADATA);
    let timeline_pending = pending.iter().any(|step| step.name() == TIMELINE_ITEMS);
    let source_classification_pending = pending
        .iter()
        .any(|step| step.name() == SOURCE_CLASSIFICATION);
    let thinking_summary_pending = pending
        .iter()
        .any(|step| step.name() == TIMELINE_THINKING_SUMMARY);
    let background_tail_pending = pending
        .iter()
        .any(|step| step.name() == TIMELINE_BACKGROUND_TAIL);
    let runs_pending = pending
        .iter()
        .any(|step| step.name() == IMMUTABLE_COMPLETION_RUNS);
    let display_pending = pending.iter().any(|step| step.name() == WORK_SNAPSHOTS);
    // Format and migration bookkeeping must describe the same content boundary. Lifecycle
    // recovery being pending never excuses a completed content step with an older marker.
    ensure!(
        model_route_head_pending == (version < 13)
            && metadata_pending == (version < 14)
            && timeline_pending == (version < 15)
            && (source_classification_pending || matches!(version, 15..=23))
            && thinking_summary_pending == (version < 16)
            && background_tail_pending == (version < 17)
            && runs_pending == (version < 18)
            && display_pending == (version < 22)
            && match version {
                1..=8 => retire_pending && atomic_pending && metering_pending && combined_pending,
                9 => !retire_pending && atomic_pending && metering_pending && combined_pending,
                10 => !retire_pending && (!atomic_pending || !metering_pending) && combined_pending,
                11 => {
                    !retire_pending
                        && !atomic_pending
                        && !metering_pending
                        && !combined_pending
                        && demand_pending
                }
                12..=23 => {
                    !retire_pending
                        && !atomic_pending
                        && !metering_pending
                        && !combined_pending
                        && !demand_pending
                }
                _ => false,
            },
        "history format conflicts with completed migrations; existing data preserved"
    );
    if version >= 12 {
        ensure!(
            row.try_get::<String>("", "thread_id")? == thread_id,
            "history database belongs to another Thread"
        );
        ensure!(
            !row.try_get::<String>("", "database_id")?.is_empty(),
            "empty history database identity"
        );
        validate_identity_collations(db).await?;
        if version == HISTORY_SCHEMA_VERSION {
            if pending
                .iter()
                .any(|step| step.name() == MEMBER_READ_METADATA)
            {
                validate_member_metadata_source(db).await?;
            } else {
                validate_current_structure(db).await?;
            }
            ensure!(
                pending.iter().all(|step| {
                    matches!(
                        step.name(),
                        BACKGROUND_RESULTS
                            | MEMBER_READ_METADATA
                            | SOURCE_CLASSIFICATION
                            | COMPLETION_BOUNDARY
                            | IMMUTABLE_COMPLETION_RUNS
                            | WORK_SNAPSHOTS
                    ) || is_lifecycle_migration(step.name())
                }),
                "current history format has pending earlier content migrations; existing data preserved"
            );
        } else {
            // CompletionBoundary already archived the old view tables at schema 17.
            // Its published input gate is distinct from the earlier demand-view layout.
            if version < 18 && (version != 17 || !completion_boundary::applied(db).await?) {
                demand_conversation::validate_tables(db).await?;
            }
            match version {
                22 => {
                    work_snapshots::validate(db).await?;
                    ensure!(
                        pending
                            .iter()
                            .all(|step| is_lifecycle_migration(step.name())),
                        "schema 22 has pending earlier content migrations; existing data preserved"
                    );
                }
                19..=21 => {
                    immutable_completion_runs::validate_preserved(db).await?;
                    ensure!(
                        pending.iter().all(|step| step.name() == WORK_SNAPSHOTS
                            || is_lifecycle_migration(step.name())),
                        "legacy display has pending earlier content migrations"
                    );
                }
                18 => {
                    immutable_completion_runs::validate(db).await?;
                    ensure!(
                        pending
                            .iter()
                            .all(|step| matches!(step.name(), WORK_SNAPSHOTS)
                                || is_lifecycle_migration(step.name())),
                        "schema 18 has pending earlier content migrations; existing data preserved"
                    );
                }
                12 => {
                    model_route_head::validate_source(db).await?;
                    atom_metadata::validate_source(db).await?;
                    timeline_items::validate_source(db).await?;
                    ensure!(
                        pending.iter().all(|step| {
                            matches!(
                                step.name(),
                                MODEL_ROUTE_HEAD
                                    | SOURCE_CLASSIFICATION
                                    | COMPLETION_BOUNDARY
                                    | IMMUTABLE_COMPLETION_RUNS
                                    | WORK_SNAPSHOTS
                                    | ATOM_METADATA
                                    | BACKGROUND_RESULTS
                                    | TIMELINE_ITEMS
                                    | TIMELINE_THINKING_SUMMARY
                                    | TIMELINE_BACKGROUND_TAIL
                                    | MEMBER_READ_METADATA
                            ) || is_lifecycle_migration(step.name())
                        }),
                        "schema 12 has pending earlier content migrations; existing data preserved"
                    );
                }
                13 => {
                    model_route_head::validate_tables(db).await?;
                    atom_metadata::validate_source(db).await?;
                    timeline_items::validate_source(db).await?;
                    ensure!(
                        pending.iter().all(|step| {
                            matches!(
                                step.name(),
                                ATOM_METADATA
                                    | SOURCE_CLASSIFICATION
                                    | COMPLETION_BOUNDARY
                                    | IMMUTABLE_COMPLETION_RUNS
                                    | WORK_SNAPSHOTS
                                    | BACKGROUND_RESULTS
                                    | TIMELINE_ITEMS
                                    | TIMELINE_THINKING_SUMMARY
                                    | TIMELINE_BACKGROUND_TAIL
                                    | MEMBER_READ_METADATA
                            ) || is_lifecycle_migration(step.name())
                        }),
                        "schema 13 has pending earlier content migrations; existing data preserved"
                    );
                }
                14 => {
                    model_route_head::validate_tables(db).await?;
                    atom_metadata::validate_tables(db).await?;
                    timeline_items::validate_source(db).await?;
                    ensure!(
                        pending.iter().all(|step| {
                            matches!(
                                step.name(),
                                BACKGROUND_RESULTS
                                    | TIMELINE_ITEMS
                                    | MEMBER_READ_METADATA
                                    | SOURCE_CLASSIFICATION
                                    | COMPLETION_BOUNDARY
                                    | IMMUTABLE_COMPLETION_RUNS
                                    | WORK_SNAPSHOTS
                                    | TIMELINE_THINKING_SUMMARY
                                    | TIMELINE_BACKGROUND_TAIL
                            ) || is_lifecycle_migration(step.name())
                        }),
                        "schema 14 has pending earlier content migrations; existing data preserved"
                    );
                }
                15 => {
                    model_route_head::validate_tables(db).await?;
                    atom_metadata::validate_tables(db).await?;
                    member_read_metadata::validate_source(db).await?;
                    // The source format legitimately carries projection v1.
                    // Its derived head is replaced by the pending migration,
                    // never decoded by the normal current-version reader.
                    legacy_current::read(db).await?;
                    ensure!(
                        pending.iter().all(|step| {
                            matches!(
                                step.name(),
                                BACKGROUND_RESULTS
                                    | MEMBER_READ_METADATA
                                    | TIMELINE_THINKING_SUMMARY
                                    | TIMELINE_BACKGROUND_TAIL
                                    | SOURCE_CLASSIFICATION
                                    | COMPLETION_BOUNDARY
                                    | IMMUTABLE_COMPLETION_RUNS
                                    | WORK_SNAPSHOTS
                            ) || is_lifecycle_migration(step.name())
                        }),
                        "schema 15 has pending earlier content migrations; existing data preserved"
                    );
                }
                16 => {
                    if pending
                        .iter()
                        .any(|step| step.name() == MEMBER_READ_METADATA)
                    {
                        validate_member_metadata_source(db).await?;
                    } else {
                        validate_schema16_structure(db).await?;
                    }
                    ensure!(
                        pending.iter().all(|step| {
                            matches!(
                                step.name(),
                                TIMELINE_BACKGROUND_TAIL
                                    | BACKGROUND_RESULTS
                                    | MEMBER_READ_METADATA
                                    | SOURCE_CLASSIFICATION
                                    | COMPLETION_BOUNDARY
                                    | IMMUTABLE_COMPLETION_RUNS
                                    | WORK_SNAPSHOTS
                            ) || is_lifecycle_migration(step.name())
                        }),
                        "schema 16 has pending earlier content migrations; existing data preserved"
                    );
                }
                17 => {
                    if pending
                        .iter()
                        .any(|step| step.name() == MEMBER_READ_METADATA)
                    {
                        validate_member_metadata_source(db).await?;
                    } else if completion_boundary::applied(db).await? {
                        completion_boundary::validate(db).await?;
                    } else {
                        validate_timeline_structure(db).await?;
                    }
                    ensure!(
                        pending.iter().all(|step| matches!(
                            step.name(),
                            BACKGROUND_RESULTS
                                | MEMBER_READ_METADATA
                                | SOURCE_CLASSIFICATION
                                | COMPLETION_BOUNDARY
                                | IMMUTABLE_COMPLETION_RUNS
                                | WORK_SNAPSHOTS
                        ) || is_lifecycle_migration(step.name())),
                        "schema 17 has pending earlier content migrations; existing data preserved"
                    );
                }
                _ => anyhow::bail!(
                    "unsupported pending history format {version}; existing data preserved"
                ),
            }
        }
        return Ok(());
    }
    for table in [
        "conversation_items",
        "conversation_contents",
        "conversation_content_chunks",
        "conversation_view_state",
        "conversation_view_entries",
    ] {
        ensure!(
            !SchemaManager::new(db).has_table(table).await?,
            "pending conversation migration has a pre-existing output table; existing data preserved"
        );
    }
    ensure!(
        SchemaManager::new(db).has_table("timeline_records").await? == !atomic_pending,
        "atomic timeline migration conflicts with its output table; existing data preserved"
    );
    ensure!(
        row.try_get::<String>("", "thread_id")? == thread_id,
        "history database belongs to another Thread"
    );
    ensure!(
        !row.try_get::<String>("", "database_id")?.is_empty(),
        "history database identity is empty"
    );
    validate_identity_collations(db).await?;
    if version == 8 {
        // Keep the published v8 adoption contract: CreateHistory may still add its
        // request_digest column when enrolling a pre-SeaORM file for the first time.
        let manager = SchemaManager::new(db);
        for table in [
            "history_items",
            "history_turns",
            "history_input_identities",
            "history_fact_receipts",
            "history_message_identities",
            "session_checkpoint",
            "session_costs",
            "current_context",
            "history_tool_tasks",
        ] {
            ensure!(
                manager.has_table(table).await?,
                "current history table {table} is missing; existing data preserved"
            );
        }
    } else if version == 9 || (version == 10 && atomic_pending) {
        validate_v9_tables(db).await?;
    } else if version == 10 || version == 11 {
        validate_tables(db).await?;
        if version == 10 {
            validate_timeline_data(db, thread_id).await?;
        }
    }
    if version == 10 && !metering_pending {
        checkpoint::read(db, thread_id).await?;
    }
    if SchemaManager::new(db)
        .has_table("session_checkpoint")
        .await?
    {
        for row in db
            .query_all_raw(statement(
                "SELECT json_extract(payload,'$.schemaVersion') AS version FROM session_checkpoint",
                vec![],
            ))
            .await?
        {
            let checkpoint_version: i64 = row.try_get("", "version")?;
            ensure!(
                (1..=i64::from(pl_core::thread::ThreadCheckpoint::SCHEMA_VERSION))
                    .contains(&checkpoint_version),
                "unsupported checkpoint schema {checkpoint_version}; existing data preserved"
            );
        }
    }
    tracing::debug!(target: "conversation_work", quick_check = 1, "history integrity check");
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "history database integrity check failed"
        );
    }
    Ok(())
}

/// First-connection trust gate, before any transaction takes the pool's only connection.
/// Missing tables remain subject to the versioned adoption/shape rules in preflight; an
/// existing table must already have the exact comparison semantics its identity queries use.
pub(super) async fn validate_identity_collations(db: &DatabaseConnection) -> Result<()> {
    let manager = SchemaManager::new(db);
    for (table, columns) in [
        (
            "history_items",
            &["item_id", "turn_id", "kind", "lifecycle"][..],
        ),
        ("history_turns", &["turn_id"][..]),
        ("history_input_identities", &["item_id"][..]),
        ("history_fact_receipts", &["item_id", "kind"][..]),
        ("history_message_identities", &["message_id"][..]),
        ("current_context", &["record_id"][..]),
        ("history_tool_tasks", &["call_id"][..]),
        ("session_costs", &["purpose", "currency"][..]),
        ("timeline_records", &["record_id"][..]),
        (
            "conversation_items",
            &["item_id", "query_class", "parent_id"][..],
        ),
        ("conversation_contents", &["owner_key", "content_key"][..]),
        (
            "conversation_content_chunks",
            &["owner_key", "content_key"][..],
        ),
        ("conversation_view_entries", &["collection", "entry_id"][..]),
        ("conversation_sources", &["source_key"][..]),
        ("timeline_items", &["item_id", "kind"][..]),
        (
            "timeline_item_members",
            &["item_id", "member_id", "completion_item_id"][..],
        ),
    ] {
        if !manager.has_table(table).await? {
            continue;
        }
        let declarations = db
            .query_all_raw(statement(
                "SELECT name,type FROM pragma_table_info(?, 'main')",
                vec![table.into()],
            ))
            .await?
            .into_iter()
            .map(|row| Ok((row.try_get("", "name")?, row.try_get("", "type")?)))
            .collect::<std::result::Result<
                std::collections::BTreeMap<String, String>,
                sea_orm::DbErr,
            >>()?;
        for column in columns {
            let declared = declarations
                .get(*column)
                .with_context(|| format!("history column {table}.{column} is missing"))?;
            let declared_upper = declared.to_ascii_uppercase();
            // SQLite datatype §3.1: INTEGER takes precedence over TEXT, including CHARINT.
            // The later BLOB/REAL/NUMERIC rules cannot produce TEXT. STRICT accepts only
            // canonical type names, so this also rejects its ANY rather than treating it as TEXT.
            ensure!(
                !declared_upper.contains("INT")
                    && ["CHAR", "CLOB", "TEXT"]
                        .iter()
                        .any(|marker| declared_upper.contains(marker)),
                "history column {table}.{column} requires TEXT affinity, found {declared:?}; existing data preserved"
            );
            let collation = sqlite_metadata::column_collation(db, table, column).await?;
            ensure!(
                collation.eq_ignore_ascii_case("BINARY"),
                "history column {table}.{column} requires BINARY comparison, found {collation}; existing data preserved"
            );
        }
    }
    Ok(())
}

/// Ordinary readers accept only the prepared content format; lifecycle migrations may remain
/// pending until explicit recovery supplies model and execution identity facts.
pub(super) async fn validate_current(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    validate_current_structure(db).await?;
    ensure!(
        !needs_content_preparation(db, thread_id).await?,
        "history content requires explicit storage preparation; existing data preserved"
    );
    Ok(())
}

async fn validate_current_structure(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == HISTORY_SCHEMA_VERSION,
        "history format is not current; existing data preserved"
    );
    display_block_order::validate(db).await
}

async fn validate_schema16_structure(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(version(db).await? == 16, "expected schema 16 upgrade input");
    validate_timeline_structure(db).await
}

async fn validate_timeline_structure(db: &impl ConnectionTrait) -> Result<()> {
    demand_conversation::validate_tables(db).await?;
    model_route_head::validate_tables(db).await?;
    atom_metadata::validate_tables(db).await?;
    legacy_timeline_store::validate_tables(db).await?;
    validate_saved_heads(db).await
}

async fn validate_member_metadata_source(db: &impl ConnectionTrait) -> Result<()> {
    demand_conversation::validate_tables(db).await?;
    model_route_head::validate_tables(db).await?;
    atom_metadata::validate_tables(db).await?;
    member_read_metadata::validate_source(db).await?;
    validate_saved_heads(db).await
}

async fn validate_saved_heads(db: &impl ConnectionTrait) -> Result<()> {
    let head = legacy_timeline_store::read_state(db)
        .await?
        .context("timeline recovery head is missing; existing data preserved")?;
    let database_id = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity is missing; existing data preserved")?
        .try_get::<String>("", "database_id")?;
    let mut projection = legacy_timeline_projection::TimelineProjection::new(
        database_id,
        head.generation,
        head.next_position,
    );
    projection
        .restore_recovery(&head.recovery)
        .context("timeline recovery is invalid; existing data preserved")?;
    checkpoint::read_model_route_head(db).await?;
    Ok(())
}

async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    validate_v9_tables(db).await?;
    db.query_all_raw(statement(
        "SELECT append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload FROM timeline_records LIMIT 0",
        vec![],
    ))
    .await
    .context("history timeline table or column is missing; existing data preserved")?;
    validate_keys(
        db,
        "timeline_records",
        &["append_seq"],
        true,
        &["record_id"],
    )
    .await?;
    Ok(())
}

/// Reuse the canonical record decoder without rewriting or aggregating existing completions.
/// Preparation may inspect every record, but bounds full payload memory to one ordinary page.
async fn validate_timeline_data(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM timeline_records WHERE append_seq<=0 LIMIT 1",
            vec![],
        ))
        .await?
        .is_none(),
        "timeline append sequence must be positive; existing data preserved"
    );
    let ceiling = super::timeline::latest_append_seq(db).await?;
    let mut after = 0;
    loop {
        let page = super::timeline::page_after(db, thread_id, after, ceiling, 100).await?;
        for item in &page.items {
            ensure!(
                after.checked_add(1) == Some(item.append_seq),
                "timeline append sequence is not contiguous; existing data preserved"
            );
            after = item.append_seq;
        }
        if !page.has_more {
            return Ok(());
        }
    }
}

/// Published v9 shape, also used by RetireOrdinals. Never add current-format tables here:
/// earlier steps must remain runnable before the AtomicTimeline step has created its output.
async fn validate_v9_tables(db: &impl ConnectionTrait) -> Result<()> {
    // Preparing each query validates required columns even on empty tables, without reading
    // history bodies or repairing a damaged current database with CREATE IF NOT EXISTS.
    for query in [
        "SELECT applied_write_seq FROM history_meta LIMIT 0",
        "SELECT ordinal,item_id,turn_id,kind,revision,lifecycle,created_at,updated_at,payload,last_write_seq FROM history_items LIMIT 0",
        "SELECT turn_id,first_ordinal,last_ordinal,revision,payload,last_write_seq FROM history_turns LIMIT 0",
        "SELECT item_id,ordinal,revision,digest,request_digest,presentation,payload,last_write_seq FROM history_input_identities LIMIT 0",
        "SELECT item_id,revision,kind,digest,payload,last_write_seq FROM history_fact_receipts LIMIT 0",
        "SELECT message_id,item_id,sequence,digest,last_write_seq FROM history_message_identities LIMIT 0",
        "SELECT id,revision,context_revision,context_count,payload,payload_hash,legacy_cleanup FROM session_checkpoint LIMIT 0",
        "SELECT purpose,currency,amount FROM session_costs LIMIT 0",
        "SELECT ordinal,record_id,payload,payload_hash FROM current_context LIMIT 0",
        "SELECT call_id,revision,task_payload,delivery_payload,last_write_seq FROM history_tool_tasks LIMIT 0",
    ] {
        db.query_all_raw(statement(query, vec![]))
            .await
            .context("history required table or column is missing; existing data preserved")?;
    }
    // These are the keys used by ordinal seeks, identity point reads and ON CONFLICT writes.
    // Check SQLite's actual constraints, not just columns or the contents of an empty database.
    for (table, primary, integer_primary, unique) in [
        ("history_meta", &["id"][..], true, &[][..]),
        ("history_items", &["ordinal"][..], true, &["item_id"][..]),
        ("history_turns", &["turn_id"][..], false, &[][..]),
        ("history_input_identities", &["item_id"][..], false, &[][..]),
        (
            "history_fact_receipts",
            &["item_id", "revision"][..],
            false,
            &[][..],
        ),
        (
            "history_message_identities",
            &["message_id"][..],
            false,
            &[][..],
        ),
        ("session_checkpoint", &["id"][..], true, &[][..]),
        (
            "session_costs",
            &["purpose", "currency"][..],
            false,
            &[][..],
        ),
        (
            "current_context",
            &["ordinal"][..],
            true,
            &["record_id"][..],
        ),
        ("history_tool_tasks", &["call_id"][..], false, &[][..]),
    ] {
        validate_keys(db, table, primary, integer_primary, unique).await?;
    }
    Ok(())
}

/// Local history key validation using SQLite's public metadata. Index names and DDL spelling
/// are immaterial; partial/expression indexes do not establish the required identity uniqueness.
async fn validate_keys(
    db: &impl ConnectionTrait,
    table: &str,
    primary: &[&str],
    integer_primary: bool,
    unique: &[&str],
) -> Result<()> {
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM main.sqlite_schema WHERE type='table' AND name=?",
            vec![table.into()],
        ))
        .await?
        .is_some(),
        "history required table {table} is missing; existing data preserved"
    );
    let columns = db
        .query_all_raw(statement(
            "SELECT name,type,pk,\"notnull\" FROM pragma_table_info(?, 'main')",
            vec![table.into()],
        ))
        .await?;
    let mut actual_primary = Vec::new();
    for column in &columns {
        if column.try_get::<i64>("", "pk")? > 0 {
            actual_primary.push(column.try_get::<String>("", "name")?);
        }
    }
    ensure!(
        actual_primary.len() == primary.len()
            && primary
                .iter()
                .all(|key| actual_primary.iter().any(|name| name == key)),
        "history table {table} primary key differs from required {primary:?}; existing data preserved"
    );
    let indexes = db
        .query_all_raw(statement(
            "SELECT name,\"unique\",origin,partial FROM pragma_index_list(?, 'main')",
            vec![table.into()],
        ))
        .await?;
    if integer_primary {
        // INTEGER PRIMARY KEY is a rowid alias. In particular INTEGER PRIMARY KEY DESC
        // instead creates a nullable indexed key: table_info's pk flag alone cannot prove it.
        ensure!(
            primary.len() == 1
                && columns.iter().any(|column| {
                    column.try_get::<String>("", "name").ok().as_deref() == Some(primary[0])
                        && column
                            .try_get::<String>("", "type")
                            .is_ok_and(|kind| kind.eq_ignore_ascii_case("INTEGER"))
                })
                && indexes.iter().all(|index| index
                    .try_get::<String>("", "origin")
                    .is_ok_and(|origin| origin != "pk")),
            "history table {table} requires an INTEGER PRIMARY KEY rowid; existing data preserved"
        );
    } else {
        ensure!(
            has_unique_key(db, &indexes, primary, true, false).await?,
            "history table {table} primary key lacks exact identity uniqueness; existing data preserved"
        );
        // Both published composite keys (receipts and costs) declare every component NOT NULL.
        // A rowid table's PRIMARY KEY alone still admits duplicate keys containing NULL.
        // Single-column TEXT primary keys intentionally retain their published nullable shape.
        if primary.len() > 1 {
            for key in primary {
                let column = columns
                    .iter()
                    .find(|column| {
                        column.try_get::<String>("", "name").ok().as_deref() == Some(*key)
                    })
                    .context("validated history primary-key column disappeared")?;
                ensure!(
                    column.try_get::<i64>("", "notnull")? == 1,
                    "history table {table} composite primary key column {key} requires NOT NULL; existing data preserved"
                );
            }
        }
    }
    for key in unique {
        ensure!(
            columns.iter().any(|column| {
                column.try_get::<String>("", "name").ok().as_deref() == Some(*key)
                    && column
                        .try_get::<i64>("", "notnull")
                        .is_ok_and(|value| value == 1)
            }) && has_unique_key(db, &indexes, &[*key], false, false).await?,
            "history table {table} requires NOT NULL UNIQUE key {key}; existing data preserved"
        );
    }
    Ok(())
}

/// A single ordered composite constraint, not a list of independently unique columns.
/// Uses transaction-local SQLite metadata; column affinity/default collations are also checked
/// by the native first-connection trust gate before the one-connection migration transaction.
async fn validate_ordered_unique_key(
    db: &impl ConnectionTrait,
    table: &str,
    keys: &[&str],
    primary: bool,
) -> Result<()> {
    let columns = db
        .query_all_raw(statement(
            "SELECT name,\"notnull\" FROM pragma_table_info(?, 'main')",
            vec![table.into()],
        ))
        .await?;
    ensure!(
        !keys.is_empty()
            && keys.iter().all(|key| columns.iter().any(|column| {
                column
                    .try_get::<String>("", "name")
                    .is_ok_and(|name| name == *key)
                    && column
                        .try_get::<i64>("", "notnull")
                        .is_ok_and(|value| value == 1)
            })),
        "history table {table} requires NOT NULL columns for key {keys:?}; existing data preserved"
    );
    let indexes = db
        .query_all_raw(statement(
            "SELECT name,\"unique\",origin,partial FROM pragma_index_list(?, 'main')",
            vec![table.into()],
        ))
        .await?;
    ensure!(
        has_unique_key(db, &indexes, keys, primary, true).await?,
        "history table {table} requires ordered BINARY NOT NULL UNIQUE key {keys:?}; existing data preserved"
    );
    Ok(())
}

async fn has_unique_key(
    db: &impl ConnectionTrait,
    indexes: &[sea_orm::QueryResult],
    keys: &[&str],
    primary: bool,
    ordered: bool,
) -> Result<bool> {
    for index in indexes {
        if index.try_get::<i64>("", "unique")? != 1
            || index.try_get::<i64>("", "partial")? != 0
            || (primary && index.try_get::<String>("", "origin")? != "pk")
        {
            continue;
        }
        let columns = db
            .query_all_raw(statement(
                "SELECT name,coll,\"desc\" AS descending FROM pragma_index_xinfo(?, 'main')
                 WHERE key=1 ORDER BY seqno",
                vec![index.try_get::<String>("", "name")?.into()],
            ))
            .await?;
        if columns.len() == keys.len()
            && keys.iter().all(|key| {
                columns.iter().any(|column| {
                    column
                        .try_get::<Option<String>>("", "name")
                        .ok()
                        .flatten()
                        .as_deref()
                        == Some(*key)
                })
            })
            && columns.iter().all(|column| {
                column
                    .try_get::<Option<String>>("", "name")
                    .is_ok_and(|name| name.is_some_and(|name| keys.contains(&name.as_str())))
                    && column
                        .try_get::<String>("", "coll")
                        .is_ok_and(|collation| collation.eq_ignore_ascii_case("BINARY"))
            })
            && (!ordered
                || keys.iter().zip(&columns).all(|(key, column)| {
                    column
                        .try_get::<Option<String>>("", "name")
                        .is_ok_and(|name| name.as_deref() == Some(*key))
                        && column
                            .try_get::<i64>("", "descending")
                            .is_ok_and(|value| value == 0)
                }))
        {
            return Ok(true);
        }
    }
    Ok(false)
}

struct RetireOrdinals;
struct MeteringFacts {
    thread_id: String,
}
impl MigrationName for MeteringFacts {
    fn name(&self) -> &str {
        METERING_FACTS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for MeteringFacts {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        checkpoint::migrate_envelope(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        super::producer::migrate(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        set_version(db, 10).await
    }
}

struct ProducerPayloads {
    thread_id: String,
}
impl MigrationName for ProducerPayloads {
    fn name(&self) -> &str {
        PRODUCER_PAYLOADS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ProducerPayloads {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        super::producer::migrate(manager.get_connection(), &self.thread_id)
            .await
            .map_err(conversion)
    }
}
impl MigrationName for RetireOrdinals {
    fn name(&self) -> &str {
        RETIRE_ORDINALS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for RetireOrdinals {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        validate_v9_tables(db).await.map_err(conversion)?;
        db.execute_unprepared("DROP TABLE IF EXISTS history_ordinals")
            .await?;
        if version(db).await? < 9 {
            set_version(db, 9).await?;
        }
        Ok(())
    }
}

struct AtomicTimeline {
    thread_id: String,
}

impl MigrationName for AtomicTimeline {
    fn name(&self) -> &str {
        ATOMIC_TIMELINE
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AtomicTimeline {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let source_version = version(db).await?;
        let metering_applied = Migrator {
            thread_id: self.thread_id.clone(),
            execution_identity: None,
            bot_root: None,
        }
        .get_applied_migrations_read_only(db)
        .await?
        .iter()
        .any(|step| step.name() == METERING_FACTS);
        if source_version != 9 && !(source_version == 10 && metering_applied) {
            return Err(DbErr::Migration(
                "atomic timeline migration requires history format 9 or metering-applied format 10"
                    .into(),
            ));
        }
        validate_v9_tables(db).await.map_err(conversion)?;
        super::timeline::migrate(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        validate_tables(db).await.map_err(conversion)?;
        set_version(db, 10).await
    }
}

struct CombinedContent {
    thread_id: String,
}

impl MigrationName for CombinedContent {
    fn name(&self) -> &str {
        COMBINED_CONTENT
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CombinedContent {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let migrator = Migrator {
            thread_id: self.thread_id.clone(),
            execution_identity: None,
            bot_root: None,
        };
        if version(db).await? != 10
            || migrator
                .get_pending_migrations_read_only(db)
                .await?
                .iter()
                .filter(|step| {
                    !work_snapshots::is_legacy_marker(step.name())
                        && step.name() != DISPLAY_BLOCK_ORDER
                })
                .any(|step| {
                    // Later content steps are still pending at the format-10 boundary.
                    !matches!(
                        step.name(),
                        COMBINED_CONTENT
                            | DEMAND_CONVERSATION
                            | MODEL_ROUTE_HEAD
                            | ATOM_METADATA
                            | MEMBER_READ_METADATA
                            | BACKGROUND_RESULTS
                            | TIMELINE_ITEMS
                            | SOURCE_CLASSIFICATION
                            | COMPLETION_BOUNDARY
                            | IMMUTABLE_COMPLETION_RUNS
                            | WORK_SNAPSHOTS
                            | TIMELINE_THINKING_SUMMARY
                            | TIMELINE_BACKGROUND_TAIL
                    ) && !is_lifecycle_migration(step.name())
                })
        {
            return Err(DbErr::Migration(
                "combined history content requires both completed format 10 content steps".into(),
            ));
        }
        validate_tables(db).await.map_err(conversion)?;
        validate_timeline_data(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        set_version(db, 11).await
    }
}

pub(super) async fn version(db: &impl ConnectionTrait) -> Result<i64, DbErr> {
    db.query_one_raw(statement(
        "SELECT schema_version FROM history_meta WHERE id=1",
        vec![],
    ))
    .await?
    .ok_or_else(|| DbErr::Migration("missing history format".into()))?
    .try_get("", "schema_version")
}
async fn set_version(db: &impl ConnectionTrait, target: i64) -> Result<(), DbErr> {
    db.execute_raw(statement(
        "UPDATE history_meta SET schema_version=? WHERE id=1",
        vec![target.into()],
    ))
    .await?;
    Ok(())
}
fn conversion(error: anyhow::Error) -> DbErr {
    match error.downcast::<DbErr>() {
        Ok(error) => error,
        Err(error) => DbErr::Migration(format!("{error:#}")),
    }
}

struct CreateHistory {
    thread_id: String,
}
impl MigrationName for CreateHistory {
    fn name(&self) -> &str {
        "m20261026_000001_history_schema"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CreateHistory {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS history_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL,
            database_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            applied_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_items (
            ordinal INTEGER PRIMARY KEY,
            item_id TEXT NOT NULL UNIQUE,
            turn_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            revision INTEGER NOT NULL,
            lifecycle TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS history_items_by_turn
            ON history_items(turn_id, ordinal);
        -- 最新终态按 ordinal 排序；缺口恢复另按原始 write_seq 范围读取。
        CREATE INDEX IF NOT EXISTS history_items_by_kind_lifecycle
            ON history_items(kind, lifecycle, ordinal);
        CREATE INDEX IF NOT EXISTS history_terminal_turns_by_write_seq
            ON history_items(last_write_seq,ordinal) WHERE kind='turn' AND lifecycle='terminal';
        -- `agent_page` 的 text-only 稀疏过滤同样带 ordinal 方向，单独一条 (kind, ordinal) 索引
        -- 才能同时满足过滤与排序。
        CREATE INDEX IF NOT EXISTS history_items_by_kind
            ON history_items(kind, ordinal);
        CREATE TABLE IF NOT EXISTS history_turns (
            turn_id TEXT PRIMARY KEY,
            first_ordinal INTEGER NOT NULL,
            last_ordinal INTEGER NOT NULL,
            revision INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        -- Turn 页是 `last_ordinal` 上的 keyset 倒序扫描；没有这条索引时深翻页会退化成全表
        -- 扫描 + 排序。
        CREATE INDEX IF NOT EXISTS history_turns_by_last_ordinal
            ON history_turns(last_ordinal);
        CREATE TABLE IF NOT EXISTS history_input_identities (
            item_id TEXT PRIMARY KEY,
            ordinal INTEGER NOT NULL,
            revision INTEGER NOT NULL,
            digest TEXT NOT NULL,
            request_digest TEXT,
            presentation TEXT CHECK (presentation IN ('visible','hidden')),
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_fact_receipts (
            item_id TEXT NOT NULL,
            revision INTEGER NOT NULL,
            kind TEXT NOT NULL,
            digest TEXT NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL,
            PRIMARY KEY(item_id, revision)
        );
        -- 已受理消息的最小身份索引：原始消息 id、时间线条目身份、受理序号与正文摘要。
        -- `digest` 可空，只用于迁移回填留下的“身份已知、正文不可验证”行（读取方 fail-closed）。
        CREATE TABLE IF NOT EXISTS history_message_identities (
            message_id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            digest TEXT,
            last_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS session_checkpoint (
            id INTEGER PRIMARY KEY CHECK(id=1),
            revision INTEGER NOT NULL,
            context_revision INTEGER NOT NULL,
            context_count INTEGER NOT NULL,
            payload TEXT NOT NULL,
            payload_hash TEXT NOT NULL,
            legacy_cleanup INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS session_costs (
            purpose TEXT NOT NULL,
            currency TEXT NOT NULL,
            amount REAL NOT NULL,
            PRIMARY KEY(purpose,currency)
        );
        CREATE TABLE IF NOT EXISTS current_context (
            ordinal INTEGER PRIMARY KEY,
            record_id TEXT NOT NULL UNIQUE,
            payload TEXT NOT NULL,
            payload_hash TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_tool_tasks (
            call_id TEXT PRIMARY KEY,
            revision INTEGER NOT NULL,
            task_payload TEXT NOT NULL CHECK (json_valid(task_payload)),
            delivery_payload TEXT CHECK (delivery_payload IS NULL OR json_valid(delivery_payload)),
            last_write_seq INTEGER NOT NULL
        );",
        )
        .await?;

        if !manager
            .has_column("history_input_identities", "request_digest")
            .await?
        {
            db.execute_unprepared(
                "ALTER TABLE history_input_identities ADD COLUMN request_digest TEXT",
            )
            .await?;
        }
        db.execute_raw(statement("INSERT OR IGNORE INTO history_meta(id,schema_version,database_id,thread_id,applied_write_seq) VALUES(1,?,?,?,0)",
            vec![8i64.into(), crate::studio::new_id("history-db").into(), self.thread_id.clone().into()])).await?;
        Ok(())
    }
}

struct InputPresentation;
impl MigrationName for InputPresentation {
    fn name(&self) -> &str {
        "m20261026_000002_history_input_presentation"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for InputPresentation {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 3 {
            if !manager
                .has_column("history_input_identities", "presentation")
                .await?
            {
                db.execute_unprepared("ALTER TABLE history_input_identities ADD COLUMN presentation TEXT CHECK (presentation IN ('visible','hidden'))").await?;
            }
            backfill_legacy_hidden_inputs(db)
                .await
                .map_err(conversion)?;
            set_version(db, 3).await?;
        }
        Ok(())
    }
}

struct InputBindings;
impl MigrationName for InputBindings {
    fn name(&self) -> &str {
        "m20261026_000003_history_input_bindings"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for InputBindings {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 4 {
            migrate_unconsumed_input_bindings(db)
                .await
                .map_err(conversion)?;
            set_version(db, 4).await?;
        }
        Ok(())
    }
}

struct ContextSources {
    thread_id: String,
}
impl MigrationName for ContextSources {
    fn name(&self) -> &str {
        "m20261026_000004_history_context_sources"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ContextSources {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 6 {
            migrate_context_sources(db, &self.thread_id)
                .await
                .map_err(conversion)?;
            set_version(db, 6).await?;
        }
        Ok(())
    }
}

struct ToolAnswers {
    thread_id: String,
}
impl MigrationName for ToolAnswers {
    fn name(&self) -> &str {
        "m20261026_000005_history_tool_answers"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ToolAnswers {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 8 {
            backfill_tool_user_input(db, &self.thread_id)
                .await
                .map_err(conversion)?;
            set_version(db, 8).await?;
        }
        Ok(())
    }
}

struct CheckpointV5 {
    thread_id: String,
}
impl MigrationName for CheckpointV5 {
    fn name(&self) -> &str {
        "m20261026_000006_history_checkpoint_v5"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CheckpointV5 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        checkpoint::migrate_envelope(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        Ok(())
    }
}

/// Checkpoint Project bindings predate kind. Upgrade only at the named history boundary,
/// so ordinary WorkspaceRecord decoding remains strict and old saved paths remain authoritative.
struct ProjectKind {
    thread_id: String,
}
impl MigrationName for ProjectKind {
    fn name(&self) -> &str {
        PROJECT_KIND
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ProjectKind {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        crate::studio::producer_migration::project_kind(&mut migrated).map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct ModelAccess {
    thread_id: String,
}
impl MigrationName for ModelAccess {
    fn name(&self) -> &str {
        MODEL_ACCESS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ModelAccess {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        // Absence of explicit close remains absence; core Closed never invents Studio intent.
        crate::studio::agent_close::is_explicitly_closed(&migrated.state).map_err(conversion)?;
        crate::studio::delegation::migrate(&mut migrated.state).map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct WorkspaceReceipt {
    thread_id: String,
}

/// Explicit representation maintenance also runs for databases that already applied workspace v2.
struct ReviewReceipt {
    thread_id: String,
}
impl MigrationName for ReviewReceipt {
    fn name(&self) -> &str {
        REVIEW_RECEIPT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ReviewReceipt {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        WorkspaceReceipt {
            thread_id: self.thread_id.clone(),
        }
        .up(manager)
        .await
    }
}
impl MigrationName for WorkspaceReceipt {
    fn name(&self) -> &str {
        WORKSPACE_RECEIPT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for WorkspaceReceipt {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        crate::studio::workspace_receipt::migration::upgrade(&mut migrated.state)
            .map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct ExecutionIdentity {
    thread_id: String,
    candidate: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
}
impl MigrationName for ExecutionIdentity {
    fn name(&self) -> &str {
        EXECUTION_IDENTITY
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ExecutionIdentity {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let (original, migrated) = self.candidate.as_deref().ok_or_else(|| {
            DbErr::Migration("execution identity requires explicit recovery preparation".into())
        })?;
        let db = manager.get_connection();
        let current = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
            .ok_or_else(|| DbErr::Migration("recovery checkpoint is absent".into()))?;
        if serde_json::to_vec(&current).map_err(|error| DbErr::Migration(error.to_string()))?
            != serde_json::to_vec(original).map_err(|error| DbErr::Migration(error.to_string()))?
        {
            return Err(DbErr::Migration(
                "checkpoint changed during recovery migration; original data preserved".into(),
            ));
        }
        checkpoint::write_representation(db, original, migrated)
            .await
            .map_err(conversion)
    }
}

struct BotRootRelocation {
    thread_id: String,
    mapping: Option<crate::studio::startup::storage_layout::bot_roots::BotRootMove>,
}
impl MigrationName for BotRootRelocation {
    fn name(&self) -> &str {
        BOT_ROOT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for BotRootRelocation {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let Some(mapping) = &self.mapping else {
            return Ok(());
        };
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        crate::studio::producer_migration::relocate_bot_checkpoint(&mut migrated, mapping)
            .map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

#[cfg(test)]
mod atomic_tests {
    use super::super::timeline::ChatCursor;
    use super::*;

    const THREAD: &str = "atomic-migration";

    /// Freeze the last published timeline format as input to the demand migration.
    struct PublishedV11;

    impl MigratorTraitSelf for PublishedV11 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                execution_identity: None,
                bot_root: None,
            }
            .migrations()
            .into_iter()
            .filter(|step| {
                !matches!(
                    step.name(),
                    BACKGROUND_RESULTS
                        | MEMBER_READ_METADATA
                        | TIMELINE_THINKING_SUMMARY
                        | TIMELINE_BACKGROUND_TAIL
                        | SOURCE_CLASSIFICATION
                        | COMPLETION_BOUNDARY
                        | IMMUTABLE_COMPLETION_RUNS
                        | WORK_SNAPSHOTS
                        | DISPLAY_BLOCK_ORDER
                )
            })
            .filter(|migration| {
                !matches!(
                    migration.name(),
                    DEMAND_CONVERSATION | MODEL_ROUTE_HEAD | ATOM_METADATA | TIMELINE_ITEMS
                )
            })
            .collect()
        }
    }

    struct PublishedV9 {
        checkpoint: Option<pl_core::thread::ThreadCheckpoint>,
    }

    impl MigratorTraitSelf for PublishedV9 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                execution_identity: self.checkpoint.as_ref().map(|checkpoint| {
                    std::sync::Arc::new((checkpoint.clone(), checkpoint.clone()))
                }),
                bot_root: None,
            }
            .migrations()
            .into_iter()
            .filter(|step| {
                !matches!(
                    step.name(),
                    BACKGROUND_RESULTS
                        | MEMBER_READ_METADATA
                        | TIMELINE_THINKING_SUMMARY
                        | TIMELINE_BACKGROUND_TAIL
                        | SOURCE_CLASSIFICATION
                        | COMPLETION_BOUNDARY
                        | IMMUTABLE_COMPLETION_RUNS
                        | WORK_SNAPSHOTS
                        | DISPLAY_BLOCK_ORDER
                )
            })
            .filter(|migration| {
                !matches!(
                    migration.name(),
                    ATOMIC_TIMELINE
                        | METERING_FACTS
                        | COMBINED_CONTENT
                        | DEMAND_CONVERSATION
                        | MODEL_ROUTE_HEAD
                        | ATOM_METADATA
                        | TIMELINE_ITEMS
                )
            })
            .collect()
        }
    }

    /// The two actually published v10 sources share a number, not a content boundary.
    /// Run the real named steps and official bookkeeping, excluding only the unpublished content.
    struct PublishedV10 {
        atomic: bool,
    }

    impl MigratorTraitSelf for PublishedV10 {
        fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
            Migrator {
                thread_id: THREAD.into(),
                execution_identity: None,
                bot_root: None,
            }
            .migrations()
            .into_iter()
            .filter(|step| {
                !matches!(
                    step.name(),
                    BACKGROUND_RESULTS
                        | MEMBER_READ_METADATA
                        | TIMELINE_THINKING_SUMMARY
                        | TIMELINE_BACKGROUND_TAIL
                        | SOURCE_CLASSIFICATION
                        | COMPLETION_BOUNDARY
                        | IMMUTABLE_COMPLETION_RUNS
                        | WORK_SNAPSHOTS
                        | DISPLAY_BLOCK_ORDER
                )
            })
            .filter(|migration| {
                migration.name() != COMBINED_CONTENT
                    && migration.name() != DEMAND_CONVERSATION
                    && migration.name() != MODEL_ROUTE_HEAD
                    && !matches!(migration.name(), ATOM_METADATA | TIMELINE_ITEMS)
                    && migration.name()
                        != if self.atomic {
                            METERING_FACTS
                        } else {
                            ATOMIC_TIMELINE
                        }
            })
            .collect()
        }
    }

    async fn v9(path: &Path, cold: bool) -> Result<DatabaseConnection> {
        let db = connect(path, crate::studio::paths::SqliteFileMode::Create).await?;
        let published = PublishedV9 { checkpoint: None };
        let content_steps = published
            .migrations()
            .iter()
            .position(|migration| is_lifecycle_migration(migration.name()))
            .context("published lifecycle boundary")?;
        published
            .up(&db, Some(u32::try_from(content_steps)?))
            .await?;
        if !cold {
            let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
                THREAD.into(),
                0,
                pl_core::thread::ThreadSnapshot::default(),
            )?;
            write_published_checkpoint(&db, &checkpoint).await?;
            // Lifecycle preparation may normalize the checkpoint before execution identity recovery.
            // Supply the actual post-preparation representation as the explicit recovery candidate.
            let lifecycle_steps = published
                .migrations()
                .iter()
                .position(|migration| migration.name() == EXECUTION_IDENTITY)
                .context("published execution boundary")?
                - content_steps;
            published
                .up(&db, Some(u32::try_from(lifecycle_steps)?))
                .await?;
            let checkpoint = checkpoint::read(&db, THREAD)
                .await?
                .context("prepared recovery checkpoint")?;
            PublishedV9 {
                checkpoint: Some(*checkpoint),
            }
            .up(&db, None)
            .await?;
        }
        assert_eq!(version(&db).await?, 9);
        Ok(db)
    }

    async fn applied(db: &DatabaseConnection, name: &str) -> Result<bool> {
        Ok(db
            .query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![name.into()],
            ))
            .await?
            .is_some())
    }

    /// Preserve structural identity and migration records as well as the selected source bodies.
    async fn schema_state(db: &DatabaseConnection) -> Result<Vec<String>> {
        let mut state = Vec::new();
        for query in [
            "SELECT json_array(type,name,tbl_name,rootpage,sql) AS fact FROM main.sqlite_schema ORDER BY type,name",
            "SELECT json_array(id,schema_version,database_id,thread_id,applied_write_seq) AS fact FROM history_meta ORDER BY id",
            "SELECT json_array(version,applied_at) AS fact FROM seaql_migrations ORDER BY version",
        ] {
            for row in db.query_all_raw(statement(query, vec![])).await? {
                state.push(row.try_get("", "fact")?);
            }
        }
        Ok(state)
    }

    #[tokio::test]
    async fn atomic_timeline_rejects_v9_identity_column_collation_mismatch() -> Result<()> {
        for populated in [false, true] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), true).await?;
            db.execute_unprepared(
                "DROP TABLE history_items;
             CREATE TABLE history_items(
                ordinal INTEGER PRIMARY KEY,item_id TEXT COLLATE NOCASE NOT NULL,
                turn_id TEXT NOT NULL,kind TEXT NOT NULL,revision INTEGER NOT NULL,
                lifecycle TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
                payload TEXT NOT NULL,last_write_seq INTEGER NOT NULL);
             CREATE UNIQUE INDEX arbitrary_exact_identity ON history_items(item_id COLLATE BINARY)",
            )
            .await?;
            let mut original = Vec::new();
            if populated {
                for (ordinal, identity) in [(1, "A"), (2, "a")] {
                    let mut item = ThreadItem::completed_user_message(
                        identity.into(),
                        THREAD.into(),
                        String::new(),
                        format!("preserve {identity}"),
                        vec![],
                        17,
                    );
                    item.ordinal = ordinal;
                    item.revision = 1;
                    let payload = serde_json::to_string(&item)?;
                    db.execute_raw(statement(
                        "INSERT INTO history_items VALUES(?,?,'','text',1,'terminal',17,17,?,1)",
                        vec![
                            integer(ordinal)?.into(),
                            identity.into(),
                            payload.clone().into(),
                        ],
                    ))
                    .await?;
                    original.push(payload);
                }
                assert_eq!(
                    db.query_one_raw(statement(
                        "SELECT COUNT(*) AS hits FROM history_items WHERE item_id='A'",
                        vec![]
                    ))
                    .await?
                    .context("identity lookup")?
                    .try_get::<i64>("", "hits")?,
                    2,
                    "the existing index validation cannot guarantee point-read identity"
                );
            }
            let before = schema_state(&db).await?;
            // Check both cases before preparation: this is a structural defect even in an empty
            // table, not a duplicate-data check or an EXPLAIN-dependent query-plan assertion.
            let error = tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
                .await?
                .expect_err("v9 initialization must reject mismatched column/index comparison");
            assert!(format!("{error:#}").contains("history_items.item_id requires BINARY"));
            assert_eq!(schema_state(&db).await?, before);
            assert_eq!(version(&db).await?, 9);
            assert!(!applied(&db, ATOMIC_TIMELINE).await?);
            assert!(
                !SchemaManager::new(&db)
                    .has_table("timeline_records")
                    .await?
            );
            let preserved = db
                .query_all_raw(statement(
                    "SELECT payload FROM history_items ORDER BY ordinal",
                    vec![],
                ))
                .await?
                .into_iter()
                .map(|row| row.try_get::<String>("", "payload"))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            assert_eq!(preserved, original);
            db.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_rejects_current_identity_column_collation_mismatch() -> Result<()> {
        for populated in [false, true] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), true).await?;
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            db.execute_unprepared(
            "DROP TABLE timeline_records;
             CREATE TABLE timeline_records(
                append_seq INTEGER PRIMARY KEY,record_id TEXT COLLATE NOCASE NOT NULL,
                turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,
                kind TEXT NOT NULL,payload TEXT NOT NULL);
             CREATE UNIQUE INDEX arbitrary_exact_identity ON timeline_records(record_id COLLATE BINARY)",
        )
        .await?;
            if populated {
                db.execute_unprepared(
                "INSERT INTO timeline_records VALUES(1,'A',NULL,NULL,NULL,'text','{\"body\":\"upper\"}');
                 INSERT INTO timeline_records VALUES(2,'a',NULL,NULL,NULL,'text','{\"body\":\"lower\"}')",
            )
            .await?;
                assert_eq!(
                    db.query_one_raw(statement(
                        "SELECT COUNT(*) AS hits FROM timeline_records WHERE record_id='A'",
                        vec![]
                    ))
                    .await?
                    .context("identity lookup")?
                    .try_get::<i64>("", "hits")?,
                    2,
                    "two exact identities alias in the default column comparison"
                );
            }
            let before = schema_state(&db).await?;
            let original = db
                .query_all_raw(statement(
                    "SELECT payload FROM timeline_records ORDER BY append_seq",
                    vec![],
                ))
                .await?
                .into_iter()
                .map(|row| row.try_get::<String>("", "payload"))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            // A newly opened cold reader does not run preflight. Its own first-connection gate
            // must reject the mismatch before publishing a trusted HistoryConnection.
            let cold = HistoryStore::open(&directory.path().join("history.sqlite"), THREAD).await?;
            let error = tokio::time::timeout(Duration::from_secs(10), cold.publication_seed())
                .await?
                .expect_err("independent cold reader must reject mismatched comparison");
            assert!(format!("{error:#}").contains("timeline_records.record_id requires BINARY"));
            assert!(cold.state.reader.get().is_none());
            assert!(cold.state.writer.get().is_none());
            assert_eq!(schema_state(&db).await?, before);
            assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
            assert!(applied(&db, ATOMIC_TIMELINE).await?);
            let preserved = db
                .query_all_raw(statement(
                    "SELECT payload FROM timeline_records ORDER BY append_seq",
                    vec![],
                ))
                .await?
                .into_iter()
                .map(|row| row.try_get::<String>("", "payload"))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            assert_eq!(preserved, original);
            db.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_checks_nonunique_turn_identity_and_kind_comparison() -> Result<()> {
        for current in [false, true] {
            for column in ["turn_id", "kind"] {
                for populated in [false, true] {
                    let directory = tempfile::tempdir()?;
                    let path = directory.path().join("history.sqlite");
                    let db = v9(&path, true).await?;
                    if current {
                        prepare(&db, THREAD, Preparation::Schema, None).await?;
                    }
                    let turn_collation = if column == "turn_id" {
                        "COLLATE NOCASE"
                    } else {
                        ""
                    };
                    let kind_collation = if column == "kind" {
                        "COLLATE NOCASE"
                    } else {
                        ""
                    };
                    db.execute_unprepared(&format!(
                        "DROP TABLE history_items;
                     CREATE TABLE history_items(
                        ordinal INTEGER PRIMARY KEY,item_id TEXT NOT NULL UNIQUE,
                        turn_id TEXT {turn_collation} NOT NULL,kind TEXT {kind_collation} NOT NULL,
                        revision INTEGER NOT NULL,lifecycle TEXT NOT NULL,
                        created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
                        payload TEXT NOT NULL,last_write_seq INTEGER NOT NULL)"
                    ))
                    .await?;
                    let mut original = Vec::new();
                    if populated {
                        let mut item = ThreadItem::completed_user_message(
                            "input".into(),
                            THREAD.into(),
                            "Turn-A".into(),
                            "preserve original body".into(),
                            vec![],
                            17,
                        );
                        item.ordinal = 1;
                        item.revision = 1;
                        let payload = serde_json::to_string(&item)?;
                        db.execute_raw(statement(
                        "INSERT INTO history_items VALUES(1,'input','Turn-A','text',1,'terminal',17,17,?,1)",
                        vec![payload.clone().into()],
                    ))
                    .await?;
                        original.push(payload);
                    }
                    let before = schema_state(&db).await?;
                    let error: anyhow::Error = if current {
                        let cold = HistoryStore::open(&path, THREAD).await?;
                        let error = tokio::time::timeout(
                            Duration::from_secs(10),
                            cold.publication_seed(),
                        )
                        .await?
                        .expect_err(
                            "cold reader must check nonunique identity and selector columns",
                        );
                        assert!(cold.state.reader.get().is_none());
                        error.into()
                    } else {
                        tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
                            .await?
                            .expect_err(
                                "preparation must check nonunique identity and selector columns",
                            )
                    };
                    assert!(
                        format!("{error:#}")
                            .contains(&format!("history_items.{column} requires BINARY"))
                    );
                    assert_eq!(schema_state(&db).await?, before);
                    assert_eq!(
                        version(&db).await?,
                        if current { HISTORY_SCHEMA_VERSION } else { 9 }
                    );
                    assert_eq!(applied(&db, ATOMIC_TIMELINE).await?, current);
                    assert_eq!(
                        SchemaManager::new(&db)
                            .has_table("timeline_records")
                            .await?,
                        current
                    );
                    let preserved = db
                        .query_all_raw(statement(
                            "SELECT payload FROM history_items ORDER BY ordinal",
                            vec![],
                        ))
                        .await?
                        .into_iter()
                        .map(|row| row.try_get::<String>("", "payload"))
                        .collect::<std::result::Result<Vec<_>, _>>()?;
                    assert_eq!(preserved, original);
                    db.close().await?;
                }
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_rejects_nonunique_ordinals_before_backfill_without_mutation()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        db.execute_unprepared(
            "DROP TABLE history_items;
         CREATE TABLE history_items (
            ordinal INTEGER NOT NULL,
            item_id TEXT NOT NULL UNIQUE,
            turn_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            revision INTEGER NOT NULL,
            lifecycle TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK(json_valid(payload)),
            last_write_seq INTEGER NOT NULL
         )",
        )
        .await?;
        // All 260 facts have the same ordinal: a LIMIT 128 + ordinal > last query would lose
        // 132 bodies. They are otherwise valid, complete facts with distinct stable identities.
        let mut original = Vec::new();
        for index in 0..260 {
            let mut item = ThreadItem::completed_user_message(
                format!("input-{index:03}"),
                THREAD.into(),
                String::new(),
                format!("preserve body {index}"),
                vec![],
                17,
            );
            item.ordinal = 7;
            item.revision = 1;
            let payload = serde_json::to_string(&item)?;
            db.execute_raw(statement(
                "INSERT INTO history_items VALUES(7,?,'','text',1,'terminal',17,17,?,1)",
                vec![item.id.into(), payload.clone().into()],
            ))
            .await?;
            original.push(payload);
        }
        assert_eq!(
            db.query_one_raw(statement("PRAGMA quick_check", vec![]))
                .await?
                .context("quick_check")?
                .try_get_by_index::<String>(0)?,
            "ok",
            "integrity checks alone do not establish application key constraints"
        );
        let before = schema_state(&db).await?;
        let error = prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .expect_err("missing ordinal primary key must fail before content DDL");
        assert!(format!("{error:#}").contains("history_items primary key"));
        assert_eq!(schema_state(&db).await?, before);
        assert_eq!(version(&db).await?, 9);
        assert!(!applied(&db, ATOMIC_TIMELINE).await?);
        assert!(
            !SchemaManager::new(&db)
                .has_table("timeline_records")
                .await?
        );
        let preserved = db
            .query_all_raw(statement(
                "SELECT payload FROM history_items ORDER BY item_id",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "payload"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(preserved, original);
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_identity_affinity_matches_sqlite_type_precedence() -> Result<()> {
        use super::super::timeline::codec::{completion_draft, encode_record};
        use super::super::timeline::frozen::{ChatItem, ChatItemParts};

        for current in [false, true] {
            for (declared, allowed, strict) in [
                ("NUMERIC", false, false),
                ("CHARINT", false, false),
                ("TEXT POINT", false, false),
                ("INTEGER", false, false),
                ("REAL", false, false),
                ("BLOB", false, false),
                ("", false, false),
                ("STRING", false, false),
                ("ANY", false, false),
                ("TEXT", true, false),
                ("varchar(32)", true, false),
                ("CLOB", true, false),
                ("BLOB TEXT", true, false),
                ("TEXT", true, true),
                ("ANY", false, true),
            ] {
                for populated in [false, true] {
                    let directory = tempfile::tempdir()?;
                    let path = directory.path().join("history.sqlite");
                    let db = v9(&path, true).await?;
                    if current {
                        PublishedV11.up(&db, Some(3)).await?;
                        assert_eq!(version(&db).await?, 11);
                    }
                    let suffix = if strict { " STRICT" } else { "" };
                    let (table, identity, sequence) = if current {
                        db.execute_unprepared(&format!(
                            "DROP TABLE timeline_records;
                         CREATE TABLE timeline_records(
                            append_seq INTEGER PRIMARY KEY,record_id {declared} NOT NULL UNIQUE,
                            turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,
                            kind TEXT NOT NULL,payload TEXT NOT NULL){suffix}"
                        ))
                        .await?;
                        ("timeline_records", "record_id", "append_seq")
                    } else {
                        db.execute_unprepared(&format!(
                        "DROP TABLE history_items;
                         CREATE TABLE history_items(
                            ordinal INTEGER PRIMARY KEY,item_id {declared} NOT NULL UNIQUE,
                            turn_id TEXT NOT NULL,kind TEXT NOT NULL,revision INTEGER NOT NULL,
                            lifecycle TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
                            payload TEXT NOT NULL,last_write_seq INTEGER NOT NULL){suffix}"
                    )).await?;
                        ("history_items", "item_id", "ordinal")
                    };
                    if populated {
                        // The numeric-affinity fixture accepts one original '01' payload; attempting
                        // to insert '1' there would already collapse its identity. Valid TEXT variants
                        // must instead retain both independently, including after v9 backfill.
                        let identities = if allowed {
                            &["01", "1"][..]
                        } else {
                            &["01"][..]
                        };
                        for (index, id) in identities.iter().enumerate() {
                            let mut item = ThreadItem::completed_user_message(
                                (*id).into(),
                                THREAD.into(),
                                String::new(),
                                format!("preserve body {id}"),
                                vec![],
                                17,
                            );
                            item.ordinal = index as u64 + 1;
                            item.revision = 1;
                            if current {
                                let draft = completion_draft(&item, 1)?;
                                let record = ChatItem::complete(ChatItemParts {
                                    item_id: draft.item_id,
                                    turn_id: draft.turn_id,
                                    append_seq: index as u64 + 1,
                                    source_effect_seq: draft.source_effect_seq,
                                    sealed_at: draft.sealed_at,
                                    fields: draft.fields,
                                    meta: draft.meta,
                                });
                                db.execute_raw(statement(
                                    "INSERT INTO timeline_records VALUES(?,?,NULL,1,17,'text',?)",
                                    vec![
                                        integer(record.append_seq)?.into(),
                                        (*id).into(),
                                        encode_record(&record)?.into(),
                                    ],
                                ))
                                .await?;
                            } else {
                                db.execute_raw(statement(
                                "INSERT INTO history_items VALUES(?,?,'','text',1,'terminal',17,17,?,1)",
                                vec![integer(item.ordinal)?.into(), (*id).into(), serde_json::to_string(&item)?.into()],
                            )).await?;
                            }
                        }
                    }
                    let select = format!(
                        "SELECT json_array({sequence},{identity},payload) AS fact FROM {table} ORDER BY {sequence}"
                    );
                    let original = db
                        .query_all_raw(statement(&select, vec![]))
                        .await?
                        .into_iter()
                        .map(|row| row.try_get::<String>("", "fact"))
                        .collect::<std::result::Result<Vec<_>, _>>()?;
                    let before = schema_state(&db).await?;
                    let cold = HistoryStore::open(&path, THREAD).await?;
                    // Timeline is a migration input now. Both published shapes must pass the
                    // preparation trust gate before a current reader can observe their records.
                    let result =
                        tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
                            .await?;
                    if allowed {
                        result?;
                        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
                        let expected = if populated { 2 } else { 0 };
                        assert_eq!(cold.publication_seed().await?.head_seq, expected);
                        if populated {
                            for id in ["01", "1"] {
                                let hits = db
                                .query_one_raw(statement(
                                    &format!(
                                        "SELECT COUNT(*) AS hits FROM {table} WHERE {identity}=?"
                                    ),
                                    vec![id.into()],
                                ))
                                .await?
                                .context("exact identity lookup")?
                                .try_get::<i64>("", "hits")?;
                                assert_eq!(hits, 1, "{declared} must keep {id} distinct");
                                assert_eq!(
                                    cold.read_chat_item(id)
                                        .await?
                                        .context("completed identity")?
                                        .header
                                        .item_id,
                                    id
                                );
                            }
                        }
                    } else {
                        let error =
                            result.expect_err("non-TEXT identity affinity must be rejected");
                        assert!(
                            format!("{error:#}")
                                .contains(&format!("{table}.{identity} requires TEXT affinity")),
                            "declared={declared:?}, strict={strict}, current={current}: {error:#}"
                        );
                        assert_eq!(schema_state(&db).await?, before);
                        assert_eq!(version(&db).await?, if current { 11 } else { 9 });
                        assert_eq!(applied(&db, ATOMIC_TIMELINE).await?, current);
                        assert_eq!(
                            SchemaManager::new(&db)
                                .has_table("timeline_records")
                                .await?,
                            current
                        );
                        assert!(cold.state.reader.get().is_none());
                    }
                    let preserved = db
                        .query_all_raw(statement(&select, vec![]))
                        .await?
                        .into_iter()
                        .map(|row| row.try_get::<String>("", "fact"))
                        .collect::<std::result::Result<Vec<_>, _>>()?;
                    assert_eq!(preserved, original);
                    db.close().await?;
                }
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_validates_all_v9_write_keys_and_semantic_unique_indexes() -> Result<()>
    {
        // CTAS preserves every queried column while removing constraints. Every listed table has a
        // key used by this history writer or its checkpoint transaction, even when the table is empty.
        for table in [
            "history_meta",
            "history_items",
            "history_turns",
            "history_input_identities",
            "history_fact_receipts",
            "history_message_identities",
            "session_checkpoint",
            "session_costs",
            "current_context",
            "history_tool_tasks",
        ] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), true).await?;
            db.execute_unprepared(&format!(
                "CREATE TABLE missing_keys AS SELECT * FROM {table};
             DROP TABLE {table}; ALTER TABLE missing_keys RENAME TO {table}"
            ))
            .await?;
            let before = schema_state(&db).await?;
            let error = prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .expect_err("same columns without primary keys must not be adopted");
            assert!(format!("{error:#}").contains(&format!("table {table} primary key")));
            assert_eq!(schema_state(&db).await?, before);
            assert!(
                !SchemaManager::new(&db)
                    .has_table("timeline_records")
                    .await?
            );
            db.close().await?;
        }
        // Rowid composite primary keys are not implicitly NOT NULL. Exercise each component
        // independently, empty and populated, through both production trust boundaries.
        for current in [false, true] {
            for (table, keys) in [
                ("history_fact_receipts", ["item_id", "revision"]),
                ("session_costs", ["purpose", "currency"]),
            ] {
                for missing in keys {
                    for populated in [false, true] {
                        let directory = tempfile::tempdir()?;
                        let path = directory.path().join("history.sqlite");
                        let db = v9(&path, true).await?;
                        if current {
                            prepare(&db, THREAD, Preparation::Schema, None).await?;
                        }
                        let first_notnull = if missing == keys[0] { "" } else { "NOT NULL" };
                        let second_notnull = if missing == keys[1] { "" } else { "NOT NULL" };
                        let (ddl, insert, select) = if table == "history_fact_receipts" {
                            let values = if missing == "item_id" {
                                "NULL,1"
                            } else {
                                "'receipt',NULL"
                            };
                            (
                            format!(
                                "CREATE TABLE history_fact_receipts(
                                    item_id TEXT {first_notnull},revision INTEGER {second_notnull},
                                    kind TEXT NOT NULL,digest TEXT NOT NULL,payload TEXT NOT NULL,
                                    last_write_seq INTEGER NOT NULL,PRIMARY KEY(item_id,revision))"
                            ),
                            format!(
                                "INSERT INTO history_fact_receipts VALUES({values},'interaction','digest','{{\"body\":\"first\"}}',1);
                                 INSERT INTO history_fact_receipts VALUES({values},'interaction','digest','{{\"body\":\"second\"}}',1)"
                            ),
                            "SELECT json_array(item_id,revision,kind,digest,payload,last_write_seq) AS fact FROM history_fact_receipts ORDER BY rowid",
                        )
                        } else {
                            let values = if missing == "purpose" {
                                "NULL,'CNY'"
                            } else {
                                "'null',NULL"
                            };
                            (
                                format!(
                                    "CREATE TABLE session_costs(
                                    purpose TEXT {first_notnull},currency TEXT {second_notnull},
                                    amount REAL NOT NULL,PRIMARY KEY(purpose,currency))"
                                ),
                                format!(
                                    "INSERT INTO session_costs VALUES({values},1.25);
                                 INSERT INTO session_costs VALUES({values},2.5)"
                                ),
                                "SELECT json_array(purpose,currency,amount) AS fact FROM session_costs ORDER BY rowid",
                            )
                        };
                        db.execute_unprepared(&format!("DROP TABLE {table}; {ddl}"))
                            .await?;
                        if populated {
                            db.execute_unprepared(&insert).await?;
                        }
                        let original = db
                            .query_all_raw(statement(select, vec![]))
                            .await?
                            .into_iter()
                            .map(|row| row.try_get::<String>("", "fact"))
                            .collect::<std::result::Result<Vec<_>, _>>()?;
                        assert_eq!(original.len(), if populated { 2 } else { 0 });
                        let before = schema_state(&db).await?;
                        let error: anyhow::Error = if current {
                            let cold = HistoryStore::open(&path, THREAD).await?;
                            let error = tokio::time::timeout(
                                Duration::from_secs(10),
                                cold.publication_seed(),
                            )
                            .await?
                            .expect_err("cold reader must reject nullable composite key");
                            assert!(cold.state.reader.get().is_none());
                            error.into()
                        } else {
                            tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
                                .await?
                                .expect_err("v9 preparation must reject nullable composite key")
                        };
                        assert!(
                        format!("{error:#}").contains(&format!(
                            "table {table} composite primary key column {missing} requires NOT NULL"
                        )),
                        "{error:#}"
                    );
                        assert_eq!(schema_state(&db).await?, before);
                        assert_eq!(
                            version(&db).await?,
                            if current { HISTORY_SCHEMA_VERSION } else { 9 }
                        );
                        assert_eq!(applied(&db, ATOMIC_TIMELINE).await?, current);
                        assert_eq!(
                            SchemaManager::new(&db)
                                .has_table("timeline_records")
                                .await?,
                            current
                        );
                        let preserved = db
                            .query_all_raw(statement(select, vec![]))
                            .await?
                            .into_iter()
                            .map(|row| row.try_get::<String>("", "fact"))
                            .collect::<std::result::Result<Vec<_>, _>>()?;
                        assert_eq!(preserved, original);
                        db.close().await?;
                    }
                }
            }
        }
        for unique_index in [
            "",
            "CREATE UNIQUE INDEX arbitrary ON history_items(item_id) WHERE ordinal>0",
            "CREATE UNIQUE INDEX arbitrary ON history_items(lower(item_id))",
            "CREATE UNIQUE INDEX arbitrary ON history_items(item_id,turn_id)",
            "CREATE UNIQUE INDEX arbitrary ON history_items(item_id COLLATE NOCASE)",
            "CREATE INDEX arbitrary ON history_items(item_id)",
            "CREATE UNIQUE INDEX arbitrary ON history_items(item_id)",
        ] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), true).await?;
            db.execute_unprepared(
                "DROP TABLE history_items;
             CREATE TABLE history_items (
                ordinal INTEGER PRIMARY KEY,item_id TEXT NOT NULL,turn_id TEXT NOT NULL,
                kind TEXT NOT NULL,revision INTEGER NOT NULL,lifecycle TEXT NOT NULL,
                created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,payload TEXT NOT NULL,
                last_write_seq INTEGER NOT NULL)",
            )
            .await?;
            if !unique_index.is_empty() {
                db.execute_unprepared(unique_index).await?;
            }
            let before = schema_state(&db).await?;
            let result = prepare(&db, THREAD, Preparation::Schema, None).await;
            if unique_index == "CREATE UNIQUE INDEX arbitrary ON history_items(item_id)" {
                result?;
                validate_current(&db, THREAD).await?;
            } else {
                assert!(
                    result.is_err(),
                    "must reject insufficient index: {unique_index}"
                );
                assert_eq!(schema_state(&db).await?, before);
                assert!(
                    !SchemaManager::new(&db)
                        .has_table("timeline_records")
                        .await?
                );
            }
            db.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_rejects_damaged_source_keys_without_repair() -> Result<()> {
        for key_ddl in [
            "append_seq INTEGER,record_id TEXT NOT NULL UNIQUE",
            "append_seq INT PRIMARY KEY,record_id TEXT NOT NULL UNIQUE",
            "append_seq INTEGER PRIMARY KEY DESC,record_id TEXT NOT NULL UNIQUE",
            "append_seq INTEGER PRIMARY KEY,record_id TEXT NOT NULL",
            "append_seq INTEGER PRIMARY KEY,record_id TEXT UNIQUE",
        ] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), true).await?;
            PublishedV11.up(&db, Some(3)).await?;
            db.execute_unprepared(&format!(
                "DROP TABLE timeline_records;
             CREATE TABLE timeline_records(
                {key_ddl},turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,
                kind TEXT NOT NULL,payload TEXT NOT NULL);
             INSERT INTO timeline_records VALUES(1,'preserved',NULL,NULL,NULL,'text','{{}}')"
            ))
            .await?;
            let before = schema_state(&db).await?;
            assert!(validate_tables(&db).await.is_err());
            assert!(
                prepare(&db, THREAD, Preparation::Schema, None)
                    .await
                    .is_err()
            );
            assert_eq!(schema_state(&db).await?, before);
            assert_eq!(version(&db).await?, 11);
            assert!(applied(&db, ATOMIC_TIMELINE).await?);
            let payload: String = db
                .query_one_raw(statement(
                    "SELECT payload FROM timeline_records WHERE record_id='preserved'",
                    vec![],
                ))
                .await?
                .context("unchanged damaged timeline source")?
                .try_get("", "payload")?;
            assert_eq!(payload, "{}");
            db.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_upgrades_complete_v9_and_pending_cold_store() -> Result<()> {
        for cold in [false, true] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), cold).await?;
            preflight(&db, THREAD).await?;
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
            assert!(applied(&db, ATOMIC_TIMELINE).await?);
            assert!(applied(&db, METERING_FACTS).await?);
            assert!(applied(&db, COMBINED_CONTENT).await?);
            assert_eq!(applied(&db, PROJECT_KIND).await?, !cold);
            assert_eq!(applied(&db, MODEL_ACCESS).await?, !cold);
            validate_current(&db, THREAD).await?;
            assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 0);
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 0);
            db.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn combined_content_upgrades_both_published_v10_sources_without_rewriting_facts()
    -> Result<()> {
        use super::super::timeline::codec::completion_draft;
        use super::super::timeline::frozen::{ChatItem, ChatItemParts};

        for atomic in [false, true] {
            let directory = tempfile::tempdir()?;
            let path = directory.path().join("history.sqlite");
            let db = v9(&path, true).await?;
            let store = HistoryStore::open(&path, THREAD).await?;
            let mut input = ThreadItem::completed_user_message(
                "original-input".into(),
                THREAD.into(),
                String::new(),
                "正文\n  keep exact bytes".into(),
                vec![],
                17,
            );
            input.ordinal = 41;
            input.revision = 3;
            store.upsert_item(&db, 7, input.clone()).await?;
            let mut state = pl_core::thread::ThreadSnapshot {
                commit_sequence: 7,
                ..Default::default()
            };
            state.usage_summary.applied_sequence = 7;
            state.usage_summary.totals.inference_count = 3;
            state.usage_summary.totals.prompt_tokens = 103;
            state.usage_summary.totals.completion_tokens = 29;
            state.usage_summary.totals.total_tokens = 132;
            state
                .usage_summary
                .pricing
                .estimated_costs
                .push(pl_core::thread::UsageCost {
                    currency: "USD".into(),
                    amount: 1.25,
                });
            let saved = pl_core::thread::ThreadCheckpoint::capture(THREAD.into(), 7, state)?;
            write_published_checkpoint(&db, &saved).await?;
            db.execute_unprepared(
                "UPDATE history_meta SET applied_write_seq=7;
             INSERT INTO session_costs VALUES('main','USD',1.25)",
            )
            .await?;
            // Encode the old schema-5 body, not just an old header on a current usage layout.
            let row = db
                .query_one_raw(statement("SELECT payload FROM session_checkpoint", vec![]))
                .await?
                .context("saved checkpoint")?;
            let mut legacy: serde_json::Value =
                serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
            super::super::legacy_usage::flatten(&mut legacy);
            legacy["state"]["usageSummary"]["turnDecodeMillis"] = 99.into();
            legacy["schemaVersion"] = 5.into();
            let payload = serde_json::to_string(&legacy)?;
            db.execute_raw(statement(
                "UPDATE session_checkpoint SET payload=?,payload_hash=?",
                vec![
                    payload.clone().into(),
                    pl_core::context::content_hash(payload.as_bytes()).into(),
                ],
            ))
            .await?;

            PublishedV10 { atomic }.up(&db, Some(1)).await?;
            assert_eq!(version(&db).await?, 10);
            assert_eq!(applied(&db, ATOMIC_TIMELINE).await?, atomic);
            assert_eq!(applied(&db, METERING_FACTS).await?, !atomic);
            assert!(!applied(&db, COMBINED_CONTENT).await?);
            if atomic {
                // A completion published after backfill has no legacy source row. It must survive
                // metering byte-for-byte, with its original identity, sequence and provenance.
                let complete = ThreadItem::completed_user_message(
                    "frozen-only".into(),
                    THREAD.into(),
                    String::new(),
                    "完整原子载荷 ".repeat(4096),
                    vec![],
                    23,
                );
                let draft = completion_draft(&complete, 7)?;
                let record = ChatItem::complete(ChatItemParts {
                    item_id: draft.item_id,
                    turn_id: draft.turn_id,
                    append_seq: 2,
                    source_effect_seq: draft.source_effect_seq,
                    sealed_at: draft.sealed_at,
                    fields: draft.fields,
                    meta: draft.meta,
                });
                super::super::timeline::append_records(&db, THREAD, &[record], true).await?;
            }
            preflight(&db, THREAD).await?;
            assert!(
                validate_current(&db, THREAD).await.is_err(),
                "v10 is never a normal-reader format"
            );
            let identity_before = db.query_one_raw(statement(
            "SELECT json_array(database_id,thread_id,applied_write_seq) AS fact FROM history_meta",
            vec![],
        )).await?.context("source identity")?.try_get::<String>("", "fact")?;
            let items_before = rows_as_facts(&db,
            "SELECT json_array(ordinal,item_id,revision,payload,last_write_seq) AS fact FROM history_items ORDER BY ordinal"
        ).await?;
            let frozen_before = if atomic {
                rows_as_facts(&db,
                "SELECT json_array(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload) AS fact FROM timeline_records ORDER BY append_seq"
            ).await?
            } else {
                Vec::new()
            };
            let metering_before = if !atomic {
                Some(
                    rows_as_facts(
                        &db,
                        "SELECT json_array(payload,payload_hash) AS fact FROM session_checkpoint",
                    )
                    .await?,
                )
            } else {
                None
            };

            // Real content preparation must run the missing step from either published source.
            // A later failure leaves that step committed, never a partially published combination.
            db.execute_unprepared(
            "CREATE TRIGGER fail_combined_marker BEFORE UPDATE OF schema_version ON history_meta
             WHEN NEW.schema_version=11
             BEGIN SELECT RAISE(ABORT,'injected combined marker failure'); END",
        )
        .await?;
            let error = prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .expect_err("combination publication must be transactional");
            assert!(format!("{error:#}").contains("injected combined marker failure"));
            assert_eq!(version(&db).await?, 10);
            assert!(applied(&db, ATOMIC_TIMELINE).await?);
            assert!(applied(&db, METERING_FACTS).await?);
            let before_failure = schema_state(&db).await?;
            let error = prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .expect_err("failed combination must be retryable without rebuilding content");
            assert!(format!("{error:#}").contains("injected combined marker failure"));
            assert_eq!(schema_state(&db).await?, before_failure);
            assert!(!applied(&db, COMBINED_CONTENT).await?);
            db.execute_unprepared("DROP TRIGGER fail_combined_marker")
                .await?;
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
            assert!(applied(&db, ATOMIC_TIMELINE).await?);
            assert!(applied(&db, METERING_FACTS).await?);
            assert!(applied(&db, COMBINED_CONTENT).await?);
            assert!(!applied(&db, PROJECT_KIND).await?);
            assert!(!applied(&db, MODEL_ACCESS).await?);
            let mut expected = saved.clone();
            expected.state.usage_summary.diagnostics.legacy_unknown = true;
            assert_eq!(
                serde_json::to_value(
                    checkpoint::read(&db, THREAD)
                        .await?
                        .context("upgraded checkpoint")?
                )?,
                serde_json::to_value(expected)?,
            );
            assert_eq!(rows_as_facts(&db,
            "SELECT json_array(database_id,thread_id,applied_write_seq) AS fact FROM history_meta"
        ).await?, [identity_before]);
            assert_eq!(rows_as_facts(&db,
            "SELECT json_array(ordinal,item_id,revision,payload,last_write_seq) AS fact FROM history_items ORDER BY ordinal"
        ).await?, items_before);
            assert_eq!(
                rows_as_facts(
                    &db,
                    "SELECT json_array(purpose,currency,amount) AS fact FROM session_costs"
                )
                .await?,
                [r#"["main","USD",1.25]"#]
            );
            let page = super::super::timeline::page(&db, THREAD, None, 2, 10).await?;
            assert_eq!(page.items.len(), if atomic { 2 } else { 1 });
            assert_eq!(page.items[0].item_id, "original-input");
            assert_eq!(page.items[0].append_seq, 1);
            assert_eq!(page.items[0].source_effect_seq, None);
            assert_eq!(page.items[0].sealed_at, None);
            assert_eq!(
                page.items[0]
                    .fields
                    .values()
                    .map(|field| field.block.text())
                    .collect::<Vec<_>>()
                    .join(""),
                "正文\n  keep exact bytes",
            );
            if atomic {
                assert_eq!(rows_as_facts(&db,
                "SELECT json_array(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload) AS fact FROM timeline_records ORDER BY append_seq"
            ).await?, frozen_before);
            }
            if let Some(before) = metering_before {
                assert_eq!(
                    rows_as_facts(
                        &db,
                        "SELECT json_array(payload,payload_hash) AS fact FROM session_checkpoint"
                    )
                    .await?,
                    before,
                    "already upgraded metering is not rewritten"
                );
            }
            let prepared = schema_state(&db).await?;
            prepare(&db, THREAD, Preparation::Schema, None).await?;
            assert_eq!(schema_state(&db).await?, prepared);
            db.close().await?;
        }
        Ok(())
    }

    async fn rows_as_facts(db: &DatabaseConnection, query: &str) -> Result<Vec<String>> {
        db.query_all_raw(statement(query, vec![]))
            .await?
            .into_iter()
            .map(|row| Ok(row.try_get("", "fact")?))
            .collect()
    }

    #[tokio::test]
    async fn atomic_timeline_preserves_published_v8_adoption() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        db.execute_unprepared(
            "DROP TABLE seaql_migrations;
         UPDATE history_meta SET schema_version=8;
         CREATE TABLE history_ordinals(item_id TEXT PRIMARY KEY,ordinal INTEGER NOT NULL)",
        )
        .await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        validate_current(&db, THREAD).await?;
        assert!(
            !SchemaManager::new(&db)
                .has_table("history_ordinals")
                .await?
        );
        assert!(applied(&db, RETIRE_ORDINALS).await?);
        assert!(applied(&db, ATOMIC_TIMELINE).await?);
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_rejects_marker_schema_and_identity_conflicts() -> Result<()> {
        for corruption in [
            "UPDATE history_meta SET schema_version=10",
            "INSERT INTO seaql_migrations(version,applied_at) VALUES('m20261027_000004_history_atomic_timeline',0)",
            "INSERT INTO seaql_migrations(version,applied_at) VALUES('m20261028_000001_history_metering_facts',0)",
            "INSERT INTO seaql_migrations(version,applied_at) VALUES('m20261028_000002_history_combined_content',0)",
            "DELETE FROM seaql_migrations WHERE version='m20261027_000001_history_retire_ordinals'",
            "CREATE TABLE timeline_records(append_seq INTEGER PRIMARY KEY)",
            "DROP TABLE history_tool_tasks",
            "UPDATE history_meta SET schema_version=999",
            "UPDATE history_meta SET thread_id='other-thread'",
        ] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), true).await?;
            db.execute_unprepared(corruption).await?;
            let before = schema_state(&db).await?;
            assert!(
                preflight(&db, THREAD).await.is_err(),
                "must reject {corruption}"
            );
            assert_eq!(schema_state(&db).await?, before);
            db.close().await?;
        }
        for corruption in [
            "DELETE FROM seaql_migrations WHERE version='m20261027_000004_history_atomic_timeline'",
            "DELETE FROM seaql_migrations WHERE version='m20261028_000001_history_metering_facts'",
            "DELETE FROM seaql_migrations WHERE version='m20261028_000002_history_combined_content'",
            "UPDATE history_meta SET schema_version=10",
            "UPDATE history_meta SET schema_version=9",
            "DROP TABLE timeline_records",
        ] {
            let directory = tempfile::tempdir()?;
            let db = v9(&directory.path().join("history.sqlite"), true).await?;
            PublishedV11.up(&db, Some(3)).await?;
            db.execute_unprepared(corruption).await?;
            let before = schema_state(&db).await?;
            assert!(
                preflight(&db, THREAD).await.is_err(),
                "must reject {corruption}"
            );
            assert_eq!(schema_state(&db).await?, before);
            db.close().await?;
        }
        for atomic in [false, true] {
            let shape_corruption = if atomic {
                "DROP TABLE timeline_records"
            } else {
                "CREATE TABLE timeline_records(append_seq INTEGER PRIMARY KEY)"
            };
            let source_corruption = if atomic {
                "DELETE FROM seaql_migrations WHERE version='m20261027_000004_history_atomic_timeline'"
            } else {
                "DELETE FROM seaql_migrations WHERE version='m20261028_000001_history_metering_facts'"
            };
            let data_corruption = if atomic {
                "INSERT INTO timeline_records VALUES(1,'damaged',NULL,NULL,NULL,'text','{}')"
            } else {
                "DROP TABLE history_tool_tasks"
            };
            for corruption in [
                shape_corruption,
                source_corruption,
                data_corruption,
                "INSERT INTO seaql_migrations(version,applied_at) VALUES('m20261028_000002_history_combined_content',0)",
                "DELETE FROM seaql_migrations WHERE version='m20261027_000001_history_retire_ordinals'",
                "UPDATE history_meta SET schema_version=11",
            ] {
                let directory = tempfile::tempdir()?;
                let db = v9(&directory.path().join("history.sqlite"), true).await?;
                PublishedV10 { atomic }.up(&db, Some(1)).await?;
                db.execute_unprepared(corruption).await?;
                let before = schema_state(&db).await?;
                assert!(
                    prepare(&db, THREAD, Preparation::Schema, None)
                        .await
                        .is_err(),
                    "must reject v10 atomic={atomic}: {corruption}",
                );
                assert_eq!(schema_state(&db).await?, before);
                if atomic && corruption == data_corruption {
                    assert_eq!(
                        rows_as_facts(&db, "SELECT payload AS fact FROM timeline_records").await?,
                        ["{}"],
                    );
                }
                db.close().await?;
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_ddl_marker_and_backfill_roll_back_then_retry() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        let mut input = ThreadItem::completed_user_message(
            "input".into(),
            THREAD.into(),
            String::new(),
            "保留正文\n  indentation".into(),
            vec![],
            17,
        );
        input.ordinal = 41;
        input.revision = 3;
        HistoryStore::open(&directory.path().join("unused.sqlite"), THREAD)
            .await?
            .upsert_item(&db, 1, input.clone())
            .await?;
        // Start at the supported metering-only boundary so the marker fault reaches the atomic
        // migration itself, after it has created and backfilled timeline_records.
        PublishedV10 { atomic: false }.up(&db, Some(1)).await?;
        db.execute_unprepared(
            "CREATE TRIGGER fail_atomic_marker BEFORE UPDATE OF schema_version ON history_meta
         WHEN NEW.schema_version=10
         BEGIN SELECT RAISE(ABORT,'injected atomic marker failure'); END",
        )
        .await?;
        let error = prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .expect_err("schema marker failure must roll back the whole content step");
        assert!(format!("{error:#}").contains("injected atomic marker failure"));
        assert_eq!(version(&db).await?, 10);
        assert!(applied(&db, METERING_FACTS).await?);
        assert!(
            !SchemaManager::new(&db)
                .has_table("timeline_records")
                .await?
        );
        assert!(!applied(&db, ATOMIC_TIMELINE).await?);
        let payload: String = db
            .query_one_raw(statement("SELECT payload FROM history_items", vec![]))
            .await?
            .context("original fact")?
            .try_get("", "payload")?;
        assert_eq!(serde_json::from_str::<ThreadItem>(&payload)?, input);
        db.execute_unprepared("DROP TRIGGER fail_atomic_marker")
            .await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 1);
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 1);
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_conversion_failure_preserves_source_and_retries() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), THREAD).await?;
        let mut items = Vec::new();
        for ordinal in [1, 2] {
            let mut item = ThreadItem::completed_user_message(
                format!("input-{ordinal}"),
                THREAD.into(),
                String::new(),
                format!("original body {ordinal}"),
                vec![],
                17,
            );
            item.ordinal = ordinal;
            item.revision = 1;
            store.upsert_item(&db, 1, item.clone()).await?;
            items.push(item);
        }
        let corrupt = r#"{"unexpected":"preserve this invalid source verbatim"}"#;
        db.execute_raw(statement(
            "UPDATE history_items SET payload=? WHERE ordinal=2",
            vec![corrupt.into()],
        ))
        .await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(version(&db).await?, 10);
        assert!(applied(&db, METERING_FACTS).await?);
        assert!(
            !SchemaManager::new(&db)
                .has_table("timeline_records")
                .await?
        );
        assert!(!applied(&db, ATOMIC_TIMELINE).await?);
        let saved: String = db
            .query_one_raw(statement(
                "SELECT payload FROM history_items WHERE ordinal=2",
                vec![],
            ))
            .await?
            .context("preserved invalid source")?
            .try_get("", "payload")?;
        assert_eq!(saved, corrupt);
        db.execute_raw(statement(
            "UPDATE history_items SET payload=? WHERE ordinal=2",
            vec![serde_json::to_string(&items[1])?.into()],
        ))
        .await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let page = super::super::timeline::page(&db, THREAD, None, 2, 10).await?;
        assert_eq!(
            page.items
                .iter()
                .map(|item| (item.item_id.as_str(), item.append_seq))
                .collect::<Vec<_>>(),
            [("input-1", 1), ("input-2", 2)]
        );
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn atomic_timeline_backfill_order_content_and_frozen_reads() -> Result<()> {
        use pl_protocol::{
            AttachmentModality, QueuedThreadTool, ThreadAttachment, ThreadContentLifecycle,
            ThreadTextChannel, ThreadTextItem, ThreadThinkingItem, ThreadToolInvocation,
            ThreadToolItem, ThreadToolState, ThreadToolUserInput, ThreadToolUserInputState,
            UserQuestion,
        };
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), THREAD).await?;
        let attachment = ThreadAttachment {
            id: "attachment-original".into(),
            modality: AttachmentModality::File,
            media_type: "text/plain".into(),
            filename: Some("原附件.txt".into()),
            width: None,
            height: None,
            byte_size: 19,
        };
        let mut input = ThreadItem::completed_user_message(
            "accepted".into(),
            THREAD.into(),
            String::new(),
            "原文\n  不裁剪".into(),
            vec![attachment.clone()],
            17,
        );
        input.ordinal = 20;
        input.revision = 1;
        input.updated_at = 9999;
        let thinking = ThreadItem::new(
            "thinking".into(),
            THREAD.into(),
            "turn".into(),
            30,
            1,
            18,
            9999,
            ThreadItemState::Thinking(ThreadThinkingItem::new(
                vec!["第一段".into(), "第二段".into()],
                vec![],
                ThreadContentLifecycle::completed(19),
            )),
        );
        let running = ThreadItem::new(
            "still-running".into(),
            THREAD.into(),
            "turn".into(),
            25,
            1,
            18,
            9999,
            ThreadItemState::Text(ThreadTextItem::new(
                ThreadTextChannel::Final,
                "尚未可靠完成".into(),
                vec![],
                ThreadContentLifecycle::streaming(),
            )),
        );
        let pending = ThreadItem::new(
            "pending-question".into(),
            THREAD.into(),
            "turn".into(),
            26,
            1,
            18,
            9999,
            ThreadItemState::Tool(
                ThreadToolItem::new(
                    ThreadToolInvocation::new("question-call".into(), "ask".into(), "{}".into()),
                    ThreadToolState::Queued(QueuedThreadTool),
                )
                .with_user_input(Some(ThreadToolUserInput::new(
                    "interaction".into(),
                    vec![UserQuestion {
                        id: "question".into(),
                        header: "待决".into(),
                        question: "尚未回答？".into(),
                        is_other: false,
                        is_secret: false,
                        options: None,
                    }],
                    ThreadToolUserInputState::Pending,
                ))),
            ),
        );
        // Insert out of order: migration order comes from the durable ordinal, not insertion order.
        for item in [&thinking, &running, &input, &pending] {
            store.upsert_item(&db, 7, item.clone()).await?;
        }
        let original: Vec<String> = db
            .query_all_raw(statement(
                "SELECT payload FROM history_items ORDER BY ordinal",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get("", "payload"))
            .collect::<std::result::Result<_, _>>()?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let page = super::super::timeline::page(&db, THREAD, None, 3, 10).await?;
        assert_eq!(page.items.len(), 3);
        assert!(!page.has_more);
        assert_eq!(page.items[0].item_id, input.id);
        assert_eq!(page.items[0].turn_id, None);
        for (position, item) in page.items.iter().enumerate() {
            assert_eq!(item.append_seq, position as u64 + 1);
            assert_eq!(
                item.source_effect_seq, None,
                "last_write_seq is not provenance"
            );
            assert_eq!(item.sealed_at, None, "updated_at is not first seal time");
        }
        let bodies = page
            .items
            .iter()
            .map(|item| {
                item.fields
                    .values()
                    .map(|field| field.block.text())
                    .collect::<Vec<_>>()
                    .join("")
            })
            .collect::<Vec<_>>();
        assert_eq!(bodies, ["原文\n  不裁剪", "第一段", "第二段"]);
        let input_meta = super::super::timeline::codec::TimelineMeta::for_item(&page.items[0])?;
        let super::super::timeline::descriptor::TimelineDescriptor::Text(text) =
            input_meta.descriptor
        else {
            anyhow::bail!("input completion lost its text descriptor");
        };
        assert_eq!(text.attachments, [attachment]);
        let after: Vec<String> = db
            .query_all_raw(statement(
                "SELECT payload FROM history_items ORDER BY ordinal",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get("", "payload"))
            .collect::<std::result::Result<_, _>>()?;
        assert_eq!(
            after, original,
            "content migration never rewrites execution facts"
        );
        let cursor = ChatCursor::of(
            &pl_core::chat::TimelineEpoch::new("migration-test")?,
            &page.items[2],
        );
        let older = super::super::timeline::page(&db, THREAD, Some(&cursor), 3, 1).await?;
        assert_eq!(older.items[0], page.items[1]);
        assert!(older.has_more);
        let catchup = super::super::timeline::page_after(&db, THREAD, 0, 2, 1).await?;
        assert_eq!(catchup.items, page.items[..1]);
        assert!(catchup.has_more);
        assert_eq!(
            super::super::timeline::read_item(&db, THREAD, &page.items[1].item_id).await?,
            Some(page.items[1].clone())
        );
        let mut invalid = cursor;
        invalid.item_id = "wrong-identity".into();
        assert!(
            super::super::timeline::page(&db, THREAD, Some(&invalid), 3, 1)
                .await
                .is_err()
        );
        assert!(
            super::super::timeline::page(&db, THREAD, None, 3, 0)
                .await
                .is_err()
        );
        super::super::timeline::append_records(&db, THREAD, &page.items, false).await?;
        let mut conflicting = page.items[0].clone();
        conflicting.sealed_at = Some(123456);
        assert!(
            super::super::timeline::append_records(&db, THREAD, &[conflicting], false)
                .await
                .is_err()
        );
        db.close().await?;
        Ok(())
    }
}
