//! Schema 15 → 16: rebuild bounded thinking summaries and independent background
//! tool groups from original facts and explicit summary contents.
use super::legacy_timeline_store as timeline;
use super::*;

pub(super) struct TimelineThinkingSummary;

impl MigrationName for TimelineThinkingSummary {
    fn name(&self) -> &str {
        TIMELINE_THINKING_SUMMARY
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for TimelineThinkingSummary {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let result: anyhow::Result<()> = async {
            let db = manager.get_connection();
            ensure!(
                version(db).await? == 15,
                "timeline thinking summary migration requires schema 15"
            );
            let row = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("timeline thinking summary migration has no history identity")?;
            let database_id: String = row.try_get("", "database_id")?;
            timeline::rebuild_schema16(db, &database_id).await?;
            set_version(db, 16).await?;
            Ok(())
        }
        .await;
        result.map_err(conversion)
    }
}
