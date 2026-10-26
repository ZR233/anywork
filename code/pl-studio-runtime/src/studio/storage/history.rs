//! Per-Thread durable timeline storage with keyset pagination.

use std::{
    path::{Path, PathBuf},
    time::Duration,
};

use crate::studio::runtime::chat_item::typed_item;
use crate::studio::storage::coordinator::history_close::{
    HistoryCloseOwner, HistoryConnectionRole, HistoryStateLease,
};
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatCursor, ChatError, ChatHistory, ChatHistoryPage, ChatItem};
use pl_protocol::thread::TimelineCursor;
use pl_protocol::{ThreadItem, ThreadItemKind, ThreadItemState, TimelineTurn};
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, SqliteTransactionMode,
    Statement, TransactionOptions, TransactionTrait, Value,
};

const HISTORY_SCHEMA_VERSION: i64 = 8;

/// Typed context for read failures. The original SQL/decoder cause remains in the anyhow chain;
/// adapters distinguish storage IO from an incompatible persisted fact without parsing messages.
#[derive(Debug, thiserror::Error)]
pub(crate) enum HistoryReadFailure {
    #[error("history storage read failed")]
    Storage,
    #[error("history read contains incompatible protocol data")]
    Protocol,
}

mod checkpoint;
mod schema;
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
/// Construction performs no filesystem or database IO. Cold reads open the *existing* database
/// read-only and never create the directory/database nor run schema mutations, while writes lazily
/// create and upgrade through the single writer connection. A deleted or damaged history store
/// therefore stays untouched by a page/turn/item query instead of being silently rebuilt, and the
/// per-Thread history writer stays the only owner that initializes or upgrades the schema.
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
pub(crate) struct HistoryStoreShare(std::sync::Weak<HistoryStoreState>);

impl std::fmt::Debug for HistoryStoreShare {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryStoreShare")
            .field("alive", &self.0.strong_count())
            .finish()
    }
}

struct HistoryStoreState {
    path: PathBuf,
    thread_id: String,
    /// This state's lifetime token, and the owner that closes its connections afterwards.
    ///
    /// The token keeps this state's existence observable, so "a legitimate holder still exists" is
    /// something the final close waits on. Its last `Drop` ends the lifetime and hands the still-open
    /// connections over inside that same boundary.
    lease: HistoryStateLease,
    /// The single writer connection, opened on the first write.
    ///
    /// Effect batches use one connection for short single-writer transactions. The Session owns
    /// ordinal allocation; this connection only persists the ordinals it supplies.
    writer: tokio::sync::OnceCell<HistoryConnection>,
    /// A read-only connection to an *existing* database, opened on the first cold read.
    reader: tokio::sync::OnceCell<HistoryConnection>,
    /// Serializes the first writer initialization against every cold read-only open.
    ///
    /// The writer's `connect(mode=rwc)` creates the file before `initialize` commits the schema and
    /// the identity row, so a read that observed the file inside that window would validate a
    /// half-initialized database and fail closed on a store that is merely still being created. The
    /// writer therefore holds the write side for its whole connect+initialize, while every cold open
    /// takes the read side first: a reader runs either before the file exists (an empty history) or
    /// after the database is fully initialized. Ordinary readers may reuse a published writer;
    /// strict canonical reads keep the same coordination but always use the read-only connection.
    init: tokio::sync::RwLock<()>,
    /// Test-only gate that parks the first writer after `connect(mode=rwc)` created the file and
    /// before `initialize` commits schema/identity. Production never installs a waiter.
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
}

impl Drop for HistoryStoreState {
    fn drop(&mut self) {
        // Only connections that were really opened are owed a close: opening one here would create
        // the very resource this drop exists to release. Both slots are taken so the state leaves
        // nothing behind, while the lease keeps each connection until its close truly succeeded.
        let mut connections = Vec::new();
        if let Some(writer) = self.writer.take() {
            connections.push((HistoryConnectionRole::Writer, writer.db));
        }
        if let Some(reader) = self.reader.take() {
            connections.push((HistoryConnectionRole::Reader, reader.db));
        }
        self.lease.finish(connections);
    }
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
    pub revision: u64,
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
    /// Terminal fact receipts produced by this effect.
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
    /// The first write creates the directory/database and initializes/upgrades the schema; reads
    /// only ever observe an existing database (or an explicitly empty history) and never mutate a
    /// byte, so an absent or damaged store cannot be resurrected by pagination or `read_item`.
    /// Test-only fixture: opens a handle whose close responsibility dies with the test.
    ///
    /// Production construction always supplies the coordinator's owner; this keeps single-file
    /// storage tests from having to build one without giving production an owner-less escape hatch.
    #[cfg(test)]
    pub(crate) async fn open(path: &Path, thread_id: &str) -> Result<Self> {
        Self::open_with(path, thread_id, HistoryCloseOwner::new()).await
    }

