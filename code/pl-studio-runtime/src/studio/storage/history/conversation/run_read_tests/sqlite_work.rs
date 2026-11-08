//! Test-only observations of the SQLx connection used by the real production page.
//! No alternate SQL implementation or database is involved.
use super::*;
use std::{
    ffi::{CStr, c_char, c_int, c_uint, c_void},
    sync::{
        Weak,
        atomic::{AtomicBool, AtomicU64, Ordering::Relaxed},
    },
};

#[derive(Default)]
struct State {
    candidates: AtomicU64,
    reference_rows: AtomicU64,
    statements: AtomicU64,
    vm_steps: AtomicU64,
    head_vm_steps: AtomicU64,
    fullscan_steps: AtomicU64,
    head_fullscan_steps: AtomicU64,
    payload_column_authorizations: AtomicU64,
    denied_reads: AtomicU64,
    unexpected_statements: AtomicU64,
    invalid_counter: AtomicBool,
    budget_exceeded: AtomicBool,
    trace_removed: AtomicBool,
    authorizer_removed: AtomicBool,
}

#[derive(Debug)]
pub(super) struct Work {
    pub candidates: u64,
    pub reference_rows: u64,
    pub statements: u64,
    pub vm_steps: u64,
    pub head_vm_steps: u64,
    pub fullscan_steps: u64,
    pub head_fullscan_steps: u64,
    pub payload_column_authorizations: u64,
    pub denied_reads: u64,
}

pub(super) struct Lifetime(Weak<State>);
impl Lifetime {
    pub fn is_alive(&self) -> bool {
        self.0.strong_count() != 0
    }
}

pub(super) struct Sampler {
    state: Arc<State>,
}

// SQLx 0.9 owns this value in its progress-handler closure. In ConnectionState::drop it first
// clears statements, then removes progress handlers, and only afterwards drops ConnectionHandle.
// Thus this destructor runs either under LockedSqliteHandle or under the worker's exclusive
// ConnectionState ownership, with no SQLite call/callback in flight and a still-live handle.
// It removes BOTH native callbacks before releasing their Arc context. If the test future is
// cancelled, dropping Sampler cannot free that context: the driver still owns this registration.
struct Registration {
    handle_address: usize,
    state: Arc<State>,
}

impl Registration {
    fn interrupt_at_budget(&self) -> bool {
        // A PROFILE VM_STEP value is defined only up to i32::MAX. Interrupt an unexpectedly
        // expensive statement around one million operations, well below that counter limit.
        // This callback is also the driver-owned lifetime anchor; it is not the work sampler.
        self.state.budget_exceeded.store(true, Relaxed);
        false
    }
}

impl Drop for Registration {
    fn drop(&mut self) {
        // SAFETY: handle_address is the exposed address obtained from LockedSqliteHandle during
        // installation. The SQLx-owned closure can only be dropped while the same native handle
        // is exclusive and still open (see the ownership/drop order above). No Rust reference is
        // made from this address. Unregistering cannot overlap a native callback, and the context
        // Arc below remains alive until after both calls return. Neither operation invokes SQL.
        let (trace, authorizer) = unsafe {
            let handle = self.handle_address as *mut libsqlite3_sys::sqlite3;
            (
                libsqlite3_sys::sqlite3_trace_v2(handle, 0, None, std::ptr::null_mut()),
                libsqlite3_sys::sqlite3_set_authorizer(handle, None, std::ptr::null_mut()),
            )
        };
        self.state
            .trace_removed
            .store(trace == libsqlite3_sys::SQLITE_OK, Relaxed);
        self.state
            .authorizer_removed
            .store(authorizer == libsqlite3_sys::SQLITE_OK, Relaxed);
    }
}

