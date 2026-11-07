//! Upgrade the two published TimelineItems layouts through a separate named step.
//! Earlier Applied records, source facts, item order and projection generation stay intact.
use super::*;
use crate::studio::storage::history::conversation::timeline;

pub(super) struct MemberReadMetadata;

impl MigrationName for MemberReadMetadata {
    fn name(&self) -> &str {
        MEMBER_READ_METADATA
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for MemberReadMetadata {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

pub(super) async fn validate_source(db: &impl ConnectionTrait) -> Result<bool> {
    timeline::validate_base_tables(db).await?;
    let columns = db
        .query_all_raw(statement(
            "PRAGMA table_info(timeline_item_members)",
            vec![],
        ))
        .await?;
    let names = columns
        .iter()
        .map(|row| row.try_get::<String>("", "name"))
        .collect::<std::result::Result<std::collections::BTreeSet<_>, _>>()?;
    let updated = names.contains("updated_effect");
    let payload = names.contains("payload_bytes");
    ensure!(
        updated == payload,
        "incomplete timeline member read metadata; existing data preserved"
    );
    Ok(updated)
}

async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    let format = version(db).await?;
    if format == 14 {
        // No derived members exist before TimelineItems. That pending step
        // creates the current layout, after the original background correction.
        return timeline_items::validate_source(db).await;
    }
    ensure!(
        matches!(format, 15 | 16),
        "member read metadata migration requires schema 14 through 16"
    );
    if !validate_source(db).await? {
        let row = db
            .query_one_raw(statement(
                "SELECT source_effect_seq FROM timeline_projection_state WHERE singleton_id=1",
                vec![],
            ))
            .await?
            .context("member metadata migration has no projection head")?;
        let source_effect_seq = u64::try_from(row.try_get::<i64>("", "source_effect_seq")?)?;
        // The former format did not record each mutable member's last update.
        // The committed projection cut is a conservative bound for that head;
        // immutable terminal facts still supply their original cut qualification.
        db.execute_unprepared("ALTER TABLE timeline_item_members ADD COLUMN updated_effect INTEGER NOT NULL DEFAULT 0;
            ALTER TABLE timeline_item_members ADD COLUMN payload_bytes INTEGER;").await?;
        db.execute_raw(statement(
            "UPDATE timeline_item_members SET updated_effect=?,payload_bytes=(
               SELECT length(c.payload) FROM conversation_items c
               WHERE c.item_id=timeline_item_members.completion_item_id)",
            vec![integer(source_effect_seq)?.into()],
        ))
        .await?;
    }
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM timeline_item_members WHERE updated_effect<admitted_effect
           OR (completion_item_id IS NOT NULL AND payload_bytes IS NULL) LIMIT 1",
            vec![]
        ))
        .await?
        .is_none(),
        "member metadata has no reliable completion or effect bound; existing data preserved"
    );
    timeline::validate_tables(db).await
}
