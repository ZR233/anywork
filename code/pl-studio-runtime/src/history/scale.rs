//! Schema 26 scale evidence for indexed event pages.
//!
//! The probe attaches to every physical reader connection and reuses the production
//! `HistoryReader::events_page` query. It does not issue a parallel page implementation.

use std::{
    ffi::{CStr, c_char, c_int, c_uint, c_void},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering::Relaxed},
    },
};

use anyhow::{Context, Result, bail, ensure};
use sea_orm::{ConnectionTrait, DatabaseConnection, TransactionTrait, Value, sqlx};

use super::{
    HistoryDemand, HistoryEventsQuery, HistoryLimits, HistoryStore, db::statement, schema,
};

const THREAD: &str = "scale-history";
const PAGE_ROWS: u32 = 20;
const SENTINEL: &[u8] = b"SCALEBODY_PAYLOAD";
const INSERT_CHUNK: i64 = 500;

struct ProbeState {
    page_rows: AtomicU64,
    page_statements: AtomicU64,
    page_vm_steps: AtomicU64,
    page_fullscan_steps: AtomicU64,
    other_statements: AtomicU64,
    denied_reads: AtomicU64,
    invalid_counter: AtomicBool,
    budget_exceeded: AtomicBool,
    trace_removed: AtomicU64,
    authorizer_removed: AtomicU64,
    installed: AtomicU64,
    unexpected_len: AtomicU64,
    unexpected_claimed: AtomicBool,
    unexpected: [AtomicU8; 240],
}

impl ProbeState {
    fn new() -> Self {
        Self {
            page_rows: AtomicU64::new(0),
            page_statements: AtomicU64::new(0),
            page_vm_steps: AtomicU64::new(0),
            page_fullscan_steps: AtomicU64::new(0),
            other_statements: AtomicU64::new(0),
            denied_reads: AtomicU64::new(0),
            invalid_counter: AtomicBool::new(false),
            budget_exceeded: AtomicBool::new(false),
            trace_removed: AtomicU64::new(0),
            authorizer_removed: AtomicU64::new(0),
            installed: AtomicU64::new(0),
            unexpected_len: AtomicU64::new(0),
            unexpected_claimed: AtomicBool::new(false),
            unexpected: [const { AtomicU8::new(0) }; 240],
        }
    }

    fn reset_counters(&self) {
        self.page_rows.store(0, Relaxed);
        self.page_statements.store(0, Relaxed);
        self.page_vm_steps.store(0, Relaxed);
        self.page_fullscan_steps.store(0, Relaxed);
        self.other_statements.store(0, Relaxed);
        self.denied_reads.store(0, Relaxed);
        self.invalid_counter.store(false, Relaxed);
        self.budget_exceeded.store(false, Relaxed);
        self.unexpected_len.store(0, Relaxed);
        self.unexpected_claimed.store(false, Relaxed);
    }
}

struct Registration {
    handle_address: usize,
    state: Arc<ProbeState>,
}

impl Registration {
    fn interrupt_at_budget(&self) -> bool {
        self.state.budget_exceeded.store(true, Relaxed);
        false
    }
}

impl Drop for Registration {
    fn drop(&mut self) {
        // SAFETY: handle_address is the exposed address taken from LockedSqliteHandle while that
        // worker was exclusively locked. SQLx drops this progress-handler closure only after that
        // same handle is exclusive again and no native callback is in flight. No Rust reference is
        // formed from the address. Both unregister calls return before the context Arc is released,
        // and neither call executes SQL.
        let (trace, authorizer) = unsafe {
            let handle = self.handle_address as *mut libsqlite3_sys::sqlite3;
            (
                libsqlite3_sys::sqlite3_trace_v2(handle, 0, None, std::ptr::null_mut()),
                libsqlite3_sys::sqlite3_set_authorizer(handle, None, std::ptr::null_mut()),
            )
        };
        if trace == libsqlite3_sys::SQLITE_OK {
            self.state.trace_removed.fetch_add(1, Relaxed);
        }
        if authorizer == libsqlite3_sys::SQLITE_OK {
            self.state.authorizer_removed.fetch_add(1, Relaxed);
        }
    }
}

