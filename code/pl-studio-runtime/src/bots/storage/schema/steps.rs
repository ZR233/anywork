//! Appended migration boundaries. Every conversion, format marker and official completion row
//! commits in the same framework transaction; no helper here starts another transaction.

use super::lineage::{self, Format};
use super::*;

pub(super) struct File8;
pub(super) struct Audience9;
pub(super) struct Publication10;
pub(super) struct Adopt(pub(super) Format);

impl MigrationName for File8 {
    fn name(&self) -> &str {
        lineage::FILE8
    }
}
impl MigrationName for Audience9 {
    fn name(&self) -> &str {
        lineage::AUDIENCE9
    }
}
impl MigrationName for Publication10 {
    fn name(&self) -> &str {
        lineage::PUBLICATION10
    }
}
impl MigrationName for Adopt {
    fn name(&self) -> &str {
        self.0.adoption_name()
    }
}

fn migration_failure(error: anyhow::Error) -> DbErr {
    match error.downcast::<DbErr>() {
        Ok(error) => error,
        Err(error) => DbErr::Migration(format!("{error:#}")),
    }
}

async fn mark<C: ConnectionTrait>(db: &C, version: i64) -> anyhow::Result<()> {
    anyhow::ensure!(
        db.execute_raw(statement(
            "UPDATE bot_meta SET schema_version=? WHERE id=1",
            vec![version.into()]
        ))
        .await?
        .rows_affected()
            == 1,
        "bot format marker is missing"
    );
    Ok(())
}

async fn normalize_files<C: ConnectionTrait>(db: &C, source: Format) -> anyhow::Result<()> {
    super::preflight::validate_format(db, source).await?;
    if source == Format::MainCard6 {
        // Published main card6 still owns snake_case text facts. Task file6 already owns the
        // current text representation and must never enter this import.
        migrate_text_send_facts(db).await?;
    }
    super::super::migrate(db, source.version()).await?;
    validate_ledger_schema(db, LedgerSource::Current8).await?;
    mark(db, 8).await
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for File8 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        normalize_files(manager.get_connection(), Format::MainCard6)
            .await
            .map_err(migration_failure)
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for Adopt {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let result = match self.0 {
            Format::File6 | Format::File7 => normalize_files(db, self.0).await,
            Format::File8 | Format::Audience9 | Format::Publication10 => {
                super::preflight::validate_format(db, self.0).await
            }
            Format::PreSix(_) | Format::MainCard6 => Err(anyhow::anyhow!(
                "main ledger cannot enter a file-format adoption"
            )),
        };
        result.map_err(migration_failure)
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for Audience9 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        async {
            super::preflight::validate_format(db, Format::File8).await?;
            audience::migrate(db).await?;
            mark(db, 9).await
        }
        .await
        .map_err(migration_failure)
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for Publication10 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        async {
            super::preflight::validate_format(db, Format::Audience9).await?;
            audience::prepare_count_indexes(db).await?;
            audience::validate(db).await?;
            publication::migrate_schema(db).await?;
            audience::prepare_current_indexes(db).await?;
            audience::validate_current(db).await?;
            publication::validate_schema(db).await?;
            mark(db, 10).await
        }
        .await
        .map_err(migration_failure)
    }
}
