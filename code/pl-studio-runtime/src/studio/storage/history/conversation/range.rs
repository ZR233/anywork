//! SQLx owns the connection, transaction and worker exclusion. Native BLOB handles never escape
//! the blocking owner; cancellation of the waiter does not drop a handle still in use.

use super::*;
use pl_core::chat::{ChatError, ContentBytes, ContentReadRequest, ContentRef, ContentWindow};
use sea_orm::{DatabaseConnection, DatabaseConnectionType};
use sqlx::Row;
use std::{ffi::CStr, ptr};

pub(in super::super) async fn read_content(
    db: &DatabaseConnection,
    request: &ContentReadRequest,
) -> Result<ContentWindow> {
    ensure!(
        (1..=pl_core::chat::MAX_READ_BYTES).contains(&request.max_bytes),
        ChatError::InvalidDemand("invalid content range size".into())
    );
    integer(request.offset)?;
    ensure!(
        matches!(
            &db.inner,
            DatabaseConnectionType::SqlxSqlitePoolConnection(_)
        ),
        "content ranges require the SQLx SQLite connection"
    );
    match &request.reference {
        ContentRef::ItemPayload(id) => {
            let mut connection = db.get_sqlite_connection_pool().acquire().await?;
            let request = request.clone();
            let id = id.clone();
            let runtime = tokio::runtime::Handle::current();
            tokio::task::spawn_blocking(move || runtime.block_on(async move {
                use sqlx::Acquire;
                let mut tx = connection.begin().await?;
                let row = sqlx::query(
                    "SELECT seq,length(payload) AS byte_length FROM conversation_items WHERE item_id=?")
                    .bind(&id).fetch_optional(&mut *tx).await?
                    .ok_or_else(|| ChatError::NotFound(id.clone()))?;
                let rowid: i64 = row.try_get("seq")?;
                let len = u64::try_from(row.try_get::<i64, _>("byte_length")?)?;
                validate_range(&request, len, 0)?;
                let size = (len - request.offset).min(request.max_bytes as u64) as usize;
                let mut handle = tx.lock_handle().await?;
                let raw = handle.as_raw_handle().as_ptr();
                let bytes = read_blob(raw, rowid, request.offset, size)?;
                drop(handle);
                let result = ContentWindow { offset: request.offset, bytes: ContentBytes::from(Arc::from(bytes)),
                    generation: 0, available_through: len, sealed: true };
                tx.commit().await?;
                Ok(result)
            })).await.context("content range blocking owner failed")?
        }
        ContentRef::Body(key) => {
            // SQLx already owns the SQLite worker. Only native BLOB access
            // needs the independent blocking owner above.
            let mut tx = db.get_sqlite_connection_pool().begin().await?;
            let is_current = super::content::current_owner(&key.owner)?.is_some();
            ChatKey::from_encoded(key.owner.as_str().to_owned())?;
            let payload: Option<Vec<u8>> = sqlx::query_scalar(
                "SELECT payload FROM conversation_contents WHERE owner_key=? AND content_key=?",
            )
            .bind(key.owner.as_str())
            .bind(&key.key)
            .fetch_optional(&mut *tx)
            .await?;
            let payload = payload.ok_or_else(|| {
                if is_current {
                    ChatError::StaleContent
                } else {
                    ChatError::NotFound(key.key.clone())
                }
            })?;
            let manifest = super::content::manifest(&payload)?;
            ensure!(manifest.sealed, ChatError::StaleContent);
            validate_range(request, manifest.byte_length, manifest.generation)?;
            let end = request.offset
                + (manifest.byte_length - request.offset).min(request.max_bytes as u64);
            let mut offset = request.offset;
            let mut bytes = Vec::with_capacity((end - offset) as usize);
            let mut first = true;
            while offset < end {
                // Locate the one boundary chunk using the offset index, then only exact
                // successors. SQLite substr() returns the requested region, not whole chunks.
                let sql = if first {
                    "SELECT byte_offset,length(data) AS chunk_length,
                                substr(data,?-byte_offset+1,?) AS bytes
                         FROM conversation_content_chunks
                         WHERE owner_key=? AND content_key=? AND byte_offset<=?
                         ORDER BY byte_offset DESC LIMIT 1"
                } else {
                    "SELECT byte_offset,length(data) AS chunk_length,
                                substr(data,?-byte_offset+1,?) AS bytes
                         FROM conversation_content_chunks
                         WHERE owner_key=? AND content_key=? AND byte_offset=?"
                };
                let row = sqlx::query(sql)
                    .bind(integer(offset)?)
                    .bind(integer(end - offset)?)
                    .bind(key.owner.as_str())
                    .bind(&key.key)
                    .bind(integer(offset)?)
                    .fetch_optional(&mut *tx)
                    .await?
                    .context("content has a missing chunk")?;
                let start = u64::try_from(row.try_get::<i64, _>("byte_offset")?)?;
                let length = u64::try_from(row.try_get::<i64, _>("chunk_length")?)?;
                ensure!(
                    length > 0
                        && length <= super::content::CHUNK_BYTES as u64
                        && start <= offset
                        && start.checked_add(length).is_some_and(|end| end > offset),
                    "content chunk gap, overlap or invalid size"
                );
                let chunk_end = start
                    .checked_add(length)
                    .context("content chunk overflow")?;
                ensure!(
                    chunk_end <= manifest.byte_length,
                    "content chunk exceeds manifest"
                );
                let part: Vec<u8> = row.try_get("bytes")?;
                ensure!(
                    part.len() as u64 == (chunk_end.min(end) - offset),
                    "content range is incomplete"
                );
                offset += part.len() as u64;
                bytes.extend_from_slice(&part);
                first = false;
            }
            let result = ContentWindow {
                offset: request.offset,
                bytes: ContentBytes::from(Arc::from(bytes)),
                generation: manifest.generation,
                available_through: manifest.byte_length,
                sealed: manifest.sealed,
            };
            tx.commit().await?;
            Ok(result)
        }
    }
}