struct Probe {
    state: Arc<ProbeState>,
    connections: u32,
}

#[derive(Debug)]
struct Work {
    page_rows: u64,
    page_statements: u64,
    page_vm_steps: u64,
    page_fullscan_steps: u64,
    other_statements: u64,
    denied_reads: u64,
    unexpected_sql: String,
}

impl Probe {
    async fn install(db: &DatabaseConnection) -> Result<Self> {
        let pool = db.get_sqlite_connection_pool();
        let connections = pool.options().get_max_connections();
        ensure!(connections > 0, "history reader pool has no connections");
        let state = Arc::new(ProbeState::new());
        let mut held = Vec::with_capacity(connections as usize);
        for _ in 0..connections {
            let mut connection = pool.acquire().await.context("acquire reader connection")?;
            let mut handle = connection
                .lock_handle()
                .await
                .context("lock reader connection")?;
            install_locked(&mut handle, &state)?;
            state.installed.fetch_add(1, Relaxed);
            drop(handle);
            held.push(connection);
        }
        deny_probe(&mut held[0], &state).await?;
        state.reset_counters();
        drop(held);
        Ok(Self { state, connections })
    }

    async fn finish(self, db: &DatabaseConnection) -> Result<Work> {
        let pool = db.get_sqlite_connection_pool();
        let mut held = Vec::with_capacity(self.connections as usize);
        for _ in 0..self.connections {
            let mut connection = pool
                .acquire()
                .await
                .context("reacquire probed connection")?;
            let mut handle = connection
                .lock_handle()
                .await
                .context("lock probed connection")?;
            handle.remove_progress_handler();
            drop(handle);
            held.push(connection);
        }
        drop(held);
        let installed = self.state.installed.load(Relaxed);
        ensure!(
            self.state.trace_removed.load(Relaxed) == installed
                && self.state.authorizer_removed.load(Relaxed) == installed,
            "native callbacks were not unregistered on every reader connection"
        );
        ensure!(
            Arc::strong_count(&self.state) == 1,
            "native callback context is still retained"
        );
        ensure!(
            !self.state.budget_exceeded.load(Relaxed),
            "statement exceeded the VM counter safety budget"
        );
        ensure!(
            !self.state.invalid_counter.load(Relaxed),
            "invalid SQLite statement counter"
        );
        let unexpected_len = self.state.unexpected_len.load(Relaxed) as usize;
        let unexpected_sql = self.state.unexpected[..unexpected_len]
            .iter()
            .map(|byte| byte.load(Relaxed) as char)
            .collect();
        Ok(Work {
            page_rows: self.state.page_rows.load(Relaxed),
            page_statements: self.state.page_statements.load(Relaxed),
            page_vm_steps: self.state.page_vm_steps.load(Relaxed),
            page_fullscan_steps: self.state.page_fullscan_steps.load(Relaxed),
            other_statements: self.state.other_statements.load(Relaxed),
            denied_reads: self.state.denied_reads.load(Relaxed),
            unexpected_sql,
        })
    }
}

