use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::{SendContent, SendIdentity, SendSource};
use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
use crate::studio::unix_seconds;
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, QueryResult, Statement,
    TransactionTrait, Value,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::Duration;

pub(super) mod audience;
pub(super) mod card;
mod legacy_schema;
pub(in crate::bots) mod publication;
pub(super) mod reply;
mod schema;
pub(in crate::bots) mod target;

const BOT_STATE_SCHEMA_VERSION: i64 = 10;

#[derive(Clone, Copy)]
enum LedgerSource {
    MainCard6,
    TaskFile6,
    TaskFile7,
    Current8,
}
const PAIRING_LIMIT: i64 = 32;
const PAIRING_TTL_SECONDS: i64 = 7 * 24 * 60 * 60;
const INBOUND_CLAIM_TTL_SECONDS: i64 = 60;
const INBOUND_RETRY_BASE_SECONDS: i64 = 5;
const INBOUND_RETRY_MAX_SECONDS: i64 = 300;
const INBOUND_RETRY_BUDGET: i64 = 8;
/// 首输入就绪等待的独立上限：与失败退避预算完全分开。就绪等待不计数、不消耗失败
/// 预算，只有这个期限到期才会以“准备未完成”收束为需处理。
const INBOUND_READINESS_WAIT_BUDGET_SECONDS: i64 = 900;
/// 就绪等待的重派节奏：只推进下一次尝试时间，不计入失败次数。
const INBOUND_READINESS_POLL_SECONDS: i64 = 5;
const INBOUND_PENDING_LIMIT: i64 = 64;
const INBOUND_PENDING_BYTES: i64 = 512 * 1024;

#[derive(Clone)]
pub struct BotStateStore {
    path: PathBuf,
    writer: Arc<tokio::sync::OnceCell<DatabaseConnection>>,
}

/// Only serializes first connect/schema work for the same physical parent + database filename.
/// Entries are weak and pruned; this is neither a task owner nor a persistent reference ledger.
type InitializationLocks = BTreeMap<PathBuf, Weak<tokio::sync::Mutex<()>>>;
static INITIALIZATION_LOCKS: OnceLock<Mutex<InitializationLocks>> = OnceLock::new();

enum DatabaseOrigin {
    Created,
    Existing,
}

/// One strict keyset page. The producer gate owns the accumulated candidate set/cursor;
/// neither this projection nor its progress is a second persistent reference index.
pub(super) struct SendResourceReferences {
    pub(super) referenced: BTreeSet<String>,
    pub(super) continuation: Option<SendResourceReferenceCursor>,
    pub(super) query_work: usize,
}

/// Only progress through the existing table, never a copy of reference facts. The producer gate
/// excludes new file claims; later rows can only be resource-free posts and need not extend it.
#[derive(Clone, Copy)]
pub(super) struct SendResourceReferenceCursor {
    after: Option<i64>,
    through: i64,
}

#[derive(Debug, Clone)]
pub enum ThreadBindingClaim {
    Bound { thread_id: String },
    Creating { creation_id: String },
    NeedsAttention { diagnostic: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SendRecordStatus {
    Succeeded,
    Partial,
    Rejected,
    Unknown,
}

impl SendRecordStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Succeeded => "succeeded",
            Self::Partial => "partial",
            Self::Rejected => "rejected",
            Self::Unknown => "unknown",
        }
    }

    /// 显式接受 `unknown`；其它未知串属于坏持久记录，不能当合法 Unknown 走重放。
    fn parse(value: &str) -> Result<Self, FeishuError> {
        match value {
            "succeeded" => Ok(Self::Succeeded),
            "partial" => Ok(Self::Partial),
            "rejected" => Ok(Self::Rejected),
            "unknown" => Ok(Self::Unknown),
            _ => Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "send record state is unreadable; local recovery required",
                false,
                None,
            )),
        }
    }
}

#[derive(Debug, Clone)]
pub struct SendRecord {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub content_hash: String,
    pub status: SendRecordStatus,
    pub platform_message_ids: Vec<String>,
    pub segments: Vec<SendSegmentFact>,
    pub facts_complete: bool,
    pub identity: SendIdentity,
    pub source: Option<SendSource>,
}

/// 自动前端文件的宿主证明；不接受工具参数，也不伪造原入站 SendSource。
#[derive(Debug, Clone)]
pub(in crate::bots) struct PublicationFilePermit {
    pub token: publication::DeliveryClaimToken,
    pub entity: publication::DeliveryEntityKey,
    pub expected_ledger_version: u64,
    pub artifact: publication::SavedArtifact,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::bots) enum PublicationFileStage {
    Upload,
    Message,
}

/// 原网络阶段的真实结果增量；writer 合并到当前行，不用旧整行快照覆盖后继阶段。
#[derive(Debug, Clone)]
pub(in crate::bots) enum PublicationFileProgress {
    Uploaded {
        file_key: String,
    },
    Sent {
        message_id: String,
    },
    Rejected {
        stage: PublicationFileStage,
        diagnostic: pl_protocol::studio::BotDiagnostic,
    },
    Unknown {
        stage: PublicationFileStage,
        diagnostic: Option<pl_protocol::studio::BotDiagnostic>,
    },
    /// 仅由尚未轮询 HTTP 的原 owner 提交，不能将已开始请求的取消写成 NotStarted。
    NotStarted {
        stage: PublicationFileStage,
        reason: pl_protocol::studio::BotSendStopReason,
        diagnostic: String,
    },
}

/// 一次已经持久登记的文件阶段。只能由 writer 构造，不能将恢复的旧 InFlight
/// 冒充为本 owner 尚未启动的阶段；发送 owner 保有它直至结果可靠保存。
#[derive(Debug)]
pub(in crate::bots) struct PublicationFileAttempt {
    permit: PublicationFilePermit,
    record: SendRecord,
    stage: PublicationFileStage,
    request_started: bool,
    stopped_before_start: bool,
}

impl PublicationFileAttempt {
    pub(in crate::bots) fn record(&self) -> &SendRecord {
        &self.record
    }

    /// 在原 admission 边界第一次轮询 HTTP 前标记；之后取消只能记录 Unknown。
    pub(in crate::bots) fn mark_request_started(&mut self) {
        self.request_started = true;
    }
}

