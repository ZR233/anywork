use super::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
use crate::studio::unix_seconds;
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, QueryResult, Statement,
    TransactionTrait, Value,
};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::Duration;

pub(super) mod card;
mod schema;

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
    writer: tokio::sync::OnceCell<DatabaseConnection>,
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
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendSegmentFact {
    pub index: u32,
    pub uuid: String,
    pub status: SendRecordStatus,
    pub platform_message_id: Option<String>,
    pub diagnostic: Option<String>,
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
    pub workspace_id: String,
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
    pub workspace_id: String,
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
            writer: tokio::sync::OnceCell::new(),
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
                    "SELECT identity, bot_id, chat_id, message_id, content_hash, status, text, open_id, chat_kind, app_id, workspace_id, creation_id, binding_revision, attachments, watch_input FROM inbound_work WHERE identity=?",
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
                workspace_id: strict_text(&work, "workspace_id")?,
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
            "INSERT INTO inbound_work(identity, bot_id, chat_id, message_id, content_hash, text, open_id, chat_kind, app_id, workspace_id, creation_id, binding_revision, attachments, status, diagnostic, claimed_by, claimed_at, updated_at)
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
                inbound.workspace_id.clone().into(),
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
                "SELECT identity, bot_id, chat_id, message_id, content_hash, text, open_id, chat_kind, app_id, workspace_id, creation_id, binding_revision, attachments, watch_input
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
                    workspace_id: strict_text(&row, "workspace_id")?,
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
        workspace_id: &str,
    ) -> Result<ThreadBindingClaim, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let row = match tx
            .query_one_raw(statement(
                "SELECT chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?
        {
            Some(row) => row,
            None => {
            // 真正 NoRow：首次受理在此写入新行，随后才提交。
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)",
            vec![
                chat_id.to_string().into(),
                "".to_string().into(),
                "creating".to_string().into(),
                creation_id.to_string().into(),
                workspace_id.to_string().into(),
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
        let stored_project = strict_text(&row, "workspace_id")?;
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
                || stored_project != workspace_id)
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
        workspace_id: &str,
    ) -> Result<String, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT thread_id, status, creation_id, workspace_id, revision, generation FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let (revision, generation) = if let Some(row) = existing {
            // 路由、创建身份与项目归属只接受持久值：解码失败不得默认成 bound 或空创建。
            let status = strict_text(&row, "status")?;
            let bound = strict_text(&row, "thread_id")?;
            let stored_creation = strict_text(&row, "creation_id")?;
            let stored_project = strict_text(&row, "workspace_id")?;
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
            if stored_project.is_empty() || stored_project != workspace_id {
                // 项目归属未知或不一致：不覆盖成当前项目，也不把 Thread 迁到另一项目。
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            (revision, generation)
        } else {
            (1u64, 1u64)
        };
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               thread_id=excluded.thread_id,
               status='bound',
               creation_id=excluded.creation_id,
               workspace_id=excluded.workspace_id,
               diagnostic='',
               updated_at=excluded.updated_at",
            vec![
                chat_id.to_string().into(),
                thread_id.to_string().into(),
                "bound".to_string().into(),
                creation_id.to_string().into(),
                workspace_id.to_string().into(),
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
        workspace_id: &str,
    ) -> Result<BindingProjection, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT chat_id, thread_id, status, revision, generation, workspace_id, creation_id, diagnostic FROM thread_bindings WHERE chat_id=?",
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
                let stored_project: String = strict_text(&row, "workspace_id")?;
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
                            || stored_project != workspace_id
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
                    workspace_id: stored_project,
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
                workspace_id: workspace_id.to_string(),
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
        workspace_id: &str,
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
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               thread_id='',
               status='creating',
               creation_id=excluded.creation_id,
               workspace_id=excluded.workspace_id,
               revision=excluded.revision,
               generation=excluded.generation,
               diagnostic='',
               updated_at=excluded.updated_at",
            vec![
                chat_id.to_string().into(),
                "".to_string().into(),
                "creating".to_string().into(),
                operation.creation_id.clone().into(),
                workspace_id.to_string().into(),
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
        workspace_id: &str,
        operation: &BindingOperation,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let row = tx
            .query_one_raw(statement(
                "SELECT status, thread_id, creation_id, workspace_id, revision FROM thread_bindings WHERE chat_id=?",
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
        let stored_project = strict_text(&row, "workspace_id")?;
        let revision = strict_watermark(&row, "revision")?;
        let claimed = status == "creating"
            && thread_id.is_empty()
            && creation_id == operation.creation_id
            && stored_project == workspace_id
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
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts
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
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts
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
                "INSERT OR IGNORE INTO send_operations(operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, updated_at)
                 VALUES(?,?,?,?,?,?,?,?)",
                vec![
                    record.operation_id.clone().into(),
                    record.bot_id.clone().into(),
                    record.chat_id.clone().into(),
                    record.content_hash.clone().into(),
                    record.status.as_str().to_string().into(),
                    record.platform_message_ids.join(",").into(),
                    encode_segment_facts(&record.segments)?.into(),
                    unix_seconds().into(),
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
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts
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
            "INSERT INTO send_operations(operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, updated_at)
             VALUES(?,?,?,?,?,?,?,?)
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
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
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
            format!("stored send segment facts are unreadable: {error}"),
            false,
            None,
        )
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
    Ok(existing)
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
    schema::inspect_existing(path).await.map_err(storage)?;
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await.map_err(storage)?;
    }
    let mut options = sqlite_file_options(path, SqliteFileMode::Create, |options| {
        options
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Full)
            .busy_timeout(Duration::from_secs(5))
            .foreign_keys(true)
    })
    .await
    .map_err(storage)?;
    options
        .max_connections(1)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    let db = Database::connect(options).await.map_err(storage)?;
    if let Err(error) = schema::initialize(&db).await {
        if let Err(cleanup) = db.close().await {
            return Err(storage(
                error.context(format!("bot ledger cleanup failed: {cleanup}")),
            ));
        }
        return Err(storage(error));
    }
    Ok(db)
}

#[cfg(test)]
mod tests {
    use super::*;

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

    /// 真实 v3 输入迁移到当前 schema，保全映射、收发账本及附件工作。
    /// 并覆盖过期旧 claim 拒绝与后继新 worker 竞争接管的 lease 语义。
    #[tokio::test]
    async fn legacy_ledger_upgrade_preserves_work_and_reopens_media_without_duplicate_admission()
    -> Result<(), Box<dyn std::error::Error>> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("bot-state.sqlite");
        let legacy = v3_database(&path).await;
        legacy.execute_unprepared("CREATE TRIGGER reject_ledger_migration BEFORE UPDATE ON bot_meta BEGIN SELECT RAISE(ABORT,'injected ledger migration failure'); END").await?;
        legacy.close().await?;

        let failed = BotStateStore::new(path.clone());
        let failure = failed
            .list_due_inbound("legacy")
            .await
            .expect_err("ledger migration must fail");
        assert!(
            failure
                .to_string()
                .contains("m20261026_000001_bot_ledger_schema")
        );
        assert!(
            failure
                .to_string()
                .contains("injected ledger migration failure")
        );
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
        probe
            .execute_unprepared(
                "CREATE TRIGGER reject_workspace_migration BEFORE UPDATE ON bot_meta
             WHEN NEW.schema_version=7
             BEGIN SELECT RAISE(ABORT,'injected ownership migration failure'); END",
            )
            .await?;
        probe.close().await?;

        let failed_ownership = BotStateStore::new(path.clone());
        assert!(
            failed_ownership
                .list_due_inbound("legacy")
                .await
                .expect_err("ownership migration must roll back")
                .to_string()
                .contains("injected ownership migration failure")
        );
        let probe = Database::connect(
            sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
        )
        .await?;
        let manager = sea_orm_migration::SchemaManager::new(&probe);
        for table in ["inbound_work", "thread_bindings"] {
            assert!(manager.has_column(table, "project_id").await?);
            assert!(!manager.has_column(table, "workspace_id").await?);
        }
        let version: i64 = probe
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "schema_version")?;
        assert_eq!(version, 6, "only the prior official migration committed");
        probe
            .execute_unprepared("DROP TRIGGER reject_workspace_migration")
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
        for table in ["inbound_work", "thread_bindings"] {
            let row = db
                .query_one_raw(statement(
                    &format!("SELECT workspace_id FROM {table} LIMIT 1"),
                    vec![],
                ))
                .await?
                .unwrap();
            assert_eq!(row.try_get::<String>("", "workspace_id")?, "project");
        }

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
        // The schema-6 card table coexists with every legacy fact. Its durable
        // pre-HTTP intent survives a reopen, while stale workers and stale card
        // versions cannot overwrite progress or turn an unknown into a retry.
        let card_binding = card::CardBinding {
            bot_id: "legacy".into(),
            chat_id: "chat".into(),
            message_id: "m1".into(),
            thread_id: "thread-1".into(),
            original_input: "bot:legacy:chat:m1".into(),
        };
        let mut card_state =
            card::CardStream::new(card_binding.clone(), "bot:legacy:chat:m1", "turn-1");
        card_state.reserve(card::CardAction::Create {
            text: "verified preview".into(),
        })?;
        assert_eq!(
            store.save_card(&mut card_state, "crashed-worker").await?,
            MarkOutcome::LostClaim
        );
        assert_eq!(
            store.save_card(&mut card_state, "w1").await?,
            MarkOutcome::Applied
        );
        let mut stale_card = card_state.clone();
        assert_eq!(
            store.save_card(&mut card_state, "w1").await?,
            MarkOutcome::Applied
        );
        assert_eq!(
            store.save_card(&mut stale_card, "w1").await?,
            MarkOutcome::LostClaim
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
        assert_eq!(
            store.save_card(&mut card_state, "w1").await?,
            MarkOutcome::LostClaim
        );

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
        drop(store);
        let reopened = BotStateStore::new(path);
        let restored_card = reopened.load_card(&card_binding).await?.unwrap();
        assert!(restored_card.uncertain());
        assert_eq!(restored_card.version, card_state.version);
        assert!(restored_card.card_id.is_none());
        assert!(restored_card.platform_message_id.is_none());
        let operation = restored_card.last_operation.unwrap();
        assert!(matches!(
            operation.status,
            card::CardOperationStatus::Intent
        ));
        assert_eq!(operation.action.text(), Some("verified preview"));
        assert_eq!(
            operation.uuid,
            card_state.last_operation.as_ref().unwrap().uuid
        );
        let restored = reopened.list_due_inbound("legacy").await?;
        assert_eq!(restored, vec![media.clone()]);
        assert_eq!(
            reopened.admit_inbound(media.clone()).await?,
            InboundAdmit::DuplicateResume(media)
        );
        assert_eq!(reopened.list_due_inbound("legacy").await?.len(), 1);
        Ok(())
    }

    /// New card JSON states survive the real v3 -> current ledger migration and
    /// reopen. Fixtures start from a known preview; this proves storage/lease
    /// transitions, not platform HTTP acceptance (covered by the observer).
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
        // Even a previously confirmed content hash cannot turn a remaining
        // preview into the final answer when canonical Final becomes empty.
        no_final.final_content_hash = Some(no_final.confirmed_content_hash.clone());
        no_final.reserve(card::CardAction::Settings {
            streaming: false,
            lifecycle: card::CardLifecycle::NoFinalReply,
            recovery: false,
        })?;
        assert!(no_final.final_content_hash.is_none());
        assert_eq!(
            store.save_card(&mut no_final, "w1").await?,
            MarkOutcome::Applied
        );
        let mut stale_intent = no_final.clone();
        assert!(stale_intent.reserve(card::CardAction::Send).is_err());
        confirm_card_test_settings(&mut no_final, card::CardLifecycle::NoFinalReply);
        assert_eq!(
            store.save_card(&mut no_final, "w1").await?,
            MarkOutcome::Applied
        );
        assert_eq!(
            store.save_card(&mut stale_intent, "w1").await?,
            MarkOutcome::LostClaim
        );
        assert_eq!(
            store.save_card(&mut stale_intent, "crashed-worker").await?,
            MarkOutcome::LostClaim
        );
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
            state.reserve(card::CardAction::Settings {
                streaming: false,
                lifecycle: card::CardLifecycle::Paused,
                recovery: false,
            })?;
            confirm_card_test_settings(&mut state, card::CardLifecycle::Paused);
            assert_eq!(
                store.save_card(&mut state, "w1").await?,
                MarkOutcome::Applied
            );
            let mut previous_target = state.clone();
            let continuation = format!("canonical-input:{message_id}");
            assert_eq!(
                store
                    .save_inbound_watch_input("legacy", "chat", message_id, "w1", &continuation)
                    .await?,
                MarkOutcome::Applied
            );
            assert!(state.bind_target(&continuation, turn_id)?);
            assert_eq!(
                store.save_card(&mut state, "w1").await?,
                MarkOutcome::Applied
            );
            assert_eq!(
                store.save_card(&mut previous_target, "w1").await?,
                MarkOutcome::LostClaim
            );
            assert_eq!(
                store
                    .save_card(&mut previous_target, "crashed-worker")
                    .await?,
                MarkOutcome::LostClaim
            );
            state.reserve(card::CardAction::Settings {
                streaming: false,
                lifecycle,
                recovery: false,
            })?;
            assert_eq!(
                store.save_card(&mut state, "w1").await?,
                MarkOutcome::Applied
            );
            if unknown {
                state.last_operation.as_mut().unwrap().status = card::CardOperationStatus::Unknown;
                state.lifecycle = card::CardLifecycle::NeedsAttention;
            } else {
                confirm_card_test_settings(&mut state, lifecycle);
            }
            assert_eq!(
                store.save_card(&mut state, "w1").await?,
                MarkOutcome::Applied
            );
            expected.push((binding, continuation, turn_id, unknown, lifecycle));
        }
        drop(store);

        let reopened = BotStateStore::new(path);
        let no_final = reopened.load_card(&binding).await?.unwrap();
        assert!(matches!(
            no_final.lifecycle,
            card::CardLifecycle::NoFinalReply
        ));
        assert!(no_final.final_content_hash.is_none());
        assert_eq!(no_final.confirmed_text, "last verified preview");
        assert_eq!(no_final.diagnostic.as_ref().unwrap().code, "noFinalReply");
        assert_eq!(
            no_final.diagnostic.as_ref().unwrap().message,
            "未生成最终答复，所示内容仅为未完成预览"
        );
        assert!(no_final.lifecycle.terminal());
        let (status, _) = work_status(&reopened, "legacy:chat:m1").await;
        assert_eq!(status, "needs_attention");
        for (binding, continuation, turn_id, unknown, lifecycle) in expected {
            let mut state = reopened.load_card(&binding).await?.unwrap();
            assert_eq!(state.watch_input, continuation);
            assert_eq!(state.turn_id.as_deref(), turn_id);
            assert_eq!(state.confirmed_text, "last verified preview");
            assert!(state.final_content_hash.is_none());
            assert_eq!(state.uncertain(), unknown);
            if unknown {
                assert!(matches!(
                    state.lifecycle,
                    card::CardLifecycle::NeedsAttention
                ));
                assert!(
                    state
                        .reserve(card::CardAction::Settings {
                            streaming: false,
                            lifecycle: card::CardLifecycle::NoFinalReply,
                            recovery: false,
                        })
                        .is_err()
                );
            } else {
                assert!(state.lifecycle == lifecycle);
                assert!(state.lifecycle.terminal());
            }
        }
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

    fn card_test_preview(binding: card::CardBinding) -> card::CardStream {
        let original_input = binding.original_input.clone();
        let mut state = card::CardStream::new(binding, &original_input, "original-turn");
        state.card_id = Some("known-card".into());
        state.platform_message_id = Some("known-message".into());
        state.confirmed_text = "last verified preview".into();
        state.confirmed_content_hash = card::hash(state.confirmed_text.as_bytes());
        state.lifecycle = card::CardLifecycle::Streaming;
        state
    }

    fn confirm_card_test_settings(state: &mut card::CardStream, lifecycle: card::CardLifecycle) {
        state.lifecycle = lifecycle;
        state.confirmed_sequence = state.sequence;
        state.last_operation.as_mut().unwrap().status = card::CardOperationStatus::Confirmed;
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