fn install_locked(
    handle: &mut sqlx::sqlite::LockedSqliteHandle<'_>,
    state: &Arc<ProbeState>,
) -> Result<()> {
    let raw = handle.as_raw_handle().as_ptr();
    // SAFETY: SQLx owns raw and every statement returned by sqlite3_next_stmt. LockedSqliteHandle
    // excludes the worker and all native calls for this check and the registration below. The
    // borrowed pointers never escape the lock; counters are only reset, never SQLx statement state.
    unsafe {
        let mut stmt = libsqlite3_sys::sqlite3_next_stmt(raw, std::ptr::null_mut());
        while !stmt.is_null() {
            ensure!(
                libsqlite3_sys::sqlite3_stmt_busy(stmt) == 0,
                "cannot install SQLite probe while a statement is busy"
            );
            stmt = libsqlite3_sys::sqlite3_next_stmt(raw, stmt);
        }
        let mut stmt = libsqlite3_sys::sqlite3_next_stmt(raw, std::ptr::null_mut());
        while !stmt.is_null() {
            libsqlite3_sys::sqlite3_stmt_status(stmt, libsqlite3_sys::SQLITE_STMTSTATUS_VM_STEP, 1);
            libsqlite3_sys::sqlite3_stmt_status(
                stmt,
                libsqlite3_sys::SQLITE_STMTSTATUS_FULLSCAN_STEP,
                1,
            );
            stmt = libsqlite3_sys::sqlite3_next_stmt(raw, stmt);
        }
    }
    let registration = Registration {
        handle_address: raw as usize,
        state: Arc::clone(state),
    };
    handle.set_progress_handler(1_000_000, move || registration.interrupt_at_budget());
    // SAFETY: raw is protected by LockedSqliteHandle. Arc::as_ptr is aligned and stable for the
    // State allocation. The progress handler retains that Arc until it unregisters both callbacks.
    // Callbacks touch only atomics. This private fixture has no previous trace or authorizer.
    let (trace, authorizer) = unsafe {
        let context = Arc::as_ptr(state).cast_mut().cast::<c_void>();
        (
            libsqlite3_sys::sqlite3_trace_v2(
                raw,
                (libsqlite3_sys::SQLITE_TRACE_PROFILE | libsqlite3_sys::SQLITE_TRACE_ROW) as c_uint,
                Some(trace_callback),
                context,
            ),
            libsqlite3_sys::sqlite3_set_authorizer(raw, Some(authorize), context),
        )
    };
    if trace != libsqlite3_sys::SQLITE_OK || authorizer != libsqlite3_sys::SQLITE_OK {
        handle.remove_progress_handler();
        bail!("native sampling registration failed: {trace}/{authorizer}");
    }
    Ok(())
}

async fn deny_probe(
    connection: &mut sqlx::pool::PoolConnection<sqlx::Sqlite>,
    state: &ProbeState,
) -> Result<()> {
    let mut handle = connection.lock_handle().await.context("lock deny probe")?;
    for sql in [
        c"SELECT 1 FROM history_bodies LIMIT 1",
        c"SELECT 1 FROM history_body_chunks LIMIT 1",
    ] {
        let before = state.denied_reads.load(Relaxed);
        let stepped = prepare_and_step(&mut handle, sql.as_ptr())?;
        ensure!(
            stepped == libsqlite3_sys::SQLITE_AUTH
                && state.denied_reads.load(Relaxed) == before + 1,
            "body authorizer probe was not denied: step={stepped}"
        );
    }
    Ok(())
}

fn prepare_and_step(
    handle: &mut sqlx::sqlite::LockedSqliteHandle<'_>,
    sql: *const c_char,
) -> Result<c_int> {
    fn sqlite_message(handle: &mut sqlx::sqlite::LockedSqliteHandle<'_>) -> String {
        // SAFETY: the handle is exclusively locked. sqlite3_errmsg stays valid until the next
        // SQLite call on this connection, and the text is copied before return.
        unsafe {
            let message = libsqlite3_sys::sqlite3_errmsg(handle.as_raw_handle().as_ptr());
            if message.is_null() {
                return String::new();
            }
            CStr::from_ptr(message).to_string_lossy().into_owned()
        }
    }

    struct Statement(*mut libsqlite3_sys::sqlite3_stmt);
    impl Drop for Statement {
        fn drop(&mut self) {
            if !self.0.is_null() {
                // SAFETY: this test owns the statement, created under the exclusive handle, and
                // finalizes it before that lock is released on every return path.
                unsafe {
                    libsqlite3_sys::sqlite3_finalize(self.0);
                }
            }
        }
    }
    let mut stmt = Statement(std::ptr::null_mut());
    // SAFETY: the connection is live and exclusively locked, sql is a NUL-terminated literal, and
    // stmt is an output slot owned by the guard above until finalization.
    let prepared = unsafe {
        libsqlite3_sys::sqlite3_prepare_v2(
            handle.as_raw_handle().as_ptr(),
            sql,
            -1,
            &mut stmt.0,
            std::ptr::null_mut(),
        )
    };
    if prepared == libsqlite3_sys::SQLITE_AUTH {
        return Ok(prepared);
    }
    ensure!(
        prepared == libsqlite3_sys::SQLITE_OK,
        "body deny probe failed to prepare: {prepared} {}",
        sqlite_message(handle)
    );
    // SAFETY: stmt is the prepared statement owned by the guard, still under the same exclusive lock.
    // The authorizer runs synchronously on this thread and only updates atomics.
    Ok(unsafe { libsqlite3_sys::sqlite3_step(stmt.0) })
}

