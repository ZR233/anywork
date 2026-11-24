//! Schema 16 → 17 changes only the rebuildable background-result grouping.
use super::legacy_timeline_store as timeline;
use super::*;

pub(super) struct TimelineBackgroundTail;

impl MigrationName for TimelineBackgroundTail {
    fn name(&self) -> &str {
        TIMELINE_BACKGROUND_TAIL
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for TimelineBackgroundTail {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        async {
            let db = manager.get_connection();
            ensure!(
                version(db).await? == 16,
                "background tail migration requires schema 16"
            );
            let row = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("background tail migration has no history identity")?;
            timeline::rebuild(db, &row.try_get::<String>("", "database_id")?).await?;
            set_version(db, 17).await?;
            Ok::<_, anyhow::Error>(())
        }
        .await
        .map_err(conversion)
    }
}
