//! schema 11→12：在维护租约与单事务内，从不可变 effect 回填任务身份索引。
use sea_orm::{ConnectionTrait, Database, TransactionTrait};

use super::{SessionStoreError, SqliteSessionOptions, sqlite, thread_history, tool_task_index};

pub(super) async fn migrate_v11(options: SqliteSessionOptions) -> Result<(), SessionStoreError> {
    let mut url = url::Url::parse("sqlite:///")
        .map_err(|error| SessionStoreError::Invalid(error.to_string()))?;
    url.set_path(
        options
            .path
            .to_str()
            .ok_or_else(|| SessionStoreError::Invalid("non-UTF8 database path".into()))?,
    );
    url.set_query(Some("mode=rw"));
    let db = Database::connect(url.to_string()).await?;
    let result = async {
        let tx = db.begin().await?;
        let version = tx.query_one_raw(sqlite::statement("PRAGMA user_version", vec![])).await?
            .ok_or_else(|| SessionStoreError::Invalid("missing version".into()))?
            .try_get::<i64>("", "user_version")?;
        if version == 12 { tx.commit().await?; return Ok(()); }
        if version != 11 {
            return Err(SessionStoreError::UnsupportedSchema { found: version, supported: 12 });
        }
        tx.execute_unprepared(tool_task_index::SCHEMA).await?;
        let mut after_thread = String::new();
        loop {
            let sessions = tx.query_all_raw(sqlite::statement(
                "SELECT DISTINCT session_id FROM session_entries WHERE session_id>? ORDER BY session_id LIMIT 128",
                vec![after_thread.clone().into()],
            )).await?;
            if sessions.is_empty() { break; }
            for session in sessions {
                let thread_id: String = session.try_get("", "session_id")?;
                after_thread.clone_from(&thread_id);
                let mut after = "pl.resource.thread-commit.".to_owned();
                let mut expected_sequence = 1;
                loop {
                    let rows = tx.query_all_raw(sqlite::statement(
                        "SELECT * FROM session_entries WHERE session_id=? AND id>? AND id<? ORDER BY id LIMIT 128",
                        vec![thread_id.clone().into(), after.clone().into(), "pl.resource.thread-commit/".into()],
                    )).await?;
                    if rows.is_empty() { break; }
                    for row in rows {
                        let effect = thread_history::decode_effect(row, &thread_id)?;
                        if effect.sequence != expected_sequence {
                            return Err(SessionStoreError::Invalid(format!("Thread {thread_id} effect 链在 {expected_sequence} 处不连续")));
                        }
                        expected_sequence = effect.sequence.checked_add(1)
                            .ok_or_else(|| SessionStoreError::Invalid("effect 序号溢出".into()))?;
                        after = format!("pl.resource.thread-commit.{:020}", effect.sequence);
                        tool_task_index::apply(&tx, &effect).await?;
                    }
                }
            }
        }
        tx.execute_unprepared("PRAGMA user_version=12").await?;
        tx.commit().await?;
        Ok(())
    }.await;
    match (result, db.close().await) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) => Err(error),
        (Ok(()), Err(error)) => Err(error.into()),
        (Err(initialization), Err(cleanup)) => Err(SessionStoreError::InitializationCleanup {
            initialization: Box::new(initialization),
            cleanup: Box::new(cleanup),
        }),
    }
}
