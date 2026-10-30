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

/// One canonical input of a Thread, projected from the durable checkpoint.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ThreadInputRow {
    /// Thread identity of the checkpoint these facts came from.
    pub thread_id: String,
    /// Read-only database the row was read from, for diagnostics.
    pub source: String,
    pub id: String,
    pub ordinal: u64,
    pub accepted_sequence: u64,
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

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct CheckpointProjection {
    thread_id: String,
    state: CheckpointStateProjection,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct CheckpointStateProjection {
    // Required: a checkpoint without the queue arrays is not the current shape.
    // This is a read-only projection of the current schema, not a full decoder.
    inputs: Vec<InputRecordProjection>,
    /// Bounded tail of minimal identities for inputs that already reached a
    /// terminal state; a consumed input may only be visible here.
    terminal_inputs: Vec<InputIdentityProjection>,
}

/// `InputIdentity` as `pl-core` serializes it (camelCase, all fields required).
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct InputIdentityProjection {
    pub(crate) digest: String,
    pub(crate) delivery: InputDeliveryProjection,
    pub(crate) id: String,
    pub(crate) ordinal: u64,
    pub(crate) revision: u64,
    pub(crate) state: InputStateProjection,
}

/// `InputRecord` as `pl-core` serializes it (camelCase, all fields required).
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct InputRecordProjection {
    pub(crate) accepted_sequence: u64,
    pub(crate) delivery: InputDeliveryProjection,
    pub(crate) input: InputBodyProjection,
    pub(crate) ordinal: u64,
    pub(crate) revision: u64,
    pub(crate) state: InputStateProjection,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct InputBodyProjection {
    pub(crate) id: String,
}

/// `InputDelivery` as `pl-core` serializes it: internally tagged with a `value`.
#[derive(serde::Deserialize)]
#[serde(
    tag = "kind",
    content = "value",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(crate) enum InputDeliveryProjection {
    NextTurn,
    CurrentTurn { turn_id: String },
}

impl InputDeliveryProjection {
    fn typed(&self) -> ThreadInputDelivery {
        match self {
            Self::NextTurn => ThreadInputDelivery::NextTurn,
            Self::CurrentTurn { turn_id } => ThreadInputDelivery::CurrentTurn {
                turn_id: turn_id.clone(),
            },
        }
    }
}

/// Current tagged encoding only; an unknown or missing tag is an error.
#[derive(serde::Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
enum InputStateProjection {
    Pending,
    Consumed {
        turn_id: String,
        // Decoded to prove the current tagged shape stays complete; the attempt
        // identity itself is not asserted here.
        #[allow(dead_code)]
        attempt_id: String,
    },
    Discarded,
}

/// Reads the canonical inputs of one Thread from its durable checkpoint.
///
/// The public Thread snapshot publishes no input list, so acceptance reads the
/// same checkpoint the runtime resumes from. The projection is a local strict
/// type over the current schema: a missing checkpoint row, an unknown input state
/// tag, or an unreadable database is an error, never an empty result. Only the
/// requested Thread is returned, and a second Thread in the same database is
/// reported as a conflict instead of being silently mixed.
pub(crate) async fn thread_inputs(home: &Path, thread_id: &str) -> Result<Vec<ThreadInputRow>> {
    let mut databases = Vec::new();
    collect_history_databases(home, 0, &mut databases)?;
    let mut rows: Option<(String, Vec<ThreadInputRow>)> = None;
    for path in databases {
        let mut connection = connect(&path).await.with_context(|| {
            format!(
                "failed to open the Thread checkpoint database {}",
                path.display()
            )
        })?;
        let selected = sea_orm::sqlx::query("SELECT payload FROM session_checkpoint")
            .fetch_all(&mut connection)
            .await
            .with_context(|| format!("failed to read session_checkpoint in {}", path.display()))?;
        connection
            .close()
            .await
            .with_context(|| format!("failed to close {}", path.display()))?;
        for row in selected {
            let payload = row
                .try_get::<String, _>(0)
                .with_context(|| format!("checkpoint payload missing in {}", path.display()))?;
            let checkpoint: CheckpointProjection =
                serde_json::from_str(&payload).with_context(|| {
                    format!("checkpoint payload is unreadable in {}", path.display())
                })?;
            if checkpoint.thread_id != thread_id {
                continue;
            }
            let mut thread_rows = Vec::new();
            let terminal = checkpoint.state.terminal_inputs.iter().map(|input| {
                let state = match &input.state {
                    InputStateProjection::Pending => ThreadInputState::Pending,
                    InputStateProjection::Consumed { turn_id, .. } => ThreadInputState::Consumed {
                        turn_id: turn_id.clone(),
                    },
                    InputStateProjection::Discarded => ThreadInputState::Discarded,
                };
                ThreadInputRow {
                    thread_id: checkpoint.thread_id.clone(),
                    source: path.display().to_string(),
                    id: input.id.clone(),
                    ordinal: input.ordinal,
                    accepted_sequence: 0,
                    revision: input.revision,
                    digest: Some(input.digest.clone()),
                    delivery: input.delivery.typed(),
                    state,
                }
            });
            for input in checkpoint.state.inputs {
                let state = match input.state {
                    InputStateProjection::Pending => ThreadInputState::Pending,
                    InputStateProjection::Consumed { turn_id, .. } => {
                        ThreadInputState::Consumed { turn_id }
                    }
                    InputStateProjection::Discarded => ThreadInputState::Discarded,
                };
                thread_rows.push(ThreadInputRow {
                    thread_id: checkpoint.thread_id.clone(),
                    source: path.display().to_string(),
                    id: input.input.id,
                    ordinal: input.ordinal,
                    accepted_sequence: input.accepted_sequence,
                    revision: input.revision,
                    digest: None,
                    delivery: input.delivery.typed(),
                    state,
                });
            }
            thread_rows.extend(terminal);
            match rows {
                Some((seen, _)) if seen != checkpoint.thread_id => {
                    anyhow::bail!("checkpoint databases disagree on the Thread identity")
                }
                Some((_, existing)) => {
                    anyhow::bail!(
                        "the Thread {thread_id} appears in more than one checkpoint database ({} rows so far, {} in {})",
                        existing.len(),
                        thread_rows.len(),
                        path.display()
                    )
                }
                None => rows = Some((checkpoint.thread_id, thread_rows)),
            }
        }
    }
    let Some((_, mut rows)) = rows else {
        anyhow::bail!("no checkpoint database holds Thread {thread_id}");
    };
    rows.sort_by_key(|row| row.ordinal);
    Ok(rows)
}

/// Bounded recursive search for per-Thread `history.sqlite` files.
///
/// Exceeding a bound is an error: a truncated search would silently report
/// "no checkpoint" for a Thread that really exists.
fn collect_history_databases(dir: &Path, depth: usize, found: &mut Vec<PathBuf>) -> Result<()> {
    const MAX_DEPTH: usize = 8;
    const MAX_FILES: usize = 32;
    anyhow::ensure!(
        depth <= MAX_DEPTH,
        "checkpoint search exceeded {MAX_DEPTH} levels at {}",
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
            "checkpoint search refuses symlink {}",
            path.display()
        );
        if metadata.is_dir() {
            collect_history_databases(&path, depth + 1, found)?;
        } else if path
            .file_name()
            .is_some_and(|name| name == "history.sqlite")
        {
            found.push(path);
            anyhow::ensure!(
                found.len() <= MAX_FILES,
                "checkpoint search found more than {MAX_FILES} databases"
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
