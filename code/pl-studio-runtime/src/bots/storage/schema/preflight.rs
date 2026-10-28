//! Read-only source proof. No migration-table installation, write pragma, DDL or repair belongs here.

use super::lineage::{Format, Migrator};
use super::*;

pub(super) async fn inspect<C: ConnectionTrait>(
    db: &C,
    origin: DatabaseOrigin,
) -> anyhow::Result<Migrator> {
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        anyhow::ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "bot ledger integrity check failed"
        );
    }
    if matches!(origin, DatabaseOrigin::Created) {
        anyhow::ensure!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*' LIMIT 1",
                vec![]
            ))
            .await?
            .is_none(),
            "a newly owned bot ledger is not empty; existing data preserved"
        );
        return Ok(Migrator::Main);
    }
    for table in ["bot_meta", "send_operations"] {
        anyhow::ensure!(
            table_exists(db, table).await?,
            "persisted bot database lacks {table}; existing data preserved"
        );
    }
    let metadata = db
        .query_all_raw(statement("SELECT id,schema_version FROM bot_meta", vec![]))
        .await?;
    anyhow::ensure!(
        metadata.len() == 1 && metadata[0].try_get::<i64>("", "id")? == 1,
        "missing or conflicting bot ledger identity"
    );
    let version: i64 = metadata[0].try_get("", "schema_version")?;
    anyhow::ensure!(
        (1..=BOT_STATE_SCHEMA_VERSION).contains(&version),
        "unsupported bot state schema {version}; existing data preserved"
    );
    let columns = table_columns(db, "send_operations").await?;
    let file_marked = columns.contains("send_identity") || columns.contains("send_source");
    let format = match version {
        1..=5 if !file_marked => Format::PreSix(version),
        6 if !file_marked => Format::MainCard6,
        6 => Format::File6,
        7 => Format::File7,
        8 => Format::File8,
        9 => Format::Audience9,
        10 => Format::Publication10,
        _ => anyhow::bail!("text ledger declares incompatible file markers"),
    };
    // Select by the official records first. A now-ten database must not switch from its recorded
    // main/file8 entry to a newly inferred adopt-ten entry.
    let recorded = Migrator::recorded(db).await?;
    if let Some(migrator) = recorded {
        migrator.verify_format(db, format).await?;
    }
    validate_format(db, format).await?;
    Ok(recorded.unwrap_or_else(|| Migrator::for_source(format)))
}

pub(super) async fn validate_format<C: ConnectionTrait>(
    db: &C,
    format: Format,
) -> anyhow::Result<()> {
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version FROM bot_meta WHERE id=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| anyhow::anyhow!("missing bot format"))?;
    anyhow::ensure!(
        row.try_get::<i64>("", "schema_version")? == format.version(),
        "bot format changed at its migration boundary"
    );
    match format {
        Format::PreSix(version) => {
            legacy_schema::validate(db, version).await?;
            let columns = table_columns(db, "send_operations").await?;
            anyhow::ensure!(
                [
                    "operation_id",
                    "chat_id",
                    "content_hash",
                    "status",
                    "platform_message_ids",
                    "updated_at"
                ]
                .iter()
                .all(|column| columns.contains(*column)),
                "legacy bot send ledger is incomplete"
            );
        }
        source => {
            validate_ledger_schema(
                db,
                match source {
                    Format::MainCard6 => LedgerSource::MainCard6,
                    Format::File6 => LedgerSource::TaskFile6,
                    Format::File7 => LedgerSource::TaskFile7,
                    Format::File8 | Format::Audience9 | Format::Publication10 => {
                        LedgerSource::Current8
                    }
                    Format::PreSix(_) => unreachable!(),
                },
            )
            .await?
        }
    }
    validate_sends(db, format).await?;
    if table_exists(db, "bot_card_streams").await? {
        let mut after: Option<String> = None;
        loop {
            let rows = db.query_all_raw(statement(
                "SELECT * FROM bot_card_streams WHERE (?1 IS NULL OR identity>?1) ORDER BY identity LIMIT 32",
                vec![after.clone().into()],
            )).await?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                let stream = card::decode_stored(row)?;
                after = Some(inbound_identity(
                    &stream.binding.bot_id,
                    &stream.binding.chat_id,
                    &stream.binding.message_id,
                ));
            }
        }
    }
    match format {
        Format::Audience9 => {
            audience::validate_source_nine(db).await?;
            publication::preflight_migration(db).await?;
        }
        Format::Publication10 => {
            audience::validate_current(db).await?;
            publication::validate_schema(db).await?;
        }
        Format::MainCard6 | Format::File8 => audience::preflight_eight(db).await?,
        Format::File6 | Format::File7 => audience::preflight_file_without_cards(db).await?,
        _ => audience::ensure_eight_absent(db).await?,
    }
    if format.version() < 10 {
        for name in [
            "bot_delivery_scopes",
            "bot_delivery_claims",
            "bot_delivery_cursors",
            "bot_delivery_pending",
        ] {
            anyhow::ensure!(
                !table_exists(db, name).await?,
                "unversioned bot publication structure: {name}"
            );
        }
    }
    anyhow::ensure!(
        db.query_one_raw(statement("PRAGMA foreign_key_check", vec![]))
            .await?
            .is_none(),
        "bot ledger foreign key proof failed"
    );
    Ok(())
}

async fn table_exists<C: ConnectionTrait>(db: &C, name: &str) -> anyhow::Result<bool> {
    Ok(db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
            vec![name.into()],
        ))
        .await?
        .is_some())
}

async fn validate_sends<C: ConnectionTrait>(db: &C, format: Format) -> anyhow::Result<()> {
    let old_text = matches!(format, Format::PreSix(_) | Format::MainCard6);
    if old_text
        && !table_columns(db, "send_operations")
            .await?
            .contains("segment_facts")
    {
        return Ok(());
    }
    // Import reads span the File8 ALTER TABLE boundary. A wildcard projection changes its result
    // shape while retaining the same prepared SQL/cache key, so each historical codec names only
    // the fields it actually consumes. The current reader also keeps its mapping explicit.
    let select = if old_text {
        "SELECT operation_id,segment_facts FROM send_operations WHERE (?1 IS NULL OR operation_id>?1) ORDER BY operation_id LIMIT 64"
    } else {
        "SELECT operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,send_identity,send_source FROM send_operations WHERE (?1 IS NULL OR operation_id>?1) ORDER BY operation_id LIMIT 64"
    };
    let mut after: Option<String> = None;
    loop {
        let rows = db
            .query_all_raw(statement(select, vec![after.clone().into()]))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = Some(row.try_get("", "operation_id")?);
            if old_text {
                let raw: String = row.try_get("", "segment_facts")?;
                if !raw.is_empty() {
                    serde_json::from_str::<Vec<LegacyTextSegment>>(&raw)?;
                }
            } else {
                send_record_from_row(row)?;
            }
        }
    }
    Ok(())
}

/// Frozen pre-file wire shape, consumed only by read-only import validation. Field values are not
/// reconstructed as new platform facts; the original LedgerSchema/File8 conversions retain them.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyTextSegment {
    #[serde(rename = "index")]
    _index: u32,
    #[serde(rename = "uuid")]
    _uuid: String,
    #[serde(rename = "status")]
    _status: SendRecordStatus,
    #[serde(rename = "platform_message_id")]
    _platform_message_id: Option<String>,
    #[serde(rename = "diagnostic")]
    _diagnostic: Option<String>,
}
