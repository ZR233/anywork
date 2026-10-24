//! Shared fixtures/evidence helpers for the ACP acceptance scenarios.
//!
//! 这些 helper 只读取隔离环境里的真实事实（配置、ACP 证据、native 退出记录、进程
//! 所有权回收），不驱动任何 UI，也不包含产品逻辑。原来的独立账号场景已合并进
//! `acp-auto-install`，这里保留被复用的部分。

use super::*;
use pl_provider_fixture::{ACP_EVENTS_FILE, AcpFixtureEvent};
use pl_studio_runtime::config::{AcpAccountConfig, ConfigPaths, ConfigStore};
use serde::Deserialize;
use serde_json::{Value, json};

const NATIVE_EXIT_SCHEMA: &str = "anywork-native-exit/1";
/// One bounded observation window while a graceful stop is pending.
///
/// A window expiring is a *pending* cleanup diagnosis, never a reason to kill the
/// supervisor or to leave the owner: the caller keeps the handle in the current
/// stack frame, records partial evidence and requests the stop again.
const CLEANUP_WINDOW: Duration = Duration::from_secs(30);
/// Every key the frozen `anywork-native-exit/1` schema must contain. `serde`'s
/// `Option` fields tolerate a missing key, so presence is checked explicitly
/// before the typed decode instead of being inferred from the type.
const NATIVE_EXIT_FIELDS: [&str; 9] = [
    "schema",
    "pid",
    "exitCode",
    "signal",
    "status",
    "elapsedMillis",
    "descendantsAtRootExit",
    "reclaimedDescendants",
    "cancelled",
];
/// The launcher's typed `anywork-native-exit/1` record.
///
/// The fields mirror the frozen schema written by `xtask`; `descendantsAtRootExit`
/// is the subtree present the moment the native host was reaped and may be
/// non-empty, while a non-empty `reclaimedDescendants` means the harness had to
/// force-kill leftovers and is therefore not a clean shutdown.
///
/// No field is defaulted: the record is proof, so a truncated document such as
/// `{"schema": …}` must fail to decode instead of silently reading as
/// "no reclaimed descendants, not cancelled". `signal`/`exitCode` stay optional in
/// type because the schema reports them as `null`; their key presence is enforced
/// by [`NATIVE_EXIT_FIELDS`] before the typed decode, because a missing key would
/// otherwise deserialize as `None`.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct NativeExit {
    schema: String,
    pid: u32,
    exit_code: Option<i32>,
    signal: Option<i32>,
    status: String,
    elapsed_millis: u64,
    descendants_at_root_exit: Vec<u32>,
    reclaimed_descendants: Vec<u32>,
    cancelled: bool,
}

impl NativeExit {
    /// Accepts only a natural, successful native exit with nothing left behind.
    pub(super) fn validate(&self, phase: &str) -> Result<()> {
        ensure!(
            self.schema == NATIVE_EXIT_SCHEMA,
            "acp-account {phase} native exit record has schema `{}`, expected `{NATIVE_EXIT_SCHEMA}`",
            self.schema
        );
        ensure!(
            self.pid > 0,
            "acp-account {phase} native exit record carries no native host pid"
        );
        ensure!(
            self.signal.is_none(),
            "acp-account {phase} native host terminated by signal {:?} (status `{}`)",
            self.signal,
            self.status
        );
        ensure!(
            !self.cancelled,
            "acp-account {phase} native host run was cancelled by the harness"
        );
        ensure!(
            self.exit_code == Some(0),
            "acp-account {phase} native host exited with {:?} (status `{}`)",
            self.exit_code,
            self.status
        );
        ensure!(
            self.reclaimed_descendants.is_empty(),
            "acp-account {phase} native host left processes behind that the harness had to reclaim: {:?}",
            self.reclaimed_descendants
        );
        Ok(())
    }

    pub(super) fn to_json(&self) -> Value {
        json!({
            "schema": self.schema,
            "pid": self.pid,
            "exitCode": self.exit_code,
            "signal": self.signal,
            "status": self.status,
            "elapsedMillis": self.elapsed_millis,
            "descendantsAtRootExit": self.descendants_at_root_exit,
            "reclaimedDescendants": self.reclaimed_descendants,
            "cancelled": self.cancelled,
            "cleanShutdown": self.exit_code == Some(0)
                && self.signal.is_none()
                && !self.cancelled
                && self.reclaimed_descendants.is_empty(),
        })
    }
}

