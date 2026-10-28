//! Per-Thread durable timeline storage with keyset pagination.

use std::{
    path::{Path, PathBuf},
    time::Duration,
};

use crate::studio::runtime::chat_item::typed_item;
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatCursor, ChatError, ChatHistory, ChatHistoryPage, ChatItem};
use pl_protocol::thread::TimelineCursor;
use pl_protocol::{ThreadItem, ThreadItemKind, ThreadItemState, TimelineTurn};
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, SqliteTransactionMode,
    Statement, TransactionOptions, TransactionTrait, Value,
};

/// The current target format, independent of released Main/ForwardNine source codecs. Old format9
/// files retain their original format and lineage read-only; only the named current target step
/// writes format10. Ordinary readers never treat a released source format as a ready current.
const HISTORY_SCHEMA_VERSION: i64 = 10;

mod checkpoint;
mod current;
mod import;
mod initialization;
mod raw_json;
mod validation;
#[cfg(test)]
pub(super) use current::MigrationFault;
pub(crate) use initialization::{ExecutionIdentityMigration, HistoryInitialization};
pub(crate) mod input_chain;
pub(crate) use input_chain::{InputChainBatch, InputChainBatchRead, InputChainReadLimits};
mod receipts;
mod resources;
mod schema;
pub(crate) use resources::context_resources;
/// 单页返回的总 payload 字节预算；达到预算即停止装入更多条目。
const PAGE_BYTE_BUDGET: usize = 2 * 1024 * 1024;
/// 单条预览预算必须小于整页预算，否则一条预览都无法落入一页。
const _: () = assert!(pl_core::chat::CHAT_ITEM_PREVIEW_BYTES < PAGE_BYTE_BUDGET);
/// 一页 Turn 最多返回的 Turn 行数（调用方 `limit` 的上限）。
const TURN_PAGE_ROW_LIMIT: usize = 200;
/// 一条 Turn 在一个 Turn 页里最多返回的条目行数。
///
/// 整页字节预算已经限制返回字节，但 SQL 读取本身也必须先有行上限，否则一条巨型 Turn 会在
/// 裁剪之前被整条读进内存。达到行上限的剩余条目由 `next_cursor` 在同一 Turn 内继续取回。
const TURN_PAGE_ITEM_LIMIT: usize = 500;
/// 一页 agent 会话窗口最多返回的条目行数（与 `session_page` 的 1..=50 契约一致）。
const AGENT_PAGE_ROW_LIMIT: usize = 50;

/// One independently owned Thread history database handle.
///
/// Construction performs no filesystem or database IO. Explicit initialization publishes a fully
/// validated current database before ordinary readers/writers may consume it. Cold reads never
/// create or upgrade a database; a missing, unfinished or damaged target is an error, not empty
/// history and not a reason to fall back to the retained source.
#[derive(Clone)]
pub(crate) struct HistoryStore {
    state: std::sync::Arc<HistoryStoreState>,
}

/// One weak, copyable view of a history handle's shared connection state.
///
/// It lets the per-Thread persistence coordinator remember which handle *is* the Thread's single
/// ordered writer without keeping it alive: a handle exists exactly as long as a real holder (the
/// effect sink or a live subscription) keeps it, so closing or evicting the Thread releases the
/// database connections and no never-expiring strong history cache can appear.
#[derive(Clone)]
pub(crate) struct HistoryStoreShare {
    state: std::sync::Weak<HistoryStoreState>,
    preparation: initialization::PreparationSlot,
    retained: std::sync::Arc<std::sync::Mutex<Option<HistoryStore>>>,
}

impl std::fmt::Debug for HistoryStoreShare {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryStoreShare")
            .field("alive", &self.state.strong_count())
            .finish()
    }
}

struct HistoryStoreState {
    path: PathBuf,
    thread_id: String,
    resources: std::sync::OnceLock<crate::resource_store::thread::ThreadArchive>,
    /// The single writer connection, opened only after current-history initialization completed.
    ///
    /// Effect batches use one connection for short single-writer transactions. The Session owns
    /// ordinal allocation; this connection only persists the ordinals it supplies.
    writer: tokio::sync::OnceCell<HistoryConnection>,
    /// A read-only connection to an *existing* database, opened on the first cold read.
    reader: tokio::sync::OnceCell<HistoryConnection>,
    /// The retained initialization worker holds the write side through migration, close, sync and
    /// publication; dropping a waiter cannot release it. Cold opens take the read side only after
    /// observing that worker's completion. Normal writer connection publication uses the same lock.
    init: std::sync::Arc<tokio::sync::RwLock<()>>,
    preparation: initialization::PreparationSlot,
    preparation_owner: std::sync::Mutex<std::sync::Weak<std::sync::Mutex<Option<HistoryStore>>>>,
    /// Test gate between exclusive preparation-file creation and official migration.
    #[cfg(test)]
    init_gate: tokio::sync::Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            tokio::sync::oneshot::Receiver<()>,
        )>,
    >,
    /// Test-only probe fired immediately before a cold reader waits on `init`.
    #[cfg(test)]
    reader_before_init: tokio::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    #[cfg(test)]
    fail_publication_confirmation: std::sync::atomic::AtomicBool,
    #[cfg(test)]
    migration_fault: std::sync::Arc<std::sync::atomic::AtomicU8>,
}

/// One live connection plus the database identity it validated.
struct HistoryConnection {
    db: DatabaseConnection,
    database_id: String,
    schema_version: i64,
}

/// 一条终态输入的最小身份记录，外加可重建的 host 提交摘要。
///
/// `request_digest` 只覆盖 host 提交身份（原始 request 与 presentation），因此重复提交可以在
/// 附件草稿已被消费之后重新计算它并校验正文；载荷无法证明正文身份时为 `None`。
pub(crate) struct InputIdentityWrite {
    pub entry: crate::studio::storage::state::InputIdentityEntry,
    pub request_digest: Option<String>,
    pub presentation: pl_protocol::MessagePresentation,
}

/// 持久化幂等命中：保存的最小身份加上保存的 host 提交摘要。
pub(crate) struct InputIdentityReceipt {
    pub entry: crate::studio::storage::state::InputIdentityEntry,
    pub request_digest: Option<String>,
}

/// One durable receipt of a terminal interaction/permission fact.
///
/// `payload` is the canonical record the effect committed, so a repeated command can be answered
/// with the same receipt instead of minting a new revision or a new execution grant.
pub(crate) struct FactReceipt {
    pub kind: String,
    pub payload: String,
}

/// One durable interaction/permission receipt together with the identity it was stored under.
pub(crate) struct DecisionReceipt {
    /// The stable receipt key, i.e. `order::receipt_id(kind, local_id)`.
    pub item_id: String,
    pub kind: String,
    pub payload: String,
}

/// One receipt write that must land in the same transaction as the effect that produced it.
pub(crate) struct FactReceiptWrite {
    pub item_id: String,
    pub revision: u64,
    pub kind: &'static str,
    pub payload: String,
}

/// 一条已受理消息的最小持久身份。
///
/// `digest` 覆盖 core 定义的消息身份（原始 id、source、正文格式与内容，以及冻结的 context），
/// 与 `sequence` 一起在产生该消息的 effect 事务里落库。因此重复投递可以证明“同身份同正文”，
/// 命中时返回原始受理序号；`digest` 为 `None` 只可能来自迁移回填：索引证明该身份已受理，但
/// 无法证明正文，读取方必须 fail-closed，绝不静默重投。
pub(crate) struct MessageIdentityWrite {
    pub message_id: String,
    /// 该消息在时间线上的条目身份，便于与 `history_items` 对齐排查。
    pub item_id: String,
    pub sequence: u64,
    pub digest: Option<String>,
}

/// 持久化消息身份命中：原始受理序号与保存的正文摘要。
pub(crate) struct MessageIdentityReceipt {
    pub sequence: u64,
    pub digest: Option<String>,
}

/// One effect's durable history write, committed as a single transaction.
pub(crate) struct EffectCommit<'a> {
    pub items: &'a [ThreadItem],
    pub rolled_back_turns: &'a std::collections::BTreeSet<String>,
    /// Minimal identities of the terminal inputs this effect's state still carries.
    pub identities: &'a [InputIdentityWrite],
    /// Minimal identities of the messages this effect admitted, committed with the same transaction.
    pub messages: &'a [MessageIdentityWrite],
    /// Canonical fact receipts produced by this effect, including immutable start proofs.
    pub receipts: &'a [FactReceiptWrite],
    /// Task lifecycle and full delivery are authority, not lossy call statistics.
    pub tasks: &'a [pl_core::thread::task::TaskRecord],
    pub deliveries: &'a [pl_core::thread::ToolDelivery],
    /// Durable resource supplements for already-committed deliveries of this effect.
    pub delivery_repairs: &'a [pl_core::thread::cold::OutputRepair],
    pub attempt: Option<&'a pl_core::thread::journal::AttemptUpdate>,
}

impl std::fmt::Debug for HistoryStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryStore")
            .field("thread_id", &self.state.thread_id)
            .finish_non_exhaustive()
    }
}

impl HistoryStore {
    /// Binds one Thread history database path without touching the filesystem or database.
    ///
    /// Only `initialize` may create/import the current history. Reads and ordinary writes require
    /// a completed target; an absent or damaged store cannot be resurrected by either operation.
    pub(crate) async fn open(path: &Path, thread_id: &str) -> Result<Self> {
        ensure!(
            !thread_id.is_empty(),
            "history Thread identity must not be empty"
        );
        Ok(Self {
            state: std::sync::Arc::new(HistoryStoreState {
                path: path.to_owned(),
                thread_id: thread_id.to_owned(),
                resources: std::sync::OnceLock::new(),
                writer: tokio::sync::OnceCell::new(),
                reader: tokio::sync::OnceCell::new(),
                init: std::sync::Arc::new(tokio::sync::RwLock::new(())),
                preparation: Default::default(),
                preparation_owner: std::sync::Mutex::new(std::sync::Weak::new()),
                #[cfg(test)]
                init_gate: tokio::sync::Mutex::new(None),
                #[cfg(test)]
                reader_before_init: tokio::sync::Mutex::new(None),
                #[cfg(test)]
                fail_publication_confirmation: std::sync::atomic::AtomicBool::new(false),
                #[cfg(test)]
                migration_fault: Default::default(),
            }),
        })
    }

    /// A weak view of this handle's shared connection state, for the per-Thread writer registry.
    pub(crate) fn shared(&self) -> HistoryStoreShare {
        let retained = self.preparation_retention();
        HistoryStoreShare {
            state: std::sync::Arc::downgrade(&self.state),
            preparation: self.state.preparation.clone(),
            retained,
        }
    }

    pub(crate) fn thread_id(&self) -> &str {
        &self.state.thread_id
    }

    /// The physical location is explicitly supplied by StudioStore, never inferred from SQL paths.
    pub(crate) fn bind_resources(
        &self,
        root: PathBuf,
        trusted_parent: PathBuf,
        attachments: PathBuf,
    ) -> Result<crate::resource_store::ThreadResourceStore> {
        let archive = self.state.resources.get_or_init(|| {
            crate::resource_store::thread::ThreadArchive::new(
                root.clone(),
                trusted_parent,
                attachments.clone(),
            )
        });
        ensure!(archive.root() == root, "Thread resource root changed");
        ensure!(
            archive.attachments() == attachments,
            "Thread attachment catalog changed"
        );
        Ok(crate::resource_store::ThreadResourceStore::new(
            self.clone(),
            archive.clone(),
        ))
    }

    pub(crate) fn resources(&self) -> Option<crate::resource_store::ThreadResourceStore> {
        self.state.resources.get().map(|archive| {
            crate::resource_store::ThreadResourceStore::new(self.clone(), archive.clone())
        })
    }

    /// Parks the next writer initialization after the file exists and before identity is committed.
    ///
    /// Returns the entered receiver and the release sender. Production never installs this gate.
    #[cfg(test)]
    pub(crate) async fn arm_init_gate(
        &self,
    ) -> (
        tokio::sync::oneshot::Receiver<()>,
        tokio::sync::oneshot::Sender<()>,
    ) {
        let (entered_tx, entered_rx) = tokio::sync::oneshot::channel();
        let (release_tx, release_rx) = tokio::sync::oneshot::channel();
        *self.state.init_gate.lock().await = Some((entered_tx, release_rx));
        (entered_rx, release_tx)
    }

    /// Signals once a cold reader is about to wait on the initialization lock.
    #[cfg(test)]
    pub(crate) async fn arm_reader_before_init(&self) -> tokio::sync::oneshot::Receiver<()> {
        let (tx, rx) = tokio::sync::oneshot::channel();
        *self.state.reader_before_init.lock().await = Some(tx);
        rx
    }

    /// The handle behind one share, or `None` once its last real holder released it.
    ///
    /// The upgraded handle is the same logical connection state — the same writer and the same
    /// validated database identity — not a new database client.
    pub(crate) fn from_share(share: &HistoryStoreShare) -> Option<Self> {
        share.state.upgrade().map(|state| Self { state })
    }

    /// The connection ordinary history reads use; a missing current store is a readiness error.
    ///
    /// The writer connection, once opened, is authoritative for reads too, so a hot writer and an
    /// in-memory test store never observe two divergent databases. Otherwise the existing file is
    /// opened read-only and validated. No read creates a file or initiates an import. A read racing
    /// explicit initialization waits for its retained result before opening the published target.
    async fn reader(&self) -> Result<Option<&HistoryConnection>> {
        self.wait_for_initialization().await?;
        if let Some(writer) = self.state.writer.get() {
            return Ok(Some(writer));
        }
        // Wait for publication and share the same coordination boundary with first writer open.
        let _initializing = self.state.init.read().await;
        // Re-check under the guard: the writer may have published its connection while we waited.
        if let Some(writer) = self.state.writer.get() {
            return Ok(Some(writer));
        }
        let connection = self
            .read_only_connection()
            .await?
            .context("current history is absent; explicit initialization is required")?;
        Ok(Some(connection))
    }

    /// Caller holds the initialization read guard. Never returns the writer, even when another
    /// observer keeps it alive; a missing file remains missing instead of reading an unlinked DB.
    async fn read_only_connection(&self) -> Result<Option<&HistoryConnection>> {
        if !tokio::fs::try_exists(&self.state.path).await? {
            // Exact proof ports distinguish "no durable proof" from an empty normal history.
            // Ordinary readers turn this into a readiness error instead of showing an empty page.
            return Ok(None);
        }
        let reader = self
            .state
            .reader
            .get_or_try_init(|| async {
                let db = connect_read_only(&self.state.path).await?;
                let result = current::validate_readable(&db, &self.state.thread_id).await;
                let (database_id, schema_version) = match result {
                    Ok(identity) => identity,
                    Err(error) => {
                        db.close().await.context("close rejected current history")?;
                        return Err(error);
                    }
                };
                Ok::<HistoryConnection, anyhow::Error>(HistoryConnection {
                    db,
                    database_id,
                    schema_version,
                })
            })
            .await?;
        if let Some(writer) = self.state.writer.get() {
            ensure!(
                reader.database_id == writer.database_id,
                "read-only history does not match the shared writer identity"
            );
        }
        Ok(Some(reader))
    }

    /// Opens the single writer connection to an already completed target.
    ///
    /// Validation is strictly read-only and precedes the writable open. This entry never chooses an
    /// origin, runs a migration or falls back to a retained source.
    async fn writer(&self) -> Result<&HistoryConnection> {
        self.wait_for_initialization().await?;
        if let Some(writer) = self.state.writer.get() {
            return Ok(writer);
        }
        let _initializing = self.state.init.write().await;
        self.state
            .writer
            .get_or_try_init(|| async {
                // Validate through mode=ro before opening a writer. A missing, partial or foreign
                // target can never be turned into a new database by an ordinary save.
                let (database_id, schema_version) =
                    current::inspect_ready(&self.state.path, &self.state.thread_id).await?;
                let db = connect(&self.state.path).await?;
                Ok::<HistoryConnection, anyhow::Error>(HistoryConnection {
                    db,
                    database_id,
                    schema_version,
                })
            })
            .await
    }

    /// Atomically applies one immutable writer batch and advances its fixed waterline.
    #[cfg(test)]
    pub(crate) async fn commit(
        &self,
        write_seq: u64,
        items: &[ThreadItem],
        turns: &[TimelineTurn],
    ) -> Result<()> {
        // Test-only producer: fixtures calling this helper explicitly own a new history. The
        // production checkpoint/effect entry remains readiness-only.
        self.initialize(HistoryInitialization::New).await?;
        ensure!(write_seq > 0, "history write sequence must be positive");
        let write_seq = integer(write_seq)?;
        let tx = begin_write(&self.writer().await?.db).await?;
        let current = applied_write_seq(&tx).await?;
        if write_seq <= current {
            tx.rollback().await?;
            return Ok(());
        }
        for item in items {
            self.upsert_item(&tx, write_seq, item.clone()).await?;
        }
        for turn in turns {
            self.upsert_turn(&tx, write_seq, turn).await?;
        }
        // A valid source fixture carries its real producer's matching restart state. Tests that
        // need a missing-checkpoint corruption remove it explicitly instead of seeding an
        // impossible nonempty history through this helper.
        let mut state = checkpoint::read(&tx, &self.state.thread_id)
            .await?
            .map_or_else(pl_core::thread::ThreadSnapshot::default, |checkpoint| {
                checkpoint.state
            });
        state.commit_sequence = u64::try_from(write_seq)?;
        checkpoint::write(
            &tx,
            &pl_core::thread::ThreadCheckpoint::capture(
                self.state.thread_id.clone(),
                u64::try_from(write_seq)?,
                state,
            ),
            None,
        )
        .await?;
        if write_seq > current {
            tx.execute_raw(statement(
                "UPDATE history_meta SET applied_write_seq=? WHERE id=1",
                vec![write_seq.into()],
            ))
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    /// Commits one effect's history facts, including every durable identity index.
    ///
    /// The minimal input/message identities and terminal receipts one effect produced are written in
    /// the same transaction as its items and Turn rows, so an index can never be durable without the
    /// effect it describes (or the other way round) after a crash between two commits.
    #[cfg(test)]
    pub(crate) async fn commit_effect(
        &self,
        write_seq: u64,
        commit: EffectCommit<'_>,
    ) -> Result<()> {
        self.initialize(HistoryInitialization::New).await?;
        let mut state = self
            .checkpoint()
            .await?
            .map_or_else(pl_core::thread::ThreadSnapshot::default, |checkpoint| {
                checkpoint.state
            });
        state.commit_sequence = write_seq;
        let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
            self.state.thread_id.clone(),
            write_seq,
            state,
        );
        let effect = pl_core::thread::ThreadEffectBatch {
            thread_id: self.state.thread_id.clone(),
            sequence: write_seq,
            ..Default::default()
        };
        self.commit_checkpoint_effect(&checkpoint, &effect, commit)
            .await
    }

    /// Publishes history and the matching latest recovery state in one transaction.
    pub(crate) async fn commit_checkpoint_effect(
        &self,
        checkpoint: &pl_core::thread::ThreadCheckpoint,
        effect: &pl_core::thread::ThreadEffectBatch,
        commit: EffectCommit<'_>,
    ) -> Result<()> {
        ensure!(
            checkpoint.thread_id == self.state.thread_id
                && effect.thread_id == self.state.thread_id
                && checkpoint.state_revision == effect.sequence
                && checkpoint.history_fence == effect.sequence,
            "checkpoint and history effect identities differ"
        );
        self.commit_inner(effect.sequence, commit, Some((checkpoint, effect)))
            .await
    }

    async fn commit_inner(
        &self,
        write_seq: u64,
        commit: EffectCommit<'_>,
        checkpoint: Option<(
            &pl_core::thread::ThreadCheckpoint,
            &pl_core::thread::ThreadEffectBatch,
        )>,
    ) -> Result<()> {
        let EffectCommit {
            items,
            rolled_back_turns,
            identities,
            messages,
            receipts,
            tasks,
            deliveries,
            delivery_repairs,
            attempt,
        } = commit;
        ensure!(write_seq > 0, "history write sequence must be positive");
        let write_seq = integer(write_seq)?;
        let tx = begin_write(&self.writer().await?.db).await?;
        let current = applied_write_seq(&tx).await?;
        if write_seq <= current {
            if let Some((checkpoint, _)) = checkpoint {
                checkpoint::verify_committed(&tx, checkpoint, current).await?;
            }
            tx.rollback().await?;
            return Ok(());
        }
        if checkpoint.is_some() {
            ensure!(
                write_seq == current + 1,
                "history write sequence is not contiguous"
            );
        }
        let mut turn_ids = std::collections::BTreeSet::new();
        for item in items {
            if !item.turn_id.is_empty() {
                turn_ids.insert(item.turn_id.clone());
            }
            self.upsert_item(&tx, write_seq, item.clone()).await?;
        }
        for turn_id in turn_ids {
            let Some(row) = tx
                .query_one_raw(statement(
                    "SELECT payload,last_write_seq FROM history_items WHERE item_id=?",
                    vec![crate::studio::thread_projection::order::turn_id(&turn_id).into()],
                ))
                .await?
            else {
                continue;
            };
            let payload: String = row.try_get("", "payload")?;
            let item: ThreadItem = serde_json::from_str(&payload)?;
            let ThreadItemState::Turn(turn) = item.state() else {
                continue;
            };
            let last = tx
                .query_one_raw(statement(
                    "SELECT item_id FROM history_items
                     WHERE turn_id=? AND kind != 'contextCompaction'
                     ORDER BY ordinal DESC LIMIT 1",
                    vec![turn_id.clone().into()],
                ))
                .await?
                .context("history Turn has no last item")?
                .try_get::<String>("", "item_id")?;
            self.upsert_turn(
                &tx,
                write_seq,
                &TimelineTurn {
                    turn: pl_protocol::Turn {
                        input_id: turn.input_id().map(str::to_owned),
                        id: turn_id.clone(),
                        thread_id: self.state.thread_id.clone(),
                        revision: u64::try_from(row.try_get::<i64>("", "last_write_seq")?)?,
                        state: turn.state().clone(),
                        updated_at: item.updated_at,
                    },
                    last_item_id: last,
                    context_disposition: if rolled_back_turns.contains(&turn_id) {
                        pl_protocol::ThreadContextDisposition::RolledBack
                    } else {
                        pl_protocol::ThreadContextDisposition::Active
                    },
                },
            )
            .await?;
        }
        for identity in identities {
            write_input_identity(&tx, write_seq, identity).await?;
        }
        for message in messages {
            write_message_identity(&tx, write_seq, message).await?;
        }
        for receipt in receipts {
            write_fact_receipt(&tx, write_seq, receipt).await?;
        }
        if let Some(attempt) = attempt
            && let pl_core::thread::AttemptOutcome::Committed(output) = &attempt.outcome
        {
            for call in output.tool_calls.iter() {
                write_tool_task(
                    &tx,
                    write_seq,
                    &pl_core::thread::task::TaskRecord {
                        id: format!("task:{}", call.call_id),
                        call_id: call.call_id.clone(),
                        tool_id: call.tool_id.clone(),
                        turn_id: attempt.turn_id.clone(),
                        revision: 0,
                        status: pl_core::thread::task::TaskStatus::Running,
                        cancel_requested: false,
                        acknowledgement: None,
                        started_sequence: None,
                    },
                )
                .await?;
            }
        }
        for task in tasks {
            write_tool_task(&tx, write_seq, task).await?;
        }
        for delivery in deliveries {
            write_tool_delivery(&tx, write_seq, delivery).await?;
        }
        for repair in delivery_repairs {
            write_tool_delivery_repair(&tx, write_seq, repair).await?;
        }
        if write_seq > current {
            tx.execute_raw(statement(
                "UPDATE history_meta SET applied_write_seq=? WHERE id=1",
                vec![write_seq.into()],
            ))
            .await?;
        }
        if let Some((checkpoint, effect)) = checkpoint {
            checkpoint::write(&tx, checkpoint, effect.context.as_ref()).await?;
            checkpoint::fold_costs(&tx, effect).await?;
        }
        tx.commit().await?;
        Ok(())
    }

    /// Reads the committed task identity and exact delivery, never a call-statistics projection.
    pub(crate) async fn tool_task(
        &self,
        task_id: &str,
    ) -> Result<Option<pl_core::thread::cold::DurableToolTask>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let call_id = task_id.strip_prefix("task:").unwrap_or(task_id);
        let Some(row) = connection
            .db
            .query_one_raw(statement(
                "SELECT task_payload,delivery_payload FROM history_tool_tasks WHERE call_id=?",
                vec![call_id.to_owned().into()],
            ))
            .await?
        else {
            return Ok(None);
        };
        let task: String = row.try_get("", "task_payload")?;
        let delivery: Option<String> = row.try_get("", "delivery_payload")?;
        Ok(Some(pl_core::thread::cold::DurableToolTask {
            task: serde_json::from_str(&task)?,
            delivery: delivery
                .map(|body| serde_json::from_str(&body))
                .transpose()?,
        }))
    }