fn contains(sql: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && sql.windows(needle.len()).any(|window| window == needle)
}

fn is_page_select(sql: &[u8]) -> bool {
    let sql = sql.trim_ascii();
    let is_events_page = contains(sql, b"FROM history_events")
        && contains(sql, b"seq>?")
        && contains(sql, b"seq<=?")
        && contains(sql, b"ORDER BY seq DESC LIMIT")
        && !contains(sql, b"history_bodies")
        && !contains(sql, b"history_body_chunks");
    let is_timeline_direct = contains(sql, b"FROM history_events d")
        && contains(sql, b"WHERE d.timeline_role=2 AND d.seq<=?")
        && contains(sql, b"AS has_folded_after")
        && !contains(sql, b"history_bodies")
        && !contains(sql, b"history_body_chunks");
    is_events_page || is_timeline_direct
}

fn starts_with_ignore_ascii_case(sql: &[u8], prefix: &[u8]) -> bool {
    sql.len() >= prefix.len()
        && sql
            .iter()
            .zip(prefix)
            .all(|(byte, expected)| byte.to_ascii_uppercase() == *expected)
}

fn is_bookkeeping(sql: &[u8]) -> bool {
    let sql = sql.trim_ascii();
    starts_with_ignore_ascii_case(sql, b"BEGIN")
        || starts_with_ignore_ascii_case(sql, b"COMMIT")
        || starts_with_ignore_ascii_case(sql, b"ROLLBACK")
        || starts_with_ignore_ascii_case(sql, b"SAVEPOINT")
        || starts_with_ignore_ascii_case(sql, b"RELEASE")
}

fn note_unexpected(state: &ProbeState, sql: &[u8]) {
    if state
        .unexpected_claimed
        .compare_exchange(false, true, Relaxed, Relaxed)
        .is_err()
    {
        return;
    }
    let length = sql.len().min(state.unexpected.len());
    for (index, byte) in sql.iter().take(length).enumerate() {
        state.unexpected[index].store(*byte, Relaxed);
    }
    state.unexpected_len.store(length as u64, Relaxed);
}