impl Sampler {
    pub async fn install(db: &sea_orm::DatabaseConnection) -> Result<Self> {
        let pool = db.get_sqlite_connection_pool();
        ensure!(
            pool.options().get_max_connections() == 1,
            "sampling requires this test fixture's single physical connection"
        );
        let state = Arc::new(State::default());
        {
            let mut connection = pool.acquire().await?;
            let mut handle = connection.lock_handle().await?;
            let raw = handle.as_raw_handle().as_ptr();
            let registration = Registration {
                handle_address: raw as usize,
                state: state.clone(),
            };
            // Install ownership before publishing any context pointer to SQLite. There is no
            // await between the three registrations, so partial installation is synchronous.
            handle.set_progress_handler(1_000_000, move || registration.interrupt_at_budget());
            // SAFETY: raw is protected by LockedSqliteHandle. Arc::as_ptr is aligned and stable;
            // the driver-owned registration above retains its strong reference until it removes
            // the callbacks. Callbacks access only shared atomics, not a mutable State reference.
            // This fresh, private fixture has no previous trace/authorizer/progress subscriber.
            let (trace, authorizer) = unsafe {
                let context = Arc::as_ptr(&state).cast_mut().cast::<c_void>();
                (
                    libsqlite3_sys::sqlite3_trace_v2(
                        raw,
                        (libsqlite3_sys::SQLITE_TRACE_PROFILE | libsqlite3_sys::SQLITE_TRACE_ROW)
                            as c_uint,
                        Some(trace_callback),
                        context,
                    ),
                    libsqlite3_sys::sqlite3_set_authorizer(raw, Some(authorize), context),
                )
            };
            if trace != libsqlite3_sys::SQLITE_OK || authorizer != libsqlite3_sys::SQLITE_OK {
                handle.remove_progress_handler();
                anyhow::bail!("native sampling registration failed: {trace}/{authorizer}");
            }
        }
        let sampler = Self { state };
        // Prove the column guard is active before the measured request. Preparing this forbidden
        // read fails even though the fixture's content table is empty. Exclude the probe from Main.
        let probe = db
            .query_all_raw(statement(
                "SELECT data FROM conversation_content_chunks LIMIT 1",
                vec![],
            ))
            .await;
        if probe.is_ok() || sampler.state.denied_reads.load(Relaxed) != 1 {
            sampler.finish(db).await?;
            anyhow::bail!("body-column authorizer probe was not denied");
        }
        sampler.state.denied_reads.store(0, Relaxed);
        Ok(sampler)
    }

    pub fn lifetime(&self) -> Lifetime {
        Lifetime(Arc::downgrade(&self.state))
    }

    pub async fn finish(self, db: &sea_orm::DatabaseConnection) -> Result<Work> {
        {
            let mut connection = db.get_sqlite_connection_pool().acquire().await?;
            let mut handle = connection.lock_handle().await?;
            // Reacquiring the worker's native lock joins any in-flight step/profile callback.
            // SQLx removes its progress callback before dropping Registration, whose destructor
            // unregisters trace/authorizer before the final native-owned State Arc is released.
            handle.remove_progress_handler();
        }
        let s = &self.state;
        ensure!(
            s.trace_removed.load(Relaxed) && s.authorizer_removed.load(Relaxed),
            "native callbacks were not unregistered"
        );
        ensure!(
            Arc::strong_count(s) == 1,
            "native callback context is still retained"
        );
        ensure!(
            !s.budget_exceeded.load(Relaxed),
            "statement exceeded the VM counter safety budget"
        );
        ensure!(
            !s.invalid_counter.load(Relaxed),
            "invalid SQLite statement counter"
        );
        ensure!(
            s.unexpected_statements.load(Relaxed) == 0,
            "production Main executed SQL other than the original RunHeads/header queries"
        );
        Ok(Work {
            candidates: s.candidates.load(Relaxed),
            reference_rows: s.reference_rows.load(Relaxed),
            statements: s.statements.load(Relaxed),
            vm_steps: s.vm_steps.load(Relaxed),
            head_vm_steps: s.head_vm_steps.load(Relaxed),
            fullscan_steps: s.fullscan_steps.load(Relaxed),
            head_fullscan_steps: s.head_fullscan_steps.load(Relaxed),
            payload_column_authorizations: s.payload_column_authorizations.load(Relaxed),
            denied_reads: s.denied_reads.load(Relaxed),
        })
    }
}

fn contains(sql: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && sql.windows(needle.len()).any(|window| window == needle)
}