/// Reads the native record, bounded, and requires it to be complete and typed.
///
/// Presence is validated on the decoded document because a `serde` `Option`
/// field accepts a missing key as `None`; a truncated record must never pass as
/// "no signal". Values still come from the typed [`NativeExit`], never from an
/// ad-hoc reading of the raw JSON.
pub(super) fn read_native_exit(path: &Path, timeout: Duration) -> Result<NativeExit> {
    let deadline = Instant::now() + timeout;
    loop {
        if let Ok(bytes) = fs::read(path) {
            let document: Value = serde_json::from_slice(&bytes).with_context(|| {
                format!("native exit record is not typed JSON: {}", path.display())
            })?;
            ensure!(
                document.is_object(),
                "native exit record is not a JSON object: {}",
                path.display()
            );
            for field in NATIVE_EXIT_FIELDS {
                ensure!(
                    document.get(field).is_some(),
                    "native exit record is missing the required `{field}` field: {}",
                    path.display()
                );
            }
            return serde_json::from_value(document).with_context(|| {
                format!(
                    "native exit record does not match {NATIVE_EXIT_SCHEMA}: {}",
                    path.display()
                )
            });
        }
        ensure!(
            Instant::now() < deadline,
            "the launcher wrote no native exit record at {}; the native shutdown is unproven",
            path.display()
        );
        thread::sleep(Duration::from_millis(50));
    }
}

pub(super) fn cleanup_owned(
    phase: &str,
    gui: &mut OwnedProcess,
    mut driver: Option<&mut OwnedProcess>,
    report: &Path,
    output: &Path,
    interrupt: &mpsc::Receiver<()>,
) -> Value {
    let driver_running = driver
        .as_mut()
        .is_some_and(|active| active.child.try_wait().ok().flatten().is_none());
    // The dart Driver is plain harness tooling in the owner's own process group;
    // its existing short bounded teardown is unchanged.
    if let Some(active) = driver.as_mut() {
        active.terminate();
    }

    let mut launcher_exit = None;
    let mut last_wait_error = None;
    let mut stop_requests = 0_u32;
    let mut pending_windows = 0_u32;
    let mut cancellation_requested = false;
    let mut pending_evidence_error = None;
    let launcher_running = match gui.child.try_wait() {
        Ok(Some(status)) => {
            launcher_exit = Some(status.to_string());
            false
        }
        Ok(None) => true,
        Err(error) => {
            last_wait_error = Some(error.to_string());
            true
        }
    };
    if launcher_running {
        loop {
            // The only signal this path sends. The resident supervisor owns the
            // native tree and performs its own cancellation and reclamation.
            if gui.request_stop() {
                stop_requests += 1;
            }
            match gui.wait_exit(CLEANUP_WINDOW) {
                Ok(Some(status)) => {
                    launcher_exit = Some(status.to_string());
                    break;
                }
                Ok(None) => {}
                Err(error) => last_wait_error = Some(error.to_string()),
            }
            pending_windows += 1;
            if interrupt.try_recv().is_ok() {
                // A cancellation of this task only requests the same graceful
                // stop; the sole supervising owner is never killed from here.
                cancellation_requested = true;
            }
            // Pending cleanup: keep the owner right here, refresh what is known so
            // a long wait is visible instead of a silent hang, and ask again.
            let pending = json!({
                "phase": phase,
                "state": "pending",
                "pendingWindows": pending_windows,
                "stopRequests": stop_requests,
                "lastWaitError": last_wait_error,
                "nativeRecordPresent": report.is_file(),
                "cancellationRequested": cancellation_requested,
                "updatedAt": epoch_seconds(SystemTime::now()),
                "note": "the resident supervisor has not exited; this harness keeps the owner and only requests a stop",
            });
            if let Err(error) = write_json(
                &output.join(format!("acp-account-pending-cleanup-{phase}.json")),
                &pending,
            ) {
                pending_evidence_error = Some(error.to_string());
            }
            println!(
                "acp-account {phase} cleanup pending: window {pending_windows}, stop requests \
                 {stop_requests} (owner retained, no kill)"
            );
        }
    }
    // Reached only after the real exit, so no live owner is dropped here.
    gui.mark_reaped();
    let native = read_native_exit(report, Duration::from_secs(20));
    let (native_record, native_error) = match native {
        Ok(native) => (Some(native.to_json()), None),
        Err(error) => (None, Some(error.to_string())),
    };
    json!({
        "phase": phase,
        "forcedTeardown": true,
        "cleanupState": "collected",
        "stopRequests": stop_requests,
        "pendingWindows": pending_windows,
        "cancellationRequested": cancellation_requested,
        "launcherRunningBeforeTeardown": launcher_running,
        "driverRunningBeforeTeardown": driver_running,
        "launcherExit": launcher_exit,
        "lastWaitError": last_wait_error,
        "pendingEvidence": (pending_windows > 0)
            .then(|| format!("acp-account-pending-cleanup-{phase}.json")),
        "pendingEvidenceError": pending_evidence_error,
        "nativeRecordAfterTeardown": native_record,
        "nativeRecordMissing": native_record.is_none(),
        "nativeRecordError": native_error,
        "cleanShutdown": false,
    })
}