unsafe extern "C" fn trace_callback(
    event: c_uint,
    context: *mut c_void,
    statement: *mut c_void,
    _: *mut c_void,
) -> c_int {
    if context.is_null() || statement.is_null() {
        return 0;
    }
    // SAFETY: each registration owns the State Arc until its native callbacks are removed. SQLite
    // passes its live sqlite3_stmt for PROFILE/ROW synchronously on the exclusive worker thread.
    // sqlite3_sql's NUL-terminated bytes remain valid for this call and are never retained.
    let (state, stmt, sql) = unsafe {
        let state = &*context.cast::<ProbeState>();
        let stmt = statement.cast::<libsqlite3_sys::sqlite3_stmt>();
        let sql = libsqlite3_sys::sqlite3_sql(stmt);
        if sql.is_null() {
            // SQLite can emit row traces without SQL text while loading its schema.
            // SQLx-prepared page queries retain their text, as do SQLite profile traces.
            if event != libsqlite3_sys::SQLITE_TRACE_ROW as c_uint {
                state.invalid_counter.store(true, Relaxed);
            }
            return 0;
        }
        (state, stmt, CStr::from_ptr(sql).to_bytes())
    };
    if is_bookkeeping(sql) {
        return 0;
    }
    let page = is_page_select(sql);
    if event == libsqlite3_sys::SQLITE_TRACE_ROW as c_uint {
        if page {
            state.page_rows.fetch_add(1, Relaxed);
        }
    } else if event == libsqlite3_sys::SQLITE_TRACE_PROFILE as c_uint {
        // SAFETY: this is the same live statement, at completion, under SQLite's worker exclusivity.
        // Reset=1 isolates this execution from later samples of a cached statement.
        let (vm, fullscan) = unsafe {
            (
                libsqlite3_sys::sqlite3_stmt_status(
                    stmt,
                    libsqlite3_sys::SQLITE_STMTSTATUS_VM_STEP,
                    1,
                ),
                libsqlite3_sys::sqlite3_stmt_status(
                    stmt,
                    libsqlite3_sys::SQLITE_STMTSTATUS_FULLSCAN_STEP,
                    1,
                ),
            )
        };
        if vm < 0 || fullscan < 0 {
            state.invalid_counter.store(true, Relaxed);
            return 0;
        }
        if page {
            state.page_statements.fetch_add(1, Relaxed);
            state.page_vm_steps.fetch_add(vm as u64, Relaxed);
            state
                .page_fullscan_steps
                .fetch_add(fullscan as u64, Relaxed);
        } else {
            state.other_statements.fetch_add(1, Relaxed);
            note_unexpected(state, sql);
        }
    }
    0
}

unsafe extern "C" fn authorize(
    context: *mut c_void,
    action: c_int,
    table: *const c_char,
    _column: *const c_char,
    _: *const c_char,
    _: *const c_char,
) -> c_int {
    if action != libsqlite3_sys::SQLITE_READ || context.is_null() || table.is_null() {
        return libsqlite3_sys::SQLITE_OK;
    }
    // SAFETY: SQLite supplies live NUL-terminated action arguments for this synchronous callback.
    // The context has the same registration-owned Arc lifetime as the trace callback.
    let (state, table) = unsafe {
        (
            &*context.cast::<ProbeState>(),
            CStr::from_ptr(table).to_bytes(),
        )
    };
    if table == b"history_bodies" || table == b"history_body_chunks" {
        state.denied_reads.fetch_add(1, Relaxed);
        return libsqlite3_sys::SQLITE_DENY;
    }
    libsqlite3_sys::SQLITE_OK
}

async fn seed(path: &std::path::Path, target: i64) -> Result<()> {
    let db = schema::connect(path, false, false).await?;
    let current = db
        .query_one_raw(statement(
            "SELECT COALESCE(MAX(seq),0) AS seq FROM history_events",
            vec![],
        ))
        .await?
        .context("history seed head missing")?
        .try_get::<i64>("", "seq")?;
    let tx = db.begin().await?;
    let mut start = current + 1;
    while start <= target {
        let end = (start + INSERT_CHUNK - 1).min(target);
        insert_range(&tx, start, end).await?;
        start = end + 1;
    }
    tx.commit().await?;
    db.close().await?;
    Ok(())
}

async fn insert_range(db: &impl ConnectionTrait, start: i64, end: i64) -> Result<()> {
    db.execute_raw(statement(
        "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
         INSERT INTO history_events(
            seq,event_id,kind,timeline_role,occurred_at,recorded_at,is_anchor,payload_schema,payload_json
         )
         SELECT i,'scale-'||i,
                CASE WHEN i % 100 = 0 THEN 'text_completed' ELSE 'item_recorded' END,
                CASE WHEN i % 100 = 0 THEN 2 ELSE 1 END,
                i,i,0,'scale.v1','{\"ref\":\"body\"}'
         FROM n",
        vec![start.into(), end.into()],
    ))
    .await?;
    db.execute_raw(statement(
        "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
         INSERT INTO history_bodies(
            body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest
         )
         SELECT 'body-'||i,'scale-'||i,0,'body','body',?,NULL,? FROM n",
        vec![
            start.into(),
            end.into(),
            i64::try_from(SENTINEL.len())?.into(),
            Value::Bytes(Some(vec![0; 32])),
        ],
    ))
    .await?;
    db.execute_raw(statement(
        "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
         INSERT INTO history_body_chunks(body_id,chunk_no,data)
         SELECT 'body-'||i,0,? FROM n",
        vec![
            start.into(),
            end.into(),
            Value::Bytes(Some(SENTINEL.to_vec())),
        ],
    ))
    .await?;
    Ok(())
}