    /// Binds one Thread history database path and the owner that closes its connections.
    pub(crate) async fn open_with(
        path: &Path,
        thread_id: &str,
        close_owner: HistoryCloseOwner,
    ) -> Result<Self> {
        ensure!(
            !thread_id.is_empty(),
            "history Thread identity must not be empty"
        );
        let lease = close_owner.register_state(thread_id)?;
        Ok(Self {
            state: std::sync::Arc::new(HistoryStoreState {
                path: path.to_owned(),
                thread_id: thread_id.to_owned(),
                lease,
                writer: tokio::sync::OnceCell::new(),
                reader: tokio::sync::OnceCell::new(),
                init: tokio::sync::RwLock::new(()),
                #[cfg(test)]
                init_gate: tokio::sync::Mutex::new(None),
                #[cfg(test)]
                reader_before_init: tokio::sync::Mutex::new(None),
            }),
        })
    }

    /// A weak view of this handle's shared connection state, for the per-Thread writer registry.
    pub(crate) fn shared(&self) -> HistoryStoreShare {
        HistoryStoreShare(std::sync::Arc::downgrade(&self.state))
    }

    pub(crate) fn thread_id(&self) -> &str {
        &self.state.thread_id
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
        share.0.upgrade().map(|state| Self { state })
    }

    /// The connection cold reads use, or `None` when no history database exists yet.
    ///
    /// The writer connection, once opened, is authoritative for reads too, so a hot writer and an
    /// in-memory test store never observe two divergent databases. Otherwise the existing file is
    /// opened read-only and validated; a missing file is reported as an empty history and is never
    /// created here, so a cold read leaves an absent store absent. A read that races the first
    /// writer initialization waits behind it instead of validating the half-initialized database
    /// that `connect(mode=rwc)` just created.
    async fn reader(&self) -> Result<Option<&HistoryConnection>> {
        if let Some(writer) = self.state.writer.get() {
            return Ok(Some(writer));
        }
        // The first writer may have created the file with `connect(mode=rwc)` while its schema and
        // identity are still uncommitted. Take the read side of the initialization lock before
        // touching the file, so we either run before the file exists or after it is fully
        // initialized; never against a half-initialized database.
        #[cfg(test)]
        if let Some(tx) = self.state.reader_before_init.lock().await.take() {
            let _ = tx.send(());
        }
        let _initializing = self.state.init.read().await;
        // Re-check under the guard: the writer may have published its connection while we waited.
        if let Some(writer) = self.state.writer.get() {
            return Ok(Some(writer));
        }
        self.read_only_connection().await
    }