/// Writes one evidence document, keeping the failure (not swallowing it).
fn write_json(path: &Path, value: &Value) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(value)?;
    fs::write(path, &bytes).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

/// Seconds since the epoch, for bounded cleanliness timing evidence.
fn epoch_seconds(value: SystemTime) -> u64 {
    value
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_secs())
}

/// 读取这一阶段收束后的 ACP 协议证据。
///
/// 两个调用点都在阶段边界：首个阶段开始前（文件还不存在），以及本阶段 GUI、native
/// 记录与 peer 全部退出之后。因此这里按**最终读取**处理，不提供“活写快照”变体：
/// - 只有 `NotFound` 等价于“还没有任何证据”，其它 I/O 失败传播；
/// - 最后一个换行之后必须**一个字节都没有**：writer 逐条写完整记录，尾部残留的
///   任何字节（含纯空白）都只能来自截断或损坏，不能当成“还没写完”默默丢弃；
/// - 完整行里的空白行、坏 JSON、缺失 event 或 `pid == 0` 一律带行号失败。
pub(super) fn read_events(state: &Path) -> Result<Vec<AcpFixtureEvent>> {
    let path = state.join(ACP_EVENTS_FILE);
    let text = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };
    let tail_start = text.rfind('\n').map_or(0, |index| index + 1);
    let (complete, tail) = text.split_at(tail_start);
    ensure!(
        tail.is_empty(),
        "fake ACP Agent evidence ends with {} byte(s) that are not a complete record: {}",
        tail.len(),
        path.display()
    );
    let mut events = Vec::new();
    for (index, line) in complete.lines().enumerate() {
        let line = line.trim();
        ensure!(
            !line.is_empty(),
            "fake ACP Agent evidence line {} is blank: {}",
            index + 1,
            path.display()
        );
        let event: AcpFixtureEvent =
            serde_json::from_str::<AcpFixtureEvent>(line).with_context(|| {
                format!(
                    "fake ACP Agent evidence line {} is not a typed record: {}",
                    index + 1,
                    path.display()
                )
            })?;
        // 每条记录都必须归因到一个真实存在的 agent 进程：writer 用
        // `std::process::id()` 写 pid，`0` 只可能来自损坏或伪造。
        ensure!(
            event_pid(&event) > 0,
            "fake ACP Agent evidence line {} carries no valid agent pid: {}",
            index + 1,
            path.display()
        );
        events.push(event);
    }
    Ok(events)
}

pub(super) fn event_pid(event: &AcpFixtureEvent) -> u32 {
    match event {
        AcpFixtureEvent::Initialize { pid }
        | AcpFixtureEvent::Authenticate { pid }
        | AcpFixtureEvent::SessionNew { pid }
        | AcpFixtureEvent::Close { pid }
        | AcpFixtureEvent::NoPrompt { pid }
        | AcpFixtureEvent::AuthenticateReleased { pid }
        | AcpFixtureEvent::Disconnect { pid, .. } => *pid,
    }
}

/// 隔离的 typed 配置入口：内存凭据，绝不动用户系统凭据库。
///
/// 路径来自产品自己的 [`ConfigPaths`]（`<studio-home>/config.toml`），验收侧不再拼
/// 文件名；每次读取都落到磁盘上的**当前**文件，不缓存任何旧快照。
pub(super) fn acp_config_store(home: &Path) -> ConfigStore {
    ConfigStore::new(ConfigPaths::from_config_dir(home))
}

/// 该 home 当前的 canonical ACP 账号（按产品 typed 配置读取）。
///
/// 文件缺失等价于“还没有账号”；文件存在但不可解析、不符合当前 schema 或被产品判为
/// 引用无效时一律失败传播——产品启动会把这类文件判为损坏并恢复，验收绝不能把它当成
/// “空账号”通过。
pub(super) fn acp_accounts(home: &Path) -> Result<BTreeMap<String, AcpAccountConfig>> {
    Ok(acp_config_store(home).load_or_default()?.acp.accounts)
}