fn validate_range(request: &ContentReadRequest, len: u64, generation: u64) -> Result<()> {
    ensure!(
        request.offset <= len,
        ChatError::InvalidArgument("content offset exceeds length".into())
    );
    ensure!(
        request
            .generation
            .is_none_or(|expected| expected == generation),
        ChatError::StaleContent
    );
    Ok(())
}

struct Blob(*mut libsqlite3_sys::sqlite3_blob);

impl Drop for Blob {
    fn drop(&mut self) {
        // SAFETY: created by sqlite3_blob_open on this blocking owner, never shared or moved to
        // another thread; the locked SQLx connection outlives this guard on every return/unwind.
        unsafe {
            libsqlite3_sys::sqlite3_blob_close(self.0);
        }
    }
}

fn sqlite_error(raw: *mut libsqlite3_sys::sqlite3, code: i32) -> anyhow::Error {
    // SAFETY: caller retains SQLx's exclusive locked, live connection; SQLite owns this
    // NUL-terminated string and it is copied before the next SQLite call.
    let message = unsafe { CStr::from_ptr(libsqlite3_sys::sqlite3_errmsg(raw)) }
        .to_string_lossy()
        .into_owned();
    anyhow::anyhow!("SQLite content BLOB error {code}: {message}")
}

fn read_blob(
    raw: *mut libsqlite3_sys::sqlite3,
    rowid: i64,
    offset: u64,
    size: usize,
) -> Result<Vec<u8>> {
    let offset = i32::try_from(offset).context("SQLite BLOB offset exceeds native range")?;
    let length = i32::try_from(size).context("SQLite BLOB window exceeds native range")?;
    let mut blob = ptr::null_mut();
    // SAFETY: raw comes from SQLx lock_handle in the calling blocking owner. No worker can
    // access it until read_blob returns. Names are static NUL-terminated strings, rowid was
    // selected in the same transaction, output points to initialized local storage, flags=0
    // requests read-only. This function has no await and no pointer escapes.
    let code = unsafe {
        libsqlite3_sys::sqlite3_blob_open(
            raw,
            c"main".as_ptr(),
            c"conversation_items".as_ptr(),
            c"payload".as_ptr(),
            rowid,
            0,
            &mut blob,
        )
    };
    if code != libsqlite3_sys::SQLITE_OK {
        return Err(sqlite_error(raw, code));
    }
    ensure!(!blob.is_null(), "SQLite returned a null BLOB handle");
    let blob = Blob(blob);
    // SAFETY: blob is live and owned exclusively by this stack; this call does not mutate it.
    let available = unsafe { libsqlite3_sys::sqlite3_blob_bytes(blob.0) };
    ensure!(
        offset
            .checked_add(length)
            .is_some_and(|end| end <= available),
        "SQLite BLOB range differs from the selected length"
    );
    let mut bytes = vec![0u8; size];
    if length > 0 {
        // SAFETY: bytes has length writable initialized bytes, and the checked range is inside
        // this live BLOB. Buffer and BLOB cannot alias. Drop closes the BLOB before SQLx unlock.
        let code = unsafe {
            libsqlite3_sys::sqlite3_blob_read(blob.0, bytes.as_mut_ptr().cast(), length, offset)
        };
        if code != libsqlite3_sys::SQLITE_OK {
            return Err(sqlite_error(raw, code));
        }
    }
    // Observe close errors rather than presenting incomplete IO as successful EOF.
    let raw_blob = blob.0;
    std::mem::forget(blob);
    // SAFETY: ownership was just transferred out of the guard, and this is its sole close.
    let code = unsafe { libsqlite3_sys::sqlite3_blob_close(raw_blob) };
    if code != libsqlite3_sys::SQLITE_OK {
        return Err(sqlite_error(raw, code));
    }
    Ok(bytes)
}
