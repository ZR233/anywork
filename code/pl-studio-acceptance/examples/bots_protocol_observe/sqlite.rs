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

/// One durable automatic-card stream row (`bot_card_streams`).
///
/// The typed reply facts live in `state_json`; this row keeps the raw text so
/// the caller can decode it with one strict local type instead of trusting a
/// hand-written field list.
#[derive(Debug, Clone)]
pub(crate) struct CardStreamRow {
    pub identity: String,
    pub message_id: String,
    pub thread_id: String,
    pub turn_id: String,
    pub version: i64,
    pub state_json: String,
}

/// One canonical input of a Thread, projected from the durable Current.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ThreadInputRow {
    /// Thread identity of the Current these facts came from.
    pub thread_id: String,
    /// Read-only database the row was read from, for diagnostics.
    pub source: String,
    pub id: String,
    pub ordinal: u64,
    /// Latest immutable state revision of this input.
    pub revision: u64,
    /// Content digest of a terminal identity; a resident record carries none.
    pub digest: Option<String>,
    pub delivery: ThreadInputDelivery,
    pub state: ThreadInputState,
}

/// Typed `InputDelivery` fact of one input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ThreadInputDelivery {
    NextTurn,
    CurrentTurn { turn_id: String },
}

/// Typed `InputState` of one canonical input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ThreadInputState {
    Pending,
    Consumed { turn_id: String },
    Discarded,
}

/// Reads the exact persisted input queues from the complete Current JSON.
/// History sequences are deliberately absent from this observation.
pub(crate) async fn thread_inputs(home: &Path, thread_id: &str) -> Result<Vec<ThreadInputRow>> {
    use pl_core::thread::{
        current::ThreadCurrent,
        input::{InputDelivery, InputState},
    };
    fn delivery(value: &InputDelivery) -> ThreadInputDelivery {
        match value {
            InputDelivery::NextTurn => ThreadInputDelivery::NextTurn,
            InputDelivery::CurrentTurn { turn_id } => ThreadInputDelivery::CurrentTurn {
                turn_id: turn_id.clone(),
            },
        }
    }
    fn state(value: &InputState) -> ThreadInputState {
        match value {
            InputState::Pending => ThreadInputState::Pending,
            InputState::Consumed { turn_id, .. } => ThreadInputState::Consumed {
                turn_id: turn_id.clone(),
            },
            InputState::Discarded => ThreadInputState::Discarded,
        }
    }
    let mut paths = Vec::new();
    collect_current_files(home, 0, &mut paths)?;
    let mut result = None;
    for path in paths {
        let bytes = tokio::fs::read(&path)
            .await
            .with_context(|| format!("read Current {}", path.display()))?;
        let envelope: serde_json::Value = serde_json::from_slice(&bytes)?;
        let saved_thread_id = envelope["threadId"]
            .as_str()
            .context("saved Current omitted its Thread identity")?;
        let saved = ThreadCurrent::from_json(&bytes, saved_thread_id)?;
        if saved.thread_id != thread_id {
            continue;
        }
        anyhow::ensure!(result.is_none(), "duplicate Current identity {thread_id}");
        let mut rows = saved
            .state
            .inputs
            .iter()
            .map(|input| ThreadInputRow {
                thread_id: saved.thread_id.clone(),
                source: path.display().to_string(),
                id: input.input.id.clone(),
                ordinal: input.ordinal,
                revision: input.revision,
                digest: None,
                delivery: delivery(&input.delivery),
                state: state(&input.state),
            })
            .collect::<Vec<_>>();
        rows.extend(
            saved
                .state
                .terminal_inputs
                .iter()
                .map(|input| ThreadInputRow {
                    thread_id: saved.thread_id.clone(),
                    source: path.display().to_string(),
                    id: input.id.clone(),
                    ordinal: input.ordinal,
                    revision: input.revision,
                    digest: Some(input.digest.clone()),
                    delivery: delivery(&input.delivery),
                    state: state(&input.state),
                }),
        );
        result = Some(rows);
    }
    let mut rows = result.with_context(|| format!("no saved Current holds Thread {thread_id}"))?;
    rows.sort_by_key(|row| row.ordinal);
    Ok(rows)
}

/// Bounded recursive search for per-Thread `current.json` files.
///
/// Exceeding a bound is an error: a truncated search would silently report
/// "no Current" for a Thread that really exists.
fn collect_current_files(dir: &Path, depth: usize, found: &mut Vec<PathBuf>) -> Result<()> {
    const MAX_DEPTH: usize = 8;
    const MAX_FILES: usize = 32;
    anyhow::ensure!(
        depth <= MAX_DEPTH,
        "Current search exceeded {MAX_DEPTH} levels at {}",
        dir.display()
    );
    let entries =
        std::fs::read_dir(dir).with_context(|| format!("failed to read {}", dir.display()))?;
    let mut paths = Vec::new();
    for entry in entries {
        paths.push(entry?.path());
    }
    paths.sort();
    for path in paths {
        let metadata = std::fs::symlink_metadata(&path)?;
        anyhow::ensure!(
            !metadata.file_type().is_symlink(),
            "Current search refuses symlink {}",
            path.display()
        );
        if metadata.is_dir() {
            collect_current_files(&path, depth + 1, found)?;
        } else if path.file_name().is_some_and(|name| name == "current.json") {
            found.push(path);
            anyhow::ensure!(
                found.len() <= MAX_FILES,
                "Current search found more than {MAX_FILES} databases"
            );
        }
    }
    Ok(())
}

fn bot_state_db(home: &Path, bot_id: &str) -> PathBuf {
    home.join("data")
        .join("bots")
        .join(bot_id)
        .join("state.sqlite")
}

pub(crate) async fn card_streams(home: &Path, bot_id: &str) -> Result<Vec<CardStreamRow>> {
    query_rows(
        &bot_state_db(home, bot_id),
        "SELECT identity, message_id, COALESCE(thread_id, ''), COALESCE(turn_id, ''), version, \
         state_json FROM bot_card_streams",
        |row| {
            Ok(CardStreamRow {
                identity: row.try_get::<String, _>(0)?,
                message_id: row.try_get::<String, _>(1)?,
                thread_id: row.try_get::<String, _>(2)?,
                turn_id: row.try_get::<String, _>(3)?,
                version: row.try_get::<i64, _>(4)?,
                state_json: row.try_get::<String, _>(5)?,
            })
        },
    )
    .await
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
    connection
        .close()
        .await
        .with_context(|| format!("failed to close {}", path.display()))?;
    mapped
}

async fn connect(path: &Path) -> Result<SqliteConnection> {
    let options = SqliteConnectOptions::new().filename(path).read_only(true);
    SqliteConnection::connect_with(&options)
        .await
        .with_context(|| format!("failed to open {} read-only", path.display()))
}
