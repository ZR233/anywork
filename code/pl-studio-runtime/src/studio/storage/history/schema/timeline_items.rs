//! Schema 14 → 15: derived Timeline item/member rows and projection state.
//! The rows are rebuilt by replaying the one Studio projection over preserved
//! atomic facts and the saved current cut; no original fact is rewritten.
use super::super::conversation::timeline;
use super::*;

pub(super) struct TimelineItems;
impl MigrationName for TimelineItems {
    fn name(&self) -> &str {
        TIMELINE_ITEMS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for TimelineItems {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let result: anyhow::Result<()> = async {
            let db = manager.get_connection();
            ensure!(
                version(db).await? == 14,
                "timeline item migration requires schema 14"
            );
            validate_source(db).await?;
            db.execute_unprepared(timeline::CREATE_SCHEMA).await?;
            db.execute_unprepared(timeline::CREATE_DERIVED_SCHEMA)
                .await?;
            let identity = db
                .query_one_raw(statement(
                    "SELECT database_id FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .context("timeline migration has no history identity")?;
            let database_id: String = identity.try_get("", "database_id")?;
            timeline::normalize_legacy(db).await?;
            timeline::rebuild(db, &database_id).await?;
            set_version(db, 15).await?;
            Ok(())
        }
        .await;
        result.map_err(conversion)
    }
}

pub(super) async fn validate_source(db: &impl ConnectionTrait) -> Result<()> {
    for table in [
        "timeline_items",
        "timeline_item_members",
        "timeline_projection_state",
        "conversation_atom_facts",
    ] {
        ensure!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
                vec![table.into()],
            ))
            .await?
            .is_none(),
            "pending timeline migration has pre-existing output table {table}; original database preserved"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests;