enum SendClaimFence<'a> {
    InboundReply(&'a reply::InboundReply),
    Publication(&'a PublicationFilePermit),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SendSegmentFact {
    pub index: u32,
    pub uuid: String,
    pub status: SendRecordStatus,
    pub platform_message_id: Option<String>,
    pub diagnostic: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<SendContent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upload: Option<UploadFact>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_stage: Option<MessageStage>,
    /// Only newly admitted typed notices carry an attempt fence; old sends gain no authority.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notice_attempt: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform_diagnostic: Option<pl_protocol::studio::BotDiagnostic>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stop_reason: Option<pl_protocol::studio::BotSendStopReason>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind"
)]
pub enum UploadFact {
    NotStarted,
    /// Persisted before the non-idempotent POST. A replay treats this as unknown, never resends.
    InFlight,
    Accepted {
        file_key: String,
    },
    Rejected,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MessageStage {
    NotStarted,
    InFlight,
    Accepted,
    Rejected,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrozenInbound {
    pub bot_id: String,
    pub message_id: String,
    pub chat_id: String,
    pub content_hash: String,
    pub text: String,
    pub attachments: Vec<super::inbound::InboundAttachment>,
    pub open_id: String,
    pub chat_kind: String,
    pub app_id: String,
    pub project_id: String,
    pub creation_id: String,
    pub binding_revision: u64,
    /// 当前 watch 的 canonical 输入身份；空串表示原 bot 输入。
    pub watch_input: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InboundAdmit {
    /// 首次受理：按值接回的输入就是本次登记的权威材料，不额外复制正文与身份。
    Fresh(FrozenInbound),
    DuplicateCompleted,
    DuplicateResume(FrozenInbound),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InboundClaim {
    Claimed,
    Busy,
    Completed,
    Missing,
    NeedsAttention,
    /// 退避未到期，本轮不派发。
    NotDue,
}

/// 认领租约核对结果：0 行条件更新不得被解释为成功续约。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ClaimLease {
    Renewed,
    LostClaim,
}

/// 状态收束核对结果：失去认领的旧持有者不能覆盖后继状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MarkOutcome {
    Applied,
    LostClaim,
}

/// One inbound work identity: the composite key column plus the frozen row identity that
/// every finish/claim decision must cross-check.
#[derive(Debug, Clone)]
struct WorkKeys<'a> {
    identity: String,
    bot_id: &'a str,
    chat_id: &'a str,
    message_id: &'a str,
}

/// The fenced facts of the claimed inbound work row, decoded once per finish.
struct ClaimedWork {
    attempt_count: i64,
    content_hash: String,
    project_id: String,
    creation_id: String,
    binding_revision: u64,
}

/// 入站工作收束语义；由账本在同一认领条件下原子落盘。
#[derive(Debug, Clone)]
pub(crate) enum WorkFinish<'a> {
    Completed,
    /// Runtime 停止观察：释放为 pending 且立即可恢复，不计失败预算。
    Interrupted,
    NeedsAttention(&'a str),
    /// 可证的原创建身份冲突：同事务收束该入站及仍匹配的 creating 路由。
    CreationConflict(&'a str),
    /// 真实 retryable 失败：计数退避；预算耗尽自动转 needs_attention。
    Retryable(&'a str),
    /// 等待外部就绪（首输入准备）：只推进下一次尝试时间，不计数、不耗失败预算；
    /// 独立等待期限到期后才以“准备未完成”（而非失败次数）收束为 needs_attention。
    Deferred(&'a str),
}

/// 同一次输入所有者保有附件时的提交退避；耗尽仍由原 finisher 原子收束。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::bots) enum InboundRetryWait {
    Until { retry_at: i64 },
    BudgetExhausted,
    LostClaim,
}

#[derive(Debug, Clone)]
pub struct ObservedDirect {
    pub chat_id: String,
    pub name: Option<String>,
    pub last_observed_at: i64,
}

#[derive(Debug, Clone)]
pub struct PairingRow {
    pub request_id: String,
    pub open_id: String,
    pub display_name: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone)]
pub struct BindingProjection {
    pub chat_id: String,
    pub project_id: String,
    /// 当前行记录的创建身份；缺失行为空串。用于证明部分现场是否属于本次请求。
    pub creation_id: String,
    pub thread_id: Option<String>,
    pub revision: u64,
    pub status: String,
    pub diagnostic: Option<String>,
}

/// Exact route observed before an asynchronous Thread lookup. A late diagnostic may affect only
/// this binding, not a successor created while the lookup was awaiting its result.
pub(in crate::bots) struct BoundThreadExpectation {
    pub chat_id: String,
    pub thread_id: String,
    pub creation_id: String,
    pub project_id: String,
    pub revision: u64,
}

#[derive(Debug, Clone)]
pub struct IdentityOccupancy {
    pub has_thread_or_inbound: bool,
    pub has_app_identity: bool,
}

#[derive(Debug, Clone)]
pub struct BindingOperation {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub content_hash: String,
    pub expected_revision: u64,
    pub creation_id: String,
    pub thread_id: Option<String>,
    pub(in crate::bots) target: target::TargetProof,
}

/// The already-verified first authorization a caller wants committed together with the
/// binding. Storage owns the generation/revision/delivery counters so the row can never
/// disagree with the route it was written beside.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct FirstStart {
    pub bot_id: String,
    pub app_id: String,
    pub operation_id: String,
}

impl BotStateStore {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            writer: Arc::new(tokio::sync::OnceCell::new()),
        }
    }

    async fn db(&self) -> Result<&DatabaseConnection, FeishuError> {
        self.writer
            .get_or_try_init(|| async { open_bot_state(&self.path).await })
            .await
    }

    pub async fn identity_occupancy(&self) -> Result<IdentityOccupancy, FeishuError> {
        let db = self.db().await?;
        // 保守派生：任何持久入站工作也同样视为身份占用。正常受理在同一事务内写
        // identity 与 work，且先提交会话绑定，因此不影响既有数据；异常遗留的 work
        // 即使缺少 identity/binding 行，也不能让关联项目变成可变。
        let thread_or_inbound = count_rows(db, "SELECT COUNT(*) AS n FROM thread_bindings").await?
            + count_rows(db, "SELECT COUNT(*) AS n FROM inbound_identities").await?
            + count_rows(db, "SELECT COUNT(*) AS n FROM inbound_work").await?;
        let app_identity = thread_or_inbound
            + count_rows(db, "SELECT COUNT(*) AS n FROM observed_directs").await?
            + count_rows(db, "SELECT COUNT(*) AS n FROM pairing_requests").await?
            + count_rows(db, "SELECT COUNT(*) AS n FROM send_operations").await?;
        Ok(IdentityOccupancy {
            has_thread_or_inbound: thread_or_inbound > 0,
            has_app_identity: app_identity > 0,
        })
    }

    pub async fn admit_inbound(&self, inbound: FrozenInbound) -> Result<InboundAdmit, FeishuError> {
        let identity = inbound_identity(&inbound.bot_id, &inbound.chat_id, &inbound.message_id);
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT identity, bot_id, message_id, chat_id, content_hash FROM inbound_identities WHERE identity=?",
                vec![identity.clone().into()],
            ))
            .await
            .map_err(storage)?;
        if let Some(row) = existing {
            let work = tx
                .query_one_raw(statement(
                    "SELECT identity, bot_id, chat_id, message_id, content_hash, status, text, open_id, chat_kind, app_id, project_id, creation_id, binding_revision, attachments, watch_input FROM inbound_work WHERE identity=?",
                    vec![identity.clone().into()],
                ))
                .await
                .map_err(storage)?;
            // 只读事务先提交，再解码既有身份与工作行：解出的长材料不跨提交等待保留，
            // 由调用方在下一等待前按真实字段计权。
            tx.commit().await.map_err(storage)?;
            // 身份行必须与派生 key 及本请求逐列一致：不从请求补或覆盖持久身份。
            let stored_identity = strict_text(&row, "identity")?;
            let stored_bot = strict_text(&row, "bot_id")?;
            let stored_message = strict_text(&row, "message_id")?;
            let stored_chat = strict_text(&row, "chat_id")?;
            let stored_hash = strict_text(&row, "content_hash")?;
            if stored_identity != identity
                || stored_bot != inbound.bot_id
                || stored_message != inbound.message_id
                || stored_chat != inbound.chat_id
                || stored_hash != inbound.content_hash
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "inbound identity conflicts with stored content",
                    false,
                    None,
                ));
            }
            let Some(work) = work else {
                // 身份行存在但工作行缺失：绑定/归属字段无从证明，不能借本次事件回填。
                return Err(work_needs_recovery());
            };
            let work_identity = strict_text(&work, "identity")?;
            let work_bot = strict_text(&work, "bot_id")?;
            let work_chat = strict_text(&work, "chat_id")?;
            let work_message = strict_text(&work, "message_id")?;
            let work_hash = strict_text(&work, "content_hash")?;
            if work_identity != identity
                || work_bot != inbound.bot_id
                || work_chat != inbound.chat_id
                || work_message != inbound.message_id
                || work_hash != inbound.content_hash
            {
                // 持久工作行与本次身份不一致：保留行，明确需本机恢复。
                return Err(work_needs_recovery());
            }
            let status = stored_text(&work, "status")?;
            // 只有仍在受理中的合法状态可以续跑；completed/needs_attention 沿既有“已完成”
            // 语义；未知值在构造续跑 payload 与任何旁写之前固定不可重试。
            match status.as_str() {
                "completed" | "needs_attention" => return Ok(InboundAdmit::DuplicateCompleted),
                "pending" | "claimed" | "failed" => {}
                _ => return Err(work_state_unreadable()),
            }
            return Ok(InboundAdmit::DuplicateResume(FrozenInbound {
                bot_id: work_bot,
                message_id: work_message,
                chat_id: work_chat,
                content_hash: work_hash,
                // 路由、绑定与 fencing 判据只接受持久值本身；空串是合法业务值。
                text: strict_text(&work, "text")?,
                attachments: serde_json::from_str(&strict_text(&work, "attachments")?)
                    .map_err(|_| work_needs_recovery())?,
                open_id: strict_text(&work, "open_id")?,
                chat_kind: strict_text(&work, "chat_kind")?,
                app_id: strict_text(&work, "app_id")?,
                project_id: strict_text(&work, "project_id")?,
                creation_id: strict_text(&work, "creation_id")?,
                binding_revision: strict_watermark(&work, "binding_revision")?,
                watch_input: strict_text(&work, "watch_input")?,
            }));
        }
        let pending = tx
            .query_one_raw(statement(
                "SELECT COUNT(*) AS n, COALESCE(SUM(LENGTH(CAST(text AS BLOB)) + LENGTH(CAST(attachments AS BLOB))),0) AS bytes FROM inbound_work WHERE status IN ('pending','claimed','failed')",
                vec![],
            ))
            .await
            .map_err(storage)?;
        // 账本聚合只接受可解码的计数与真实 UTF-8 字节数；损坏显式失败，不按 0 继续。
        let (pending_n, pending_bytes) = match &pending {
            Some(row) => (stored_i64(row, "n")?, stored_i64(row, "bytes")?),
            None => (0, 0),
        };
        let attachments =
            serde_json::to_string(&inbound.attachments).map_err(|_| work_needs_recovery())?;
        let text_bytes = i64::try_from(inbound.text.len() + attachments.len())
            .map_err(|_| work_needs_recovery())?;
        if pending_n >= INBOUND_PENDING_LIMIT
            || pending_bytes.saturating_add(text_bytes) > INBOUND_PENDING_BYTES
        {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "inbound pending budget is full",
                true,
                None,
            ));
        }
        // 受理时刻就是本轮唯一可用的就绪等待起点：它与受理行同一事务写入，之后
        // 所有写入者（中断/可重试失败/就绪等待）只沿用这个最早起点。
        let admitted_at = unix_seconds();
        tx.execute_raw(statement(
            "INSERT INTO inbound_identities(identity, bot_id, message_id, chat_id, content_hash, admitted_at)
             VALUES(?,?,?,?,?,?)",
            vec![
                identity.clone().into(),
                inbound.bot_id.clone().into(),
                inbound.message_id.clone().into(),
                inbound.chat_id.clone().into(),
                inbound.content_hash.clone().into(),
                admitted_at.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.execute_raw(statement(
            "INSERT INTO inbound_work(identity, bot_id, chat_id, message_id, content_hash, text, open_id, chat_kind, app_id, project_id, creation_id, binding_revision, attachments, status, diagnostic, claimed_by, claimed_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            vec![
                identity.into(),
                inbound.bot_id.clone().into(),
                inbound.chat_id.clone().into(),
                inbound.message_id.clone().into(),
                inbound.content_hash.clone().into(),
                inbound.text.clone().into(),
                inbound.open_id.clone().into(),
                inbound.chat_kind.clone().into(),
                inbound.app_id.clone().into(),
                inbound.project_id.clone().into(),
                inbound.creation_id.clone().into(),
                i64::try_from(inbound.binding_revision)
                    .map_err(|_| work_needs_recovery())?
                    .into(),
                attachments.into(),
                "pending".to_string().into(),
                "".to_string().into(),
                "".to_string().into(),
                0i64.into(),
                admitted_at.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(InboundAdmit::Fresh(inbound))
    }

    pub async fn claim_inbound_work(
        &self,
        bot_id: &str,
        chat_id: &str,
        message_id: &str,
        worker_id: &str,
    ) -> Result<InboundClaim, FeishuError> {
        let identity = inbound_identity(bot_id, chat_id, message_id);
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let Some(row) = tx
            .query_one_raw(statement(
                "SELECT identity, bot_id, chat_id, message_id, content_hash, status, claimed_by, claimed_at, next_attempt_at FROM inbound_work WHERE identity=?",
                vec![identity.clone().into()],
            ))
            .await
            .map_err(storage)?
        else {
            tx.commit().await.map_err(storage)?;
            return Ok(InboundClaim::Missing);
        };
        // 行身份必须与派生 key 及调用键逐列一致；content_hash 同样严格解码，
        // 不把损坏或缺失默认成空串后继续认领。
        let stored_identity = strict_text(&row, "identity")?;
        let stored_bot = strict_text(&row, "bot_id")?;
        let stored_chat = strict_text(&row, "chat_id")?;
        let stored_message = strict_text(&row, "message_id")?;
        let _content_hash = strict_text(&row, "content_hash")?;
        if stored_identity != identity
            || stored_bot != bot_id
            || stored_chat != chat_id
            || stored_message != message_id
        {
            tx.commit().await.map_err(storage)?;
            return Err(work_needs_recovery());
        }
        let status = stored_text(&row, "status")?;
        if status == "completed" {
            tx.commit().await.map_err(storage)?;
            return Ok(InboundClaim::Completed);
        }
        if status == "needs_attention" {
            tx.commit().await.map_err(storage)?;
            return Ok(InboundClaim::NeedsAttention);
        }
        if status != "pending" && status != "failed" && status != "claimed" {
            tx.commit().await.map_err(storage)?;
            // 未知状态不是 Busy：保留行并要求本机恢复，不猜成可重试。
            return Err(work_state_unreadable());
        }
        let claimed_by = stored_text(&row, "claimed_by")?;
        let claimed_at = stored_i64(&row, "claimed_at")?;
        let next_attempt_at = stored_i64(&row, "next_attempt_at")?;
        let now = unix_seconds();
        if status == "claimed" {
            // 统一 lease 边界：age < TTL 才有效；到期（age >= TTL）只能被新 worker 竞争接管。
            let lease_alive = !claimed_by.is_empty()
                && now.saturating_sub(claimed_at) < INBOUND_CLAIM_TTL_SECONDS;
            if lease_alive && claimed_by != worker_id {
                tx.commit().await.map_err(storage)?;
                return Ok(InboundClaim::Busy);
            }
        } else if next_attempt_at > now {
            // 分类退避未到期：不固定频率重派，交由到期后的 sweep 处理。
            tx.commit().await.map_err(storage)?;
            return Ok(InboundClaim::NotDue);
        }
        let claimed = tx
            .execute_raw(statement(
                "UPDATE inbound_work
                 SET status='claimed', claimed_by=?, claimed_at=?, next_attempt_at=0, updated_at=?
                 WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                   AND (
                     (status IN ('pending','failed') AND next_attempt_at<=?)
                     OR (status='claimed' AND claimed_at<=?)
                   )",
                vec![
                    worker_id.to_string().into(),
                    now.into(),
                    now.into(),
                    identity.into(),
                    bot_id.to_string().into(),
                    chat_id.to_string().into(),
                    message_id.to_string().into(),
                    now.into(),
                    now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into(),
                ],
            ))
            .await
            .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        if claimed.rows_affected() == 0 {
            // 读取与条件更新之间被后继认领抢占：本持有者不覆盖后继。
            return Ok(InboundClaim::Busy);
        }
        Ok(InboundClaim::Claimed)
    }

    /// 续约同一持有者的认领租约；0 行条件更新必须显式表达失租。
    ///
    /// 有效 lease 的定义与 claim/takeover 一致：`claimed_at` 距今严格小于租约时长。
    /// 过期的旧持有者在尚无人接管时同样不得续约，不得自认续权。
    pub(crate) async fn renew_inbound_claim(
        &self,
        bot_id: &str,
        chat_id: &str,
        message_id: &str,
        worker_id: &str,
    ) -> Result<ClaimLease, FeishuError> {
        let identity = inbound_identity(bot_id, chat_id, message_id);
        let db = self.db().await?;
        let now = unix_seconds();
        let renewed = db
            .execute_raw(statement(
                "UPDATE inbound_work
                 SET claimed_at=?, updated_at=?
                 WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                   AND claimed_by=? AND status='claimed' AND claimed_at>?",
                vec![
                    now.into(),
                    now.into(),
                    identity.into(),
                    bot_id.to_string().into(),
                    chat_id.to_string().into(),
                    message_id.to_string().into(),
                    worker_id.to_string().into(),
                    now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into(),
                ],
            ))
            .await
            .map_err(storage)?;
        if renewed.rows_affected() == 1 {
            Ok(ClaimLease::Renewed)
        } else {
            Ok(ClaimLease::LostClaim)
        }
    }

    /// 在同一事务里判定并写入一次入站工作结果。
    ///
    /// 每个分支先核本持有者的有效 claim，再核受理身份与工作行的逐字段关联；失去认领
    /// 返回 `LostClaim`，持久身份损坏返回需恢复，两者均不写入。
    /// 首次准备等待不消耗失败预算，其唯一计时来源是受理身份的不可变 `admitted_at`；
    /// 退避预算耗尽时，创建中的路由必须仍匹配该工作的原项目/创建身份/绑定修订才收束。
    pub(crate) async fn finish_inbound_work(
        &self,
        bot_id: &str,
        chat_id: &str,
        message_id: &str,
        worker_id: &str,
        finish: WorkFinish<'_>,
    ) -> Result<MarkOutcome, FeishuError> {
        let keys = WorkKeys {
            identity: inbound_identity(bot_id, chat_id, message_id),
            bot_id,
            chat_id,
            message_id,
        };
        let db = self.db().await?;
        let now = unix_seconds();
        let lease_cutoff = now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS);
        let tx = db.begin().await.map_err(storage)?;
        let Some(work) = Self::claimed_work(&tx, &keys, worker_id, lease_cutoff).await? else {
            tx.commit().await.map_err(storage)?;
            return Ok(MarkOutcome::LostClaim);
        };
        let admitted = Self::admitted_at(&tx, &keys, &work).await?;
        let identity: sea_orm::Value = keys.identity.clone().into();
        let updated = match finish {
            WorkFinish::Completed => {
                tx.execute_raw(statement(
                    "UPDATE inbound_work
                     SET status='completed', diagnostic='', claimed_by='', claimed_at=0,
                         attempt_count=0, next_attempt_at=0, updated_at=?
                     WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                       AND claimed_by=? AND status='claimed' AND claimed_at>?",
                    vec![
                        now.into(),
                        identity,
                        bot_id.to_string().into(),
                        chat_id.to_string().into(),
                        message_id.to_string().into(),
                        worker_id.to_string().into(),
                        lease_cutoff.into(),
                    ],
                ))
                .await
                .map_err(storage)?
            }
            WorkFinish::Interrupted => {
                tx.execute_raw(statement(
                    "UPDATE inbound_work
                     SET status='pending', diagnostic='runtime stopped before a local terminal fact',
                         claimed_by='', claimed_at=0, next_attempt_at=0, updated_at=?
                     WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                       AND claimed_by=? AND status='claimed' AND claimed_at>?",
                    vec![
                        now.into(),
                        identity,
                        bot_id.to_string().into(),
                        chat_id.to_string().into(),
                        message_id.to_string().into(),
                        worker_id.to_string().into(),
                        lease_cutoff.into(),
                    ],
                ))
                .await
                .map_err(storage)?
            }
            WorkFinish::NeedsAttention(diagnostic) | WorkFinish::CreationConflict(diagnostic) => {
                tx.execute_raw(statement(
                    "UPDATE inbound_work
                     SET status='needs_attention', diagnostic=?, claimed_by='', claimed_at=0, updated_at=?
                     WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                       AND claimed_by=? AND status='claimed' AND claimed_at>?",
                    vec![
                        diagnostic.to_string().into(),
                        now.into(),
                        identity,
                        bot_id.to_string().into(),
                        chat_id.to_string().into(),
                        message_id.to_string().into(),
                        worker_id.to_string().into(),
                        lease_cutoff.into(),
                    ],
                ))
                .await
                .map_err(storage)?
            }
            WorkFinish::Retryable(diagnostic) => {
                let next_count = work.attempt_count.saturating_add(1);
                if next_count >= INBOUND_RETRY_BUDGET {
                    tx.execute_raw(statement(
                        "UPDATE inbound_work
                         SET status='needs_attention',
                             diagnostic=?,
                             claimed_by='', claimed_at=0, updated_at=?
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            format!(
                                "recovery budget exhausted after {INBOUND_RETRY_BUDGET} failures: {diagnostic}"
                            )
                            .into(),
                            now.into(),
                            identity,
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?
                } else {
                    tx.execute_raw(statement(
                        "UPDATE inbound_work
                         SET status='failed', diagnostic=?, claimed_by='', claimed_at=0,
                             attempt_count=?, next_attempt_at=?, updated_at=?
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            diagnostic.to_string().into(),
                            next_count.into(),
                            now.saturating_add(retry_backoff_seconds(next_count)).into(),
                            now.into(),
                            identity,
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?
                }
            }
            WorkFinish::Deferred(diagnostic) => {
                let deadline = admitted
                    .checked_add(INBOUND_READINESS_WAIT_BUDGET_SECONDS)
                    .ok_or_else(work_needs_recovery)?;
                if now >= deadline {
                    // 等待上限只收束这一条入站工作：仍在准备的授权与 bound 路由保持原样。
                    tx.execute_raw(statement(
                        "UPDATE inbound_work
                         SET status='needs_attention', diagnostic=?, claimed_by='', claimed_at=0, updated_at=?
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            format!(
                                "first input preparation did not complete within {INBOUND_READINESS_WAIT_BUDGET_SECONDS}s: {diagnostic}"
                            )
                            .into(),
                            now.into(),
                            identity,
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?
                } else {
                    tx.execute_raw(statement(
                        "UPDATE inbound_work
                         SET status='pending', diagnostic=?, claimed_by='', claimed_at=0,
                             next_attempt_at=?, updated_at=?
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            diagnostic.to_string().into(),
                            now.saturating_add(INBOUND_READINESS_POLL_SECONDS).into(),
                            now.into(),
                            identity,
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?
                }
            }
        };
        let applied = updated.rows_affected() == 1;
        if applied {
            // 与入站终态同一事务：失 claim 时两者都不写，路由只按原创建身份收束。
            let collapse_reason = match &finish {
                WorkFinish::CreationConflict(diagnostic) => Some((*diagnostic).to_string()),
                WorkFinish::Retryable(diagnostic)
                    if work.attempt_count.saturating_add(1) >= INBOUND_RETRY_BUDGET =>
                {
                    Some(format!(
                        "conversation Thread creation did not complete: {diagnostic}"
                    ))
                }
                _ => None,
            };
            if let Some(diagnostic) = collapse_reason.as_deref() {
                Self::collapse_creating_route_in(&tx, &keys, &work, diagnostic).await?;
            }
        }
        tx.commit().await.map_err(storage)?;
        if applied {
            Ok(MarkOutcome::Applied)
        } else {
            Ok(MarkOutcome::LostClaim)
        }
    }

    /// 对确定未受理的可重试 submit 记录退避，保留原 claim 与附件所有权。
    ///
    /// BudgetExhausted 不先写终态：调用者将原失败交还 finisher，由既有 Retryable
    /// 分支在同一事务中完成第八次失败及必要的 creating 路由收束。
    pub(in crate::bots) async fn retain_inbound_retry(
        &self,
        inbound: &FrozenInbound,
        worker_id: &str,
        diagnostic: &str,
    ) -> Result<InboundRetryWait, FeishuError> {
        let keys = WorkKeys {
            identity: inbound_identity(&inbound.bot_id, &inbound.chat_id, &inbound.message_id),
            bot_id: &inbound.bot_id,
            chat_id: &inbound.chat_id,
            message_id: &inbound.message_id,
        };
        let now = unix_seconds();
        let cutoff = now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS);
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let Some(work) = Self::claimed_work(&tx, &keys, worker_id, cutoff).await? else {
            return Ok(InboundRetryWait::LostClaim);
        };
        Self::admitted_at(&tx, &keys, &work).await?;
        if work.content_hash != inbound.content_hash
            || work.project_id != inbound.project_id
            || work.creation_id != inbound.creation_id
            || work.binding_revision != inbound.binding_revision
        {
            return Err(work_needs_recovery());
        }
        let next_count = work.attempt_count.saturating_add(1);
        if next_count >= INBOUND_RETRY_BUDGET {
            return Ok(InboundRetryWait::BudgetExhausted);
        }
        let retry_at = now
            .checked_add(retry_backoff_seconds(next_count))
            .ok_or_else(work_needs_recovery)?;
        let updated = tx.execute_raw(statement(
            "UPDATE inbound_work SET attempt_count=?,next_attempt_at=?,diagnostic=?,updated_at=?
             WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
               AND status='claimed' AND claimed_by=? AND claimed_at>?",
            vec![next_count.into(), retry_at.into(), diagnostic.to_string().into(), now.into(),
                keys.identity.into(), inbound.bot_id.clone().into(), inbound.chat_id.clone().into(),
                inbound.message_id.clone().into(), worker_id.to_string().into(), cutoff.into()],
        )).await.map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(if updated.rows_affected() == 1 {
            InboundRetryWait::Until { retry_at }
        } else {
            InboundRetryWait::LostClaim
        })
    }

    /// 读取当前认领的工作行。没有有效认领与持久行解码损坏分别表达，调用方均不得写终态。
    async fn claimed_work<C: ConnectionTrait>(
        db: &C,
        keys: &WorkKeys<'_>,
        worker_id: &str,
        lease_cutoff: i64,
    ) -> Result<Option<ClaimedWork>, FeishuError> {
        let row = db
            .query_one_raw(statement(
                "SELECT attempt_count, bot_id, chat_id, message_id, content_hash, project_id,
                        creation_id, binding_revision
                 FROM inbound_work
                 WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                   AND claimed_by=? AND status='claimed' AND claimed_at>?",
                vec![
                    keys.identity.clone().into(),
                    keys.bot_id.to_string().into(),
                    keys.chat_id.to_string().into(),
                    keys.message_id.to_string().into(),
                    worker_id.to_string().into(),
                    lease_cutoff.into(),
                ],
            ))
            .await
            .map_err(storage)?;
        let Some(row) = row else {
            return Ok(None);
        };
        if stored_text(&row, "bot_id")? != keys.bot_id
            || stored_text(&row, "chat_id")? != keys.chat_id
            || stored_text(&row, "message_id")? != keys.message_id
        {
            return Err(work_needs_recovery());
        }
        let attempt_count = stored_i64(&row, "attempt_count")?;
        if attempt_count < 0 {
            return Err(work_needs_recovery());
        }
        Ok(Some(ClaimedWork {
            attempt_count,
            content_hash: stored_text(&row, "content_hash")?,
            project_id: stored_text(&row, "project_id")?,
            creation_id: stored_text(&row, "creation_id")?,
            binding_revision: strict_watermark(&row, "binding_revision")?,
        }))
    }

    /// 首次准备等待的唯一计时来源：受理身份行不可变的 `admitted_at`。
    ///
    /// 身份行缺失、字段与该工作行不一致、时间缺失或非正都属于持久损坏，返回需恢复；
    /// 绝不用工作行的更新时间、诊断文本或当前时间补猜。
    async fn admitted_at<C: ConnectionTrait>(
        db: &C,
        keys: &WorkKeys<'_>,
        work: &ClaimedWork,
    ) -> Result<i64, FeishuError> {
        let row = db
            .query_one_raw(statement(
                "SELECT admitted_at, bot_id, chat_id, message_id, content_hash
                 FROM inbound_identities WHERE identity=?",
                vec![keys.identity.clone().into()],
            ))
            .await
            .map_err(storage)?;
        let Some(row) = row else {
            return Err(work_needs_recovery());
        };
        if stored_text(&row, "bot_id")? != keys.bot_id
            || stored_text(&row, "chat_id")? != keys.chat_id
            || stored_text(&row, "message_id")? != keys.message_id
            || stored_text(&row, "content_hash")? != work.content_hash
        {
            return Err(work_needs_recovery());
        }
        let admitted = stored_i64(&row, "admitted_at")?;
        if admitted <= 0 {
            return Err(work_needs_recovery());
        }
        Ok(admitted)
    }

    /// 创建冲突或失败预算耗尽时的路由收束：只认仍匹配该工作原聊天、项目、创建身份与绑定修订
    /// 的 `creating` 路由，不按 chat 关闭后继显式新建替换出来的创建中路由。
    async fn collapse_creating_route_in<C: ConnectionTrait>(
        db: &C,
        keys: &WorkKeys<'_>,
        work: &ClaimedWork,
        diagnostic: &str,
    ) -> Result<bool, FeishuError> {
        if work.creation_id.is_empty() || work.project_id.is_empty() {
            return Ok(false);
        }
        let result = db
            .execute_raw(statement(
                "UPDATE thread_bindings
                 SET status='needs_attention', diagnostic=?, updated_at=?, revision=revision+1
                 WHERE chat_id=? AND project_id=? AND creation_id=? AND revision=? AND status='creating'
                   AND revision<9223372036854775807",
                vec![
                    diagnostic.to_string().into(),
                    unix_seconds().into(),
                    keys.chat_id.to_string().into(),
                    work.project_id.clone().into(),
                    work.creation_id.clone().into(),
                    i64::try_from(work.binding_revision)
                        .map_err(|_| corrupt_binding())?
                        .into(),
                ],
            ))
            .await
            .map_err(storage)?;
        Ok(result.rows_affected() == 1)
    }

    /// 只取到期工作：pending/failed 退避到期，或 claimed 租约过期（进程崩溃）。
    pub(crate) async fn list_due_inbound(
        &self,
        bot_id: &str,
    ) -> Result<Vec<FrozenInbound>, FeishuError> {
        let now = unix_seconds();
        let db = self.db().await?;
        let rows = db
            .query_all_raw(statement(
                "SELECT identity, bot_id, chat_id, message_id, content_hash, text, open_id, chat_kind, app_id, project_id, creation_id, binding_revision, attachments, watch_input
                 FROM inbound_work
                 WHERE bot_id=? AND (
                   (status IN ('pending','failed') AND next_attempt_at<=?)
                   OR (status='claimed' AND claimed_at<=?)
                 )
                 ORDER BY updated_at ASC",
                vec![
                    bot_id.to_string().into(),
                    now.into(),
                    now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into(),
                ],
            ))
            .await
            .map_err(storage)?;
        rows.into_iter()
            .map(|row| {
                // 派生 key 与列值必须自洽：坏 key 不能先被当成可恢复工作再变 Missing。
                let identity: String = strict_text(&row, "identity")?;
                let row_bot: String = strict_text(&row, "bot_id")?;
                let row_chat: String = strict_text(&row, "chat_id")?;
                let row_message: String = strict_text(&row, "message_id")?;
                if row_bot != bot_id
                    || identity != inbound_identity(&row_bot, &row_chat, &row_message)
                {
                    return Err(work_needs_recovery());
                }
                Ok(FrozenInbound {
                    bot_id: row_bot,
                    chat_id: row_chat,
                    message_id: row_message,
                    content_hash: stored_text(&row, "content_hash")?,
                    text: stored_text(&row, "text")?,
                    attachments: serde_json::from_str(&strict_text(&row, "attachments")?)
                        .map_err(|_| work_needs_recovery())?,
                    open_id: stored_text(&row, "open_id")?,
                    chat_kind: stored_text(&row, "chat_kind")?,
                    // 绑定/路由/fencing 判据只接受持久值；空串（如尚无续接输入）是合法值。
                    app_id: strict_text(&row, "app_id")?,
                    project_id: strict_text(&row, "project_id")?,
                    creation_id: strict_text(&row, "creation_id")?,
                    binding_revision: strict_watermark(&row, "binding_revision")?,
                    watch_input: strict_text(&row, "watch_input")?,
                })
            })
            .collect()
    }

    pub async fn owns_thread(&self, thread_id: &str) -> Result<bool, FeishuError> {
        let db = self.db().await?;
        db.query_one_raw(statement(
            "SELECT chat_id FROM thread_bindings WHERE thread_id=? OR (status='creating' AND creation_id=?) LIMIT 1",
            vec![thread_id.to_owned().into(), thread_id.to_owned().into()],
        ))
        .await
        .map(|row| row.is_some())
        .map_err(storage)
    }

    pub(in crate::bots) async fn claim_thread_binding(
        &self,
        claim: &target::TargetClaim,
    ) -> Result<ThreadBindingClaim, FeishuError> {
        let chat_id = claim.chat_id.as_str();
        let creation_id = claim.creation_id.as_str();
        let project_id = claim.project_id.as_str();
        if chat_id.is_empty() || creation_id.is_empty() || project_id.is_empty() {
            return Err(corrupt_binding());
        }
        // 首次受理只能冻结已核实的证明：无类型的受理会让离线重启后无法恢复目标种类。
        let first = claim.freeze(1);
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let row = match tx
            .query_one_raw(statement(
                "SELECT chat_id, thread_id, status, creation_id, project_id, revision, generation, diagnostic,target_json FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?
        {
            Some(row) => row,
            None => {
            // 真正 NoRow：首次受理在此写入新行，随后才提交。
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id, revision, generation, diagnostic, created_at, updated_at,target_json)
             VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            vec![
                chat_id.to_string().into(),
                "".to_string().into(),
                "creating".to_string().into(),
                creation_id.to_string().into(),
                project_id.to_string().into(),
                1i64.into(),
                1i64.into(),
                "".to_string().into(),
                unix_seconds().into(),
                unix_seconds().into(),
                first.encode()?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
            return Ok(ThreadBindingClaim::Creating {
            creation_id: creation_id.to_string(),
            });
            }
        };
        // 只读事务先提交：解码出的既有身份（可能来自更大的历史创建）与诊断不跨提交
        // 等待保留，随后只由调用方按真实长度计权。
        tx.commit().await.map_err(storage)?;
        // 路由与创建身份只接受持久值：解码失败不得默认成 bound/空创建。
        let stored_chat = strict_text(&row, "chat_id")?;
        let status = strict_text(&row, "status")?;
        let thread_id = strict_text(&row, "thread_id")?;
        let stored_creation = strict_text(&row, "creation_id")?;
        let stored_project = strict_text(&row, "project_id")?;
        let diagnostic = strict_text(&row, "diagnostic")?;
        let stored_target = target::TargetProof::decode(&row)?;
        // 水位同样严格解码：坏行不能继续被当成可用绑定。
        let revision = strict_watermark(&row, "revision")?;
        let _generation = strict_watermark(&row, "generation")?;
        if stored_chat != chat_id {
            return Err(corrupt_binding());
        }
        // 合法 bound/creating 必须有可证明的创建身份与项目：空项目不是通配。
        // 迁移后的 needs_attention 行允许保留空的创建/项目，仍走它自己的诊断路径。
        let needs_proof = status == "bound" || status == "creating";
        if needs_proof
            && (stored_creation.is_empty()
                || stored_project.is_empty()
                || stored_project != project_id)
        {
            return Err(binding_needs_recovery());
        }
        // 合法状态只有 bound/creating/needs_attention；旧 pending/absent 已由迁移
        // 规范为 attention，运行时不再兼容，也不默认成任一可用状态。
        match status.as_str() {
            "bound" if !thread_id.is_empty() && thread_id != "pending" => {
                Ok(ThreadBindingClaim::Bound { thread_id })
            }
            // bound 缺少可用 Thread 身份：不可证明归属，保留现场要求本机恢复。
            "bound" => Err(binding_needs_recovery()),
            // creating 的创建身份已由上面的 needs_proof 判定非空。同一创建意图的
            // 目标种类只能同源一致：冲突保留现场，不按本次输入覆盖已冻结的证明。
            "creating" => {
                if !stored_target.same_intent(&first) {
                    return Err(binding_needs_recovery());
                }
                // 已冻结证明指向的原始事实必须仍可用；只有同一事实的再次投递
                // 可以重建它。另一条同 kind 的入站不得顶替原来源。
                if !target::source_present(
                    db,
                    &stored_target,
                    chat_id,
                    &stored_project,
                    &stored_creation,
                    revision,
                )
                .await?
                    && !stored_target.same_source(&first)
                {
                    return Err(binding_needs_recovery());
                }
                Ok(ThreadBindingClaim::Creating {
                    creation_id: stored_creation,
                })
            }
            "needs_attention" => Ok(ThreadBindingClaim::NeedsAttention {
                diagnostic: if diagnostic.is_empty() {
                    "conversation Thread binding needs local recovery".to_string()
                } else {
                    diagnostic
                },
            }),
            _ => Err(binding_state_unreadable()),
        }
    }

    pub(in crate::bots) async fn bind_thread(
        &self,
        chat_id: &str,
        thread_id: &str,
        creation_id: &str,
        project_id: &str,
        first_start: Option<&FirstStart>,
    ) -> Result<String, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT thread_id, status, creation_id, project_id, revision, generation,target_json FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let (revision, generation, target) = if let Some(row) = existing {
            // 路由、创建身份与项目归属只接受持久值：解码失败不得默认成 bound 或空创建。
            let status = strict_text(&row, "status")?;
            let bound = strict_text(&row, "thread_id")?;
            let stored_creation = strict_text(&row, "creation_id")?;
            let stored_project = strict_text(&row, "project_id")?;
            // 水位只接受无损解码：缺列或损坏不得回退到 1 覆盖既有水位。
            let revision = strict_watermark(&row, "revision")?;
            let generation = strict_watermark(&row, "generation")?;
            if status != "bound" && status != "creating" {
                // 未知状态不得被本次绑定的 UPSERT 覆盖成 bound。
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            if status == "bound" && !bound.is_empty() && bound != thread_id && bound != "pending" {
                tx.commit().await.map_err(storage)?;
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "chat is already bound to another Thread",
                    false,
                    None,
                ));
            }
            if stored_creation.is_empty() {
                // 既有行没有创建身份：无法证明属于本次创建，拒绝覆盖。
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            if stored_creation != creation_id {
                tx.commit().await.map_err(storage)?;
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "chat Thread creation identity conflict",
                    false,
                    None,
                ));
            }
            if stored_project.is_empty() || stored_project != project_id {
                // 项目归属未知或不一致：不覆盖成当前项目，也不把 Thread 迁到另一项目。
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            let target = target::TargetProof::decode(&row)?;
            // 写入的 origin 必须携带本次创建意图已冻结的证明：Created 来自首次受理，
            // 迁移后的在建意图只能是可核对旧来源给出的 Legacy；Unproven 保留现场等
            // 本机处理，不在这里补猜目标种类。
            if target.kind().is_none() {
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            // 引用某条原始事实之前必须在同一事务内确认它已经在库：不提交之后必然
            // 打不开的 origin。缺失时保留 creating，等原事实到达再续接。
            if !target::source_present(&tx, &target, chat_id, project_id, creation_id, revision)
                .await?
            {
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            // operation 的最终 Thread 归属与 route/origin 同批提交：分两次提交的窗口
            // 会让重启后的开库校验看到 origin 已存在而来源 operation 仍未指向它。
            if target::bind_operation_thread(
                &tx,
                &target,
                chat_id,
                creation_id,
                revision,
                thread_id,
            )
            .await
            .is_err()
            {
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            (revision, generation, target)
        } else {
            return Err(binding_needs_recovery());
        };
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               thread_id=excluded.thread_id,
               status='bound',
               creation_id=excluded.creation_id,
               project_id=excluded.project_id,
               diagnostic='',
               updated_at=excluded.updated_at",
            vec![
                chat_id.to_string().into(),
                thread_id.to_string().into(),
                "bound".to_string().into(),
                creation_id.to_string().into(),
                project_id.to_string().into(),
                i64::try_from(revision)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                i64::try_from(generation)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                "".to_string().into(),
                unix_seconds().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        audience::bind_origin(
            &tx,
            thread_id,
            chat_id,
            project_id,
            creation_id,
            revision,
            &target,
        )
        .await?;
        // 首次授权与绑定事实同批提交：不允许出现「绑定已可见、授权头缺失」的窗口。
        // 只有当前创建意图（Created）才能自动建立；旧来源迁入的意图保持人工升级。
        if let Some(first) = first_start {
            if !matches!(target, target::TargetProof::Created { .. }) {
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            audience::first_pending_start(
                &tx,
                first,
                chat_id,
                creation_id,
                project_id,
                revision,
                thread_id,
            )
            .await?;
        }
        tx.commit().await.map_err(storage)?;
        Ok(thread_id.to_string())
    }

    pub(in crate::bots) async fn mark_binding_attention(
        &self,
        expected: &BoundThreadExpectation,
        diagnostic: &str,
    ) -> Result<bool, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let next = expected
            .revision
            .checked_add(1)
            .and_then(|v| i64::try_from(v).ok())
            .ok_or_else(corrupt_binding)?;
        let result=tx.execute_raw(statement(
            "UPDATE thread_bindings SET status='needs_attention', diagnostic=?, updated_at=?, revision=?
             WHERE chat_id=? AND thread_id=? AND creation_id=? AND project_id=? AND revision=? AND status='bound'",
            vec![
                diagnostic.to_string().into(),
                unix_seconds().into(),
                next.into(),
                expected.chat_id.clone().into(),
                expected.thread_id.clone().into(),
                expected.creation_id.clone().into(),
                expected.project_id.clone().into(),
                i64::try_from(expected.revision).map_err(|_|corrupt_binding())?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        if result.rows_affected() != 1 {
            tx.rollback().await.map_err(storage)?;
            return Ok(false);
        }
        audience::close_unavailable_binding(&tx, expected).await?;
        tx.commit().await.map_err(storage)?;
        Ok(true)
    }

    pub async fn binding_for_chat(
        &self,
        chat_id: &str,
        bot_id: &str,
        project_id: &str,
    ) -> Result<BindingProjection, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT chat_id, thread_id, status, revision, generation, project_id, creation_id, diagnostic FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let projection = match row {
            Some(row) => {
                // 只接受与查询键一致的持久行；状态分类先于归属判定，
                // 迁移保留的 needs_attention 缺创建/项目是合法事实，不用当前请求补齐。
                let stored_chat: String = strict_text(&row, "chat_id")?;
                if stored_chat != chat_id {
                    return Err(corrupt_binding());
                }
                let stored_status: String = strict_text(&row, "status")?;
                let stored_project: String = strict_text(&row, "project_id")?;
                let stored_creation: String = strict_text(&row, "creation_id")?;
                let thread_id = empty_to_none(strict_text(&row, "thread_id")?)
                    .filter(|value| value != "pending");
                let revision = strict_watermark(&row, "revision")?;
                // 已选水位两列都严格解码，不静默忽略 generation。
                let _generation = strict_watermark(&row, "generation")?;
                match stored_status.as_str() {
                    // bound 必须带真实 Thread 身份：缺失或旧 pending sentinel 都不是可路由绑定。
                    "bound" if thread_id.is_none() => return Err(binding_needs_recovery()),
                    // 合法绑定/创建必须有可证明的创建身份与同项目归属（空项目不是通配）。
                    "bound" | "creating" => {
                        if stored_creation.is_empty()
                            || stored_project.is_empty()
                            || stored_project != project_id
                        {
                            return Err(binding_needs_recovery());
                        }
                    }
                    // 合法 attention 允许缺创建/项目与诊断，原样保留既有事实。
                    "needs_attention" => {}
                    _ => {
                        // 旧 pending/absent 已由迁移规范为 attention；未知状态同样
                        // 不得默认成 NeedsAttention 或任何可用绑定。
                        return Err(binding_state_unreadable());
                    }
                }
                BindingProjection {
                    chat_id: stored_chat,
                    project_id: stored_project,
                    // 创建身份与绑定水位是归属判据：损坏必须显式失败，不能默认化。
                    creation_id: stored_creation,
                    thread_id,
                    revision,
                    status: stored_status,
                    diagnostic: empty_to_none(strict_text(&row, "diagnostic")?),
                }
            }
            None => BindingProjection {
                chat_id: chat_id.to_string(),
                project_id: project_id.to_string(),
                creation_id: String::new(),
                thread_id: None,
                revision: 0,
                status: "absent".to_string(),
                diagnostic: None,
            },
        };
        let _ = bot_id;
        Ok(projection)
    }

    /// 首次绑定操作的原子起点：绑定水位切换与该操作的持久记录在同一次提交中生效。
    ///
    /// 调用方已用 [`Self::load_binding_operation`] 与 [`Self::binding_for_chat`] 判定这是首次受理；
    /// 本方法仍在事务内重做 CAS 判定，避免两次读取之间的并发切换被覆盖。
    pub async fn begin_binding_operation(
        &self,
        chat_id: &str,
        expected_revision: u64,
        project_id: &str,
        operation: &BindingOperation,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT revision, generation FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let (current_revision, current_generation) = match &existing {
            Some(row) => (
                strict_watermark(row, "revision")?,
                strict_watermark(row, "generation")?,
            ),
            None => (0, 0),
        };
        if current_revision != expected_revision {
            tx.commit().await.map_err(storage)?;
            return Err(stale_binding_revision());
        }
        let next_revision = current_revision
            .checked_add(1)
            .ok_or_else(corrupt_binding)?;
        let next_generation = current_generation
            .checked_add(1)
            .ok_or_else(corrupt_binding)?;
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id, revision, generation, diagnostic, created_at, updated_at,target_json)
             VALUES(?,?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               thread_id='',
               status='creating',
               creation_id=excluded.creation_id,
               project_id=excluded.project_id,
               revision=excluded.revision,
               generation=excluded.generation,
               target_json=excluded.target_json,
               diagnostic='',
               updated_at=excluded.updated_at",
            vec![
                chat_id.to_string().into(),
                "".to_string().into(),
                "creating".to_string().into(),
                operation.creation_id.clone().into(),
                project_id.to_string().into(),
                i64::try_from(next_revision)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                i64::try_from(next_generation)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                "".to_string().into(),
                unix_seconds().into(),
                unix_seconds().into(),
                operation.target.encode()?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        if !insert_binding_operation(&tx, operation).await? {
            // 同一 operationId 已存在不同记录：保留原记录，不覆盖他人操作。
            return Err(binding_needs_recovery());
        }
        audience::close_chat(
            &tx,
            chat_id,
            pl_protocol::BotAudienceCloseReason::BindingReplaced,
        )
        .await?;
        tx.commit().await.map_err(storage)?;
        Ok(())
    }

    /// 补齐可证明归属的部分现场：只有创建身份、项目与恰好下一绑定 revision 都匹配时，
    /// 才写入缺失的操作记录；不再次切换绑定水位，也不覆盖其他创建。
    pub async fn adopt_binding_operation(
        &self,
        chat_id: &str,
        expected_revision: u64,
        project_id: &str,
        operation: &BindingOperation,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let row = tx
            .query_one_raw(statement(
                "SELECT status, thread_id, creation_id, project_id, revision,target_json FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let Some(row) = row else {
            tx.commit().await.map_err(storage)?;
            return Err(binding_needs_recovery());
        };
        let status = strict_text(&row, "status")?;
        let thread_id = strict_text(&row, "thread_id")?;
        let creation_id = strict_text(&row, "creation_id")?;
        let stored_project = strict_text(&row, "project_id")?;
        let revision = strict_watermark(&row, "revision")?;
        let claimed = status == "creating"
            && target::TargetProof::decode(&row)? == operation.target
            && thread_id.is_empty()
            && creation_id == operation.creation_id
            && stored_project == project_id
            && revision
                == expected_revision
                    .checked_add(1)
                    .ok_or_else(corrupt_binding)?;
        if !claimed {
            tx.commit().await.map_err(storage)?;
            return Err(binding_needs_recovery());
        }
        if !insert_binding_operation(&tx, operation).await? {
            tx.commit().await.map_err(storage)?;
            return Err(binding_needs_recovery());
        }
        tx.commit().await.map_err(storage)?;
        Ok(())
    }

    pub async fn load_binding_operation(
        &self,
        operation_id: &str,
    ) -> Result<Option<BindingOperation>, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id,target_json
                 FROM binding_operations WHERE operation_id=?",
                vec![operation_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        row.map(|row| {
            // 操作身份与冻结 revision 是接续判据：损坏必须显式失败，不能默认化。
            let stored_operation: String = strict_text(&row, "operation_id")?;
            if stored_operation != operation_id {
                return Err(corrupt_binding());
            }
            Ok(BindingOperation {
                operation_id: stored_operation,
                bot_id: strict_text(&row, "bot_id")?,
                chat_id: strict_text(&row, "chat_id")?,
                content_hash: strict_text(&row, "content_hash")?,
                expected_revision: strict_watermark(&row, "expected_revision")?,
                creation_id: strict_text(&row, "creation_id")?,
                thread_id: empty_to_none(strict_text(&row, "thread_id")?),
                target: target::TargetProof::decode(&row)?,
            })
        })
        .transpose()
    }

    pub async fn save_binding_operation(
        &self,
        operation: &BindingOperation,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "INSERT INTO binding_operations(operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id, updated_at,target_json)
             VALUES(?,?,?,?,?,?,?,?,?)
             ON CONFLICT(operation_id) DO UPDATE SET
               thread_id=excluded.thread_id,
               updated_at=excluded.updated_at",
            vec![
                operation.operation_id.clone().into(),
                operation.bot_id.clone().into(),
                operation.chat_id.clone().into(),
                operation.content_hash.clone().into(),
                i64::try_from(operation.expected_revision)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                operation.creation_id.clone().into(),
                operation.thread_id.clone().unwrap_or_default().into(),
                unix_seconds().into(),
                operation.target.encode()?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }

    pub async fn observe_direct(
        &self,
        chat_id: &str,
        open_id: Option<&str>,
        name: Option<&str>,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "INSERT INTO observed_directs(chat_id, open_id, name, last_observed_at)
             VALUES(?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               open_id=excluded.open_id,
               name=COALESCE(NULLIF(excluded.name,''), observed_directs.name),
               last_observed_at=excluded.last_observed_at",
            vec![
                chat_id.to_string().into(),
                open_id.unwrap_or("").to_string().into(),
                name.unwrap_or("").to_string().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }

    pub(crate) async fn last_activity_at(&self) -> Result<Option<i64>, FeishuError> {
        let db = self.db().await?;
        let row = db.query_one_raw(statement(
            "SELECT MAX(at) AS at FROM (SELECT MAX(admitted_at) AS at FROM inbound_identities UNION ALL SELECT MAX(updated_at) AS at FROM send_operations)", vec![]
        )).await.map_err(storage)?.ok_or_else(|| storage("missing bot activity aggregate"))?;
        row.try_get::<Option<i64>>("", "at").map_err(storage)
    }

    /// 只读取已记录的直聊对端身份；空值不代表直聊，也不用于猜目标种类。
    pub(crate) async fn observed_direct_open_id(
        &self,
        chat_id: &str,
    ) -> Result<Option<String>, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT open_id FROM observed_directs WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        row.map(|row| strict_text(&row, "open_id")).transpose()
    }

    pub async fn list_observed_directs(&self) -> Result<Vec<ObservedDirect>, FeishuError> {
        let db = self.db().await?;
        let rows = db
            .query_all_raw(statement(
                "SELECT chat_id, name, last_observed_at FROM observed_directs ORDER BY last_observed_at DESC",
                vec![],
            ))
            .await
            .map_err(storage)?;
        rows.into_iter()
            .map(|row| {
                Ok(ObservedDirect {
                    chat_id: stored_text(&row, "chat_id")?,
                    name: empty_to_none(stored_text(&row, "name")?),
                    last_observed_at: stored_i64(&row, "last_observed_at")?,
                })
            })
            .collect()
    }

    pub async fn record_pairing(
        &self,
        request_id: &str,
        open_id: &str,
        display_name: Option<&str>,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let cutoff = unix_seconds().saturating_sub(PAIRING_TTL_SECONDS);
        tx.execute_raw(statement(
            "DELETE FROM pairing_requests WHERE created_at < ?",
            vec![cutoff.into()],
        ))
        .await
        .map_err(storage)?;
        let count = tx
            .query_one_raw(statement(
                "SELECT COUNT(*) AS n FROM pairing_requests",
                vec![],
            ))
            .await
            .map_err(storage)?;
        // 配额计数只接受可解码值：损坏不能静默放宽配对上限。
        let n: i64 = match &count {
            Some(row) => stored_i64(row, "n")?,
            None => 0,
        };
        let existing = tx
            .query_one_raw(statement(
                "SELECT open_id FROM pairing_requests WHERE open_id=?",
                vec![open_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        if existing.is_none() && n >= PAIRING_LIMIT {
            tx.commit().await.map_err(storage)?;
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "pairing request budget is full",
                true,
                None,
            ));
        }
        tx.execute_raw(statement(
            "INSERT INTO pairing_requests(request_id, open_id, display_name, created_at)
             VALUES(?,?,?,?)
             ON CONFLICT(open_id) DO UPDATE SET
               display_name=excluded.display_name,
               created_at=excluded.created_at",
            vec![
                request_id.to_string().into(),
                open_id.to_string().into(),
                display_name.unwrap_or("").to_string().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(())
    }

    pub async fn list_pairings(&self) -> Result<Vec<PairingRow>, FeishuError> {
        let db = self.db().await?;
        let cutoff = unix_seconds().saturating_sub(PAIRING_TTL_SECONDS);
        db.execute_raw(statement(
            "DELETE FROM pairing_requests WHERE created_at < ?",
            vec![cutoff.into()],
        ))
        .await
        .map_err(storage)?;
        let rows = db
            .query_all_raw(statement(
                "SELECT request_id, open_id, display_name, created_at FROM pairing_requests
                 ORDER BY created_at DESC LIMIT ?",
                vec![PAIRING_LIMIT.into()],
            ))
            .await
            .map_err(storage)?;
        rows.into_iter()
            .map(|row| {
                Ok(PairingRow {
                    request_id: stored_text(&row, "request_id")?,
                    open_id: stored_text(&row, "open_id")?,
                    display_name: empty_to_none(stored_text(&row, "display_name")?),
                    created_at: stored_i64(&row, "created_at")?,
                })
            })
            .collect()
    }

    pub async fn clear_pairing(&self, open_id: &str) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "DELETE FROM pairing_requests WHERE open_id=?",
            vec![open_id.to_string().into()],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }

    /// 只读发送记录：首次认领的权威判定在准入内用它区分“首次”与“已持久同操作”。
    pub(crate) async fn load_send(
        &self,
        operation_id: &str,
    ) -> Result<Option<SendRecord>, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, send_identity, send_source
                 FROM send_operations WHERE operation_id=?",
                vec![operation_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(send_record_from_row(row)?))
    }

    /// 该操作是否已有持久记录：只读存在性，不解码整条事实、不跨后续等待保留材料。
    pub(crate) async fn send_exists(&self, operation_id: &str) -> Result<bool, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT 1 AS present FROM send_operations WHERE operation_id=?",
                vec![operation_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        Ok(row.is_some())
    }

    pub async fn claim_send(&self, record: &SendRecord) -> Result<Option<SendRecord>, FeishuError> {
        self.claim_send_fenced(record, None).await
    }

    pub(super) async fn claim_reply_send(
        &self,
        record: &SendRecord,
        reply: &reply::InboundReply,
    ) -> Result<Option<SendRecord>, FeishuError> {
        self.claim_send_fenced(record, Some(SendClaimFence::InboundReply(reply)))
            .await
    }

    /// 原发送行与精确公开实体绑定原子提交；已有操作只返回原记录，不重放网络。
    pub(in crate::bots) async fn claim_publication_file_send(
        &self,
        record: &SendRecord,
        permit: &PublicationFilePermit,
    ) -> Result<Option<SendRecord>, FeishuError> {
        self.claim_send_fenced(record, Some(SendClaimFence::Publication(permit)))
            .await
    }

    async fn claim_send_fenced(
        &self,
        record: &SendRecord,
        fence: Option<SendClaimFence<'_>>,
    ) -> Result<Option<SendRecord>, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, send_identity, send_source
                 FROM send_operations WHERE operation_id=?",
                vec![record.operation_id.clone().into()],
            ))
            .await
            .map_err(storage)?;
        if let Some(row) = existing {
            if let Some(SendClaimFence::Publication(permit)) = &fence {
                let existing = conflict_or_existing(record, send_record_from_row(row)?)?;
                if Self::settle_delivery_file_result(
                    &tx,
                    &permit.token.scope,
                    &permit.entity,
                    &record.operation_id,
                )
                .await?
                    == publication::SettlementOutcome::Superseded
                {
                    return Err(publication::conflict());
                }
                tx.commit().await.map_err(storage)?;
                return Ok(Some(existing));
            }
            // 先提交只读事务再解码：既有结果的长事实不与本次 initial 同时跨提交等待。
            tx.commit().await.map_err(storage)?;
            let existing = send_record_from_row(row)?;
            return conflict_or_existing(record, existing).map(Some);
        }
        if let Some(SendClaimFence::InboundReply(reply)) = &fence {
            if record.bot_id != reply.source.bot_id || record.chat_id != reply.source.chat_id {
                return Err(reply::denied());
            }
            reply::check(&tx, reply).await?;
        }
        let inserted = tx
            .execute_raw(statement(
                "INSERT OR IGNORE INTO send_operations(operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, updated_at, send_identity, send_source)
                 VALUES(?,?,?,?,?,?,?,?,?,?)",
                vec![
                    record.operation_id.clone().into(),
                    record.bot_id.clone().into(),
                    record.chat_id.clone().into(),
                    record.content_hash.clone().into(),
                    record.status.as_str().to_string().into(),
                    record.platform_message_ids.join(",").into(),
                    encode_segment_facts(&record.segments)?.into(),
                    unix_seconds().into(),
                    encode_send_identity(&record.identity)?.into(),
                    encode_send_source(&record.source)?.into(),
                ],
            ))
            .await
            .map_err(storage)?;
        if inserted.rows_affected() == 1 {
            if let Some(SendClaimFence::Publication(permit)) = &fence {
                let [segment] = record.segments.as_slice() else {
                    return Err(publication::conflict());
                };
                if segment.upload != Some(UploadFact::NotStarted)
                    || segment.message_stage != Some(MessageStage::NotStarted)
                    || segment.stop_reason.is_some()
                    || segment.platform_message_id.is_some()
                    || !record.platform_message_ids.is_empty()
                {
                    return Err(publication::conflict());
                }
                Self::bind_delivery_file_operation(
                    &tx,
                    &permit.token,
                    &permit.entity,
                    permit.expected_ledger_version,
                    &record.operation_id,
                    &permit.artifact,
                )
                .await?;
            }
            tx.commit().await.map_err(storage)?;
            return Ok(None);
        }
        let Some(row) = tx
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, send_identity, send_source
                 FROM send_operations WHERE operation_id=?",
                vec![record.operation_id.clone().into()],
            ))
            .await
            .map_err(storage)?
        else {
            tx.commit().await.map_err(storage)?;
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "send operation claim raced without a persisted record",
                true,
                None,
            ));
        };
        if let Some(SendClaimFence::Publication(permit)) = &fence {
            let existing = conflict_or_existing(record, send_record_from_row(row)?)?;
            if Self::settle_delivery_file_result(
                &tx,
                &permit.token.scope,
                &permit.entity,
                &record.operation_id,
            )
            .await?
                == publication::SettlementOutcome::Superseded
            {
                return Err(publication::conflict());
            }
            tx.commit().await.map_err(storage)?;
            return Ok(Some(existing));
        }
        // 同理：提交完成后再解码已存事实，避免长材料跨提交等待。
        tx.commit().await.map_err(storage)?;
        let existing = send_record_from_row(row)?;
        conflict_or_existing(record, existing).map(Some)
    }

    pub async fn save_send(&self, record: &SendRecord) -> Result<(), FeishuError> {
        if let Some(existing) = self.load_send(&record.operation_id).await? {
            conflict_or_existing(record, existing)?;
        }
        let db = self.db().await?;
        db.execute_raw(statement(
            "INSERT INTO send_operations(operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, updated_at, send_identity, send_source)
             VALUES(?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(operation_id) DO UPDATE SET
               status=excluded.status,
               platform_message_ids=excluded.platform_message_ids,
               segment_facts=excluded.segment_facts,
               updated_at=excluded.updated_at",
            vec![
                record.operation_id.clone().into(),
                record.bot_id.clone().into(),
                record.chat_id.clone().into(),
                record.content_hash.clone().into(),
                record.status.as_str().to_string().into(),
                record.platform_message_ids.join(",").into(),
                encode_segment_facts(&record.segments)?.into(),
                unix_seconds().into(),
                encode_send_identity(&record.identity)?.into(),
                encode_send_source(&record.source)?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }

    /// 自动前端仅能接续可证明尚未开始的原阶段；已接受的上传不会再次上传。
    pub(in crate::bots) async fn begin_publication_file_stage(
        &self,
        operation_id: &str,
        permit: &PublicationFilePermit,
        stage: PublicationFileStage,
    ) -> Result<PublicationFileAttempt, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        Self::fence_delivery_file_write(&tx, &permit.token, &permit.entity, operation_id).await?;
        let mut record = publication_send_record_in(&tx, operation_id).await?;
        let fact = record.segments.first_mut().ok_or_else(corrupt_send)?;
        match stage {
            PublicationFileStage::Upload
                if fact.upload == Some(UploadFact::NotStarted)
                    && fact.message_stage == Some(MessageStage::NotStarted) =>
            {
                fact.upload = Some(UploadFact::InFlight);
            }
            PublicationFileStage::Message
                if matches!(fact.upload, Some(UploadFact::Accepted { .. }))
                    && fact.message_stage == Some(MessageStage::NotStarted) =>
            {
                fact.message_stage = Some(MessageStage::InFlight);
            }
            _ => return Err(publication::conflict()),
        }
        fact.stop_reason = None;
        fact.diagnostic = None;
        fact.platform_diagnostic = None;
        refresh_publication_send_status(&mut record);
        write_publication_send_in(&tx, &record).await?;
        sync_publication_send_in(&tx, permit, operation_id).await?;
        tx.commit().await.map_err(storage)?;
        Ok(PublicationFileAttempt {
            permit: permit.clone(),
            record,
            stage,
            request_started: false,
            stopped_before_start: false,
        })
    }

    /// 已有文件操作在请求准备前失败/取消：只可记录真实 NotStarted 阶段，不能清除
    /// 遗留 InFlight/Unknown。没有网络意图时不为本地失败先制造一个意图再撤销。
    pub(in crate::bots) async fn stop_publication_file_before_start(
        &self,
        operation_id: &str,
        permit: &PublicationFilePermit,
        progress: PublicationFileProgress,
    ) -> Result<SendRecord, FeishuError> {
        let PublicationFileProgress::NotStarted { stage, .. } = &progress else {
            return Err(publication::conflict());
        };
        let stage = *stage;
        let tx = self.db().await?.begin().await.map_err(storage)?;
        require_publication_owner_in(&tx, &permit.token).await?;
        let mut record = publication_send_record_in(&tx, operation_id).await?;
        let fact = &record.segments[0];
        let unstarted = match stage {
            PublicationFileStage::Upload => fact.upload == Some(UploadFact::NotStarted),
            PublicationFileStage::Message => fact.message_stage == Some(MessageStage::NotStarted),
        };
        if !unstarted {
            return Err(publication::conflict());
        }
        apply_publication_progress(&mut record, stage, progress)?;
        refresh_publication_send_status(&mut record);
        write_publication_send_in(&tx, &record).await?;
        sync_publication_send_in(&tx, permit, operation_id).await?;
        tx.commit().await.map_err(storage)?;
        Ok(record)
    }

    /// 只合并原阶段结果，不以旧整行快照覆盖另一阶段。真实结果不要求当前授权复活。
    pub(in crate::bots) async fn settle_publication_file_stage(
        &self,
        attempt: &mut PublicationFileAttempt,
        progress: PublicationFileProgress,
    ) -> Result<SendRecord, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let mut record = publication_send_record_in(&tx, &attempt.record.operation_id).await?;
        conflict_or_existing(&attempt.record, record.clone())?;
        if attempt.stopped_before_start {
            return Err(publication::conflict());
        }
        let stopped_before_start = matches!(&progress, PublicationFileProgress::NotStarted { .. });
        if let PublicationFileProgress::NotStarted { stage, .. } = &progress {
            if attempt.request_started || *stage != attempt.stage {
                return Err(publication::conflict());
            }
            require_publication_owner_in(&tx, &attempt.permit.token).await?;
        } else if !attempt.request_started {
            return Err(publication::conflict());
        }
        apply_publication_progress(&mut record, attempt.stage, progress)?;
        refresh_publication_send_status(&mut record);
        write_publication_send_in(&tx, &record).await?;
        sync_publication_send_in(&tx, &attempt.permit, &record.operation_id).await?;
        tx.commit().await.map_err(storage)?;
        attempt.stopped_before_start = stopped_before_start;
        attempt.record = record.clone();
        Ok(record)
    }

    /// Each auxiliary IM POST has a durable stage intent under the same live
    /// inbound/target fence as first claim. Confirmation uses save_send without
    /// this fence so revocation cannot discard an already-started result.
    pub(super) async fn save_reply_send_intent(
        &self,
        record: &SendRecord,
        reply: &reply::InboundReply,
    ) -> Result<(), FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        reply::check(&tx, reply).await?;
        let existing = tx.query_one_raw(statement(
            "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, send_identity, send_source FROM send_operations WHERE operation_id=?",
            vec![record.operation_id.clone().into()],
        )).await.map_err(storage)?.ok_or_else(reply::denied)?;
        conflict_or_existing(record, send_record_from_row(existing)?)?;
        if record.bot_id != reply.source.bot_id || record.chat_id != reply.source.chat_id {
            return Err(reply::denied());
        }
        let updated = tx.execute_raw(statement(
            "UPDATE send_operations SET status=?,platform_message_ids=?,segment_facts=?,updated_at=? WHERE operation_id=?",
            vec![record.status.as_str().into(),record.platform_message_ids.join(",").into(),encode_segment_facts(&record.segments)?.into(),unix_seconds().into(),record.operation_id.clone().into()],
        )).await.map_err(storage)?;
        if updated.rows_affected() != 1 {
            return Err(reply::denied());
        }
        tx.commit().await.map_err(storage)?;
        Ok(())
    }

    pub(crate) async fn has_source_thread(&self, thread_id: &str) -> Result<bool, FeishuError> {
        self.db()
            .await?
            .query_one_raw(statement(
                "SELECT 1 AS present FROM inbound_work WHERE creation_id=? LIMIT 1",
                vec![thread_id.to_owned().into()],
            ))
            .await
            .map(|row| row.is_some())
            .map_err(storage)
    }

    /// Reads one bounded page, retaining every status and failing closed on all stored facts.
    /// One row per page bounds decoded metadata at the same existing send-freeze ceiling;
    /// the maintenance owner separately bounds page count and retains the keyset continuation.
    pub(super) async fn referenced_send_resources(
        &self,
        candidate_ids: &[String],
        continuation: Option<SendResourceReferenceCursor>,
    ) -> Result<SendResourceReferences, FeishuError> {
        if candidate_ids.len() > 128 {
            return Err(corrupt_send());
        }
        if self.writer.get().is_none() {
            match tokio::fs::metadata(&self.path).await {
                Ok(metadata) if metadata.is_file() => {}
                Ok(_) => return Err(corrupt_send()),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Unavailable,
                        "send ledger is missing while resource objects exist; local recovery required",
                        false,
                        None,
                    ));
                }
                Err(error) => return Err(state_failure(error)),
            }
        }
        let db = self.db().await?;
        let mut page = SendResourceReferences {
            referenced: BTreeSet::new(),
            continuation: None,
            query_work: 0,
        };
        let cursor = match continuation {
            Some(cursor) => cursor,
            None => {
                let upper = db
                    .query_one_raw(statement(
                        "SELECT MAX(rowid) AS maximum FROM send_operations",
                        vec![],
                    ))
                    .await
                    .map_err(state_failure)?
                    .ok_or_else(corrupt_send)?;
                page.query_work += 1;
                let Some(through) = upper
                    .try_get::<Option<i64>>("", "maximum")
                    .map_err(|error| corrupt_send().with_source(error))?
                else {
                    return Ok(page);
                };
                SendResourceReferenceCursor {
                    after: None,
                    through,
                }
            }
        };
        let rows = db.query_all_raw(statement(
            "SELECT rowid AS resource_cursor,operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,send_identity,send_source
             FROM send_operations WHERE (?1 IS NULL OR rowid>?1) AND rowid<=?2 ORDER BY rowid LIMIT 1",
            vec![cursor.after.into(), cursor.through.into()],
        )).await.map_err(state_failure)?;
        page.query_work += 1;
        for row in rows {
            let after = row
                .try_get::<i64>("", "resource_cursor")
                .map_err(|error| corrupt_send().with_source(error))?;
            let record = send_record_from_row(row)?;
            if record.identity != SendIdentity::LegacyText && !record.facts_complete {
                return Err(corrupt_send());
            }
            match &record.identity {
                SendIdentity::File { .. }
                    if record.segments.len() != 1
                        || !matches!(
                            record.segments[0].content,
                            Some(SendContent::File { .. })
                        ) =>
                {
                    return Err(corrupt_send());
                }
                SendIdentity::Markdown { .. }
                    if record.segments.is_empty()
                        || record
                            .segments
                            .iter()
                            .any(|segment| segment.content.is_none()) =>
                {
                    return Err(corrupt_send());
                }
                _ => {}
            }
            page.continuation = Some(SendResourceReferenceCursor {
                after: Some(after),
                through: cursor.through,
            });
            for segment in record.segments {
                if let Some(SendContent::File { resource, .. }) = segment.content {
                    crate::resource_store::FileResourceStore::validate_owned_reference(&resource)
                        .map_err(|error| corrupt_send().with_source(error))?;
                    if candidate_ids
                        .iter()
                        .any(|candidate| candidate == resource.id())
                    {
                        page.referenced.insert(resource.id().to_owned());
                    }
                }
            }
        }
        Ok(page)
    }
}

async fn require_publication_owner_in<C: ConnectionTrait>(
    db: &C,
    token: &publication::DeliveryClaimToken,
) -> Result<(), FeishuError> {
    // 只是保存原 owner 的未启动结果，不授予新副作用；关闭授权不抹掉事实，但后继
    // owner 已接管时不能用旧本地停止覆盖其新阶段。
    let held = db.query_one_raw(statement(
        "SELECT 1 FROM bot_delivery_claims WHERE scope_key=? AND owner_id=? AND lease_generation=? AND work_version=?",
        vec![token.scope.storage_key()?.into(), token.owner_id.clone().into(),
            i64::try_from(token.lease_generation).map_err(|_| corrupt_send())?.into(),
            i64::try_from(token.work_version).map_err(|_| corrupt_send())?.into()],
    )).await.map_err(storage)?.is_some();
    if !held {
        return Err(publication::conflict());
    }
    Ok(())
}

async fn publication_send_record_in<C: ConnectionTrait>(
    db: &C,
    operation_id: &str,
) -> Result<SendRecord, FeishuError> {
    let row = db.query_one_raw(statement(
        "SELECT operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,send_identity,send_source FROM send_operations WHERE operation_id=?",
        vec![operation_id.to_string().into()],
    )).await.map_err(storage)?.ok_or_else(corrupt_send)?;
    let record = send_record_from_row(row)?;
    if record.source.is_some()
        || !matches!(record.identity, SendIdentity::File { .. })
        || !record.facts_complete
        || record.segments.len() != 1
        || !matches!(record.segments[0].content, Some(SendContent::File { .. }))
        || record.segments[0].index != 0
        || record.segments[0].uuid.is_empty()
    {
        return Err(corrupt_send());
    }
    Ok(record)
}

async fn write_publication_send_in<C: ConnectionTrait>(
    db: &C,
    record: &SendRecord,
) -> Result<(), FeishuError> {
    let changed = db.execute_raw(statement(
        "UPDATE send_operations SET status=?,platform_message_ids=?,segment_facts=?,updated_at=? WHERE operation_id=?",
        vec![record.status.as_str().into(), record.platform_message_ids.join(",").into(),
            encode_segment_facts(&record.segments)?.into(), unix_seconds().into(), record.operation_id.clone().into()],
    )).await.map_err(storage)?;
    if changed.rows_affected() != 1 {
        return Err(corrupt_send());
    }
    Ok(())
}

async fn sync_publication_send_in<C: ConnectionTrait>(
    db: &C,
    permit: &PublicationFilePermit,
    operation_id: &str,
) -> Result<(), FeishuError> {
    if BotStateStore::settle_delivery_file_result(
        db,
        &permit.token.scope,
        &permit.entity,
        operation_id,
    )
    .await?
        == publication::SettlementOutcome::Superseded
    {
        return Err(publication::conflict());
    }
    Ok(())
}

fn refresh_publication_send_status(record: &mut SendRecord) {
    let fact = &mut record.segments[0];
    let uncertain = matches!(
        fact.upload,
        Some(UploadFact::InFlight | UploadFact::Unknown)
    ) || matches!(
        fact.message_stage,
        Some(MessageStage::InFlight | MessageStage::Unknown)
    );
    let rejected = matches!(fact.upload, Some(UploadFact::Rejected))
        || fact.message_stage == Some(MessageStage::Rejected)
        || fact.stop_reason.is_some();
    let status = if fact.message_stage == Some(MessageStage::Accepted) {
        SendRecordStatus::Succeeded
    } else if uncertain {
        SendRecordStatus::Unknown
    } else if rejected {
        SendRecordStatus::Rejected
    } else {
        SendRecordStatus::Unknown
    };
    fact.status = status;
    record.status = status;
}

fn apply_publication_progress(
    record: &mut SendRecord,
    stage: PublicationFileStage,
    progress: PublicationFileProgress,
) -> Result<(), FeishuError> {
    let fact = record.segments.first_mut().ok_or_else(corrupt_send)?;
    let progress_stage = match &progress {
        PublicationFileProgress::Uploaded { .. } => PublicationFileStage::Upload,
        PublicationFileProgress::Sent { .. } => PublicationFileStage::Message,
        PublicationFileProgress::Rejected { stage, .. }
        | PublicationFileProgress::Unknown { stage, .. }
        | PublicationFileProgress::NotStarted { stage, .. } => *stage,
    };
    if stage != progress_stage {
        return Err(publication::conflict());
    }
    match progress {
        PublicationFileProgress::Uploaded { file_key } => {
            if file_key.is_empty() {
                return Err(publication::conflict());
            }
            match &fact.upload {
                Some(UploadFact::Accepted { file_key: existing }) if *existing == file_key => {
                    return Ok(());
                }
                Some(UploadFact::InFlight | UploadFact::Unknown) => {}
                _ => return Err(publication::conflict()),
            }
            fact.upload = Some(UploadFact::Accepted { file_key });
            fact.stop_reason = None;
            fact.diagnostic = None;
            fact.platform_diagnostic = None;
        }
        PublicationFileProgress::Sent { message_id } => {
            if message_id.is_empty() || !matches!(fact.upload, Some(UploadFact::Accepted { .. })) {
                return Err(publication::conflict());
            }
            match fact.message_stage {
                Some(MessageStage::Accepted)
                    if fact.platform_message_id.as_ref() == Some(&message_id) =>
                {
                    return Ok(());
                }
                Some(MessageStage::InFlight | MessageStage::Unknown) => {}
                _ => return Err(publication::conflict()),
            }
            fact.message_stage = Some(MessageStage::Accepted);
            fact.platform_message_id = Some(message_id.clone());
            record.platform_message_ids = vec![message_id];
            fact.stop_reason = None;
            fact.diagnostic = None;
            fact.platform_diagnostic = None;
        }
        PublicationFileProgress::Rejected { diagnostic, .. } => {
            match stage {
                PublicationFileStage::Upload => match fact.upload {
                    Some(UploadFact::Rejected) => return Ok(()),
                    Some(UploadFact::InFlight | UploadFact::Unknown) => {
                        fact.upload = Some(UploadFact::Rejected)
                    }
                    _ => return Err(publication::conflict()),
                },
                PublicationFileStage::Message => match fact.message_stage {
                    Some(MessageStage::Rejected) => return Ok(()),
                    Some(MessageStage::InFlight | MessageStage::Unknown) => {
                        fact.message_stage = Some(MessageStage::Rejected)
                    }
                    _ => return Err(publication::conflict()),
                },
            }
            fact.diagnostic = Some(diagnostic.message.clone());
            fact.platform_diagnostic = Some(diagnostic);
        }
        PublicationFileProgress::Unknown { diagnostic, .. } => {
            match stage {
                PublicationFileStage::Upload => match fact.upload {
                    Some(UploadFact::Accepted { .. } | UploadFact::Rejected) => return Ok(()),
                    Some(UploadFact::InFlight | UploadFact::Unknown) => {
                        fact.upload = Some(UploadFact::Unknown)
                    }
                    _ => return Err(publication::conflict()),
                },
                PublicationFileStage::Message => match fact.message_stage {
                    Some(MessageStage::Accepted | MessageStage::Rejected) => return Ok(()),
                    Some(MessageStage::InFlight | MessageStage::Unknown) => {
                        fact.message_stage = Some(MessageStage::Unknown)
                    }
                    _ => return Err(publication::conflict()),
                },
            }
            if let Some(diagnostic) = diagnostic {
                fact.diagnostic = Some(diagnostic.message.clone());
                fact.platform_diagnostic = Some(diagnostic);
            }
        }
        PublicationFileProgress::NotStarted {
            reason, diagnostic, ..
        } => {
            match stage {
                PublicationFileStage::Upload => match fact.upload {
                    Some(UploadFact::NotStarted | UploadFact::InFlight) => {
                        fact.upload = Some(UploadFact::NotStarted)
                    }
                    _ => return Err(publication::conflict()),
                },
                PublicationFileStage::Message => match fact.message_stage {
                    Some(MessageStage::NotStarted | MessageStage::InFlight) => {
                        fact.message_stage = Some(MessageStage::NotStarted)
                    }
                    _ => return Err(publication::conflict()),
                },
            }
            fact.stop_reason = Some(reason);
            fact.diagnostic = Some(diagnostic);
            fact.platform_diagnostic = None;
        }
    }
    Ok(())
}

fn inbound_identity(bot_id: &str, chat_id: &str, message_id: &str) -> String {
    format!("{bot_id}:{chat_id}:{message_id}")
}

/// 派生入站身份（`bot:chat:message`）的 UTF-8 字节数，供占用冻结计权使用。
pub(crate) fn inbound_identity_bytes(
    bot_id: &str,
    chat_id: &str,
    message_id: &str,
) -> Result<usize, FeishuError> {
    bot_id
        .len()
        .checked_add(chat_id.len())
        .and_then(|total| total.checked_add(message_id.len()))
        // 两个 ':' 分隔符。
        .and_then(|total| total.checked_add(2))
        .ok_or_else(super::occupancy::freeze_budget_error)
}

/// 分类退避：5 秒起指数增长，封顶 300 秒。
fn retry_backoff_seconds(attempt: i64) -> i64 {
    let shift = attempt.saturating_sub(1).clamp(0, 16) as u32;
    INBOUND_RETRY_BASE_SECONDS
        .saturating_mul(1i64.checked_shl(shift).unwrap_or(INBOUND_RETRY_MAX_SECONDS))
        .min(INBOUND_RETRY_MAX_SECONDS)
}

fn empty_to_none(value: String) -> Option<String> {
    if value.is_empty() { None } else { Some(value) }
}

fn encode_segment_facts(segments: &[SendSegmentFact]) -> Result<String, FeishuError> {
    serde_json::to_string(segments).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("failed to persist send segment facts: {error}"),
            true,
            None,
        )
    })
}

fn encode_send_identity(identity: &SendIdentity) -> Result<String, FeishuError> {
    serde_json::to_string(identity).map_err(storage)
}

fn encode_send_source(source: &Option<SendSource>) -> Result<String, FeishuError> {
    serde_json::to_string(source).map_err(storage)
}

/// Metadata only; resource bytes are held in the shared immutable resource store, not this budget.
pub(crate) fn send_metadata_bytes(record: &SendRecord) -> Result<usize, FeishuError> {
    let bytes = encode_send_identity(&record.identity)?
        .len()
        .checked_add(encode_send_source(&record.source)?.len())
        .ok_or_else(super::occupancy::freeze_budget_error)?;
    bytes
        .checked_mul(3)
        .ok_or_else(super::occupancy::freeze_budget_error)
}

/// 分段事实 JSON 参数的 UTF-8 长度（与持久化编码同一实现），供占用冻结计权使用。
pub(crate) fn segment_facts_bytes(segments: &[SendSegmentFact]) -> Result<usize, FeishuError> {
    Ok(encode_segment_facts(segments)?.len())
}

fn decode_segment_facts(
    raw: &str,
    ids: &[String],
    overall: SendRecordStatus,
) -> Result<(Vec<SendSegmentFact>, bool), FeishuError> {
    // 只有真正空串才是既有 legacy 记录；空白内容属于坏 JSON，不能冒充合法历史事实。
    if raw.is_empty() {
        return Ok(legacy_segment_facts(ids, overall));
    }
    let facts: Vec<SendSegmentFact> = serde_json::from_str(raw).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            "stored send segment facts are unreadable; local recovery required",
            false,
            None,
        )
        .with_source(error)
    })?;
    Ok((facts, true))
}

fn legacy_segment_facts(ids: &[String], overall: SendRecordStatus) -> (Vec<SendSegmentFact>, bool) {
    let diagnostic = Some("legacy send record lacks per-segment facts".to_string());
    let facts = ids
        .iter()
        .enumerate()
        .map(|(index, id)| SendSegmentFact {
            index: index as u32,
            uuid: String::new(),
            status: match overall {
                SendRecordStatus::Succeeded => SendRecordStatus::Succeeded,
                _ => SendRecordStatus::Unknown,
            },
            platform_message_id: Some(id.clone()),
            diagnostic: diagnostic.clone(),
            content: None,
            upload: None,
            message_stage: None,
            notice_attempt: None,
            platform_diagnostic: None,
            stop_reason: None,
        })
        .collect::<Vec<_>>();
    (facts, false)
}

fn send_record_from_row(row: sea_orm::QueryResult) -> Result<SendRecord, FeishuError> {
    let ids_raw = stored_text(&row, "platform_message_ids")?;
    let ids = if ids_raw.is_empty() {
        Vec::new()
    } else {
        ids_raw.split(',').map(str::to_string).collect()
    };
    // 列解码失败不能折叠成 legacy 空事实；真正已存的空串仍走既有迁移分支。
    let facts_raw = stored_text(&row, "segment_facts")?;
    let status = SendRecordStatus::parse(&stored_text(&row, "status")?)?;
    let (segments, facts_complete) = decode_segment_facts(&facts_raw, &ids, status)?;
    Ok(SendRecord {
        operation_id: stored_text(&row, "operation_id")?,
        bot_id: stored_text(&row, "bot_id")?,
        chat_id: stored_text(&row, "chat_id")?,
        content_hash: stored_text(&row, "content_hash")?,
        status,
        platform_message_ids: ids,
        segments,
        facts_complete,
        identity: serde_json::from_str(&stored_text(&row, "send_identity")?)
            .map_err(|error| corrupt_send().with_source(error))?,
        source: serde_json::from_str(&stored_text(&row, "send_source")?)
            .map_err(|error| corrupt_send().with_source(error))?,
    })
}

fn conflict_or_existing(
    record: &SendRecord,
    existing: SendRecord,
) -> Result<SendRecord, FeishuError> {
    verify_send_identity(
        &existing,
        &record.operation_id,
        &record.bot_id,
        &record.chat_id,
        &record.content_hash,
    )?;
    if existing.identity != record.identity || existing.source != record.source {
        return Err(FeishuError::new(
            FeishuErrorKind::Conflict,
            "operationId already used by a different send type or source",
            false,
            None,
        ));
    }
    Ok(existing)
}

fn corrupt_send() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "stored send provenance is unreadable; local recovery required",
        false,
        None,
    )
}

/// 已持久发送记录与本次请求的严格身份核验：相同 operationId 只能是同一机器人、
/// 同一会话与同一正文。只读本地指纹，不涉及联网或凭据。
pub(crate) fn verify_send_identity(
    existing: &SendRecord,
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    content_hash: &str,
) -> Result<(), FeishuError> {
    if existing.operation_id == operation_id
        && existing.bot_id == bot_id
        && existing.chat_id == chat_id
        && existing.content_hash == content_hash
    {
        return Ok(());
    }
    Err(FeishuError::new(
        FeishuErrorKind::Conflict,
        "operationId already used with different content",
        false,
        None,
    ))
}

fn storage(error: impl std::fmt::Display) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("bot state failed: {error:#}"),
        true,
        None,
    )
}

fn state_failure(error: impl Into<anyhow::Error>) -> FeishuError {
    FeishuError::history_read("access bot ledger", error.into())
}

fn statement(sql: &str, values: Vec<Value>) -> Statement {
    Statement::from_sql_and_values(DatabaseBackend::Sqlite, sql, values)
}

/// 绑定记录的关键身份与水位只接受无损解码：损坏或回退默认值会让归属与合并水位失真。
fn strict_text(row: &QueryResult, column: &str) -> Result<String, FeishuError> {
    stored_text(row, column)
}

fn strict_watermark(row: &QueryResult, column: &str) -> Result<u64, FeishuError> {
    let raw = stored_i64(row, column)?;
    u64::try_from(raw).map_err(|_| corrupt_binding())
}

/// 持久字段解码失败：坏类型/坏行是不可恢复的本地事实，不能当作临时 IO 重试。
/// 只用于已取回行的字段解码；查询/执行/提交本身的失败仍按 `storage` 分类为可重试。
fn stored_record_unreadable() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot state record has unreadable persisted fields; local recovery required",
        false,
        None,
    )
}