    /// Finds committed deliveries that may reference one archived tool attachment.
    ///
    /// The delivery is the durable authority for the full resource reference. The SQL substring
    /// only narrows candidates; the caller decodes each delivery and verifies its typed media
    /// projection before granting access to any bytes.
    pub(crate) async fn tool_media_deliveries(
        &self,
        attachment_id: &str,
    ) -> Result<Vec<pl_core::thread::ToolDelivery>> {
        let Some(connection) = self.reader().await? else {
            return Ok(Vec::new());
        };
        let rows = connection
            .db
            .query_all_raw(statement(
                "SELECT delivery_payload FROM history_tool_tasks
                 WHERE delivery_payload IS NOT NULL AND instr(delivery_payload, ?) > 0",
                vec![attachment_id.to_owned().into()],
            ))
            .await?;
        rows.into_iter()
            .map(|row| {
                let payload: String = row.try_get("", "delivery_payload")?;
                Ok(serde_json::from_str(&payload)?)
            })
            .collect()
    }

    /// Reads the minimal identity of a previously admitted input, if the durable index knows it.
    ///
    /// This is the cross-restart idempotency lookup for `submitPrompt`: the returned record lets
    /// the runtime rebuild the original receipt without re-admitting the input or replaying history.
    /// Reads the newest durable receipt of one interaction/permission identity.
    ///
    /// This is the cross-window/cross-restart authority for a repeated terminal interaction
    /// command: `payload` is the exact committed record, so the host can answer with the original
    /// receipt or reject a conflicting payload instead of minting a new revision, granting a new
    /// execution permission or replaying the effect. A missing store or receipt returns `None`.
    pub(crate) async fn latest_fact_receipt(&self, item_id: &str) -> Result<Option<FactReceipt>> {
        if item_id.is_empty() {
            return Ok(None);
        }
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT revision,kind,digest,payload FROM history_fact_receipts
                 WHERE item_id=? ORDER BY revision DESC LIMIT 1",
                vec![item_id.to_owned().into()],
            ))
            .await?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(FactReceipt {
            kind: row.try_get("", "kind")?,
            payload: row.try_get("", "payload")?,
        }))
    }

    /// The newest durable receipt of every decision identity this Thread ever committed.
    ///
    /// Canonical snapshots keep only pending decisions, so a settled question or approval leaves the
    /// snapshot behind and the receipts become the only read-only source that can still prove it.
    /// Operation identity reuse, a terminal replay and the hand-over reconciliation all read this one
    /// source instead of a snapshot that has already dropped the record. A missing store or no
    /// receipts returns an empty list; a storage fault is propagated.
    pub(crate) async fn decision_receipts(&self) -> Result<Vec<DecisionReceipt>> {
        let Some(connection) = self.reader().await? else {
            return Ok(Vec::new());
        };
        let rows = connection
            .db
            .query_all_raw(statement(
                "SELECT newest.item_id, newest.kind, newest.payload FROM history_fact_receipts newest \
                 JOIN (SELECT item_id, MAX(revision) AS revision FROM history_fact_receipts \
                       WHERE kind IN ('interaction','permission') GROUP BY item_id) latest \
                   ON latest.item_id = newest.item_id AND latest.revision = newest.revision \
                 WHERE newest.kind IN ('interaction','permission') ORDER BY newest.item_id",
                Vec::new(),
            ))
            .await?;
        rows.into_iter()
            .map(|row| {
                Ok(DecisionReceipt {
                    item_id: row.try_get("", "item_id")?,
                    kind: row.try_get("", "kind")?,
                    payload: row.try_get("", "payload")?,
                })
            })
            .collect()
    }

    pub(crate) async fn input_identity(
        &self,
        input_id: &str,
    ) -> Result<Option<InputIdentityReceipt>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT payload,request_digest FROM history_input_identities WHERE item_id=?",
                vec![input_id.into()],
            ))
            .await?;
        match row {
            Some(row) => Ok(Some(InputIdentityReceipt {
                entry: serde_json::from_str(&row.try_get::<String>("", "payload")?)?,
                request_digest: row.try_get::<Option<String>>("", "request_digest")?,
            })),
            None => Ok(None),
        }
    }

    /// Checks the completed current database before seeding an active projection. Never migrates.
    pub(crate) async fn prepare_activation(&self) -> Result<()> {
        self.writer().await?;
        Ok(())
    }

    /// Only a committed hidden disposition can discharge a pruned input without a timeline row.
    pub(crate) async fn hidden_input_identities(
        &self,
        ids: impl IntoIterator<Item = String>,
    ) -> Result<std::collections::BTreeSet<String>> {
        let ids = ids.into_iter().collect::<std::collections::BTreeSet<_>>();
        if ids.is_empty() {
            return Ok(Default::default());
        }
        let Some(connection) = self.reader().await? else {
            return Ok(Default::default());
        };
        ensure!(
            connection.schema_version == HISTORY_SCHEMA_VERSION,
            "current history is not at its completed target format"
        );
        let mut hidden = std::collections::BTreeSet::new();
        let ids = ids.into_iter().collect::<Vec<_>>();
        for batch in ids.chunks(400) {
            let placeholders = vec!["?"; batch.len()].join(",");
            let rows = connection
                .db
                .query_all_raw(statement(
                    &format!(
                        "SELECT item_id,presentation FROM history_input_identities \
                         WHERE item_id IN ({placeholders})"
                    ),
                    batch.iter().cloned().map(Into::into).collect(),
                ))
                .await?;
            for row in rows {
                let id: String = row.try_get("", "item_id")?;
                match row
                    .try_get::<Option<String>>("", "presentation")?
                    .as_deref()
                {
                    Some("hidden") => {
                        hidden.insert(id);
                    }
                    Some("visible") | None => {}
                    Some(other) => anyhow::bail!("invalid input presentation {other}"),
                }
            }
        }
        Ok(hidden)
    }

    /// Reads the minimal durable identity of one accepted message, if the index knows it.
    ///
    /// This is the cross-window/cross-restart idempotency lookup for message delivery: the returned
    /// sequence is the original admission receipt and the digest is the proof of the accepted body.
    /// A row without a digest can only come from a migration backfill, and the caller must treat it
    /// as unverifiable instead of re-delivering. An unknown identity returns `None`; a missing or
    /// damaged current store fails so the caller cannot admit a duplicate from unready storage.
    pub(crate) async fn message_identity(
        &self,
        message_id: &str,
    ) -> Result<Option<MessageIdentityReceipt>> {
        if message_id.is_empty() {
            return Ok(None);
        }
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT sequence,digest FROM history_message_identities WHERE message_id=?",
                vec![message_id.into()],
            ))
            .await?;
        match row {
            Some(row) => {
                let sequence = u64::try_from(row.try_get::<i64>("", "sequence")?)
                    .context("durable message identity has an invalid admission sequence")?;
                Ok(Some(MessageIdentityReceipt {
                    sequence,
                    digest: row.try_get::<Option<String>>("", "digest")?,
                }))
            }
            None => Ok(None),
        }
    }

    pub(crate) async fn existing_items(
        &self,
        ids: impl IntoIterator<Item = String>,
    ) -> Result<std::collections::BTreeMap<String, ThreadItem>> {
        let Some(connection) = self.reader().await? else {
            return Ok(std::collections::BTreeMap::new());
        };
        let mut items = std::collections::BTreeMap::new();
        let ids = ids
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        for batch in ids.chunks(400) {
            let placeholders = vec!["?"; batch.len()].join(",");
            let sql = format!(
                "SELECT item_id,payload FROM history_items WHERE item_id IN ({placeholders})"
            );
            let rows = connection
                .db
                .query_all_raw(statement(
                    &sql,
                    batch.iter().cloned().map(Into::into).collect(),
                ))
                .await?;
            for row in rows {
                let id: String = row.try_get("", "item_id")?;
                let payload: String = row.try_get("", "payload")?;
                items.insert(id, serde_json::from_str(&payload)?);
            }
        }
        Ok(items)
    }

    pub(crate) async fn items_for_turn(&self, turn_id: &str) -> Result<Vec<ThreadItem>> {
        let Some(connection) = self.reader().await? else {
            return Ok(Vec::new());
        };
        query_items(
            &connection.db,
            "SELECT payload FROM history_items WHERE turn_id=? ORDER BY ordinal ASC",
            vec![turn_id.into()],
        )
        .await
    }

    pub(crate) async fn watermark(&self) -> Result<u64> {
        match self.reader().await? {
            Some(connection) => connection_watermark(connection).await,
            None => Ok(0),
        }
    }

    async fn upsert_item(
        &self,
        db: &impl ConnectionTrait,
        write_seq: i64,
        mut item: ThreadItem,
    ) -> Result<()> {
        ensure!(
            item.thread_id == self.state.thread_id && !item.id.is_empty(),
            "history item identity does not belong to this Thread"
        );
        ensure!(
            item.ordinal > 0,
            "history item ordinal must be assigned by the Session"
        );
        ensure!(item.revision > 0, "history item revision must be positive");
        let revision = integer(item.revision)?;
        let existing = db
            .query_one_raw(statement(
                "SELECT ordinal,turn_id,kind,revision,lifecycle,created_at,payload,last_write_seq
                 FROM history_items WHERE item_id=?",
                vec![item.id.clone().into()],
            ))
            .await?;
        let kind = kind_label(item.kind());
        let lifecycle = if item.is_terminal() {
            "terminal"
        } else {
            "open"
        };
        if let Some(row) = existing {
            let old_ordinal: i64 = row.try_get("", "ordinal")?;
            let old_turn: String = row.try_get("", "turn_id")?;
            let old_kind: String = row.try_get("", "kind")?;
            let old_revision: i64 = row.try_get("", "revision")?;
            let old_lifecycle: String = row.try_get("", "lifecycle")?;
            let old_created_at: i64 = row.try_get("", "created_at")?;
            let old_payload: String = row.try_get("", "payload")?;
            let old_write_seq: i64 = row.try_get("", "last_write_seq")?;
            ensure!(
                (old_turn == item.turn_id || old_turn.is_empty()) && old_kind == kind,
                "history item identity fields changed"
            );
            ensure!(
                item.ordinal == u64::try_from(old_ordinal)?,
                "history item ordinal changed for {}",
                item.id
            );
            item.created_at = old_created_at;
            let payload = serde_json::to_string(&item)?;
            if old_revision > revision {
                return Ok(());
            }
            if old_revision == revision {
                ensure!(old_payload == payload, "history item revision conflict");
                return Ok(());
            }
            // A later canonical revision supersedes the stored item, which is how the projection
            // completes facts it could not know earlier (binding a queued input to its Turn, or
            // settling a pending input into consumed/discarded). Only a late non-final draft may
            // not rewrite an item that already reached a terminal state.
            ensure!(
                old_lifecycle != "terminal" || item.is_terminal(),
                "terminal history item was revised"
            );
            ensure!(
                old_kind != "turn" || old_lifecycle != "terminal" || old_write_seq == write_seq,
                "terminal Turn notification sequence changed for {}",
                item.id
            );
            db.execute_raw(statement(
                "UPDATE history_items SET
                    revision=?,lifecycle=?,turn_id=?,updated_at=?,payload=?,last_write_seq=?
                 WHERE item_id=?",
                vec![
                    revision.into(),
                    lifecycle.into(),
                    item.turn_id.clone().into(),
                    item.updated_at.into(),
                    payload.into(),
                    write_seq.into(),
                    item.id.clone().into(),
                ],
            ))
            .await?;
            if old_turn.is_empty() && !item.turn_id.is_empty() {
                // A queued message may predate its Turn. Binding that *same* item identity to
                // the Turn can extend the indexed start backwards, but no unrelated write may
                // change the first ordinal checked by `upsert_turn` below.
                db.execute_raw(statement(
                    "UPDATE history_turns SET first_ordinal=MIN(first_ordinal, ?) WHERE turn_id=?",
                    vec![old_ordinal.into(), item.turn_id.clone().into()],
                ))
                .await?;
            }
            return Ok(());
        }
        let ordinal = integer(item.ordinal)?;
        let payload = serde_json::to_string(&item)?;
        db.execute_raw(statement(
            "INSERT INTO history_items(
                ordinal,item_id,turn_id,kind,revision,lifecycle,
                created_at,updated_at,payload,last_write_seq
             ) VALUES(?,?,?,?,?,?,?,?,?,?)",
            vec![
                ordinal.into(),
                item.id.clone().into(),
                item.turn_id.clone().into(),
                kind.into(),
                revision.into(),
                lifecycle.into(),
                item.created_at.into(),
                item.updated_at.into(),
                payload.into(),
                write_seq.into(),
            ],
        ))
        .await?;
        Ok(())
    }

    async fn upsert_turn(
        &self,
        db: &impl ConnectionTrait,
        write_seq: i64,
        turn: &TimelineTurn,
    ) -> Result<()> {
        ensure!(
            turn.turn.thread_id == self.state.thread_id && !turn.turn.id.is_empty(),
            "history Turn identity does not belong to this Thread"
        );
        let first_ordinal = db
            .query_one_raw(statement(
                "SELECT MIN(ordinal) AS ordinal FROM history_items WHERE turn_id=?",
                vec![turn.turn.id.clone().into()],
            ))
            .await?
            .and_then(|row| row.try_get::<Option<i64>>("", "ordinal").ok().flatten())
            .context("history Turn has no item")?;
        let last_ordinal = db
            .query_one_raw(statement(
                "SELECT ordinal FROM history_items WHERE item_id=? AND turn_id=?",
                vec![
                    turn.last_item_id.clone().into(),
                    turn.turn.id.clone().into(),
                ],
            ))
            .await?
            .context("history Turn last item is missing")?
            .try_get::<i64>("", "ordinal")?;
        let revision = integer(turn.turn.revision)?;
        let payload = serde_json::to_string(turn)?;
        let existing = db
            .query_one_raw(statement(
                "SELECT first_ordinal,last_ordinal,revision,payload,last_write_seq
                 FROM history_turns WHERE turn_id=?",
                vec![turn.turn.id.clone().into()],
            ))
            .await?;
        if let Some(row) = existing {
            let old_first: i64 = row.try_get("", "first_ordinal")?;
            let old_last: i64 = row.try_get("", "last_ordinal")?;
            let old_revision: i64 = row.try_get("", "revision")?;
            let old_payload: String = row.try_get("", "payload")?;
            let old_write_seq: i64 = row.try_get("", "last_write_seq")?;
            ensure!(
                old_first == first_ordinal,
                "history Turn first item changed"
            );
            if old_revision > revision {
                return Ok(());
            }
            if old_revision == revision {
                if old_payload == payload {
                    return Ok(());
                }
                // 同一 revision 的 Turn 行只能被同一条事实的“投影前进”重写，绝不能被另一份事实
                // 替换：Turn 本体（state/input_id/updated_at，与它的 revision 一起来自那条已落库的
                // Turn 条目）必须逐字相同，结尾只能向后延伸，上下文处置只允许由 Active 落定为
                // RolledBack。其余差异都说明有人在同一 revision 下改写了这条 Turn，必须显式失败，
                // 而不是靠更大的 write_seq 静默覆盖旧 payload。
                let stored: TimelineTurn = serde_json::from_str(&old_payload)?;
                ensure!(
                    stored.turn == turn.turn,
                    "history Turn revision conflict: the Turn fact changed at revision {revision}"
                );
                ensure!(
                    last_ordinal >= old_last,
                    "history Turn end moved backwards at revision {revision}"
                );
                ensure!(
                    stored.context_disposition == turn.context_disposition
                        || stored.context_disposition
                            == pl_protocol::ThreadContextDisposition::Active,
                    "history Turn context disposition regressed at revision {revision}"
                );
                ensure!(
                    write_seq >= old_write_seq,
                    "history Turn write sequence moved backwards"
                );
            }
            db.execute_raw(statement(
                "UPDATE history_turns SET
                    last_ordinal=?,revision=?,payload=?,last_write_seq=?
                 WHERE turn_id=?",
                vec![
                    last_ordinal.into(),
                    revision.into(),
                    payload.into(),
                    write_seq.into(),
                    turn.turn.id.clone().into(),
                ],
            ))
            .await?;
            return Ok(());
        }
        db.execute_raw(statement(
            "INSERT INTO history_turns(
                turn_id,first_ordinal,last_ordinal,revision,payload,last_write_seq
             ) VALUES(?,?,?,?,?,?)",
            vec![
                turn.turn.id.clone().into(),
                first_ordinal.into(),
                last_ordinal.into(),
                revision.into(),
                payload.into(),
                write_seq.into(),
            ],
        ))
        .await?;
        Ok(())
    }

    /// Reads one canonical item by identity, including its complete body.
    ///
    /// 这是按身份的**单条 on-demand 读取**，不是第二份历史：它只返回被点名的那一条正文，不带分页、
    /// 不带邻居、也不把结果缓存进 `HistoryStore`。调用方按字段与版本分块读取正文，因此这里刻意没有
    /// 字节上限——有上限就无法取回超预算条目的完整正文。需要遍历历史时必须走有界页，不能靠反复读取
    /// 单条来物化整段历史。
    ///
    /// # Errors
    /// Fails on a storage read failure; a missing identity is `None`.
    pub(crate) async fn read_chat_item(&self, item_id: &str) -> Result<Option<ChatItem>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let Some(row) = connection
            .db
            .query_one_raw(statement(
                "SELECT ordinal,payload FROM history_items WHERE item_id=?",
                vec![item_id.into()],
            ))
            .await?
        else {
            return Ok(None);
        };
        let ordinal = u64::try_from(row.try_get::<i64>("", "ordinal")?)?;
        let payload: String = row.try_get("", "payload")?;
        let mut item: ThreadItem = serde_json::from_str(&payload)?;
        item.ordinal = ordinal;
        Ok(Some(chat_item(item, true)?))
    }

    async fn latest_allocated_order(&self) -> Result<u64> {
        let Some(connection) = self.reader().await? else {
            return Ok(0);
        };
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT MAX(ordinal) AS ordinal FROM history_items",
                vec![],
            ))
            .await?
            .context("history ordinal query returned no row")?;
        let maximum: Option<i64> = row.try_get("", "ordinal")?;
        Ok(u64::try_from(maximum.unwrap_or(0))?)
    }

    /// Reads up to `limit` durable rows strictly older than `before`, ascending.
    ///
    /// `ordinal` 是 `INTEGER PRIMARY KEY`（rowid 别名）且严格递增、永不复用，因此“严格更旧”就是一
    /// 个 rowid range seek（`ordinal < ?`），不需要 OR 表达式或前缀扫描；identity 只用于校验游标
    /// scope（见 [`HistoryStore::ensure_cursor_identity`]），不参与排序。`has_older` 来自真实多出的
    /// 一行，短页本身不证明到头，并且只有本页的行会被解码。
    async fn chat_page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage> {
        let Some(connection) = self.reader().await? else {
            return Ok(ChatHistoryPage::default());
        };
        let probe = limit.saturating_add(1);
        let mut rows = match before {
            Some(before) => {
                query_chat_ids(
                    &connection.db,
                    "SELECT ordinal,item_id FROM history_items
                     WHERE ordinal < ? ORDER BY ordinal DESC LIMIT ?",
                    vec![integer(before.order)?.into(), integer(probe)?.into()],
                )
                .await?
            }
            None => {
                query_chat_ids(
                    &connection.db,
                    "SELECT ordinal,item_id FROM history_items
                     ORDER BY ordinal DESC LIMIT ?",
                    vec![integer(probe)?.into()],
                )
                .await?
            }
        };
        let has_older = rows.len() > limit;
        rows.truncate(limit);
        rows.reverse();
        let mut items = Vec::with_capacity(rows.len());
        for (ordinal, item_id) in rows {
            let row = connection
                .db
                .query_one_raw(statement(
                    "SELECT payload FROM history_items WHERE ordinal=?",
                    vec![integer(ordinal)?.into()],
                ))
                .await?
                .with_context(|| format!("chat page item {item_id} disappeared during read"))?;
            let payload: String = row.try_get("", "payload")?;
            let item: ThreadItem = serde_json::from_str(&payload)?;
            ensure!(
                item.id == item_id && item.ordinal == ordinal,
                "chat page item {item_id} differs from its indexed identity or order"
            );
            items.push(chat_item(item, true)?);
        }
        Ok(ChatHistoryPage { items, has_older })
    }

    /// Reads the newest terminal Turn this Thread already committed, without a body read.
    ///
    /// The realtime contract carries a finished Turn exactly once — the authoritative snapshot only
    /// ever holds the *active* Turn and `turnCompleted` is broadcast only to the subscribers that
    /// exist at that moment — so a projection owner that is installed (or a subscription that opens)
    /// after the finishing commit has no live frame left to learn it from. This cold read closes that
    /// gap from the durable facts the writer already committed, never from item bodies and never by
    /// scanning: "finished" is a stored column (`history_items.lifecycle='terminal'`) and its partial
    /// index is therefore able to return the single newest finished Turn by execution order.
    ///
    /// The two durable tables are one fact, chosen deliberately: `history_items` carries the
    /// `lifecycle`/`last_write_seq` columns the partial index orders on, while `history_turns.payload`
    /// carries the typed `Turn` the realtime frame and the client use. `commit_effect` writes both in
    /// the same transaction from the same turn item, and `upsert_item` freezes a terminal Turn item's
    /// `last_write_seq` (a later sequence is rejected), so an item row can name the newest finished
    /// Turn in execution order and that identity's Turn payload is the very fact the item projected —
    /// identity and revision are the writer's own, not a re-derivation, and no body is read.
    ///
    /// 冷读缺失历史库时返回 `None`，且绝不创建它。
    pub(crate) async fn newest_terminal_turn(&self) -> Result<Option<pl_protocol::Turn>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        // `history_terminal_turns_by_write_seq` is declared over exactly this predicate
        // (`kind='turn' AND lifecycle='terminal'`) and its leading column is `last_write_seq`, so
        // this is one index scan returning at most one row — no table scan, no ordering work and no
        // bounded-scan heuristic that a pathological history could defeat.
        let Some(row) = connection
            .db
            .query_one_raw(statement(
                "SELECT turn_id FROM history_items
                 WHERE kind='turn' AND lifecycle='terminal'
                 ORDER BY last_write_seq DESC, ordinal DESC LIMIT 1",
                vec![],
            ))
            .await?
        else {
            return Ok(None);
        };
        let turn_id: String = row.try_get("", "turn_id")?;
        let payload: String = connection
            .db
            .query_one_raw(statement(
                "SELECT payload FROM history_turns WHERE turn_id=?",
                vec![turn_id.into()],
            ))
            .await?
            .context("terminal Turn item has no committed Turn record")?
            .try_get("", "payload")?;
        let history: pl_protocol::TimelineTurn = serde_json::from_str(&payload)?;
        ensure!(
            history.turn.state.is_terminal(),
            "terminal Turn item does not resolve to a terminal Turn record"
        );
        Ok(Some(history.turn))
    }

    /// Reads the latest admitted Turn at exactly the caller's proven durable fence, without bodies.
    /// Unlike the retained-terminal seed, this query must not skip a newer unfinished Turn. The
    /// existing `(kind, ordinal)` item index orders admissions, not later items of an older Turn;
    /// its matching typed Turn and the watermark are read in the same SQLite snapshot.
    pub(crate) async fn latest_turn_at(
        &self,
        history_fence: u64,
    ) -> Result<Option<pl_protocol::Turn>> {
        let Some(connection) = self.reader().await? else {
            ensure!(history_fence == 0, "child durable history is missing");
            return Ok(None);
        };
        let tx = connection.db.begin().await?;
        let turn = read_latest_turn_at(&tx, &self.state.thread_id, history_fence).await?;
        tx.commit().await?;
        Ok(turn)
    }

    /// Reads one bounded Turn page, newest Turn first, without activating a Thread owner.
    ///
    /// The page is a keyset over `history_turns.last_ordinal` (index-backed, no offset, no full
    /// scan, no sort) and is bounded twice: by the caller's row limit and by [`PAGE_BYTE_BUDGET`]
    /// over the serialized entries, exactly like the item page. When the byte budget stops the page
    /// the returned cursor points at the last entry actually returned — inside the Turn it stopped
    /// in — so the next page resumes exactly there. Every item of every Turn is therefore reachable
    /// by following the cursors in ordinal order, and one page never grows with the size of one
    /// Turn: an oversized Turn is returned as consecutive windows instead of one unbounded body.
    ///
    /// 冷读缺失历史库时返回空 Turn 页，且绝不创建它。
    pub(crate) async fn turn_page(
        &self,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<pl_protocol::ThreadTurnPage> {
        let limit = limit.clamp(1, TURN_PAGE_ROW_LIMIT);
        let Some(connection) = self.reader().await? else {
            return Ok(pl_protocol::ThreadTurnPage {
                next_cursor: None,
                turns: Vec::new(),
            });
        };
        let watermark = connection_watermark(connection).await?;
        let resume = match cursor {
            Some(cursor) => {
                Some(turn_page_resume(connection, &self.state.thread_id, cursor, watermark).await?)
            }
            None => None,
        };
        let mut turns = Vec::new();
        let mut next_cursor = None;
        let mut used = 0_usize;
        // 本页真正返回的最后一条位置（Turn id 与窗口内的条目 ordinal）：续传阶段与本轮批量扫描
        // 都更新它，因此无论是字节预算还是行预算停下，`next_cursor` 都指向真实返回的位置。
        let mut last_returned: Option<(String, i64)> = None;
        // 续传：上一页的字节预算停在某条 Turn 内部时，先取回同一条 Turn 的剩余条目，再从它更旧的
        // Turn 继续。
        let mut older_than = None;
        if let Some(resume) = &resume {
            older_than = Some(resume.end_ordinal);
            if resume.after_ordinal < resume.end_ordinal {
                let entry = turn_page_entry(
                    connection,
                    &resume.turn_id,
                    resume.after_ordinal,
                    PAGE_BYTE_BUDGET,
                )
                .await?
                .context("history cursor does not belong to this Thread")?;
                used = used.saturating_add(entry.bytes);
                last_returned = Some((resume.turn_id.clone(), entry.after_ordinal));
                if entry.more {
                    next_cursor = Some(turn_page_cursor(
                        connection,
                        &self.state.thread_id,
                        &resume.turn_id,
                        entry.after_ordinal,
                        watermark,
                    )?);
                }
                turns.push(entry.history);
                if next_cursor.is_some() {
                    return Ok(pl_protocol::ThreadTurnPage { next_cursor, turns });
                }
            }
        }
        while turns.len() < limit {
            let take = limit - turns.len();
            // 多取一行只为判断“还有更旧的 Turn”；这一行不属于本页，下一页用严格更小的
            // `last_ordinal` 边界重新取回，因此不会跳过任何 Turn。
            let rows = match older_than {
                Some(bound) => {
                    connection
                        .db
                        .query_all_raw(statement(
                            "SELECT turn_id,first_ordinal,last_ordinal FROM history_turns
                             WHERE last_ordinal < ? ORDER BY last_ordinal DESC LIMIT ?",
                            vec![bound.into(), integer(take + 1)?.into()],
                        ))
                        .await?
                }
                None => {
                    connection
                        .db
                        .query_all_raw(statement(
                            "SELECT turn_id,first_ordinal,last_ordinal FROM history_turns
                             ORDER BY last_ordinal DESC LIMIT ?",
                            vec![integer(take + 1)?.into()],
                        ))
                        .await?
                }
            };
            if rows.is_empty() {
                break;
            }
            let more_turns = rows.len() > take;
            let mut last_end = older_than;
            let mut stopped = false;
            for row in rows.into_iter().take(take) {
                let turn_id: String = row.try_get("", "turn_id")?;
                let first_ordinal: i64 = row.try_get("", "first_ordinal")?;
                let end_ordinal: i64 = row.try_get("", "last_ordinal")?;
                let budget = PAGE_BYTE_BUDGET.saturating_sub(used);
                let Some(entry) = turn_page_entry(
                    connection,
                    &turn_id,
                    first_ordinal.saturating_sub(1),
                    budget,
                )
                .await?
                else {
                    continue;
                };
                // 整条 Turn 都装不进本页时留在下一页（游标指向本页最后返回的位置）。本页第一条
                // 永远返回，否则游标无法前进。
                if !turns.is_empty() && entry.bytes > budget {
                    stopped = true;
                    break;
                }
                used = used.saturating_add(entry.bytes);
                last_returned = Some((turn_id, entry.after_ordinal));
                last_end = Some(end_ordinal);
                let window_truncated = entry.more;
                turns.push(entry.history);
                if window_truncated {
                    // 字节或行预算在这条 Turn 内部用尽：游标停在窗口内的最后一条条目上。
                    stopped = true;
                    break;
                }
            }
            if !stopped && !more_turns {
                next_cursor = None;
                break;
            }
            let Some((turn_id, after_ordinal)) = &last_returned else {
                // 唯一一条候选 Turn 都取不到（历史被外部改写）：没有可续传的位置。
                next_cursor = None;
                break;
            };
            next_cursor = Some(turn_page_cursor(
                connection,
                &self.state.thread_id,
                turn_id,
                *after_ordinal,
                watermark,
            )?);
            if stopped || turns.len() >= limit {
                break;
            }
            older_than = last_end;
        }
        Ok(pl_protocol::ThreadTurnPage { next_cursor, turns })
    }

    pub(crate) async fn agent_page(
        &self,
        descending: bool,
        text_only: bool,
        anchor: Option<u64>,
        ceiling: Option<u64>,
        through: Option<u64>,
        limit: usize,
    ) -> Result<(u64, u64, Vec<ThreadItem>, bool)> {
        // 行上限与探测行必须用同一份 limit：早先的写法按调用方 limit 比较 `has_more`，却把
        // SQL LIMIT 截到 51，limit > 50 时会返回 51 条却宣称“没有更多”。这里先收敛 limit，再
        // 多取一行作为“确实还有匹配条目”的证据。
        let limit = limit.clamp(1, AGENT_PAGE_ROW_LIMIT);
        let Some(connection) = self.reader().await? else {
            // 缺失历史库：空窗口，且读操作绝不创建它。
            return Ok((0, 0, Vec::new(), false));
        };
        let watermark = connection_watermark(connection).await?;
        if let Some(through) = through {
            ensure!(
                through <= watermark,
                "agent session cursor is ahead of durable history"
            );
        }
        let ceiling = match ceiling {
            Some(ceiling) => ceiling,
            None => {
                let row = connection
                    .db
                    .query_one_raw(statement(
                        "SELECT COALESCE(MAX(ordinal),0) AS ordinal FROM history_items",
                        vec![],
                    ))
                    .await?
                    .context("history ceiling query returned no row")?;
                u64::try_from(row.try_get::<i64>("", "ordinal")?)?
            }
        };
        let mut predicates = vec!["ordinal <= ?"];
        let mut values = vec![integer(ceiling)?.into()];
        if let Some(anchor) = anchor {
            predicates.push(if descending {
                "ordinal < ?"
            } else {
                "ordinal > ?"
            });
            values.push(integer(anchor)?.into());
        }
        if text_only {
            predicates.push("kind = 'text'");
        }
        values.push(integer(limit + 1)?.into());
        let sql = format!(
            "SELECT payload FROM history_items WHERE {} ORDER BY ordinal {} LIMIT ?",
            predicates.join(" AND "),
            if descending { "DESC" } else { "ASC" }
        );
        let mut items = query_items(&connection.db, &sql, values).await?;
        let has_more = items.len() > limit;
        items.truncate(limit);
        Ok((watermark, ceiling, items, has_more))
    }

    /// Reads one committed timeline item by its durable identity.
    ///
    /// The projection owner needs the canonical committed body of an identity whose live preview already
    /// released it (for example the tool result a reliable-output repair names) so the *same* owner can
    /// still project the repaired fact with its own content version instead of the writer inventing one.
    /// This is a read of an already-committed fact, never a read-back of the effect being written.
    pub(crate) async fn item(&self, item_id: &str) -> Result<Option<ThreadItem>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT payload FROM history_items WHERE item_id=?",
                vec![item_id.to_owned().into()],
            ))
            .await?;
        row.map(|row| {
            let payload: String = row.try_get("", "payload")?;
            Ok(serde_json::from_str(&payload)?)
        })
        .transpose()
    }
}

