//! Frozen schema-24 completion writer retained only by explicit migration fixtures.
use super::current::PreparedCurrent;
use super::*;

pub(in super::super) async fn apply(
    db: &impl ConnectionTrait,
    effect: u64,
    prepared: &PreparedCurrent,
) -> Result<()> {
    ensure!(
        prepared
            .owner_id()
            .is_none_or(|_| prepared.revision() == effect),
        "prepared facts belong to another effect"
    );
    for write in prepared.contents.iter() {
        ensure!(write.sealed, "independent documents must be complete");
        super::content::write_content(db, &write.content, true).await?;
    }
    crate::studio::storage::history::execution_sources::apply(db, effect, &prepared.source_changes)
        .await?;
    crate::studio::storage::history::execution_lifecycle::apply(db, &prepared.lifecycle).await?;
    Ok(())
}

pub(in super::super) async fn verify(
    db: &impl ConnectionTrait,
    prepared: &PreparedCurrent,
) -> Result<()> {
    crate::studio::storage::history::execution_sources::verify(
        db,
        prepared.revision(),
        &prepared.source_changes,
    )
    .await?;
    crate::studio::storage::history::execution_lifecycle::verify(db, &prepared.lifecycle).await?;
    for write in prepared.contents.iter() {
        let manifest = super::content::validate_content(db, &write.content)
            .await?
            .context("retried complete document is missing")?;
        ensure!(manifest.sealed, "retried complete document is not sealed");
    }
    Ok(())
}