async fn assert_index_plan(path: &std::path::Path) -> Result<()> {
    let db = schema::connect(path, true, false).await?;
    let rows = db
        .query_all_raw(statement(
            "EXPLAIN QUERY PLAN SELECT seq FROM history_events WHERE 1=1 AND seq>? AND seq<=? ORDER BY seq DESC LIMIT ?",
            vec![0i64.into(), 1i64.into(), 21i64.into()],
        ))
        .await?;
    let plan = rows
        .iter()
        .map(|row| row.try_get::<String>("", "detail"))
        .collect::<std::result::Result<Vec<_>, _>>()?
        .join("\n");
    ensure!(
        plan.contains("SEARCH") && plan.contains("history_events") && !plan.contains("SCAN"),
        "event page does not use an index seek: {plan}"
    );
    ensure!(
        !plan.contains("history_bodies") && !plan.contains("history_body_chunks"),
        "event page plan touches body storage: {plan}"
    );
    db.close().await?;
    Ok(())
}

async fn verify_indexed_event_pages(sizes: &[u64]) -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    {
        let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
        store.close().await?;
    }
    let mut baseline = None;
    for &size in sizes {
        seed(&path, i64::try_from(size)?).await?;
        let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
        let probe = Probe::install(&store.inner.reader).await?;
        let page = store
            .reader()
            .events_page(
                HistoryEventsQuery::AllEvents,
                None,
                None,
                HistoryDemand {
                    max_rows: PAGE_ROWS,
                    max_bytes: 256 * 1024,
                },
            )
            .await;
        let work = probe.finish(&store.inner.reader).await?;
        let page = page.context("history event page failed while body reads were denied")?;
        let expected_entries = PAGE_ROWS as u64;
        let expected_rows = expected_entries + u64::from(size > expected_entries);
        assert_eq!(page.entries.len() as u64, expected_entries, "{work:?}");
        assert_eq!(work.page_rows, expected_rows, "{work:?}");
        assert_eq!(work.page_statements, 1, "{work:?}");
        assert_eq!(
            work.other_statements, 0,
            "unexpected SQL: {}",
            work.unexpected_sql
        );
        assert_eq!(work.denied_reads, 0, "{work:?}");
        assert_eq!(work.page_fullscan_steps, 0, "{work:?}");
        assert!(work.page_vm_steps > 0, "{work:?}");
        assert_eq!(page.entries[0].seq, size);
        assert!(
            page.entries
                .windows(2)
                .all(|pair| pair[0].seq == pair[1].seq + 1),
            "event page is not a descending index page"
        );
        assert!(
            page.entries.iter().all(|entry| {
                entry.payload_json == "{\"ref\":\"body\"}"
                    && !entry
                        .payload_json
                        .as_bytes()
                        .windows(SENTINEL.len())
                        .any(|window| window == SENTINEL)
            }),
            "event page included body bytes"
        );
        assert_eq!(page.next.is_some(), size > expected_entries);
        if let Some(steps) = baseline {
            assert!(
                work.page_vm_steps <= steps + 64,
                "index seek cost grew with table size: baseline={steps} now={} size={size}",
                work.page_vm_steps
            );
        } else {
            baseline = Some(work.page_vm_steps);
        }
        eprintln!(
            "Schema26 size={size} page_rows={} statements={} vm_steps={} fullscan=0 denied_body_reads=0",
            work.page_rows, work.page_statements, work.page_vm_steps
        );
        store.close().await?;
    }
    let db = schema::connect(&path, true, false).await?;
    let chunk = db
        .query_one_raw(statement(
            "SELECT data FROM history_body_chunks WHERE body_id='body-1'",
            vec![],
        ))
        .await?
        .context("seeded body chunk missing")?;
    let bytes: Vec<u8> = chunk.try_get("", "data")?;
    assert_eq!(
        bytes, SENTINEL,
        "scale fixture did not retain a separate body"
    );
    db.close().await?;
    assert_index_plan(&path).await?;
    Ok(())
}