impl ChatHistory for HistoryStore {
    /// 产品展示预算：正文合计 32 KiB，工具参数与结果各最多 4 KiB。
    ///
    /// 有界预览由这一处统一实现，因此页、订阅基线与实时出帧共用同一份裁剪规则；裁剪按
    /// `ContentBlock` 前缀复用，不再重新解码/重编码整条 JSON。
    fn bounded(&self, item: &ChatItem) -> std::result::Result<ChatItem, ChatError> {
        crate::studio::runtime::timeline_content::preview::bounded(item)
    }

    async fn latest_allocated_order(&self) -> std::result::Result<u64, ChatError> {
        HistoryStore::latest_allocated_order(self)
            .await
            .map_err(chat_history_error)
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> std::result::Result<ChatHistoryPage, ChatError> {
        if let Some(before) = before {
            self.ensure_cursor_identity(before).await?;
        }
        self.chat_page(before, limit)
            .await
            .map_err(chat_history_error)
    }

    async fn item(&self, item_id: &str) -> std::result::Result<Option<ChatItem>, ChatError> {
        self.read_chat_item(item_id)
            .await
            .map_err(chat_history_error)
    }
}

impl HistoryStore {
    /// 校验游标身份与它命名的 durable 顺序一致。
    ///
    /// 顺序槽严格递增且永不复用，因此 `ordinal < ?` 恰好就是严格 `(ordinal, identity)` 边界；这里
    /// 用一次 rowid 点查保证：如果该顺序已经有行，它的 identity 必须就是游标声明的那个，否则拒绝，
    /// 绝不把游标当成「附近某条」的猜测位置。该顺序还没有 durable 行是合法情形——边界可以指向尚未
    /// 落盘的权威条目。
    async fn ensure_cursor_identity(
        &self,
        before: &ChatCursor,
    ) -> std::result::Result<(), ChatError> {
        let connection = self.reader().await.map_err(chat_history_error)?;
        let Some(connection) = connection else {
            return Ok(());
        };
        let ordinal = integer(before.order).map_err(chat_history_error)?.into();
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT item_id FROM history_items WHERE ordinal=?",
                vec![ordinal],
            ))
            .await
            .map_err(anyhow::Error::new)
            .map_err(chat_history_error)?;
        let Some(row) = row else {
            return Ok(());
        };
        let item_id: String = row
            .try_get("", "item_id")
            .map_err(anyhow::Error::new)
            .map_err(chat_history_error)?;
        if item_id == before.item_id {
            return Ok(());
        }
        Err(ChatError::InvalidArgument(format!(
            "timeline cursor names order {} with a different identity",
            before.order
        )))
    }
}

pub(crate) fn chat_item(item: ThreadItem, saved: bool) -> Result<ChatItem> {
    typed_item(item, saved)
}

fn chat_history_error(error: anyhow::Error) -> ChatError {
    ChatError::History(error.into_boxed_dyn_error())
}

/// One query implementation for hot fixed-fence reads and strict read-only checkpoint snapshots.
async fn read_latest_turn_at(
    tx: &impl ConnectionTrait,
    thread_id: &str,
    history_fence: u64,
) -> Result<Option<pl_protocol::Turn>> {
    let fence = integer(history_fence)?;
    ensure!(
        applied_write_seq(tx).await? == fence,
        "child history changed or does not cover the evaluation fence"
    );
    let latest = tx
        .query_one_raw(statement(
            "SELECT turn_id,last_write_seq FROM history_items WHERE kind='turn'
             ORDER BY ordinal DESC LIMIT 1",
            vec![],
        ))
        .await?;
    let Some(latest) = latest else {
        return Ok(None);
    };
    let turn_id: String = latest.try_get("", "turn_id")?;
    let item_sequence: i64 = latest.try_get("", "last_write_seq")?;
    let row = tx
        .query_one_raw(statement(
            "SELECT payload,last_write_seq FROM history_turns WHERE turn_id=?",
            vec![turn_id.clone().into()],
        ))
        .await?
        .context("latest Turn item has no committed Turn record")?;
    let payload: String = row.try_get("", "payload")?;
    let history: TimelineTurn = serde_json::from_str(&payload)?;
    ensure!(
        history.turn.id == turn_id
            && history.turn.thread_id == thread_id
            && integer(history.turn.revision)? == item_sequence
            && item_sequence <= row.try_get::<i64>("", "last_write_seq")?
            && row.try_get::<i64>("", "last_write_seq")? <= fence,
        "latest Turn record does not match its committed identity or fence"
    );
    Ok(Some(history.turn))
}

async fn connect(path: &Path) -> Result<DatabaseConnection> {
    initialization::validate_database_path(path).await?;
    let mut options = crate::studio::paths::sqlite_file_options(
        path,
        crate::studio::paths::SqliteFileMode::Create,
        |options| {
            options
                .journal_mode(SqliteJournalMode::Wal)
                .synchronous(SqliteSynchronous::Full)
                .busy_timeout(Duration::from_secs(5))
                .foreign_keys(true)
        },
    )
    .await?;
    options
        .max_connections(1)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    Ok(Database::connect(options).await?)
}

/// 一次历史写事务在放弃之前额外重试的次数（每次都会先等 `busy_timeout`）。
const HISTORY_WRITE_RETRIES: u32 = 2;

/// Begins one history write transaction that takes the write lock up front.
///
/// `BEGIN DEFERRED` only upgrades its read lock when the first write statement runs, and SQLite
/// reports `SQLITE_BUSY` for a failed upgrade *without* invoking the busy handler — so the
/// configured `busy_timeout` cannot serialize two writers that both read before they write. Every
/// history write reads the applied waterline and then writes it in
/// the same transaction, so it must start as a writer: `BEGIN IMMEDIATE` makes the busy handler do
/// the waiting, and a transaction that still finds the lock held past the timeout is retried a
/// bounded number of times before it is reported. A structural failure (constraint, corruption)
/// is never retried.
async fn begin_write(db: &DatabaseConnection) -> Result<sea_orm::DatabaseTransaction> {
    let mut attempt: u32 = 0;
    loop {
        let started = db
            .begin_with_options(TransactionOptions {
                sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
                ..Default::default()
            })
            .await;
        match started {
            Ok(tx) => return Ok(tx),
            Err(error)
                if attempt < HISTORY_WRITE_RETRIES && is_retryable_write(&error.to_string()) =>
            {
                attempt += 1;
                // The busy handler already waited for the lock; a short pause only gives the other
                // writer a chance to commit before this attempt re-acquires it.
                tokio::time::sleep(Duration::from_millis(50 * u64::from(attempt))).await;
            }
            Err(error) => return Err(error.into()),
        }
    }
}

/// 只有忙/锁/IO 类错误允许在写者内部有界重试；结构与约束错误必须立刻失败闭锁。
///
/// 与全局 call writer 的判定保持同一集合：一次瞬时 `SQLITE_BUSY`/`SQLITE_LOCKED`/`SQLITE_IOERR`
/// 既不丢事实也不得升级成终态持久化失败，而约束/损坏类错误必须原样上报。
pub(crate) fn is_retryable_write(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("database is locked")
        || message.contains("database table is locked")
        || message.contains("database is busy")
        || message.contains("disk i/o error")
        || message.contains("sqlite_busy")
        || message.contains("sqlite_locked")
        || message.contains("sqlite_ioerr")
}

/// Opens an *existing* history database read-only, without creating or upgrading anything.
///
/// `mode=ro` makes SQLite refuse to create a missing file, and no schema/journal PRAGMA that would
/// mutate the database is issued here; a concurrent WAL writer stays visible through its
/// checkpoint, so cold pagination is neither gated on nor able to disturb the writer.
async fn connect_read_only(path: &Path) -> Result<DatabaseConnection> {
    initialization::validate_database_path(path).await?;
    let mut options = crate::studio::paths::sqlite_file_options(
        path,
        crate::studio::paths::SqliteFileMode::ReadOnly,
        |options| {
            // Only read-safe settings: cold reads must not change the journal or schema.
            options
                .busy_timeout(Duration::from_secs(5))
                .foreign_keys(true)
        },
    )
    .await?;
    options
        .max_connections(1)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    Database::connect(options).await.with_context(|| {
        format!(
            "history database could not be opened read-only: {}",
            path.display()
        )
    })
}

/// Validates an existing history database's schema, Thread and database identity without writing.
///
/// A missing identity row, an unsupported schema version, a foreign Thread or an empty database id
/// fails closed so a cold read reports the damage instead of adopting or rebuilding the store.
async fn validate_existing(db: &impl ConnectionTrait, thread_id: &str) -> Result<(String, i64)> {
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version,database_id,thread_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await
        .context("history database has no readable identity table")?;
    let row = row.context("history database identity row is missing")?;
    let version: i64 = row.try_get("", "schema_version")?;
    ensure!(
        version == HISTORY_SCHEMA_VERSION,
        "unsupported history schema {version}; existing data preserved"
    );
    let owner: String = row.try_get("", "thread_id")?;
    ensure!(
        owner == thread_id,
        "history database belongs to another Thread"
    );
    let database_id: String = row.try_get("", "database_id")?;
    ensure!(
        !database_id.is_empty(),
        "history database identity is empty"
    );
    current::verify_completion(db).await?;
    Ok((database_id, version))
}

async fn write_tool_task(
    tx: &impl ConnectionTrait,
    write_seq: i64,
    task: &pl_core::thread::task::TaskRecord,
) -> Result<()> {
    let payload = serde_json::to_string(task)?;
    let existing = tx
        .query_one_raw(statement(
            "SELECT revision,task_payload FROM history_tool_tasks WHERE call_id=?",
            vec![task.call_id.clone().into()],
        ))
        .await?;
    if let Some(existing) = existing {
        let revision: i64 = existing.try_get("", "revision")?;
        if revision >= integer(task.revision)? {
            if revision == integer(task.revision)? {
                let stored: String = existing.try_get("", "task_payload")?;
                ensure!(
                    stored == payload,
                    "tool task {} conflicts with committed revision",
                    task.id
                );
            }
            return Ok(());
        }
    }
    tx.execute_raw(statement(
        "INSERT INTO history_tool_tasks(call_id,revision,task_payload,delivery_payload,last_write_seq)
         VALUES(?,?,?,NULL,?) ON CONFLICT(call_id) DO UPDATE SET
         revision=excluded.revision,task_payload=excluded.task_payload,
         last_write_seq=excluded.last_write_seq",
        vec![task.call_id.clone().into(), integer(task.revision)?.into(), payload.into(), write_seq.into()],
    ))
    .await?;
    Ok(())
}

async fn write_tool_delivery(
    tx: &impl ConnectionTrait,
    write_seq: i64,
    delivery: &pl_core::thread::ToolDelivery,
) -> Result<()> {
    let payload = serde_json::to_string(delivery)?;
    let existing = tx
        .query_one_raw(statement(
            "SELECT task_payload,delivery_payload FROM history_tool_tasks WHERE call_id=?",
            vec![delivery.call_id.clone().into()],
        ))
        .await?
        .with_context(|| format!("tool delivery {} has no admitted task", delivery.call_id))?;
    if let Some(stored) = existing.try_get::<Option<String>>("", "delivery_payload")? {
        ensure!(
            stored == payload,
            "tool delivery {} conflicts with committed body",
            delivery.call_id
        );
        return Ok(());
    }
    let task_payload: String = existing.try_get("", "task_payload")?;
    let mut task: pl_core::thread::task::TaskRecord = serde_json::from_str(&task_payload)?;
    if task.status == pl_core::thread::task::TaskStatus::Running {
        task.status = match delivery.outcome {
            pl_core::thread::ToolOutcome::Succeeded => pl_core::thread::task::TaskStatus::Succeeded,
            pl_core::thread::ToolOutcome::Failed(_) => pl_core::thread::task::TaskStatus::Failed,
            pl_core::thread::ToolOutcome::Cancelled => pl_core::thread::task::TaskStatus::Cancelled,
            pl_core::thread::ToolOutcome::Interrupted => {
                pl_core::thread::task::TaskStatus::Interrupted
            }
        };
        task.revision = task
            .revision
            .checked_add(1)
            .context("tool task revision exhausted")?;
        if task.status == pl_core::thread::task::TaskStatus::Cancelled {
            task.cancel_requested = true;
        }
    }
    tx.execute_raw(statement(
        "UPDATE history_tool_tasks SET revision=?,task_payload=?,delivery_payload=?,last_write_seq=? WHERE call_id=?",
        vec![integer(task.revision)?.into(), serde_json::to_string(&task)?.into(), payload.into(), write_seq.into(), delivery.call_id.clone().into()],
    ))
    .await?;
    Ok(())
}

/// Folds one repaired resource reference into the delivery the Thread already committed.
///
/// The delivery is the durable authority for a tool's full resource set, so a reference the retry
/// stored after the result was committed is recorded there as well as on the projected item. The
/// delivery keeps its call identity, outcome and every already-committed reference; an identical
/// reference is never appended twice, so a repeated repair cannot duplicate the fact or move the
/// result. A repair whose result is not committed yet is not written here at all: the owner keeps it
/// pending until the commit that carries the result, so a reference can never land in history
/// without the delivery it supplements.
///
/// This only supplements a durable delivery fact; the canonical timeline item and its content version
/// are produced by the Thread's single projection owner, never invented here.
async fn write_tool_delivery_repair(
    tx: &impl ConnectionTrait,
    write_seq: i64,
    repair: &pl_core::thread::cold::OutputRepair,
) -> Result<()> {
    let existing = tx
        .query_one_raw(statement(
            "SELECT delivery_payload FROM history_tool_tasks WHERE call_id=?",
            vec![repair.call_id.clone().into()],
        ))
        .await?;
    let Some(row) = existing else {
        return Ok(());
    };
    let Some(stored) = row.try_get::<Option<String>>("", "delivery_payload")? else {
        return Ok(());
    };
    let mut delivery: pl_core::thread::ToolDelivery = serde_json::from_str(&stored)?;
    let resource = pl_core::context::ContextContent::Resource {
        reference: repair.reference.clone(),
    };
    if delivery.delivered_context.contains(&resource) {
        return Ok(());
    }
    delivery.delivered_context.push(resource);
    tx.execute_raw(statement(
        "UPDATE history_tool_tasks SET delivery_payload=?,last_write_seq=? WHERE call_id=?",
        vec![
            serde_json::to_string(&delivery)?.into(),
            write_seq.into(),
            repair.call_id.clone().into(),
        ],
    ))
    .await?;
    Ok(())
}

/// Current durable write sequence of one already-open connection.
async fn connection_watermark(connection: &HistoryConnection) -> Result<u64> {
    u64::try_from(applied_write_seq(&connection.db).await?)
        .context("negative history write sequence")
}

/// Turn 页的续传位置。
///
/// `after_ordinal` 是本页最后返回的条目 ordinal，`end_ordinal` 是这条 Turn 的 durable 结尾；
/// 两者相等表示这条 Turn 已完整返回，下一页从更旧的 Turn 继续。
#[derive(Debug, Clone)]
struct TurnPageResume {
    turn_id: String,
    after_ordinal: i64,
    end_ordinal: i64,
}

/// 一条 Turn 在一个 Turn 页里的条目窗口。
struct TurnPageEntry {
    history: pl_protocol::ThreadTurnHistory,
    /// 窗口内最后一条条目的 ordinal；窗口为空时等于 Turn 结尾。
    after_ordinal: i64,
    /// 这条 Turn 是否还有未返回的条目。
    more: bool,
    /// 本条 entry 计入整页预算的序列化字节（与 item 页同一计量方式）。
    bytes: usize,
}

/// 构造 Turn 页的版本化游标：绑定 Thread、数据库身份、水位与 Turn 内的续传位置。
///
/// 复用 [`TimelineCursor`] 的自校验封装（ordinal 位置、`item_id` 位置存 Turn id），因此数据库
/// 重建、跨 Thread 或水位回退的游标都会被拒绝，而不是被当成“附近某条”静默沿用。
fn turn_page_cursor(
    connection: &HistoryConnection,
    thread_id: &str,
    turn_id: &str,
    after_ordinal: i64,
    watermark: u64,
) -> Result<String> {
    Ok(TimelineCursor::new(
        thread_id.to_owned(),
        connection.database_id.clone(),
        u64::try_from(after_ordinal)?,
        turn_id.to_owned(),
        watermark,
    )
    .encode())
}