/// 读取持久文本字段；类型不可解码是固定的本机恢复错误，不回显原值。
fn stored_text(row: &QueryResult, column: &str) -> Result<String, FeishuError> {
    row.try_get("", column)
        .map_err(|_| stored_record_unreadable())
}

/// 读取持久整数/水位字段；类型不可解码同样是固定的本机恢复错误。
fn stored_i64(row: &QueryResult, column: &str) -> Result<i64, FeishuError> {
    row.try_get("", column)
        .map_err(|_| stored_record_unreadable())
}

fn corrupt_binding() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot conversation binding record is unreadable",
        false,
        None,
    )
}

fn stale_binding_revision() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "stale conversation Thread binding revision",
        true,
        None,
    )
}

/// 无法证明归属的既有绑定记录：保留现场，明确报告需本机恢复，不冒充正常进行中。
pub(crate) fn binding_needs_recovery() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "conversation Thread binding needs local recovery: reuse the operation that created it",
        false,
        None,
    )
}

/// 已完成操作的原绑定已被后继显式本地操作替代：固定安全错误。
///
/// 不返回后继操作的结果、不切回旧绑定、不新建，也不靠联网预检改写归属。
pub(crate) fn binding_superseded() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "the conversation Thread binding created by this operation was superseded by a later local operation",
        false,
        None,
    )
}

/// 已受理身份缺少可解码的持久工作行：不从当前请求或配置回填，明确需本机恢复。
fn work_needs_recovery() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "admitted input is missing its durable work record; local recovery required",
        false,
        None,
    )
}

/// 持久工作状态不是已知集合：保留行并要求本机恢复，不当作可重试忙碌。
fn work_state_unreadable() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "admitted input has an unrecognized durable state; local recovery required",
        false,
        None,
    )
}

/// 绑定状态不是已知集合：不能默认投影成 needs_attention。
fn binding_state_unreadable() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "conversation Thread binding state is unreadable; local recovery required",
        false,
        None,
    )
}

/// 在给定连接/事务内写入操作记录；返回是否真正插入（否则已有同 operationId 记录）。
async fn insert_binding_operation<C: ConnectionTrait>(
    db: &C,
    operation: &BindingOperation,
) -> Result<bool, FeishuError> {
    let expected_revision =
        i64::try_from(operation.expected_revision).map_err(|_| corrupt_binding())?;
    let inserted = db
        .execute_raw(statement(
            "INSERT OR IGNORE INTO binding_operations(operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id, updated_at, target_json)
             VALUES(?,?,?,?,?,?,?,?,?)",
            vec![
                operation.operation_id.clone().into(),
                operation.bot_id.clone().into(),
                operation.chat_id.clone().into(),
                operation.content_hash.clone().into(),
                expected_revision.into(),
                operation.creation_id.clone().into(),
                operation.thread_id.clone().unwrap_or_default().into(),
                unix_seconds().into(),
                operation.target.encode()?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
    Ok(inserted.rows_affected() == 1)
}

async fn count_rows(db: &DatabaseConnection, sql: &str) -> Result<i64, FeishuError> {
    let row = db
        .query_one_raw(statement(sql, vec![]))
        .await
        .map_err(storage)?;
    // 占用派生依赖该计数：解码失败必须显式失败，不能当成 0 允许项目变更。
    match &row {
        Some(row) => stored_i64(row, "n"),
        None => Ok(0),
    }
}

async fn open_bot_state(path: &Path) -> Result<DatabaseConnection, FeishuError> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(state_failure)?;
    }
    let parent = path.parent().ok_or_else(|| {
        state_failure(crate::studio::startup::data_error(anyhow::anyhow!(
            "bot database has no parent"
        )))
    })?;
    let filename = path.file_name().ok_or_else(|| {
        state_failure(crate::studio::startup::data_error(anyhow::anyhow!(
            "bot database has no filename"
        )))
    })?;
    let path = tokio::fs::canonicalize(parent)
        .await
        .map_err(state_failure)?
        .join(filename);
    let initialization = {
        let mut locks = INITIALIZATION_LOCKS
            .get_or_init(Mutex::default)
            .lock()
            .map_err(|_| {
                state_failure(crate::studio::startup::data_error(anyhow::anyhow!(
                    "bot database initialization lock failed"
                )))
            })?;
        locks.retain(|_, lock| lock.strong_count() > 0);
        match locks.get(&path).and_then(Weak::upgrade) {
            Some(lock) => lock,
            None => {
                let lock = Arc::new(tokio::sync::Mutex::new(()));
                locks.insert(path.clone(), Arc::downgrade(&lock));
                lock
            }
        }
    };
    let _initialization = initialization.lock().await;
    schema::inspect_existing(&path)
        .await
        .map_err(state_failure)?;
    // Exclusive file creation, not an empty-schema heuristic, establishes new ownership. An
    // interrupted attempt leaves its file for local recovery; a later open cannot claim it anew.
    let origin = match tokio::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .await
    {
        Ok(_) => DatabaseOrigin::Created,
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => DatabaseOrigin::Existing,
        Err(error) => return Err(state_failure(error)),
    };
    let mut options = sqlite_file_options(&path, SqliteFileMode::Create, |options| {
        options
            // The file is already owned or existing. Never silently recreate a disappeared DB.
            .create_if_missing(false)
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Full)
            .busy_timeout(Duration::from_secs(5))
            .foreign_keys(true)
    })
    .await
    .map_err(state_failure)?;
    options
        .max_connections(1)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    let db = Database::connect(options).await.map_err(state_failure)?;
    if let Err(error) = schema::initialize(&db, origin).await {
        let _ = db.close().await;
        return Err(state_failure(error));
    }
    Ok(db)
}

/// Version and complete required structures jointly identify the known divergent schemas.
/// A partial file marker can never be treated as a main card/text schema.
async fn validate_ledger_schema<C: ConnectionTrait>(
    db: &C,
    source: LedgerSource,
) -> anyhow::Result<()> {
    legacy_schema::validate_source(db, source).await
}

