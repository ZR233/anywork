use super::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
use crate::studio::unix_seconds;
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, QueryResult, Statement,
    TransactionTrait, Value,
};
use std::path::{Path, PathBuf};
use std::time::Duration;

mod binding;
pub(super) mod card;
mod inbound;
use inbound::{INBOUND_CLAIM_TTL_SECONDS, inbound_identity};
mod pairing;
mod schema;
mod send;

pub use binding::{BindingOperation, BindingProjection, ThreadBindingClaim};
pub(crate) use binding::{binding_needs_recovery, binding_superseded};
pub(crate) use inbound::{ClaimLease, MarkOutcome, WorkFinish, inbound_identity_bytes};
pub use inbound::{FrozenInbound, InboundAdmit, InboundClaim};
pub use send::{SendRecord, SendRecordStatus, SendSegmentFact};
pub(crate) use send::{segment_facts_bytes, verify_send_identity};

const BOT_STATE_SCHEMA_VERSION: i64 = 7;

#[derive(Clone)]
pub struct BotStateStore {
    path: PathBuf,
    writer: tokio::sync::OnceCell<DatabaseConnection>,
}

#[derive(Debug, Clone)]
pub struct IdentityOccupancy {
    pub has_thread_or_inbound: bool,
    pub has_app_identity: bool,
}

impl BotStateStore {
    pub(crate) async fn delete_threads(&self, ids: &[String]) -> Result<(), FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        for id in ids {
            // Input identities and sends are tied to their original ledger rows, never inferred
            // from an entire chat (a neighboring replacement binding may share that chat).
            tx.execute_raw(statement(
                "DELETE FROM send_operations WHERE operation_id IN
                 (SELECT 'botreply:' || bot_id || ':' || chat_id || ':' || message_id
                    FROM bot_card_streams WHERE thread_id=?)",
                vec![id.clone().into()],
            ))
            .await
            .map_err(storage)?;
            tx.execute_raw(statement(
                "DELETE FROM inbound_identities WHERE identity IN
                 (SELECT identity FROM inbound_work WHERE creation_id=?)",
                vec![id.clone().into()],
            ))
            .await
            .map_err(storage)?;
            for (table, predicate) in [
                ("bot_card_streams", "thread_id=?"),
                ("inbound_work", "creation_id=?"),
                ("binding_operations", "thread_id=? OR creation_id=?"),
                ("thread_bindings", "thread_id=? OR creation_id=?"),
            ] {
                let values = if predicate.contains(" OR ") {
                    vec![id.clone().into(), id.clone().into()]
                } else {
                    vec![id.clone().into()]
                };
                tx.execute_raw(statement(
                    &format!("DELETE FROM {table} WHERE {predicate}"),
                    values,
                ))
                .await
                .map_err(storage)?;
            }
        }
        tx.commit().await.map_err(storage)?;
        Ok(())
    }
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
        let row = db
            .query_one_raw(statement(
                "SELECT EXISTS(SELECT 1 FROM thread_bindings)
                    OR EXISTS(SELECT 1 FROM inbound_identities)
                    OR EXISTS(SELECT 1 FROM inbound_work) AS thread_or_inbound,
                    EXISTS(SELECT 1 FROM observed_directs)
                    OR EXISTS(SELECT 1 FROM pairing_requests)
                    OR EXISTS(SELECT 1 FROM send_operations) AS platform_records",
                vec![],
            ))
            .await
            .map_err(storage)?
            .ok_or_else(stored_record_unreadable)?;
        let has_thread_or_inbound = stored_i64(&row, "thread_or_inbound")? != 0;
        Ok(IdentityOccupancy {
            has_thread_or_inbound,
            has_app_identity: has_thread_or_inbound || stored_i64(&row, "platform_records")? != 0,
        })
    }
}
fn empty_to_none(value: String) -> Option<String> {
    if value.is_empty() { None } else { Some(value) }
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
mod test_support;
#[cfg(test)]
mod tests;