/// 解析 Turn 页游标，返回它在本数据库内的续传位置。
///
/// 版本化 token 是唯一的合法输入：它逐项校验 Thread、数据库身份、水位，并要求游标落在该 Turn
/// 自己的条目上。任何非版本化输入（例如旧版原始 `turn_id`）都无法在数据库被替换后绑定到本库的
/// 身份与水位——同名 Turn 仍然存在时静默沿用等于把游标当成本库“附近某条”——因此显式失败，由调用
/// 方重新加载窗口，而不是回退兼容或猜测位置。
async fn turn_page_resume(
    connection: &HistoryConnection,
    thread_id: &str,
    cursor: &str,
    watermark: u64,
) -> Result<TurnPageResume> {
    let parsed = TimelineCursor::decode(cursor)
        .context("Turn cursor is not a versioned history cursor; restart the page")?;
    ensure!(
        parsed.thread_id == thread_id,
        "timeline cursor belongs to another Thread"
    );
    ensure!(
        parsed.database_id == connection.database_id,
        "timeline cursor belongs to a rebuilt history database; restart the page"
    );
    ensure!(
        parsed.applied_write_sequence <= watermark,
        "timeline cursor was read from a newer history than this database"
    );
    let row = connection
        .db
        .query_one_raw(statement(
            "SELECT turn_id,last_ordinal FROM history_turns WHERE turn_id=?",
            vec![parsed.item_id.clone().into()],
        ))
        .await?
        .context("timeline cursor Turn no longer exists; restart the page")?;
    let stored_turn: String = row.try_get("", "turn_id")?;
    ensure!(
        stored_turn == parsed.item_id,
        "timeline cursor Turn identity changed; restart the page"
    );
    let end_ordinal: i64 = row.try_get("", "last_ordinal")?;
    let after_ordinal = i64::try_from(parsed.ordinal).context("timeline cursor is out of range")?;
    ensure!(
        after_ordinal <= end_ordinal,
        "timeline cursor is ahead of the durable Turn end; restart the page"
    );
    // 游标必须落在该 Turn 自己的条目上：位置被改写时明确失败，绝不猜一个相邻位置。
    let anchor = connection
        .db
        .query_one_raw(statement(
            "SELECT turn_id FROM history_items WHERE ordinal=?",
            vec![after_ordinal.into()],
        ))
        .await?
        .context("timeline cursor item no longer exists; restart the page")?;
    let anchor_turn: String = anchor.try_get("", "turn_id")?;
    ensure!(
        anchor_turn == parsed.item_id,
        "timeline cursor item identity changed; restart the page"
    );
    Ok(TurnPageResume {
        turn_id: parsed.item_id,
        after_ordinal,
        end_ordinal,
    })
}

/// 取一条 Turn 在 `after_ordinal` 之后的条目窗口。
///
/// 条目按 ordinal 升序、连续前缀返回，受 [`TURN_PAGE_ITEM_LIMIT`] 行与 `budget` 字节约束；
/// 窗口为空时返回 `None`（这条 Turn 没有条目，通常意味着历史被外部改写）。至少返回一条条目，
/// 否则超大条目的截断点无法让游标前进。
async fn turn_page_entry(
    connection: &HistoryConnection,
    turn_id: &str,
    after_ordinal: i64,
    budget: usize,
) -> Result<Option<TurnPageEntry>> {
    let Some(row) = connection
        .db
        .query_one_raw(statement(
            "SELECT last_ordinal,payload FROM history_turns WHERE turn_id=?",
            vec![turn_id.into()],
        ))
        .await?
    else {
        return Ok(None);
    };
    let end_ordinal: i64 = row.try_get("", "last_ordinal")?;
    let turn: TimelineTurn = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
    // 多取一行探测这条 Turn 是否还有更晚的条目。
    let rows = query_items(
        &connection.db,
        "SELECT payload FROM history_items
             WHERE turn_id=? AND ordinal > ? ORDER BY ordinal ASC LIMIT ?",
        vec![
            turn_id.into(),
            after_ordinal.into(),
            integer(TURN_PAGE_ITEM_LIMIT + 1)?.into(),
        ],
    )
    .await?;
    let mut more = rows.len() > TURN_PAGE_ITEM_LIMIT;
    let mut used = serde_json::to_string(&turn)?.len();
    let mut items = Vec::new();
    for item in rows.into_iter().take(TURN_PAGE_ITEM_LIMIT) {
        let size = serde_json::to_string(&item)?.len();
        if !items.is_empty() && used.saturating_add(size) > budget {
            more = true;
            break;
        }
        used = used.saturating_add(size);
        items.push(item);
    }
    let after_ordinal = match items.last() {
        Some(item) => integer(item.ordinal)?,
        // 这条 Turn 没有可返回的条目：直接标记为已完整返回，避免游标停在原地打转。
        None => end_ordinal,
    };
    Ok(Some(TurnPageEntry {
        history: pl_protocol::ThreadTurnHistory {
            turn: turn.turn,
            items,
            context_disposition: turn.context_disposition,
        },
        after_ordinal,
        more,
        bytes: used,
    }))
}

async fn query_items(
    db: &DatabaseConnection,
    sql: &str,
    values: Vec<Value>,
) -> Result<Vec<ThreadItem>> {
    db.query_all_raw(statement(sql, values))
        .await?
        .into_iter()
        .map(|row| {
            let payload: String = row.try_get("", "payload")?;
            Ok(serde_json::from_str(&payload)?)
        })
        .collect()
}

async fn query_chat_ids(
    db: &DatabaseConnection,
    sql: &str,
    values: Vec<Value>,
) -> Result<Vec<(u64, String)>> {
    db.query_all_raw(statement(sql, values))
        .await?
        .into_iter()
        .map(|row| {
            Ok((
                u64::try_from(row.try_get::<i64>("", "ordinal")?)?,
                row.try_get("", "item_id")?,
            ))
        })
        .collect()
}

fn statement(sql: &str, values: Vec<Value>) -> Statement {
    Statement::from_sql_and_values(DatabaseBackend::Sqlite, sql, values)
}

/// Writes one minimal input identity inside the transaction of the effect that produced it.
///
/// Only the small `(id, digest, delivery, state, ordinal, revision)` record is kept, never the
/// admitted body or its context, so the index grows far more slowly than the timeline and never
/// becomes a second copy of history. It exists so the runtime can answer a repeated submission
/// after the input left core state without loading historical entities back into core.
///
/// A repeated write of the same identity only refreshes its bookkeeping. A different digest for an
/// already-recorded id is an identity conflict: the accepted identity is never silently
/// overwritten, and the conflict fails the whole effect transaction instead.
async fn write_input_identity(
    db: &impl ConnectionTrait,
    write_seq: i64,
    identity: &InputIdentityWrite,
) -> Result<()> {
    let existing = db
        .query_one_raw(statement(
            "SELECT digest,presentation,request_digest,payload FROM history_input_identities
             WHERE item_id=?",
            vec![identity.entry.id.clone().into()],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: String = row.try_get("", "digest")?;
        ensure!(
            stored == identity.entry.digest,
            "input identity {} conflicts with its durable record",
            identity.entry.id
        );
        let presentation: Option<String> = row.try_get("", "presentation")?;
        ensure!(
            presentation
                .as_deref()
                .is_none_or(|stored| stored == presentation_label(identity.presentation)),
            "input identity {} conflicts with its durable presentation",
            identity.entry.id
        );
        // A control operation's request identity is the *first* admission, not whatever the current
        // commit can recompute. These fields are insert-if-absent: once a row carries them, the newer
        // commit can neither overwrite nor falsify them, so a later route change, a later consumption
        // or a later state advance still answers with the original receipt.
        let mut entry = identity.entry.clone();
        let mut request_digest = identity.request_digest.clone();
        if entry.purpose == pl_core::thread::input::InputPurpose::Continuation {
            let stored_entry: crate::studio::storage::state::InputIdentityEntry =
                serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
            entry.expected_model_route_revision = stored_entry
                .expected_model_route_revision
                .or(entry.expected_model_route_revision);
            entry.continuation_admission_revision = stored_entry
                .continuation_admission_revision
                .or(entry.continuation_admission_revision);
            request_digest = row
                .try_get::<Option<String>>("", "request_digest")?
                .or(request_digest);
        }
        let payload = serde_json::to_string(&entry)?;
        db.execute_raw(statement(
            "UPDATE history_input_identities
             SET ordinal=?,revision=?,request_digest=?,presentation=?,payload=?,last_write_seq=?
             WHERE item_id=?",
            vec![
                integer(entry.ordinal)?.into(),
                integer(entry.revision)?.into(),
                request_digest.into(),
                presentation_label(identity.presentation).into(),
                payload.into(),
                write_seq.into(),
                entry.id.clone().into(),
            ],
        ))
        .await?;
        return Ok(());
    }
    let payload = serde_json::to_string(&identity.entry)?;
    db.execute_raw(statement(
        "INSERT INTO history_input_identities(
            item_id,ordinal,revision,digest,request_digest,presentation,payload,last_write_seq
         )
         VALUES(?,?,?,?,?,?,?,?)",
        vec![
            identity.entry.id.clone().into(),
            integer(identity.entry.ordinal)?.into(),
            integer(identity.entry.revision)?.into(),
            identity.entry.digest.clone().into(),
            identity.request_digest.clone().into(),
            presentation_label(identity.presentation).into(),
            payload.into(),
            write_seq.into(),
        ],
    ))
    .await?;
    Ok(())
}

fn presentation_label(presentation: pl_protocol::MessagePresentation) -> &'static str {
    match presentation {
        pl_protocol::MessagePresentation::Visible => "visible",
        pl_protocol::MessagePresentation::Hidden => "hidden",
    }
}

/// Records the minimal durable identity of one message this effect admitted.
///
/// The row shares the effect's transaction, so the receipt can never be durable without the history
/// fact that admitted the message. A repeated write of the same identity with the same digest only
/// refreshes its bookkeeping. A different digest for an already-recorded identity never overwrites
/// the accepted identity: the conflict fails the whole effect transaction. A row that exists without
/// a digest (a migration backfill) is left untouched, so its readers keep failing closed instead of
/// silently replacing an unverifiable accepted identity.
async fn write_message_identity(
    db: &impl ConnectionTrait,
    write_seq: i64,
    identity: &MessageIdentityWrite,
) -> Result<()> {
    ensure!(
        !identity.message_id.is_empty() && !identity.item_id.is_empty(),
        "durable message identity must not be empty"
    );
    let existing = db
        .query_one_raw(statement(
            "SELECT digest FROM history_message_identities WHERE message_id=?",
            vec![identity.message_id.clone().into()],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: Option<String> = row.try_get("", "digest")?;
        match (&stored, &identity.digest) {
            (Some(stored), Some(digest)) => ensure!(
                stored == digest,
                "message identity {} conflicts with its durable record",
                identity.message_id
            ),
            // A backfilled row proves the identity but not the body; it is never overwritten.
            (None, _) => return Ok(()),
            (Some(_), None) => return Ok(()),
        }
        db.execute_raw(statement(
            "UPDATE history_message_identities
             SET item_id=?,sequence=?,digest=?,last_write_seq=?
             WHERE message_id=?",
            vec![
                identity.item_id.clone().into(),
                integer(identity.sequence)?.into(),
                identity.digest.clone().into(),
                write_seq.into(),
                identity.message_id.clone().into(),
            ],
        ))
        .await?;
        return Ok(());
    }
    db.execute_raw(statement(
        "INSERT INTO history_message_identities(
            message_id,item_id,sequence,digest,last_write_seq
         )
         VALUES(?,?,?,?,?)",
        vec![
            identity.message_id.clone().into(),
            identity.item_id.clone().into(),
            integer(identity.sequence)?.into(),
            identity.digest.clone().into(),
            write_seq.into(),
        ],
    ))
    .await?;
    Ok(())
}

/// Writes one canonical fact receipt in the same transaction as the effect that produced it.
/// The digest is taken from the canonical source payload (the committed record), so a repeated
/// write of the same `(item_id, revision)` is idempotent while a different payload for an
/// already-recorded revision is an identity conflict that fails the whole effect transaction.
/// Receipts are immutable per revision: a newer revision is a new row, never an overwrite of an
/// older terminal fact.
async fn write_fact_receipt(
    db: &impl ConnectionTrait,
    write_seq: i64,
    receipt: &FactReceiptWrite,
) -> Result<()> {
    ensure!(
        !receipt.item_id.is_empty(),
        "durable fact receipt identity must not be empty"
    );
    let digest = pl_core::context::content_hash(receipt.payload.as_bytes());
    let revision = integer(receipt.revision)?;
    let existing = db
        .query_one_raw(statement(
            "SELECT digest FROM history_fact_receipts WHERE item_id=? AND revision=?",
            vec![receipt.item_id.clone().into(), revision.into()],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: String = row.try_get("", "digest")?;
        ensure!(
            stored == digest,
            "durable fact receipt {}@{} conflicts with its recorded payload",
            receipt.item_id,
            receipt.revision
        );
        db.execute_raw(statement(
            "UPDATE history_fact_receipts SET kind=?,payload=?,last_write_seq=?
             WHERE item_id=? AND revision=?",
            vec![
                receipt.kind.to_owned().into(),
                receipt.payload.clone().into(),
                write_seq.into(),
                receipt.item_id.clone().into(),
                revision.into(),
            ],
        ))
        .await?;
        return Ok(());
    }
    db.execute_raw(statement(
        "INSERT INTO history_fact_receipts(item_id,revision,kind,digest,payload,last_write_seq)
         VALUES(?,?,?,?,?,?)",
        vec![
            receipt.item_id.clone().into(),
            revision.into(),
            receipt.kind.to_owned().into(),
            digest.into(),
            receipt.payload.clone().into(),
            write_seq.into(),
        ],
    ))
    .await?;
    Ok(())
}

async fn applied_write_seq(db: &impl ConnectionTrait) -> Result<i64> {
    Ok(db
        .query_one_raw(statement(
            "SELECT applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history metadata is missing")?
        .try_get("", "applied_write_seq")?)
}

fn integer(value: impl TryInto<i64>) -> Result<i64> {
    value
        .try_into()
        .map_err(|_| anyhow::anyhow!("history integer exceeds SQLite range"))
}

fn kind_label(kind: ThreadItemKind) -> &'static str {
    match kind {
        ThreadItemKind::Raw => "raw",
        ThreadItemKind::Text => "text",
        ThreadItemKind::Thinking => "thinking",
        ThreadItemKind::Tool => "tool",
        ThreadItemKind::Agent => "agent",
        ThreadItemKind::Turn => "turn",
        ThreadItemKind::Inference => "inference",
        ThreadItemKind::Skill => "skill",
        ThreadItemKind::File => "file",
        ThreadItemKind::PublicArtifact => "publicArtifact",
        ThreadItemKind::ContextCompaction => "contextCompaction",
    }
}

#[cfg(test)]
pub(super) mod test_support {
    use super::*;

    #[derive(Debug, PartialEq, Eq)]
    pub(in crate::studio::storage) struct SourceEvidence {
        main: Vec<u8>,
        wal: Option<Vec<u8>>,
        tables: Vec<(String, String, Vec<(i64, String)>)>,
    }

    pub(in crate::studio::storage) async fn source_evidence(path: &Path) -> Result<SourceEvidence> {
        let db = connect_read_only(path).await?;
        let tx = db.begin().await?;
        let mut tables = Vec::new();
        for row in tx.query_all_raw(statement(
            "SELECT name,sql FROM sqlite_schema WHERE type='table' AND name NOT GLOB 'sqlite_*' ORDER BY name", vec![]
        )).await? {
            let name: String = row.try_get("", "name")?;
            let sql: String = row.try_get("", "sql")?;
            let quoted = format!("\"{}\"", name.replace('"', "\"\""));
            let mut fields = Vec::new();
            for column in tx.query_all_raw(statement(&format!("PRAGMA table_xinfo({quoted})"), vec![])).await? {
                let column: String = column.try_get("", "name")?;
                fields.push(format!("quote(\"{}\")", column.replace('"', "\"\"")));
            }
            let rows = tx.query_all_raw(statement(&format!(
                "SELECT rowid AS source_rowid,json_array({}) AS original FROM {quoted} ORDER BY rowid", fields.join(",")
            ), vec![])).await?;
            let values = rows.into_iter().map(|row| Ok((row.try_get("", "source_rowid")?, row.try_get("", "original")?)))
                .collect::<Result<Vec<_>>>()?;
            tables.push((name, sql, values));
        }
        tx.rollback().await?;
        db.close().await?;
        // Capture after this inspector has settled its own SQLite read. Opening a closed WAL-mode
        // source may create an empty auxiliary WAL: that is the inspector's baseline, not an import
        // write. No bytes or presence facts are normalized away.
        let main = tokio::fs::read(path).await?;
        let mut wal_path = path.as_os_str().to_owned();
        wal_path.push("-wal");
        let wal = match tokio::fs::read(Path::new(&wal_path)).await {
            Ok(bytes) => Some(bytes),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(error) => return Err(error.into()),
        };
        Ok(SourceEvidence { main, wal, tables })
    }

    /// Inspects a fixture's immutable source without admitting it as a current HistoryStore.
    /// This is not a production fallback: ordinary readers still require the completed target.
    pub(in crate::studio::storage) async fn source_checkpoint(
        path: &Path,
        thread_id: &str,
    ) -> Result<Option<pl_core::thread::ThreadCheckpoint>> {
        let db = connect_read_only(path).await?;
        let tx = match db.begin().await {
            Ok(tx) => tx,
            Err(error) => {
                db.close().await?;
                return Err(error.into());
            }
        };
        let result = checkpoint::read(&tx, thread_id).await;
        let released = tx.rollback().await;
        let closed = db.close().await;
        let checkpoint = result?;
        released?;
        closed?;
        Ok(checkpoint)
    }

    /// Turns a test-owned current installation into a pre-upgrade fixture. Every fact is copied
    /// from one SQLite readonly snapshot (including committed WAL), with the old official create
    /// step as producer schema. Only the test-owned current family is removed after independent
    /// logical verification. No production migration calls this helper or deletes a source.
    pub(in crate::studio::storage) async fn seed_legacy_installation(
        current: &Path,
        legacy: &Path,
        thread_id: &str,
    ) -> Result<()> {
        assert_ne!(current, legacy);
        assert!(!legacy.exists());
        let before = source_evidence(current).await?;
        let db = connect(legacy).await?;
        schema::create_released_source(&db, thread_id).await?;
        let original = connect_read_only(current).await?;
        let snapshot = original.begin().await?;
        let tx = begin_write(&db).await?;
        import::copy_fixture_facts(&snapshot, &tx).await?;
        tx.commit().await?;
        snapshot.rollback().await?;
        original.close().await?;
        db.close().await?;
        let after = source_evidence(legacy).await?;
        let facts = |evidence: &SourceEvidence| {
            evidence
                .tables
                .iter()
                .filter(|(name, _, _)| {
                    !matches!(name.as_str(), "history_meta" | "seaql_migrations")
                })
                .map(|(name, _, rows)| (name.clone(), rows.clone()))
                .collect::<Vec<_>>()
        };
        assert_eq!(
            facts(&before),
            facts(&after),
            "fixture creation must not lose any raw row or identity"
        );
        let old = connect_read_only(legacy).await?;
        let new = connect_read_only(current).await?;
        let identity = |row: sea_orm::QueryResult| -> Result<(String, String, i64)> {
            Ok((
                row.try_get("", "database_id")?,
                row.try_get("", "thread_id")?,
                row.try_get("", "applied_write_seq")?,
            ))
        };
        assert_eq!(
            identity(
                old.query_one_raw(statement("SELECT * FROM history_meta WHERE id=1", vec![]))
                    .await?
                    .context("source meta")?
            )?,
            identity(
                new.query_one_raw(statement("SELECT * FROM history_meta WHERE id=1", vec![]))
                    .await?
                    .context("current meta")?
            )?
        );
        old.close().await?;
        new.close().await?;
        for suffix in ["-wal", "-shm", ""] {
            let mut path = current.as_os_str().to_owned();
            path.push(suffix);
            match tokio::fs::remove_file(Path::new(&path)).await {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(error.into()),
            }
        }
        Ok(())
    }

    pub(in crate::studio::storage) fn import_origin(
        source: &Path,
        thread_id: &str,
    ) -> Result<HistoryInitialization> {
        Ok(HistoryInitialization::ImportV2 {
            source_database: source.into(),
            legacy_state: super::super::state::StateStore::new(
                source.parent().context("source parent")?.into(),
                thread_id,
            ),
            migrate_execution_identity: std::sync::Arc::new(|_| Ok(())),
        })
    }

    pub(in crate::studio::storage) async fn import_source(
        source: &Path,
        target: &Path,
        thread_id: &str,
    ) -> Result<HistoryStore> {
        let history = HistoryStore::open(target, thread_id).await?;
        history
            .initialize(import_origin(source, thread_id)?)
            .await?;
        assert_current(target, thread_id).await?;
        Ok(history)
    }

    pub(in crate::studio::storage) async fn assert_current(
        path: &Path,
        thread_id: &str,
    ) -> Result<()> {
        let db = connect_read_only(path).await?;
        let row = db
            .query_one_raw(statement(
                "SELECT schema_version,thread_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("target meta")?;
        assert_eq!(
            row.try_get::<i64>("", "schema_version")?,
            HISTORY_SCHEMA_VERSION
        );
        assert_eq!(row.try_get::<String>("", "thread_id")?, thread_id);
        let records = db
            .query_all_raw(statement(
                "SELECT version FROM seaql_migrations ORDER BY version",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "version"))
            .collect::<Result<Vec<_>, _>>()?;
        assert_eq!(records, [current::CURRENT_STEP]);
        db.close().await?;
        Ok(())
    }

    pub(in crate::studio::storage) async fn assert_pending(target: &Path) -> Result<()> {
        assert!(
            !tokio::fs::try_exists(target).await?,
            "failed migration cannot publish canonical history"
        );
        let prefix = format!(
            ".{}.prepare-",
            target
                .file_name()
                .context("target filename")?
                .to_string_lossy()
        );
        let mut entries = tokio::fs::read_dir(target.parent().context("target parent")?).await?;
        let mut owned = Vec::new();
        while let Some(entry) = entries.next_entry().await? {
            if entry.file_name().to_string_lossy().starts_with(&prefix)
                && entry
                    .path()
                    .extension()
                    .is_some_and(|extension| extension == "sqlite")
            {
                owned.push(entry.path());
            }
        }
        assert_eq!(
            owned.len(),
            1,
            "the failed owner retains exactly its own preparation"
        );
        let db = connect_read_only(&owned[0]).await?;
        let completed = db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS count FROM seaql_migrations",
                vec![],
            ))
            .await?
            .context("official target ledger")?;
        assert_eq!(
            completed.try_get::<i64>("", "count")?,
            0,
            "failed official step has no completion row"
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='history_meta'",
                vec![]
            ))
            .await?
            .is_none(),
            "the target transaction must roll back its data and structure together"
        );
        db.close().await?;
        Ok(())
    }
}

#[cfg(test)]
mod storage_fault_tests {
    use super::test_support::{
        assert_current, assert_pending, import_origin, import_source, source_evidence,
    };
    use super::*;
    use crate::studio::thread_projection::order;

