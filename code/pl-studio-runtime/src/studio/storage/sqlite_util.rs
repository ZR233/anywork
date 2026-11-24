//! Shared SQLite file primitives. Domain schema admission stays with each database owner.

use anyhow::{Result, ensure};
use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};

/// Runs `PRAGMA quick_check`.
///
/// A connection or decode failure remains [`sea_orm::DbErr`]. A completed check whose row is
/// not `ok` is reported with `failed` and does not replace that database error.
pub(crate) async fn preflight_sqlite(
    db: &impl ConnectionTrait,
    failed: &'static str,
) -> Result<()> {
    for row in db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "PRAGMA quick_check",
        ))
        .await?
    {
        ensure!(row.try_get_by_index::<String>(0)? == "ok", "{failed}");
    }
    Ok(())
}

/// 只有数据库忙/锁/IO 类错误允许自动重试；结构或约束错误必须显式回给调用方。
pub(crate) fn is_retryable_write(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("database is locked")
        || message.contains("database table is locked")
        || message.contains("database is busy")
        || message.contains("disk i/o error")
        || message.contains("sqlite_busy")
        || message.contains("sqlite_locked")
        || message.contains("sqlite_ioerr")
}

#[cfg(test)]
mod tests {
    use super::*;
    use sea_orm::Database;

    #[tokio::test]
    async fn healthy_database_passes_without_rewriting_connection_errors() {
        let db = Database::connect("sqlite::memory:")
            .await
            .expect("memory database");
        preflight_sqlite(&db, "integrity check failed")
            .await
            .expect("fresh database is intact");

        db.close().await.expect("close memory database");
        let error = preflight_sqlite(&db, "integrity check failed")
            .await
            .expect_err("closed database must fail the pragma");
        assert!(
            error.downcast_ref::<sea_orm::DbErr>().is_some(),
            "connection failure must stay a database error, got {error:?}"
        );
        assert!(
            !error.to_string().contains("integrity check failed"),
            "connection failure must not be rewritten as an integrity result: {error}"
        );
    }
}