async fn migrate<C: ConnectionTrait>(db: &C, version: i64) -> anyhow::Result<()> {
    card::migrate(db).await?;
    db.execute_unprepared(
        "CREATE UNIQUE INDEX IF NOT EXISTS pairing_open_id ON pairing_requests(open_id)",
    )
    .await?;
    ensure_column(
        db,
        "inbound_identities",
        "bot_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(db, "inbound_work", "bot_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "chat_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "message_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "content_hash",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(db, "inbound_work", "text", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "attachments",
        "TEXT NOT NULL DEFAULT '[]'",
    )
    .await?;
    ensure_column(db, "inbound_work", "open_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "chat_kind", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "generation",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "inbound_work", "app_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "project_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "creation_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "binding_revision",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "inbound_work", "claimed_by", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "claimed_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "watch_input",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "attempt_count",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "next_attempt_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "status",
        "TEXT NOT NULL DEFAULT 'bound'",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "creation_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "project_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "revision",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "generation",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "diagnostic",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "updated_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "send_operations", "bot_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "send_operations",
        "segment_facts",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "send_operations",
        "send_identity",
        "TEXT NOT NULL DEFAULT '{\"kind\":\"legacyText\"}'",
    )
    .await?;
    ensure_column(
        db,
        "send_operations",
        "send_source",
        "TEXT NOT NULL DEFAULT 'null'",
    )
    .await?;
    db.execute_unprepared(
        "CREATE INDEX IF NOT EXISTS inbound_source_creation ON inbound_work(creation_id, status)",
    )
    .await?;
    if version < 6 {
        migrate_text_send_facts(db).await?;
    }
    if version < 7 {
        migrate_send_stages(db).await?;
    }
    // 旧 pending 与“creating 但缺创建身份”的行一律规范为 needs_attention：
    // 不从 thread_id 反推创建身份，运行时也不再重新兼容这两种值。
    db.execute_unprepared(
        "UPDATE thread_bindings
         SET status='needs_attention',
             diagnostic='legacy pending binding requires local recreate',
             revision=CASE WHEN revision=0 THEN 1 ELSE revision END
         WHERE thread_id='pending' OR status='pending' OR (status='creating' AND creation_id='')",
    )
    .await?;
    db.execute_unprepared(
        "UPDATE inbound_work
         SET status='needs_attention',
             diagnostic='legacy inbound lacks frozen binding identity'
         WHERE status IN ('pending','claimed','failed')
           AND (creation_id='' OR app_id='' OR project_id='')",
    )
    .await?;
    db.execute_unprepared(
        "UPDATE thread_bindings SET revision=1, generation=1 WHERE revision=0 AND status='bound'",
    )
    .await?;
    db.execute_raw(statement(
        "INSERT INTO bot_meta(id, schema_version) VALUES(1, ?)
         ON CONFLICT(id) DO UPDATE SET schema_version=excluded.schema_version",
        // This helper establishes the complete C1 representation only. Its caller performs the
        // distinct audience migration before recording current schema nine in the same transaction.
        vec![8i64.into()],
    ))
    .await?;
    Ok(())
}

/// v1..v5 stored snake_case segment fields and only text sends. Preserve their exact hashes,
/// outcome/provenance and UUIDs; only the JSON schema is rewritten inside this transaction.
async fn migrate_text_send_facts<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct OldSegment {
        index: u32,
        uuid: String,
        status: SendRecordStatus,
        platform_message_id: Option<String>,
        diagnostic: Option<String>,
    }
    let mut after = String::new();
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT operation_id, segment_facts FROM send_operations WHERE operation_id>? ORDER BY operation_id LIMIT 64",
            vec![after.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let operation: String = row.try_get("", "operation_id")?;
            let raw: String = row.try_get("", "segment_facts")?;
            if !raw.is_empty() {
                let old: Vec<OldSegment> = serde_json::from_str(&raw)?;
                let facts = old
                    .into_iter()
                    .map(|old| SendSegmentFact {
                        index: old.index,
                        uuid: old.uuid,
                        status: old.status,
                        platform_message_id: old.platform_message_id,
                        diagnostic: old.diagnostic,
                        content: None,
                        upload: None,
                        message_stage: None,
                        notice_attempt: None,
                        platform_diagnostic: None,
                        stop_reason: None,
                    })
                    .collect::<Vec<_>>();
                db.execute_raw(statement(
                    "UPDATE send_operations SET segment_facts=? WHERE operation_id=?",
                    vec![
                        serde_json::to_string(&facts)?.into(),
                        operation.clone().into(),
                    ],
                ))
                .await?;
            }
            after = operation;
        }
    }
    Ok(())
}

/// v6 mixed application failure with platform rejection. Correct only proven old local paths;
/// missing historical evidence becomes Unknown, never invented NotStarted.
async fn migrate_send_stages<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = String::new();
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT operation_id, segment_facts, send_identity, platform_message_ids FROM send_operations WHERE operation_id>? ORDER BY operation_id LIMIT 64",
            vec![after.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let operation: String = row.try_get("", "operation_id")?;
            let raw: String = row.try_get("", "segment_facts")?;
            if !raw.is_empty() {
                let identity: SendIdentity =
                    serde_json::from_str(&row.try_get::<String>("", "send_identity")?)?;
                let mut facts: Vec<SendSegmentFact> = serde_json::from_str(&raw)?;
                let mut repaired_stop = false;
                for fact in &mut facts {
                    repaired_stop |=
                        migrate_stage_fact(fact, matches!(identity, SendIdentity::File { .. }));
                }
                let new_status = if repaired_stop {
                    Some(
                        if facts.iter().any(|fact| {
                            matches!(
                                fact.upload,
                                Some(UploadFact::Unknown | UploadFact::InFlight)
                            ) || matches!(
                                fact.message_stage,
                                Some(MessageStage::Unknown | MessageStage::InFlight)
                            )
                        }) {
                            "unknown"
                        } else if row
                            .try_get::<String>("", "platform_message_ids")?
                            .is_empty()
                        {
                            "rejected"
                        } else {
                            "partial"
                        },
                    )
                } else {
                    None
                };
                db.execute_raw(statement(
                    "UPDATE send_operations SET segment_facts=?, status=COALESCE(?,status) WHERE operation_id=?",
                    vec![serde_json::to_string(&facts)?.into(), new_status.map(str::to_owned).into(), operation.clone().into()],
                )).await?;
            }
            after = operation;
        }
    }
    Ok(())
}

fn migrate_stage_fact(fact: &mut SendSegmentFact, file_operation: bool) -> bool {
    use pl_protocol::studio::BotSendStopReason;
    let file = file_operation
        || fact.upload.is_some()
        || matches!(fact.content, Some(SendContent::File { .. }));
    if file && fact.upload.is_none() {
        fact.upload = Some(UploadFact::Unknown);
    }
    if fact.message_stage.is_none() {
        fact.message_stage = Some(
            if fact
                .platform_message_id
                .as_ref()
                .is_some_and(|id| !id.is_empty())
            {
                MessageStage::Accepted
            } else {
                MessageStage::Unknown
            },
        );
    }
    let diagnostic = fact.diagnostic.as_deref().unwrap_or_default();
    let cancelled = diagnostic
        == "send cancelled before the next network write; earlier stages retain their recorded result";
    let local = matches!(
        diagnostic,
        "retained send resource is unavailable or invalid"
            | "outgoing file byte budget is full"
            | "invalid upload media type"
            | "file upload requires 1..=30,000,000 bytes"
            | "complete message HTTP JSON exceeds 30,000 UTF-8 bytes"
            | "post content exceeds 30,000 UTF-8 bytes"
            | "send uuid exceeds 50 characters"
    );
    if cancelled || local {
        if matches!(
            fact.upload,
            Some(UploadFact::Rejected | UploadFact::Unknown)
        ) {
            fact.upload = Some(UploadFact::NotStarted);
        }
        if fact.message_stage == Some(MessageStage::Rejected) {
            fact.message_stage = Some(MessageStage::NotStarted);
        }
        fact.stop_reason = Some(if cancelled {
            BotSendStopReason::Cancelled
        } else {
            BotSendStopReason::LocalFailure
        });
        fact.platform_diagnostic = None;
        fact.status = SendRecordStatus::Rejected;
        return true;
    }
    if matches!(
        diagnostic,
        "消息资源超过单文件或批次字节预算"
            | "Feishu HTTP service is unavailable"
            | "Feishu HTTP request failed"
    ) {
        if fact.upload == Some(UploadFact::Rejected) {
            fact.upload = Some(UploadFact::Unknown);
        }
        if fact.message_stage == Some(MessageStage::Rejected) {
            fact.message_stage = Some(MessageStage::Unknown);
        }
        if diagnostic == "消息资源超过单文件或批次字节预算" {
            fact.platform_diagnostic = None;
            fact.diagnostic = Some(
                "legacy POST response exceeded the local body budget; result is unknown".into(),
            );
        }
        fact.status = SendRecordStatus::Unknown;
        return true;
    }
    // A v6 Rejected without a platform code has no proof that a POST was rejected remotely.
    if fact
        .platform_diagnostic
        .as_ref()
        .and_then(|d| d.platform_code.as_ref())
        .is_none()
    {
        let mut changed = false;
        if fact.upload == Some(UploadFact::Rejected) {
            fact.upload = Some(UploadFact::Unknown);
            changed = true;
        }
        if fact.message_stage == Some(MessageStage::Rejected) {
            fact.message_stage = Some(MessageStage::Unknown);
            changed = true;
        }
        if changed {
            fact.status = SendRecordStatus::Unknown;
        }
        return changed;
    }
    false
}

async fn ensure_column<C: ConnectionTrait>(
    db: &C,
    table: &str,
    column: &str,
    decl: &str,
) -> anyhow::Result<()> {
    if !table_columns(db, table).await?.contains(column) {
        db.execute_unprepared(&format!("ALTER TABLE {table} ADD COLUMN {column} {decl}"))
            .await?;
    }
    Ok(())
}

