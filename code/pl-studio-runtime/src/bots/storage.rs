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

const BOT_STATE_SCHEMA_VERSION: i64 = 7;
const PAIRING_LIMIT: i64 = 32;
const PAIRING_TTL_SECONDS: i64 = 7 * 24 * 60 * 60;
const INBOUND_CLAIM_TTL_SECONDS: i64 = 60;
const INBOUND_RETRY_BASE_SECONDS: i64 = 5;
const INBOUND_RETRY_MAX_SECONDS: i64 = 300;
const INBOUND_RETRY_BUDGET: i64 = 8;
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

/// 入站工作收束语义；由账本在同一认领条件下原子落盘。
#[derive(Debug, Clone)]
pub(crate) enum WorkFinish<'a> {
    Completed,
    /// Runtime 停止观察：释放为 pending 且立即可恢复，不计失败预算。
    Interrupted,
    NeedsAttention(&'a str),
    /// 真实 retryable 失败：计数退避；预算耗尽自动转 needs_attention。
    Retryable(&'a str),
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
        tx.execute_raw(statement(
            "INSERT INTO inbound_identities(identity, bot_id, message_id, chat_id, content_hash, admitted_at)
             VALUES(?,?,?,?,?,?)",
            vec![
                identity.clone().into(),
                inbound.bot_id.clone().into(),
                inbound.message_id.clone().into(),
                inbound.chat_id.clone().into(),
                inbound.content_hash.clone().into(),
                unix_seconds().into(),
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
                unix_seconds().into(),
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

    /// 持久化 canonical 恢复进度（当前 watch 的输入身份）；失租时不得覆盖后继进度。
    pub(crate) async fn save_inbound_watch_input(
        &self,
        bot_id: &str,
        chat_id: &str,
        message_id: &str,
        worker_id: &str,
        watch_input: &str,
    ) -> Result<MarkOutcome, FeishuError> {
        let identity = inbound_identity(bot_id, chat_id, message_id);
        let db = self.db().await?;
        let now = unix_seconds();
        let lease_cutoff = now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS);
        let updated = db
            .execute_raw(statement(
                "UPDATE inbound_work
                 SET watch_input=?, updated_at=?
                 WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                   AND claimed_by=? AND status='claimed' AND claimed_at>?",
                vec![
                    watch_input.to_string().into(),
                    now.into(),
                    identity.into(),
                    bot_id.to_string().into(),
                    chat_id.to_string().into(),
                    message_id.to_string().into(),
                    worker_id.to_string().into(),
                    lease_cutoff.into(),
                ],
            ))
            .await
            .map_err(storage)?;
        if updated.rows_affected() == 1 {
            Ok(MarkOutcome::Applied)
        } else {
            Ok(MarkOutcome::LostClaim)
        }
    }

    /// 在同一认领条件下收束入站工作状态；失败按分类退避，预算耗尽转需处理。
    ///
    /// 所有分支（含 Retryable 的事务内 SELECT/UPDATE）都核对同一有效 lease：
    /// `claimed_by` 为本持有者、状态仍为 claimed 且租约未过期。过期的旧持有者
    /// 即使尚未被接管也不得收束状态；0 行统一返回 `LostClaim`，不得吞成完成。
    pub(crate) async fn finish_inbound_work(
        &self,
        bot_id: &str,
        chat_id: &str,
        message_id: &str,
        worker_id: &str,
        finish: WorkFinish<'_>,
    ) -> Result<MarkOutcome, FeishuError> {
        let identity = inbound_identity(bot_id, chat_id, message_id);
        let db = self.db().await?;
        let now = unix_seconds();
        let lease_cutoff = now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS);
        match finish {
            WorkFinish::Completed => {
                let updated = db
                    .execute_raw(statement(
                        "UPDATE inbound_work
                         SET status='completed', diagnostic='', claimed_by='', claimed_at=0,
                             attempt_count=0, next_attempt_at=0, updated_at=?
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            now.into(),
                            identity.into(),
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?;
                Ok(mark_outcome(updated.rows_affected()))
            }
            WorkFinish::Interrupted => {
                let updated = db
                    .execute_raw(statement(
                        "UPDATE inbound_work
                         SET status='pending',
                             diagnostic='runtime stopped before a local terminal fact',
                             claimed_by='', claimed_at=0, next_attempt_at=0, updated_at=?
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            now.into(),
                            identity.into(),
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?;
                Ok(mark_outcome(updated.rows_affected()))
            }
            WorkFinish::NeedsAttention(diagnostic) => {
                let updated = db
                    .execute_raw(statement(
                        "UPDATE inbound_work
                         SET status='needs_attention', diagnostic=?, claimed_by='', claimed_at=0, updated_at=?
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            diagnostic.to_string().into(),
                            now.into(),
                            identity.into(),
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?;
                Ok(mark_outcome(updated.rows_affected()))
            }
            WorkFinish::Retryable(diagnostic) => {
                let tx = db.begin().await.map_err(storage)?;
                let row = tx
                    .query_one_raw(statement(
                        "SELECT attempt_count FROM inbound_work
                         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
                           AND claimed_by=? AND status='claimed' AND claimed_at>?",
                        vec![
                            identity.clone().into(),
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?;
                let attempt_count = match row {
                    Some(row) => stored_i64(&row, "attempt_count")?,
                    None => {
                        tx.commit().await.map_err(storage)?;
                        return Ok(MarkOutcome::LostClaim);
                    }
                };
                let next_count = attempt_count.saturating_add(1);
                let updated = if next_count >= INBOUND_RETRY_BUDGET {
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
                            identity.into(),
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
                            identity.into(),
                            bot_id.to_string().into(),
                            chat_id.to_string().into(),
                            message_id.to_string().into(),
                            worker_id.to_string().into(),
                            lease_cutoff.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?
                };
                let applied = updated.rows_affected() == 1;
                tx.commit().await.map_err(storage)?;
                if applied {
                    Ok(MarkOutcome::Applied)
                } else {
                    Ok(MarkOutcome::LostClaim)
                }
            }
        }
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

    pub async fn claim_thread_binding(
        &self,
        chat_id: &str,
        creation_id: &str,
        project_id: &str,
    ) -> Result<ThreadBindingClaim, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let row = match tx
            .query_one_raw(statement(
                "SELECT chat_id, thread_id, status, creation_id, project_id, revision, generation, diagnostic FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?
        {
            Some(row) => row,
            None => {
            // 真正 NoRow：首次受理在此写入新行，随后才提交。
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)",
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
        // 水位同样严格解码：坏行不能继续被当成可用绑定。
        let _revision = strict_watermark(&row, "revision")?;
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
            // creating 的创建身份已由上面的 needs_proof 判定非空。
            "creating" => Ok(ThreadBindingClaim::Creating {
                creation_id: stored_creation,
            }),
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

    pub async fn bind_thread(
        &self,
        chat_id: &str,
        thread_id: &str,
        creation_id: &str,
        project_id: &str,
    ) -> Result<String, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT thread_id, status, creation_id, project_id, revision, generation FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let (revision, generation) = if let Some(row) = existing {
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
            (revision, generation)
        } else {
            (1u64, 1u64)
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
        tx.commit().await.map_err(storage)?;
        Ok(thread_id.to_string())
    }

    pub async fn mark_binding_attention(
        &self,
        chat_id: &str,
        diagnostic: &str,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "UPDATE thread_bindings SET status='needs_attention', diagnostic=?, updated_at=? WHERE chat_id=?",
            vec![
                diagnostic.to_string().into(),
                unix_seconds().into(),
                chat_id.to_string().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
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
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               thread_id='',
               status='creating',
               creation_id=excluded.creation_id,
               project_id=excluded.project_id,
               revision=excluded.revision,
               generation=excluded.generation,
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
            ],
        ))
        .await
        .map_err(storage)?;
        if !insert_binding_operation(&tx, operation).await? {
            // 同一 operationId 已存在不同记录：保留原记录，不覆盖他人操作。
            return Err(binding_needs_recovery());
        }
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
                "SELECT status, thread_id, creation_id, project_id, revision FROM thread_bindings WHERE chat_id=?",
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
                "SELECT operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id
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
            "INSERT INTO binding_operations(operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id, updated_at)
             VALUES(?,?,?,?,?,?,?,?)
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
            // 先提交只读事务再解码：既有结果的长事实不与本次 initial 同时跨提交等待。
            tx.commit().await.map_err(storage)?;
            let existing = send_record_from_row(row)?;
            return conflict_or_existing(record, existing).map(Some);
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

    /// Resolve the exact canonical input first, including completed work for a legitimate same-call
    /// replay. Only a not-yet-recorded continuation needs the bounded active-work candidate set.
    pub(crate) async fn inbound_sources(
        &self,
        thread_id: &str,
        input_id: &str,
    ) -> Result<Vec<SendSource>, FeishuError> {
        let db = self.db().await?;
        let mut rows = db.query_all_raw(statement(
            "SELECT bot_id, chat_id, message_id, open_id, chat_kind, app_id, project_id, creation_id, binding_revision
             FROM inbound_work WHERE creation_id=?
               AND (('bot:' || bot_id || ':' || chat_id || ':' || message_id)=? OR watch_input=?) LIMIT 65",
            vec![thread_id.to_owned().into(), input_id.to_owned().into(), input_id.to_owned().into()],
        )).await.map_err(storage)?;
        if rows.is_empty() {
            rows = db.query_all_raw(statement(
            "SELECT bot_id, chat_id, message_id, open_id, chat_kind, app_id, project_id, creation_id, binding_revision
             FROM inbound_work WHERE creation_id=? AND status IN ('pending','claimed','failed') LIMIT 65",
            vec![thread_id.to_owned().into()],
            )).await.map_err(storage)?;
        }
        if rows.len() > 64 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "source proof exceeds the inbound work bound; local recovery required",
                false,
                None,
            ));
        }
        rows.into_iter()
            .map(|row| {
                let bot_id = strict_text(&row, "bot_id")?;
                let chat_id = strict_text(&row, "chat_id")?;
                let message_id = strict_text(&row, "message_id")?;
                let original_input_id = format!("bot:{bot_id}:{chat_id}:{message_id}");
                Ok(SendSource {
                    bot_id,
                    chat_id,
                    message_id,
                    app_id: strict_text(&row, "app_id")?,
                    project_id: strict_text(&row, "project_id")?,
                    open_id: strict_text(&row, "open_id")?,
                    chat_kind: strict_text(&row, "chat_kind")?,
                    creation_id: strict_text(&row, "creation_id")?,
                    binding_revision: strict_watermark(&row, "binding_revision")?,
                    thread_id: thread_id.to_owned(),
                    input_id: original_input_id.clone(),
                    original_input_id,
                })
            })
            .collect()
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

fn mark_outcome(rows_affected: u64) -> MarkOutcome {
    if rows_affected == 1 {
        MarkOutcome::Applied
    } else {
        MarkOutcome::LostClaim
    }
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
        format!("bot state failed: {error}"),
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
            "INSERT OR IGNORE INTO binding_operations(operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id, updated_at)
             VALUES(?,?,?,?,?,?,?,?)",
            vec![
                operation.operation_id.clone().into(),
                operation.bot_id.clone().into(),
                operation.chat_id.clone().into(),
                operation.content_hash.clone().into(),
                expected_revision.into(),
                operation.creation_id.clone().into(),
                operation.thread_id.clone().unwrap_or_default().into(),
                unix_seconds().into(),
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
    initialize(&db, origin).await.map_err(state_failure)?;
    Ok(db)
}

async fn initialize(db: &DatabaseConnection, origin: DatabaseOrigin) -> anyhow::Result<()> {
    let tx = db.begin().await?;
    // A previously committed bot database must not silently rebuild an empty reference ledger.
    // All established schema versions own both tables. Even an entirely empty existing schema
    // is not evidence that we created this file; inspect before any CREATE/MIGRATE statement.
    let version = if matches!(origin, DatabaseOrigin::Existing) {
        let tables = tx
        .query_one_raw(statement(
                "SELECT COUNT(*) AS required FROM sqlite_master WHERE type='table' AND name IN ('bot_meta','send_operations')",
                vec![],
            ))
            .await?
            .ok_or_else(|| crate::studio::startup::data_error(anyhow::anyhow!("bot schema identity is unreadable")))?;
        if tables.try_get::<i64>("", "required")? != 2 {
            return Err(crate::studio::startup::data_error(anyhow::anyhow!(
                "persisted bot database lacks its established metadata or send ledger; local recovery required"
            )));
        }
        let metadata_columns = table_columns(&tx, "bot_meta").await?;
        if !["id", "schema_version"]
            .iter()
            .all(|column| metadata_columns.contains(*column))
        {
            return Err(crate::studio::startup::data_error(anyhow::anyhow!(
                "persisted bot metadata schema is incomplete; local recovery required"
            )));
        }
        let metadata = tx
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .ok_or_else(|| {
                crate::studio::startup::data_error(anyhow::anyhow!(
                    "persisted bot database lacks its schema version; local recovery required"
                ))
            })?;
        let version = metadata
            .try_get::<i64>("", "schema_version")
            .map_err(crate::studio::startup::data_error)?;
        if !(1..=BOT_STATE_SCHEMA_VERSION).contains(&version) {
            return Err(crate::studio::startup::data_error(anyhow::anyhow!(
                "persisted bot schema version is invalid or unsupported; local recovery required"
            )));
        }
        if version >= 6 {
            validate_file_ledger_schema(&tx).await?;
            if version < 7 {
                // v6 already owns file identities and references. Only stage semantics change;
                // never repair missing file facts with defaults or re-run the text migration.
                migrate_send_stages(&tx).await?;
                tx.execute_raw(statement(
                    "UPDATE bot_meta SET schema_version=? WHERE id=1",
                    vec![BOT_STATE_SCHEMA_VERSION.into()],
                ))
                .await?;
            }
            tx.commit().await?;
            return Ok(());
        }
        version
    } else {
        0 // Only this call's exclusive file creation authorizes a genuinely new schema.
    };
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS bot_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL
        )",
    )
    .await?;
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS inbound_identities (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            message_id TEXT NOT NULL,
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            admitted_at INTEGER NOT NULL
        )",
    )
    .await?;
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS inbound_work (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL DEFAULT '',
            message_id TEXT NOT NULL DEFAULT '',
            content_hash TEXT NOT NULL DEFAULT '',
            text TEXT NOT NULL DEFAULT '',
            open_id TEXT NOT NULL DEFAULT '',
            chat_kind TEXT NOT NULL DEFAULT '',
            generation INTEGER NOT NULL DEFAULT 0,
            app_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '',
            creation_id TEXT NOT NULL DEFAULT '',
            binding_revision INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            diagnostic TEXT NOT NULL,
            claimed_by TEXT NOT NULL DEFAULT '',
            claimed_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
        )",
    )
    .await?;
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS thread_bindings (
            chat_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'bound',
            creation_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '',
            revision INTEGER NOT NULL DEFAULT 0,
            generation INTEGER NOT NULL DEFAULT 0,
            diagnostic TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0
        )",
    )
    .await?;
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS observed_directs (
            chat_id TEXT PRIMARY KEY,
            open_id TEXT NOT NULL,
            name TEXT NOT NULL,
            last_observed_at INTEGER NOT NULL
        )",
    )
    .await?;
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS pairing_requests (
            request_id TEXT PRIMARY KEY,
            open_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            created_at INTEGER NOT NULL
        )",
    )
    .await?;
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS send_operations (
            operation_id TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            status TEXT NOT NULL,
            platform_message_ids TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )",
    )
    .await?;
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS binding_operations (
            operation_id TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL,
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            expected_revision INTEGER NOT NULL,
            creation_id TEXT NOT NULL,
            thread_id TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL
        )",
    )
    .await?;
    migrate(&tx, version).await?;
    tx.commit().await?;
    Ok(())
}

/// v6 and v7 share these complete file-aware tables/columns; v7 changes JSON stages only.
/// Earlier text schemas deliberately keep their existing transactional migration boundary.
async fn validate_file_ledger_schema<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let required: &[(&str, &[&str])] = &[
        ("bot_meta", &["id", "schema_version"]),
        (
            "inbound_identities",
            &[
                "identity",
                "bot_id",
                "message_id",
                "chat_id",
                "content_hash",
                "admitted_at",
            ],
        ),
        (
            "inbound_work",
            &[
                "identity",
                "bot_id",
                "chat_id",
                "message_id",
                "content_hash",
                "text",
                "open_id",
                "chat_kind",
                "generation",
                "app_id",
                "project_id",
                "creation_id",
                "binding_revision",
                "status",
                "diagnostic",
                "claimed_by",
                "claimed_at",
                "updated_at",
                "attachments",
                "watch_input",
                "attempt_count",
                "next_attempt_at",
            ],
        ),
        (
            "thread_bindings",
            &[
                "chat_id",
                "thread_id",
                "status",
                "creation_id",
                "project_id",
                "revision",
                "generation",
                "diagnostic",
                "created_at",
                "updated_at",
            ],
        ),
        (
            "observed_directs",
            &["chat_id", "open_id", "name", "last_observed_at"],
        ),
        (
            "pairing_requests",
            &["request_id", "open_id", "display_name", "created_at"],
        ),
        (
            "send_operations",
            &[
                "operation_id",
                "bot_id",
                "chat_id",
                "content_hash",
                "status",
                "platform_message_ids",
                "updated_at",
                "segment_facts",
                "send_identity",
                "send_source",
            ],
        ),
        (
            "binding_operations",
            &[
                "operation_id",
                "bot_id",
                "chat_id",
                "content_hash",
                "expected_revision",
                "creation_id",
                "thread_id",
                "updated_at",
            ],
        ),
    ];
    for (table, required_columns) in required {
        let present = db
            .query_one_raw(statement(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                vec![(*table).into()],
            ))
            .await?
            .is_some();
        let columns = table_columns(db, table).await?;
        if !present
            || required_columns
                .iter()
                .any(|column| !columns.contains(*column))
        {
            return Err(crate::studio::startup::data_error(anyhow::anyhow!(
                "persisted file-aware bot schema is incomplete in {table}; local recovery required"
            )));
        }
    }
    Ok(())
}

async fn migrate<C: ConnectionTrait>(db: &C, version: i64) -> anyhow::Result<()> {
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
        vec![BOT_STATE_SCHEMA_VERSION.into()],
    ))
    .await?;
    Ok(())
}

/// v1..v5 stored snake_case segment fields and only text sends. Preserve their exact hashes,
/// outcome/provenance and UUIDs; only the JSON schema is rewritten inside this transaction.
async fn migrate_text_send_facts<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    #[derive(Deserialize)]
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

        for version in [6, 7] {
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
        db.execute_unprepared("UPDATE bot_meta SET schema_version=6 WHERE id=1")
            .await?;
        drop(store);
        let reopened = BotStateStore::new(path);
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
            // A later text-only ledger stored real per-segment snake_case JSON. Both the oldest
            // no-facts row and this known partial result must survive the v6 typed-send migration.
            legacy.execute_unprepared(
            "ALTER TABLE send_operations ADD COLUMN segment_facts TEXT NOT NULL DEFAULT '';
             INSERT INTO send_operations(operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, updated_at, segment_facts)
             VALUES('op-with-facts', 'legacy', 'chat', 'old-text-hash', 'partial', 'pm-known', 1,
               '[{\"index\":0,\"uuid\":\"old-uuid\",\"status\":\"succeeded\",\"platform_message_id\":\"pm-known\",\"diagnostic\":null},{\"index\":1,\"uuid\":\"old-uuid-2\",\"status\":\"rejected\",\"platform_message_id\":null,\"diagnostic\":\"known rejection\"}]');"
        ).await?;
            if version == 5 {
                // These are the remaining columns in HEAD's schema5 initialize+migrate result.
                // Do not invent earlier per-column introduction versions or reject pre6 schemas.
                legacy.execute_unprepared(
                "ALTER TABLE inbound_work ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]';
                 ALTER TABLE inbound_work ADD COLUMN watch_input TEXT NOT NULL DEFAULT '';
                 ALTER TABLE inbound_work ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0;
                 ALTER TABLE inbound_work ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0;
                 UPDATE bot_meta SET schema_version=5 WHERE id=1;",
            ).await?;
            }
            drop(legacy);

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
}
