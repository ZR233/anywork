//! Product schema ownership and official migration history.
use anyhow::{Result, ensure};
use sea_orm::{ConnectionTrait, DatabaseBackend, DatabaseConnection, DbErr, Statement};
use sea_orm_migration::{MigrationName, MigrationTrait, MigratorTrait, SchemaManager};

pub(in crate::studio) const STUDIO_DATABASE_SCHEMA_VERSION: i64 = 25;

pub(super) async fn preflight(db: &DatabaseConnection) -> Result<()> {
    let version = version(db).await?;
    if version == 0 {
        ensure!(db.query_one_raw(Statement::from_string(DatabaseBackend::Sqlite, "SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1")).await?.is_none(), "unversioned nonempty Studio database; existing data preserved");
        ensure!(
            Migrator::get_applied_migrations_read_only(db)
                .await?
                .is_empty(),
            "Studio schema is missing; existing data preserved"
        );
    } else {
        ensure!(
            (22..=25).contains(&version),
            crate::studio::startup::migration_error(
                "Studio product",
                "preflight",
                super::StudioDatabaseError::UnsupportedSchema {
                    found: version,
                    supported: STUDIO_DATABASE_SCHEMA_VERSION
                }
            )
        );
    }
    let pending = Migrator::get_pending_migrations_read_only(db)
        .await
        .map_err(|error| {
            crate::studio::startup::migration_error("Studio product", "preflight", error)
        })?;
    ensure!(
        !pending.is_empty() || version == STUDIO_DATABASE_SCHEMA_VERSION,
        "Studio format conflicts with completed migrations; existing data preserved"
    );
    for row in db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "PRAGMA quick_check",
        ))
        .await?
    {
        ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "Studio database integrity check failed"
        );
    }
    Ok(())
}

pub(super) async fn migrate(db: &DatabaseConnection) -> Result<()> {
    preflight(db).await.map_err(|error| {
        crate::studio::startup::migration_error("Studio product", "preflight", error)
    })?;
    if let Err(error) = Migrator::up(db, None).await {
        let pending = Migrator::get_pending_migrations_read_only(db)
            .await
            .unwrap_or_default();
        let step = pending
            .first()
            .map_or("migration bookkeeping", |migration| migration.name());
        return Err(crate::studio::startup::migration_error(
            "Studio product",
            step,
            error,
        ));
    }
    Ok(())
}

async fn version(db: &impl ConnectionTrait) -> Result<i64, DbErr> {
    db.query_one_raw(Statement::from_string(
        DatabaseBackend::Sqlite,
        "PRAGMA user_version",
    ))
    .await?
    .ok_or_else(|| DbErr::Migration("missing Studio format".into()))?
    .try_get_by_index(0)
}

struct Migrator;
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(ProductSchema),
            Box::new(DirectoryFields),
            Box::new(Delegation),
            Box::new(ExplicitClose),
        ]
    }
}

struct ProductSchema;
impl MigrationName for ProductSchema {
    fn name(&self) -> &str {
        "m20261026_000001_product_schema"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ProductSchema {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? == 0 {
            db.execute_unprepared(include_str!("product_schema.sql"))
                .await?;
            db.execute_unprepared(include_str!("agent_evaluations.sql"))
                .await?;
            db.execute_unprepared("PRAGMA user_version=25").await?;
        }
        Ok(())
    }
}

struct DirectoryFields;
impl MigrationName for DirectoryFields {
    fn name(&self) -> &str {
        "m20261026_000002_product_directory_fields"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for DirectoryFields {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? == 22 {
            db.execute_unprepared("ALTER TABLE threads ADD COLUMN last_user_message_at INTEGER; PRAGMA user_version=23").await?;
        }
        Ok(())
    }
}

struct Delegation;
impl MigrationName for Delegation {
    fn name(&self) -> &str {
        "m20261026_000003_product_delegation"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for Delegation {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 24 {
            db.execute_unprepared("ALTER TABLE threads ADD COLUMN delegation_mode TEXT NOT NULL DEFAULT 'profile'; ALTER TABLE threads ADD COLUMN delegation_preference TEXT NOT NULL DEFAULT 'balanced'; ALTER TABLE threads ADD COLUMN frozen_model_json TEXT;").await?;
            db.execute_unprepared(include_str!("agent_evaluations.sql"))
                .await?;
            db.execute_unprepared("PRAGMA user_version=24").await?;
        }
        Ok(())
    }
}

struct ExplicitClose;
impl MigrationName for ExplicitClose {
    fn name(&self) -> &str {
        "m20261026_000004_product_explicit_close"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ExplicitClose {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 25 {
            db.execute_unprepared("ALTER TABLE threads ADD COLUMN explicitly_closed INTEGER NOT NULL DEFAULT 0 CHECK(explicitly_closed IN (0,1)); PRAGMA user_version=25").await?;
        }
        Ok(())
    }
}