    /// Caller holds the initialization read guard. Never returns the writer, even when another
    /// observer keeps it alive; a missing file remains missing instead of reading an unlinked DB.
    async fn read_only_connection(&self) -> Result<Option<&HistoryConnection>> {
        if !tokio::fs::try_exists(&self.state.path).await? {
            return Ok(None);
        }
        let reader = self
            .state
            .reader
            .get_or_try_init(|| async {
                let db = connect_read_only(&self.state.path)
                    .await
                    .context(HistoryReadFailure::Storage)?;
                let (database_id, schema_version) =
                    validate_existing(&db, &self.state.thread_id).await?;
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

    /// The single writer connection, created and upgraded on first use.
    ///
    /// The whole first connect+initialize runs under the write side of the initialization lock, so a
    /// cold read that races it cannot observe the created-but-uninitialized database. The guard is
    /// released as soon as the connection is published, and every later call returns through the
    /// fast path above it.
    async fn writer(&self) -> Result<&HistoryConnection> {
        if let Some(writer) = self.state.writer.get() {
            return Ok(writer);
        }
        let _initializing = self.state.init.write().await;
        self.state
            .writer
            .get_or_try_init(|| async {
                schema::inspect_existing(&self.state.path, &self.state.thread_id).await?;
                let parent = self
                    .state
                    .path
                    .parent()
                    .context("history database path has no parent directory")?;
                tokio::fs::create_dir_all(parent).await?;
                let db = connect(&self.state.path).await?;
                #[cfg(test)]
                if let Some((entered, release)) = self.state.init_gate.lock().await.take() {
                    let _ = entered.send(());
                    let _ = release.await;
                }
                let database_id = match schema::initialize(&db, &self.state.thread_id).await {
                    Ok(id) => id,
                    Err(error) => {
                        if let Err(cleanup) = db.close().await {
                            return Err(
                                crate::studio::startup::cleanup_error(cleanup).context(error)
                            );
                        }
                        return Err(error);
                    }
                };
                Ok::<HistoryConnection, anyhow::Error>(HistoryConnection {
                    db,
                    database_id,
                    schema_version: HISTORY_SCHEMA_VERSION,
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
        self.commit_inner(write_seq, commit, None).await
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
            .await
            .context(HistoryReadFailure::Storage)?;
        let Some(row) = row else {
            return Ok(None);
        };
        (|| -> Result<_> {
            Ok(Some(FactReceipt {
                revision: u64::try_from(row.try_get::<i64>("", "revision")?)
                    .context("durable fact receipt has an invalid revision")?,
                kind: row.try_get("", "kind")?,
                payload: row.try_get("", "payload")?,
            }))
        })()
        .context(HistoryReadFailure::Protocol)
    }

    /// Reads exactly the original fact revision. Never substitutes the latest saved decision.
    pub(crate) async fn fact_receipt_at(
        &self,
        item_id: &str,
        revision: u64,
    ) -> Result<Option<FactReceipt>> {
        let revision = i64::try_from(revision)
            .context("fact revision exceeds SQLite range")
            .context(HistoryReadFailure::Protocol)?;
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT revision,kind,payload FROM history_fact_receipts WHERE item_id=? AND revision=?",
                vec![item_id.to_owned().into(), revision.into()],
            ))
            .await.context(HistoryReadFailure::Storage)?;
        row.map(|row| {
            Ok::<_, anyhow::Error>(FactReceipt {
                revision: u64::try_from(row.try_get::<i64>("", "revision")?)
                    .context("durable fact receipt has an invalid revision")?,
                kind: row.try_get("", "kind")?,
                payload: row.try_get("", "payload")?,
            })
        })
        .transpose()
        .context(HistoryReadFailure::Protocol)
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

    /// Reads an existing durable input identity without preparing or migrating storage.
    pub(crate) async fn input_identity(
        &self,
        input_id: &str,
    ) -> Result<Option<InputIdentityReceipt>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        // Supported cold schemas are 2..=8. request_digest is an independent additive column,
        // installed by writer initialization rather than by a dedicated schema-version step.
        // Inspect only this known table's columns: version alone cannot prove column presence,
        // and a pure evidence read must not call writer()/prepare_activation() to add it.
        let columns = connection
            .db
            .query_all_raw(statement(
                "PRAGMA table_info(history_input_identities)",
                vec![],
            ))
            .await
            .context(HistoryReadFailure::Storage)?;
        let columns = columns
            .iter()
            .map(|row| {
                row.try_get::<String>("", "name")
                    .context(HistoryReadFailure::Protocol)
            })
            .collect::<Result<std::collections::BTreeSet<_>>>()?;
        ensure!(
            columns.contains("item_id") && columns.contains("payload"),
            HistoryReadFailure::Protocol
        );
        let has_request_digest = columns.contains("request_digest");
        let sql = if has_request_digest {
            "SELECT payload,request_digest FROM history_input_identities WHERE item_id=?"
        } else {
            "SELECT payload FROM history_input_identities WHERE item_id=?"
        };
        let row = connection
            .db
            .query_one_raw(statement(sql, vec![input_id.into()]))
            .await
            .context(HistoryReadFailure::Storage)?;
        (|| -> Result<_> {
            match row {
                Some(row) => Ok(Some(InputIdentityReceipt {
                    entry: serde_json::from_str(&row.try_get::<String>("", "payload")?)?,
                    request_digest: if has_request_digest {
                        row.try_get::<Option<String>>("", "request_digest")?
                    } else {
                        None
                    },
                })),
                None => Ok(None),
            }
        })()
        .context(HistoryReadFailure::Protocol)
    }

    /// Upgrades existing history before an active owner seeds its canonical projection.
    pub(crate) async fn prepare_activation(&self) -> Result<()> {
        // Envelope migrations evolve independently from the table format. Every existing
        // activation lets the official migrator decide which named steps remain pending.
        if tokio::fs::try_exists(&self.state.path).await? {
            self.writer().await?;
        }
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
        // A cold v2 reader may page history without touching the database. An active projection
        // needs the new proof column, so its owning writer upgrades that existing database first.
        let connection = if connection.schema_version < HISTORY_SCHEMA_VERSION {
            self.writer().await?
        } else {
            connection
        };
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
    /// as unverifiable instead of re-delivering. A missing store or unknown identity returns `None`,
    /// while a damaged store fails so the caller can fail closed rather than admit a duplicate.
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
        // 缺少索引表只意味着这条身份“未知”，不是存储故障：升级前写入的库还没有这张表，写者会在
        // 下一次提交时补建它，冷读既不能失败也不能替它建表。是否真有这条历史由上层的旧历史探测
        // 决定，从而让索引之前的消息 fail-closed 而不是被当成新消息重投。缺表之外的一切错误
        // （IO、损坏库、schema 不可读）都必须原样上抛，绝不伪装成“没有这条身份”。
        if !message_identity_index_exists(connection).await? {
            return Ok(None);
        }
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
        .context("history database has no readable identity table")
        .context(HistoryReadFailure::Storage)?;
    (|| -> Result<_> {
        let row = row.context("history database identity row is missing")?;
        let version: i64 = row.try_get("", "schema_version")?;
        ensure!(
            (2..=HISTORY_SCHEMA_VERSION).contains(&version),
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
        Ok((database_id, version))
    })()
    .context(HistoryReadFailure::Protocol)
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

/// Creates or validates the schema and returns the owning database identity.
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

/// Reports whether one history database already carries the durable message identity index.
///
/// A database written before that index existed has no such table until the writer creates it on its
/// next commit, so a cold read must report "this identity is unknown" instead of failing (and must
/// never create the table itself). Reading the catalog is a plain read; any failure of it is a real
/// storage failure the caller must surface rather than swallow.
async fn message_identity_index_exists(connection: &HistoryConnection) -> Result<bool> {
    Ok(connection
        .db
        .query_one_raw(statement(
            "SELECT name FROM sqlite_master
             WHERE type='table' AND name='history_message_identities'",
            vec![],
        ))
        .await?
        .is_some())
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

/// Writes one terminal fact receipt in the same transaction as the effect that produced it.
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
        ThreadItemKind::ContextCompaction => "contextCompaction",
    }
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;
    use crate::studio::thread_projection::order;

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
        drop(db);
        drop(store);

        let migrated = HistoryStore::open(&path, "legacy-plan").await?;
        assert_eq!(migrated.watermark().await?, 1);
        let old = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        let version = old
            .query_one_raw(statement(
                "SELECT schema_version FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .context("missing legacy metadata")?
            .try_get::<i64>("", "schema_version")?;
        assert_eq!(version, 2);
        drop(old);
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
        Ok(())
    }

    #[tokio::test]
    async fn activation_migrates_only_proven_unconsumed_input_bindings() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "migration").await?;
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
        let migrated = HistoryStore::open(&path, "migration").await?;
        // Ordinary cold reads retain their read-only contract.
        assert_eq!(
            migrated.existing_items(["pending".into()]).await?["pending"].turn_id,
            "turn-pending"
        );
        migrated.prepare_activation().await?;
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
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, "local-orders").await?;
        let session = pl_core::chat::Session::new(store.clone());
        assert_eq!(session.reserve_order("input-1").await?, 1);
        assert_eq!(session.reserve_order("input-1").await?, 1);
        assert_eq!(session.reserve_order("input-2").await?, 2);
        assert!(!tokio::fs::try_exists(&path).await?);

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
        assert!(store.fact_receipt_at("second", 2).await?.is_none());
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
        save_receipt(&store, 3, "second").await?;
        let exact = store
            .fact_receipt_at("second", 2)
            .await?
            .context("missing exact receipt")?;
        assert_eq!(
            exact.revision, 2,
            "a newer saved fact must not replace the requested revision"
        );
        assert_eq!(exact.kind, "interaction");
        assert_eq!(
            store
                .latest_fact_receipt("second")
                .await?
                .context("missing latest receipt")?
                .revision,
            3
        );
        assert!(store.fact_receipt_at("second", 4).await?.is_none());
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
        store
            .commit_effect(
                1,
                EffectCommit {
                    items: &[item.clone()],
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
            .import_checkpoint(
                &ThreadCheckpoint::capture("context-migration".into(), 1, state.clone()),
                &[],
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
        db.execute_unprepared("DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=5; CREATE TRIGGER reject_context_migration BEFORE UPDATE ON current_context BEGIN SELECT RAISE(ABORT,'injected context migration failure'); END;").await?;
        drop(store);
        let failed = HistoryStore::open(&path, "context-migration").await?;
        assert!(failed.prepare_activation().await.is_err());
        let reader = failed.reader().await?.context("reader")?;
        assert_eq!(reader.schema_version, 5);
        let row = reader
            .db
            .query_one_raw(statement(
                "SELECT payload FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?
            .context("checkpoint")?;
        assert_eq!(row.try_get::<String>("", "payload")?, encoded);
        let recovery = sea_orm::Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::ReadWrite,
                |options| options,
            )
            .await?,
        )
        .await?;
        recovery
            .execute_unprepared("DROP TRIGGER reject_context_migration")
            .await?;
        recovery.close().await?;
        drop(failed);
        let restored = HistoryStore::open(&path, "context-migration").await?;
        restored.prepare_activation().await?;
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
        assert_eq!(checkpoint.state.extensions, state.extensions);
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
        let path = directory.path().join("history.sqlite");
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
        history.import_checkpoint(&checkpoint, &purposes).await?;
        history.import_checkpoint(&checkpoint, &purposes).await?;
        drop(history);
        let history = HistoryStore::open(&path, "costs").await?;
        history.prepare_activation().await?;
        let restored = history.checkpoint().await?.unwrap();
        assert_eq!(restored.state.extensions, frozen_billing);
        let batch = pl_core::thread::ThreadEffectBatch {
            committed_at: 42,
            extensions: restored
                .state
                .extensions
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
        assert_eq!(facts.len(), 4);
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
        for id in ["no-charge", "compaction-no-charge"] {
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
        Ok(())
    }

    #[tokio::test]
    async fn toml_checkpoint_import_cleans_only_replaced_files_and_reopens() -> Result<()> {
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
        let history =
            HistoryStore::open(&directory.path().join("history.sqlite"), "import").await?;
        assert!(
            state.prepare_recovery(&history).await.is_err(),
            "missing migration body must preserve source"
        );
        assert!(tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        for body in bodies {
            let hex = body
                .entry
                .reference
                .digest()
                .strip_prefix("sha256:")
                .context("digest")?;
            let directory = directory.path().join("blobs/checkpoint").join(&hex[..2]);
            tokio::fs::create_dir_all(&directory).await?;
            tokio::fs::write(directory.join(hex), &body.bytes).await?;
        }
        legacy["schemaVersion"] = serde_json::json!(999);
        let future = toml::to_string(&legacy)?;
        tokio::fs::write(directory.path().join("state.toml"), &future).await?;
        assert!(
            state.prepare_recovery(&history).await.is_err(),
            "a valid backup must not hide an unknown primary version"
        );
        assert_eq!(
            tokio::fs::read_to_string(directory.path().join("state.toml")).await?,
            future
        );
        tokio::fs::write(directory.path().join("state.toml"), &original).await?;
        history.writer().await?.db.execute_unprepared("CREATE TRIGGER reject_import BEFORE INSERT ON session_checkpoint BEGIN SELECT RAISE(ABORT,'migration interrupted'); END;").await?;
        assert!(state.prepare_recovery(&history).await.is_err());
        assert!(history.checkpoint().await?.is_none());
        assert!(tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        history
            .writer()
            .await?
            .db
            .execute_unprepared("DROP TRIGGER reject_import")
            .await?;
        history
            .writer()
            .await?
            .db
            .execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
            .await?;
        assert!(
            state.prepare_recovery(&history).await.is_err(),
            "mismatched history fence must preserve source"
        );
        assert!(tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        history
            .writer()
            .await?
            .db
            .execute_unprepared("UPDATE history_meta SET applied_write_seq=0")
            .await?;
        let imported = state
            .prepare_recovery(&history)
            .await?
            .context("imported checkpoint")?;
        assert_eq!(imported.state.context, checkpoint.state.context);
        assert!(imported.state.attempt_ids.contains_key("old-attempt"));
        assert_eq!(imported.state_revision, checkpoint.state_revision);
        assert!(!tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        assert!(!tokio::fs::try_exists(directory.path().join("state.prev.toml")).await?);
        assert!(!tokio::fs::try_exists(directory.path().join("blobs/checkpoint")).await?);
        assert_eq!(
            tokio::fs::read(directory.path().join("blobs/attachment")).await?,
            b"keep"
        );
        assert_eq!(
            state
                .prepare_recovery(&history)
                .await?
                .context("reopened")?
                .state_revision,
            imported.state_revision
        );
        Ok(())
    }

    /// 冷加载的 fail-closed 判据：没有 checkpoint 却已有写入水位，且没有任何 legacy 来源时，
    /// 判据必须明确失败，并完整保留现场（不补写 checkpoint、不清零水位、不生成 legacy 文件）。
    ///
    /// 故障形态由测试私有的 writer 注入：正常提交会在同一事务里写 checkpoint，因此"水位已前进、
    /// checkpoint 行缺失"只能来自损坏或半初始化的库。计数只用同一 writer 的真实读查询，不复制
    /// 被测判据本身。
    #[tokio::test]
    async fn cold_load_without_a_checkpoint_fails_closed_and_preserves_the_store() -> Result<()> {
        async fn rows(history: &HistoryStore, sql: &'static str) -> Result<i64> {
            let row = history
                .writer()
                .await?
                .db
                .query_one_raw(statement(sql, vec![]))
                .await?
                .context("count row")?;
            Ok(row.try_get("", "rows")?)
        }

        let directory = tempfile::tempdir()?;
        let history =
            HistoryStore::open(&directory.path().join("history.sqlite"), "unordered").await?;
        history
            .writer()
            .await?
            .db
            .execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
            .await?;
        let checkpoints = "SELECT COUNT(*) AS rows FROM session_checkpoint";
        let turns = "SELECT COUNT(*) AS rows FROM history_turns";
        // 前置现场：当前 schema、没有 checkpoint、没有已提交 Turn、也没有 legacy 文件。
        assert_eq!(rows(&history, checkpoints).await?, 0);
        assert_eq!(rows(&history, turns).await?, 0);
        assert!(!tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        assert!(!tokio::fs::try_exists(directory.path().join("state.prev.toml")).await?);

        let state = super::super::state::StateStore::new(directory.path().to_owned(), "unordered");
        let error = state
            .load_read_only(&history)
            .await
            .expect_err("a missing checkpoint with a committed watermark must fail closed");
        assert!(
            error
                .to_string()
                .contains("history exists without a recovery checkpoint"),
            "unexpected failure: {error}"
        );

        // 现场保持：checkpoint 仍缺失（且没有被补写）、水位没有被清零或改写、仍没有 legacy 文件。
        assert_eq!(rows(&history, checkpoints).await?, 0);
        assert_eq!(rows(&history, turns).await?, 0);
        assert!(history.checkpoint().await?.is_none());
        assert_eq!(history.watermark().await?, 1);
        assert!(!tokio::fs::try_exists(directory.path().join("state.toml")).await?);
        assert!(!tokio::fs::try_exists(directory.path().join("state.prev.toml")).await?);
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

        let migrated = HistoryStore::open(&path, thread_id).await?;
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
        let reopened = HistoryStore::open(&path, thread_id).await?;
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

        let migrated = HistoryStore::open(&path, thread_id).await?;
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

        let migrated = HistoryStore::open(&path, thread_id).await?;
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

        let migrated = HistoryStore::open(&path, thread_id).await?;
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
        let reopened = HistoryStore::open(&path, thread_id).await?;
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
                "DROP TABLE IF EXISTS seaql_migrations; UPDATE history_meta SET schema_version=7; \
                 CREATE TRIGGER reject_plan_history BEFORE UPDATE ON history_items \
                 BEGIN SELECT RAISE(ABORT,'injected plan history failure'); END;",
            )
            .await?;
        drop(store);

        let failed = HistoryStore::open(&path, thread_id).await?;
        assert!(failed.prepare_activation().await.is_err());
        let reader = failed.reader().await?.context("reader")?;
        assert_eq!(reader.schema_version, 7);
        let row = reader
            .db
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
        drop(failed);

        let recovery = sea_orm::Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::ReadWrite,
                |options| options,
            )
            .await?,
        )
        .await?;
        recovery
            .execute_unprepared("DROP TRIGGER reject_plan_history")
            .await?;
        recovery.close().await?;

        let restored = HistoryStore::open(&path, thread_id).await?;
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

            let reopened = HistoryStore::open(&path, &thread_id).await?;
            let failure = reopened
                .prepare_activation()
                .await
                .expect_err("a corrupt Q&A fact must fail the migration");
            let diagnostic = failure.to_string();
            assert!(
                !diagnostic.contains("secret-deployment-token"),
                "the diagnostic must not leak a private answer: {diagnostic}"
            );
            // 显式失败：条目仍是迁移前的样子，没有被伪造成已回答。
            let unchanged = reopened.existing_items([saved.id.clone()]).await?;
            assert!(
                unchanged
                    .get(&saved.id)
                    .and_then(|item| item.tool())
                    .is_some_and(|tool| tool.user_input().is_none()),
                "a failed migration must not publish a Q&A projection"
            );
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

    /// A borrowed pool really blocks the close; both opened pools then close on their own duty.
    #[tokio::test]
    async fn history_pools_close_only_when_their_connection_is_free() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let owner = HistoryCloseOwner::new();
        // Two really opened pools over one file: the writer connection of one state and the read-only
        // connection of another. Both name the Thread the database itself was initialized for.
        let writer_state = HistoryStore::open_with(&path, "close-pools", owner.clone()).await?;
        writer_state.commit(1, &[], &[]).await?;
        let reader_state = HistoryStore::open_with(&path, "close-pools", owner.clone()).await?;
        assert_eq!(reader_state.watermark().await?, 1);
        // Hold the writer pool's only permit, so its close really has to wait for it.
        let transaction = {
            let connection = writer_state.writer().await?;
            begin_write(&connection.db).await?
        };
        drop(writer_state);
        drop(reader_state);
        assert_eq!(owner.outstanding(), 2, "both opened pools are owed a close");
        for _ in 0..64 {
            if owner.completed() > 0 {
                break;
}
            tokio::task::yield_now().await;
        }
        assert_eq!(owner.completed(), 1, "only the pool with a free connection closed");
        assert_eq!(owner.outstanding(), 1, "the borrowed pool is still owed its close");
        // Releasing the permit lets the very same duty (no second pool) close.
        transaction.commit().await?;
        owner.settle().await?;
        assert_eq!(owner.outstanding(), 0);
        assert_eq!(owner.completed(), 2, "both real pools are closed");
        // Closing connections leaves the database itself intact and readable.
        let reopened = HistoryStore::open_with(&path, "close-pools", owner.clone()).await?;
        assert_eq!(reopened.watermark().await?, 1);
        drop(reopened);
        Ok(())
    }

    /// A holder that outlived the seal keeps the close pending until it is really released.
    #[tokio::test]
    async fn a_holder_that_outlived_the_seal_keeps_the_close_pending() -> Result<()> {
        use std::future::Future as _;

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let owner = HistoryCloseOwner::new();
        let history = HistoryStore::open_with(&path, "sealed", owner.clone()).await?;
        history.commit(1, &[], &[]).await?;
        owner.seal();
        // Poll the real wait once: it must be pending while a holder is alive, and dropping it must
        // leave the state responsibility exactly where it was.
        let mut waiting = std::pin::pin!(owner.settle_when_no_state_is_left());
        std::future::poll_fn(|cx| {
        assert!(
                waiting.as_mut().poll(cx).is_pending(),
                "a live holder must keep the close pending"
        );
            std::task::Poll::Ready(())
        })
        .await;
        drop(waiting);
        assert_eq!(
            owner.live_states(),
            1,
            "cancelling the wait keeps the state responsibility"
        );
        drop(history);
        // Releasing the holder lets a later wait join the same responsibility to its real end.
        assert_eq!(owner.live_states(), 0);
        owner.settle_when_no_state_is_left().await?;
        assert_eq!(
            owner.outstanding(),
            0,
            "the connection is still really closed, never silently dropped"
        );
        assert_eq!(owner.completed(), 1);
        // The database itself stays readable after its connection really closed.
        // The sealed owner refuses new states, so this check uses a fresh unsealed owner over the
        // same Thread identity and path, then closes it too.
        let reopened_owner = HistoryCloseOwner::new();
        let reopened =
            HistoryStore::open_with(&path, "sealed", reopened_owner.clone()).await?;
        assert_eq!(reopened.watermark().await?, 1);
        drop(reopened);
        reopened_owner.seal();
        reopened_owner.settle_when_no_state_is_left().await?;
        Ok(())
    }

    /// A controlled close failure keeps the same connection for the next attempt, and the late
    /// observer of the failed attempt can neither drop nor overwrite the newer one.
    #[tokio::test]
    async fn a_failed_close_is_retried_on_the_same_connection() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let owner = HistoryCloseOwner::new();
        let history = HistoryStore::open_with(&path, "retry-close", owner.clone()).await?;
        history.commit(1, &[], &[]).await?;
        // The first attempt fails with a typed database error and its observer is delayed.
        owner.arm_close_failure();
        let (gate, wait) = tokio::sync::oneshot::channel::<()>();
        owner.arm_observer_delay(wait);
        drop(history);
        let first = owner.settle().await;
        assert!(first.is_err(), "the controlled close failure must be reported");
        assert_eq!(
            owner.outstanding(),
            1,
            "the original connection is kept for another attempt"
        );
        // The next entry re-arms it and closes the very same connection for real.
        owner.settle().await?;
        assert_eq!(owner.outstanding(), 0);
        assert_eq!(owner.completed(), 1);
        // The late observer of attempt 1 arrives after attempt 2 already succeeded: it must change
        // nothing — no new task, no failure, no duplicate close.
        gate.send(()).expect("the observer gate is still open");
        for _ in 0..64 {
            tokio::task::yield_now().await;
        }
        assert_eq!(owner.outstanding(), 0);
        assert_eq!(owner.completed(), 1);
        // Same Thread identity and path; this owner is not sealed, and it is closed before returning.
        let reopened_owner = HistoryCloseOwner::new();
        let reopened = HistoryStore::open_with(&path, "retry-close", reopened_owner.clone()).await?;
        assert_eq!(reopened.watermark().await?, 1);
        drop(reopened);
        reopened_owner.seal();
        reopened_owner.settle_when_no_state_is_left().await?;
        Ok(())
    }

    /// A close that never started is a real responsibility the next entry still settles.
    #[tokio::test]
    async fn an_unstarted_close_is_retried_on_the_same_connection() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let owner = HistoryCloseOwner::new();
        let history = HistoryStore::open_with(&path, "no-runtime", owner.clone()).await?;
        history.commit(1, &[], &[]).await?;
        // Released on a plain OS thread: no runtime can close it there.
        std::thread::spawn(move || drop(history))
            .join()
            .expect("the holder thread must end");
        assert_eq!(owner.outstanding(), 1, "an unstarted close is still owed");
        owner.settle().await?;
        assert_eq!(owner.outstanding(), 0);
        assert_eq!(owner.completed(), 1);
        let reopened_owner = HistoryCloseOwner::new();
        let reopened =
            HistoryStore::open_with(&path, "no-runtime", reopened_owner.clone()).await?;
        assert_eq!(reopened.watermark().await?, 1);
        drop(reopened);
        reopened_owner.seal();
        reopened_owner.settle_when_no_state_is_left().await?;
        Ok(())
}
}
