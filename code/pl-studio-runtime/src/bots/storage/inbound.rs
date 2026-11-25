use super::binding::strict_watermark;
use super::*;

pub(super) const INBOUND_CLAIM_TTL_SECONDS: i64 = 60;
const INBOUND_RETRY_BASE_SECONDS: i64 = 5;
const INBOUND_RETRY_MAX_SECONDS: i64 = 300;
const INBOUND_RETRY_BUDGET: i64 = 8;
const INBOUND_PENDING_LIMIT: i64 = 64;
const INBOUND_PENDING_BYTES: i64 = 512 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrozenInbound {
    pub bot_id: String,
    pub message_id: String,
    pub chat_id: String,
    pub content_hash: String,
    pub text: String,
    pub attachments: Vec<crate::bots::inbound::InboundAttachment>,
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

impl BotStateStore {
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
            let stored_identity = stored_text(&row, "identity")?;
            let stored_bot = stored_text(&row, "bot_id")?;
            let stored_message = stored_text(&row, "message_id")?;
            let stored_chat = stored_text(&row, "chat_id")?;
            let stored_hash = stored_text(&row, "content_hash")?;
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
            let work_identity = stored_text(&work, "identity")?;
            let work_bot = stored_text(&work, "bot_id")?;
            let work_chat = stored_text(&work, "chat_id")?;
            let work_message = stored_text(&work, "message_id")?;
            let work_hash = stored_text(&work, "content_hash")?;
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
                text: stored_text(&work, "text")?,
                attachments: serde_json::from_str(&stored_text(&work, "attachments")?)
                    .map_err(|_| work_needs_recovery())?,
                open_id: stored_text(&work, "open_id")?,
                chat_kind: stored_text(&work, "chat_kind")?,
                app_id: stored_text(&work, "app_id")?,
                workspace_id: stored_text(&work, "workspace_id")?,
                creation_id: stored_text(&work, "creation_id")?,
                binding_revision: strict_watermark(&work, "binding_revision")?,
                watch_input: stored_text(&work, "watch_input")?,
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
        let stored_identity = stored_text(&row, "identity")?;
        let stored_bot = stored_text(&row, "bot_id")?;
        let stored_chat = stored_text(&row, "chat_id")?;
        let stored_message = stored_text(&row, "message_id")?;
        let _content_hash = stored_text(&row, "content_hash")?;
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
        let db = self.db().await?;
        let now = unix_seconds();
        let fence = InboundClaimFence::new(bot_id, chat_id, message_id, worker_id, now);
        let renewed = db
            .execute_raw(fence.statement(
                "UPDATE inbound_work
                 SET claimed_at=?, updated_at=?",
                vec![now.into(), now.into()],
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
        let db = self.db().await?;
        let now = unix_seconds();
        let fence = InboundClaimFence::new(bot_id, chat_id, message_id, worker_id, now);
        let updated = db
            .execute_raw(fence.statement(
                "UPDATE inbound_work
                 SET watch_input=?, updated_at=?",
                vec![watch_input.to_string().into(), now.into()],
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
        let db = self.db().await?;
        let now = unix_seconds();
        let fence = InboundClaimFence::new(bot_id, chat_id, message_id, worker_id, now);
        match finish {
            WorkFinish::Completed => {
                let updated = db
                    .execute_raw(fence.statement(
                        "UPDATE inbound_work
                         SET status='completed', diagnostic='', claimed_by='', claimed_at=0,
                             attempt_count=0, next_attempt_at=0, updated_at=?",
                        vec![now.into()],
                    ))
                    .await
                    .map_err(storage)?;
                Ok(mark_outcome(updated.rows_affected()))
            }
            WorkFinish::Interrupted => {
                let updated = db
                    .execute_raw(fence.statement(
                        "UPDATE inbound_work
                         SET status='pending',
                             diagnostic='runtime stopped before a local terminal fact',
                             claimed_by='', claimed_at=0, next_attempt_at=0, updated_at=?",
                        vec![now.into()],
                    ))
                    .await
                    .map_err(storage)?;
                Ok(mark_outcome(updated.rows_affected()))
            }
            WorkFinish::NeedsAttention(diagnostic) => {
                let updated = db
                    .execute_raw(fence.statement(
                        "UPDATE inbound_work
                         SET status='needs_attention', diagnostic=?, claimed_by='', claimed_at=0, updated_at=?",
                        vec![
                            diagnostic.to_string().into(),
                            now.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?;
                Ok(mark_outcome(updated.rows_affected()))
            }
            WorkFinish::Retryable(diagnostic) => {
                let tx = db.begin().await.map_err(storage)?;
                let row = tx
                    .query_one_raw(
                        fence.statement("SELECT attempt_count FROM inbound_work", vec![]),
                    )
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
                    tx.execute_raw(fence.statement(
                        "UPDATE inbound_work
                         SET status='needs_attention',
                             diagnostic=?,
                             claimed_by='', claimed_at=0, updated_at=?",
                        vec![
                            format!(
                                "recovery budget exhausted after {INBOUND_RETRY_BUDGET} failures: {diagnostic}"
                            )
                            .into(),
                            now.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?
                } else {
                    tx.execute_raw(fence.statement(
                        "UPDATE inbound_work
                         SET status='failed', diagnostic=?, claimed_by='', claimed_at=0,
                             attempt_count=?, next_attempt_at=?, updated_at=?",
                        vec![
                            diagnostic.to_string().into(),
                            next_count.into(),
                            now.saturating_add(retry_backoff_seconds(next_count)).into(),
                            now.into(),
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
                let identity: String = stored_text(&row, "identity")?;
                let row_bot: String = stored_text(&row, "bot_id")?;
                let row_chat: String = stored_text(&row, "chat_id")?;
                let row_message: String = stored_text(&row, "message_id")?;
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
                    attachments: serde_json::from_str(&stored_text(&row, "attachments")?)
                        .map_err(|_| work_needs_recovery())?,
                    open_id: stored_text(&row, "open_id")?,
                    chat_kind: stored_text(&row, "chat_kind")?,
                    // 绑定/路由/fencing 判据只接受持久值；空串（如尚无续接输入）是合法值。
                    app_id: stored_text(&row, "app_id")?,
                    workspace_id: stored_text(&row, "workspace_id")?,
                    creation_id: stored_text(&row, "creation_id")?,
                    binding_revision: strict_watermark(&row, "binding_revision")?,
                    watch_input: stored_text(&row, "watch_input")?,
                })
            })
            .collect()
    }
}

struct InboundClaimFence {
    values: [Value; 6],
}

impl InboundClaimFence {
    fn new(bot_id: &str, chat_id: &str, message_id: &str, worker_id: &str, now: i64) -> Self {
        Self {
            values: [
                inbound_identity(bot_id, chat_id, message_id).into(),
                bot_id.to_owned().into(),
                chat_id.to_owned().into(),
                message_id.to_owned().into(),
                worker_id.to_owned().into(),
                now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into(),
            ],
        }
    }

    fn statement(&self, sql: &str, mut values: Vec<Value>) -> Statement {
        values.extend_from_slice(&self.values);
        statement(
            &format!(
                "{sql} WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=? \
                 AND claimed_by=? AND status='claimed' AND claimed_at>?"
            ),
            values,
        )
    }
}

pub(super) fn inbound_identity(bot_id: &str, chat_id: &str, message_id: &str) -> String {
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
        .ok_or_else(crate::bots::occupancy::freeze_budget_error)
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
