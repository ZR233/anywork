//! SQLite's authoritative column metadata at the initial history trust boundary.
//!
//! Call only before opening a transaction: history pools have one connection, and
//! acquiring it from a transaction would wait on that transaction's own lease.

use anyhow::{Context, Result, bail, ensure};
use sea_orm::{DatabaseConnection, DatabaseConnectionType};
use sqlx::sqlite::SqliteConnection;
use std::ffi::{CStr, CString};
use std::ptr;

pub(super) async fn column_collation(
    db: &DatabaseConnection,
    table: &str,
    column: &str,
) -> Result<String> {
    ensure!(
        matches!(
            &db.inner,
            DatabaseConnectionType::SqlxSqlitePoolConnection(_)
        ),
        "history column metadata requires the SQLx SQLite connection"
    );
    let table_name = CString::new(table).context("history table name contains NUL")?;
    let column_name = CString::new(column).context("history column name contains NUL")?;
    let mut connection = db.get_sqlite_connection_pool().acquire().await?;
    let connection: &mut SqliteConnection = &mut connection;
    let mut handle = connection.lock_handle().await?;
    let raw = handle.as_raw_handle().as_ptr();
    let mut collation = ptr::null();

    // SAFETY: SQLx's locked handle excludes its worker for this entire synchronous
    // section and keeps the non-null SQLite connection alive. All input names are
    // live, NUL-terminated C strings; `main` selects only the trusted history schema.
    // The output points to an initialized local pointer, and omitted outputs may be
    // null by SQLite's contract. No pointer escapes or crosses an await. SQLx and
    // libsqlite3-sys are pinned to the same binding identity in the Cargo manifests.
    let status = unsafe {
        libsqlite3_sys::sqlite3_table_column_metadata(
            raw,
            c"main".as_ptr(),
            table_name.as_ptr(),
            column_name.as_ptr(),
            ptr::null_mut(),
            &mut collation,
            ptr::null_mut(),
            ptr::null_mut(),
            ptr::null_mut(),
        )
    };
    if status != libsqlite3_sys::SQLITE_OK {
        // SAFETY: `raw` is still locked and alive. SQLite always returns a valid
        // NUL-terminated error string; copy it before any further SQLite API call
        // or before releasing the handle that owns it.
        let message = unsafe { CStr::from_ptr(libsqlite3_sys::sqlite3_errmsg(raw)) }
            .to_string_lossy()
            .into_owned();
        bail!("history column metadata failed for {table}.{column}: SQLite {status}: {message}");
    }
    ensure!(
        !collation.is_null(),
        "history column metadata omitted collation for {table}.{column}"
    );
    // SAFETY: SQLITE_OK with a non-null collation output supplies a NUL-terminated
    // string borrowed from this locked connection. Copy before the next SQLite API
    // call, including any call made by dropping/releasing the connection.
    let collation = unsafe { CStr::from_ptr(collation) }
        .to_str()
        .context("history column collation is not UTF-8")?
        .to_owned();
    Ok(collation)
}
