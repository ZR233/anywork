use anyhow::{Context, Result};
use sea_orm::sqlx::{
    Connection as _, Row,
    sqlite::{SqliteConnectOptions, SqliteConnection},
};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub(crate) struct BindingRow {
    pub chat_id: String,
}

#[derive(Debug, Clone)]
pub(crate) struct ThreadBindingRow {
    pub chat_id: String,
    pub thread_id: String,
    pub status: String,
    /// Production creation identity (`botthread:<bot>:<chat>:<operation>`).
    pub creation_id: String,
}

#[derive(Debug, Clone)]
pub(crate) struct InboundRow {
    pub message_id: String,
    pub status: String,
    pub diagnostic: String,
}

#[derive(Debug, Clone)]
pub(crate) struct SendRow {
    pub operation_id: String,
    pub status: String,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct SendDetailRow {
    pub operation_id: String,
    pub status: String,
    pub platform_message_ids: String,
    /// Raw durable segment-facts JSON, decoded by the caller with a strict
    /// local type so unreadable facts fail closed instead of being ignored.
    pub segment_facts: String,
}

#[derive(Debug, Clone)]
pub(crate) struct BindingOperationRow {
    pub operation_id: String,
    pub chat_id: String,
    pub thread_id: String,
    pub expected_revision: i64,
    /// Production creation identity persisted with the accepted operation.
    pub creation_id: String,
}

fn bot_state_db(home: &Path, bot_id: &str) -> PathBuf {
    home.join("v2")
        .join("bots")
        .join(bot_id)
        .join("state.sqlite")
}

pub(crate) async fn bindings(home: &Path, bot_id: &str) -> Result<Vec<BindingRow>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT chat_id FROM thread_bindings",
        |row| {
            Ok(BindingRow {
                chat_id: row.try_get::<String, _>(0)?,
            })
        },
    )
    .await
}

pub(crate) async fn thread_bindings(home: &Path, bot_id: &str) -> Result<Vec<ThreadBindingRow>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT chat_id, thread_id, status, creation_id FROM thread_bindings",
        |row| {
            Ok(ThreadBindingRow {
                chat_id: row.try_get::<String, _>(0)?,
                thread_id: row.try_get::<String, _>(1)?,
                status: row.try_get::<String, _>(2)?,
                creation_id: row.try_get::<String, _>(3)?,
            })
        },
    )
    .await
}

pub(crate) async fn inbound(home: &Path, bot_id: &str) -> Result<Vec<InboundRow>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT message_id, status, diagnostic FROM inbound_work",
        |row| {
            Ok(InboundRow {
                message_id: row.try_get::<String, _>(0)?,
                status: row.try_get::<String, _>(1)?,
                diagnostic: row.try_get::<String, _>(2).unwrap_or_default(),
            })
        },
    )
    .await
}

pub(crate) async fn observed_directs(home: &Path, bot_id: &str) -> Result<Vec<String>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT chat_id FROM observed_directs",
        |row| Ok(row.try_get::<String, _>(0)?),
    )
    .await
}

pub(crate) async fn binding_operations(
    home: &Path,
    bot_id: &str,
) -> Result<Vec<BindingOperationRow>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT operation_id, chat_id, COALESCE(thread_id, ''), expected_revision, creation_id \
         FROM binding_operations",
        |row| {
            Ok(BindingOperationRow {
                operation_id: row.try_get::<String, _>(0)?,
                chat_id: row.try_get::<String, _>(1)?,
                thread_id: row.try_get::<String, _>(2)?,
                expected_revision: row.try_get::<i64, _>(3)?,
                creation_id: row.try_get::<String, _>(4)?,
            })
        },
    )
    .await
}

pub(crate) async fn sends(home: &Path, bot_id: &str) -> Result<Vec<SendRow>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT operation_id, status FROM send_operations",
        |row| {
            Ok(SendRow {
                operation_id: row.try_get::<String, _>(0)?,
                status: row.try_get::<String, _>(1)?,
            })
        },
    )
    .await
}

pub(crate) async fn send_details(home: &Path, bot_id: &str) -> Result<Vec<SendDetailRow>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT operation_id, status, platform_message_ids, COALESCE(segment_facts, '') \
         FROM send_operations",
        |row| {
            Ok(SendDetailRow {
                operation_id: row.try_get::<String, _>(0)?,
                status: row.try_get::<String, _>(1)?,
                platform_message_ids: row.try_get::<String, _>(2)?,
                segment_facts: row.try_get::<String, _>(3)?,
            })
        },
    )
    .await
}

async fn query_rows<T, F>(path: &Path, sql: &'static str, map: F) -> Result<Vec<T>>
where
    F: Fn(&sea_orm::sqlx::sqlite::SqliteRow) -> Result<T>,
{
    let mut connection = connect(path).await?;
    let rows = sea_orm::sqlx::query(sql)
        .fetch_all(&mut connection)
        .await
        .with_context(|| format!("query failed on {}", path.display()))?;
    let mapped = rows.iter().map(map).collect();
    connection.close().await.ok();
    mapped
}

async fn connect(path: &Path) -> Result<SqliteConnection> {
    let options = SqliteConnectOptions::new().filename(path).read_only(true);
    SqliteConnection::connect_with(&options)
        .await
        .with_context(|| format!("failed to open {} read-only", path.display()))
}
