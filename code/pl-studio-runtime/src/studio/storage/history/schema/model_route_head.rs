//! Schema 12 → 13: prepare historical route/Profile encodings and project the checkpoint head.
use super::*;

pub(super) struct RootModelRouteHead {
    pub(super) thread_id: String,
}

impl MigrationName for RootModelRouteHead {
    fn name(&self) -> &str {
        MODEL_ROUTE_HEAD
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for RootModelRouteHead {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let result: anyhow::Result<()> = async {
            ensure!(
                version(db).await? == 12,
                "model route head migration requires schema 12"
            );
            demand_conversation::validate_tables(db).await?;
            validate_source(db).await?;
            // Reuse all canonical hash, identity, context and fence validation. Only this
            // explicit migration reads the full checkpoint to backfill the narrow head.
            let original = checkpoint::read(db, &self.thread_id).await?;
            db.execute_unprepared(
                "ALTER TABLE history_meta ADD COLUMN model_route_json TEXT NULL;
                 ALTER TABLE history_meta ADD COLUMN model_route_hash TEXT NULL",
            )
            .await?;
            if let Some(original) = original {
                let mut migrated = original.clone();
                crate::studio::model_route::migration::upgrade(&mut migrated.state)?;
                checkpoint::write_representation(db, &original, &migrated).await?;
                checkpoint::write_model_route_head(db, &migrated.state).await?;
            }
            validate_tables(db).await?;
            checkpoint::read_model_route_head(db).await?;
            set_version(db, 13).await?;
            Ok(())
        }
        .await;
        result.map_err(conversion)
    }
}

pub(super) async fn validate_source(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        db.query_all_raw(statement(
            "SELECT name FROM pragma_table_info('history_meta')
             WHERE name IN ('model_route_json','model_route_hash')",
            vec![],
        ))
        .await?
        .is_empty(),
        "pending model route head migration has pre-existing output columns; existing data preserved"
    );
    Ok(())
}

/// Shape admission never selects the recovery payload or context rows.
pub(super) async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    db.query_all_raw(statement(
        "SELECT model_route_json,model_route_hash FROM history_meta LIMIT 0",
        vec![],
    ))
    .await?;
    let columns = db
        .query_all_raw(statement(
            "SELECT name,type,\"notnull\" FROM pragma_table_info('history_meta')
             WHERE name IN ('model_route_json','model_route_hash')",
            vec![],
        ))
        .await?;
    ensure!(columns.len() == 2, "model route head columns are missing");
    for column in columns {
        ensure!(
            column
                .try_get::<String>("", "type")?
                .eq_ignore_ascii_case("TEXT")
                && column.try_get::<i64>("", "notnull")? == 0,
            "model route head columns must be nullable TEXT"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests;