    /// Malformed durable input must remain a persistent-data failure, not a retryable SQLite
    /// query error or an absent source proof. The external diagnostic must not expose the row.
    #[tokio::test]
    async fn bot_input_identity_corruption_is_nonretryable_without_exposing_payload() -> Result<()>
    {
        use crate::bots::FeishuError;
        use pl_core::thread::input::{InputIdentity, InputState};
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(
            &directory.path().join("history-current.sqlite"),
            "bot-source",
        )
        .await?;
        store.initialize(HistoryInitialization::New).await?;
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: &[],
                    rolled_back_turns: &Default::default(),
                    identities: &[InputIdentityWrite {
                        entry: crate::studio::storage::state::InputIdentityEntry::new(
                            InputIdentity {
                                purpose: Default::default(),
                                continuation: None,
                                id: "steering".into(),
                                ordinal: 2,
                                revision: 1,
                                digest: "input-digest".into(),
                                delivery: Default::default(),
                                state: InputState::Consumed {
                                    turn_id: "bot-turn".into(),
                                    attempt_id: "attempt".into(),
                                },
                            },
                            1,
                        ),
                        request_digest: None,
                        presentation: pl_protocol::MessagePresentation::Visible,
                    }],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let connection = store.writer().await?;
        let db = &connection.db;
        assert_eq!(
            store
                .input_identity("steering")
                .await?
                .map(|receipt| receipt.entry.id),
            Some("steering".into())
        );
        let private_marker = "private-corrupt-row-marker";
        db.execute_raw(statement(
            "UPDATE history_input_identities SET payload=? WHERE item_id='steering'",
            vec![
                serde_json::json!({"private": private_marker})
                    .to_string()
                    .into(),
            ],
        ))
        .await?;
        let cause = store
            .input_identity("steering")
            .await
            .err()
            .context("corrupt input identity must fail closed")?;
        let error = FeishuError::history_read("read canonical bot input identity", cause);
        assert_eq!(error.diagnostic().code, "unavailable");
        assert!(
            !error.retryable(),
            "persistent JSON corruption must require local recovery"
        );
        assert!(
            std::error::Error::source(&error).is_some(),
            "the original cause must remain available internally"
        );
        let external = serde_json::to_string(&error.diagnostic())?;
        assert!(!external.contains(private_marker));
        assert!(external.contains("local recovery required"));
        Ok(())
    }