async fn table_columns<C: ConnectionTrait>(
    db: &C,
    table: &str,
) -> anyhow::Result<BTreeSet<String>> {
    db.query_all_raw(statement(&format!("PRAGMA table_info({table})"), vec![]))
        .await?
        .into_iter()
        .map(|row| row.try_get::<String>("", "name"))
        .collect::<Result<BTreeSet<_>, _>>()
        .map_err(crate::studio::startup::data_error)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---- 首绑 / 首次授权 / 撤权 / 接续的持久状态不变量 ----
    //
    // 这些用例只断言 bot 状态库里可核对的持久事实（路由、授权头、代次、幂等与
    // 失败/就绪预算），与上面的迁移、历史保存与恢复故障测试同风格；只能通过真实
    // 平台行为观察的部分（下载次数、CardKit 语义）由 `bots_protocol_observe` 的
    // 对应用例证明，不在这里用 runtime 单测表达。
    use crate::bots::audience::{first_start, permission_close_reason, prepare_permission};
    use crate::bots::config::{
        BOT_CONFIG_SCHEMA_VERSION, BotConfigFile, BotPlatformConfig, FeishuBotConfig,
    };
    use crate::bots::protocol::error::FeishuErrorKind;
    use crate::bots::storage::audience::Authorization;
    use crate::bots::storage::target::{TargetClaim, TargetKind};
    use crate::studio::audience_start::{AudienceStartIntent, AudienceStartReceipt};
    use crate::studio::thread_audience::BotThreadInputReadiness;
    use pl_protocol::studio::{
        BotAuthorizationPhase, BotThreadSyncAction, ChangeBotThreadSyncRequest,
    };
    use pl_protocol::{BotAudienceCloseReason, BotAuthorizationHead, BotSyncCas};

    const BOT: &str = "botfixture";
    const CHAT: &str = "chat-1";
    const THREAD: &str = "thread-1";
    const PROJECT: &str = "project";
    const APP: &str = "app";

    #[cfg(unix)]
    fn resource_claim(
        operation: &str,
        resource: pl_core::context::ResourceReference,
    ) -> SendRecord {
        SendRecord {
            operation_id: operation.into(),
            bot_id: "recovery-bot".into(),
            chat_id: "chat".into(),
            content_hash: format!("claim-{operation}"),
            status: SendRecordStatus::Unknown,
            platform_message_ids: Vec::new(),
            facts_complete: true,
            identity: SendIdentity::File {
                request_hash: operation.into(),
            },
            source: None,
            segments: vec![SendSegmentFact {
                index: 0,
                uuid: "persisted-before-crash".into(),
                status: SendRecordStatus::Unknown,
                platform_message_id: None,
                diagnostic: None,
                content: Some(SendContent::File {
                    filename: "original.bin".into(),
                    upload_filename: "original.bin".into(),
                    resource,
                }),
                upload: Some(UploadFact::NotStarted),
                message_stage: Some(MessageStage::NotStarted),
                notice_attempt: None,
                platform_diagnostic: None,
                stop_reason: None,
            }],
        }
    }

    /// A real schema-loss fault must not turn an existing database into an empty reference proof.
    #[cfg(unix)]
    #[tokio::test]
    async fn existing_schema_loss_preserves_resources_instead_of_reinitializing_the_ledger()
    -> Result<(), Box<dyn std::error::Error>> {
        use crate::resource_store::FileResourceStore;
        use pl_core::context::ResourceReader;
        use std::sync::Arc;

        for version in [6, 7, 8] {
            for (name, fault) in [
                (
                    "file-facts-and-identity",
                    "ALTER TABLE send_operations DROP COLUMN segment_facts;
                 ALTER TABLE send_operations DROP COLUMN send_identity",
                ),
                (
                    "file-facts",
                    "ALTER TABLE send_operations DROP COLUMN segment_facts",
                ),
                (
                    "file-identity",
                    "ALTER TABLE send_operations DROP COLUMN send_identity",
                ),
                (
                    "file-source",
                    "ALTER TABLE send_operations DROP COLUMN send_source",
                ),
                (
                    "send-base",
                    "ALTER TABLE send_operations DROP COLUMN chat_id",
                ),
                (
                    "inbound-attachments",
                    "ALTER TABLE inbound_work DROP COLUMN attachments",
                ),
                ("other-required-table", "DROP TABLE observed_directs"),
                (
                    "metadata-version-column",
                    "ALTER TABLE bot_meta DROP COLUMN schema_version",
                ),
                ("metadata-version-row", "DELETE FROM bot_meta WHERE id=1"),
                (
                    "invalid-version",
                    "UPDATE bot_meta SET schema_version=-1 WHERE id=1",
                ),
                ("both", "DROP TABLE bot_meta; DROP TABLE send_operations"),
                ("metadata", "DROP TABLE bot_meta"),
                ("ledger", "DROP TABLE send_operations"),
            ] {
                let directory = tempfile::tempdir()?;
                let path = directory.path().join("state.sqlite");
                let first = BotStateStore::new(path.clone());
                first.db().await?;
                let resources = FileResourceStore::new(directory.path().join("send-resources"));
                let reference = resources
                    .retain_bytes(
                        Arc::from(b"committed original".as_slice()),
                        "application/octet-stream",
                    )
                    .await?;
                first
                    .claim_send(&resource_claim("original", reference.clone()))
                    .await?;
                let db = first.db().await?;
                if version < 8 {
                    db.execute_unprepared("DROP TABLE bot_card_streams").await?;
                }
                db.execute_raw(statement(
                    "UPDATE bot_meta SET schema_version=? WHERE id=1",
                    vec![version.into()],
                ))
                .await?;
                db.execute_unprepared(fault).await?;
                let schema_before = db
                    .query_all_raw(statement(
                        "SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name",
                        vec![],
                    ))
                    .await?
                    .into_iter()
                    .map(|row| -> Result<_, sea_orm::DbErr> {
                        Ok((
                            row.try_get::<String>("", "name")?,
                            row.try_get::<String>("", "sql")?,
                        ))
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                assert!(
                    schema_before
                        .iter()
                        .any(|(name, _)| name == "thread_bindings")
                );
                let mut recovery =
                    super::super::send_resources::SendResources::new(resources.clone());
                let reopened = BotStateStore::new(path);
                let error = recovery
                    .maintain(&reopened)
                    .await
                    .expect_err(&format!("v{version}/{name}"));
                assert!(!error.retryable(), "schema loss requires local recovery");
                assert!(recovery.needs_maintenance());
                assert_eq!(
                    resources
                        .read(reference, Default::default())
                        .await?
                        .as_ref(),
                    b"committed original"
                );
                let schema_after = db
                    .query_all_raw(statement(
                        "SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name",
                        vec![],
                    ))
                    .await?
                    .into_iter()
                    .map(|row| -> Result<_, sea_orm::DbErr> {
                        Ok((
                            row.try_get::<String>("", "name")?,
                            row.try_get::<String>("", "sql")?,
                        ))
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                assert_eq!(
                    schema_before, schema_after,
                    "recovery must not recreate tables or synthesize missing columns"
                );
            }
        }

        // An interrupted/unknown empty file is existing state, not proof of fresh ownership.
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("state.sqlite");
        std::fs::write(&path, [])?;
        assert!(
            !BotStateStore::new(path)
                .db()
                .await
                .err()
                .ok_or("existing empty DB was recreated")?
                .retryable()
        );
        let concurrent_path = directory.path().join("concurrent-new.sqlite");
        let first = BotStateStore::new(concurrent_path.clone());
        let concurrent = BotStateStore::new(concurrent_path);
        let (a, b) = tokio::join!(first.db(), concurrent.db());
        a?;
        b?;
        Ok(())
    }

    /// A complete column list is not proof of the constraints used by dedup/CAS.
    /// Rebuild actual SQLite tables (not a mocked metadata helper), then enter
    /// through a fresh store and prove rejection leaves schema, version and rows intact.
    #[tokio::test]
    async fn incompatible_constraints_preserve_the_original_database()
    -> Result<(), Box<dyn std::error::Error>> {
        for source in ["main6", "file6", "file7", "current8", "text3", "text5"] {
            for (table, from, to) in [
                ("pairing_requests", "unique", "missing"),
                ("pairing_requests", "unique", "composite"),
                ("pairing_requests", "unique", "partial"),
                (
                    "inbound_identities",
                    "identity TEXT PRIMARY KEY",
                    "identity TEXT",
                ),
                ("inbound_work", "identity TEXT PRIMARY KEY", "identity TEXT"),
                (
                    "thread_bindings",
                    "chat_id TEXT PRIMARY KEY",
                    "chat_id TEXT",
                ),
                (
                    "observed_directs",
                    "chat_id TEXT PRIMARY KEY",
                    "chat_id TEXT",
                ),
                (
                    "pairing_requests",
                    "request_id TEXT PRIMARY KEY",
                    "request_id TEXT",
                ),
                (
                    "send_operations",
                    "operation_id TEXT PRIMARY KEY",
                    "operation_id TEXT",
                ),
                (
                    "binding_operations",
                    "operation_id TEXT PRIMARY KEY",
                    "operation_id TEXT",
                ),
                ("bot_meta", "id INTEGER PRIMARY KEY", "id INTEGER"),
                ("bot_meta", "CHECK (id = 1)", ""),
                ("bot_meta", "CHECK (id = 1)", "CHECK(id IN (1,2))"),
                (
                    "bot_card_streams",
                    "identity TEXT PRIMARY KEY",
                    "identity TEXT",
                ),
                (
                    "bot_card_streams",
                    "identity TEXT PRIMARY KEY",
                    "identity TEXT UNIQUE",
                ),
                ("bot_card_streams", "CHECK(version>0)", ""),
                ("bot_card_streams", "CHECK(version>0)", "CHECK(version>=0)"),
                ("observed_directs", "open_id TEXT NOT NULL", "open_id TEXT"),
                (
                    "observed_directs",
                    "last_observed_at INTEGER NOT NULL",
                    "last_observed_at TEXT NOT NULL",
                ),
            ] {
                let text_source = source.starts_with("text");
                // The declared pre6 migration establishes this index/card table;
                // absent constraints there are not a fabricated current schema.
                if text_source
                    && (from == "unique" && to == "missing" || table == "bot_card_streams")
                    || matches!(source, "file6" | "file7") && table == "bot_card_streams"
                {
                    continue;
                }
                let directory = tempfile::tempdir()?;
                let path = directory.path().join("constraints.sqlite");
                let db = if text_source {
                    let db = v3_database(&path).await;
                    if source == "text5" {
                        db.execute_unprepared("UPDATE bot_meta SET schema_version=5")
                            .await?;
                    }
                    db
                } else {
                    let store = BotStateStore::new(path.clone());
                    let db = store.db().await?.clone();
                    if matches!(source, "main6" | "file6" | "file7") {
                        remove_schema9_fixture(&db).await?;
                    }
                    match source {
                        "main6" => {
                            db.execute_unprepared("ALTER TABLE send_operations DROP COLUMN send_identity; ALTER TABLE send_operations DROP COLUMN send_source; UPDATE bot_meta SET schema_version=6").await?;
                        }
                        "file6" | "file7" => {
                            db.execute_unprepared(&format!("DROP TABLE bot_card_streams; UPDATE bot_meta SET schema_version={}", if source == "file6" { 6 } else { 7 })).await?;
                        }
                        _ => {}
                    }
                    db
                };
                db.execute_unprepared("INSERT INTO observed_directs VALUES('preserved-chat','original-open','original-name',42)").await?;
                if from == "unique" {
                    db.execute_unprepared("DROP INDEX IF EXISTS pairing_open_id")
                        .await?;
                    match to {
                        "composite" => {
                            db.execute_unprepared("CREATE UNIQUE INDEX pairing_open_id ON pairing_requests(open_id,request_id)").await?;
                        }
                        "partial" => {
                            db.execute_unprepared("CREATE UNIQUE INDEX pairing_open_id ON pairing_requests(open_id) WHERE created_at>0").await?;
                        }
                        _ => {}
                    }
                } else {
                    let ddl: String = db
                        .query_one_raw(statement(
                            "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                            vec![table.into()],
                        ))
                        .await?
                        .unwrap()
                        .try_get("", "sql")?;
                    let replaced = ddl.replace(from, to);
                    assert_ne!(
                        ddl, replaced,
                        "fault must change the real declaration: {source}/{table}/{from}"
                    );
                    let indices = db.query_all_raw(statement("SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name=? AND sql IS NOT NULL", vec![table.into()])).await?;
                    db.execute_unprepared(&format!("ALTER TABLE {table} RENAME TO damaged_table; {replaced}; INSERT INTO {table} SELECT * FROM damaged_table; DROP TABLE damaged_table;")).await?;
                    for row in indices {
                        db.execute_unprepared(&row.try_get::<String>("", "sql")?)
                            .await?;
                    }
                }
                let snapshot = |db: DatabaseConnection| async move {
                    let schema = db.query_all_raw(statement("SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name", vec![])).await?.into_iter().map(|row| Ok((row.try_get::<String>("", "name")?, row.try_get::<String>("", "sql")?))).collect::<Result<Vec<_>, sea_orm::DbErr>>()?;
                    let version: i64 = db
                        .query_one_raw(statement(
                            "SELECT schema_version FROM bot_meta WHERE id=1",
                            vec![],
                        ))
                        .await?
                        .unwrap()
                        .try_get("", "schema_version")?;
                    let row = db.query_one_raw(statement("SELECT open_id,name FROM observed_directs WHERE chat_id='preserved-chat'", vec![])).await?.unwrap();
                    Ok::<_, sea_orm::DbErr>((
                        schema,
                        version,
                        row.try_get::<String>("", "open_id")?,
                        row.try_get::<String>("", "name")?,
                    ))
                };
                let before = snapshot(db.clone()).await?;
                let result = BotStateStore::new(path).load_send("absent").await;
                assert!(
                    result.is_err(),
                    "accepted broken constraints: {source}/{table}/{from}/{to}"
                );
                assert!(!result.err().unwrap().retryable());
                assert_eq!(
                    before,
                    snapshot(db).await?,
                    "failed open must preserve the original database"
                );
            }
        }
        Ok(())
    }

    /// Real persisted claims survive process reconstruction; corrupt ledger facts prevent unlink,
    /// and bounded recovery advances past >1024 referenced entries rather than rescanning a prefix.
    #[cfg(unix)]
    #[tokio::test]
    async fn send_resource_recovery_preserves_shared_claims_and_resumes_bounded_work()
    -> Result<(), Box<dyn std::error::Error>> {
        use crate::resource_store::FileResourceStore;
        use pl_core::context::ResourceReader;
        use std::collections::BTreeMap;
        use std::sync::Arc;
        let directory = tempfile::tempdir()?;
        let home = directory.path().join("physical-home");
        let alias = directory.path().join("home-alias");
        std::fs::create_dir(&home)?;
        std::os::unix::fs::symlink(&home, &alias)?;
        let root = alias.join("send-resources");
        let resources = FileResourceStore::beneath(alias.clone(), root.clone());
        let mut retained = BTreeMap::new();
        for index in 0_u32..1040 {
            let reference = resources
                .retain_bytes(
                    Arc::from(index.to_le_bytes().to_vec()),
                    "application/octet-stream",
                )
                .await?;
            retained.insert(reference.id().to_owned(), reference);
        }
        let mut scan = None;
        let mut order = Vec::new();
        loop {
            let batch = resources.owned_batch(scan, 128).await?;
            order.extend(
                batch
                    .objects
                    .iter()
                    .filter_map(|object| object.resource_id().map(str::to_owned)),
            );
            scan = batch.continuation;
            if scan.is_none() {
                break;
            }
        }
        assert_eq!(order.len(), 1040);
        let path = alias.join("state.sqlite");
        let ledger = BotStateStore::new(path.clone());
        let mut original = None;
        for (index, id) in order.iter().take(1024).enumerate() {
            let record = resource_claim(&format!("op-{index:04}"), retained[id].clone());
            assert!(ledger.claim_send(&record).await?.is_none());
            if index == 0 {
                original = Some(record);
            }
        }
        let original = original.ok_or("missing initial claim")?;
        let shared = resource_claim("shared-second-operation", retained[&order[0]].clone());
        assert!(ledger.claim_send(&shared).await?.is_none());
        // A failed/cancelled unclaimed retain with identical bytes has no extra ref row.
        let same = resources
            .retain_bytes(
                Arc::from(
                    resources
                        .read(retained[&order[0]].clone(), Default::default())
                        .await?
                        .as_ref(),
                ),
                "application/octet-stream",
            )
            .await?;
        assert_eq!(same.id(), order[0]);
        ledger
            .db()
            .await?
            .execute_raw(statement(
                "UPDATE send_operations SET segment_facts='{}' WHERE operation_id=?",
                vec![original.operation_id.clone().into()],
            ))
            .await?;
        let mut recovery = super::super::send_resources::SendResources::new(
            FileResourceStore::beneath(alias, root),
        );
        let failure = recovery
            .maintain(&ledger)
            .await
            .expect_err("bad ledger must not prove absence of references");
        assert!(!failure.retryable());
        assert!(
            resources
                .read(retained[&order[1039]].clone(), Default::default())
                .await
                .is_ok(),
            "dirty ledger must leave orphan bytes untouched"
        );
        // Explicitly repair only the injected bytes from the previously frozen real record;
        // normal save_send intentionally refuses to overwrite an unreadable persisted row.
        ledger
            .db()
            .await?
            .execute_raw(statement(
                "UPDATE send_operations SET segment_facts=? WHERE operation_id=?",
                vec![
                    serde_json::to_string(&original.segments)?.into(),
                    original.operation_id.clone().into(),
                ],
            ))
            .await?;
        drop(ledger);
        let reopened = BotStateStore::new(path);
        let mut jobs = 0;
        loop {
            jobs += 1;
            match recovery.maintain(&reopened).await {
                Ok(()) => break,
                Err(error) if error.kind() == FeishuErrorKind::Busy && jobs < 600 => {}
                Err(error) => return Err(error.into()),
            }
        }
        assert!(
            jobs > 2,
            "fixture must cross maintenance scan/query budgets"
        );
        for id in order.iter().take(1024) {
            assert!(
                resources
                    .read(retained[id].clone(), Default::default())
                    .await
                    .is_ok(),
                "referenced bytes must remain"
            );
        }
        for id in order.iter().skip(1024) {
            assert!(
                resources
                    .read(retained[id].clone(), Default::default())
                    .await
                    .is_err(),
                "unclaimed crash residue must be removed"
            );
        }
        assert!(reopened.load_send(&original.operation_id).await?.is_some());
        assert!(reopened.load_send(&shared.operation_id).await?.is_some());
        Ok(())
    }

    /// 直接以 v3 形态建库并塞入真实业务行：一条远古过期 claimed 的 work、
    /// 一个 bound 绑定与一条发送事实，用于验证 v4 迁移的真实保全与 lease 语义。
    async fn v3_database(path: &Path) -> DatabaseConnection {
        let mut options = sqlite_file_options(path, SqliteFileMode::Create, |options| options)
            .await
            .unwrap();
        options.max_connections(1);
        let db = Database::connect(options).await.unwrap();
        db.execute_unprepared(
            "CREATE TABLE bot_meta (id INTEGER PRIMARY KEY CHECK (id = 1), schema_version INTEGER NOT NULL);
             INSERT INTO bot_meta(id, schema_version) VALUES(1, 3);
             CREATE TABLE inbound_identities (
                identity TEXT PRIMARY KEY, bot_id TEXT NOT NULL DEFAULT '',
                message_id TEXT NOT NULL, chat_id TEXT NOT NULL,
                content_hash TEXT NOT NULL, admitted_at INTEGER NOT NULL);
             CREATE TABLE inbound_work (
                identity TEXT PRIMARY KEY, bot_id TEXT NOT NULL DEFAULT '',
                chat_id TEXT NOT NULL DEFAULT '', message_id TEXT NOT NULL DEFAULT '',
                content_hash TEXT NOT NULL DEFAULT '', text TEXT NOT NULL DEFAULT '',
                open_id TEXT NOT NULL DEFAULT '', chat_kind TEXT NOT NULL DEFAULT '',
                generation INTEGER NOT NULL DEFAULT 0, app_id TEXT NOT NULL DEFAULT '',
                project_id TEXT NOT NULL DEFAULT '', creation_id TEXT NOT NULL DEFAULT '',
                binding_revision INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL,
                diagnostic TEXT NOT NULL, claimed_by TEXT NOT NULL DEFAULT '',
                claimed_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL);
             CREATE TABLE thread_bindings (
                chat_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'bound', creation_id TEXT NOT NULL DEFAULT '',
                project_id TEXT NOT NULL DEFAULT '', revision INTEGER NOT NULL DEFAULT 0,
                generation INTEGER NOT NULL DEFAULT 0, diagnostic TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0);
             CREATE TABLE observed_directs (
                chat_id TEXT PRIMARY KEY, open_id TEXT NOT NULL, name TEXT NOT NULL,
                last_observed_at INTEGER NOT NULL);
             CREATE TABLE pairing_requests (
                request_id TEXT PRIMARY KEY, open_id TEXT NOT NULL,
                display_name TEXT NOT NULL, created_at INTEGER NOT NULL);
             CREATE TABLE send_operations (
                operation_id TEXT PRIMARY KEY, bot_id TEXT NOT NULL DEFAULT '',
                chat_id TEXT NOT NULL, content_hash TEXT NOT NULL, status TEXT NOT NULL,
                platform_message_ids TEXT NOT NULL, updated_at INTEGER NOT NULL);
             CREATE TABLE binding_operations (
                operation_id TEXT PRIMARY KEY, bot_id TEXT NOT NULL, chat_id TEXT NOT NULL,
                content_hash TEXT NOT NULL, expected_revision INTEGER NOT NULL,
                creation_id TEXT NOT NULL, thread_id TEXT NOT NULL DEFAULT '',
                updated_at INTEGER NOT NULL);
             INSERT INTO inbound_identities(identity, bot_id, message_id, chat_id, content_hash, admitted_at)
             VALUES('legacy:chat:m1', 'legacy', 'm1', 'chat', 'hash', 1);
             INSERT INTO inbound_work(identity, bot_id, chat_id, message_id, content_hash, text,
               open_id, chat_kind, app_id, project_id, creation_id, binding_revision, status,
               diagnostic, claimed_by, claimed_at, updated_at)
             VALUES('legacy:chat:m1', 'legacy', 'chat', 'm1', 'hash', 'question',
               'open', 'direct', 'app', 'project', 'botthread:legacy:chat', 1, 'claimed',
               '', 'crashed-worker', 1, 1);
             INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id,
               revision, generation, diagnostic, created_at, updated_at)
             VALUES('chat', 'thread-1', 'bound', 'botthread:legacy:chat', 'project', 1, 1, '', 1, 1);
             INSERT INTO send_operations(operation_id, bot_id, chat_id, content_hash, status,
               platform_message_ids, updated_at)
             VALUES('op-1', 'legacy', 'chat', 'hash', 'succeeded', 'pm-1', 1);",
        )
        .await
        .unwrap();
        db
    }

    async fn work_status(store: &BotStateStore, identity: &str) -> (String, String) {
        let db = store.db().await.unwrap();
        let row = db
            .query_one_raw(statement(
                "SELECT status, claimed_by FROM inbound_work WHERE identity=?",
                vec![identity.to_string().into()],
            ))
            .await
            .unwrap()
            .expect("migrated work row");
        (
            row.try_get("", "status").unwrap(),
            row.try_get("", "claimed_by").unwrap(),
        )
    }

    /// Real v6 stage repairs must preserve complete file identities/references through recovery.
    #[tokio::test]
    async fn v6_send_stage_migration_separates_local_stops_and_unknown_responses()
    -> Result<(), Box<dyn std::error::Error>> {
        use pl_protocol::studio::{BotSendStage as Stage, BotSendStopReason as Stop};
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("v6-stages.sqlite");
        let store = BotStateStore::new(path.clone());
        let db = store.db().await?;
        let resources =
            crate::resource_store::FileResourceStore::new(directory.path().join("resources"));
        let original: std::sync::Arc<[u8]> =
            std::sync::Arc::from(b"v6 exact retained original".as_slice());
        let reference = resources
            .retain_bytes(original.clone(), "application/octet-stream")
            .await?;
        let content = SendContent::File {
            filename: "v6.bin".into(),
            upload_filename: "v6.bin".into(),
            resource: reference.clone(),
        };
        let cancelled = "send cancelled before the next network write; earlier stages retain their recorded result";
        let cases = [
            (
                "cancel-before-upload",
                serde_json::json!({"kind":"rejected"}),
                Some("notStarted"),
                cancelled,
                None,
                Stage::NotStarted,
                Stage::NotStarted,
                Some(Stop::Cancelled),
            ),
            (
                "cancel-after-upload",
                serde_json::json!({"kind":"accepted","fileKey":"v6-key"}),
                Some("rejected"),
                cancelled,
                None,
                Stage::Accepted,
                Stage::NotStarted,
                Some(Stop::Cancelled),
            ),
            (
                "response-budget",
                serde_json::json!({"kind":"rejected"}),
                Some("notStarted"),
                "消息资源超过单文件或批次字节预算",
                None,
                Stage::Unknown,
                Stage::NotStarted,
                None,
            ),
            (
                "local-read",
                serde_json::json!({"kind":"unknown"}),
                Some("notStarted"),
                "retained send resource is unavailable or invalid",
                None,
                Stage::NotStarted,
                Stage::NotStarted,
                Some(Stop::LocalFailure),
            ),
            (
                "platform-rejection",
                serde_json::json!({"kind":"rejected"}),
                Some("notStarted"),
                "Feishu permission was denied",
                Some("230027"),
                Stage::Rejected,
                Stage::NotStarted,
                None,
            ),
            (
                "unproven-history",
                serde_json::Value::Null,
                None,
                "unknown historical result",
                None,
                Stage::Unknown,
                Stage::Unknown,
                None,
            ),
            (
                "http-server-error",
                serde_json::json!({"kind":"rejected"}),
                Some("notStarted"),
                "Feishu HTTP service is unavailable",
                Some("503"),
                Stage::Unknown,
                Stage::NotStarted,
                None,
            ),
        ];
        for (id, upload, message, diagnostic, code, ..) in &cases {
            let facts = serde_json::json!([{
                "index":0,"uuid":"v6-uuid","status":"rejected","platformMessageId":null,
                "diagnostic":diagnostic,"upload":upload,"messageStage":message,"content":content,
                "platformDiagnostic":{"code":"rejected","message":diagnostic,"retryable":false,"platformCode":code,"guidance":null}
            }]);
            db.execute_raw(statement(
                "INSERT INTO send_operations(operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,updated_at,send_identity,send_source)
                 VALUES(?,'bot','chat','unchanged-v6-hash','rejected','',?,1,'{\"kind\":\"file\",\"requestHash\":\"original-request\"}','null')",
                vec![id.to_string().into(), facts.to_string().into()],
            )).await?;
        }
        remove_schema9_fixture(db).await?;
        db.execute_unprepared(
            "DROP TABLE bot_card_streams; UPDATE bot_meta SET schema_version=6 WHERE id=1",
        )
        .await?;
        drop(store);
        let reopened = BotStateStore::new(path.clone());
        for (id, _, _, _, _, upload, message, stop) in cases {
            let record = reopened
                .load_send(id)
                .await?
                .ok_or("migrated record missing")?;
            assert_eq!(record.content_hash, "unchanged-v6-hash");
            assert_eq!(record.segments[0].uuid, "v6-uuid");
            assert_eq!(
                record.identity,
                SendIdentity::File {
                    request_hash: "original-request".into()
                }
            );
            assert_eq!(
                record.segments[0].content.as_ref(),
                Some(&content),
                "stage migration must not rewrite file references"
            );
            let retry = reopened
                .claim_send(&record)
                .await?
                .ok_or("retry lost original record")?;
            let result = super::super::delivery::replay_send(retry);
            assert_eq!(result.segments[0].upload_stage, Some(upload), "{id}");
            assert_eq!(result.segments[0].message_stage, message, "{id}");
            assert_eq!(result.segments[0].stop_reason, stop, "{id}");
            if id == "cancel-after-upload" {
                assert_eq!(
                    record.segments[0].upload,
                    Some(UploadFact::Accepted {
                        file_key: "v6-key".into()
                    })
                );
            }
            if id == "response-budget" {
                assert_eq!(result.status, pl_protocol::studio::BotSendStatus::Unknown);
            }
            if id == "unproven-history" {
                assert_eq!(result.status, pl_protocol::studio::BotSendStatus::Rejected);
            }
            if id == "http-server-error" {
                assert_eq!(
                    result.segments[0]
                        .diagnostic
                        .as_ref()
                        .and_then(|diagnostic| diagnostic.platform_code.as_deref()),
                    Some("503")
                );
            }
        }
        let mut recovery = super::super::send_resources::SendResources::new(resources.clone());
        recovery.maintain(&reopened).await?;
        assert!(!recovery.needs_maintenance());
        let mut file7 = reopened.load_send("cancel-after-upload").await?.unwrap();
        file7.segments[0].upload = Some(UploadFact::Rejected);
        file7.segments[0].stop_reason = None;
        reopened.save_send(&file7).await?;
        remove_schema9_fixture(reopened.db().await?).await?;
        reopened
            .db()
            .await?
            .execute_unprepared(
                "DROP TABLE bot_card_streams; UPDATE bot_meta SET schema_version=7 WHERE id=1",
            )
            .await?;
        drop(reopened);
        let file7_reopened = BotStateStore::new(path);
        let preserved = file7_reopened
            .load_send("cancel-after-upload")
            .await?
            .unwrap();
        assert_eq!(
            preserved.segments, file7.segments,
            "task file7 must not rerun the file6 diagnostic-based stage repair"
        );
        assert_eq!(preserved.identity, file7.identity);
        assert_eq!(
            pl_core::context::ResourceAccess::new(resources)
                .read(&reference, tokio_util::sync::CancellationToken::new())
                .await?
                .as_ref(),
            original.as_ref()
        );
        Ok(())
    }

    #[tokio::test]
    async fn legacy_ledger_upgrade_preserves_work_and_reopens_media_without_duplicate_admission()
    -> Result<(), Box<dyn std::error::Error>> {
        for version in [3, 5] {
            let directory = tempfile::tempdir()?;
            let path = directory.path().join("bot-state.sqlite");
            let legacy = v3_database(&path).await;
            // Preserve both source shapes: the oldest row has no segment facts, while this
            // later text result already owns exact snake_case UUID and platform facts.
            legacy.execute_unprepared(
                "ALTER TABLE send_operations ADD COLUMN segment_facts TEXT NOT NULL DEFAULT '';
                 INSERT INTO send_operations(operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,updated_at,segment_facts)
                 VALUES('op-with-facts','legacy','chat','old-text-hash','partial','pm-known',1,
                 '[{\"index\":0,\"uuid\":\"old-uuid\",\"status\":\"succeeded\",\"platform_message_id\":\"pm-known\",\"diagnostic\":null},{\"index\":1,\"uuid\":\"old-uuid-2\",\"status\":\"rejected\",\"platform_message_id\":null,\"diagnostic\":\"known rejection\"}]');"
            ).await?;
            if version == 5 {
                // Keep the injected-failure probe at version three; after rollback the
                // successful import below uses this complete historical version-five shape.
                legacy.execute_unprepared(
                    "ALTER TABLE inbound_work ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]';
                     ALTER TABLE inbound_work ADD COLUMN watch_input TEXT NOT NULL DEFAULT '';
                     ALTER TABLE inbound_work ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0;
                     ALTER TABLE inbound_work ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0;"
                ).await?;
            }
            legacy.execute_unprepared("CREATE TRIGGER reject_ledger_migration BEFORE UPDATE ON bot_meta BEGIN SELECT RAISE(ABORT,'injected ledger migration failure'); END").await?;
            legacy.close().await?;

            let failed = BotStateStore::new(path.clone());
            let failure = failed
                .list_due_inbound("legacy")
                .await
                .expect_err("ledger migration must fail");
            // Public diagnostics deliberately redact persistent contents. Assert the retained
            // typed private cause, not a leak through FeishuError's user-facing Display.
            let FeishuError::Protocol { source, .. } = &failure;
            let startup = source
                .as_deref()
                .and_then(|cause| {
                    cause.downcast_ref::<crate::studio::startup::StudioStartupError>()
                })
                .expect("migration retained its typed startup cause");
            assert_eq!(
                startup.kind,
                crate::studio::startup::StudioStartupErrorKind::Migration
            );
            let failure_chain = format!("{:#}", anyhow::Error::new(failure));
            assert!(failure_chain.contains("m20261026_000001_bot_ledger_schema"));
            assert!(failure_chain.contains("injected ledger migration failure"));
            drop(failed);
            let probe = Database::connect(
                sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
            )
            .await?;
            assert_eq!(
                probe
                    .query_one_raw(statement(
                        "SELECT schema_version FROM bot_meta WHERE id=1",
                        vec![]
                    ))
                    .await?
                    .unwrap()
                    .try_get::<i64>("", "schema_version")?,
                3
            );
            assert!(
                probe
                    .query_one_raw(statement("SELECT version FROM seaql_migrations", vec![]))
                    .await?
                    .is_none()
            );
            assert_eq!(
                probe
                    .query_one_raw(statement(
                        "SELECT text FROM inbound_work WHERE identity='legacy:chat:m1'",
                        vec![]
                    ))
                    .await?
                    .unwrap()
                    .try_get::<String>("", "text")?,
                "question"
            );
            probe
                .execute_unprepared("DROP TRIGGER reject_ledger_migration")
                .await?;
            // Keep the published failure regression on version three; after that probe, the
            // successful import still covers each genuine pre-six source in this fixture loop.
            probe
                .execute_raw(statement(
                    "UPDATE bot_meta SET schema_version=? WHERE id=1",
                    vec![version.into()],
                ))
                .await?;
            probe.close().await?;

            let store = BotStateStore::new(path.clone());
            // 旧 claimed 行与绑定、发送事实仍在，schema 升到当前版本。
            let due = store.list_due_inbound("legacy").await?;
            assert_eq!(due.len(), 1);
            assert_eq!(due[0].message_id, "m1");
            assert_eq!(due[0].text, "question");
            assert!(due[0].attachments.is_empty());
            assert_eq!(due[0].watch_input, "");
            let db = store.db().await?;
            assert!(
            db.query_one_raw(statement(
                "SELECT thread_id FROM thread_bindings WHERE chat_id='chat' AND thread_id='thread-1'",
                vec![],
            ))
            .await?
            .is_some(),
            "migrated binding survives"
        );
            assert!(
            db.query_one_raw(statement(
                "SELECT status FROM send_operations WHERE operation_id='op-1' AND status='succeeded'",
                vec![],
            ))
            .await?
            .is_some(),
            "migrated send fact survives"
        );
            let version: i64 = db
                .query_one_raw(statement(
                    "SELECT schema_version FROM bot_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .unwrap()
                .try_get("", "schema_version")?;
            assert_eq!(version, BOT_STATE_SCHEMA_VERSION);
            let old = store.load_send("op-1").await?.ok_or("old send missing")?;
            assert_eq!(old.identity, SendIdentity::LegacyText);
            assert_eq!(old.content_hash, "hash");
            assert!(!old.facts_complete);
            assert_eq!(old.platform_message_ids, ["pm-1"]);
            let known = store
                .load_send("op-with-facts")
                .await?
                .ok_or("known text send missing")?;
            assert_eq!(known.identity, SendIdentity::LegacyText);
            assert_eq!(known.content_hash, "old-text-hash");
            assert_eq!(known.status, SendRecordStatus::Partial);
            assert!(known.facts_complete);
            assert_eq!(known.segments[0].uuid, "old-uuid");
            assert_eq!(
                known.segments[0].platform_message_id.as_deref(),
                Some("pm-known")
            );
            assert_eq!(known.segments[1].status, SendRecordStatus::Rejected);
            assert_eq!(
                known.segments[1].diagnostic.as_deref(),
                Some("known rejection")
            );
            // A file cannot borrow a migrated text operation even with its old hash copied verbatim.
            let mut conflicting_file = old.clone();
            conflicting_file.identity = SendIdentity::File {
                request_hash: "file-request".into(),
            };
            assert_eq!(
                store
                    .claim_send(&conflicting_file)
                    .await
                    .unwrap_err()
                    .kind(),
                FeishuErrorKind::Conflict
            );
            assert!(store.claim_send(&old).await?.is_some());

            // 过期旧身份不得自认续权：迁移前 crash 的 worker 的租约已过期，
            // renew/finish 都被有效 lease 条件拒绝，行不被旧持有者改写。
            assert_eq!(
                store
                    .renew_inbound_claim("legacy", "chat", "m1", "crashed-worker")
                    .await?,
                ClaimLease::LostClaim
            );
            assert_eq!(
                store
                    .finish_inbound_work(
                        "legacy",
                        "chat",
                        "m1",
                        "crashed-worker",
                        WorkFinish::Completed
                    )
                    .await?,
                MarkOutcome::LostClaim
            );
            let (status, claimed_by) = work_status(&store, "legacy:chat:m1").await;
            assert_eq!(status, "claimed");
            assert_eq!(claimed_by, "crashed-worker");

            // 后继新 worker 对到期槽竞争接管成功，且在有效租约内可续约与收束。
            assert_eq!(
                store
                    .claim_inbound_work("legacy", "chat", "m1", "w1")
                    .await?,
                InboundClaim::Claimed
            );
            assert_eq!(
                store
                    .renew_inbound_claim("legacy", "chat", "m1", "w1")
                    .await?,
                ClaimLease::Renewed
            );
            assert_eq!(
                store
                    .finish_inbound_work("legacy", "chat", "m1", "w1", WorkFinish::Completed)
                    .await?,
                MarkOutcome::Applied
            );
            let (status, claimed_by) = work_status(&store, "legacy:chat:m1").await;
            assert_eq!(status, "completed");
            assert_eq!(claimed_by, "");

            // New media work must survive a process boundary alongside the migrated text row.
            let mut media = due[0].clone();
            media.message_id = "media-after-migration".into();
            media.content_hash = "media-content".into();
            media.attachments = vec![
                super::super::inbound::InboundAttachment::File {
                    key: "file-key".into(),
                    filename: "中文证据.txt".into(),
                },
                super::super::inbound::InboundAttachment::Image {
                    key: "image-key".into(),
                },
            ];
            assert!(matches!(
                store.admit_inbound(media.clone()).await?,
                InboundAdmit::Fresh(_)
            ));
            // A claimed upload interrupted at restart must retain the exact original object and
            // unknown stage alongside old text records. A changed working file is never reread.
            let resources =
                crate::resource_store::FileResourceStore::new(directory.path().join("resources"));
            let original: std::sync::Arc<[u8]> =
                std::sync::Arc::from(b"exact original\0bytes".as_slice());
            let resource = resources
                .retain_bytes(original.clone(), "application/octet-stream")
                .await?;
            let file = SendRecord {
                operation_id: "interrupted-file".into(),
                bot_id: "legacy".into(),
                chat_id: "chat".into(),
                content_hash: "frozen-file-identity".into(),
                identity: SendIdentity::File {
                    request_hash: "request".into(),
                },
                source: None,
                status: SendRecordStatus::Unknown,
                platform_message_ids: vec![],
                facts_complete: true,
                segments: vec![SendSegmentFact {
                    index: 0,
                    uuid: "file-uuid".into(),
                    status: SendRecordStatus::Unknown,
                    platform_message_id: None,
                    diagnostic: None,
                    platform_diagnostic: None,
                    stop_reason: None,
                    content: Some(SendContent::File {
                        filename: "no-extension".into(),
                        upload_filename: "no-extension.bin".into(),
                        resource: resource.clone(),
                    }),
                    upload: Some(UploadFact::InFlight),
                    message_stage: Some(MessageStage::NotStarted),
                    notice_attempt: None,
                }],
            };
            assert!(store.claim_send(&file).await?.is_none());
            drop(store);
            let reopened = BotStateStore::new(path);
            let restored = reopened.list_due_inbound("legacy").await?;
            assert_eq!(restored, vec![media.clone()]);
            assert_eq!(
                reopened.admit_inbound(media.clone()).await?,
                InboundAdmit::DuplicateResume(media)
            );
            assert_eq!(reopened.list_due_inbound("legacy").await?.len(), 1);
            let frozen = reopened
                .claim_send(&file)
                .await?
                .ok_or("claimed file lost on restart")?;
            assert_eq!(frozen.identity, file.identity);
            assert_eq!(frozen.segments[0].upload, Some(UploadFact::InFlight));
            let replay = super::super::delivery::replay_send(frozen);
            assert_eq!(replay.status, pl_protocol::studio::BotSendStatus::Unknown);
            assert!(replay.segments[0].diagnostic.is_some());
            assert_eq!(
                pl_core::context::ResourceAccess::new(resources)
                    .read(&resource, tokio_util::sync::CancellationToken::new())
                    .await?
                    .as_ref(),
                original.as_ref()
            );
            let old_again = reopened
                .load_send("op-with-facts")
                .await?
                .ok_or("known migrated text lost")?;
            assert_eq!(old_again.content_hash, "old-text-hash");
            assert_eq!(old_again.segments, known.segments);
        }
        Ok(())
    }

    /// Frozen pre-publication card rows retain their no-final/continuation materials through the
    /// official main-card6 migration and reopen. Fixtures do not execute the retired writer.
    #[tokio::test]
    async fn migrated_card_progress_preserves_no_final_and_continuation_targets()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("bot-state.sqlite");
        drop(v3_database(&path).await);
        let store = BotStateStore::new(path.clone());
        let seed = store.list_due_inbound("legacy").await?.remove(0);
        assert_eq!(
            store
                .claim_inbound_work("legacy", "chat", "m1", "w1")
                .await?,
            InboundClaim::Claimed
        );
        let binding = card_test_binding("m1");
        let mut no_final = card_test_preview(binding.clone());
        // This historical row records a confirmed no-final close, not a new final answer.
        no_final.version = 2;
        no_final.sequence = 1;
        no_final.confirmed_sequence = 1;
        no_final.lifecycle = card::CardLifecycle::NoFinalReply;
        no_final.diagnostic = Some(card_test_no_final_diagnostic());
        no_final.last_operation = Some(card_test_operation(
            card::CardAction::Settings {
                streaming: false,
                lifecycle: card::CardLifecycle::NoFinalReply,
                recovery: false,
            },
            1,
            card::CardOperationStatus::Confirmed,
        ));
        insert_legacy_card_fixture(store.db().await?, &no_final).await?;
        assert_eq!(
            store
                .finish_inbound_work(
                    "legacy",
                    "chat",
                    "m1",
                    "w1",
                    WorkFinish::NeedsAttention(card::CardLifecycle::NoFinalReply.summary())
                )
                .await?,
            MarkOutcome::Applied
        );

        let mut expected = Vec::new();
        for (message_id, turn_id, lifecycle, unknown) in [
            (
                "failed-continuation",
                Some("canonical-failed-turn"),
                card::CardLifecycle::Failed,
                true,
            ),
            (
                "cancelled-continuation",
                Some("canonical-cancelled-turn"),
                card::CardLifecycle::Cancelled,
                false,
            ),
            (
                "discarded-continuation",
                None,
                card::CardLifecycle::InteractionEnded,
                false,
            ),
        ] {
            let mut inbound = seed.clone();
            inbound.message_id = message_id.to_string();
            inbound.content_hash = format!("hash:{message_id}");
            assert!(matches!(
                store.admit_inbound(inbound).await?,
                InboundAdmit::Fresh(_)
            ));
            assert_eq!(
                store
                    .claim_inbound_work("legacy", "chat", message_id, "w1")
                    .await?,
                InboundClaim::Claimed
            );
            let binding = card_test_binding(message_id);
            let mut state = card_test_preview(binding.clone());
            let continuation = format!("canonical-input:{message_id}");
            // Reconstruct the already stored canonical continuation and its original operation.
            // A fixture INSERT is not a replacement implementation of the old claim/CAS writer.
            state.version = 4;
            state.watch_input = continuation.clone();
            state.turn_id = turn_id.map(str::to_owned);
            state.sequence = 2;
            state.confirmed_sequence = if unknown { 1 } else { 2 };
            state.lifecycle = if unknown {
                card::CardLifecycle::NeedsAttention
            } else {
                lifecycle
            };
            state.last_operation = Some(card_test_operation(
                card::CardAction::Settings {
                    streaming: false,
                    lifecycle,
                    recovery: false,
                },
                2,
                if unknown {
                    card::CardOperationStatus::Unknown
                } else {
                    card::CardOperationStatus::Confirmed
                },
            ));
            let db = store.db().await?;
            db.execute_raw(statement(
                "UPDATE inbound_work SET watch_input=? WHERE identity=?",
                vec![
                    continuation.clone().into(),
                    inbound_identity("legacy", "chat", message_id).into(),
                ],
            ))
            .await?;
            insert_legacy_card_fixture(db, &state).await?;
            expected.push((binding, continuation, turn_id, unknown, lifecycle));
        }
        // Reproduce fixed main's actual card6 shape, then compare every retained card and
        // operation fact through the current ledger rather than its retired table encoding.
        let db = store.db().await?;
        let before_cards = db
            .query_all_raw(statement(
                "SELECT state_json FROM bot_card_streams ORDER BY identity",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "state_json"))
            .collect::<Result<Vec<_>, _>>()?;
        remove_schema9_fixture(db).await?;
        db.execute_unprepared(
            "ALTER TABLE send_operations DROP COLUMN send_identity;
            ALTER TABLE send_operations DROP COLUMN send_source;
            UPDATE bot_meta SET schema_version=6 WHERE id=1",
        )
        .await?;
        drop(store);

        let reopened = BotStateStore::new(path);
        reopened.db().await?;
        for original in &before_cards {
            let original: card::CardStream = serde_json::from_str(original)?;
            assert_migrated_card_material(&reopened, &original).await?;
        }
        assert!(
            reopened
                .db()
                .await?
                .query_one_raw(statement("SELECT 1 FROM bot_card_streams LIMIT 1", vec![],))
                .await?
                .is_none(),
            "successful migration must retire the old writable card facts"
        );
        let no_final = migrated_card_entity(&reopened, &binding).await?.state.card;
        assert_eq!(no_final.lifecycle, Some(card::CardLifecycle::NoFinalReply));
        assert!(no_final.final_content_hash.is_none());
        assert_eq!(no_final.confirmed_text, "last verified preview");
        assert_eq!(no_final.diagnostic.as_ref().unwrap().code, "noFinalReply");
        assert_eq!(
            no_final.diagnostic.as_ref().unwrap().message,
            "未生成最终答复，所示内容仅为未完成预览"
        );
        assert!(
            no_final
                .lifecycle
                .is_some_and(card::CardLifecycle::terminal)
        );
        let (status, _) = work_status(&reopened, "legacy:chat:m1").await;
        assert_eq!(status, "needs_attention");
        for (binding, continuation, turn_id, unknown, lifecycle) in expected {
            let entity = migrated_card_entity(&reopened, &binding).await?;
            let scope = reopened.delivery_scope(&entity.scope).await?.unwrap();
            let publication::DeliveryScopeOrigin::LegacyFinal { legacy } = scope.origin else {
                panic!("old finite reply gained frontend authority");
            };
            assert_eq!(legacy.watch_input, continuation);
            assert_eq!(legacy.original_turn_id.as_deref(), turn_id);
            assert_eq!(entity.turn_id.as_deref(), turn_id);
            let state = &entity.state.card;
            assert_eq!(state.confirmed_text, "last verified preview");
            assert!(state.final_content_hash.is_none());
            assert_eq!(
                matches!(
                    entity.state.settled.as_ref().map(|settled| &settled.result),
                    Some(publication::DeliveryResult::Unknown { .. })
                ),
                unknown,
            );
            if unknown {
                assert_eq!(state.lifecycle, Some(card::CardLifecycle::NeedsAttention));
                if let publication::DeliveryClaimOutcome::Acquired(token) = reopened
                    .claim_delivery_scope(&entity.scope, "delivery-owner")
                    .await?
                {
                    assert!(
                        reopened
                            .register_delivery_card_intent(
                                &token,
                                &entity.entity,
                                entity.ledger_version,
                                publication::DeliveryAction::UpdateSettings {
                                    card_id: state.card_id.clone().unwrap(),
                                    streaming: false,
                                    lifecycle: card::CardLifecycle::NoFinalReply,
                                    recovery: false,
                                },
                                |_, _| panic!("Unknown must not allocate a replacement request"),
                            )
                            .await
                            .is_err()
                    );
                    assert_eq!(migrated_card_entity(&reopened, &binding).await?, entity);
                }
            } else {
                assert_eq!(state.lifecycle, Some(lifecycle));
                assert!(state.lifecycle.is_some_and(card::CardLifecycle::terminal));
            }
        }
        Ok(())
    }

    /// The official read-only migration preflight rejects unknown historical card fields at every
    /// nesting level without rewriting their bytes or version. No retired runtime reader is used.
    #[tokio::test]
    async fn current_card_unknown_fields_are_preserved_and_rejected()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("card-json.sqlite");
        drop(v3_database(&path).await);
        let store = BotStateStore::new(path.clone());
        store.list_due_inbound("legacy").await?;
        assert_eq!(
            store
                .claim_inbound_work("legacy", "chat", "m1", "w1")
                .await?,
            InboundClaim::Claimed
        );
        let binding = card_test_binding("m1");
        let mut state = card_test_preview(binding.clone());
        state.sequence = 1;
        state.confirmed_sequence = 1;
        state.lifecycle = card::CardLifecycle::Paused;
        state.last_operation = Some(card_test_operation(
            card::CardAction::Settings {
                streaming: false,
                lifecycle: card::CardLifecycle::Paused,
                recovery: false,
            },
            1,
            card::CardOperationStatus::Confirmed,
        ));
        state.recovery_used = true;
        state.recovery = Some(card::CardRecovery {
            action: card::CardAction::Settings {
                streaming: false,
                lifecycle: card::CardLifecycle::Paused,
                recovery: false,
            },
            phase: card::CardRecoveryPhase::Close,
        });
        state.diagnostic = Some(card_test_no_final_diagnostic());
        state.last_operation.as_mut().unwrap().diagnostic = state.diagnostic.clone();
        let db = store.db().await?;
        insert_legacy_card_fixture(db, &state).await?;
        // Genuine schema-eight fixture: remove current structures/official completion records
        // before checking the historical codec through the normal non-mutating open preflight.
        remove_schema9_fixture(db).await?;
        db.execute_unprepared("UPDATE bot_meta SET schema_version=8 WHERE id=1")
            .await?;
        schema::inspect_existing(&path).await?;
        let original = serde_json::to_value(&state)?;
        let mut accepted = Vec::new();
        for pointer in [
            "",
            "/binding",
            "/lastOperation",
            "/lastOperation/action",
            "/lastOperation/diagnostic",
            "/recovery",
            "/recovery/action",
            "/diagnostic",
        ] {
            let mut payload = original.clone();
            payload
                .pointer_mut(pointer)
                .unwrap()
                .as_object_mut()
                .unwrap()
                .insert(
                    "futureDurableFact".into(),
                    serde_json::json!({"retained":"must not disappear"}),
                );
            let raw = serde_json::to_string(&payload)?;
            db.execute_raw(statement(
                "UPDATE bot_card_streams SET state_json=?",
                vec![raw.clone().into()],
            ))
            .await?;
            if schema::inspect_existing(&path).await.is_ok() {
                accepted.push(pointer.to_string());
            }
            let row = db
                .query_one_raw(statement(
                    "SELECT state_json,version FROM bot_card_streams",
                    vec![],
                ))
                .await?
                .unwrap();
            assert_eq!(row.try_get::<String>("", "state_json")?, raw);
            assert_eq!(row.try_get::<i64>("", "version")?, state.version);
        }
        for action in [
            card::CardAction::Create {
                text: "preview".into(),
            },
            card::CardAction::Send {},
            card::CardAction::Content {
                text: "preview".into(),
                final_content: false,
            },
        ] {
            let mut variant = state.clone();
            let operation = variant.last_operation.as_mut().unwrap();
            operation.action = action;
            operation.content_hash = card::hash(&serde_json::to_vec(&operation.action)?);
            let mut payload = serde_json::to_value(variant)?;
            db.execute_raw(statement(
                "UPDATE bot_card_streams SET state_json=?",
                vec![payload.to_string().into()],
            ))
            .await?;
            assert!(
                schema::inspect_existing(&path).await.is_ok(),
                "declared action must remain readable"
            );
            let tag = payload["lastOperation"]["action"]["kind"]
                .as_str()
                .unwrap()
                .to_string();
            payload["lastOperation"]["action"]
                .as_object_mut()
                .unwrap()
                .insert("futureDurableFact".into(), true.into());
            let raw = payload.to_string();
            db.execute_raw(statement(
                "UPDATE bot_card_streams SET state_json=?",
                vec![raw.clone().into()],
            ))
            .await?;
            if schema::inspect_existing(&path).await.is_ok() {
                accepted.push(tag);
            }
            assert_eq!(
                db.query_one_raw(statement("SELECT state_json FROM bot_card_streams", vec![]))
                    .await?
                    .unwrap()
                    .try_get::<String>("", "state_json")?,
                raw
            );
        }
        assert!(
            accepted.is_empty(),
            "unknown durable fields accepted at: {accepted:?}"
        );
        Ok(())
    }

    /// Faults at the real schema boundary must roll back DDL and retain the exact old card intent.
    /// This checks migration/storage only; no test claims platform acceptance or authorization.
    #[tokio::test]
    async fn schema9_migration_preserves_card_material_and_rolls_back_unprovable_origins()
    -> Result<(), Box<dyn std::error::Error>> {
        for fault in [
            "none",
            "conflicting-target",
            "same-chat-creation",
            "same-chat-project",
            "same-chat-revision",
            "same-chat-bot",
            "same-creation-thread",
            "missing-project",
            "missing-revision",
            "historical-project",
            "commit-boundary",
            "nested-card",
        ] {
            let directory = tempfile::tempdir()?;
            let path = directory.path().join("bot-state.sqlite");
            drop(v3_database(&path).await);
            let store = BotStateStore::new(path.clone());
            store.list_due_inbound("legacy").await?;
            assert_eq!(
                store
                    .claim_inbound_work("legacy", "chat", "m1", "worker")
                    .await?,
                InboundClaim::Claimed
            );
            let binding = card_test_binding("m1");
            let mut state = card_test_preview(binding.clone());
            state.sequence = 1;
            state.last_operation = Some(card_test_operation(
                card::CardAction::Content {
                    text: "frozen exact pending body".into(),
                    final_content: false,
                },
                1,
                card::CardOperationStatus::Intent,
            ));
            insert_legacy_card_fixture(store.db().await?, &state).await?;
            let db = store.db().await?.clone();
            let mut before: String = db
                .query_one_raw(statement("SELECT state_json FROM bot_card_streams", vec![]))
                .await?
                .unwrap()
                .try_get("", "state_json")?;
            remove_schema9_fixture(&db).await?;
            db.execute_unprepared("UPDATE bot_meta SET schema_version=8 WHERE id=1")
                .await?;
            match fault {
                "conflicting-target" => {
                    db.execute_unprepared("INSERT INTO thread_bindings SELECT 'other-chat',thread_id,status,creation_id,project_id,revision,generation,diagnostic,created_at,updated_at FROM thread_bindings WHERE chat_id='chat'").await?;
                }
                "same-chat-creation" => {
                    db.execute_unprepared("INSERT INTO binding_operations VALUES('conflicting-origin','legacy','chat','old-hash',0,'different-creation','thread-1',1)").await?;
                }
                "same-chat-project" => {
                    db.execute_unprepared("UPDATE inbound_work SET project_id='different-project'")
                        .await?;
                }
                "same-chat-revision" => {
                    db.execute_unprepared("UPDATE inbound_work SET binding_revision=2")
                        .await?;
                }
                "same-chat-bot" => {
                    db.execute_unprepared("UPDATE inbound_work SET bot_id='different-bot'")
                        .await?;
                }
                "same-creation-thread" => {
                    db.execute_unprepared("INSERT INTO binding_operations VALUES('conflicting-thread','legacy','chat','old-hash',0,'botthread:legacy:chat','different-thread',1)").await?;
                }
                "missing-project" => {
                    db.execute_unprepared("UPDATE inbound_work SET project_id=''; UPDATE thread_bindings SET project_id=''").await?;
                }
                "missing-revision" => {
                    db.execute_unprepared("UPDATE inbound_work SET binding_revision=0; UPDATE thread_bindings SET revision=0").await?;
                }
                "historical-project" => {
                    db.execute_unprepared("INSERT INTO binding_operations VALUES('old-origin','legacy','chat','old-hash',0,'old-creation','old-thread',1)").await?;
                }
                "commit-boundary" => {
                    db.execute_unprepared("CREATE TRIGGER stop_schema9 BEFORE UPDATE OF schema_version ON bot_meta WHEN NEW.schema_version>8 BEGIN SELECT RAISE(ABORT,'controlled migration fault'); END").await?;
                }
                "nested-card" => {
                    let mut value: serde_json::Value = serde_json::from_str(&before)?;
                    value["lastOperation"]["unrecognizedDurableFact"] =
                        serde_json::json!("must retain exact original");
                    before = serde_json::to_string(&value)?;
                    db.execute_raw(statement(
                        "UPDATE bot_card_streams SET state_json=?",
                        vec![before.clone().into()],
                    ))
                    .await?;
                }
                _ => {}
            }
            drop(store);
            let reopened = BotStateStore::new(path);
            let result = reopened.db().await;
            if matches!(
                fault,
                "none" | "missing-project" | "missing-revision" | "historical-project"
            ) {
                result?;
                if matches!(fault, "missing-project" | "missing-revision") {
                    assert!(
                        reopened
                            .audience_scope("thread-1", "legacy")
                            .await?
                            .is_none(),
                        "{fault} fabricated a trusted origin from missing proof"
                    );
                } else {
                    let scope = reopened
                        .audience_scope("thread-1", "legacy")
                        .await?
                        .ok_or("migration lost Thread origin")?;
                    assert!(
                        scope.origin.requires_upgrade,
                        "old privacy must not gain an active public audience"
                    );
                    assert!(
                        scope.head.is_none(),
                        "migration fabricated a new authorization"
                    );
                }
                if fault == "historical-project" {
                    assert!(
                        reopened
                            .audience_scope("old-thread", "legacy")
                            .await?
                            .is_none(),
                        "historical origin borrowed the current different Thread's project"
                    );
                }
                let original: card::CardStream = serde_json::from_str(&before)?;
                let entity = assert_migrated_card_material(&reopened, &original).await?;
                assert!(matches!(
                    entity.state.settled.as_ref().map(|settled| &settled.result),
                    Some(publication::DeliveryResult::Unknown { .. }),
                ));
                assert!(
                    db.query_one_raw(statement("SELECT 1 FROM bot_card_streams LIMIT 1", vec![],))
                        .await?
                        .is_none(),
                    "{fault} kept a second writable card ledger"
                );
            } else {
                assert!(result.is_err(), "{fault} failed to reject migration");
                let version: i64 = db
                    .query_one_raw(statement(
                        "SELECT schema_version FROM bot_meta WHERE id=1",
                        vec![],
                    ))
                    .await?
                    .unwrap()
                    .try_get("", "schema_version")?;
                assert_eq!(version, 8, "{fault} committed a partial schema version");
                assert!(
                    db.query_one_raw(statement(
                        "SELECT name FROM sqlite_schema WHERE name='bot_authorizations'",
                        vec![]
                    ))
                    .await?
                    .is_none(),
                    "{fault} left partial audience DDL"
                );
                let after: String = db
                    .query_one_raw(statement("SELECT state_json FROM bot_card_streams", vec![]))
                    .await?
                    .unwrap()
                    .try_get("", "state_json")?;
                assert_eq!(
                    after, before,
                    "{fault} changed UUID/sequence/accepted body or pending operation during rollback"
                );
            }
        }
        Ok(())
    }

    /// A v8 database may only adopt a creation target kind its own sources recorded.
    /// Missing evidence stays typed Unproven, and a half-baked "current" shape is
    /// rejected instead of being repaired on ordinary open.
    #[tokio::test]
    async fn schema9_creation_target_proof_adopts_only_recorded_sources()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("target-proof.sqlite");
        let store = BotStateStore::new(path.clone());
        let db = store.db().await?.clone();
        remove_schema9_fixture(&db).await?;
        db.execute_unprepared(
            "DELETE FROM inbound_work; DELETE FROM thread_bindings; DELETE FROM observed_directs;
             INSERT INTO inbound_work(identity, bot_id, chat_id, message_id, content_hash, text,
               open_id, chat_kind, app_id, project_id, creation_id, binding_revision, status,
               diagnostic, claimed_by, claimed_at, updated_at)
             VALUES('legacy:group-chat:m2','legacy','group-chat','m2','hash','q','','group','app','project','botthread:legacy:group-chat',1,'completed','','',0,1),
                   ('legacy:direct-chat:m3','legacy','direct-chat','m3','hash','q','peer','direct','app','project','botthread:legacy:direct-chat',1,'completed','','',0,1),
                   ('legacy:pending-chat:m4','legacy','pending-chat','m4','hash','q','','group','app','project','botthread:legacy:pending-chat',1,'completed','','',0,1),
                   ('legacy:peerless-chat:m5','legacy','peerless-chat','m5','hash','q','','direct','app','project','botthread:legacy:peerless-chat',1,'completed','','',0,1),
                   ('legacy:stranger:m6','legacy','stranger','m6','hash','q','peer','direct','app','project','botthread:legacy:pending-chat',1,'completed','','',0,1);
             INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id,
               revision, generation, diagnostic, created_at, updated_at)
             VALUES('group-chat','thread-g','bound','botthread:legacy:group-chat','project',1,1,'',1,1),
                   ('direct-chat','thread-d','bound','botthread:legacy:direct-chat','project',1,1,'',1,1),
                   ('pending-chat','','creating','botthread:legacy:pending-chat','project',1,1,'',1,1),
                   ('unknown-chat','','creating','botthread:legacy:unknown-chat','project',1,1,'',1,1),
                   ('peerless-chat','','creating','botthread:legacy:peerless-chat','project',1,1,'',1,1);
             INSERT INTO binding_operations(operation_id, bot_id, chat_id, content_hash,
               expected_revision, creation_id, thread_id, updated_at)
             VALUES('op-pending','legacy','pending-chat','hash',0,'botthread:legacy:pending-chat','',1),
                   ('op-unknown','legacy','unknown-chat','hash',0,'botthread:legacy:unknown-chat','',1),
                   ('op-peerless','legacy','peerless-chat','hash',0,'botthread:legacy:peerless-chat','',1);
             UPDATE bot_meta SET schema_version=8 WHERE id=1",
        )
        .await?;
        drop(store);
        let reopened = BotStateStore::new(path.clone());
        let db = reopened.db().await?.clone();
        for (chat, proof) in [
            (
                "group-chat",
                target::TargetProof::Legacy {
                    target: target::TargetKind::Group,
                },
            ),
            (
                "direct-chat",
                target::TargetProof::Legacy {
                    target: target::TargetKind::Direct {
                        open_id: "peer".into(),
                    },
                },
            ),
            (
                "pending-chat",
                target::TargetProof::Legacy {
                    target: target::TargetKind::Group,
                },
            ),
            ("unknown-chat", target::TargetProof::Unproven),
            // A typed direct row without a peer is still "not a group", but it cannot
            // prove a direct peer and must stay Unproven on its own.
            ("peerless-chat", target::TargetProof::Unproven),
        ] {
            let row = db
                .query_one_raw(statement(
                    "SELECT target_json FROM thread_bindings WHERE chat_id=?",
                    vec![chat.to_string().into()],
                ))
                .await?
                .expect("retained binding row");
            assert_eq!(
                row.try_get::<String>("", "target_json")?,
                proof.encode()?,
                "{chat} adopted a creation target its own sources did not record"
            );
        }
        // 未完成的 operation 与其 creating route 必须携带同一份证明。
        for (operation_id, chat) in [
            ("op-pending", "pending-chat"),
            ("op-unknown", "unknown-chat"),
            ("op-peerless", "peerless-chat"),
        ] {
            let route = db
                .query_one_raw(statement(
                    "SELECT target_json FROM thread_bindings WHERE chat_id=?",
                    vec![chat.to_string().into()],
                ))
                .await?
                .expect("retained binding row");
            let operation = db
                .query_one_raw(statement(
                    "SELECT target_json FROM binding_operations WHERE operation_id=?",
                    vec![operation_id.to_string().into()],
                ))
                .await?
                .expect("retained operation row");
            assert_eq!(
                route.try_get::<String>("", "target_json")?,
                operation.try_get::<String>("", "target_json")?,
                "{chat} left its pending operation without the same creation target"
            );
        }
        // 回填只动证明：创建意图的原有状态/身份/水位逐字保留。
        for (chat, creation) in [
            ("pending-chat", "botthread:legacy:pending-chat"),
            ("unknown-chat", "botthread:legacy:unknown-chat"),
        ] {
            let row = db
                .query_one_raw(statement(
                    "SELECT status,creation_id,project_id,revision FROM thread_bindings WHERE chat_id=?",
                    vec![chat.to_string().into()],
                ))
                .await?
                .expect("retained binding row");
            assert_eq!(row.try_get::<String>("", "status")?, "creating");
            assert_eq!(row.try_get::<String>("", "creation_id")?, creation);
            assert_eq!(row.try_get::<String>("", "project_id")?, "project");
            assert_eq!(row.try_get::<i64>("", "revision")?, 1);
        }
        // The proven kind is not a current membership or send grant.
        assert!(
            reopened
                .audience_scope("thread-g", "legacy")
                .await?
                .is_some_and(|scope| scope.origin.requires_upgrade && scope.head.is_none()),
            "adopted legacy evidence must not fabricate a current authorization"
        );
        // An unreadable value is a real fault: refuse to open and retain the row.
        db.execute_unprepared(
            "UPDATE thread_bindings SET target_json='{\"kind\":\"bogus\"}' WHERE chat_id='group-chat'",
        )
        .await?;
        drop(reopened);
        assert!(
            BotStateStore::new(path.clone()).db().await.is_err(),
            "an unreadable creation target was silently repaired"
        );
        let retained = db
            .query_one_raw(statement(
                "SELECT target_json FROM thread_bindings WHERE chat_id='group-chat'",
                vec![],
            ))
            .await?
            .expect("retained binding row");
        assert_eq!(
            retained.try_get::<String>("", "target_json")?,
            "{\"kind\":\"bogus\"}",
            "rejected creation target was rewritten"
        );
        // A same-version database that lost the finite structure is rejected as well.
        let structure_path = directory.path().join("target-structure.sqlite");
        let current = BotStateStore::new(structure_path.clone());
        let structure_db = current.db().await?.clone();
        structure_db
            .execute_unprepared("ALTER TABLE binding_operations DROP COLUMN target_json")
            .await?;
        drop(current);
        assert!(
            BotStateStore::new(structure_path).db().await.is_err(),
            "a half-baked current schema was patched instead of rejected"
        );
        Ok(())
    }

    /// A recorded group and a recorded direct for one creation are a real conflict: the
    /// migration must roll back to the exact v8 state instead of adopting either kind.
    #[tokio::test]
    async fn schema9_conflicting_creation_sources_roll_back_the_migration()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("target-conflict.sqlite");
        let store = BotStateStore::new(path.clone());
        let db = store.db().await?.clone();
        remove_schema9_fixture(&db).await?;
        db.execute_unprepared(
            "DELETE FROM inbound_work; DELETE FROM thread_bindings;
             INSERT INTO inbound_work(identity, bot_id, chat_id, message_id, content_hash, text,
               open_id, chat_kind, app_id, project_id, creation_id, binding_revision, status,
               diagnostic, claimed_by, claimed_at, updated_at)
             VALUES('legacy:chat:m1','legacy','chat','m1','hash','q','','group','app','project','botthread:legacy:chat',1,'completed','','',0,1),
                   ('legacy:chat:m2','legacy','chat','m2','hash','q','','direct','app','project','botthread:legacy:chat',1,'completed','','',0,1);
             INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id,
               revision, generation, diagnostic, created_at, updated_at)
             VALUES('chat','thread-1','bound','botthread:legacy:chat','project',1,1,'',1,1);
             UPDATE bot_meta SET schema_version=8 WHERE id=1",
        )
        .await?;
        drop(store);
        assert!(
            BotStateStore::new(path).db().await.is_err(),
            "a group/direct creation source conflict was adopted"
        );
        let version: i64 = db
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .expect("retained metadata row")
            .try_get("", "schema_version")?;
        assert_eq!(version, 8, "conflicting migration committed a version");
        assert!(
            db.query_one_raw(statement(
                "SELECT name FROM sqlite_schema WHERE name='bot_audience_origins'",
                vec![]
            ))
            .await?
            .is_none(),
            "conflicting migration left partial audience DDL"
        );
        let rows = db
            .query_all_raw(statement(
                "SELECT message_id FROM inbound_work ORDER BY message_id",
                vec![],
            ))
            .await?;
        assert_eq!(
            rows.len(),
            2,
            "conflicting migration dropped an original row"
        );
        Ok(())
    }

    /// Empty primary keys are part of the finite structure: their payload must be decoded
    /// too, not skipped by pagination.
    #[tokio::test]
    async fn schema9_target_payload_is_decoded_for_empty_keys()
    -> Result<(), Box<dyn std::error::Error>> {
        for table in ["thread_bindings", "binding_operations"] {
            let directory = tempfile::tempdir()?;
            let path = directory.path().join(format!("empty-key-{table}.sqlite"));
            let store = BotStateStore::new(path.clone());
            let db = store.db().await?.clone();
            let (key, insert) = if table == "thread_bindings" {
                (
                    "chat_id",
                    "INSERT INTO thread_bindings(chat_id,thread_id,status,creation_id,project_id,\
                     revision,generation,diagnostic,created_at,updated_at,target_json)\
                     VALUES('','','needs_attention','','project',0,0,'',1,1,'{\"kind\":\"unproven\"}')",
                )
            } else {
                (
                    "operation_id",
                    "INSERT INTO binding_operations(operation_id,bot_id,chat_id,content_hash,\
                     expected_revision,creation_id,thread_id,updated_at,target_json)\
                     VALUES('','legacy','chat','hash',0,'unused-creation','',1,'{\"kind\":\"unproven\"}')",
                )
            };
            db.execute_unprepared(insert).await?;
            // Control: the same row with a well-formed payload opens normally.
            BotStateStore::new(path.clone())
                .db()
                .await
                .unwrap_or_else(|error| panic!("{table} rejected a well-formed payload: {error}"));
            db.execute_unprepared(&format!(
                "UPDATE {table} SET target_json='{{\"kind\":\"bogus\"}}' WHERE {key}=''"
            ))
            .await?;
            drop(store);
            assert!(
                BotStateStore::new(path.clone()).db().await.is_err(),
                "{table} skipped the payload of its empty key"
            );
            let retained = db
                .query_one_raw(statement(
                    &format!("SELECT target_json FROM {table} WHERE {key}=''"),
                    vec![],
                ))
                .await?
                .expect("retained row");
            assert_eq!(
                retained.try_get::<String>("", "target_json")?,
                "{\"kind\":\"bogus\"}",
                "{table} repaired the rejected payload"
            );
        }
        Ok(())
    }

    /// A creation intent may only be committed for a source that already reached storage,
    /// and a committed intent must be completable from its persisted proof alone.
    #[tokio::test]
    async fn creation_binding_requires_and_resumes_its_recorded_source()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("creation-source.sqlite");
        let store = BotStateStore::new(path.clone());
        store.db().await?;
        let first = target::TargetClaim::from_inbound(
            "legacy",
            "app",
            "project",
            "chat",
            "botthread:legacy:chat",
            "m1",
            target::TargetKind::Group,
        );
        let claim = store.claim_thread_binding(&first).await?;
        assert!(
            matches!(claim, ThreadBindingClaim::Creating { .. }),
            "first admission must freeze a creating route"
        );
        // 另一条同 kind 的入站不得顶替原来源。
        let other = target::TargetClaim::from_inbound(
            "legacy",
            "app",
            "project",
            "chat",
            "botthread:legacy:chat",
            "m2",
            target::TargetKind::Group,
        );
        assert!(
            store.claim_thread_binding(&other).await.is_err(),
            "a different same-kind message stood in for the frozen source"
        );
        // 同一 messageId 但冻结身份不同（此处 app）同样不得顶替原来源。
        let wrong_identity = target::TargetClaim::from_inbound(
            "legacy",
            "other-app",
            "project",
            "chat",
            "botthread:legacy:chat",
            "m1",
            target::TargetKind::Group,
        );
        assert!(
            store.claim_thread_binding(&wrong_identity).await.is_err(),
            "a different frozen app identity stood in for the original source"
        );
        // 同一事实的再次投递可以重建它。
        assert!(
            matches!(
                store.claim_thread_binding(&first).await?,
                ThreadBindingClaim::Creating { .. }
            ),
            "re-delivery of the frozen source must remain resumable"
        );
        // 来源行缺席时绑定必须被拒，且不写之后必然打不开的 origin。
        assert!(
            store
                .bind_thread("chat", "thread-c", "botthread:legacy:chat", "project", None)
                .await
                .is_err(),
            "binding referenced a source row that never reached storage"
        );
        assert!(store.audience_scope("thread-c", "legacy").await?.is_none());
        drop(store);
        BotStateStore::new(path.clone()).db().await?;
        let store = BotStateStore::new(path.clone());
        let db = store.db().await?.clone();
        db.execute_unprepared(
            "INSERT INTO inbound_work(identity,bot_id,chat_id,message_id,content_hash,text,\
             open_id,chat_kind,generation,app_id,project_id,creation_id,binding_revision,\
             status,diagnostic,claimed_by,claimed_at,updated_at)\
             VALUES('legacy:chat:m1','legacy','chat','m1','hash','q','','group',1,'app',\
             'project','botthread:legacy:chat',1,'completed','','',0,1)",
        )
        .await?;
        assert_eq!(
            store
                .bind_thread("chat", "thread-c", "botthread:legacy:chat", "project", None)
                .await?,
            "thread-c"
        );
        let scope = store
            .audience_scope("thread-c", "legacy")
            .await?
            .expect("bound origin");
        assert!(
            !scope.origin.requires_upgrade,
            "a current creation target must not demand an upgrade"
        );
        // 显式创建意图：提交后中断，重试只靠持久证明完成同一创建。
        let draft = target::TargetClaim::from_operation(
            "legacy",
            "app",
            "project",
            "ui-chat",
            "botthread:legacy:ui-chat:op1",
            "op1",
            target::TargetKind::Group,
        );
        let operation = BindingOperation {
            operation_id: "op1".into(),
            bot_id: "legacy".into(),
            chat_id: "ui-chat".into(),
            content_hash: "hash".into(),
            expected_revision: 0,
            creation_id: "botthread:legacy:ui-chat:op1".into(),
            thread_id: None,
            target: draft.freeze(1),
        };
        store
            .begin_binding_operation("ui-chat", 0, "project", &operation)
            .await?;
        // 中断后的重试只从持久记录读取：完整证明（含具体来源）必须逐字恢复。
        let persisted = store
            .load_binding_operation("op1")
            .await?
            .expect("persisted creation intent");
        assert_eq!(
            persisted.target, operation.target,
            "continuation lost the persisted creation target"
        );
        assert_eq!(
            store
                .bind_thread(
                    "ui-chat",
                    "thread-u",
                    "botthread:legacy:ui-chat:op1",
                    "project",
                    None
                )
                .await?,
            "thread-u"
        );
        // operation 的最终 Thread 归属与 route/origin 同批提交：此刻不再需要第二次写入。
        let operation_thread: String = db
            .query_one_raw(statement(
                "SELECT thread_id FROM binding_operations WHERE operation_id='op1'",
                vec![],
            ))
            .await?
            .expect("retained operation row")
            .try_get("", "thread_id")?;
        assert_eq!(
            operation_thread, "thread-u",
            "the operation still pointed nowhere after the bound route was committed"
        );
        drop(store);
        // 在旧的「两次提交之间」这一刻模拟重启：库必须能打开且 origin 一致。
        let between_writes = BotStateStore::new(path.clone());
        between_writes.db().await?;
        let scope = between_writes
            .audience_scope("thread-u", "legacy")
            .await?
            .expect("origin committed with its operation");
        assert!(!scope.origin.requires_upgrade);
        drop(between_writes);
        // 生产序列紧随其后的保存仍是幂等的。
        let store = BotStateStore::new(path.clone());
        store.db().await?;
        store
            .save_binding_operation(&BindingOperation {
                thread_id: Some("thread-u".into()),
                ..operation
            })
            .await?;
        drop(store);
        // 开库校验必须接受这次续接的结果。
        let reopened = BotStateStore::new(path);
        reopened.db().await?;
        let scope = reopened
            .audience_scope("thread-u", "legacy")
            .await?
            .expect("resumed origin");
        assert!(!scope.origin.requires_upgrade);
        Ok(())
    }

    /// Evidence for one creating chat/creation may not be split across projects: a foreign
    /// project must abort the migration instead of being filtered out for the other kind.
    #[tokio::test]
    async fn schema9_foreign_project_creation_source_rolls_back()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("foreign-project.sqlite");
        let store = BotStateStore::new(path.clone());
        let db = store.db().await?.clone();
        remove_schema9_fixture(&db).await?;
        db.execute_unprepared(
            "DELETE FROM inbound_work; DELETE FROM thread_bindings;
             INSERT INTO inbound_work(identity, bot_id, chat_id, message_id, content_hash, text,
               open_id, chat_kind, app_id, project_id, creation_id, binding_revision, status,
               diagnostic, claimed_by, claimed_at, updated_at)
             VALUES('legacy:c1:m1','legacy','c1','m1','hash','q','peer','direct','app','project','botthread:legacy:c1',1,'completed','','',0,1),
                   ('legacy:c1:m2','legacy','c1','m2','hash','q','','group','app','other-project','botthread:legacy:c1',1,'completed','','',0,1);
             INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id,
               revision, generation, diagnostic, created_at, updated_at)
             VALUES('c1','','creating','botthread:legacy:c1','project',1,1,'',1,1);
             UPDATE bot_meta SET schema_version=8 WHERE id=1",
        )
        .await?;
        drop(store);
        assert!(
            BotStateStore::new(path).db().await.is_err(),
            "a foreign-project creation source was filtered out instead of conflicting"
        );
        let version: i64 = db
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .expect("retained metadata row")
            .try_get("", "schema_version")?;
        assert_eq!(version, 8, "foreign-project migration committed a version");
        assert!(
            db.query_one_raw(statement(
                "SELECT name FROM pragma_table_xinfo('thread_bindings') WHERE name='target_json'",
                vec![]
            ))
            .await?
            .is_none(),
            "foreign-project migration left a partially altered route table"
        );
        let route = db
            .query_one_raw(statement(
                "SELECT chat_id,status,creation_id,project_id,revision FROM thread_bindings",
                vec![],
            ))
            .await?
            .expect("retained binding row");
        assert_eq!(route.try_get::<String>("", "chat_id")?, "c1");
        assert_eq!(route.try_get::<String>("", "status")?, "creating");
        assert_eq!(
            route.try_get::<String>("", "creation_id")?,
            "botthread:legacy:c1"
        );
        assert_eq!(route.try_get::<String>("", "project_id")?, "project");
        assert_eq!(route.try_get::<i64>("", "revision")?, 1);
        Ok(())
    }

    /// A direct peer identity above the verified bound is rejected before any write, so no
    /// unaccounted copy can survive and no partial route is left behind.
    #[tokio::test]
    async fn creation_target_rejects_oversized_direct_peer()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("peer-bound.sqlite");
        let store = BotStateStore::new(path.clone());
        let db = store.db().await?.clone();
        let oversized = target::TargetClaim::from_inbound(
            "legacy",
            "app",
            "project",
            "chat",
            "botthread:legacy:chat",
            "m1",
            target::TargetKind::Direct {
                open_id: "p".repeat(target::MAX_PEER_BYTES + 1),
            },
        );
        assert!(
            store.claim_thread_binding(&oversized).await.is_err(),
            "an unbounded direct peer was frozen as a creation target"
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT chat_id FROM thread_bindings WHERE chat_id='chat'",
                vec![]
            ))
            .await?
            .is_none(),
            "a rejected direct peer still produced a partial binding row"
        );
        // 边界值本身仍然可用。
        let accepted = target::TargetClaim::from_inbound(
            "legacy",
            "app",
            "project",
            "chat",
            "botthread:legacy:chat",
            "m1",
            target::TargetKind::Direct {
                open_id: "p".repeat(target::MAX_PEER_BYTES),
            },
        );
        assert!(
            matches!(
                store.claim_thread_binding(&accepted).await?,
                ThreadBindingClaim::Creating { .. }
            ),
            "a peer exactly at the supported bound must still be accepted"
        );
        Ok(())
    }

    /// R9：入站退避预算耗尽时，`creating` 路由必须拿到终局（`needs_attention`），
    /// 不能留下永久占位；预算未耗尽时不得提前收束。
    #[tokio::test]
    async fn exhausted_inbound_budget_gives_the_creating_route_a_terminal_state()
    -> Result<(), Box<dyn std::error::Error>> {
        const DIAGNOSTIC: &str = "failed to create bot Thread: fixture";
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("budget.sqlite");
        let store = BotStateStore::new(path);
        let db = store.db().await?.clone();
        let claim = target::TargetClaim::from_operation(
            "botfixture",
            "app",
            "project",
            "chat-1",
            "botthread:botfixture:chat-1:op1",
            "op1",
            target::TargetKind::Group,
        );
        assert!(matches!(
            store.claim_thread_binding(&claim).await?,
            ThreadBindingClaim::Creating { .. }
        ));
        let inbound = FrozenInbound {
            bot_id: "botfixture".to_string(),
            message_id: "m1".to_string(),
            chat_id: "chat-1".to_string(),
            content_hash: "hash".to_string(),
            text: "hi".to_string(),
            attachments: Vec::new(),
            open_id: String::new(),
            chat_kind: "group".to_string(),
            app_id: "app".to_string(),
            project_id: "project".to_string(),
            creation_id: "botthread:botfixture:chat-1:op1".to_string(),
            binding_revision: 1,
            watch_input: String::new(),
        };
        assert!(matches!(
            store.admit_inbound(inbound).await?,
            InboundAdmit::Fresh(_)
        ));
        // 首次失败就属于“项目缺席”这一类：只保留有界退避，路由与入站都不收束。
        assert_eq!(
            store
                .claim_inbound_work("botfixture", "chat-1", "m1", "w1")
                .await?,
            InboundClaim::Claimed
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    "botfixture",
                    "chat-1",
                    "m1",
                    "w1",
                    WorkFinish::Retryable(DIAGNOSTIC),
                )
                .await?,
            MarkOutcome::Applied
        );
        let route = store
            .binding_for_chat("chat-1", "botfixture", "project")
            .await?;
        assert_eq!(
            route.status, "creating",
            "the first retryable failure must keep the creation intent"
        );
        assert_eq!(
            store
                .claim_inbound_work("botfixture", "chat-1", "m1", "w1")
                .await?,
            InboundClaim::NotDue,
            "the inbound keeps its recorded backoff instead of being consumed"
        );
        // 只把重试计数器推进到边界：真实退避需要等待分钟级时间，探针不允许 sleep；
        // 这里不涉及任何来源/证明事实（inbound 行本身由真实受理写入）。
        let seed = |attempt: i64| {
            let db = db.clone();
            async move {
                db.execute_unprepared(&format!(
                    "UPDATE inbound_work SET attempt_count={attempt}, status='pending', \
                     claimed_by='', claimed_at=0, next_attempt_at=0"
                ))
                .await
                .unwrap();
            }
        };
        // 未耗尽：下一次失败只计数，路由仍 creating、入站未被消费。
        seed(6).await;
        assert_eq!(
            store
                .claim_inbound_work("botfixture", "chat-1", "m1", "w1")
                .await?,
            InboundClaim::Claimed
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    "botfixture",
                    "chat-1",
                    "m1",
                    "w1",
                    WorkFinish::Retryable(DIAGNOSTIC),
                )
                .await?,
            MarkOutcome::Applied
        );
        let route = store
            .binding_for_chat("chat-1", "botfixture", "project")
            .await?;
        assert_eq!(
            route.status, "creating",
            "a retryable failure before the budget is exhausted must keep the creation intent"
        );
        assert_eq!(route.creation_id, "botthread:botfixture:chat-1:op1");
        assert_eq!(
            store
                .claim_inbound_work("botfixture", "chat-1", "m1", "w1")
                .await?,
            InboundClaim::NotDue,
            "the inbound must stay retryable with its recorded backoff"
        );

        // 耗尽：这一次失败必须让创建身份有终局。
        seed(7).await;
        assert_eq!(
            store
                .claim_inbound_work("botfixture", "chat-1", "m1", "w1")
                .await?,
            InboundClaim::Claimed
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    "botfixture",
                    "chat-1",
                    "m1",
                    "w1",
                    WorkFinish::Retryable(DIAGNOSTIC),
                )
                .await?,
            MarkOutcome::Applied
        );
        let route = store
            .binding_for_chat("chat-1", "botfixture", "project")
            .await?;
        assert_eq!(
            route.status, "needs_attention",
            "the exhausted budget must give the creating route a terminal state"
        );
        assert_eq!(
            route.creation_id, "botthread:botfixture:chat-1:op1",
            "no second creation intent may be invented"
        );
        assert!(route.thread_id.is_none());
        assert!(
            route.revision > 1,
            "the collapse must advance the route revision"
        );
        // 入站与 binding 的诊断可对账（同一基础原因）。
        let (diagnostic, applied_index) = match store.claim_thread_binding(&claim).await? {
            ThreadBindingClaim::NeedsAttention { diagnostic } => (diagnostic, true),
            _ => (String::new(), false),
        };
        assert!(
            applied_index,
            "the collapsed route must report needs-attention"
        );
        assert!(
            diagnostic.contains(DIAGNOSTIC),
            "binding diagnostic: {diagnostic}"
        );
        assert!(
            store
                .claim_thread_binding(&claim)
                .await
                .is_ok_and(|claim| matches!(claim, ThreadBindingClaim::NeedsAttention { .. })),
            "a collapsed creation identity stays fully described"
        );
        assert_eq!(
            store
                .claim_inbound_work("botfixture", "chat-1", "m1", "w1")
                .await?,
            InboundClaim::NeedsAttention,
            "the inbound must be collapsed with the binding, not silently dropped"
        );
        // 收束后原 claim 已释放：再次从唯一收束入口提交不能覆盖原终局或抬高路由版本。
        assert_eq!(
            store
                .finish_inbound_work(
                    "botfixture",
                    "chat-1",
                    "m1",
                    "w1",
                    WorkFinish::CreationConflict("again"),
                )
                .await?,
            MarkOutcome::LostClaim
        );
        let unchanged = store
            .binding_for_chat("chat-1", "botfixture", "project")
            .await?;
        assert_eq!(unchanged.status, route.status);
        assert_eq!(unchanged.revision, route.revision);
        assert_eq!(unchanged.creation_id, route.creation_id);
        assert_eq!(unchanged.diagnostic, route.diagnostic);
        // 可恢复：既有显式创建按当前 revision 替换该路由。
        let projection = store
            .binding_for_chat("chat-1", "botfixture", "project")
            .await?;
        let replacement = target::TargetClaim::from_operation(
            "botfixture",
            "app",
            "project",
            "chat-1",
            "botthread:botfixture:chat-1:op2",
            "op2",
            target::TargetKind::Group,
        );
        let operation = BindingOperation {
            operation_id: "op2".to_string(),
            bot_id: "botfixture".to_string(),
            chat_id: "chat-1".to_string(),
            content_hash: "hash2".to_string(),
            expected_revision: projection.revision,
            creation_id: "botthread:botfixture:chat-1:op2".to_string(),
            thread_id: None,
            target: replacement.freeze(projection.revision + 1),
        };
        store
            .begin_binding_operation("chat-1", projection.revision, "project", &operation)
            .await?;
        let rebound = store
            .binding_for_chat("chat-1", "botfixture", "project")
            .await?;
        assert_eq!(rebound.status, "creating");
        assert_eq!(rebound.creation_id, "botthread:botfixture:chat-1:op2");
        Ok(())
    }

    async fn remove_schema9_fixture(db: &DatabaseConnection) -> Result<(), sea_orm::DbErr> {
        // Reconstruct the actual pre-audience source shape, not a partially downgraded
        // current database whose pending rows still reference the replaced item table.
        // The historical source predates official completion records. Remove the tracking
        // table only at this fixture boundary; production must reject a contradictory log.
        db.execute_unprepared("DROP TABLE IF EXISTS seaql_migrations")
            .await?;
        db.execute_unprepared("DROP TABLE bot_delivery_pending;
            DROP TABLE bot_delivery_claims; DROP TABLE bot_delivery_cursors;
            DROP TABLE bot_delivery_items; DROP TABLE bot_delivery_scopes;
            DROP TABLE bot_sync_operations; DROP TABLE bot_authorizations; DROP TABLE bot_audience_origins;
            DROP INDEX IF EXISTS bot_legacy_unfinished_count; DROP INDEX IF EXISTS bot_legacy_unknown_count; DROP INDEX IF EXISTS bot_legacy_attention_count;
            DROP INDEX IF EXISTS bot_binding_creation_lookup; DROP INDEX IF EXISTS bot_legacy_work_scope;
            DROP INDEX IF EXISTS bot_legacy_unreadable_work; DROP INDEX IF EXISTS bot_legacy_identity_scope;
            DROP INDEX IF EXISTS bot_binding_thread_lookup; DROP INDEX IF EXISTS bot_route_thread_lookup; DROP INDEX IF EXISTS bot_card_thread_lookup;
            DROP INDEX IF EXISTS bot_route_creation_lookup;
            ALTER TABLE thread_bindings DROP COLUMN target_json;
            ALTER TABLE binding_operations DROP COLUMN target_json").await?;
        Ok(())
    }

    fn card_test_binding(message_id: &str) -> card::CardBinding {
        card::CardBinding {
            bot_id: "legacy".into(),
            chat_id: "chat".into(),
            message_id: message_id.into(),
            thread_id: "thread-1".into(),
            original_input: format!("bot:legacy:chat:{message_id}"),
        }
    }

    async fn migrated_card_entity(
        store: &BotStateStore,
        binding: &card::CardBinding,
    ) -> Result<publication::DeliveryEntity, Box<dyn std::error::Error>> {
        let scope = publication::DeliveryScopeKey::LegacyFinal {
            inbound_identity: inbound_identity(
                &binding.bot_id,
                &binding.chat_id,
                &binding.message_id,
            ),
        };
        Ok(store
            .delivery_entity(
                &scope,
                &publication::DeliveryEntityKey::LegacyFinal {
                    entity_id: binding.reply_operation(),
                },
            )
            .await?
            .ok_or("migration lost a retained card entity")?)
    }

    /// The old bytes remain the expected facts; never use the production converter to
    /// construct this expectation or ask the deleted legacy table for successful migration.
    async fn assert_migrated_card_material(
        store: &BotStateStore,
        original: &card::CardStream,
    ) -> Result<publication::DeliveryEntity, Box<dyn std::error::Error>> {
        use publication::{DeliveryAction, DeliveryResult, DeliveryScopeOrigin};
        use sha2::Digest;
        let entity = migrated_card_entity(store, &original.binding).await?;
        let scope = store
            .delivery_scope(&entity.scope)
            .await?
            .ok_or("missing legacy scope")?;
        assert_eq!(scope.bot_id, original.binding.bot_id);
        assert_eq!(scope.chat_id, original.binding.chat_id);
        assert_eq!(scope.thread_id, original.binding.thread_id);
        let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin else {
            panic!("migration fabricated frontend authority for an old card");
        };
        assert_eq!(legacy.original_input_id, original.binding.original_input);
        assert_eq!(legacy.watch_input, original.watch_input);
        assert_eq!(legacy.original_turn_id, original.turn_id);
        assert_eq!(entity.turn_id, original.turn_id);
        assert!(
            entity.item_order.is_none(),
            "migration fabricated canonical order"
        );
        let card = &entity.state.card;
        assert_eq!(card.card_id, original.card_id);
        assert_eq!(card.platform_message_id, original.platform_message_id);
        assert_eq!(card.sequence, original.sequence);
        assert_eq!(card.confirmed_sequence, original.confirmed_sequence);
        assert_eq!(card.lifecycle, Some(original.lifecycle));
        assert_eq!(card.confirmed_text, original.confirmed_text);
        assert_eq!(card.confirmed_content_hash, original.confirmed_content_hash);
        assert_eq!(card.final_content_hash, original.final_content_hash);
        assert_eq!(card.recovery_used, original.recovery_used);
        assert_eq!(card.diagnostic, original.diagnostic);
        assert!(
            original.recovery.is_none(),
            "fixture must explicitly check any recovery action"
        );
        assert!(card.recovery.is_none());
        assert!(
            entity.state.in_flight.is_none(),
            "old Intent must become Unknown, not replayable"
        );
        match (&original.last_operation, &entity.state.settled) {
            (None, None) => {}
            (Some(old), Some(settled)) => {
                let intent = &settled.intent;
                assert_eq!(intent.sequence, old.sequence);
                assert_eq!(intent.uuid, old.uuid);
                assert_eq!(
                    intent.legacy_action_hash.as_deref(),
                    Some(old.content_hash.as_str())
                );
                let body: serde_json::Value = serde_json::from_str(intent.request.body())?;
                let expected_target = match &old.action {
                    card::CardAction::Content { .. } => "elementContent",
                    card::CardAction::Settings { .. } => "settings",
                    _ => panic!("fixture operation needs an explicit old request target"),
                };
                assert_eq!(
                    serde_json::to_value(intent.request.target())?,
                    expected_target,
                    "migration must retain the old endpoint, not replace it with WholeCard"
                );
                let request_identity =
                    serde_json::to_vec(&(expected_target, intent.request.body()))?;
                assert_eq!(
                    intent.request_hash,
                    format!(
                        "sha256:{}",
                        hex::encode(sha2::Sha256::digest(&request_identity))
                    )
                );
                match (&old.action, &intent.action) {
                    (
                        card::CardAction::Content {
                            text,
                            final_content,
                        },
                        DeliveryAction::UpdateContent {
                            card_id,
                            text: actual,
                            final_content: actual_final,
                        },
                    ) => {
                        assert_eq!(Some(card_id), original.card_id.as_ref());
                        assert_eq!(actual, text);
                        assert_eq!(actual_final, final_content);
                        assert_eq!(
                            body,
                            serde_json::json!({
                                "content": text, "sequence": old.sequence, "uuid": old.uuid,
                            })
                        );
                    }
                    (
                        card::CardAction::Settings {
                            streaming,
                            lifecycle,
                            recovery,
                        },
                        DeliveryAction::UpdateSettings {
                            card_id,
                            streaming: actual_streaming,
                            lifecycle: actual_lifecycle,
                            recovery: actual_recovery,
                        },
                    ) => {
                        assert_eq!(Some(card_id), original.card_id.as_ref());
                        assert_eq!(actual_streaming, streaming);
                        assert_eq!(actual_lifecycle, lifecycle);
                        assert_eq!(actual_recovery, recovery);
                        assert_eq!(body["sequence"], old.sequence);
                        assert_eq!(body["uuid"], old.uuid);
                        let settings: serde_json::Value = serde_json::from_str(
                            body["settings"].as_str().ok_or("missing frozen settings")?,
                        )?;
                        assert_eq!(
                            settings,
                            serde_json::json!({"config": {
                                "streaming_mode": streaming, "summary": {"content": lifecycle.summary()},
                            }})
                        );
                    }
                    _ => panic!(
                        "migration changed the fixture operation kind or lost its parameters"
                    ),
                }
                match old.status {
                    card::CardOperationStatus::Intent | card::CardOperationStatus::Unknown => {
                        assert!(matches!(settled.result, DeliveryResult::Unknown { .. }));
                    }
                    card::CardOperationStatus::Confirmed => {
                        assert!(matches!(
                            settled.result,
                            DeliveryResult::ContentAccepted { .. }
                                | DeliveryResult::SettingsAccepted { .. }
                        ));
                    }
                    card::CardOperationStatus::Rejected => {
                        assert!(matches!(settled.result, DeliveryResult::Rejected { .. }));
                    }
                }
            }
            _ => panic!("migration lost or fabricated the last card operation"),
        }
        Ok(entity)
    }

    fn card_test_preview(binding: card::CardBinding) -> card::CardStream {
        card::CardStream {
            watch_input: binding.original_input.clone(),
            binding,
            turn_id: Some("original-turn".into()),
            version: 1,
            lifecycle: card::CardLifecycle::Streaming,
            card_id: Some("known-card".into()),
            platform_message_id: Some("known-message".into()),
            sequence: 0,
            confirmed_sequence: 0,
            confirmed_text: "last verified preview".into(),
            confirmed_content_hash: card::hash(b"last verified preview"),
            final_content_hash: None,
            last_operation: None,
            recovery_used: false,
            recovery: None,
            diagnostic: None,
        }
    }

    fn card_test_operation(
        action: card::CardAction,
        sequence: i32,
        status: card::CardOperationStatus,
    ) -> card::CardOperation {
        card::CardOperation {
            content_hash: card::hash(&serde_json::to_vec(&action).expect("fixture action encodes")),
            action,
            sequence,
            uuid: "0123456789abcdef0123456789abcdef".into(),
            status,
            diagnostic: None,
        }
    }

    fn card_test_no_final_diagnostic() -> pl_protocol::studio::BotDiagnostic {
        pl_protocol::studio::BotDiagnostic {
            code: "noFinalReply".into(),
            message: "未生成最终答复，所示内容仅为未完成预览".into(),
            retryable: false,
            platform_code: None,
            guidance: None,
        }
    }

    /// Only historical fixture material: no lease/version predicates, state transition, or
    /// current runtime API. The real official opener/codec is the subject of the assertions.
    async fn insert_legacy_card_fixture<C: ConnectionTrait>(
        db: &C,
        state: &card::CardStream,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let binding = &state.binding;
        db.execute_raw(statement(
            "INSERT INTO bot_card_streams(identity,bot_id,chat_id,message_id,thread_id,original_input,watch_input,turn_id,version,state_json,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,1)",
            vec![
                inbound_identity(&binding.bot_id, &binding.chat_id, &binding.message_id).into(),
                binding.bot_id.clone().into(),
                binding.chat_id.clone().into(),
                binding.message_id.clone().into(),
                binding.thread_id.clone().into(),
                binding.original_input.clone().into(),
                state.watch_input.clone().into(),
                state.turn_id.clone().unwrap_or_default().into(),
                state.version.into(),
                serde_json::to_string(state)?.into(),
            ],
        )).await?;
        Ok(())
    }

    fn config_with(enabled: bool, trusted_chat: bool, trusted_open: &[&str]) -> BotConfigFile {
        BotConfigFile {
            schema_version: BOT_CONFIG_SCHEMA_VERSION,
            id: BOT.to_string(),
            name: "fixture".to_string(),
            project_id: PROJECT.to_string(),
            platform: BotPlatformConfig::FeishuChina(FeishuBotConfig {
                app_id: APP.to_string(),
                trusted_open_ids: trusted_open.iter().map(|id| id.to_string()).collect(),
                trusted_chat_ids: if trusted_chat {
                    [CHAT.to_string()].into_iter().collect()
                } else {
                    Default::default()
                },
            }),
            enabled,
            tools_enabled: true,
            model_route: None,
            config_revision: 1,
            selected_ref: None,
            created_at: 1,
            updated_at: 1,
        }
    }

    fn config(enabled: bool, trusted_chat: bool) -> BotConfigFile {
        config_with(enabled, trusted_chat, &[])
    }

    fn group_first(config: &BotConfigFile) -> Option<FirstStart> {
        first_start(config, BOT, CHAT, APP, PROJECT, &TargetKind::Group)
    }

    fn creation() -> String {
        format!("botthread:{BOT}:{CHAT}:op1")
    }

    /// 与真实 route 同身份的 pending 授权（用于没有自动授权头的场景）。
    fn pending_at(creation_id: &str, generation: u64, binding_revision: u64) -> Authorization {
        Authorization {
            intent: AudienceStartIntent {
                // 与 `first_start` 生成并持久化的自动 operation 身份一致；这两个用例都在
                // 没有授权头的路由上构造 pending 事实，因此不能从 head() 取。
                operation_id: "botprepare:botfixture:chat-1:1".to_string(),
                thread_id: THREAD.to_string(),
                authorization: pl_protocol::BotAuthorizationId {
                    bot_id: BOT.to_string(),
                    chat_id: CHAT.to_string(),
                    generation,
                },
                binding_revision,
            },
            app_id: APP.to_string(),
            project_id: PROJECT.to_string(),
            creation_id: creation_id.to_string(),
            revision: 1,
            phase: BotAuthorizationPhase::PendingStart,
            start: None,
            closed: None,
            delivery_version: 1,
        }
    }

    /// 真实首次绑定路径：已冻结的创建意图 → 断言门控判据 → 原子绑定（含首次授权头）。
    async fn bind_first(
        path: &Path,
        config: &BotConfigFile,
    ) -> Result<BotStateStore, Box<dyn std::error::Error>> {
        bind_kind(path, config, TargetKind::Group).await
    }

    async fn bind_kind(
        path: &Path,
        config: &BotConfigFile,
        kind: TargetKind,
    ) -> Result<BotStateStore, Box<dyn std::error::Error>> {
        let store = BotStateStore::new(path.to_path_buf());
        store.binding_for_chat(CHAT, BOT, PROJECT).await?;
        let claim =
            TargetClaim::from_operation(BOT, APP, PROJECT, CHAT, &creation(), "op1", kind.clone());
        let operation = BindingOperation {
            operation_id: "op1".to_string(),
            bot_id: BOT.to_string(),
            chat_id: CHAT.to_string(),
            content_hash: "hash".to_string(),
            expected_revision: 0,
            creation_id: creation(),
            thread_id: None,
            target: claim.freeze(1),
        };
        store
            .begin_binding_operation(CHAT, 0, PROJECT, &operation)
            .await?;
        let first = first_start(config, BOT, CHAT, APP, PROJECT, &kind);
        store
            .bind_thread(CHAT, THREAD, &creation(), PROJECT, first.as_ref())
            .await?;
        Ok(store)
    }

    async fn head(store: &BotStateStore) -> Authorization {
        store
            .audience_scope(THREAD, BOT)
            .await
            .expect("audience scope")
            .expect("proven origin")
            .head
            .expect("authorization head")
    }

    fn receipt(intent: &AudienceStartIntent) -> AudienceStartReceipt {
        AudienceStartReceipt {
            version: 1,
            intent: intent.clone(),
            extension_revision: 1,
            sequence: 1,
            excluded_turn_id: None,
        }
    }

    fn request(
        operation_id: &str,
        action: BotThreadSyncAction,
        auth: &Authorization,
    ) -> ChangeBotThreadSyncRequest {
        ChangeBotThreadSyncRequest {
            operation_id: operation_id.to_string(),
            thread_id: THREAD.to_string(),
            action,
            expected: BotSyncCas {
                binding_revision: auth.intent.binding_revision,
                authorization_head: BotAuthorizationHead::Present {
                    authorization: auth.reference(),
                },
            },
        }
    }

    /// R1：首次授权判据只依据调用方已核验并冻结的目标事实 + 当前配置，不依赖账本行。
    /// 受信群且**从未收到任何入站消息**时必须建立 gen1 PendingStart；其余三种未获准情形不建立。
    #[tokio::test]
    async fn first_start_uses_frozen_target_and_current_permission()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("gate.sqlite");
        let trusted = config(true, true);
        // 旧判据（从账本推断 chat 种类）在这个真实状态下不可用：没有任何入站行。
        let probe = BotStateStore::new(path.clone());
        probe.binding_for_chat(CHAT, BOT, PROJECT).await?;
        assert!(
            probe.audience_target(CHAT).await.is_err(),
            "the ledger cannot classify a chat that never received an inbound message"
        );
        drop(probe);
        // 新判据只依赖冻结目标 + 当前配置。
        assert!(
            group_first(&trusted).is_some(),
            "a trusted group must establish its first authorization without ledger rows"
        );
        // 端到端：真实绑定 → gen1 PendingStart 存在。
        let store = bind_first(&path, &trusted).await?;
        let pending = head(&store).await;
        assert_eq!(pending.phase, BotAuthorizationPhase::PendingStart);
        assert_eq!(pending.intent.authorization.generation, 1);
        drop(store);
        // 未获准的三种情形一律不建立。
        assert!(
            group_first(&config(true, false)).is_none(),
            "an untrusted group must not be authorized"
        );
        assert!(
            group_first(&config(false, true)).is_none(),
            "a disabled bot must not authorize anything"
        );
        assert!(
            first_start(
                &trusted,
                BOT,
                CHAT,
                APP,
                PROJECT,
                &TargetKind::Direct {
                    open_id: String::new(),
                }
            )
            .is_none(),
            "an unknown direct peer identity must not be trusted by inference"
        );
        assert!(
            first_start(
                &trusted,
                BOT,
                CHAT,
                APP,
                PROJECT,
                &TargetKind::Direct {
                    open_id: "peer".to_string(),
                }
            )
            .is_none(),
            "a direct peer outside the trusted set must not be authorized"
        );
        assert!(
            first_start(
                &config_with(true, false, &["peer"]),
                BOT,
                CHAT,
                APP,
                PROJECT,
                &TargetKind::Direct {
                    open_id: "peer".to_string(),
                }
            )
            .is_some(),
            "a trusted direct peer must be authorized from the frozen identity"
        );
        // 身份不匹配（app/project）同样不建立。
        let mut changed = trusted.clone();
        changed.project_id = "other-project".to_string();
        assert!(group_first(&changed).is_none());
        Ok(())
    }

    /// P1：没有任何首入站消息的新群会话，首次绑定后自动出现 generation 1 PendingStart，
    /// 由同一 intent/op 推进到 Active；重启只看到一个 intent，不重复切 cut、不多推进
    /// delivery_version，也不需要手动 Enable。
    #[tokio::test]
    async fn first_binding_commits_pending_start_and_resumes_once()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path: PathBuf = directory.path().join("first-start.sqlite");
        let store = bind_first(&path, &config(true, true)).await?;
        let scope = store
            .audience_scope(THREAD, BOT)
            .await?
            .expect("origin written with the binding");
        let Some(pending) = scope.head else {
            panic!("a permitted first binding must freeze its first authorization");
        };
        assert_eq!(pending.intent.authorization.generation, 1);
        assert_eq!(pending.phase, BotAuthorizationPhase::PendingStart);
        // 自动 operation 身份是持久事实：首绑写入的正是 `botprepare:<bot>:<chat>:1`
        // （`audience::command::first_start_operation` 的生成结果，这里按持久值断言）。
        assert_eq!(
            pending.intent.operation_id,
            "botprepare:botfixture:chat-1:1"
        );
        assert_eq!(pending.intent.binding_revision, 1);
        assert_eq!(pending.delivery_version, 1);
        assert!(pending.start.is_none());
        assert!(pending.closed.is_none());
        // 未激活时本机输入等待：Preparing 只表示确有正在准备的 cut。
        assert_eq!(
            store.thread_input_readiness(BOT, THREAD, PROJECT).await?,
            BotThreadInputReadiness::Preparing
        );
        drop(store);

        // 重启：同一库、同一 intent，只有一条待推进记录；不需要手动 Enable。
        let reopened = BotStateStore::new(path.clone());
        reopened.binding_for_chat(CHAT, BOT, PROJECT).await?;
        let pendings = reopened.pending_syncs(("", 0)).await?;
        assert_eq!(pendings.len(), 1, "restart must not open another intent");
        assert_eq!(pendings[0].intent, pending.intent);
        let receipt = receipt(&pendings[0].intent);
        let activated = reopened.activate_sync(&receipt).await?;
        assert!(
            activated.changed,
            "the saved cut must activate this generation"
        );
        assert_eq!(activated.authorization.phase, BotAuthorizationPhase::Active);
        assert_eq!(activated.authorization.start.as_ref(), Some(&receipt));
        assert_eq!(activated.authorization.intent, pending.intent);
        assert_eq!(
            activated.authorization.delivery_version, 1,
            "activation must not advance the delivery version"
        );
        assert_eq!(
            reopened
                .thread_input_readiness(BOT, THREAD, PROJECT)
                .await?,
            BotThreadInputReadiness::Ready
        );
        // 同一 Saved 再次到达：不再切 cut、不再改代、不再加 revision。
        let again = reopened.activate_sync(&receipt).await?;
        assert!(!again.changed);
        assert_eq!(
            again.authorization.revision,
            activated.authorization.revision
        );
        assert_eq!(again.authorization.start.as_ref(), Some(&receipt));
        drop(reopened);

        let third = BotStateStore::new(path);
        third.binding_for_chat(CHAT, BOT, PROJECT).await?;
        let settled = head(&third).await;
        assert_eq!(settled.phase, BotAuthorizationPhase::Active);
        assert_eq!(settled.intent.authorization.generation, 1);
        assert_eq!(settled.start.as_ref(), Some(&receipt));
        assert_eq!(settled.delivery_version, 1);
        Ok(())
    }

    /// P2：撤权/停用/绑定不可用都必须显式 Closed 且记录真实原因；PendingStart 同样被封闭，
    /// 之后 enable(true) 只开新代，不复活旧代、不自动授信。
    #[tokio::test]
    async fn revocation_closes_explicitly_and_enable_only_opens_a_new_generation()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("closed.sqlite");
        let store = bind_first(&path, &config(true, true)).await?;
        let pending = head(&store).await;
        assert_eq!(pending.phase, BotAuthorizationPhase::PendingStart);

        // 停用：PendingStart 也必须落到 Closed(BotDisabled)。
        let (changed, _) = store
            .prune_authorization_page(&config(false, true), ("", 0))
            .await?;
        assert!(
            changed,
            "disabling the bot must close the pending generation"
        );
        let closed = head(&store).await;
        assert_eq!(closed.phase, BotAuthorizationPhase::Closed);
        assert_eq!(
            closed.closed.as_ref().map(|(reason, _)| *reason),
            Some(BotAudienceCloseReason::BotDisabled)
        );

        // enable(true) 只在 Closed 上开新代；旧代保持原样。
        let enabled = config(true, true);
        let reopened = store
            .change_sync(
                &request("enable-1", BotThreadSyncAction::Enable, &closed),
                &enabled,
            )
            .await?;
        assert!(reopened.changed);
        assert_eq!(
            reopened.authorization.phase,
            BotAuthorizationPhase::PendingStart
        );
        assert_eq!(
            reopened.authorization.intent.authorization.generation, 2,
            "enable must open the next generation, not revive the closed one"
        );
        let old = store
            .audience_authorization(&closed.intent.authorization)
            .await?
            .expect("closed generation retained");
        assert_eq!(old.phase, BotAuthorizationPhase::Closed);
        assert_eq!(
            old.closed.as_ref().map(|(reason, _)| *reason),
            Some(BotAudienceCloseReason::BotDisabled)
        );
        // PendingStart 不能被 Enable 顶替/复活。
        assert!(
            store
                .change_sync(
                    &request(
                        "enable-2",
                        BotThreadSyncAction::Enable,
                        &reopened.authorization
                    ),
                    &enabled
                )
                .await
                .is_err(),
            "a pending generation must not be replaced by another enable"
        );
        drop(store);

        // 撤回信任（enabled 但不在 trusted 列表）→ TrustRevoked。
        let untrusted_path = directory.path().join("trust.sqlite");
        let untrusted = bind_first(&untrusted_path, &config(true, true)).await?;
        let (changed, _) = untrusted
            .prune_authorization_page(&config(true, false), ("", 0))
            .await?;
        assert!(changed);
        let closed = head(&untrusted).await;
        assert_eq!(closed.phase, BotAuthorizationPhase::Closed);
        assert_eq!(
            closed.closed.as_ref().map(|(reason, _)| *reason),
            Some(BotAudienceCloseReason::TrustRevoked)
        );
        drop(untrusted);

        // 绑定不可用 → BindingUnavailable（真实路径：mark_binding_attention）。
        let unavailable_path = directory.path().join("unavailable.sqlite");
        let unavailable = bind_first(&unavailable_path, &config(true, true)).await?;
        let before = head(&unavailable).await;
        let scope = unavailable
            .audience_scope(THREAD, BOT)
            .await?
            .expect("origin");
        assert!(
            unavailable
                .mark_binding_attention(
                    &BoundThreadExpectation {
                        chat_id: CHAT.to_string(),
                        thread_id: THREAD.to_string(),
                        creation_id: creation(),
                        project_id: PROJECT.to_string(),
                        revision: scope.binding.revision,
                    },
                    "fixture attention",
                )
                .await?
        );
        // attention 之后路由不再是 bound：直接读该代授权行验证封闭原因。
        let closed = unavailable
            .audience_authorization(&before.intent.authorization)
            .await?
            .expect("closed head retained");
        assert_eq!(
            closed.closed.as_ref().map(|(reason, _)| *reason),
            Some(BotAudienceCloseReason::BindingUnavailable)
        );
        Ok(())
    }

    /// P3：Close 之后到达的 Saved 只能得到 Closed —— 不激活、不改 revision/原因、不推进
    /// delivery_version、不产生 start。
    #[tokio::test]
    async fn late_saved_after_close_never_revives() -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("late-saved.sqlite");
        let store = bind_first(&path, &config(true, true)).await?;
        let pending = head(&store).await;
        let closed = store
            .change_sync(
                &request("close-1", BotThreadSyncAction::Close, &pending),
                &config(true, true),
            )
            .await?;
        assert!(closed.changed);
        assert_eq!(closed.authorization.phase, BotAuthorizationPhase::Closed);
        assert_eq!(
            closed
                .authorization
                .closed
                .as_ref()
                .map(|(reason, _)| *reason),
            Some(BotAudienceCloseReason::LocalClose)
        );
        let settled_revision = closed.authorization.revision;
        let settled_delivery = closed.authorization.delivery_version;

        let late = store.activate_sync(&receipt(&pending.intent)).await?;
        assert!(!late.changed, "a closed generation must not activate");
        assert_eq!(late.authorization.phase, BotAuthorizationPhase::Closed);
        assert_eq!(late.authorization.revision, settled_revision);
        assert_eq!(late.authorization.closed, closed.authorization.closed);
        assert_eq!(late.authorization.delivery_version, settled_delivery);
        assert!(late.authorization.start.is_none());
        drop(store);

        // 新实例读同一事实：仍是 Closed(LocalClose)，没有 start。
        let reopened = BotStateStore::new(path);
        reopened.binding_for_chat(CHAT, BOT, PROJECT).await?;
        let settled = head(&reopened).await;
        assert_eq!(settled.phase, BotAuthorizationPhase::Closed);
        assert_eq!(
            settled.closed.as_ref().map(|(reason, _)| *reason),
            Some(BotAudienceCloseReason::LocalClose)
        );
        assert!(settled.start.is_none());
        assert_eq!(settled.delivery_version, settled_delivery);
        Ok(())
    }

    /// R2：自动建立的 operation 身份不得被后续显式 Enable 复用（跨代复用会让宿主拒绝该代
    /// cut）。复用必须 typed conflict 且不写新代；换全新 id 仍能开新代并激活。
    #[tokio::test]
    async fn auto_start_operation_id_cannot_be_reused_by_a_later_enable()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("operation-reuse.sqlite");
        let store = bind_first(&path, &config(true, true)).await?;
        let pending = head(&store).await;
        let enabled = config(true, true);
        let closed = store
            .change_sync(
                &request("close-1", BotThreadSyncAction::Close, &pending),
                &enabled,
            )
            .await?;
        assert_eq!(closed.authorization.phase, BotAuthorizationPhase::Closed);
        // 复用自动 operation id 的 Enable：必须在写库前确定性拒绝。
        let reused = pending.intent.operation_id.clone();
        let rejected = match store
            .change_sync(
                &request(&reused, BotThreadSyncAction::Enable, &closed.authorization),
                &enabled,
            )
            .await
        {
            Err(error) => error,
            Ok(_) => panic!("reusing the automatic operation id must be a typed conflict"),
        };
        assert_eq!(
            rejected.kind(),
            FeishuErrorKind::Conflict,
            "the reuse must be reported as a conflict, not as another failure"
        );
        assert!(
            store
                .audience_authorization(&pl_protocol::BotAuthorizationId {
                    bot_id: BOT.to_string(),
                    chat_id: CHAT.to_string(),
                    generation: 2,
                })
                .await?
                .is_none(),
            "a rejected reuse must not write the next generation"
        );
        // 全新 id 仍能正常开新代并激活。
        let fresh = store
            .change_sync(
                &request(
                    "enable-fresh",
                    BotThreadSyncAction::Enable,
                    &closed.authorization,
                ),
                &enabled,
            )
            .await?;
        assert_eq!(fresh.authorization.intent.authorization.generation, 2);
        assert_eq!(
            fresh.authorization.phase,
            BotAuthorizationPhase::PendingStart
        );
        let activated = store
            .activate_sync(&receipt(&fresh.authorization.intent))
            .await?;
        assert_eq!(activated.authorization.phase, BotAuthorizationPhase::Active);
        Ok(())
    }

    /// R4：恢复路径的权限重核必须用该 chat 持久化的 typed 证明，不能回到账本推断。
    #[tokio::test]
    async fn prepare_permission_uses_the_persisted_typed_target()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        // A. GUI 新建群：Created{Group} 证明 + 零 inbound/observed 行。
        let group_path = directory.path().join("prepare-group.sqlite");
        let group = bind_first(&group_path, &config(true, true)).await?;
        let pending = head(&group).await;
        assert!(
            group.audience_target(CHAT).await.is_err(),
            "the ledger still cannot classify a chat that never received an inbound message"
        );
        prepare_permission(&group, &config(true, true), &pending)
            .await
            .expect("the recovery recheck must use the persisted typed target");
        // 撤权事实 → Permission，并按真实原因关闭。
        let untrusted = prepare_permission(&group, &config(true, false), &pending)
            .await
            .expect_err("an untrusted group must not pass the recheck");
        assert_eq!(untrusted.kind(), FeishuErrorKind::Permission);
        assert_eq!(
            permission_close_reason(&config(true, false)),
            BotAudienceCloseReason::TrustRevoked
        );
        assert_eq!(
            permission_close_reason(&config(false, true)),
            BotAudienceCloseReason::BotDisabled
        );
        drop(group);

        // B. Direct 证明：判据来自 proof 里的 open_id，而不是 observed_directs。
        let direct_path = directory.path().join("prepare-direct.sqlite");
        let peer = TargetKind::Direct {
            open_id: "peer".to_string(),
        };
        let direct = bind_kind(&direct_path, &config(true, false), peer.clone()).await?;
        // 同一共享门控的拒绝由紧随其后的 `prepare_permission` 断言与真实用例覆盖。
        let pending = pending_at(&creation(), 1, 1);
        let rejected = prepare_permission(&direct, &config(true, false), &pending)
            .await
            .expect_err("an untrusted direct peer must not pass the recheck");
        assert_eq!(rejected.kind(), FeishuErrorKind::Permission);
        prepare_permission(&direct, &config_with(true, false, &["peer"]), &pending)
            .await
            .expect("a trusted direct peer must pass from its frozen identity");
        Ok(())
    }

    /// R7：Created 证明与 pending auth / route 的身份必须逐字段等值；「无 binding 行」不得
    /// 回退账本推断。错配一律 fail-closed（不关闭真实授权）。
    #[tokio::test]
    async fn prepare_permission_requires_matching_identity()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("identity.sqlite");
        let store = bind_first(&path, &config(true, true)).await?;
        let auth = head(&store).await;
        let trusted = config(true, true);
        prepare_permission(&store, &trusted, &auth)
            .await
            .expect("matching route/proof/pending identity");

        let cases: [(&str, Authorization); 6] = [
            ("other chat", {
                let mut broken = auth.clone();
                broken.intent.authorization.chat_id = "other-chat".to_string();
                broken
            }),
            ("other creation", {
                let mut broken = auth.clone();
                broken.creation_id = "botthread:other".to_string();
                broken
            }),
            ("other binding revision", {
                let mut broken = auth.clone();
                broken.intent.binding_revision = 2;
                broken
            }),
            ("other bot", {
                let mut broken = auth.clone();
                broken.intent.authorization.bot_id = "otherbotfixture".to_string();
                broken
            }),
            ("other app", {
                let mut broken = auth.clone();
                broken.app_id = "other-app".to_string();
                broken
            }),
            ("other project", {
                let mut broken = auth.clone();
                broken.project_id = "other-project".to_string();
                broken
            }),
        ];
        for (label, broken) in cases {
            let error = match prepare_permission(&store, &trusted, &broken).await {
                Ok(()) => panic!("{label} must not pass the recovery recheck"),
                Err(error) => error,
            };
            assert_eq!(
                error.kind(),
                FeishuErrorKind::Unavailable,
                "{label} must fail closed as an inconsistency, not as a permission fact"
            );
            assert!(!error.retryable(), "{label} is not a transient failure");
        }
        // 错配不得关闭真实授权：head 仍是 PendingStart。
        assert_eq!(
            head(&store).await.phase,
            BotAuthorizationPhase::PendingStart,
            "an inconsistent identity must not close the pending authorization"
        );
        drop(store);

        // 「无 binding 行」即使账本可分类，也必须 fail-closed。
        let orphan_path = directory.path().join("orphan.sqlite");
        let orphan = BotStateStore::new(orphan_path);
        orphan.binding_for_chat(CHAT, BOT, PROJECT).await?;
        orphan.observe_direct(CHAT, Some("peer"), None).await?;
        assert!(
            orphan.audience_target(CHAT).await.is_ok(),
            "the ledger can classify this chat, so a fallback would wrongly pass"
        );
        let error = match prepare_permission(
            &orphan,
            &config_with(true, false, &["peer"]),
            &pending_at(&creation(), 1, 1),
        )
        .await
        {
            Ok(()) => panic!("a missing binding row must not fall back to the ledger"),
            Err(error) => error,
        };
        assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
        Ok(())
    }

    /// R3：未获许可的首次绑定不建立授权头，且该已绑定 Thread 在本机必须 `Ready`
    /// （不能永久 `Preparing` 阻塞输入）。
    #[tokio::test]
    async fn unpermitted_binding_establishes_no_authorization_and_stays_ready()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("unpermitted.sqlite");
        let store = bind_first(&path, &config(true, false)).await?;
        let scope = store.audience_scope(THREAD, BOT).await?.expect("origin");
        assert!(
            scope.head.is_none(),
            "an unverified permission must not freeze an authorization"
        );
        assert_eq!(
            store.thread_input_readiness(BOT, THREAD, PROJECT).await?,
            BotThreadInputReadiness::Ready,
            "a bound Thread without any authorization head must stay locally usable"
        );
        Ok(())
    }

    /// R8：创建身份不可重试冲突必须一次性收束为可见需处理状态；可重试分类不得收束。
    #[tokio::test]
    async fn identity_conflict_collapses_the_creating_route_once()
    -> Result<(), Box<dyn std::error::Error>> {
        const DIAGNOSTIC: &str = "conversation Thread creation identity cannot be bound";
        // 纯分类/项目事实探针就近放在 `bots::creation` 的单元测试里（纯函数，不涉持久状态）。

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("identity-conflict.sqlite");
        let store = BotStateStore::new(path);
        store.binding_for_chat(CHAT, BOT, PROJECT).await?;
        let claim_target = TargetClaim::from_operation(
            BOT,
            APP,
            PROJECT,
            CHAT,
            &creation(),
            "op1",
            TargetKind::Group,
        );
        assert!(matches!(
            store.claim_thread_binding(&claim_target).await?,
            ThreadBindingClaim::Creating { .. }
        ));
        // 可重试分类（`bots::creation` 的纯函数探针）下不收束：创建意图仍保留。
        assert!(matches!(
            store.claim_thread_binding(&claim_target).await?,
            ThreadBindingClaim::Creating { .. }
        ));

        assert!(matches!(
            store.admit_inbound(probe_inbound("m-conflict")).await?,
            InboundAdmit::Fresh(_)
        ));
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, "m-conflict", "worker")
                .await?,
            InboundClaim::Claimed
        );
        let identity = inbound_identity(BOT, CHAT, "m-conflict");
        let before = work_ledger(&store, &identity).await;
        // 失认领不能先关闭路由；仍有效的 owner 也必须原子提交两行。
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-conflict",
                    "stale",
                    WorkFinish::CreationConflict(DIAGNOSTIC)
                )
                .await?,
            MarkOutcome::LostClaim
        );
        assert_eq!(
            store.binding_for_chat(CHAT, BOT, PROJECT).await?.status,
            "creating"
        );
        assert_eq!(work_ledger(&store, &identity).await, before);
        let db = store.db().await?;
        db.execute_unprepared("CREATE TRIGGER stop_creation_finish BEFORE UPDATE OF status ON thread_bindings WHEN NEW.status='needs_attention' BEGIN SELECT RAISE(ABORT,'controlled route settlement fault'); END").await?;
        assert!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-conflict",
                    "worker",
                    WorkFinish::CreationConflict(DIAGNOSTIC)
                )
                .await
                .is_err()
        );
        assert_eq!(
            work_ledger(&store, &identity).await,
            before,
            "route settlement failure must roll back the inbound terminal write"
        );
        assert_eq!(
            store.binding_for_chat(CHAT, BOT, PROJECT).await?.status,
            "creating"
        );
        db.execute_unprepared("DROP TRIGGER stop_creation_finish")
            .await?;

        // 身份冲突：工作与路由一次性收束；重复旧认领不再写入。
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-conflict",
                    "worker",
                    WorkFinish::CreationConflict(DIAGNOSTIC)
                )
                .await?,
            MarkOutcome::Applied,
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-conflict",
                    "worker",
                    WorkFinish::CreationConflict(DIAGNOSTIC)
                )
                .await?,
            MarkOutcome::LostClaim,
            "the collapse must happen exactly once"
        );
        let work = work_ledger(&store, &identity).await;
        assert_eq!(work.status, "needs_attention");
        assert_eq!(
            work.attempt_count, 0,
            "a proven conflict must not consume retries"
        );
        match store.claim_thread_binding(&claim_target).await? {
            ThreadBindingClaim::NeedsAttention { diagnostic } => {
                assert_eq!(diagnostic, DIAGNOSTIC, "the real reason must be visible");
            }
            _ => panic!("a collapsed creation identity must report needs-attention"),
        }
        let projection = store.binding_for_chat(CHAT, BOT, PROJECT).await?;
        assert_eq!(projection.status, "needs_attention");
        assert_eq!(
            projection.creation_id,
            creation(),
            "the collapsed route must keep the original creation identity"
        );
        assert!(
            projection.thread_id.is_none(),
            "no partially bound Thread may be recorded"
        );

        // 既有恢复入口：显式创建可以按当前 revision 替换该路由（新操作/新创建意图），
        // 因此不会把该 chat 永久挡住。
        let replacement = TargetClaim::from_operation(
            BOT,
            APP,
            PROJECT,
            CHAT,
            "botthread:botfixture:chat-1:op2",
            "op2",
            TargetKind::Group,
        );
        let operation = BindingOperation {
            operation_id: "op2".to_string(),
            bot_id: BOT.to_string(),
            chat_id: CHAT.to_string(),
            content_hash: "hash2".to_string(),
            expected_revision: projection.revision,
            creation_id: "botthread:botfixture:chat-1:op2".to_string(),
            thread_id: None,
            target: replacement.freeze(projection.revision + 1),
        };
        store
            .begin_binding_operation(CHAT, projection.revision, PROJECT, &operation)
            .await?;
        let rebound = store.binding_for_chat(CHAT, BOT, PROJECT).await?;
        assert_eq!(rebound.status, "creating");
        assert_eq!(
            rebound.creation_id, operation.creation_id,
            "recovery replaces the intent instead of creating a second one"
        );
        assert_eq!(rebound.revision, projection.revision + 1);
        Ok(())
    }

    /// 原发送行与公开实体同事务推进，未知结果不重发，迟到结果不覆盖另一阶段。
    #[tokio::test]
    async fn publication_file_stages_commit_with_entity_and_preserve_late_results()
    -> Result<(), Box<dyn std::error::Error>> {
        use publication::{
            DeliveryCandidate, DeliveryCandidateContent, DeliveryClaimOutcome, DeliveryInputChain,
            DeliveryScopeKey, SavedArtifact,
        };
        use sha2::Digest;
        let directory = tempfile::tempdir()?;
        let store = bind_first(
            &directory.path().join("file-stages.sqlite"),
            &config(true, true),
        )
        .await?;
        let pending = head(&store).await;
        store.activate_sync(&receipt(&pending.intent)).await?;
        let scope_key = DeliveryScopeKey::Frontend {
            authorization: pending.intent.authorization.clone(),
        };
        let scope = store.delivery_scope(&scope_key).await?.unwrap();
        let DeliveryClaimOutcome::Acquired(token) =
            store.claim_delivery_scope(&scope_key, "file-owner").await?
        else {
            panic!("active frontend scope must be claimable");
        };
        let resources =
            crate::resource_store::FileResourceStore::new(directory.path().join("send-resources"));
        let resource = resources
            .retain_bytes(
                std::sync::Arc::from(b"exact original".as_slice()),
                "text/plain",
            )
            .await?;
        let artifact = SavedArtifact::from_metadata(&crate::studio::TimelineItemMetadata {
            shell: pl_protocol::ThreadItem::new(
                "artifact-item".into(),
                THREAD.into(),
                "gui-turn".into(),
                2,
                1,
                1,
                1,
                pl_protocol::ThreadItemState::PublicArtifact(
                    pl_protocol::ThreadPublicArtifactItem {
                        publication_id: "publication".into(),
                        tool_call_id: "publish-call".into(),
                        display_name: "report.txt".into(),
                        published_at: 1,
                        resource: pl_protocol::ThreadArtifactResource {
                            id: resource.id().into(),
                            content_digest: resource.content_digest().into(),
                            byte_len: resource.byte_len(),
                            media_type: resource.media_type().into(),
                        },
                    },
                ),
            ),
            fields: vec![],
            saved: true,
            lifecycle: pl_protocol::TimelineLifecycle::Terminal,
        })?;
        let key = artifact.entity_key();
        store
            .merge_delivery_candidate(
                &token,
                &DeliveryCandidate {
                    entity: key.clone(),
                    turn_id: artifact.turn_id().into(),
                    item_order: artifact.item_order(),
                    input_chain: DeliveryInputChain::Proven {
                        input_id: "gui-input".into(),
                        continuation_ancestors: vec![],
                    },
                    content: DeliveryCandidateContent::File {
                        artifact: artifact.clone(),
                    },
                },
            )
            .await?;
        let entity = store.delivery_entity(&scope_key, &key).await?.unwrap();
        let permit = PublicationFilePermit {
            token,
            entity: key.clone(),
            expected_ledger_version: entity.ledger_version,
            artifact: artifact.clone(),
        };
        let operation = "publication-send";
        let segments = vec![SendContent::File {
            filename: "report.txt".into(),
            upload_filename: "report.txt".into(),
            resource,
        }];
        let uuid = hex::encode(sha2::Sha256::digest(serde_json::to_vec(&(
            operation, BOT, CHAT, 0usize,
        ))?))[..32]
            .to_string();
        let record = crate::bots::send_service::into_record(
            operation.into(),
            BOT.into(),
            CHAT.into(),
            super::super::send::SendPlan {
                content_hash: publication::delivery_file_plan_hash(
                    &scope, &key, &artifact, operation, &segments,
                )?,
                identity: SendIdentity::File {
                    request_hash: publication::delivery_file_request_hash(&scope, &key, &artifact)?,
                },
                source: None,
                segments,
                uuids: vec![uuid.clone()],
                retention: None,
            },
        );
        let mut stale = permit.clone();
        stale.expected_ledger_version += 1;
        assert!(
            store
                .claim_publication_file_send(&record, &stale)
                .await
                .is_err()
        );
        assert!(
            store.load_send(operation).await?.is_none(),
            "failed binding must roll back the send claim"
        );
        assert!(
            store
                .claim_publication_file_send(&record, &permit)
                .await?
                .is_none()
        );
        assert!(
            store
                .claim_publication_file_send(&record, &permit)
                .await?
                .is_some()
        );
        assert!(
            store
                .begin_publication_file_stage(operation, &permit, PublicationFileStage::Message)
                .await
                .is_err()
        );

        let mut cancelled = store
            .begin_publication_file_stage(operation, &permit, PublicationFileStage::Upload)
            .await?;
        assert!(
            store
                .settle_publication_file_stage(
                    &mut cancelled,
                    PublicationFileProgress::Uploaded {
                        file_key: "unstarted".into()
                    }
                )
                .await
                .is_err()
        );
        store
            .settle_publication_file_stage(
                &mut cancelled,
                PublicationFileProgress::NotStarted {
                    stage: PublicationFileStage::Upload,
                    reason: pl_protocol::studio::BotSendStopReason::Cancelled,
                    diagnostic: "before HTTP".into(),
                },
            )
            .await?;
        let mut upload = store
            .begin_publication_file_stage(operation, &permit, PublicationFileStage::Upload)
            .await?;
        upload.mark_request_started();
        store
            .settle_publication_file_stage(
                &mut upload,
                PublicationFileProgress::Unknown {
                    stage: PublicationFileStage::Upload,
                    diagnostic: None,
                },
            )
            .await?;
        assert!(
            store
                .begin_publication_file_stage(operation, &permit, PublicationFileStage::Upload)
                .await
                .is_err(),
            "Unknown must not replay upload"
        );
        let db = store.db().await?;
        db.execute_unprepared("CREATE TRIGGER stop_file_projection BEFORE UPDATE ON bot_delivery_items BEGIN SELECT RAISE(ABORT,'controlled file projection fault'); END").await?;
        assert!(
            store
                .settle_publication_file_stage(
                    &mut upload,
                    PublicationFileProgress::Uploaded {
                        file_key: "upload-key".into()
                    }
                )
                .await
                .is_err()
        );
        assert_eq!(
            store.load_send(operation).await?.unwrap().segments[0].upload,
            Some(UploadFact::Unknown),
            "projection failure must roll back the send result too"
        );
        db.execute_unprepared("DROP TRIGGER stop_file_projection")
            .await?;
        store
            .settle_publication_file_stage(
                &mut upload,
                PublicationFileProgress::Uploaded {
                    file_key: "upload-key".into(),
                },
            )
            .await?;
        assert!(
            store
                .begin_publication_file_stage(operation, &permit, PublicationFileStage::Upload)
                .await
                .is_err(),
            "accepted upload must not repeat"
        );
        let mut message = store
            .begin_publication_file_stage(operation, &permit, PublicationFileStage::Message)
            .await?;
        message.mark_request_started();
        let active = head(&store).await;
        store
            .change_sync(
                &request("close-file", BotThreadSyncAction::Close, &active),
                &config(true, true),
            )
            .await?;
        let sent = store
            .settle_publication_file_stage(
                &mut message,
                PublicationFileProgress::Sent {
                    message_id: "message-id".into(),
                },
            )
            .await?;
        assert_eq!(sent.segments[0].uuid, uuid);
        assert_eq!(sent.platform_message_ids, ["message-id"]);
        let late = store
            .settle_publication_file_stage(
                &mut upload,
                PublicationFileProgress::Unknown {
                    stage: PublicationFileStage::Upload,
                    diagnostic: None,
                },
            )
            .await?;
        assert_eq!(
            late.segments[0].upload,
            Some(UploadFact::Accepted {
                file_key: "upload-key".into()
            })
        );
        assert_eq!(
            late.segments[0].message_stage,
            Some(MessageStage::Accepted),
            "late upload result must not overwrite message progress"
        );
        assert!(
            store
                .settle_publication_file_stage(
                    &mut cancelled,
                    PublicationFileProgress::NotStarted {
                        stage: PublicationFileStage::Upload,
                        reason: pl_protocol::studio::BotSendStopReason::Cancelled,
                        diagnostic: "stale stop".into(),
                    }
                )
                .await
                .is_err()
        );
        let delivered = store.delivery_entity(&scope_key, &key).await?.unwrap();
        assert_eq!(
            delivered.state.accepted,
            pl_protocol::studio::BotItemPresentation::File {
                revision: artifact.revision()
            }
        );
        assert_eq!(head(&store).await.phase, BotAuthorizationPhase::Closed);
        Ok(())
    }

    /// 入站账本的完整持久行（就绪等待/失败预算探针共用）。
    #[derive(Debug, PartialEq, Eq)]
    struct WorkLedger {
        status: String,
        diagnostic: String,
        claimed_by: String,
        attempt_count: i64,
        next_attempt_at: i64,
    }

    async fn work_ledger(store: &BotStateStore, identity: &str) -> WorkLedger {
        let db = store.db().await.unwrap();
        let row = db
            .query_one_raw(statement(
                "SELECT status, diagnostic, claimed_by, attempt_count, next_attempt_at
                 FROM inbound_work WHERE identity=?",
                vec![identity.to_string().into()],
            ))
            .await
            .unwrap()
            .expect("inbound work row");
        WorkLedger {
            status: row.try_get("", "status").unwrap(),
            diagnostic: row.try_get("", "diagnostic").unwrap(),
            claimed_by: row.try_get("", "claimed_by").unwrap(),
            attempt_count: row.try_get("", "attempt_count").unwrap(),
            next_attempt_at: row.try_get("", "next_attempt_at").unwrap(),
        }
    }

    /// 只推进时间与租约到“可再次认领”（真实退避/等待需要分钟级时间，探针不允许 sleep）。
    async fn make_due(db: &DatabaseConnection) -> Result<(), sea_orm::DbErr> {
        db.execute_unprepared(
            "UPDATE inbound_work SET status='pending', claimed_by='', claimed_at=0, next_attempt_at=0",
        )
        .await?;
        Ok(())
    }

    /// 受理身份行的不可变受理时刻（唯一首次准备计时来源）。
    async fn admitted_time(store: &BotStateStore, identity: &str) -> i64 {
        let db = store.db().await.unwrap();
        db.query_one_raw(statement(
            "SELECT admitted_at FROM inbound_identities WHERE identity=?",
            vec![identity.to_string().into()],
        ))
        .await
        .unwrap()
        .expect("admission identity row")
        .try_get("", "admitted_at")
        .unwrap()
    }

    /// 只把**受理时刻**老化到超期（时间控制；不改任何来源、证明或诊断事实）。
    async fn age_admission(db: &DatabaseConnection, admitted: i64) -> Result<(), sea_orm::DbErr> {
        db.execute_unprepared(&format!(
            "UPDATE inbound_identities SET admitted_at={}",
            admitted - INBOUND_READINESS_WAIT_BUDGET_SECONDS - 1
        ))
        .await?;
        Ok(())
    }

    /// 首次准备等待是正常等待：反复等待不消耗失败预算、不写机器前缀、不改受理时刻，
    /// 也不收束 `bound + PendingStart` 路由。
    #[tokio::test]
    async fn readiness_waiting_never_consumes_the_failure_budget()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("readiness-wait.sqlite");
        let store = bind_first(&path, &config(true, true)).await?;
        assert_eq!(
            head(&store).await.phase,
            BotAuthorizationPhase::PendingStart,
            "the ready-wait probe needs the real first-bound pending authorization"
        );
        assert!(matches!(
            store.admit_inbound(probe_inbound("m-ready")).await?,
            InboundAdmit::Fresh(_)
        ));
        let identity = inbound_identity(BOT, CHAT, "m-ready");
        let admitted = admitted_time(&store, &identity).await;
        assert!(admitted > 0, "admission must persist its immutable time");
        let db = store.db().await?.clone();
        // 失败预算只有 8 次：就绪等待 12 轮仍必须可继续，且一次失败都不计。
        for round in 0..12 {
            make_due(&db).await?;
            assert_eq!(
                store.claim_inbound_work(BOT, CHAT, "m-ready", "w1").await?,
                InboundClaim::Claimed
            );
            assert_eq!(
                store
                    .finish_inbound_work(
                        BOT,
                        CHAT,
                        "m-ready",
                        "w1",
                        WorkFinish::Deferred("bot conversation is preparing its first input"),
                    )
                    .await?,
                MarkOutcome::Applied
            );
            let ledger = work_ledger(&store, &identity).await;
            assert_eq!(
                ledger.status, "pending",
                "round {round} must stay reschedulable"
            );
            assert_eq!(
                ledger.attempt_count, 0,
                "round {round}: readiness waiting must never consume the failure budget"
            );
            assert_eq!(
                ledger.diagnostic, "bot conversation is preparing its first input",
                "round {round}: the reason is display-only, with no machine prefix"
            );
            assert!(
                ledger.next_attempt_at > 0,
                "round {round}: the wait must schedule its own next attempt"
            );
            assert_eq!(
                admitted_time(&store, &identity).await,
                admitted,
                "round {round}: the admission time is immutable"
            );
            assert_eq!(
                store.binding_for_chat(CHAT, BOT, PROJECT).await?.status,
                "bound",
                "round {round}: waiting must never collapse a bound route"
            );
        }
        // 就绪到达后同一入站正常完成。
        make_due(&db).await?;
        assert_eq!(
            store.claim_inbound_work(BOT, CHAT, "m-ready", "w1").await?,
            InboundClaim::Claimed
        );
        assert_eq!(
            store
                .finish_inbound_work(BOT, CHAT, "m-ready", "w1", WorkFinish::Completed)
                .await?,
            MarkOutcome::Applied
        );
        assert_eq!(
            store.claim_inbound_work(BOT, CHAT, "m-ready", "w1").await?,
            InboundClaim::Completed
        );
        Ok(())
    }

    /// 首次准备期限只来自受理身份不可变时间：关停中断、可重试失败与重启都不刷新它；
    /// 到期只收束该入站工作，不关授权、不动 bound 路由。
    #[tokio::test]
    async fn readiness_deadline_comes_from_admission_and_survives_restarts()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("readiness-deadline.sqlite");
        let store = bind_first(&path, &config(true, true)).await?;
        assert!(matches!(
            store.admit_inbound(probe_inbound("m-deadline")).await?,
            InboundAdmit::Fresh(_)
        ));
        let identity = inbound_identity(BOT, CHAT, "m-deadline");
        let admitted = admitted_time(&store, &identity).await;
        let db = store.db().await?.clone();
        // 两次关停中断（等价两次重启）：受理时刻与等待期限都不变。
        for round in 0..2 {
            assert_eq!(
                store
                    .claim_inbound_work(BOT, CHAT, "m-deadline", "w1")
                    .await?,
                InboundClaim::Claimed
            );
            assert_eq!(
                store
                    .finish_inbound_work(BOT, CHAT, "m-deadline", "w1", WorkFinish::Interrupted)
                    .await?,
                MarkOutcome::Applied
            );
            let ledger = work_ledger(&store, &identity).await;
            assert_eq!(
                ledger.status, "pending",
                "round {round} must stay reschedulable"
            );
            assert_eq!(
                ledger.attempt_count, 0,
                "an interruption never counts as failure"
            );
            assert_eq!(
                admitted_time(&store, &identity).await,
                admitted,
                "round {round}: an interruption must not restart the admission clock"
            );
        }
        // 可重试失败（readiness 读取错误）只计数与更新原因，不改受理时刻。
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, "m-deadline", "w1")
                .await?,
            InboundClaim::Claimed
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-deadline",
                    "w1",
                    WorkFinish::Retryable("bot input readiness is unreadable: fixture"),
                )
                .await?,
            MarkOutcome::Applied
        );
        let ledger = work_ledger(&store, &identity).await;
        assert_eq!(ledger.status, "failed");
        assert_eq!(ledger.attempt_count, 1);
        assert_eq!(
            ledger.diagnostic, "bot input readiness is unreadable: fixture",
            "the failure reason is written verbatim, without a machine prefix"
        );
        assert_eq!(
            admitted_time(&store, &identity).await,
            admitted,
            "a retryable failure must not restart the admission clock"
        );
        // 老化受理时刻到超期后进入就绪等待：必须直接收束，且只收束入站工作。
        age_admission(&db, admitted).await?;
        make_due(&db).await?;
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, "m-deadline", "w1")
                .await?,
            InboundClaim::Claimed
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-deadline",
                    "w1",
                    WorkFinish::Deferred("bot conversation is preparing its first input"),
                )
                .await?,
            MarkOutcome::Applied
        );
        let ledger = work_ledger(&store, &identity).await;
        assert_eq!(ledger.status, "needs_attention");
        assert!(
            ledger
                .diagnostic
                .contains("first input preparation did not complete"),
            "the terminal reason must name the unfinished preparation: {}",
            ledger.diagnostic
        );
        assert!(
            !ledger.diagnostic.contains("recovery budget exhausted"),
            "readiness waiting must never be reported as an exhausted failure budget: {}",
            ledger.diagnostic
        );
        assert_eq!(
            store.binding_for_chat(CHAT, BOT, PROJECT).await?.status,
            "bound",
            "only the inbound work becomes terminal; the route stays bound"
        );
        assert_eq!(
            head(&store).await.phase,
            BotAuthorizationPhase::PendingStart,
            "the preparation deadline must never close the pending authorization"
        );
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, "m-deadline", "w1")
                .await?,
            InboundClaim::NeedsAttention
        );
        Ok(())
    }

    /// 预算耗尽的收束必须 claim-fenced：失租的旧持有者既不能写入站终态，也不能把
    /// 后继仍在创建的 `creating` 路由判成终局；有效认领时两者一起生效。
    #[tokio::test]
    async fn exhausted_budget_collapse_requires_a_live_claim()
    -> Result<(), Box<dyn std::error::Error>> {
        const DIAGNOSTIC: &str = "failed to create bot Thread: fixture";
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("claim-fenced.sqlite");
        let store = BotStateStore::new(path);
        let claim = target::TargetClaim::from_operation(
            BOT,
            APP,
            PROJECT,
            CHAT,
            &creation(),
            "op1",
            target::TargetKind::Group,
        );
        assert!(matches!(
            store.claim_thread_binding(&claim).await?,
            ThreadBindingClaim::Creating { .. }
        ));
        assert!(matches!(
            store.admit_inbound(probe_inbound("m-fence")).await?,
            InboundAdmit::Fresh(_)
        ));
        let identity = inbound_identity(BOT, CHAT, "m-fence");
        let db = store.db().await?.clone();

        // Admission damage must not be mistaken for an old clock or permission to
        // finish. Exercise every finish outcome at the actual transactional boundary.
        let admitted = admitted_time(&store, &identity).await;
        db.execute_unprepared(&format!(
            "UPDATE inbound_work SET status='claimed', attempt_count=7, claimed_by='w1', claimed_at={}",
            unix_seconds()
        ))
        .await?;
        let before = work_ledger(&store, &identity).await;
        for fault in [
            "DELETE FROM inbound_identities",
            "UPDATE inbound_identities SET content_hash='other-content'",
            "UPDATE inbound_identities SET bot_id='other-bot'",
            "UPDATE inbound_identities SET chat_id='other-chat'",
            "UPDATE inbound_identities SET message_id='other-message'",
            "UPDATE inbound_identities SET admitted_at=0",
            "UPDATE inbound_identities SET admitted_at='invalid-time'",
        ] {
            db.execute_unprepared(fault).await?;
            for finish in [
                WorkFinish::Completed,
                WorkFinish::Interrupted,
                WorkFinish::NeedsAttention(DIAGNOSTIC),
                WorkFinish::CreationConflict(DIAGNOSTIC),
                WorkFinish::Retryable(DIAGNOSTIC),
                WorkFinish::Deferred("preparing"),
            ] {
                let error = store
                    .finish_inbound_work(BOT, CHAT, "m-fence", "w1", finish)
                    .await
                    .expect_err("an unproven admission must require recovery");
                assert_eq!(error.kind(), FeishuErrorKind::Unavailable, "{fault}");
                assert_eq!(work_ledger(&store, &identity).await, before, "{fault}");
                let route = store.binding_for_chat(CHAT, BOT, PROJECT).await?;
                assert_eq!(route.status, "creating", "{fault}");
                assert_eq!(route.revision, 1, "{fault}");
                assert_eq!(route.creation_id, creation(), "{fault}");
            }
            // Only undo this test's injected damage, using the original admission.
            db.execute_unprepared("DELETE FROM inbound_identities")
                .await?;
            db.execute_raw(statement(
                "INSERT INTO inbound_identities(identity,bot_id,message_id,chat_id,content_hash,admitted_at) VALUES(?,?,?,?,?,?)",
                vec![
                    identity.clone().into(), BOT.into(), "m-fence".into(), CHAT.into(),
                    "hash-m-fence".into(), admitted.into(),
                ],
            )).await?;
        }

        // 同一 run 的 submit 退避保留 claim；附件无需交回恢复扫描再下载。
        db.execute_unprepared("UPDATE inbound_work SET attempt_count=0")
            .await?;
        for expected_count in 1..=7 {
            let retry = store
                .retain_inbound_retry(&probe_inbound("m-fence"), "w1", DIAGNOSTIC)
                .await?;
            let InboundRetryWait::Until { retry_at } = retry else {
                panic!("a bounded pre-acceptance retry must retain its owner: {retry:?}");
            };
            let work = work_ledger(&store, &identity).await;
            assert_eq!(
                (work.status.as_str(), work.claimed_by.as_str()),
                ("claimed", "w1")
            );
            assert_eq!(work.attempt_count, expected_count);
            assert_eq!(work.next_attempt_at, retry_at);
            assert_eq!(admitted_time(&store, &identity).await, admitted);
        }
        let before_exhaustion = work_ledger(&store, &identity).await;
        assert_eq!(
            store
                .retain_inbound_retry(&probe_inbound("m-fence"), "w1", DIAGNOSTIC)
                .await?,
            InboundRetryWait::BudgetExhausted
        );
        assert_eq!(
            work_ledger(&store, &identity).await,
            before_exhaustion,
            "the finisher alone owns the eighth failure and terminal transaction"
        );
        assert_eq!(
            store.binding_for_chat(CHAT, BOT, PROJECT).await?.status,
            "creating"
        );

        // A. 认领已被另一 worker 接管：旧持有者不得收束任何东西。
        db.execute_unprepared(&format!(
            "UPDATE inbound_work SET status='claimed', attempt_count=7, claimed_by='w2', claimed_at={}",
            unix_seconds()
        ))
        .await?;
        assert_eq!(
            store
                .retain_inbound_retry(&probe_inbound("m-fence"), "w1", DIAGNOSTIC)
                .await?,
            InboundRetryWait::LostClaim
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-fence",
                    "w1",
                    WorkFinish::Retryable(DIAGNOSTIC)
                )
                .await?,
            MarkOutcome::LostClaim
        );
        assert_eq!(
            store.binding_for_chat(CHAT, BOT, PROJECT).await?.status,
            "creating",
            "a lost claim must never collapse the route a successor is still creating"
        );
        let ledger = work_ledger(&store, &identity).await;
        assert_eq!(
            (ledger.status.as_str(), ledger.claimed_by.as_str()),
            ("claimed", "w2"),
            "a lost claim must not rewrite the inbound terminal state either"
        );

        // B. 同一 worker 但租约已过期：同样不得收束。
        db.execute_unprepared(&format!(
            "UPDATE inbound_work SET status='claimed', claimed_by='w1', claimed_at={}",
            unix_seconds() - INBOUND_CLAIM_TTL_SECONDS - 1
        ))
        .await?;
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-fence",
                    "w1",
                    WorkFinish::Retryable(DIAGNOSTIC)
                )
                .await?,
            MarkOutcome::LostClaim
        );
        assert_eq!(
            store.binding_for_chat(CHAT, BOT, PROJECT).await?.status,
            "creating",
            "an expired lease must not collapse the creating route"
        );

        // C. 有效认领：入站终态与路由收束在同一次调用里一起生效。
        db.execute_unprepared(&format!(
            "UPDATE inbound_work SET status='claimed', claimed_by='w1', claimed_at={}",
            unix_seconds()
        ))
        .await?;
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "m-fence",
                    "w1",
                    WorkFinish::Retryable(DIAGNOSTIC)
                )
                .await?,
            MarkOutcome::Applied
        );
        let route = store.binding_for_chat(CHAT, BOT, PROJECT).await?;
        assert_eq!(route.status, "needs_attention");
        assert!(
            route
                .diagnostic
                .as_deref()
                .is_some_and(|diagnostic| diagnostic.contains(DIAGNOSTIC)),
            "the collapsed route must carry the real reason"
        );
        let ledger = work_ledger(&store, &identity).await;
        assert_eq!(ledger.status, "needs_attention");
        assert!(
            ledger.diagnostic.contains("recovery budget exhausted"),
            "the inbound must record the exhausted budget: {}",
            ledger.diagnostic
        );
        Ok(())
    }

    /// 三个探针共用的真实入站事实（与 `bots_protocol_observe` 的直聊入站同形状）。
    fn probe_inbound(message_id: &str) -> FrozenInbound {
        FrozenInbound {
            bot_id: BOT.to_string(),
            message_id: message_id.to_string(),
            chat_id: CHAT.to_string(),
            content_hash: format!("hash-{message_id}"),
            text: "hi".to_string(),
            attachments: Vec::new(),
            open_id: String::new(),
            chat_kind: "group".to_string(),
            app_id: APP.to_string(),
            project_id: PROJECT.to_string(),
            creation_id: creation(),
            binding_revision: 1,
            watch_input: String::new(),
        }
    }
    #[tokio::test]
    async fn ledger_adopts_current_file_and_refuses_future_writes() -> anyhow::Result<()> {
        for fault in ["format", "migration", "missing_table"] {
            let directory = tempfile::tempdir()?;
            let path = directory.path().join("ledger.sqlite");
            let original = open_bot_state(&path).await?;
            original
                .execute_unprepared("DROP TABLE seaql_migrations")
                .await?;
            original.close().await?;
            let adopted = open_bot_state(&path).await?;
            assert!(
                adopted
                    .query_one_raw(statement("SELECT version FROM seaql_migrations", vec![]))
                    .await?
                    .is_some()
            );
            if fault == "format" {
                adopted
                    .execute_unprepared("UPDATE bot_meta SET schema_version=999")
                    .await?;
            } else if fault == "missing_table" {
                adopted
                    .execute_unprepared("DROP TABLE seaql_migrations; DROP TABLE inbound_work")
                    .await?;
            } else {
                adopted.execute_unprepared("INSERT INTO seaql_migrations(version,applied_at) VALUES('m99999999_future',1)").await?;
            }
            adopted.close().await?;
            let before = tokio::fs::read(&path).await?;
            assert!(open_bot_state(&path).await.is_err());
            assert_eq!(tokio::fs::read(&path).await?, before);
        }
        Ok(())
    }
}