#[tokio::test]
async fn bounded_event_pages_use_index_seeks_without_loading_bodies() -> Result<()> {
    verify_indexed_event_pages(&[20, 100]).await
}

#[tokio::test]
#[ignore = "full event scale coverage runs in Rust Scale Checks"]
async fn hundred_thousand_events_use_index_seeks_without_loading_bodies() -> Result<()> {
    verify_indexed_event_pages(&[20, 100, 10_000, 100_000]).await
}

async fn assert_timeline_index_plans(path: &std::path::Path) -> Result<()> {
    let db = schema::connect(path, true, false).await?;
    let plan_rows = db
        .query_all_raw(statement(
            &format!("EXPLAIN QUERY PLAN {}", super::db::direct_timeline_sql()),
            vec![
                10_000i64.into(),
                10_000i64.into(),
                1i64.into(),
                10_000i64.into(),
                10_000i64.into(),
                10_000i64.into(),
                21i64.into(),
            ],
        ))
        .await?;
    let plan = plan_rows
        .iter()
        .map(|row| row.try_get::<String>("", "detail"))
        .collect::<std::result::Result<Vec<_>, _>>()?
        .join("\n");
    ensure!(
        plan.contains("idx_events_boundaries")
            && plan.contains("idx_events_work")
            && !plan.contains("SCAN")
            && !plan.contains("history_bodies"),
        "direct timeline 1-SQL query does not use covering indexes without SCAN: {plan}"
    );
    db.close().await?;
    Ok(())
}

async fn verify_indexed_timeline_pages(sizes: &[u64]) -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    {
        let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
        store.close().await?;
    }
    let mut baseline = None;
    for &size in sizes {
        seed(&path, i64::try_from(size)?).await?;
        let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
        let probe = Probe::install(&store.inner.reader).await?;
        let page = store
            .reader()
            .timeline_page(
                None,
                None,
                HistoryDemand {
                    max_rows: PAGE_ROWS,
                    max_bytes: 256 * 1024,
                },
            )
            .await;
        let work = probe.finish(&store.inner.reader).await?;
        let page = page.context("timeline page failed while body reads were denied")?;
        assert!(!page.entries.is_empty(), "{work:?}");
        assert_eq!(
            work.page_statements, 1,
            "expected exactly 1 SQL statement for timeline_page, got {}: {work:?}",
            work.page_statements
        );
        assert_eq!(
            work.other_statements, 0,
            "unexpected SQL: {}",
            work.unexpected_sql
        );
        assert_eq!(work.denied_reads, 0, "{work:?}");
        assert_eq!(work.page_fullscan_steps, 0, "{work:?}");
        assert!(work.page_vm_steps > 0, "{work:?}");
        if let Some(steps) = baseline {
            assert!(
                work.page_vm_steps <= steps + 256,
                "timeline_page seek cost grew with table size: baseline={steps} now={} size={size}",
                work.page_vm_steps
            );
        } else {
            baseline = Some(work.page_vm_steps);
        }
        eprintln!(
            "Schema27 timeline size={size} statements={} vm_steps={} fullscan={} denied_body_reads=0",
            work.page_statements, work.page_vm_steps, work.page_fullscan_steps
        );
        store.close().await?;
    }
    assert_timeline_index_plans(&path).await?;
    Ok(())
}

#[tokio::test]
async fn bounded_timeline_pages_use_covering_indexes_without_loading_bodies() -> Result<()> {
    verify_indexed_timeline_pages(&[3_000, 10_000]).await
}

#[tokio::test]
#[ignore = "full event scale coverage runs in Rust Scale Checks"]
async fn hundred_thousand_timeline_pages_use_covering_indexes_without_loading_bodies() -> Result<()>
{
    verify_indexed_timeline_pages(&[3_000, 10_000, 100_000]).await
}