    /// A durable terminal Turn is readable by its own Turn identity, and a later revision of the
    /// same Turn identity is rejected instead of silently rewriting committed history.
    #[tokio::test]
    async fn terminal_turn_history_is_readable_by_turn_and_rejects_revisions() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "child").await?;
        let terminal = |id: &str, ordinal: u64| {
            ThreadItem::new(
                format!("turn:{id}"),
                "child".into(),
                id.into(),
                ordinal,
                1,
                1,
                1,
                ThreadItemState::Turn(pl_protocol::ThreadTurnItem::new(
                    pl_protocol::TurnState::Completed(pl_protocol::CompletedTurnState::new(
                        Some(1),
                        1,
                        pl_protocol::TurnCompletion::Normal,
                    )),
                )),
            )
        };
        store.commit(30, &[terminal("first", 1)], &[]).await?;
        store
            .commit(80, &[terminal("second", 2), terminal("third", 3)], &[])
            .await?;

        let first = store.items_for_turn("first").await?;
        assert_eq!(first.len(), 1);
        assert_eq!(first[0].id, "turn:first");
        let committed = store.items_for_turn("second").await?;
        assert_eq!(committed.len(), 1);
        assert_eq!(committed[0].revision, 1);
        assert!(store.items_for_turn("missing").await?.is_empty());
        let mut revised = terminal("second", 2);
        revised.revision = 2;
        assert!(store.commit(90, &[revised], &[]).await.is_err());
        Ok(())
    }

    /// Enabling explicit publications must not grant publication intent to old path-only files.
    /// The new typed item survives a cold read without rewriting the pre-publication payload. The
    /// current format arrives through the real target import, without promoting old file rows.
    #[tokio::test]
    async fn publication_upgrade_preserves_old_files_and_new_explicit_items() -> Result<()> {
        use pl_core::thread::{ThreadCheckpoint, ThreadEffectBatch, ThreadSnapshot};
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "publication-migration";
        let store = HistoryStore::open(&path, thread_id).await?;
        store.initialize(HistoryInitialization::New).await?;
        let old_file = ThreadItem::new(
            "old-file".into(),
            thread_id.into(),
            "turn".into(),
            1,
            1,
            1,
            1,
            ThreadItemState::File(pl_protocol::ThreadFileItem::new(
                "report.md".into(),
                Some("text/markdown".into()),
                1,
            )),
        );
        // One real commit carries the historical file together with the checkpoint the recovery
        // boundary needs; no SQL fabricates either of them.
        let checkpoint = ThreadCheckpoint::capture(
            thread_id.into(),
            1,
            ThreadSnapshot {
                commit_sequence: 1,
                ..Default::default()
            },
        );
        let effect = ThreadEffectBatch {
            thread_id: thread_id.into(),
            sequence: 1,
            ..Default::default()
        };
        store
            .commit_checkpoint_effect(
                &checkpoint,
                &effect,
                EffectCommit {
                    items: std::slice::from_ref(&old_file),
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
        assert_eq!(
            stored_format(&store).await?,
            HISTORY_SCHEMA_VERSION,
            "a created file is completed to the current format"
        );
        assert_eq!(
            store
                .reader()
                .await?
                .context("created history")?
                .schema_version,
            HISTORY_SCHEMA_VERSION,
            "the cached format is the on-disk fact, never a hard-coded one"
        );
        {
            let db = &store.writer().await?.db;
            db.execute_unprepared(
                "DROP TABLE seaql_migrations; UPDATE history_meta SET schema_version=8",
            )
            .await?;
            schema::advance_released_eight(db, thread_id, None).await?;
            let original = checkpoint::read(db, thread_id)
                .await?
                .context("released checkpoint")?;
            schema::advance_released_eight(db, thread_id, Some((original.clone(), original)))
                .await?;
        }
        drop(store);
        let target = directory.path().join("history-current.sqlite");
        let upgraded = HistoryStore::open(&target, thread_id).await?;
        upgraded
            .initialize(HistoryInitialization::ImportV2 {
                source_database: path.clone(),
                legacy_state: super::super::state::StateStore::new(
                    directory.path().to_owned(),
                    thread_id,
                ),
                migrate_execution_identity: std::sync::Arc::new(|_| Ok(())),
            })
            .await?;
        upgraded.prepare_activation().await?;
        assert_eq!(
            stored_format(&upgraded).await?,
            HISTORY_SCHEMA_VERSION,
            "activation is idempotent once the file is current"
        );
        assert_eq!(
            upgraded.items_for_turn("turn").await?,
            vec![old_file.clone()]
        );
        assert_eq!(upgraded.watermark().await?, 1);
        let artifact = ThreadItem::new(
            "artifact:publication".into(),
            thread_id.into(),
            "turn".into(),
            2,
            1,
            2,
            2,
            ThreadItemState::PublicArtifact(pl_protocol::ThreadPublicArtifactItem {
                publication_id: "publication".into(),
                tool_call_id: "publish-call".into(),
                display_name: "空文件".into(),
                resource: pl_protocol::ThreadArtifactResource {
                    id: "archived-empty-original".into(),
                    content_digest:
                        "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                            .into(),
                    byte_len: 0,
                    media_type: "application/octet-stream".into(),
                },
                published_at: 2,
            }),
        );
        let mut state = upgraded
            .checkpoint()
            .await?
            .context("imported checkpoint")?
            .state;
        state.commit_sequence = 2;
        upgraded
            .commit_checkpoint_effect(
                &ThreadCheckpoint::capture(thread_id.into(), 2, state),
                &ThreadEffectBatch {
                    thread_id: thread_id.into(),
                    sequence: 2,
                    ..Default::default()
                },
                EffectCommit {
                    items: std::slice::from_ref(&artifact),
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
        drop(upgraded);

        let cold = HistoryStore::open(&target, thread_id).await?;
        assert_eq!(cold.items_for_turn("turn").await?, vec![old_file, artifact]);
        assert_eq!(cold.watermark().await?, 2);
        assert_eq!(
            cold.reader()
                .await?
                .context("missing upgraded history")?
                .schema_version,
            HISTORY_SCHEMA_VERSION,
            "a reopened handle reads the committed format, not a hard-coded one"
        );
        assert_eq!(stored_format(&cold).await?, HISTORY_SCHEMA_VERSION);
        Ok(())
    }

    /// The format the file itself declares, read through the owning writer connection.
    async fn stored_format(store: &HistoryStore) -> Result<i64> {
        let row = store
            .writer()
            .await?
            .db
            .query_one_raw(statement(
                "SELECT schema_version FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("stored history format")?;
        Ok(row.try_get("", "schema_version")?)
    }

    #[tokio::test]
    async fn legacy_plan_continuation_migrates_only_proven_hidden_identity() -> Result<()> {
        use pl_core::{
            context::OpaquePayload,
            thread::input::{InputRecord, InputState, ThreadInput},
        };
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "legacy-plan").await?;
        // 一条真实的计划确认：提问、决定与发起它的 plan_submit 条目都属于同一次工具调用。
        let call_id = "call-plan";
        let plan_item = plan_tool_item(call_id, "legacy-plan", 1);
        let id = format!(
            "interaction:{}:continuation",
            pl_core::tool::opaque::tool_interaction_id(call_id)
        );
        let mut interaction =
            plan_decision_record(call_id, &plan_fixture("Approved plan")?, &["Approve"])?;
        interaction.created_at = 1;
        interaction.updated_at = 2;
        interaction.continuation_id = Some(id.clone());
        let input = InputRecord {
            continuation: None,
            accepted_sequence: 1,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: id.clone(),
                payload: OpaquePayload::new(
                    "pl.studio.interaction-continuation",
                    1,
                    serde_json::json!({
                        "interactionId": pl_core::tool::opaque::tool_interaction_id(call_id),
                        "presentation": "hidden"
                    })
                    .to_string(),
                )?,
                context: vec![],
            },
            ordinal: 1,
            revision: 2,
            state: InputState::Consumed {
                turn_id: "next-turn".into(),
                attempt_id: "attempt".into(),
            },
        };
        let mut unproven = input.clone();
        unproven.input.id = "unproven-input".into();
        unproven.ordinal = 2;
        let identities = [
            InputIdentityWrite {
                entry: crate::studio::storage::state::InputIdentityEntry::new(
                    pl_core::thread::input::input_identity(&input),
                    1,
                ),
                request_digest: None,
                presentation: pl_protocol::MessagePresentation::Hidden,
            },
            InputIdentityWrite {
                entry: crate::studio::storage::state::InputIdentityEntry::new(
                    pl_core::thread::input::input_identity(&unproven),
                    1,
                ),
                request_digest: None,
                presentation: pl_protocol::MessagePresentation::Visible,
            },
        ];
        let receipts = [FactReceiptWrite {
            item_id: order::receipt_id("interaction", &interaction.request.id),
            revision: interaction.revision,
            kind: "interaction",
            payload: serde_json::to_string(&interaction)?,
        }];
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&plan_item),
                    rolled_back_turns: &Default::default(),
                    identities: &identities,
                    messages: &[],
                    receipts: &receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "ALTER TABLE history_input_identities DROP COLUMN presentation; \
             DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=2",
        )
        .await?;
        db.close().await?;
        store.writer().await?.db.clone().close().await?;
        drop(store);

        let target = directory.path().join("history-current.sqlite");
        let cold = HistoryStore::open(&target, "legacy-plan").await?;
        assert!(
            cold.watermark().await.is_err(),
            "a missing current store is not empty history"
        );
        assert!(!target.exists());
        let source = source_evidence(&path).await?;
        let migrated = import_source(&path, &target, "legacy-plan").await?;
        assert_eq!(migrated.watermark().await?, 1);
        let old = connect_read_only(&path).await?;
        let version = old
            .query_one_raw(statement(
                "SELECT schema_version FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("missing legacy metadata")?
            .try_get::<i64>("", "schema_version")?;
        assert_eq!(version, 2);
        old.close().await?;
        assert_eq!(
            migrated
                .hidden_input_identities([id.clone(), "unproven-input".into()])
                .await?,
            [id.clone()].into()
        );
        assert_eq!(
            migrated
                .reader()
                .await?
                .context("missing migrated history")?
                .schema_version,
            HISTORY_SCHEMA_VERSION
        );
        assert!(migrated.existing_items([id]).await?.is_empty());
        assert_eq!(migrated.watermark().await?, 1);
        assert_eq!(source_evidence(&path).await?, source);
        Ok(())
    }

    #[tokio::test]
    async fn activation_migrates_only_proven_unconsumed_input_bindings() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "migration").await?;
        // The legacy fixture's watermark10 follows a real contiguous producer prefix.
        for sequence in 1..10 {
            store.commit(sequence, &[], &[]).await?;
        }
        let mut items = Vec::new();
        for (ordinal, id, input_id) in [
            (1, "pending", "pending"),
            (3, "consumed", "consumed"),
            (5, "other", "unknown"),
        ] {
            let turn_id = format!("turn-{id}");
            let mut item = ThreadItem::completed_user_message(
                id.into(),
                "migration".into(),
                turn_id.clone(),
                "preserved".into(),
                vec![],
                7,
            );
            item.ordinal = ordinal;
            item.revision = 3;
            items.push(item);
            items.push(ThreadItem::new(
                crate::studio::thread_projection::order::turn_id(&turn_id),
                "migration".into(),
                turn_id,
                ordinal + 1,
                1,
                7,
                8,
                ThreadItemState::Turn(
                    pl_protocol::ThreadTurnItem::new(pl_protocol::TurnState::Completed(
                        pl_protocol::CompletedTurnState::new(
                            Some(1),
                            1,
                            pl_protocol::TurnCompletion::Normal,
                        ),
                    ))
                    .with_input_id(Some(input_id.into())),
                ),
            ));
        }
        store
            .commit_effect(
                10,
                EffectCommit {
                    items: &items,
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
        write_input_identity(
            &store.writer().await?.db,
            10,
            &InputIdentityWrite {
                entry: crate::studio::storage::state::InputIdentityEntry::new(
                    pl_core::thread::input::InputIdentity {
                        purpose: Default::default(),
                        continuation: None,
                        id: "consumed".into(),
                        ordinal: 3,
                        revision: 2,
                        digest: "retained-digest".into(),
                        delivery: Default::default(),
                        state: pl_core::thread::input::InputState::Consumed {
                            turn_id: "turn-consumed".into(),
                            attempt_id: "attempt".into(),
                        },
                    },
                    1,
                ),
                request_digest: None,
                presentation: pl_protocol::MessagePresentation::Visible,
            },
        )
        .await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=3",
            )
            .await?;
        drop(store);
        let target = directory.path().join("history-current.sqlite");
        let cold = HistoryStore::open(&target, "migration").await?;
        assert!(cold.existing_items(["pending".into()]).await.is_err());
        assert!(
            !target.exists(),
            "ordinary cold reads cannot initiate import"
        );
        let source = source_evidence(&path).await?;
        let original = connect_read_only(&path).await?;
        let row = original
            .query_one_raw(statement(
                "SELECT payload FROM history_items WHERE item_id='pending'",
                vec![],
            ))
            .await?
            .context("source pending item")?;
        let pending: ThreadItem = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        assert_eq!(pending.turn_id, "turn-pending");
        original.close().await?;
        let migrated = import_source(&path, &target, "migration").await?;
        migrated.prepare_activation().await?;
        assert_eq!(source_evidence(&path).await?, source);
        let saved = migrated
            .existing_items(items.iter().map(|item| item.id.clone()))
            .await?;
        let mut expected = items[0].clone();
        expected.turn_id.clear();
        expected.revision += 1;
        assert_eq!(saved["pending"], expected);
        for item in &items[1..] {
            assert_eq!(&saved[&item.id], item);
        }
        assert_eq!(migrated.watermark().await?, 10);
        let first = migrated
            .reader()
            .await?
            .context("migrated connection")?
            .db
            .query_one_raw(statement(
                "SELECT first_ordinal FROM history_turns WHERE turn_id=?",
                vec!["turn-pending".into()],
            ))
            .await?
            .context("migrated Turn")?
            .try_get::<i64>("", "first_ordinal")?;
        assert_eq!(first, 2);
        assert!(migrated.input_identity("consumed").await?.is_some());
        migrated.prepare_activation().await?;
        assert_eq!(
            migrated.existing_items(["pending".into()]).await?["pending"],
            expected
        );
        Ok(())
    }

    #[tokio::test]
    async fn session_orders_do_not_write_sqlite_reservations() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history-current.sqlite");
        let store = HistoryStore::open(&path, "local-orders").await?;
        let unready = pl_core::chat::Session::new(store.clone());
        assert!(
            unready.reserve_order("input-1").await.is_err(),
            "an uninitialized history cannot seed a normal Session order"
        );
        assert!(!tokio::fs::try_exists(&path).await?);
        drop(unready);
        store.initialize(HistoryInitialization::New).await?;
        assert_current(&path, "local-orders").await?;
        assert_eq!(store.watermark().await?, 0);
        let empty = source_evidence(&path).await?;
        let session = pl_core::chat::Session::new(store.clone());
        assert_eq!(session.reserve_order("input-1").await?, 1);
        assert_eq!(session.reserve_order("input-1").await?, 1);
        assert_eq!(session.reserve_order("input-2").await?, 2);
        assert_eq!(
            source_evidence(&path).await?,
            empty,
            "order reservations must not write SQLite rows, schema, main or WAL bytes"
        );
        assert!(store.checkpoint().await?.is_none());
        assert_eq!(store.watermark().await?, 0);

        let mut item = ThreadItem::completed_user_message(
            "input-1".to_owned(),
            "local-orders".to_owned(),
            "turn-1".to_owned(),
            "hello".to_owned(),
            vec![],
            1,
        );
        item.ordinal = 1;
        item.revision = 1;
        store.commit(1, &[item], &[]).await?;
        let row = store
            .reader()
            .await?
            .context("missing committed history")?
            .db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS count FROM sqlite_master
                 WHERE type='table' AND name='history_ordinals'",
                vec![],
            ))
            .await?
            .context("missing schema query")?;
        assert_eq!(row.try_get::<i64>("", "count")?, 0);
        let mut missing_order = ThreadItem::completed_user_message(
            "missing-order".to_owned(),
            "local-orders".to_owned(),
            "turn-1".to_owned(),
            "not allocated".to_owned(),
            vec![],
            2,
        );
        missing_order.revision = 2;
        assert!(store.commit(2, &[missing_order], &[]).await.is_err());
        assert_eq!(store.watermark().await?, 1);
        let mut changed_order = store.item("input-1").await?.context("committed input")?;
        changed_order.ordinal = 2;
        changed_order.revision = 2;
        assert!(store.commit(2, &[changed_order], &[]).await.is_err());
        assert_eq!(store.watermark().await?, 1);
        assert_eq!(session.reserve_order("input-3").await?, 3);

        drop(session);
        let reopened =
            pl_core::chat::Session::new(HistoryStore::open(&path, "local-orders").await?);
        // Uncommitted order 2 was never durable and is not reconstructed after restart.
        assert_eq!(reopened.reserve_order("input-4").await?, 2);
        Ok(())
    }

    #[tokio::test]
    async fn a_bounded_page_continues_by_its_real_boundary_and_a_session_starts_from_the_latest_page()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store =
            HistoryStore::open(&directory.path().join("history.sqlite"), "paged-thread").await?;
        let items = (0..120)
            .map(|index| {
                let mut item = ThreadItem::completed_user_message(
                    format!("message-{index}"),
                    "paged-thread".to_owned(),
                    "turn-1".to_owned(),
                    "hello".to_owned(),
                    vec![],
                    1,
                );
                item.ordinal = index + 1;
                item.revision = 1;
                item
            })
            .collect::<Vec<_>>();
        store.commit(1, &items, &[]).await?;
        let page = store.chat_page(None, 100).await?;
        assert_eq!(page.items.len(), 100);
        assert_eq!(page.items.first().unwrap().item_id, "message-20");
        assert_eq!(page.items.last().unwrap().item_id, "message-119");
        assert!(page.has_older);
        let before = store
            .chat_page(Some(&pl_core::chat::ChatCursor::new(21, "message-20")), 100)
            .await?;
        assert_eq!(before.items.len(), 20);
        assert!(!before.has_older);

        // A fresh session starts from the latest small page and continues by the page boundary it
        // proves, instead of pretending a short page reached the beginning of history.
        let session = pl_core::chat::Session::new(store.clone());
        let mut initial = session.subscribe_tail().await?;
        let baseline = initial.initial()?;
        assert_eq!(baseline.items.len(), 32);
        assert_eq!(baseline.items.first().unwrap().item_id, "message-88");
        assert_eq!(baseline.items.last().unwrap().item_id, "message-119");
        assert!(
            baseline.has_older,
            "the first frame carries its own boundary"
        );
        assert_eq!(
            baseline.before,
            Some(pl_core::chat::ChatCursor::new(89, "message-88"))
        );
        let older = session
            .page(
                pl_core::chat::ChatPageRequest::before(pl_core::chat::ChatCursor::new(
                    89,
                    "message-88",
                ))
                .with_limit(32),
            )
            .await?;
        assert_eq!(older.items.len(), 32);
        assert_eq!(older.items.first().unwrap().item_id, "message-56");
        assert_eq!(older.items.last().unwrap().item_id, "message-87");
        assert!(older.has_older);

        // Only persisted items seed the next Session; a discarded live allocation has no
        // durable reservation to inflate the next ordinal after a restart.
        let reopened =
            HistoryStore::open(&directory.path().join("history.sqlite"), "paged-thread").await?;
        let resumed = pl_core::chat::Session::new(reopened);
        assert_eq!(resumed.reserve_order("message-120").await?, 121);
        let mut committed = ThreadItem::completed_user_message(
            "message-120".to_owned(),
            "paged-thread".to_owned(),
            "turn-1".to_owned(),
            "resumed".to_owned(),
            vec![],
            2,
        );
        committed.ordinal = 121;
        committed.revision = 2;
        store.commit(2, &[committed], &[]).await?;
        let final_session = pl_core::chat::Session::new(
            HistoryStore::open(&directory.path().join("history.sqlite"), "paged-thread").await?,
        );
        assert_eq!(final_session.reserve_order("message-121").await?, 122);
        Ok(())
    }

    async fn save_receipt(store: &HistoryStore, sequence: u64, id: &str) -> Result<()> {
        let receipts = [FactReceiptWrite {
            item_id: id.to_owned(),
            revision: sequence,
            kind: "interaction",
            payload: "{}".to_owned(),
        }];
        store
            .commit_effect(
                sequence,
                EffectCommit {
                    items: &[],
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await
    }

    #[tokio::test]
    async fn sqlite_rejection_retains_watermark_and_same_batch_can_retry() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store =
            HistoryStore::open(&directory.path().join("history.sqlite"), "thread-1").await?;
        save_receipt(&store, 1, "first").await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "CREATE TRIGGER reject_receipt BEFORE INSERT ON history_fact_receipts \
             BEGIN SELECT RAISE(ABORT, 'controlled history rejection'); END",
            )
            .await?;
        assert!(save_receipt(&store, 2, "second").await.is_err());
        assert_eq!(store.watermark().await?, 1);
        assert!(store.latest_fact_receipt("second").await?.is_none());
        store
            .writer()
            .await?
            .db
            .execute_unprepared("DROP TRIGGER reject_receipt")
            .await?;
        save_receipt(&store, 2, "second").await?;
        save_receipt(&store, 2, "second").await?;
        assert_eq!(store.watermark().await?, 2);
        assert_eq!(
            store
                .latest_fact_receipt("second")
                .await?
                .context("missing retried receipt")?
                .payload,
            "{}"
        );
        Ok(())
    }

    #[tokio::test]
    async fn task_identity_and_delivery_share_history_authority() -> Result<()> {
        use pl_core::thread::task::{TaskRecord, TaskStatus};
        use pl_core::thread::{ToolDelivery, ToolDeliveryTarget, ToolOutcome};

        let directory = tempfile::tempdir()?;
        let store =
            HistoryStore::open(&directory.path().join("history.sqlite"), "thread-2").await?;
        let tasks = [TaskRecord {
            id: "task:call-1".to_owned(),
            call_id: "call-1".to_owned(),
            turn_id: "turn-1".to_owned(),
            tool_id: "tool-1".to_owned(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: None,
        }];
        let empty = std::collections::BTreeSet::new();
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: &[],
                    rolled_back_turns: &empty,
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &tasks,
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let delivery = ToolDelivery {
            target: ToolDeliveryTarget::CallResult,
            call_id: "call-1".to_owned(),
            tool_id: "tool-1".to_owned(),
            output: pl_core::tool::ToolOutput::new(
                pl_core::context::OpaquePayload::text("done"),
                vec![],
            ),
            delivered_context: vec![],
            outcome: ToolOutcome::Succeeded,
        };
        store
            .commit_effect(
                2,
                EffectCommit {
                    items: &[],
                    rolled_back_turns: &empty,
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[delivery],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let result = store
            .tool_task("task:call-1")
            .await?
            .context("missing committed task")?;
        assert_eq!(result.task.status, TaskStatus::Succeeded);
        assert_eq!(
            result.delivery.context("missing delivery")?.call_id,
            "call-1"
        );
        Ok(())
    }

    #[tokio::test]
    async fn checkpoint_context_and_watermark_roll_back_and_retry_together() -> Result<()> {
        use pl_core::{
            context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
            thread::{ThreadCheckpoint, ThreadEffectBatch, ThreadSnapshot, journal::ContextChange},
        };
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(&directory.path().join("history.sqlite"), "atomic").await?;
        store.initialize(HistoryInitialization::New).await?;
        let record = |id: &str| -> Result<ContextRecord> {
            Ok(ContextRecord {
                id: id.into(),
                turn_id: None,
                source: if id == "second" {
                    ContextSource::Assistant
                } else {
                    ContextSource::User
                },
                content: if id == "second" {
                    vec![ContextContent::Opaque { payload: pl_core::context::OpaquePayload::new("pl.model.assistant", 2, serde_json::json!({
                    "receipt": {"binding":{"providerInstanceId":"fixture","requestedModel":"fixture","adapter":"openAiCompatible","protocol":"responses","isolation":"test","purpose":"turn","contextWindow":null},
                    "response":{"responseId":"stored-replay","content":null,"replay":{"kind":"responses","output":[{"id":"stored-progress","type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"retained progress","annotations":[]}]}]},"toolCalls":[],"responsesContextItems":[],"accounting":{},"model":"fixture"}},"bindings":[]
                }).to_string())? }]
                } else {
                    vec![ContextContent::Text {
                        text: std::sync::Arc::from(id),
                    }]
                },
                tool_calls: vec![],
            })
        };
        let empty = std::collections::BTreeSet::new();
        let commit = || EffectCommit {
            items: &[],
            rolled_back_turns: &empty,
            identities: &[],
            messages: &[],
            receipts: &[],
            tasks: &[],
            deliveries: &[],
            delivery_repairs: &[],
            attempt: None,
        };
        let mut state = ThreadSnapshot {
            commit_sequence: 1,
            context: ContextSnapshot {
                revision: 1,
                records: vec![record("first")?].into(),
            },
            ..Default::default()
        };
        state.usage_summary.inference_count = 1;
        state.usage_summary.applied_sequence = 1;
        let first = ThreadCheckpoint::capture("atomic".into(), 1, state.clone());
        let effect = ThreadEffectBatch {
            thread_id: "atomic".into(),
            sequence: 1,
            context: Some(ContextChange::Append {
                revision: 1,
                records: state.context.records.clone(),
            }),
            ..Default::default()
        };
        store
            .commit_checkpoint_effect(&first, &effect, commit())
            .await?;
        // Reject any rewrite of the existing prefix: a normal append must only insert the suffix.
        store.writer().await?.db.execute_unprepared(
            "CREATE TRIGGER reject_context_update BEFORE UPDATE ON current_context BEGIN SELECT RAISE(FAIL, 'prefix rewritten'); END;
             CREATE TRIGGER reject_context_delete BEFORE DELETE ON current_context BEGIN SELECT RAISE(FAIL, 'prefix deleted'); END;
             CREATE TRIGGER fail_checkpoint BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(FAIL, 'injected checkpoint failure'); END;"
        ).await?;
        state.commit_sequence = 2;
        state.usage_summary.inference_count = 2;
        state.usage_summary.applied_sequence = 2;
        state.context.revision = 2;
        state.context.records = vec![record("first")?, record("second")?].into();
        let second = ThreadCheckpoint::capture("atomic".into(), 2, state);
        let effect = ThreadEffectBatch {
            thread_id: "atomic".into(),
            sequence: 2,
            context: Some(ContextChange::Append {
                revision: 2,
                records: vec![record("second")?].into(),
            }),
            ..Default::default()
        };
        assert!(
            store
                .commit_checkpoint_effect(&second, &effect, commit())
                .await
                .is_err()
        );
        assert_eq!(store.watermark().await?, 1);
        assert_eq!(
            store
                .checkpoint()
                .await?
                .unwrap()
                .state
                .usage_summary
                .inference_count,
            1
        );
        assert_eq!(
            store
                .checkpoint()
                .await?
                .context("checkpoint")?
                .state
                .context,
            first.state.context
        );
        store
            .writer()
            .await?
            .db
            .execute_unprepared("DROP TRIGGER fail_checkpoint")
            .await?;
        store
            .commit_checkpoint_effect(&second, &effect, commit())
            .await?;
        // A lost acknowledgement retries the same transaction without duplicating the append.
        store
            .commit_checkpoint_effect(&second, &effect, commit())
            .await?;
        assert_eq!(store.watermark().await?, 2);
        assert_eq!(
            store
                .checkpoint()
                .await?
                .unwrap()
                .state
                .usage_summary
                .inference_count,
            2
        );
        assert_eq!(
            store
                .checkpoint()
                .await?
                .context("checkpoint")?
                .state
                .context,
            second.state.context
        );
        let before: i64 = store
            .writer()
            .await?
            .db
            .query_one_raw(statement("SELECT total_changes() AS changes", vec![]))
            .await?
            .unwrap()
            .try_get("", "changes")?;
        let mut state = second.state.clone();
        let mut serialized_new_bytes = 0_usize;
        for sequence in 3..=139 {
            let added = record(&format!("context-{sequence}"))?;
            serialized_new_bytes += serde_json::to_vec(&added)?.len();
            let mut records = state.context.records.to_vec();
            records.push(added.clone());
            state.context.records = records.into();
            state.context.revision = sequence;
            state.commit_sequence = sequence;
            let checkpoint = ThreadCheckpoint::capture("atomic".into(), sequence, state.clone());
            let effect = ThreadEffectBatch {
                thread_id: "atomic".into(),
                sequence,
                context: Some(ContextChange::Append {
                    revision: sequence,
                    records: vec![added].into(),
                }),
                ..Default::default()
            };
            store
                .commit_checkpoint_effect(&checkpoint, &effect, commit())
                .await?;
        }
        let after: i64 = store
            .writer()
            .await?
            .db
            .query_one_raw(statement("SELECT total_changes() AS changes", vec![]))
            .await?
            .unwrap()
            .try_get("", "changes")?;
        assert_eq!(
            after - before,
            137 * 3,
            "each append only changes one context row, checkpoint, and watermark"
        );
        // The prefix guards were active for every tested append. Remove these test-owned mutation
        // sentinels before exercising ordinary cold readiness; unknown triggers stay forbidden.
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "DROP TRIGGER reject_context_update; DROP TRIGGER reject_context_delete",
            )
            .await?;
        let database_bytes = tokio::fs::metadata(directory.path().join("history.sqlite"))
            .await?
            .len();
        let wal_bytes = tokio::fs::metadata(directory.path().join("history.sqlite-wal"))
            .await?
            .len();
        eprintln!(
            "storage long-task: calls=137 records=139 new_context_serialized_bytes={serialized_new_bytes} sqlite_row_mutations={} database_bytes={database_bytes} wal_bytes={wal_bytes}",
            after - before
        );

        // A timeline owns its HistoryStore independently of an execution owner. Preserve that
        // actual shared writer holder, then require the canonical read to initialize a different,
        // truly read-only connection instead of returning the writer's fast path.
        let _timeline = pl_core::chat::Session::new(store.clone());
        let share = store.shared();
        drop(store);
        let retained = HistoryStore::from_share(&share).context("timeline retained history")?;
        assert!(retained.state.writer.get().is_some());
        assert!(retained.state.reader.get().is_none());
        let (checkpoint, latest) = retained
            .read_only_checkpoint_with_latest_turn()
            .await?
            .context("canonical state through retained history")?;
        assert_eq!(checkpoint.state.commit_sequence, 139);
        assert_eq!(checkpoint.state.context, state.context);
        assert!(latest.is_none());
        let reader = retained
            .state
            .reader
            .get()
            .context("strict read must use the read-only connection")?;
        let writer = retained.state.writer.get().context("retained writer")?;
        assert!(!std::ptr::eq(reader, writer));
        let write = "UPDATE history_meta SET applied_write_seq=applied_write_seq WHERE id=1";
        // The exact same statement is valid on the still-live writer, but SQLite must refuse it
        // on the connection the canonical read just used; no query-name convention is evidence.
        writer.db.execute_unprepared(write).await?;
        assert!(reader.db.execute_unprepared(write).await.is_err());
        assert_eq!(retained.watermark().await?, 139);
        Ok(())
    }

    #[tokio::test]
    async fn context_source_migration_is_atomic_and_preserves_business_state_and_history()
    -> Result<()> {
        use pl_core::{
            context::{
                AgentMessageKind, ContextContent, ContextRecord, ContextSnapshot, ContextSource,
                OpaquePayload, content_hash,
            },
            thread::{RuntimeFact, ThreadCheckpoint, ThreadSnapshot, extensions::ExtensionRecord},
        };
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "context-migration").await?;
        store.initialize(HistoryInitialization::New).await?;
        let mut item = ThreadItem::completed_user_message(
            "original-user".into(),
            "context-migration".into(),
            "original-turn".into(),
            "保留的原始历史".into(),
            vec![],
            7,
        );
        item.ordinal = 1;
        item.revision = 1;
        let text = ContextContent::Text {
            text: std::sync::Arc::from("approved version one"),
        };
        let state = ThreadSnapshot {
            commit_sequence: 1,
            context: ContextSnapshot {
                revision: 1,
                records: vec![
                    ContextRecord {
                        id: "runtime:plan:1".into(),
                        turn_id: None,
                        source: ContextSource::Runtime {
                            source_id: "plan".into(),
                        },
                        content: vec![text.clone()],
                        tool_calls: vec![],
                    },
                    ContextRecord {
                        id: "inbox:1:task".into(),
                        turn_id: None,
                        source: ContextSource::Runtime {
                            source_id: "parent".into(),
                        },
                        content: vec![ContextContent::Text {
                            text: "delegated task".into(),
                        }],
                        tool_calls: vec![],
                    },
                    ContextRecord {
                        id: "workspace:context-migration".into(),
                        turn_id: None,
                        source: ContextSource::Runtime {
                            source_id: "studio.workspace".into(),
                        },
                        content: vec![ContextContent::Text {
                            text: "assigned workspace".into(),
                        }],
                        tool_calls: vec![],
                    },
                    ContextRecord {
                        id: "workflow:context-migration:initial".into(),
                        turn_id: None,
                        source: ContextSource::Runtime {
                            source_id: "studio.workflow".into(),
                        },
                        content: vec![ContextContent::Text {
                            text: "current workflow".into(),
                        }],
                        tool_calls: vec![],
                    },
                    ContextRecord {
                        id: "workspace:another-session".into(),
                        turn_id: None,
                        source: ContextSource::Runtime {
                            source_id: "studio.workspace".into(),
                        },
                        content: vec![ContextContent::Text {
                            text: "preserved unclassified material".into(),
                        }],
                        tool_calls: vec![],
                    },
                ]
                .into(),
            },
            runtime_facts: vec![RuntimeFact {
                source_id: "plan".into(),
                content: vec![text],
            }]
            .into(),
            extensions: std::collections::BTreeMap::from([(
                "plan.authority".into(),
                ExtensionRecord {
                    revision: 1,
                    payload: OpaquePayload::text("approved"),
                },
            )]),
            last_attempt_usage: Some(pl_core::model::ModelUsage {
                input_tokens: Some(83),
                ..Default::default()
            }),
            ..Default::default()
        };
        store
            .commit_checkpoint_effect(
                &ThreadCheckpoint::capture("context-migration".into(), 1, state.clone()),
                &pl_core::thread::ThreadEffectBatch {
                    thread_id: "context-migration".into(),
                    sequence: 1,
                    ..Default::default()
                },
                EffectCommit {
                    items: std::slice::from_ref(&item),
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
        let db = &store.writer().await?.db;
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .context("checkpoint")?;
        let mut legacy: serde_json::Value =
            serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        legacy["schemaVersion"] = serde_json::json!(3);
        legacy["state"]
            .as_object_mut()
            .context("state")?
            .remove("lastAttemptUsageOrigin");
        let encoded = serde_json::to_string(&legacy)?;
        db.execute_raw(statement(
            "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
            vec![
                encoded.clone().into(),
                content_hash(encoded.as_bytes()).into(),
            ],
        ))
        .await?;
        db.execute_unprepared(
            "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=5",
        )
        .await?;
        let target = directory.path().join("history-current.sqlite");
        let failed = HistoryStore::open(&target, "context-migration").await?;
        let reject = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true));
        let rejected = reject.clone();
        assert!(
            failed
                .initialize(HistoryInitialization::ImportV2 {
                    source_database: path.clone(),
                    legacy_state: super::super::state::StateStore::new(
                        directory.path().to_owned(),
                        "context-migration"
                    ),
                    migrate_execution_identity: std::sync::Arc::new(move |_| {
                        ensure!(
                            !rejected.load(std::sync::atomic::Ordering::Acquire),
                            "injected context migration failure"
                        );
                        Ok(())
                    }),
                })
                .await
                .is_err()
        );
        assert!(!target.exists());
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .context("checkpoint")?;
        assert_eq!(row.try_get::<String>("", "payload")?, encoded);
        reject.store(false, std::sync::atomic::Ordering::Release);
        failed.retry_initialization().await?;
        let restored = HistoryStore::open(&target, "context-migration").await?;
        let checkpoint = restored
            .checkpoint()
            .await?
            .context("migrated checkpoint")?;
        // 迁移落点跟随核心当前的 checkpoint schema，而不是在测试里再抄一份版本号。
        assert_eq!(
            checkpoint.schema_version,
            pl_core::thread::ThreadCheckpoint::SCHEMA_VERSION
        );
        assert!(matches!(
            checkpoint.state.context.records[0].source,
            ContextSource::RuntimeFact { .. }
        ));
        assert!(matches!(
            checkpoint.state.context.records[1].source,
            ContextSource::AgentMessage {
                purpose: AgentMessageKind::Unclassified,
                ..
            }
        ));
        assert!(
            matches!(&checkpoint.state.context.records[2].source, ContextSource::RuntimeFact { source_id } if source_id == "studio.workspace")
        );
        assert!(
            matches!(&checkpoint.state.context.records[3].source, ContextSource::RuntimeFact { source_id } if source_id == "studio.workflow")
        );
        assert_eq!(
            checkpoint.state.context.records[4],
            state.context.records[4]
        );
        let mut preserved = checkpoint.state.extensions.clone();
        preserved.remove(crate::studio::delegation::EXTENSION);
        assert_eq!(preserved, state.extensions);
        assert_eq!(
            checkpoint.state.last_attempt_usage,
            state.last_attempt_usage
        );
        assert!(checkpoint.state.last_attempt_usage_origin.is_none());
        assert_eq!(
            restored.existing_items([item.id.clone()]).await?[&item.id],
            item
        );
        assert_eq!(restored.watermark().await?, 1);
        Ok(())
    }

    #[tokio::test]
    async fn legacy_auxiliary_costs_are_imported_once_without_summing_overlapping_totals()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let source_path = directory.path().join("history.sqlite");
        let source = connect(&source_path).await?;
        schema::initialize(&source, "costs").await?;
        let path = directory.path().join("history-current.sqlite");
        let history = HistoryStore::open(&path, "costs").await?;
        let mut state = pl_core::thread::ThreadSnapshot::default();
        state
            .usage_summary
            .estimated_costs
            .push(pl_core::thread::UsageCost {
                currency: "USD".into(),
                amount: 2.0,
            });
        for (id, pricing) in [
            ("historical-disabled", pl_protocol::PricingOutcome::Disabled),
            ("no-charge", pl_protocol::PricingOutcome::NoCharge),
        ] {
            let receipt = crate::studio::thread_projection::AuxiliaryBillingReceipt {
                succeeded: true,
                billing: pl_protocol::InferenceBillingRecord {
                    inference_id: id.into(),
                    purpose: Some("title".into()),
                    account_id: "frozen-account".into(),
                    account_display_name: None,
                    model_id: Some("frozen-model".into()),
                    model_observation: None,
                    effort: None,
                    context_window: Some(64_000),
                    accounting: pl_protocol::InferenceAccounting {
                        usage: pl_protocol::UsageReport {
                            input_tokens: Some(100),
                            output_tokens: Some(10),
                            cache_read_tokens: Some(40),
                            cache_write_tokens: Some(20),
                            reasoning_tokens: Some(5),
                            total_tokens: Some(110),
                        },
                        pricing,
                        price_snapshot: None,
                        request_started_at: Some(1),
                    },
                    prompt_generation: None,
                    prompt_cache_policy: None,
                    prefix_changed_reason: None,
                    orchestration: Default::default(),
                    timing: None,
                    recorded_at: 2,
                },
            };
            let compaction = crate::compaction::CompactionReceipt {
                inference_id: format!("compaction-{id}"),
                binding: pl_model::runtime::ModelCallBinding {
                    account_id: "frozen-account".into(),
                    model_id: "frozen-model".into(),
                    protocol: pl_model::protocol::ProtocolKind::OpenAiCompatible,
                    wire_api: pl_model::protocol::WireApi::Responses,
                    isolation: "frozen-namespace".into(),
                    purpose: "compaction".into(),
                    context_window: Some(64_000),
                    max_context_window: Some(64_000),
                    auto_compact_limit: None,
                },
                reasoning_effort: None,
                context_window: Some(64_000),
                turn_id: "frozen-turn".into(),
                accounting: receipt.billing.accounting.clone(),
                model_observation: None,
                implementation: Some("textSummary".into()),
                error: None,
            };
            state.extension_sequence += 1;
            let compaction_payload = if id == "historical-disabled" {
                pl_core::context::OpaquePayload::new(
                    "pl.studio.compaction",
                    2,
                    serde_json::to_string(&compaction)?,
                )?
            } else {
                let payload = compaction.into_payload()?;
                assert_eq!(payload.version(), 3);
                payload
            };
            state.extensions.insert(
                format!("compaction-{id}"),
                pl_core::thread::extensions::ExtensionRecord {
                    revision: state.extension_sequence,
                    payload: compaction_payload,
                },
            );
            let payload = if id == "historical-disabled" {
                // Real historical v2 can still express Disabled, never NoCharge.
                pl_core::context::OpaquePayload::new(
                    "pl.studio.auxiliary-billing",
                    2,
                    serde_json::to_string(&receipt)?,
                )?
            } else {
                let payload = receipt.into_payload()?;
                assert_eq!(payload.version(), 3);
                payload
            };
            state.extension_sequence += 1;
            state.extensions.insert(
                id.into(),
                pl_core::thread::extensions::ExtensionRecord {
                    revision: state.extension_sequence,
                    payload,
                },
            );
        }
        let frozen_billing = state.extensions.clone();
        let checkpoint = pl_core::thread::ThreadCheckpoint::capture("costs".into(), 0, state);
        let purposes = [("main", 2.0), ("title", 3.0), ("review", 4.0)]
            .into_iter()
            .map(
                |(purpose, amount)| super::super::calls::PurposeUsageProjection {
                    purpose: Some(purpose.into()),
                    estimated_costs: vec![pl_protocol::RuntimeCostAmount {
                        currency: "USD".into(),
                        amount,
                    }],
                },
            )
            .collect::<Vec<_>>();
        let legacy_toml = toml::to_string(&checkpoint)?;
        tokio::fs::write(directory.path().join("state.toml"), legacy_toml.as_bytes()).await?;
        let calls_path = directory.path().join("calls.sqlite");
        let calls = super::super::calls::CallsStore::prepare(&calls_path).await?;
        let costs_db = connect(&calls_path).await?;
        for purpose in &purposes {
            for cost in &purpose.estimated_costs {
                costs_db.execute_raw(statement(
                    "INSERT INTO call_usage_summary(root_thread_id,thread_id,purpose,cost_currency,amount,revision) VALUES('costs','costs',?,?,?,0)",
                    vec![purpose.purpose.clone().unwrap_or_default().into(), cost.currency.clone().into(), cost.amount.into()],
                )).await?;
            }
        }
        costs_db.close().await?;
        let source_before = test_support::source_evidence(&source_path).await?;
        let origin = HistoryInitialization::ImportV2 {
            source_database: source_path.clone(),
            legacy_state: super::super::state::StateStore::new(
                directory.path().to_owned(),
                "costs",
            )
            .with_legacy_calls(calls.clone()),
            migrate_execution_identity: std::sync::Arc::new(|_| Ok(())),
        };
        history.initialize(origin.clone()).await?;
        history.initialize(origin).await?;
        drop(history);
        let history = HistoryStore::open(&path, "costs").await?;
        history.prepare_activation().await?;
        let restored = history.checkpoint().await?.unwrap();
        let mut preserved_billing = restored.state.extensions.clone();
        preserved_billing.remove(crate::studio::delegation::EXTENSION);
        // Legacy per-request compaction records remain in the source TOML. Only the newest is
        // current state after import; the auxiliary billing records keep their original keys.
        assert_eq!(
            preserved_billing,
            std::collections::BTreeMap::from([
                (
                    "historical-disabled".into(),
                    frozen_billing["historical-disabled"].clone(),
                ),
                ("no-charge".into(), frozen_billing["no-charge"].clone()),
                (
                    crate::compaction::LATEST_RECEIPT.into(),
                    frozen_billing["compaction-no-charge"].clone(),
                ),
            ])
        );
        for (extensions, expected_count) in [(&frozen_billing, 4), (&preserved_billing, 3)] {
            let batch = pl_core::thread::ThreadEffectBatch {
                committed_at: 42,
                extensions: extensions
                    .iter()
                    .map(
                        |(id, record)| pl_core::thread::extensions::ExtensionChange::Put {
                            id: id.clone(),
                            record: record.clone(),
                        },
                    )
                    .collect(),
                ..Default::default()
            };
            let facts = crate::studio::thread_projection::billing_facts(&batch)?;
            assert_eq!(facts.len(), expected_count);
            for fact in facts {
                let expected = if fact.record.inference_id.ends_with("historical-disabled") {
                    pl_protocol::PricingOutcome::Disabled
                } else {
                    pl_protocol::PricingOutcome::NoCharge
                };
                assert_eq!(fact.record.accounting.pricing, expected);
                assert_eq!(fact.record.accounting.usage.total_tokens, Some(110));
                assert!(fact.record.accounting.estimated_costs().is_empty());
            }
        }
        for id in ["no-charge", crate::compaction::LATEST_RECEIPT] {
            let payload = &restored.state.extensions[id].payload;
            let wrong_version =
                pl_core::context::OpaquePayload::new(payload.format(), 2, payload.content())?;
            let wrong_batch = pl_core::thread::ThreadEffectBatch {
                extensions: vec![pl_core::thread::extensions::ExtensionChange::Put {
                    id: id.into(),
                    record: pl_core::thread::extensions::ExtensionRecord {
                        revision: 1,
                        payload: wrong_version,
                    },
                }]
                .into(),
                ..Default::default()
            };
            assert!(
                crate::studio::thread_projection::billing_facts(&wrong_batch).is_err(),
                "NoCharge is not valid in a historical v2 billing/compaction payload"
            );
        }
        assert_eq!(restored.state.usage_summary.estimated_costs[0].amount, 9.0);
        let saved = history.accounting().await?.unwrap().purpose_costs;
        assert_eq!(
            saved
                .iter()
                .flat_map(|(_, costs)| costs)
                .map(|cost| cost.amount)
                .sum::<f64>(),
            9.0
        );
        assert_eq!(
            tokio::fs::read(directory.path().join("state.toml")).await?,
            legacy_toml.as_bytes()
        );
        assert_eq!(
            test_support::source_evidence(&source_path).await?,
            source_before
        );
        source.close().await?;
        calls.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn toml_checkpoint_import_preserves_original_files_and_reopens() -> Result<()> {
        use pl_core::thread::{ThreadCheckpoint, ThreadSnapshot};
        let directory = tempfile::tempdir()?;
        let mut snapshot = ThreadSnapshot::default();
        snapshot.context.records = vec![pl_core::context::ContextRecord {
            id: "retained".into(),
            turn_id: None,
            source: pl_core::context::ContextSource::User,
            content: vec![pl_core::context::ContextContent::Text {
                text: std::sync::Arc::from("retained migration body"),
            }],
            tool_calls: vec![],
        }]
        .into();
        let checkpoint = ThreadCheckpoint::capture("import".into(), 0, snapshot);
        let (external, bodies) = checkpoint.externalize_bodies(1);
        let mut legacy =
            serde_json::to_value(toml::from_str::<toml::Value>(&toml::to_string(&external)?)?)?;
        legacy["schemaVersion"] = serde_json::json!(2);
        legacy["state"]["attempts"] = serde_json::json!([{
            "turnId":"old", "attemptId":"old-attempt", "input":{"revision":0,"records":[]},
            "tools":[], "outcome":{"kind":"running"}
        }]);
        let original = toml::to_string(&legacy)?;
        tokio::fs::write(directory.path().join("state.toml"), original.as_bytes()).await?;
        tokio::fs::write(
            directory.path().join("state.prev.toml"),
            original.as_bytes(),
        )
        .await?;
        tokio::fs::create_dir_all(directory.path().join("blobs/checkpoint")).await?;
        tokio::fs::write(
            directory.path().join("blobs/checkpoint/orphan"),
            b"obsolete",
        )
        .await?;
        tokio::fs::write(directory.path().join("blobs/attachment"), b"keep").await?;
        let state = super::super::state::StateStore::new(directory.path().to_owned(), "import");
        let source_path = directory.path().join("history.sqlite");
        let source = connect(&source_path).await?;
        schema::initialize(&source, "import").await?;
        let source_facts = source_evidence(&source_path).await?;
        let target_path = directory.path().join("history-current.sqlite");
        let history = HistoryStore::open(&target_path, "import").await?;
        let reject = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let rejected = reject.clone();
        let origin = HistoryInitialization::ImportV2 {
            source_database: source_path.clone(),
            legacy_state: state.clone(),
            migrate_execution_identity: std::sync::Arc::new(move |_| {
                ensure!(
                    !rejected.load(std::sync::atomic::Ordering::Acquire),
                    "migration interrupted"
                );
                Ok(())
            }),
        };
        assert!(
            history.initialize(origin.clone()).await.is_err(),
            "missing migration body must preserve source"
        );
        assert_pending(&target_path).await?;
        assert_eq!(source_evidence(&source_path).await?, source_facts);
        assert!(tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        let mut legacy_blobs = Vec::new();
        for body in bodies {
            let hex = body
                .entry
                .reference
                .digest()
                .strip_prefix("sha256:")
                .context("digest")?;
            let directory = directory.path().join("blobs/checkpoint").join(&hex[..2]);
            tokio::fs::create_dir_all(&directory).await?;
            let path = directory.join(hex);
            tokio::fs::write(&path, &body.bytes).await?;
            legacy_blobs.push((path, body.bytes));
        }
        legacy["schemaVersion"] = serde_json::json!(999);
        let future = toml::to_string(&legacy)?;
        tokio::fs::write(directory.path().join("state.toml"), &future).await?;
        assert!(
            history.retry_initialization().await.is_err(),
            "a valid backup must not hide an unknown primary version"
        );
        assert_eq!(
            tokio::fs::read_to_string(directory.path().join("state.toml")).await?,
            future
        );
        assert_pending(&target_path).await?;
        assert_eq!(source_evidence(&source_path).await?, source_facts);
        tokio::fs::write(directory.path().join("state.toml"), &original).await?;
        reject.store(true, std::sync::atomic::Ordering::Release);
        assert!(history.retry_initialization().await.is_err());
        assert!(history.checkpoint().await.is_err());
        assert!(
            !target_path.exists(),
            "failed official import must not publish a current database"
        );
        assert_pending(&target_path).await?;
        assert_eq!(source_evidence(&source_path).await?, source_facts);
        assert!(tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        reject.store(false, std::sync::atomic::Ordering::Release);
        history.set_migration_fault(Some(MigrationFault::LegacyInsert));
        let failure = history.retry_initialization().await.expect_err(
            "legacy checkpoint insertion must occur inside the official target transaction",
        );
        assert!(format!("{failure:#}").contains("injected target history migration write failure"));
        assert_pending(&target_path).await?;
        assert_eq!(source_evidence(&source_path).await?, source_facts);
        history.set_migration_fault(None);
        source
            .execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
            .await?;
        let mismatched = source_evidence(&source_path).await?;
        assert!(
            history.retry_initialization().await.is_err(),
            "mismatched history fence must preserve source"
        );
        assert_pending(&target_path).await?;
        assert_eq!(source_evidence(&source_path).await?, mismatched);
        assert!(tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        source
            .execute_unprepared("UPDATE history_meta SET applied_write_seq=0")
            .await?;
        let ready_source = source_evidence(&source_path).await?;
        history.retry_initialization().await?;
        assert_current(&target_path, "import").await?;
        assert_eq!(source_evidence(&source_path).await?, ready_source);
        let imported = history.checkpoint().await?.context("imported checkpoint")?;
        assert_eq!(imported.state.context, checkpoint.state.context);
        assert!(imported.state.attempt_ids.contains_key("old-attempt"));
        assert_eq!(imported.state_revision, checkpoint.state_revision);
        assert_eq!(
            tokio::fs::read_to_string(directory.path().join("state.toml")).await?,
            original
        );
        assert_eq!(
            tokio::fs::read_to_string(directory.path().join("state.prev.toml")).await?,
            original
        );
        assert_eq!(
            tokio::fs::read(directory.path().join("blobs/checkpoint/orphan")).await?,
            b"obsolete"
        );
        assert_eq!(
            tokio::fs::read(directory.path().join("blobs/attachment")).await?,
            b"keep"
        );
        for (path, bytes) in legacy_blobs {
            assert_eq!(
                tokio::fs::read(path).await?,
                bytes,
                "referenced legacy blob bytes are preserved"
            );
        }
        assert_eq!(
            state
                .load_read_only(&HistoryStore::open(&target_path, "import").await?)
                .await?
                .context("reopened")?
                .state_revision,
            imported.state_revision
        );
        history.initialize(origin).await?;
        source.close().await?;
        Ok(())
    }

    /// 一次普通问答的问题、回答与权威状态。
    ///
    /// 问题原始正文、答案值与私有的 `pl.studio.user-answer` 回执都由这里构造，测试直接用真实
    /// 生产者格式验证历史链路，而不是另造一份测试专用协议。
    struct QuestionFixture {
        questions: Vec<pl_protocol::UserQuestion>,
        answer: serde_json::Value,
    }

    fn question_fixture() -> QuestionFixture {
        QuestionFixture {
            questions: vec![
                pl_protocol::UserQuestion {
                    id: "provider".into(),
                    header: "Provider".into(),
                    question: "Which provider should the next release verify?".into(),
                    is_other: true,
                    is_secret: false,
                    options: Some(vec![pl_protocol::UserQuestionOption {
                        label: "anthropic".into(),
                        description: "Verify the Claude route".into(),
                    }]),
                },
                pl_protocol::UserQuestion {
                    id: "token".into(),
                    header: "Token".into(),
                    question: "Paste the deployment token".into(),
                    is_other: true,
                    is_secret: true,
                    options: None,
                },
            ],
            answer: serde_json::json!({
                "answers": {
                    "provider": {"answers": ["anthropic\nline two"]},
                    "token": {"answers": ["secret-deployment-token"]},
                }
            }),
        }
    }

    fn interaction_record(
        call_id: &str,
        fixture: &QuestionFixture,
        revision: u64,
        state: pl_core::thread::interactions::InteractionState,
    ) -> Result<pl_core::thread::interactions::InteractionRecord> {
        Ok(pl_core::thread::interactions::InteractionRecord {
            created_at: 100,
            updated_at: 100 + i64::try_from(revision)?,
            continuation_id: None,
            request: pl_core::thread::interactions::InteractionRequest {
                id: pl_core::tool::opaque::tool_interaction_id(call_id),
                turn_id: "turn-qa".into(),
                payload: pl_core::context::OpaquePayload::new(
                    "pl.tool.user-input",
                    1,
                    serde_json::to_string(&fixture.questions)?,
                )?,
            },
            revision,
            state,
            extension_mutations: vec![],
        })
    }

    fn answered_record(
        call_id: &str,
        fixture: &QuestionFixture,
    ) -> Result<pl_core::thread::interactions::InteractionRecord> {
        interaction_record(
            call_id,
            fixture,
            2,
            pl_core::thread::interactions::InteractionState::Resolved(
                pl_core::thread::interactions::InteractionResponse {
                    payload: pl_core::context::OpaquePayload::new(
                        "pl.studio.user-answer",
                        1,
                        serde_json::to_string(&fixture.answer)?,
                    )?,
                    context: vec![],
                },
            ),
        )
    }

    /// 一条已经提交过、但还没有问答投影的工具条目（旧历史的样子）。
    fn question_tool_item(call_id: &str, thread_id: &str, ordinal: u64) -> ThreadItem {
        ThreadItem::new(
            order::tool_id(call_id),
            thread_id.into(),
            "turn-qa".into(),
            ordinal,
            3,
            111,
            222,
            ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    call_id.into(),
                    "request_user_input".into(),
                    "{\"questions\":[]}".into(),
                ),
                pl_protocol::ThreadToolState::Running(pl_protocol::RunningThreadTool::new(
                    String::new(),
                )),
            )),
        )
    }

    fn question_effect(
        commit: i64,
        sequence: u64,
        records: Vec<pl_core::thread::interactions::InteractionRecord>,
    ) -> pl_core::thread::ThreadEffectBatch {
        pl_core::thread::ThreadEffectBatch {
            committed_at: commit,
            sequence,
            interactions: records.into(),
            ..Default::default()
        }
    }

    /// 一条真实的计划确认事实：提问正文就是计划文档，hash、问题身份与选项都由生产者格式约束。
    fn plan_fixture(plan: &str) -> Result<crate::plan_tool::PlanConfirmationPrompt> {
        use pl_protocol::{MessagePresentation, UserQuestion, UserQuestionOption};
        Ok(crate::plan_tool::PlanConfirmationPrompt {
            question: UserQuestion {
                id: pl_protocol::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                header: "Plan".into(),
                question: plan.into(),
                is_other: true,
                is_secret: false,
                options: Some(vec![
                    UserQuestionOption {
                        label: "Approve".into(),
                        description: "Approve this exact Plan and allow the task to proceed."
                            .into(),
                    },
                    UserQuestionOption {
                        label: "Revise".into(),
                        description: "Request a revised Plan and optionally describe the changes."
                            .into(),
                    },
                ]),
            },
            expected_plan_revision: 1,
            plan_hash: pl_core::context::content_hash(plan.as_bytes()),
            created_at: 100,
            presentation: MessagePresentation::Hidden,
        })
    }

    /// `plan_submit` 的工具条目：调用已发起计划确认，旧历史里还没有 typed 计划回执。
    fn plan_tool_item(call_id: &str, thread_id: &str, ordinal: u64) -> ThreadItem {
        ThreadItem::new(
            order::tool_id(call_id),
            thread_id.into(),
            "turn-plan".into(),
            ordinal,
            3,
            111,
            222,
            ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    call_id.into(),
                    "plan_submit".into(),
                    "{\"expectedRevision\":0,\"plan\":\"# Plan\"}".into(),
                ),
                pl_protocol::ThreadToolState::Running(pl_protocol::RunningThreadTool::new(
                    String::new(),
                )),
            )),
        )
    }

    fn plan_interaction_record(
        call_id: &str,
        prompt: &crate::plan_tool::PlanConfirmationPrompt,
        revision: u64,
        state: pl_core::thread::interactions::InteractionState,
    ) -> Result<pl_core::thread::interactions::InteractionRecord> {
        Ok(pl_core::thread::interactions::InteractionRecord {
            created_at: 100,
            updated_at: 100 + i64::try_from(revision)?,
            continuation_id: None,
            request: pl_core::thread::interactions::InteractionRequest {
                id: pl_core::tool::opaque::tool_interaction_id(call_id),
                turn_id: "turn-plan".into(),
                payload: pl_core::context::OpaquePayload::new(
                    crate::plan_tool::PLAN_CONFIRMATION_FORMAT,
                    1,
                    serde_json::to_string(prompt)?,
                )?,
            },
            revision,
            state,
            extension_mutations: vec![],
        })
    }

    /// 已解决的计划确认：决定标记与用户反馈都留在答案列表里，原样保留。
    fn plan_decision_record(
        call_id: &str,
        prompt: &crate::plan_tool::PlanConfirmationPrompt,
        answers: &[&str],
    ) -> Result<pl_core::thread::interactions::InteractionRecord> {
        plan_interaction_record(
            call_id,
            prompt,
            2,
            pl_core::thread::interactions::InteractionState::Resolved(
                pl_core::thread::interactions::InteractionResponse {
                    payload: pl_core::context::OpaquePayload::new(
                        crate::plan_tool::PLAN_ANSWER_FORMAT,
                        1,
                        serde_json::to_string(&serde_json::json!({
                            "answers": {
                                pl_protocol::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID: {
                                    "answers": answers
                                }
                            }
                        }))?,
                    )?,
                    context: vec![],
                },
            ),
        )
    }

    /// 已回答的问答必须落在原工具条目上：ID、ordinal、创建时间与 Turn 不变，只增加问答正文。
    #[test]
    fn ordinary_user_answer_updates_the_calling_item_in_place() -> Result<()> {
        let thread = pl_protocol::Thread::placeholder("qa-thread");
        let fixture = question_fixture();
        let call_id = "call-qa";
        let saved = question_tool_item(call_id, &thread.id, 7);
        let mut existing = std::collections::BTreeMap::new();
        existing.insert(saved.id.clone(), saved.clone());
        let projection = |record| {
            crate::studio::thread_projection::project_effect_items(
                &thread,
                &pl_core::thread::ThreadSnapshot::default(),
                &question_effect(500, 9, vec![record]),
                &existing,
                &Default::default(),
                &Default::default(),
            )
        };

        let pending = interaction_record(
            call_id,
            &fixture,
            1,
            pl_core::thread::interactions::InteractionState::Pending,
        )?;
        let waiting = projection(pending)?;
        assert_eq!(waiting.items.len(), 1);
        let item = waiting.items[0].tool().context("tool item")?;
        let user_input = item.user_input().context("pending Q&A")?;
        assert!(matches!(
            user_input.state(),
            pl_protocol::ThreadToolUserInputState::Pending
        ));
        assert_eq!(user_input.questions().len(), 2);
        assert_eq!(waiting.items[0].id, saved.id);
        assert_eq!(waiting.items[0].ordinal, 7);
        assert_eq!(waiting.items[0].created_at, 111);
        assert_eq!(waiting.items[0].turn_id, "turn-qa");

        let answered = projection(answered_record(call_id, &fixture)?)?;
        // 同一个条目，不是第二条问答记录。
        assert_eq!(answered.items.len(), 1);
        assert_eq!(answered.items[0].id, saved.id);
        assert_eq!(answered.items[0].ordinal, 7);
        assert_eq!(answered.items[0].created_at, 111);
        let user_input = answered.items[0]
            .tool()
            .and_then(|tool| tool.user_input())
            .context("answered Q&A")?;
        let answers = user_input.answers();
        assert_eq!(answers.len(), 2);
        assert_eq!(answers[0].question_id(), "provider");
        assert_eq!(answers[0].answers(), ["anthropic\nline two"]);
        // 敏感回答只公开它已被回答，原值不进入公开投影。
        assert!(answers[1].is_redacted());
        assert!(answers[1].answers().is_empty());
        assert!(answered.items[0].revision >= 1);
        Ok(())
    }

    /// 计划决定落在发起它的 `plan_submit` 条目上：身份、顺序与创建时间不变，状态与答案都取自
    /// 同一份 canonical 交互事实，不因工具成功或当前计划而推演。
    #[test]
    fn plan_confirmation_history_lands_on_the_submitting_call_in_place() -> Result<()> {
        use pl_protocol::ThreadToolUserInputState;

        let thread = pl_protocol::Thread::placeholder("plan-thread");
        let plan = "# Plan\n\n1. Migrate the receipts.\n";
        let prompt = plan_fixture(plan)?;
        let saved = plan_tool_item("call-plan", &thread.id, 5);
        let mut existing = std::collections::BTreeMap::new();
        existing.insert(saved.id.clone(), saved.clone());
        let projection = |record| {
            crate::studio::thread_projection::project_effect_items(
                &thread,
                &pl_core::thread::ThreadSnapshot::default(),
                &question_effect(500, 9, vec![record]),
                &existing,
                &Default::default(),
                &Default::default(),
            )
        };

        let waiting = projection(plan_interaction_record(
            "call-plan",
            &prompt,
            1,
            pl_core::thread::interactions::InteractionState::Pending,
        )?)?;
        assert_eq!(waiting.items.len(), 1);
        let item = &waiting.items[0];
        assert_eq!(item.id, saved.id);
        assert_eq!(item.ordinal, 5);
        assert_eq!(item.created_at, 111);
        assert_eq!(item.turn_id, "turn-plan");
        let pending = item
            .tool()
            .and_then(|tool| tool.user_input())
            .context("pending Plan confirmation")?;
        assert_eq!(
            pending.interaction_id(),
            pl_core::tool::opaque::tool_interaction_id("call-plan")
        );
        assert!(matches!(pending.state(), ThreadToolUserInputState::Pending));
        assert_eq!(pending.questions().len(), 1);
        assert_eq!(
            pending.questions()[0].id,
            pl_protocol::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID
        );
        assert_eq!(pending.questions()[0].question, plan);
        assert_eq!(
            pending.questions()[0]
                .options
                .as_ref()
                .map(|options| options.iter().map(|option| option.label.as_str()).collect()),
            Some(vec!["Approve", "Revise"])
        );

        // 请求修改：Revise 标记与完整的用户反馈原样保留在答案列表里，不在历史投影里二次解读。
        let revised = projection(plan_decision_record(
            "call-plan",
            &prompt,
            &["Revise", "split the migration step"],
        )?)?;
        assert_eq!(revised.items.len(), 1);
        let item = &revised.items[0];
        assert_eq!(item.id, saved.id);
        assert_eq!(item.ordinal, 5);
        assert_eq!(item.created_at, 111);
        let decision = item
            .tool()
            .and_then(|tool| tool.user_input())
            .context("resolved Plan confirmation")?;
        let answers = decision.answers();
        assert_eq!(answers.len(), 1);
        assert_eq!(
            answers[0].question_id(),
            pl_protocol::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID
        );
        assert_eq!(answers[0].answers(), ["Revise", "split the migration step"]);
        assert!(!answers[0].is_redacted());
        Ok(())
    }

    /// 调用正文只剩历史时，投影报告该 identity 让调用方补读，而不是丢下已回答的问答。
    #[test]
    fn pruned_call_reports_the_identity_instead_of_dropping_the_answer() -> Result<()> {
        let thread = pl_protocol::Thread::placeholder("qa-thread");
        let fixture = question_fixture();
        let projection = crate::studio::thread_projection::project_effect_items(
            &thread,
            &pl_core::thread::ThreadSnapshot::default(),
            &question_effect(500, 9, vec![answered_record("call-qa", &fixture)?]),
            &Default::default(),
            &Default::default(),
            &Default::default(),
        )?;
        assert!(projection.items.is_empty());
        assert_eq!(
            projection.unresolved_calls,
            [order::tool_id("call-qa")].into()
        );

        // live 投影只剩放置元数据占位（真实正文已被回收）时同样报告 identity，绝不静默丢弃权威问答。
        let mut placeholder = question_tool_item("call-qa", &thread.id, 7);
        placeholder =
            placeholder.with_state(ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
                vec![],
                "This item's body is no longer resident in the live preview cache.",
                111,
            )));
        let mut resident = std::collections::BTreeMap::new();
        resident.insert(placeholder.id.clone(), placeholder.clone());
        let without_body = crate::studio::thread_projection::project_effect_items(
            &thread,
            &pl_core::thread::ThreadSnapshot::default(),
            &question_effect(500, 9, vec![answered_record("call-qa", &fixture)?]),
            &resident,
            &Default::default(),
            &Default::default(),
        )?;
        assert!(without_body.items.is_empty());
        assert_eq!(
            without_body.unresolved_calls,
            [order::tool_id("call-qa")].into()
        );

        // 补读到 durable 正文后，同一次投影就落在原条目上。
        let saved = question_tool_item("call-qa", &thread.id, 7);
        let mut existing = std::collections::BTreeMap::new();
        existing.insert(saved.id.clone(), saved);
        let resolved = crate::studio::thread_projection::project_effect_items(
            &thread,
            &pl_core::thread::ThreadSnapshot::default(),
            &question_effect(500, 9, vec![answered_record("call-qa", &fixture)?]),
            &existing,
            &Default::default(),
            &Default::default(),
        )?;
        resolved.ensure_complete()?;
        assert_eq!(resolved.items.len(), 1);
        assert!(
            resolved.items[0]
                .tool()
                .and_then(|tool| tool.user_input())
                .is_some_and(|input| input.state().is_resolved())
        );
        Ok(())
    }

    /// 同一调用后续重新投影（任务状态推进、结果交付）不会抹掉已保存的问答。
    ///
    /// 问答属于交互事实，不属于这一次工具状态转移；重新投影必须把它带回同一条目。
    #[test]
    fn later_projection_of_the_same_call_keeps_the_saved_answer() -> Result<()> {
        use pl_core::thread::task::{TaskRecord, TaskStatus};

        let thread = pl_protocol::Thread::placeholder("qa-thread");
        let fixture = question_fixture();
        let mut answered = question_tool_item("call-qa", &thread.id, 7);
        let record = answered_record("call-qa", &fixture)?;
        crate::studio::thread_projection::attach_tool_user_input(
            &mut answered,
            crate::studio::thread_projection::project_tool_user_input(&thread.id, &record)?
                .context("answered Q&A")?,
        )?;
        let mut existing = std::collections::BTreeMap::new();
        existing.insert(answered.id.clone(), answered.clone());
        let task = TaskRecord {
            id: "task:call-qa".into(),
            call_id: "call-qa".into(),
            tool_id: "request_user_input".into(),
            turn_id: "turn-qa".into(),
            revision: 2,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(9),
        };
        let effect = pl_core::thread::ThreadEffectBatch {
            committed_at: 600,
            sequence: 10,
            tasks: [task].into(),
            ..Default::default()
        };
        let projection = crate::studio::thread_projection::project_effect_items(
            &thread,
            &pl_core::thread::ThreadSnapshot::default(),
            &effect,
            &existing,
            &Default::default(),
            &Default::default(),
        )?;
        let item = projection
            .items
            .iter()
            .find(|item| item.id == answered.id)
            .context("re-projected tool item")?;
        let answers = item
            .tool()
            .and_then(|tool| tool.user_input())
            .context("kept Q&A")?
            .answers();
        assert_eq!(answers[0].answers(), ["anthropic\nline two"]);
        assert!(answers[1].is_redacted());
        Ok(())
    }

    /// 旧历史（v2 结构、v6 schema）在打开时从 durable 交互回执补齐问答，原位迁移且可重复打开。
    #[tokio::test]
    async fn legacy_history_gains_the_answered_qa_in_place_once() -> Result<()> {
        use pl_core::thread::interactions::InteractionState;

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "qa-thread";
        let fixture = question_fixture();
        let saved = question_tool_item("call-qa", thread_id, 4);
        let pending = interaction_record("call-qa", &fixture, 1, InteractionState::Pending)?;
        let answered = answered_record("call-qa", &fixture)?;
        let receipts: Vec<FactReceiptWrite> = [&pending, &answered]
            .into_iter()
            .map(|record| FactReceiptWrite {
                item_id: order::receipt_id("interaction", &record.request.id),
                revision: record.revision,
                kind: "interaction",
                payload: serde_json::to_string(record).expect("encode receipt"),
            })
            .collect();
        let store = HistoryStore::open(&path, thread_id).await?;
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&saved),
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        // 旧库：条目里没有问答投影，schema 停在补齐之前。
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=6",
            )
            .await?;
        drop(store);

        let source = source_evidence(&path).await?;
        let target = directory.path().join("history-current.sqlite");
        let migrated = import_source(&path, &target, thread_id).await?;
        migrated.prepare_activation().await?;
        let items = migrated.existing_items([saved.id.clone()]).await?;
        let item = items.get(&saved.id).context("migrated tool item")?;
        assert_eq!(item.ordinal, 4);
        assert_eq!(item.created_at, 111);
        assert_eq!(item.turn_id, "turn-qa");
        let user_input = item
            .tool()
            .and_then(|tool| tool.user_input())
            .context("migrated Q&A")?;
        assert_eq!(user_input.interaction_id(), "tool-interaction:call-qa");
        assert_eq!(
            user_input.questions()[0].question,
            "Which provider should the next release verify?"
        );
        let answers = user_input.answers();
        assert_eq!(answers[0].answers(), ["anthropic\nline two"]);
        assert!(answers[1].is_redacted(), "secret answer must stay private");
        let migrated_revision = item.revision;
        // 私有回执仍是原始 payload：敏感答案没有被公开投影改写。
        let receipt = migrated
            .latest_fact_receipt(&order::receipt_id(
                "interaction",
                "tool-interaction:call-qa",
            ))
            .await?
            .context("interaction receipt")?;
        assert!(receipt.payload.contains("secret-deployment-token"));
        drop(migrated);

        // 二次打开不再改变内容，也不会丢答案或重复推进版本。
        let reopened = HistoryStore::open(&target, thread_id).await?;
        reopened.prepare_activation().await?;
        let again = reopened.existing_items([saved.id.clone()]).await?;
        let item = again.get(&saved.id).context("reopened tool item")?;
        assert_eq!(item.revision, migrated_revision);
        assert_eq!(
            item.tool()
                .and_then(|tool| tool.user_input())
                .map(|input| input.answers().len()),
            Some(2)
        );
        assert_eq!(source_evidence(&path).await?, source);
        assert_current(&target, thread_id).await?;
        Ok(())
    }

    /// 迁移只原位改载荷，不推进内容版本：身份/顺序/时间/版本不变，紧接的正常提交仍能写回。
    ///
    /// 若迁移自己推进了 revision，紧接着的内容变化就会撞上同一 revision 的不同载荷（history item
    /// revision conflict），或把真实内容版本挤到迁移伪造的版本域之下而被静默丢弃。
    #[tokio::test]
    async fn migrated_qa_keeps_the_content_version_and_accepts_the_next_commit() -> Result<()> {
        use pl_core::thread::interactions::InteractionState;
        use pl_protocol::{SucceededThreadTool, ThreadToolOutput, ThreadToolState};

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "qa-version";
        let fixture = question_fixture();
        let saved = question_tool_item("call-version", thread_id, 4);
        let pending = interaction_record("call-version", &fixture, 1, InteractionState::Pending)?;
        let answered = answered_record("call-version", &fixture)?;
        let receipts: Vec<FactReceiptWrite> = [&pending, &answered]
            .into_iter()
            .map(|record| FactReceiptWrite {
                item_id: order::receipt_id("interaction", &record.request.id),
                revision: record.revision,
                kind: "interaction",
                payload: serde_json::to_string(record).expect("encode receipt"),
            })
            .collect();
        let store = HistoryStore::open(&path, thread_id).await?;
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&saved),
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=6",
            )
            .await?;
        drop(store);

        let source = source_evidence(&path).await?;
        let target = directory.path().join("history-current.sqlite");
        let migrated = import_source(&path, &target, thread_id).await?;
        migrated.prepare_activation().await?;
        let item = migrated
            .existing_items([saved.id.clone()])
            .await?
            .remove(&saved.id)
            .context("migrated tool item")?;
        assert_eq!(item.ordinal, 4);
        assert_eq!(item.created_at, 111);
        assert_eq!(item.turn_id, "turn-qa");
        // 迁移不伪造内容版本：读回的基线仍是被迁移条目的原版本。
        assert_eq!(
            item.revision, 3,
            "content version must be preserved by the migration"
        );
        let user_input = item
            .tool()
            .and_then(|tool| tool.user_input())
            .context("migrated Q&A")?;
        assert_eq!(user_input.answers()[0].answers(), ["anthropic\nline two"]);

        // 正常的下一次内容提交：同一身份在原版本上推进一次（结果交付），必须落库成功。
        let mut delivered = item.clone();
        delivered.revision = 4;
        delivered.updated_at = 700;
        let tool = item.tool().context("tool item")?.clone();
        delivered = delivered.with_state(ThreadItemState::Tool(
            pl_protocol::ThreadToolItem::new(
                tool.invocation().clone(),
                ThreadToolState::Succeeded(SucceededThreadTool::new(
                    700,
                    ThreadToolOutput::new(
                        "waiting for the user's response.".into(),
                        vec![],
                        vec![],
                        None,
                    ),
                )),
            )
            .with_user_input(Some(user_input.clone())),
        ));
        migrated
            .commit_effect(
                2,
                EffectCommit {
                    items: std::slice::from_ref(&delivered),
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
        let reread = migrated
            .existing_items([item.id.clone()])
            .await?
            .remove(&item.id)
            .context("re-read tool item")?;
        assert_eq!(reread.revision, 4);
        let answers = reread
            .tool()
            .and_then(|tool| tool.user_input())
            .context("kept Q&A after the next commit")?
            .answers();
        assert_eq!(answers[0].answers(), ["anthropic\nline two"]);
        assert_eq!(source_evidence(&path).await?, source);
        assert_current(&target, thread_id).await?;
        Ok(())
    }

    /// 取消的问答保持取消事实，不会被伪造成已回答。
    #[tokio::test]
    async fn cancelled_question_is_migrated_as_cancelled() -> Result<()> {
        use pl_core::thread::interactions::InteractionState;

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "qa-cancelled";
        let fixture = question_fixture();
        let saved = question_tool_item("call-cancel", thread_id, 2);
        let cancelled =
            interaction_record("call-cancel", &fixture, 2, InteractionState::Cancelled)?;
        let receipts = [FactReceiptWrite {
            item_id: order::receipt_id("interaction", &cancelled.request.id),
            revision: cancelled.revision,
            kind: "interaction",
            payload: serde_json::to_string(&cancelled)?,
        }];
        let store = HistoryStore::open(&path, thread_id).await?;
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&saved),
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=6",
            )
            .await?;
        drop(store);

        let source = source_evidence(&path).await?;
        let target = directory.path().join("history-current.sqlite");
        let migrated = import_source(&path, &target, thread_id).await?;
        migrated.prepare_activation().await?;
        let items = migrated.existing_items([saved.id.clone()]).await?;
        let user_input = items
            .get(&saved.id)
            .and_then(|item| item.tool())
            .and_then(|tool| tool.user_input())
            .context("migrated cancelled Q&A")?;
        assert!(matches!(
            user_input.state(),
            pl_protocol::ThreadToolUserInputState::Cancelled
        ));
        assert!(user_input.answers().is_empty());
        assert_eq!(source_evidence(&path).await?, source);
        assert_current(&target, thread_id).await?;
        Ok(())
    }

    /// schema 7 的库已有计划提问与决定回执、但条目还没有 typed 计划历史：打开时从 durable 回执
    /// 原位补齐。批准与取消都以保存的交互事实为准，身份、顺序、时间、内容版本与私有回执不变，
    /// 后续正常提交继续在迁移后的版本域上推进，重开幂等。
    #[tokio::test]
    async fn legacy_v7_history_gains_the_plan_decisions_in_place() -> Result<()> {
        use pl_core::thread::interactions::InteractionState;
        use pl_protocol::{SucceededThreadTool, ThreadToolOutput, ThreadToolState};

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "plan-history";
        let approved_plan = "# Plan\n\n1. Approve this path.\n";
        let cancelled_plan = "# Plan\n\n1. Cancel this path.\n";
        let approved_prompt = plan_fixture(approved_plan)?;
        let cancelled_prompt = plan_fixture(cancelled_plan)?;
        let approved_item = plan_tool_item("call-approve", thread_id, 3);
        let cancelled_item = plan_tool_item("call-cancel", thread_id, 5);
        let records = [
            plan_interaction_record(
                "call-approve",
                &approved_prompt,
                1,
                InteractionState::Pending,
            )?,
            plan_decision_record("call-approve", &approved_prompt, &["Approve"])?,
            plan_interaction_record(
                "call-cancel",
                &cancelled_prompt,
                1,
                InteractionState::Pending,
            )?,
            plan_interaction_record(
                "call-cancel",
                &cancelled_prompt,
                2,
                InteractionState::Cancelled,
            )?,
        ];
        let receipts: Vec<FactReceiptWrite> = records
            .iter()
            .map(|record| FactReceiptWrite {
                item_id: order::receipt_id("interaction", &record.request.id),
                revision: record.revision,
                kind: "interaction",
                payload: serde_json::to_string(record).expect("encode receipt"),
            })
            .collect();
        let store = HistoryStore::open(&path, thread_id).await?;
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: &[approved_item.clone(), cancelled_item.clone()],
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        // 旧库：schema 停在计划历史补齐之前，条目里没有 typed 计划回执。
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=7",
            )
            .await?;
        drop(store);

        let source = source_evidence(&path).await?;
        let target = directory.path().join("history-current.sqlite");
        let migrated = import_source(&path, &target, thread_id).await?;
        migrated.prepare_activation().await?;
        let items = migrated
            .existing_items([approved_item.id.clone(), cancelled_item.id.clone()])
            .await?;
        let approved = items.get(&approved_item.id).context("approved Plan item")?;
        assert_eq!(approved.ordinal, 3);
        assert_eq!(approved.created_at, 111);
        assert_eq!(approved.turn_id, "turn-plan");
        assert_eq!(
            approved.revision, approved_item.revision,
            "the migration keeps the content version"
        );
        let decision = approved
            .tool()
            .and_then(|tool| tool.user_input())
            .context("approved Plan history")?;
        assert_eq!(
            decision.interaction_id(),
            pl_core::tool::opaque::tool_interaction_id("call-approve")
        );
        assert_eq!(decision.questions().len(), 1);
        assert_eq!(
            decision.questions()[0].id,
            pl_protocol::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID
        );
        assert_eq!(decision.questions()[0].question, approved_plan);
        assert_eq!(decision.answers()[0].answers(), ["Approve"]);

        // 取消保留真实取消状态，不被伪造成已批准。
        let cancelled = items
            .get(&cancelled_item.id)
            .context("cancelled Plan item")?;
        let cancelled_history = cancelled
            .tool()
            .and_then(|tool| tool.user_input())
            .context("cancelled Plan history")?;
        assert!(matches!(
            cancelled_history.state(),
            pl_protocol::ThreadToolUserInputState::Cancelled
        ));
        assert!(cancelled_history.answers().is_empty());

        // 私有交互回执仍是原始载荷：派生补齐只写派生条目，不改写原始答案与上下文。
        let receipt = migrated
            .latest_fact_receipt(&order::receipt_id(
                "interaction",
                &pl_core::tool::opaque::tool_interaction_id("call-approve"),
            ))
            .await?
            .context("Plan interaction receipt")?;
        assert!(receipt.payload.contains("Approve"));

        // 正常的下一次内容提交（真正的工具结果交付）继续在迁移后的版本域上推进一次。
        let tool = approved.tool().context("tool item")?.clone();
        let mut delivered = approved.clone();
        delivered.revision = approved.revision.checked_add(1).context("revision")?;
        delivered.updated_at = 700;
        delivered = delivered.with_state(ThreadItemState::Tool(
            pl_protocol::ThreadToolItem::new(
                tool.invocation().clone(),
                ThreadToolState::Succeeded(SucceededThreadTool::new(
                    700,
                    ThreadToolOutput::new(
                        "waiting for the user's response.".into(),
                        vec![],
                        vec![],
                        None,
                    ),
                )),
            )
            .with_user_input(tool.user_input().cloned()),
        ));
        migrated
            .commit_effect(
                2,
                EffectCommit {
                    items: std::slice::from_ref(&delivered),
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
        let reread = migrated
            .existing_items([approved_item.id.clone()])
            .await?
            .remove(&approved_item.id)
            .context("committed Plan item")?;
        assert_eq!(reread.revision, delivered.revision);
        assert_eq!(
            reread
                .tool()
                .and_then(|tool| tool.user_input())
                .map(|input| input.answers()[0].answers().to_vec()),
            Some(vec!["Approve".to_string()])
        );
        let migrated_revision = reread.revision;
        drop(migrated);

        // 二次打开不再改变内容：幂等重开保留身份、顺序与版本。
        let reopened = HistoryStore::open(&target, thread_id).await?;
        reopened.prepare_activation().await?;
        let again = reopened.existing_items([approved_item.id.clone()]).await?;
        let item = again.get(&approved_item.id).context("reopened Plan item")?;
        assert_eq!(item.revision, migrated_revision);
        assert_eq!(item.ordinal, 3);
        assert_eq!(item.created_at, 111);
        assert!(
            item.tool()
                .and_then(|tool| tool.user_input())
                .is_some_and(|input| input.state().is_resolved())
        );
        assert_eq!(source_evidence(&path).await?, source);
        assert_current(&target, thread_id).await?;
        Ok(())
    }

    /// 计划历史补齐失败必须回滚整个升级：schema 停在原版本、条目保留迁移前载荷，修好后可重试。
    #[tokio::test]
    async fn failed_plan_history_migration_rolls_back_schema_and_items() -> Result<()> {
        use pl_core::thread::interactions::InteractionState;

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "plan-rollback";
        let plan = "# Plan\n\n1. Rollback path.\n";
        let prompt = plan_fixture(plan)?;
        let saved = plan_tool_item("call-plan", thread_id, 2);
        let records = [
            plan_interaction_record("call-plan", &prompt, 1, InteractionState::Pending)?,
            plan_decision_record("call-plan", &prompt, &["Approve"])?,
        ];
        let receipts: Vec<FactReceiptWrite> = records
            .iter()
            .map(|record| FactReceiptWrite {
                item_id: order::receipt_id("interaction", &record.request.id),
                revision: record.revision,
                kind: "interaction",
                payload: serde_json::to_string(record).expect("encode receipt"),
            })
            .collect();
        let store = HistoryStore::open(&path, thread_id).await?;
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&saved),
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &receipts,
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        store
            .writer()
            .await?
            .db
            .execute_unprepared(
                "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=7",
            )
            .await?;
        drop(store);

        let source = source_evidence(&path).await?;
        let target = directory.path().join("history-current.sqlite");
        let failed = HistoryStore::open(&target, thread_id).await?;
        failed.set_migration_fault(Some(MigrationFault::ToolAnswerUpdate));
        let failure = failed
            .initialize(import_origin(&path, thread_id)?)
            .await
            .expect_err("target Q&A update must be rejected");
        assert!(format!("{failure:#}").contains("injected target history migration write failure"));
        assert_pending(&target).await?;
        assert_eq!(source_evidence(&path).await?, source);
        let reader = connect_read_only(&path).await?;
        let meta = reader
            .query_one_raw(statement(
                "SELECT schema_version FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("source meta")?;
        assert_eq!(meta.try_get::<i64>("", "schema_version")?, 7);
        let row = reader
            .query_one_raw(statement(
                "SELECT payload FROM history_items WHERE item_id=?",
                vec![saved.id.clone().into()],
            ))
            .await?
            .context("pre-migration item")?;
        let unchanged: ThreadItem = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        assert!(
            unchanged
                .tool()
                .is_some_and(|tool| tool.user_input().is_none()),
            "a failed migration must not publish a Plan history"
        );
        assert_eq!(unchanged.revision, saved.revision);
        reader.close().await?;
        failed.set_migration_fault(None);
        failed.retry_initialization().await?;
        let restored = HistoryStore::open(&target, thread_id).await?;
        restored.prepare_activation().await?;
        let migrated = restored
            .existing_items([saved.id.clone()])
            .await?
            .remove(&saved.id)
            .context("migrated Plan item")?;
        assert_eq!(migrated.revision, saved.revision);
        assert_eq!(
            migrated
                .tool()
                .and_then(|tool| tool.user_input())
                .map(|input| input.answers()[0].answers().to_vec()),
            Some(vec!["Approve".to_string()])
        );
        assert_current(&target, thread_id).await?;
        assert_eq!(source_evidence(&path).await?, source);
        Ok(())
    }

    /// 无法验证的计划事实显式失败：改过的计划正文与内核拒绝的决定都不会被当成批准。
    #[test]
    fn unverifiable_plan_facts_fail_instead_of_faking_an_approval() -> Result<()> {
        let plan = "# Plan\n\n1. Verified path.\n";
        // 正文与生产者记录的 hash 不再一致。
        let mut tampered = plan_fixture(plan)?;
        tampered.plan_hash = pl_core::context::content_hash(b"another plan");
        let changed = plan_decision_record("call-plan", &tampered, &["Approve"])?;
        let failure =
            crate::studio::thread_projection::project_tool_user_input("plan-thread", &changed)
                .expect_err("a changed Plan text must not be published as approved");
        assert!(failure.to_string().contains("Plan confirmation"));
        assert!(
            !failure.to_string().contains("Verified path"),
            "the diagnostic must not republish the Plan body: {failure}"
        );

        // 决定语义由 Plan 内核判定：同时选择批准与修改、以及没有任何决定的已解决事实都拒绝，
        // 证明历史投影确实复用了 owner 的校验，而不是自己猜一个决定。
        let prompt = plan_fixture(plan)?;
        for answers in [vec!["Approve", "Revise"], vec![]] {
            let rejected = plan_decision_record("call-plan", &prompt, &answers)?;
            let failure =
                crate::studio::thread_projection::project_tool_user_input("plan-thread", &rejected)
                    .expect_err("a Plan decision the kernel rejects must not be published");
            let diagnostic = failure.to_string();
            assert!(
                diagnostic.contains("decision is invalid"),
                "the rejection must name the owner decision check: {diagnostic}"
            );
            assert!(
                !diagnostic.contains("Verified path"),
                "the diagnostic must not republish the Plan body: {diagnostic}"
            );
        }
        Ok(())
    }

    /// 跳过的题不伪造成“已回答但隐藏”：空答案列表只是没有作答，只有真正提供的敏感答案才脱敏。
    #[test]
    fn skipped_questions_are_not_published_as_hidden_answers() -> Result<()> {
        let fixture = question_fixture();
        let mut record = answered_record("call-skip", &fixture)?;
        record.state = pl_core::thread::interactions::InteractionState::Resolved(
            pl_core::thread::interactions::InteractionResponse {
                payload: pl_core::context::OpaquePayload::new(
                    "pl.studio.user-answer",
                    1,
                    serde_json::to_string(&serde_json::json!({
                        "answers": {
                            "provider": {"answers": ["anthropic"]},
                            "token": {"answers": []},
                        }
                    }))?,
                )?,
                context: vec![],
            },
        );

        let projection =
            crate::studio::thread_projection::project_tool_user_input("qa-thread", &record)?
                .context("Q&A")?;
        let answers = projection.answers();
        assert!(projection.state().is_resolved());
        assert_eq!(answers.len(), 1, "an empty answer list is not an answer");
        assert_eq!(answers[0].question_id(), "provider");
        assert_eq!(answers[0].answers(), ["anthropic"]);
        assert!(
            answers.iter().all(|answer| !answer.is_redacted()),
            "a skipped sensitive question must not be published as a hidden answer"
        );

        // 真正提供了值的敏感题仍然只公开“已回答/已隐藏”，原值不进入公开投影。
        let provided = crate::studio::thread_projection::project_tool_user_input(
            "qa-thread",
            &answered_record("call-skip", &fixture)?,
        )?
        .context("provided Q&A")?;
        let secret = provided
            .answers()
            .iter()
            .find(|answer| answer.question_id() == "token")
            .context("sensitive answer")?;
        assert!(secret.is_redacted());
        assert!(secret.answers().is_empty());
        Ok(())
    }

    /// 无法解码的交互事实显式失败，不伪造任何问答，也不把私密答案带进诊断。
    #[tokio::test]
    async fn unreadable_qa_facts_fail_the_migration_instead_of_faking_an_answer() -> Result<()> {
        use pl_core::thread::interactions::{InteractionResponse, InteractionState};

        let mut unsupported = answered_record("call-broken", &question_fixture())?;
        unsupported.request.payload =
            pl_core::context::OpaquePayload::new("pl.tool.user-input", 2, "[]")?;

        let mut unknown_question = answered_record("call-broken", &question_fixture())?;
        unknown_question.state = InteractionState::Resolved(InteractionResponse {
            payload: pl_core::context::OpaquePayload::new(
                "pl.studio.user-answer",
                1,
                serde_json::to_string(&serde_json::json!({
                    "answers": {"never-asked": {"answers": ["secret-deployment-token"]}}
                }))?,
            )?,
            context: vec![],
        });

        for (index, record) in [unsupported, unknown_question].into_iter().enumerate() {
            let directory = tempfile::tempdir()?;
            let path = directory.path().join("history.sqlite");
            let thread_id = format!("qa-broken-{index}");
            let saved = question_tool_item("call-broken", &thread_id, 2);
            let receipts = [FactReceiptWrite {
                item_id: order::receipt_id("interaction", &record.request.id),
                revision: record.revision,
                kind: "interaction",
                payload: serde_json::to_string(&record)?,
            }];
            let store = HistoryStore::open(&path, &thread_id).await?;
            store
                .commit_effect(
                    1,
                    EffectCommit {
                        items: std::slice::from_ref(&saved),
                        rolled_back_turns: &Default::default(),
                        identities: &[],
                        messages: &[],
                        receipts: &receipts,
                        tasks: &[],
                        deliveries: &[],
                        delivery_repairs: &[],
                        attempt: None,
                    },
                )
                .await?;
            store
                .writer()
                .await?
                .db
                .execute_unprepared("DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=6")
                .await?;
            drop(store);

            let source = source_evidence(&path).await?;
            let target = directory.path().join("history-current.sqlite");
            let reopened = HistoryStore::open(&target, &thread_id).await?;
            let failure = reopened
                .initialize(import_origin(&path, &thread_id)?)
                .await
                .expect_err("a corrupt Q&A fact must fail the migration");
            let diagnostic = format!("{failure:#}");
            assert!(
                !diagnostic.contains("secret-deployment-token"),
                "the diagnostic must not leak a private answer: {diagnostic}"
            );
            // 显式失败：条目仍是迁移前的样子，没有被伪造成已回答。
            assert_pending(&target).await?;
            assert!(reopened.existing_items([saved.id.clone()]).await.is_err());
            let original = connect_read_only(&path).await?;
            let row = original
                .query_one_raw(statement(
                    "SELECT payload FROM history_items WHERE item_id=?",
                    vec![saved.id.clone().into()],
                ))
                .await?
                .context("source tool item")?;
            let unchanged: ThreadItem =
                serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
            assert!(
                unchanged
                    .tool()
                    .is_some_and(|tool| tool.user_input().is_none()),
                "a failed migration must not publish a Q&A projection"
            );
            original.close().await?;
            assert_eq!(source_evidence(&path).await?, source);
        }
        Ok(())
    }

    /// 长问答正文走既有内容预算：问题与答案在字段域里，静态元数据不带正文，按身份能读回完整条目。
    #[tokio::test]
    async fn long_user_answer_stays_in_budgeted_fields_and_expands_by_identity() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "qa-long";
        let fixture = question_fixture();
        let long_answer = "preserved line\n".repeat(20_000);
        let mut item = question_tool_item("call-long", thread_id, 3);
        let record = interaction_record(
            "call-long",
            &fixture,
            2,
            pl_core::thread::interactions::InteractionState::Resolved(
                pl_core::thread::interactions::InteractionResponse {
                    payload: pl_core::context::OpaquePayload::new(
                        "pl.studio.user-answer",
                        1,
                        serde_json::to_string(&serde_json::json!({
                            "answers": {
                                "provider": {"answers": [long_answer]},
                                "token": {"answers": ["secret-deployment-token"]},
                            }
                        }))?,
                    )?,
                    context: vec![],
                },
            ),
        )?;
        let user_input =
            crate::studio::thread_projection::project_tool_user_input(thread_id, &record)?
                .context("Q&A")?;
        crate::studio::thread_projection::attach_tool_user_input(&mut item, user_input)?;

        let store = HistoryStore::open(&path, thread_id).await?;
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&item),
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

        // 静态元数据只带结构：问答正文不进 meta，因此不绕过内容预算。
        let complete = store
            .read_chat_item(&item.id)
            .await?
            .context("complete chat item")?;
        let meta = String::from_utf8_lossy(&complete.meta).to_string();
        assert!(!meta.contains("preserved line"));
        assert!(!meta.contains("secret-deployment-token"));
        let answer_field = crate::studio::runtime::chat_item::user_input_answer_field(0, 0);
        assert_eq!(
            complete.field(&answer_field).map(|block| block.text()),
            Some(long_answer.clone())
        );
        // 完整条目按身份回源可还原全部正文，条目身份不变。
        let restored = crate::studio::runtime::chat_item::canonical_item(&complete)?;
        assert_eq!(restored, item);

        // 分页预览只交付有界正文，并把省略量交给消费者按身份补齐。
        let session = pl_core::chat::Session::new(store.clone());
        let page = session
            .page(pl_core::chat::ChatPageRequest::latest().with_limit(10))
            .await?;
        let previewed = page.items.first().context("paged item")?;
        assert!(previewed.omitted_bytes() > 0);
        assert!(
            previewed
                .field(&answer_field)
                .map(|block| block.text())
                .is_none_or(|text| text.len() < long_answer.len())
        );
        Ok(())
    }
}