enum Kind {
    Heads,
    Reference,
    Unexpected,
}

fn kind(sql: &[u8]) -> Kind {
    let sql = sql.trim_ascii();
    if sql == run_read::RUN_HEADS_SQL.as_bytes().trim_ascii() {
        Kind::Heads
    } else if sql.starts_with(b"SELECT ")
        && sql.ends_with(b"FROM conversation_items WHERE seq=?")
        && contains(sql, b"length(payload)")
        && sql
            .windows(b"payload".len())
            .filter(|w| *w == b"payload")
            .count()
            == 1
    {
        // Permit the production run-start validation point read, but never a raw payload select.
        Kind::Reference
    } else {
        Kind::Unexpected
    }
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
    // SAFETY: registration owns the State Arc until native callbacks are removed; SQLite passes
    // its live sqlite3_stmt for PROFILE/ROW synchronously on the exclusive SQLx worker thread.
    // sqlite3_sql's NUL-terminated bytes remain valid for this call and are never retained.
    let (state, stmt, sql) = unsafe {
        let state = &*context.cast::<State>();
        let stmt = statement.cast::<libsqlite3_sys::sqlite3_stmt>();
        let sql = libsqlite3_sys::sqlite3_sql(stmt);
        if sql.is_null() {
            state.invalid_counter.store(true, Relaxed);
            return 0;
        }
        (state, stmt, CStr::from_ptr(sql).to_bytes())
    };
    let kind = kind(sql);
    if event == libsqlite3_sys::SQLITE_TRACE_ROW as c_uint {
        match kind {
            Kind::Heads => {
                state.candidates.fetch_add(1, Relaxed);
            }
            Kind::Reference => {
                state.reference_rows.fetch_add(1, Relaxed);
            }
            Kind::Unexpected => {}
        }
    } else if event == libsqlite3_sys::SQLITE_TRACE_PROFILE as c_uint {
        // SAFETY: this is the same live statement, at completion, under SQLite's worker
        // exclusivity. Reset=1 isolates executions of cached statements between samples.
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
        state.statements.fetch_add(1, Relaxed);
        state.vm_steps.fetch_add(vm as u64, Relaxed);
        state.fullscan_steps.fetch_add(fullscan as u64, Relaxed);
        match kind {
            Kind::Heads => {
                state.head_vm_steps.fetch_add(vm as u64, Relaxed);
                state
                    .head_fullscan_steps
                    .fetch_add(fullscan as u64, Relaxed);
            }
            Kind::Reference => {}
            Kind::Unexpected => {
                state.unexpected_statements.fetch_add(1, Relaxed);
            }
        }
    }
    // No allocation, locks, panicking operations, SQL execution or retained SQLite pointers.
    0
}

unsafe extern "C" fn authorize(
    context: *mut c_void,
    action: c_int,
    table: *const c_char,
    column: *const c_char,
    _: *const c_char,
    _: *const c_char,
) -> c_int {
    if action != libsqlite3_sys::SQLITE_READ || context.is_null() || table.is_null() {
        return libsqlite3_sys::SQLITE_OK;
    }
    // SAFETY: SQLite supplies live NUL-terminated action arguments for this synchronous callback.
    // The context has the same driver-owned Arc lifetime as the trace callback.
    let (state, table) = unsafe { (&*context.cast::<State>(), CStr::from_ptr(table).to_bytes()) };
    if table == b"conversation_contents" || table == b"conversation_content_chunks" {
        state.denied_reads.fetch_add(1, Relaxed);
        return libsqlite3_sys::SQLITE_DENY;
    }
    // SAFETY: short-circuit evaluation proves column is non-null before this conversion;
    // SQLite's column argument has the same synchronous callback lifetime as table.
    if table == b"conversation_items"
        && !column.is_null()
        && unsafe { CStr::from_ptr(column) }.to_bytes() == b"payload"
    {
        // SQLite authorizers cannot distinguish length(payload) from payload. Permit the
        // header length access, and separately reject any non-header SQL in the trace audit.
        state.payload_column_authorizations.fetch_add(1, Relaxed);
    }
    libsqlite3_sys::SQLITE_OK
}
