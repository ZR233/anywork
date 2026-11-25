//! 产品目录/lease 事实在一个 SQLite 事务中提交。
//!
//! 模型调用事实属于独立的 `calls.sqlite`，由 `storage::calls::CallsStore` 的唯一逻辑 writer
//! 落库，本模块不再承载模型性能或计费的第二份事实。
use super::queue::{PendingBatch, StudioMutation};
use super::store_error;
use super::worker::{BatchError, PersistenceDisposition};
use crate::PureError;
use crate::studio::StudioStore;
use crate::studio::store::directory::apply_directory_delta;
use crate::studio::store::object::put_object;
use sea_orm::TransactionTrait;

/// Acknowledges one atomic directory/lease batch only after its persistence obligation finishes.
pub(super) trait BatchPersistence: Send + Sync {
    fn apply<'a>(
        &'a self,
        batch: &'a PendingBatch,
    ) -> futures::future::BoxFuture<'a, Result<(), BatchError>>;
}

pub(super) struct StorePersistence(pub(super) StudioStore);
impl BatchPersistence for StorePersistence {
    fn apply<'a>(
        &'a self,
        batch: &'a PendingBatch,
    ) -> futures::future::BoxFuture<'a, Result<(), BatchError>> {
        Box::pin(apply_batch(&self.0, batch))
    }
}

pub(super) async fn apply_batch(
    store: &StudioStore,
    batch: &PendingBatch,
) -> Result<(), BatchError> {
    let tx = store.database().begin().await.map_err(classify_db_error)?;
    for entry in &batch.entries {
        match entry.mutation.as_ref() {
            StudioMutation::Delta(delta) => {
                apply_directory_delta(store, &tx, delta)
                    .await
                    .map_err(classify_store_error)?;
            }
            StudioMutation::WorktreeLease(lease) => {
                put_object(
                    &tx,
                    &lease.owner_thread_id,
                    lease,
                    crate::studio::unix_seconds(),
                )
                .await
                .map_err(classify_store_error)?;
            }
        }
    }
    tx.commit().await.map_err(classify_db_error)?;
    Ok(())
}

fn classify_db_error(error: sea_orm::DbErr) -> BatchError {
    let disposition = db_error_disposition(&error);
    classified_store_error(disposition, store_error(error))
}

fn classify_store_error(error: anyhow::Error) -> BatchError {
    let disposition = error
        .downcast_ref::<sea_orm::DbErr>()
        .map_or(PersistenceDisposition::Blocked, db_error_disposition);
    classified_store_error(disposition, store_error(error))
}

fn classified_store_error(disposition: PersistenceDisposition, error: PureError) -> BatchError {
    match disposition {
        PersistenceDisposition::Retryable => BatchError::RetryableStore(error),
        PersistenceDisposition::Blocked => BatchError::BlockedStore(error),
    }
}

fn db_error_disposition(error: &sea_orm::DbErr) -> PersistenceDisposition {
    use sea_orm::{ConnAcquireErr, DbErr, RuntimeErr, SqlxError};

    match error {
        DbErr::ConnectionAcquire(ConnAcquireErr::Timeout) => PersistenceDisposition::Retryable,
        DbErr::Conn(RuntimeErr::SqlxError(error))
        | DbErr::Exec(RuntimeErr::SqlxError(error))
        | DbErr::Query(RuntimeErr::SqlxError(error)) => match error.as_ref() {
            SqlxError::Database(error) => error
                .code()
                .as_deref()
                .and_then(|code| code.parse::<i32>().ok())
                .map_or(PersistenceDisposition::Blocked, sqlite_code_disposition),
            SqlxError::Io(error)
                if matches!(
                    error.kind(),
                    std::io::ErrorKind::Interrupted
                        | std::io::ErrorKind::WouldBlock
                        | std::io::ErrorKind::TimedOut
                ) =>
            {
                PersistenceDisposition::Retryable
            }
            SqlxError::PoolTimedOut => PersistenceDisposition::Retryable,
            _ => PersistenceDisposition::Blocked,
        },
        _ => PersistenceDisposition::Blocked,
    }
}

fn sqlite_code_disposition(extended_code: i32) -> PersistenceDisposition {
    match extended_code & 0xff {
        // SQLITE_BUSY、SQLITE_LOCKED 与 SQLITE_IOERR 允许自动重试。
        5 | 6 | 10 => PersistenceDisposition::Retryable,
        // 损坏、只读、容量耗尽、结构/约束错误等均需要人工处置。
        _ => PersistenceDisposition::Blocked,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sea_orm::{ConnAcquireErr, DbErr, RuntimeErr};

    #[test]
    fn retry_classification_preserves_typed_sources_through_context() {
        let cases = [
            (
                "pool timeout",
                DbErr::ConnectionAcquire(ConnAcquireErr::Timeout),
                true,
            ),
            (
                "diagnostic text cannot authorize retry",
                DbErr::Exec(RuntimeErr::Internal("database is locked".into())),
                false,
            ),
            (
                "constraint failure",
                DbErr::Custom("constraint violation".into()),
                false,
            ),
        ];
        for (name, source, retryable) in cases {
            let error =
                classify_store_error(anyhow::Error::new(source).context("persist directory"));
            assert_eq!(
                matches!(error, BatchError::RetryableStore(_)),
                retryable,
                "{name}"
            );
        }
    }
}
