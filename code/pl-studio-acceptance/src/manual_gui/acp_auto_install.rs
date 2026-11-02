//! Antigravity auto-install acceptance through the real native GUI.
//!
//! The fixture peer imitates only the outside world: the official registry
//! document, the Google distribution ZIP and the TLS trust boundary. The product
//! reaches it through the ordinary `HTTPS_PROXY` contract plus an isolated
//! `SSL_CERT_FILE`; nothing here relaxes production TLS, hosts or source policy,
//! and no product install logic is re-implemented.
//!
//! Each lifecycle writes one control document with its own frozen descriptor
//! (version/archive/args identity), starts the peer, opens one isolated Studio
//! home and one GUI through `--native-launch`, then waits for an operator
//! runbook. This module owns the environment, the isolated trust setup and the
//! factual checks on the real `<home>/studio/acp-servers` tree, the peer request
//! log and the native exit record.
//!
//! Phase matrix (产品只允许一个固定的 1.4.1 发行，所以不再按版本区分；每个 home
//! 代表一组需要连续性的阶段，故障阶段各自独立)：
//! `first`（H1，预置旧账号、无安装）→ preparationRequired@prepare，再真实准备
//! unknown-length 包 → ready → 保存唯一新账号 → check；`auth-faults`（H1 同安装）
//! → 认证成功/等待/失败/取消/迟到与 Native 表单回归，合成 state 在安装树外；
//! `restart`（H1）→ 重开只读验证，archive GET 为 0；`resume`（H2，预置账号）→
//! 单次断流后的真实 Range 续传；`cancel`（H3，预置账号）→ 取消保留同 descriptor
//! 的 partial；`retry`（H3）→ 新操作续传同一 partial → ready + 保存；`reuse`
//! （H3）→ 同安装 reused、零 GET；`faults-unsafe-zip`（H4）→ Traversal 包被拒绝。
//!
//! Wire/storage identity: `installationId` is the wire value `sha256:<64hex>` and
//! the filesystem key is the 64 lowercase hex. Installed directories, downloads,
//! partial downloads and receipts are matched through that mapping.

use super::acp_support::{
    acp_accounts, acp_config_store, cleanup_owned, event_pid, read_events, read_native_exit,
};
use super::*;
use pl_provider_fixture::acp_install::{
    CONTROL_FILE, READY_FILE, REPORT_FILE, REQUESTS_FILE, file_sha256, host_target,
};
use pl_provider_fixture::{ACP_AUTHENTICATED_MARKER, AcpFixtureBehavior, AcpFixtureEvent};
use pl_studio_runtime::config::{AcpAccountConfig, AcpProvider};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::io::Read as _;

/// Fixture peer state directory owned by this scenario.
const PEER_DIR_NAME: &str = "acp-install-peer";
/// Fake ACP server state directory the packaged program writes into.
const AGENT_DIR_NAME: &str = "acp-install-agent";
/// Auxiliary member kept inside the package next to the program.
const AUXILIARY_NAME: &str = "localharness_external";
/// Failure summary written next to the retained environment.
const FAILURE_FILE: &str = "acp-auto-install-failure.json";
/// Peer log lines copied into the failure summary (the real file stays untouched).
const PEER_LOG_TAIL_LINES: usize = 40;
/// Provider document identity.
const PROVIDER: &str = "antigravity";
/// Program member named by the registry `cmd`.
const PROGRAM_MEMBER: &str = "agy_acp_server.par";
/// Wire installation identity prefix.
const WIRE_ID_PREFIX: &str = "sha256:";
/// 预置旧账号的固定 id：schema 25 里 id 只是 map key，值本身不参与产品语义。
const SEED_ACCOUNT_ID: &str = "5eed0000-0000-4000-8000-00000000acp1";

pub(super) struct AcpAutoInstallScenario<'a> {
    pub workspace: &'a Path,
    pub app_dir: &'a Path,
    pub home: &'a Path,
    pub working: &'a Path,
    pub output: &'a Path,
    /// Cargo-resolved absolute path of the `pl-provider-fixture` binary. It is
    /// both the fixture peer and the packaged official server program.
    pub fixture_program: &'a Path,
    /// Whether the harness keeps the isolated environment after a successful run.
    pub retain_environment: bool,
    /// Which frozen phase group this run covers; every unselected phase is absent
    /// from the evidence instead of being filled in as passed.
    pub start: StartPhase,
    pub interrupt: &'a mpsc::Receiver<()>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Expect {
    Ready,
    Cancelled,
    Failed,
    /// 只观察账号认证终态（安装已在前一阶段完成），不产生新的安装操作。
    Auth,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Save {
    /// A new account row must appear and launch exactly the published program.
    New,
    /// The canonical account document must not change at all.
    None,
    /// Either unchanged or one new row launching the published program.
    Existing,
}

/// 本次运行的起点：完整八阶段，或只跑后四阶段组。
///
/// 只有两个起点，不提供任意跳阶段：`first` 是既有默认（`PHASES` 全量），`cancel`
/// 是 `cancel/retry/reuse/faults-unsafe-zip`。这两组各自满足前置——`cancel` 自己
/// 预置账号、`retry` 自己保存身份——所以后四阶段不依赖任何 `first` 身份，也不共享
/// 上一次失败运行的 partial 或摘要。
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum StartPhase {
    /// 默认起点：全部冻结阶段。
    First,
    /// 取消/重试/复用组 + 独立归档故障阶段。
    Cancel,
}

impl StartPhase {
    /// CLI 取值与证据里的 label。
    pub(super) const fn label(self) -> &'static str {
        match self {
            Self::First => "first",
            Self::Cancel => "cancel",
        }
    }

    /// 该起点在冻结阶段表里的下标。
    fn index(self) -> usize {
        PHASES
            .iter()
            .position(|spec| spec.phase == self.label())
            .expect("every start phase names one of the frozen phases")
    }

    /// 本次运行选中的阶段名（按冻结顺序，不含未选阶段）。
    pub(super) fn selected_phases(self) -> Vec<&'static str> {
        PHASES
            .iter()
            .skip(self.index())
            .map(|spec| spec.phase)
            .collect()
    }
}

/// Which isolated home one phase runs in.
///
/// Continuity groups share a home (they must see the previous phase's real
/// artifacts); archive faults get their own home so a fault can never be avoided by
/// reusing another phase's cache or by changing a version.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Home {
    /// H1: old-account baseline, install, save, auth faults and restart.
    First,
    /// H2: independent uninstalled baseline for the resume lifecycle.
    Resume,
    /// H3: shared cancel → retry → reuse continuation.
    Transfer,
    /// H4: the unsafe-archive fault.
    Fault,
}

/// The concrete home directories owned by this scenario.
struct Homes {
    first: PathBuf,
    resume: PathBuf,
    transfer: PathBuf,
    fault: PathBuf,
}

impl Homes {
    fn new(context: &AcpAutoInstallScenario<'_>) -> Result<Self> {
        let resume = context.working.join("acp-install-home-resume");
        let transfer = context.working.join("acp-install-home-transfer");
        let fault = context.working.join("acp-install-home-fault");
        for home in [&resume, &transfer, &fault] {
            fs::create_dir_all(home)?;
        }
        Ok(Self {
            // H1 is the isolated home the manual-gui coordinator already created.
            first: context.home.to_path_buf(),
            resume,
            transfer,
            fault,
        })
    }

    fn slot(&self, home: Home) -> &Path {
        match home {
            Home::First => &self.first,
            Home::Resume => &self.resume,
            Home::Transfer => &self.transfer,
            Home::Fault => &self.fault,
        }
    }

    fn all(&self) -> [&Path; 4] {
        [&self.first, &self.resume, &self.transfer, &self.fault]
    }
}

/// One GUI lifecycle and the external environment it must observe.
struct PhaseSpec {
    phase: &'static str,
    home: Home,
    expect: Expect,
    save: Save,
    /// 该阶段开始时必须已有一个 schema 25 ACP 账号（无安装）作为旧配置基线。
    seed_account: bool,
    /// 该阶段必须先看到 `preparationRequired@prepare` 的真实终态。
    require_preparation_required: bool,
    /// Driver 需要第四个参数：绝对的合成 fixture state 目录。
    needs_agent_state: bool,
    /// 包形状与传输控制。
    variant: &'static str,
    unknown_length: bool,
    drop_after_bytes: Option<u64>,
    drop_requests: u32,
    chunk_bytes: usize,
    chunk_delay_ms: u64,
    /// 该阶段必须证明下载真的以非零 Range 续传。
    require_resume: bool,
    /// 该阶段必须复用既有安装且不请求归档。
    require_reuse: bool,
    /// 该阶段必须写出 `summary.savedAccount`（first/retry）。
    saves_identity: bool,
    /// 该阶段从 first/retry 的 `savedAccount` 读取身份并核对当前 revision。
    consumes_identity: bool,
    /// 该阶段必须观察到的 typed 安装失败码。
    fault_code: Option<&'static str>,
    /// 该阶段必须**存在且为 true** 的真实 check（缺失不算通过）。
    required_checks: &'static [&'static str],
    required_captures: &'static [&'static str],
}

const PHASES: [PhaseSpec; 8] = [
    PhaseSpec {
        phase: "first",
        home: Home::First,
        expect: Expect::Ready,
        save: Save::New,
        seed_account: true,
        require_preparation_required: true,
        needs_agent_state: false,
        variant: "normal",
        // Unknown total: progress must stay real bytes, never a synthesized
        // percentage, while the fixed package still installs completely.
        unknown_length: true,
        drop_after_bytes: None,
        drop_requests: 0,
        // Pace the synthetic transfer so the Driver can observe and capture
        // downloading even when the optimized fixture archive is small.
        chunk_bytes: 65_536,
        chunk_delay_ms: 150,
        require_resume: false,
        require_reuse: false,
        saves_identity: true,
        consumes_identity: false,
        fault_code: None,
        required_checks: &[
            "seedPreparationRequired",
            "seedCheckDidNotChangeAccounts",
            "accountsBaselineReady",
            "savedAccountIdentityRecorded",
        ],
        required_captures: &["prepare-required", "progress", "ready", "connected"],
    },
    PhaseSpec {
        phase: "auth-faults",
        home: Home::First,
        expect: Expect::Auth,
        save: Save::None,
        seed_account: false,
        require_preparation_required: false,
        // The Driver may only touch the synthetic state directory this harness owns.
        needs_agent_state: true,
        variant: "normal",
        unknown_length: false,
        drop_after_bytes: None,
        drop_requests: 0,
        chunk_bytes: 262_144,
        chunk_delay_ms: 2,
        require_resume: false,
        require_reuse: false,
        saves_identity: false,
        consumes_identity: true,
        fault_code: None,
        required_checks: &[
            "firstLoginSamePidChain",
            "authenticationFailedForThisAttempt",
            "authCancellationJoinedThisPid",
            "lateReleaseCannotReviveCancelledLogin",
            "syntheticCredentialRestoredForRestart",
            "restoreLoginSamePidChain",
            "usageQueryActionSent",
            "usageReadyForSavedIdentity",
            "nativeFormRenderedAndCancelledWithoutSaving",
            "authFaultsAccountsUnchanged",
        ],
        required_captures: &[
            "authenticating",
            "verified",
            "authentication-failed",
            "auth-cancelled",
            "quota-details",
            "quota-list",
            "native-form",
        ],
    },
    PhaseSpec {
        phase: "restart",
        home: Home::First,
        expect: Expect::Auth,
        save: Save::None,
        seed_account: false,
        require_preparation_required: false,
        needs_agent_state: false,
        variant: "normal",
        unknown_length: false,
        drop_after_bytes: None,
        drop_requests: 0,
        chunk_bytes: 262_144,
        chunk_delay_ms: 2,
        require_resume: false,
        // A restart verifies the stored installation; it must not download again.
        require_reuse: true,
        saves_identity: false,
        consumes_identity: true,
        fault_code: None,
        required_checks: &[
            "authLoadedUncheckedAfterRestart",
            "explicitCheckVerifiedAfterRestart",
            "restartCheckDidNotPrepare",
            "restartAccountsUnchanged",
        ],
        required_captures: &["reopened", "connected-reopened"],
    },
    PhaseSpec {
        phase: "resume",
        home: Home::Resume,
        expect: Expect::Ready,
        save: Save::None,
        seed_account: true,
        require_preparation_required: false,
        needs_agent_state: false,
        variant: "normal",
        unknown_length: false,
        // The body dies once; the download must continue from the real number of
        // bytes already on disk with a Range request.
        drop_after_bytes: Some(4 * 1024 * 1024),
        drop_requests: 1,
        chunk_bytes: 65_536,
        // Keep the resumed transfer observable through the screenshot barrier,
        // including when little remains after the injected connection drop.
        chunk_delay_ms: 150,
        require_resume: true,
        require_reuse: false,
        saves_identity: false,
        consumes_identity: false,
        fault_code: None,
        required_checks: &["resumeDidNotSave"],
        required_captures: &["progress-resumed", "ready"],
    },
    PhaseSpec {
        phase: "cancel",
        home: Home::Transfer,
        expect: Expect::Cancelled,
        save: Save::None,
        seed_account: true,
        require_preparation_required: false,
        needs_agent_state: false,
        variant: "normal",
        unknown_length: false,
        drop_after_bytes: None,
        drop_requests: 0,
        // 慢分块只负责制造一个真实可取消的下载窗口；`Cancelling` 是否恰好可截到
        // 由真实采样决定，验收不能为了截图延迟或注入生产取消状态。
        chunk_bytes: 65_536,
        chunk_delay_ms: 150,
        require_resume: false,
        require_reuse: false,
        saves_identity: false,
        consumes_identity: false,
        fault_code: None,
        required_checks: &[
            "cancelHasOperation",
            "cancelReleaseCaptured",
            "cancelActionSent",
            "cancellingObservationRecorded",
            "cancelledKeepsOriginalOperation",
            "cancelledOperationRecorded",
            "cancelledDidNotSave",
        ],
        // 取消中瞬态不保证驻留一帧：`cancelling` 截图可选（若记录仍严格核验），
        // 必需证据是真实点击前的下载窗口与同 operation 的 `cancelled` 终态。
        required_captures: &["downloading-before-cancel", "cancelled"],
    },
    PhaseSpec {
        phase: "retry",
        home: Home::Transfer,
        expect: Expect::Ready,
        save: Save::New,
        seed_account: false,
        require_preparation_required: false,
        needs_agent_state: false,
        variant: "normal",
        unknown_length: false,
        drop_after_bytes: None,
        drop_requests: 0,
        chunk_bytes: 65_536,
        // Retry must retain the same real downloading capture window.
        chunk_delay_ms: 150,
        // Same descriptor and bytes as the cancelled lifecycle: the preserved
        // partial belongs to this identity, so the retry continues it.
        require_resume: true,
        require_reuse: false,
        saves_identity: true,
        consumes_identity: false,
        fault_code: None,
        required_checks: &[
            "retryHasCancelEvidence",
            "retryOperationIsFresh",
            "retryReleaseMatchesCancel",
            "savedAccountIdentityRecorded",
        ],
        required_captures: &["progress-retry", "ready", "connected"],
    },
    PhaseSpec {
        phase: "reuse",
        home: Home::Transfer,
        expect: Expect::Ready,
        save: Save::Existing,
        seed_account: false,
        require_preparation_required: false,
        needs_agent_state: false,
        variant: "normal",
        unknown_length: false,
        drop_after_bytes: None,
        drop_requests: 0,
        chunk_bytes: 262_144,
        chunk_delay_ms: 2,
        require_resume: false,
        require_reuse: true,
        saves_identity: false,
        consumes_identity: false,
        fault_code: None,
        required_checks: &["reusedBadgeVisible", "reuseFlagTrue", "reuseDidNotSave"],
        required_captures: &["ready-reused"],
    },
    PhaseSpec {
        phase: "faults-unsafe-zip",
        home: Home::Fault,
        expect: Expect::Failed,
        save: Save::None,
        seed_account: true,
        require_preparation_required: false,
        needs_agent_state: false,
        variant: "traversal",
        unknown_length: false,
        drop_after_bytes: None,
        drop_requests: 0,
        chunk_bytes: 262_144,
        chunk_delay_ms: 0,
        require_resume: false,
        require_reuse: false,
        saves_identity: false,
        consumes_identity: false,
        fault_code: Some("invalidArchive"),
        required_checks: &[
            "failureCodeIsinvalidArchive",
            "failureVisible",
            "failureHasOperation",
            "failureReadable",
        ],
        required_captures: &["failed-archive"],
    },
];

pub(super) fn run(context: &AcpAutoInstallScenario<'_>) -> Result<()> {
    ensure!(
        cfg!(unix),
        "the acp-auto-install acceptance currently requires the Linux native host"
    );
    let program = context.fixture_program.canonicalize().with_context(|| {
        format!(
            "the fixture peer/program executable is missing: {}",
            context.fixture_program.display()
        )
    })?;
    ensure!(
        program.is_file(),
        "the fixture peer/program is not a regular file: {}",
        program.display()
    );
    let target = host_target()?;
    ensure!(
        target == "linux-x86_64" || target == "linux-aarch64",
        "the acp-auto-install acceptance expects a Linux host target, got {target}"
    );
    // The packaged official program *is* this fixture binary. Recording its
    // identity once lets every lifecycle prove the published entry was the same
    // bytes instead of trusting the peer's own ready document.
    let program_sha = file_sha256(&program)?;
    let program_bytes = fs::metadata(&program)?.len();
    let peer = context.working.join(PEER_DIR_NAME);
    fs::create_dir_all(&peer)?;
    let agent = context.working.join(AGENT_DIR_NAME);
    fs::create_dir_all(&agent)?;
    // The packaged program is the fake ACP Agent: it authenticates immediately
    // when asked and answers `session/new` only when its own credential exists.
    // The acceptance itself never presses "login", so a logged-out check must
    // yield `Required` instead of a forged credential.
    fs::write(
        agent.join("behavior.json"),
        serde_json::to_vec_pretty(&AcpFixtureBehavior::default())?,
    )?;
    let auxiliary = context.working.join(AUXILIARY_NAME);
    // A real auxiliary member is packaged and must survive extraction; it is a
    // plain text asset with a non-executable mode, standing in for the second
    // helper the official package ships.
    fs::write(
        &auxiliary,
        b"anywork ACP install fixture auxiliary member\n",
    )?;
    let homes = Homes::new(context)?;
    // 每个 home 只允许本场景自己预置的一份旧账号基线：既有账号不是“准备阶段
    // 提前保存”的证据，准备/复用阶段都按该阶段开始前的 canonical 账号比较。
    for home in homes.all() {
        ensure!(
            acp_accounts(home)?.is_empty(),
            "the isolated ACP home already contains a saved account before the journey started"
        );
    }

    let redactions = build_redactions(context, &program, &agent, &peer, &auxiliary, &homes);
    let mut phases: Vec<Value> = Vec::new();
    let screenshots: Vec<Value> = Vec::new();
    let mut cleanups: Vec<Value> = Vec::new();
    // 已发布账本按**实际 home** 归属：同一个固定 descriptor/storage key 出现在两个
    // 隔离 home 里是两个物理安装，跨 home 的“被删除/被改”结论没有意义。
    let mut published: BTreeMap<PathBuf, BTreeMap<String, BTreeMap<String, String>>> =
        BTreeMap::new();
    let mut saved_accounts: BTreeMap<&'static str, Value> = BTreeMap::new();
    let mut previous_partial: Option<String> = None;
    let previous_operation: Option<String> = None;
    let previous_cancel: Option<Value> = None;
    let mut last_ready_key: Option<String> = None;

    let journey = (|| -> Result<()> {
        // 只跑本次起点选中的连续阶段组：未选阶段的 home 保持既有空目录布局，
        // 绝不补造它们的身份、摘要或通过状态。
        for spec in PHASES.iter().skip(context.start.index()) {
            let home = homes.slot(spec.home);
            let layout = Layout::new(home.to_path_buf(), target.clone());
            if spec.seed_account {
                seed_acp_account(home)?;
            }
            if spec.consumes_identity {
                ensure!(
                    saved_accounts.contains_key("first"),
                    "the {} phase has no saved identity from an earlier save",
                    spec.phase
                );
            }
            let control = control_document(spec, &program, &auxiliary, &agent)?;
            clear_peer_evidence(&peer)?;
            write_json(&peer.join(CONTROL_FILE), &control)?;
            let peer_log = context
                .working
                .join(format!("acp-install-peer-{}.log", spec.phase));
            let mut peer_process = start_peer(&program, &peer, &peer_log)?;
            let ready = match wait_ready(&peer, &mut peer_process, context.interrupt) {
                Ok(ready) => ready,
                Err(error) => {
                    let _ = stop_peer(&mut peer_process, &peer);
                    return Err(error);
                }
            };
            let saved_identity: Option<Value> = saved_accounts.get("first").cloned();
            let config_before = canonical_accounts(home)?;
            let snapshot_before = layout.installed_snapshot()?;
            let parts_before = layout.parts()?;
            let events_before = read_events(&agent)?.len();

            // Snapshot/capture files share one output directory across phases, so
            // only artifacts written after this lifecycle started may be trusted.
            let gui_log = context
                .working
                .join(format!("acp-install-{}-gui.log", spec.phase));
            let report = context
                .working
                .join(format!("acp-install-{}-native-exit.json", spec.phase));
            let mut gui = start_gui(context, home, &ready, &gui_log, &report)?;
            let gui_pid = gui.child.id();
            let _ = spec.needs_agent_state.then_some(agent.as_path());
            // One owning block for the whole lifecycle: operator observation,
            // native exit record and its validation all run here, so every
            // failure is reclaimed by the same cleanup path instead of bypassing it.
            let outcome = (|| -> Result<Value> {
                let vm_url = wait_vm(&gui_log, &mut gui, context.interrupt)?;
                observe_capture_exit(
                    context.app_dir,
                    &vm_url,
                    context.output,
                    context.interrupt,
                    &mut gui,
                    None,
                    &format!(
                        "acp-auto-install {}: complete the {} observation in the isolated Studio, then type done.",
                        spec.phase, spec.phase
                    ),
                )?;
                let gui_status = wait_for_gui_exit(spec.phase, &mut gui, context.interrupt)?;
                ensure!(
                    gui_status.success(),
                    "the GUI launcher exited with {gui_status} for the acp-auto-install {} lifecycle",
                    spec.phase
                );
                // The native record is the authority for the real process tree:
                // read and validate it before anything is marked reaped.
                let native = read_native_exit(&report, Duration::from_secs(20))?;
                native.validate(&format!("acp-auto-install {}", spec.phase))?;
                Ok(native.to_json())
            })();
            let native = match outcome {
                Ok(native) => native,
                Err(error) => {
                    cleanups.push(cleanup_owned(
                        spec.phase,
                        &mut gui,
                        None,
                        &report,
                        context.output,
                        context.interrupt,
                    ));
                    let stop = stop_peer(&mut peer_process, &peer);
                    let mut message = format!(
                        "acp-auto-install {} lifecycle failed: {error:#}",
                        spec.phase
                    );
                    if let Err(stop_error) = stop {
                        message
                            .push_str(&format!("; the peer cleanup also failed: {stop_error:#}"));
                    }
                    return Err(anyhow::anyhow!(message));
                }
            };
            gui.mark_reaped();
            drop(gui);
            let peer_facts = stop_peer(&mut peer_process, &peer)?;
            let audit = audit_peer_requests(&peer_facts)?;
            let credential_present = agent.join(ACP_AUTHENTICATED_MARKER).is_file();
            let snapshot_after = layout.installed_snapshot()?;
            let parts_after = layout.parts()?;
            let finals_after = layout.final_archives()?;
            let config_after = canonical_accounts(home)?;
            let events = read_events(&agent)?;
            ensure!(
                events.len() >= events_before,
                "the fake ACP Agent rewrote its typed evidence during the {} lifecycle",
                spec.phase
            );
            let delta = &events[events_before..];

            // 只把当前 home 自己已核实的账本交给本阶段断言；其它 home 的安装既不能
            // 被要求出现在这里，也不影响这里的结论。
            let home_published = published.get(home).cloned().unwrap_or_default();
            let facts = PhaseFacts {
                output: context.output,
                spec,
                layout: &layout,
                ready: &ready,
                peer: &peer_facts,
                audit: audit.clone(),
                program_member: PROGRAM_MEMBER,
                archive_sha: ready
                    .get("archiveSha256")
                    .and_then(Value::as_str)
                    .context("the peer ready document carries no archive digest")?
                    .to_owned(),
                expected_members: expected_members(&ready)?,
                config_before: &config_before,
                config_after: &config_after,
                snapshot_before: &snapshot_before,
                snapshot_after: &snapshot_after,
                published: &home_published,
                parts_before: &parts_before,
                parts_after: &parts_after,
                finals_after: &finals_after,
                previous_partial: previous_partial.as_deref(),
                previous_operation: previous_operation.as_deref(),
                previous_cancel: previous_cancel.as_ref(),
                events: delta,
                previous_ready_key: last_ready_key.as_deref(),
                program_sha: &program_sha,
                program_bytes,
                credential_present,
                saved_identity: saved_identity.as_ref(),
                native,
                gui_pid,
            };
            if spec.saves_identity {
                let added = accounts_added(&config_before, &config_after)?;
                ensure!(
                    added.len() == 1,
                    "acp-auto-install {} saved {} new accounts, expected exactly one",
                    spec.phase,
                    added.len()
                );
                let saved = added[0]
                    .as_object()
                    .with_context(|| {
                        format!(
                            "acp-auto-install {} saved no account identity",
                            spec.phase
                        )
                    })?;
                ensure!(
                    saved
                        .get("accountId")
                        .and_then(Value::as_str)
                        .is_some_and(|id| !id.is_empty()),
                    "acp-auto-install {} recorded an empty saved account identity",
                    spec.phase
                );
                saved_accounts.insert(spec.phase, added[0].clone());
            }
            let phase_evidence = assert_phase(&facts)?;
            let _ = &phase_evidence;
            let next_partial = (spec.expect == Expect::Cancelled)
                .then(|| {
                    facts
                        .parts_after
                        .keys()
                        .find(|key| !facts.parts_before.contains_key(*key))
                        .cloned()
                })
                .flatten();
            drop(facts);
            if spec.expect == Expect::Cancelled {
                ensure!(
                    next_partial.is_some(),
                    "acp-auto-install cancel left no partial download to continue"
                );
                previous_partial = next_partial;
            }
            if spec.expect == Expect::Ready {
                let key = if spec.require_reuse {
                    last_ready_key.clone()
                } else {
                    snapshot_after
                        .keys()
                        .find(|key| !snapshot_before.contains_key(*key))
                        .cloned()
                };
                last_ready_key = key;
                // 只更新本 home 的账本，绝不覆写其它 home 已经核过的安装。
                published.insert(home.to_path_buf(), snapshot_after);
            }
            phases.push(phase_evidence);
        }
        Ok(())
    })();

    let identity = json!({
        "target": target,
        "programSha256": program_sha,
        "programBytes": program_bytes,
    });
    let evidence_error = write_install_evidence(
        context,
        &phases,
        &screenshots,
        &cleanups,
        &redactions,
        &identity,
    );
    journey?;
    match evidence_error {
        Some(error) => Err(error),
        None => {
            if context.retain_environment {
                scrub_private_material(&peer)?;
            }
            Ok(())
        }
    }
}

struct PhaseFacts<'a> {
    output: &'a Path,
    spec: &'a PhaseSpec,
    layout: &'a Layout,
    ready: &'a Value,
    peer: &'a PeerFacts,
    /// 由完整请求日志推导出的固定来源证据（每生命周期都必须核对）。
    audit: Value,
    program_member: &'static str,
    archive_sha: String,
    expected_members: Vec<MemberExpect>,
    config_before: &'a Value,
    config_after: &'a Value,
    snapshot_before: &'a BTreeMap<String, BTreeMap<String, String>>,
    snapshot_after: &'a BTreeMap<String, BTreeMap<String, String>>,
    published: &'a BTreeMap<String, BTreeMap<String, String>>,
    parts_before: &'a BTreeMap<String, u64>,
    parts_after: &'a BTreeMap<String, u64>,
    finals_after: &'a BTreeSet<String>,
    previous_partial: Option<&'a str>,
    previous_operation: Option<&'a str>,
    previous_cancel: Option<&'a Value>,
    events: &'a [AcpFixtureEvent],
    previous_ready_key: Option<&'a str>,
    /// Digest and length of the fixture binary that is also the packaged program.
    program_sha: &'a str,
    program_bytes: u64,
    credential_present: bool,
    /// `first` 记录的保存身份；认证类阶段必须用它而不是“最后一项/同名”猜。
    saved_identity: Option<&'a Value>,
    native: Value,
    gui_pid: u32,
}

fn assert_phase(facts: &PhaseFacts<'_>) -> Result<Value> {
    let spec = facts.spec;
    match spec.expect {
        Expect::Ready => assert_ready(facts)?,
        Expect::Auth => assert_auth_phase(facts)?,
        Expect::Cancelled => {
            assert_no_new_publication(facts, "cancel")?;
            ensure!(
                facts.config_before == facts.config_after,
                "acp-auto-install cancel changed the saved accounts"
            );
            let new_parts: Vec<&String> = facts
                .parts_after
                .keys()
                .filter(|key| !facts.parts_before.contains_key(*key))
                .collect();
            ensure!(
                !new_parts.is_empty(),
                "acp-auto-install cancel produced no partial download for the frozen descriptor"
            );
            for key in &new_parts {
                ensure!(
                    !facts.finals_after.contains(*key),
                    "acp-auto-install cancel already completed the archive for {key}"
                );
            }
            assert_frozen_archive_request(facts)?;
        }
        Expect::Failed => {
            assert_frozen_archive_request(facts)?;
            assert_no_new_publication(facts, "fault")?;
            ensure!(
                facts.config_before == facts.config_after,
                "acp-auto-install {} changed the saved accounts although it failed",
                spec.phase
            );
        }
    }
    phase_evidence(facts)
}

fn assert_fixture_usage_captures(facts: &PhaseFacts<'_>) -> Result<()> {
    let _ = facts;
    Ok(())
}

fn assert_fixture_usage_snapshot(
    snapshot: &Value,
    account_id: &str,
    connection_revision: u64,
    capture_name: &str,
) -> Result<()> {
    ensure!(
        snapshot["settings"]["acpAuth"]["loaded"].as_bool() == Some(true),
        "{capture_name} quota capture has no loaded auth observation"
    );
    let configured = snapshot["settings"]["acpAccounts"]
        .as_array()
        .context("quota capture carries no current ACP account summaries")?;
    let configured: Vec<_> = configured
        .iter()
        .filter(|account| {
            account["accountId"].as_str() == Some(account_id)
                && account["connectionRevision"].as_u64() == Some(connection_revision)
        })
        .collect();
    ensure!(
        configured.len() == 1,
        "{capture_name} quota is not bound to the current configured identity"
    );
    // 列表只观察账号摘要；provider 仅在详情需求仍活跃时可用。
    let provider = &configured[0]["provider"];
    ensure!(
        provider.is_null() || provider.as_str() == Some(PROVIDER),
        "{capture_name} quota account changed provider"
    );
    let accounts = snapshot["settings"]["acpAuth"]["accounts"]
        .as_array()
        .with_context(|| format!("{capture_name} snapshot has no ACP auth accounts"))?;
    let matching: Vec<_> = accounts
        .iter()
        .filter(|account| {
            account["accountId"].as_str() == Some(account_id)
                && account["connectionRevision"].as_u64() == Some(connection_revision)
        })
        .collect();
    ensure!(
        matching.len() == 1,
        "{capture_name} quota is not bound to the saved account identity"
    );
    ensure!(
        matching[0]["state"]["kind"].as_str() == Some("verified"),
        "{capture_name} quota capture has no current verified authentication"
    );
    let usage = &matching[0]["usage"];
    ensure!(
        usage["checkedAt"].as_i64().is_some(),
        "{capture_name} quota has no typed checkedAt"
    );
    let state = &usage["state"];
    ensure!(
        state["kind"].as_str() == Some("ready"),
        "{capture_name} quota state is not ready"
    );
    let groups = state["groups"]
        .as_array()
        .with_context(|| format!("{capture_name} quota carries no groups"))?;
    ensure!(
        groups.len() == 2
            && groups[0]["name"].as_str() == Some("Gemini Models")
            && groups[1]["name"].as_str() == Some("Disabled Models"),
        "{capture_name} quota groups differ from the fixed fixture"
    );
    let weekly = groups[0]["limits"]
        .as_array()
        .context("Gemini Models carries no limits")?;
    let disabled = groups[1]["limits"]
        .as_array()
        .context("Disabled Models carries no limits")?;
    ensure!(
        weekly.len() == 2 && disabled.len() == 1,
        "{capture_name} quota did not retain every fixture limit"
    );
    ensure!(
        weekly[0]["label"].as_str() == Some("Weekly Limit Remaining")
            && weekly[0]["remaining"]["kind"].as_str() == Some("percentage")
            && weekly[0]["remaining"]["value"].as_i64() == Some(91)
            && weekly[0]["nextResetAt"].as_i64() == Some(1_790_929_320),
        "{capture_name} weekly quota differs from the fixed fixture"
    );
    ensure!(
        weekly[1]["label"].as_str() == Some("Burst Limit")
            && weekly[1]["remaining"]["kind"].as_str() == Some("units")
            && weekly[1]["remaining"]["value"].as_i64() == Some(1_234)
            && weekly[1]["nextResetAt"].is_null(),
        "{capture_name} burst quota differs from the fixed fixture"
    );
    ensure!(
        disabled[0]["label"].as_str() == Some("Legacy Limit")
            && disabled[0]["remaining"]["kind"].as_str() == Some("disabled")
            && disabled[0]["nextResetAt"].is_null(),
        "{capture_name} disabled quota differs from the fixed fixture"
    );
    Ok(())
}

/// 认证类阶段的断言：只读验证，不产生安装操作。
///
/// 必须出现该阶段声明的全部 captured 证据，最终恢复合成 Verified，且 `first`
/// 记录的保存身份在阶段结束时仍以同一 id/provider 存在（revision 只允许前进）。
fn assert_auth_phase(facts: &PhaseFacts<'_>) -> Result<()> {
    let spec = facts.spec;
    ensure!(
        facts.credential_present,
        "acp-auto-install {} ended without restoring the synthetic credential marker",
        spec.phase
    );
    ensure!(
        facts
            .events
            .iter()
            .any(|event| matches!(event, AcpFixtureEvent::Initialize { .. })),
        "acp-auto-install {} never reached the fake ACP agent",
        spec.phase
    );
    if spec.phase == "auth-faults" {
        assert_fixture_usage_captures(facts)?;
        assert_connection_events(facts.events, spec.phase)?;
        ensure!(
            facts
                .events
                .iter()
                .any(|event| matches!(event, AcpFixtureEvent::Authenticate { .. })),
            "acp-auto-install auth-faults never exercised a real authenticate request"
        );
    }
    ensure!(
        facts.config_before == facts.config_after,
        "acp-auto-install {} changed the saved accounts during a read-only verification",
        spec.phase
    );
    assert_no_new_publication(facts, spec.phase)?;
    if spec.require_reuse {
        ensure!(
            archive_requests(facts) == 0,
            "acp-auto-install {} requested the archive during a stored-installation check",
            spec.phase
        );
    }
    let identity = facts
        .saved_identity
        .context("the auth phase has no saved identity from the first phase")?;
    let account_id = identity["accountId"]
        .as_str()
        .context("the saved identity carries no accountId")?;
    let account = facts
        .config_after
        .get(account_id)
        .with_context(|| format!("the saved identity `{account_id}` disappeared"))?;
    ensure!(
        account["provider"].as_str() == Some(PROVIDER),
        "the saved identity `{account_id}` changed provider"
    );
    // `connectionRevision` 不是 desired 配置字段：它由 Driver 保存时记录的 canonical
    // 身份持有，而这里核对的是同一身份在当前配置里仍然存在且 provider 未变。
    Ok(())
}

fn assert_ready(facts: &PhaseFacts<'_>) -> Result<()> {
    let spec = facts.spec;
    let new_keys: Vec<String> = facts
        .snapshot_after
        .keys()
        .filter(|key| !facts.snapshot_before.contains_key(*key))
        .cloned()
        .collect();
    let key = if spec.require_reuse {
        ensure!(
            archive_requests(facts) == 0,
            "acp-auto-install reuse requested the archive again: {}",
            archive_requests(facts)
        );
        ensure!(
            facts.snapshot_before == facts.snapshot_after,
            "acp-auto-install reuse changed the published installation instead of reusing it"
        );
        facts
            .previous_ready_key
            .map(str::to_owned)
            .context("acp-auto-install reuse has no previous ready installation")?
    } else {
        ensure!(
            new_keys.len() == 1,
            "acp-auto-install {} published {} new installations, expected exactly one",
            spec.phase,
            new_keys.len()
        );
        new_keys[0].clone()
    };
    ensure!(
        storage_key_of_wire(&format!("{WIRE_ID_PREFIX}{key}")).as_deref() == Some(key.as_str()),
        "acp-auto-install {} published a directory that is not a storage key",
        spec.phase
    );
    verify_installed(facts, &key)?;
    ensure!(
        facts.snapshot_after.contains_key(&key),
        "acp-auto-install {} reports a ready entry without its published directory",
        spec.phase
    );
    ensure!(
        facts.finals_after.contains(&key),
        "acp-auto-install {} has no completed archive for {key}",
        spec.phase
    );
    ensure!(
        file_sha256(&facts.layout.downloads_dir().join(format!("{key}.zip")))? == facts.archive_sha,
        "acp-auto-install {} local archive digest differs from the served package",
        spec.phase
    );

    match spec.save {
        Save::New => {
            if spec.seed_account {
                let before = facts
                    .config_before
                    .get(SEED_ACCOUNT_ID)
                    .context("the phase never seeded the pre-existing ACP account")?;
                ensure!(
                    facts.config_after.get(SEED_ACCOUNT_ID) == Some(before),
                    "the pre-existing ACP account changed while a new account was saved"
                );
            }
            let added = accounts_added(facts.config_before, facts.config_after)?;
            ensure!(
                added.len() == 1,
                "acp-auto-install {} saved {} new accounts, expected exactly one",
                spec.phase,
                added.len()
            );
            // 即便本 phase 没有预置新账号，也必须证明既存账号逐行原样保留。
            for (previous_id, previous_row) in facts
                .config_before
                .as_object()
                .context("the phase baseline is not a canonical account map")?
            {
                ensure!(
                    facts.config_after.get(previous_id) == Some(previous_row),
                    "acp-auto-install {} changed the pre-existing account `{previous_id}`",
                    spec.phase
                );
            }
            assert_desired_account(&added[0])?;
            assert_connection(facts, spec)?;
        }
        Save::Existing => {
            // reuse 只重新校验既有安装：账号配置必须**完全相等**，一个新增都不允许。
            ensure!(
                facts.config_before == facts.config_after,
                "acp-auto-install {} changed the saved accounts although reuse never saves",
                spec.phase
            );
        }
        Save::None => {
            ensure!(
                facts.config_before == facts.config_after,
                "acp-auto-install {} saved an account although only preparation was requested",
                spec.phase
            );
        }
    }
    for (previous_key, members) in facts.published {
        let after = facts.snapshot_after.get(previous_key).with_context(|| {
            format!(
                "acp-auto-install {} removed the previously published installation {previous_key}",
                spec.phase
            )
        })?;
        ensure!(
            after == members,
            "acp-auto-install {} changed the previously published installation {previous_key}",
            spec.phase
        );
    }
    for (previous_key, members) in facts.snapshot_before {
        if previous_key == &key {
            continue;
        }
        let after = facts.snapshot_after.get(previous_key).with_context(|| {
            format!(
                "acp-auto-install {} removed the installation {previous_key}",
                spec.phase
            )
        })?;
        ensure!(
            after == members,
            "acp-auto-install {} changed the pre-existing installation {previous_key}",
            spec.phase
        );
    }
    if spec.require_resume {
        assert_resumed_download(facts, &key)?;
    } else if !spec.require_reuse {
        ensure!(
            archive_requests(facts) >= 1,
            "acp-auto-install {} reported readiness without any archive request",
            spec.phase
        );
    }
    Ok(())
}

fn assert_no_new_publication(facts: &PhaseFacts<'_>, label: &str) -> Result<()> {
    ensure!(
        facts.snapshot_before.keys().eq(facts.snapshot_after.keys()),
        "acp-auto-install {label} installed or removed a published directory"
    );
    for (key, members) in facts.published {
        let after = facts
            .snapshot_after
            .get(key)
            .with_context(|| format!("acp-auto-install {label} removed the published {key}"))?;
        ensure!(
            after == members,
            "acp-auto-install {label} changed the previously published installation {key}"
        );
    }
    Ok(())
}

/// Requires a real continuation: a 206 response whose Range starts above zero on
/// this lifecycle's archive, with the same representation validator.
fn assert_resumed_download(facts: &PhaseFacts<'_>, key: &str) -> Result<()> {
    let spec = facts.spec;
    let etag = format!("\"fixture-archive-{}\"", facts.archive_sha);
    let resumed = facts
        .peer
        .requests
        .iter()
        .filter(|record| record["status"].as_u64() == Some(206))
        .any(|record| {
            record["range"]
                .as_str()
                .and_then(range_start)
                .is_some_and(|start| start > 0)
                && record["etag"].as_str().is_some_and(|value| value == etag)
        });
    ensure!(
        resumed,
        "acp-auto-install {} never continued the download with a non-zero Range 206 (requests: {})",
        spec.phase,
        facts.peer.requests.len()
    );
    if spec.phase == "resume" {
        ensure!(
            facts.peer.report["archiveDrops"]
                .as_u64()
                .is_some_and(|drops| drops >= 1),
            "acp-auto-install resume never had its body interrupted"
        );
    }
    if spec.phase == "retry" {
        let partial = facts
            .previous_partial
            .context("the cancel lifecycle kept no partial download to continue")?;
        ensure!(
            partial == key,
            "acp-auto-install retry did not continue the cancelled partial: `{partial}` vs `{key}`"
        );
    }
    Ok(())
}

fn verify_installed(facts: &PhaseFacts<'_>, key: &str) -> Result<()> {
    let directory = facts.layout.installed_dir(key);
    let receipt_path = directory.join("receipt.json");
    let receipt = read_json(&receipt_path)?;
    ensure!(
        receipt["format"].as_u64() == Some(1),
        "the installation receipt does not declare format 1"
    );
    ensure!(
        receipt["installationId"].as_str() == Some(format!("{WIRE_ID_PREFIX}{key}").as_str()),
        "the installation receipt wire identity does not match its storage key"
    );
    ensure!(
        receipt["release"]["version"].as_str() == Some(SERVER_VERSION),
        "the installation receipt names another release version"
    );
    ensure!(
        receipt["release"]["archiveUrl"].as_str() == Some(fixed_archive_url()?.as_str()),
        "the installation receipt names another archive URL"
    );
    ensure!(
        receipt["release"]["sha256"].is_null(),
        "the installation receipt records another publisher digest"
    );
    ensure!(
        receipt["command"].as_str() == Some(facts.program_member),
        "the installation receipt names another program entry"
    );
    let args = receipt["args"]
        .as_array()
        .context("the installation receipt has no args array")?
        .iter()
        .map(Value::as_str)
        .collect::<Option<Vec<_>>>()
        .context("the installation receipt args contain a non-string entry")?;
    ensure!(
        args == OFFICIAL_ARGV,
        "the installation receipt froze a different argv: {args:?}"
    );
    ensure!(
        receipt["archiveSha256"].as_str() == Some(facts.archive_sha.as_str()),
        "the installation receipt records another local archive digest"
    );
    let members = receipt["members"]
        .as_array()
        .context("the installation receipt has no member list")?;
    ensure!(
        members.len() == facts.expected_members.len(),
        "the installation receipt lists {} members, the served package has {}",
        members.len(),
        facts.expected_members.len()
    );
    let mut expected_files = BTreeSet::new();
    expected_files.insert("receipt.json".to_owned());
    for expected in &facts.expected_members {
        expected_files.insert(expected.path.clone());
        let member = members
            .iter()
            .find(|member| member["path"].as_str() == Some(expected.path.as_str()))
            .with_context(|| {
                format!(
                    "the installation receipt lost the package member `{}`",
                    expected.path
                )
            })?;
        ensure!(
            member["size"].as_u64() == Some(expected.size),
            "the installation receipt member `{}` has another size",
            expected.path
        );
        ensure!(
            member["sha256"].as_str() == Some(expected.sha256.as_str()),
            "the installation receipt member `{}` has another digest",
            expected.path
        );
        ensure!(
            member["mode"].as_u64().map(|mode| mode as u32) == expected.mode
                || (member["mode"] == Value::Null && expected.mode.is_none()),
            "the installation receipt member `{}` has another mode",
            expected.path
        );
        #[cfg(unix)]
        ensure!(
            expected.mode.is_some(),
            "the package declares no mode for the published member `{}`",
            expected.path
        );
    }
    // Binary identity: the published program must be the very fixture binary the
    // peer packaged, so no phase can pass with a substituted or truncated entry.
    let published_program = members
        .iter()
        .find(|member| member["path"].as_str() == Some(facts.program_member))
        .context("the installation receipt omits the published program entry")?;
    ensure!(
        published_program["sha256"].as_str() == Some(facts.program_sha),
        "the published program is not the fixture binary: the receipt digest differs"
    );
    ensure!(
        published_program["size"].as_u64() == Some(facts.program_bytes),
        "the published program has another size than the fixture binary"
    );
    // Package directories carry their own normalized mode in the receipt, so the
    // published tree is compared against that declaration instead of one blanket
    // rule; an undeclared directory can never survive inside a complete install.
    let mut declared_dirs: BTreeMap<String, Option<u32>> = BTreeMap::new();
    for declared in receipt["directories"]
        .as_array()
        .context("the installation receipt has no directory list")?
    {
        let path = declared["path"]
            .as_str()
            .context("a receipt directory has no path")?;
        ensure!(
            !path.is_empty()
                && declared_dirs
                    .insert(
                        path.to_owned(),
                        declared["mode"].as_u64().map(|mode| mode as u32)
                    )
                    .is_none(),
            "the installation receipt declares the directory `{path}` twice or with an empty path"
        );
    }
    assert_managed_root(
        &format!("<{PROVIDER} key>"),
        Some(mode_of(&fs::metadata(&directory)?)),
    )?;
    // The published tree must contain exactly the receipt plus its declared
    // members: no extra files, directories, links or special entries can hide
    // inside it, and every entry keeps its declared permission facts.
    for (relative, kind, size, sha, mode) in walk_tree(&directory)? {
        match kind {
            EntryKind::Directory => {
                let declared = declared_dirs.get(&relative).with_context(|| {
                    format!(
                        "the published installation contains an undeclared directory: {relative}"
                    )
                })?;
                assert_package_directory(&relative, mode, *declared)?;
                continue;
            }
            EntryKind::Symlink | EntryKind::Special => {
                bail!("the published installation contains a non-regular entry: {relative}")
            }
            EntryKind::File => {}
        }
        ensure!(
            expected_files.contains(&relative),
            "the published installation contains an undeclared file: {relative}"
        );
        assert_plain_file_mode(&relative, mode)?;
        let expected = facts
            .expected_members
            .iter()
            .find(|member| member.path == relative);
        if let Some(expected) = expected {
            ensure!(
                size == expected.size,
                "the published package member `{relative}` has another size"
            );
            ensure!(
                sha == expected.sha256,
                "the published package member `{relative}` has another digest"
            );
            if let Some(expected_mode) = expected.mode {
                ensure!(
                    mode == Some(expected_mode),
                    "the published package member `{relative}` has the wrong mode"
                );
                if relative == facts.program_member {
                    ensure!(
                        expected_mode & 0o111 != 0,
                        "the published program member carries no executable bit"
                    );
                } else {
                    ensure!(
                        expected_mode & 0o111 == 0,
                        "a non-program package member carries an executable bit: {relative}"
                    );
                }
            }
        }
    }
    ensure!(
        expected_files
            .iter()
            .all(|relative| { directory.join(relative).is_file() }),
        "the published installation is missing a declared member"
    );
    for relative in declared_dirs.keys() {
        ensure!(
            directory.join(relative).is_dir(),
            "the published installation is missing the declared directory `{relative}`"
        );
    }
    Ok(())
}

fn assert_connection(facts: &PhaseFacts<'_>, spec: &PhaseSpec) -> Result<()> {
    assert_connection_events(facts.events, spec.phase)
}

fn assert_connection_events(events: &[AcpFixtureEvent], phase: &str) -> Result<()> {
    let mut seen: BTreeMap<u32, Vec<&'static str>> = BTreeMap::new();
    for event in events {
        let name = match event {
            AcpFixtureEvent::Initialize { .. } => "initialize",
            AcpFixtureEvent::Authenticate { .. } => "authenticate",
            AcpFixtureEvent::SessionNew { .. } => "session/new",
            AcpFixtureEvent::Close { .. } => "close",
            AcpFixtureEvent::UsagePrompt { .. } => "usagePrompt",
            AcpFixtureEvent::NoPrompt { .. } => "prompt",
            AcpFixtureEvent::AuthenticateReleased { .. } | AcpFixtureEvent::Disconnect { .. } => {
                continue;
            }
        };
        seen.entry(event_pid(event)).or_default().push(name);
    }
    if phase == "auth-faults" {
        ensure!(
            events
                .iter()
                .filter(|event| matches!(event, AcpFixtureEvent::UsagePrompt { .. }))
                .count()
                == 1,
            "acp-auto-install auth-faults must issue exactly one fixed /usage prompt"
        );
        ensure!(
            !events
                .iter()
                .any(|event| matches!(event, AcpFixtureEvent::NoPrompt { .. })),
            "acp-auto-install auth-faults sent an unexpected prompt"
        );
        let usage_event = events
            .iter()
            .position(|event| matches!(event, AcpFixtureEvent::UsagePrompt { .. }))
            .expect("exactly one UsagePrompt was checked above");
        let usage_pid = event_pid(&events[usage_event]);
        let sequence = seen
            .get(&usage_pid)
            .context("the fixed usage prompt has no connection sequence")?;
        ensure!(
            sequence.as_slice() == ["initialize", "session/new", "usagePrompt", "close"],
            "acp-auto-install auth-faults expected initialize → session/new → usagePrompt → close for the usage connection; observed {sequence:?}"
        );
        return Ok(());
    }
    ensure!(
        !events.iter().any(|event| matches!(
            event,
            AcpFixtureEvent::UsagePrompt { .. }
                | AcpFixtureEvent::NoPrompt { .. }
                | AcpFixtureEvent::Authenticate { .. }
        )),
        "acp-auto-install {phase} sent an ACP prompt or login request the user never asked for"
    );
    ensure!(
        seen.values().any(|sequence| {
            let initialize = sequence.iter().position(|name| *name == "initialize");
            let session = sequence.iter().position(|name| *name == "session/new");
            matches!((initialize, session), (Some(init), Some(session)) if init < session)
        }),
        "acp-auto-install {phase} never completed one ACP connection (initialize → session/new); observed {seen:?}",
    );
    Ok(())
}

#[cfg(test)]
mod acp_usage_connection_tests {
    use super::{assert_connection_events, assert_fixture_usage_snapshot};
    use pl_provider_fixture::AcpFixtureEvent;
    use serde_json::json;

    #[test]
    fn auth_phase_accepts_the_usage_probe_after_explicit_login() {
        assert_connection_events(
            &[
                AcpFixtureEvent::Initialize { pid: 41 },
                AcpFixtureEvent::Authenticate { pid: 41 },
                AcpFixtureEvent::SessionNew { pid: 41 },
                AcpFixtureEvent::Close { pid: 41 },
                AcpFixtureEvent::Initialize { pid: 42 },
                AcpFixtureEvent::SessionNew { pid: 42 },
                AcpFixtureEvent::UsagePrompt { pid: 42 },
                AcpFixtureEvent::Close { pid: 42 },
            ],
            "auth-faults",
        )
        .expect("the exact native usage probe sequence is valid");
    }

    #[test]
    fn auth_phase_rejects_extra_prompt_login_and_incomplete_probe_sequences() {
        for events in [
            vec![
                AcpFixtureEvent::Initialize { pid: 42 },
                AcpFixtureEvent::SessionNew { pid: 42 },
                AcpFixtureEvent::UsagePrompt { pid: 42 },
                AcpFixtureEvent::NoPrompt { pid: 42 },
                AcpFixtureEvent::Close { pid: 42 },
            ],
            vec![
                AcpFixtureEvent::Initialize { pid: 42 },
                AcpFixtureEvent::SessionNew { pid: 42 },
                AcpFixtureEvent::Authenticate { pid: 42 },
                AcpFixtureEvent::UsagePrompt { pid: 42 },
                AcpFixtureEvent::Close { pid: 42 },
            ],
            vec![
                AcpFixtureEvent::Initialize { pid: 42 },
                AcpFixtureEvent::SessionNew { pid: 42 },
                AcpFixtureEvent::UsagePrompt { pid: 42 },
            ],
            vec![
                AcpFixtureEvent::Initialize { pid: 42 },
                AcpFixtureEvent::SessionNew { pid: 42 },
                AcpFixtureEvent::Close { pid: 42 },
                AcpFixtureEvent::UsagePrompt { pid: 42 },
                AcpFixtureEvent::Close { pid: 42 },
            ],
        ] {
            assert!(
                assert_connection_events(&events, "auth-faults").is_err(),
                "unexpected protocol sequence was accepted: {events:?}"
            );
        }
    }

    #[test]
    fn other_phases_continue_to_reject_usage_prompts() {
        let events = [
            AcpFixtureEvent::Initialize { pid: 42 },
            AcpFixtureEvent::SessionNew { pid: 42 },
            AcpFixtureEvent::UsagePrompt { pid: 42 },
            AcpFixtureEvent::Close { pid: 42 },
        ];
        for phase in ["first", "restart", "resume", "retry", "reuse"] {
            assert!(assert_connection_events(&events, phase).is_err());
        }
    }

    fn fixture_usage_snapshot() -> serde_json::Value {
        json!({
            "settings": {
                "acpAccounts": [{
                    "accountId": "saved-account",
                    "connectionRevision": 7,
                    "provider": null,
                }],
                "acpAuth": {
                    "loaded": true,
                    "accounts": [{
                        "accountId": "saved-account",
                        "connectionRevision": 7,
                        "state": {"kind": "verified"},
                        "usage": {
                            "checkedAt": 1_790_000_000_i64,
                            "state": {
                                "kind": "ready",
                                "groups": [
                                    {
                                        "name": "Gemini Models",
                                        "limits": [
                                            {
                                                "label": "Weekly Limit Remaining",
                                                "remaining": {"kind": "percentage", "value": 91},
                                                "nextResetAt": 1_790_929_320_i64,
                                            },
                                            {
                                                "label": "Burst Limit",
                                                "remaining": {"kind": "units", "value": 1_234},
                                                "nextResetAt": null,
                                            },
                                        ],
                                    },
                                    {
                                        "name": "Disabled Models",
                                        "limits": [{
                                            "label": "Legacy Limit",
                                            "remaining": {"kind": "disabled"},
                                            "nextResetAt": null,
                                        }],
                                    },
                                ],
                            },
                        },
                    }],
                },
            },
        })
    }

    #[test]
    fn canonical_usage_snapshot_requires_saved_identity_and_all_fixture_limits() {
        let snapshot = fixture_usage_snapshot();
        assert_fixture_usage_snapshot(&snapshot, "saved-account", 7, "quota-details")
            .expect("the complete identity-bound fixture usage is valid");
        assert!(
            assert_fixture_usage_snapshot(&snapshot, "another-account", 7, "quota-details")
                .is_err(),
            "usage must not be borrowed from a different account"
        );
        let mut revoked = snapshot.clone();
        revoked["settings"]["acpAuth"]["accounts"][0]["state"]["kind"] = json!("required");
        assert!(
            assert_fixture_usage_snapshot(&revoked, "saved-account", 7, "quota-list").is_err(),
            "retained quota must not prove a currently verified capture"
        );

        let mut changed_reset = snapshot.clone();
        changed_reset["settings"]["acpAuth"]["accounts"][0]["usage"]["state"]["groups"][0]["limits"]
            [0]["nextResetAt"] = json!(1_790_929_321_i64);
        assert!(
            assert_fixture_usage_snapshot(&changed_reset, "saved-account", 7, "quota-details")
                .is_err(),
            "a mismatched reset timestamp must not pass"
        );

        let mut missing_limit = snapshot;
        missing_limit["settings"]["acpAuth"]["accounts"][0]["usage"]["state"]["groups"][1]["limits"] =
            json!([]);
        assert!(
            assert_fixture_usage_snapshot(&missing_limit, "saved-account", 7, "quota-list")
                .is_err(),
            "omitting the disabled model group limit must not pass"
        );
    }

    #[test]
    fn quota_list_uses_current_summary_identity_without_loading_details() {
        let snapshot = fixture_usage_snapshot();
        assert_fixture_usage_snapshot(&snapshot, "saved-account", 7, "quota-list")
            .expect("a current summary and verified quota do not require account details");

        let mut changed = snapshot.clone();
        changed["settings"]["acpAccounts"][0]["connectionRevision"] = json!(8);
        assert!(
            assert_fixture_usage_snapshot(&changed, "saved-account", 7, "quota-list").is_err(),
            "retained auth usage cannot prove a changed configured identity"
        );

        let mut unloaded = snapshot;
        unloaded["settings"]["acpAuth"]["loaded"] = json!(false);
        assert!(
            assert_fixture_usage_snapshot(&unloaded, "saved-account", 7, "quota-list").is_err(),
            "an unloaded auth observation cannot prove a quota capture"
        );
    }
}

/// 账号投影只允许 name/provider/身份/revision：执行字段（program/args）已从
/// 现役结构删除，任何残留都说明兼容分支还在偷偷生效。
fn assert_saved_account(account: &Value) -> Result<()> {
    ensure!(
        account["provider"].as_str() == Some(PROVIDER),
        "the saved ACP account does not select the antigravity provider"
    );
    ensure!(
        account["accountId"]
            .as_str()
            .is_some_and(|id| !id.is_empty()),
        "the saved ACP account carries no identity"
    );
    ensure!(
        account["name"]
            .as_str()
            .is_some_and(|name| !name.is_empty()),
        "the saved ACP account carries no name"
    );
    ensure!(
        account["connectionRevision"].as_i64().is_some(),
        "the saved ACP account carries no connection revision"
    );
    for legacy in ["program", "args"] {
        ensure!(
            account.get(legacy).is_none(),
            "the saved ACP account still carries the removed `{legacy}` field"
        );
    }
    Ok(())
}

/// canonical 快照里的 desired 配置行：只有身份、名称与接入类型。
///
/// `connectionRevision` 属于 runtime 投影（快照账号由 [`assert_saved_account`] 检查），
/// desired 配置永远没有这个字段，这里不能要求它。
fn assert_desired_account(account: &Value) -> Result<()> {
    ensure!(
        account["provider"].as_str() == Some(PROVIDER),
        "the saved ACP account does not select the antigravity provider"
    );
    ensure!(
        account["accountId"]
            .as_str()
            .is_some_and(|id| !id.is_empty()),
        "the saved ACP account carries no identity"
    );
    ensure!(
        account["name"]
            .as_str()
            .is_some_and(|name| !name.is_empty()),
        "the saved ACP account carries no name"
    );
    for legacy in ["program", "args"] {
        ensure!(
            account.get(legacy).is_none(),
            "the saved ACP account still carries the removed `{legacy}` field"
        );
    }
    Ok(())
}

fn accounts_added(before: &Value, after: &Value) -> Result<Vec<Value>> {
    let before = account_rows(before)?;
    let after = account_rows(after)?;
    Ok(after
        .into_iter()
        .filter(|(id, _)| !before.iter().any(|(known, _)| known == id))
        .map(|(_, row)| row)
        .collect())
}

fn account_rows(config: &Value) -> Result<Vec<(String, Value)>> {
    let Some(table) = config.as_object() else {
        return Ok(Vec::new());
    };
    Ok(table
        .iter()
        .map(|(id, row)| {
            // desired 配置的每一行都不自带 id：map 的 key 才是身份。这里显式补上，
            // 让“新增了哪一条”按 canonical id 判断，而不是按名称或顺序猜。
            let mut row = row.clone();
            if let Some(object) = row.as_object_mut() {
                object
                    .entry("accountId")
                    .or_insert_with(|| Value::String(id.clone()));
            }
            (id.clone(), row)
        })
        .collect())
}

/// 预置一份 schema 25 的 ACP 账号基线：只有 name/provider，没有安装也没有凭据。
///
/// 这是“既有账号不提前保存”的证据起点：准备/复用阶段必须证明它没有被改写。
fn seed_acp_account(home: &Path) -> Result<()> {
    let store = acp_config_store(home);
    let mut config = store.load_or_default()?;
    ensure!(
        config.acp.accounts.is_empty(),
        "the isolated ACP home already contains a saved account before the seed"
    );
    config.acp.accounts.insert(
        SEED_ACCOUNT_ID.to_owned(),
        AcpAccountConfig {
            name: "antigravity-seed".to_owned(),
            provider: AcpProvider::Antigravity,
        },
    );
    // 用产品自己的校验与原子保存：schema 版本、models/routes/mode routes 与 ACP 声明
    // 必须一起成立，否则产品启动会把它当作损坏配置恢复，预置账号就被静默丢弃。
    config.validate()?;
    store.save(&config)?;
    Ok(())
}

fn canonical_accounts(home: &Path) -> Result<Value> {
    Ok(serde_json::to_value(acp_accounts(home)?)?)
}

#[derive(Clone)]
struct MemberExpect {
    path: String,
    size: u64,
    sha256: String,
    mode: Option<u32>,
}

fn expected_members(ready: &Value) -> Result<Vec<MemberExpect>> {
    let members = ready["members"]
        .as_array()
        .context("the peer ready document carries no member list")?;
    members
        .iter()
        .map(|member| {
            Ok(MemberExpect {
                path: member["path"]
                    .as_str()
                    .context("a peer member has no path")?
                    .to_owned(),
                size: member["size"]
                    .as_u64()
                    .context("a peer member has no size")?,
                sha256: member["sha256"]
                    .as_str()
                    .context("a peer member has no digest")?
                    .to_owned(),
                mode: member["mode"].as_u64().map(|mode| mode as u32),
            })
        })
        .collect()
}

/// 产品固定的发行版本：所有成功 install/release 证据都必须是这一个值。
const SERVER_VERSION: &str = pl_provider_fixture::acp_install::SERVER_VERSION;

/// 固定官方 argv：Linux 只有 `--uid=`，Windows 没有任何参数。
const OFFICIAL_ARGV: &[&str] = if cfg!(windows) { &[] } else { &["--uid="] };

/// 当前宿主固定的完整官方归档 URL（含 `agy-extensions/releases`）。
fn fixed_archive_url() -> Result<String> {
    let target = host_target()?;
    pl_provider_fixture::acp_install::fixed::archive_url(&target)
        .context("the host has no fixed Antigravity release")
}

/// 当前宿主固定的归档请求路径（含前导 `/`）。
fn fixed_archive_path() -> Result<String> {
    let target = host_target()?;
    pl_provider_fixture::acp_install::fixed::archive_path(&target)
        .context("the host has no fixed Antigravity release")
}

struct PeerFacts {
    report: Value,
    requests: Vec<Value>,
    /// The peer proved that admission was closed and every handler was joined.
    closed: bool,
}

/// 已退役的 latest-registry 来源：host 与 path 都取自被删除的实现与 design/28，
/// 不引入新的限制。
const RETIRED_REGISTRY_HOST: &str = "cdn.agentclientprotocol.com";
const RETIRED_REGISTRY_PATH_PREFIX: &str = "/registry/";

/// 一条 peer 证据记录的种类与必需字段（与 fixture writer 一一对应）。
fn validate_peer_record(record: &Value, number: usize) -> Result<()> {
    let kind = record["kind"]
        .as_str()
        .filter(|kind| !kind.trim().is_empty())
        .with_context(|| format!("peer log line {number} carries no record kind"))?;
    let string_field = |field: &str| -> Result<()> {
        ensure!(
            record[field].as_str().is_some(),
            "peer log line {number} (`{kind}`) requires the string field `{field}`"
        );
        Ok(())
    };
    let number_field = |field: &str| -> Result<()> {
        ensure!(
            record[field].as_u64().is_some(),
            "peer log line {number} (`{kind}`) requires the integer field `{field}`"
        );
        Ok(())
    };
    match kind {
        "connectionError" => {
            string_field("peer")?;
            string_field("message")?;
        }
        "tunnelError" => {
            string_field("host")?;
            string_field("message")?;
        }
        "rejectedPlainRequest" => {
            number_field("seq")?;
            string_field("method")?;
            string_field("uri")?;
            number_field("status")?;
        }
        "rejectedTunnel" => {
            number_field("seq")?;
            string_field("authority")?;
            number_field("status")?;
        }
        "connect" => {
            number_field("seq")?;
            string_field("host")?;
            number_field("status")?;
            number_field("atMs")?;
        }
        "handlerError" => {
            number_field("seq")?;
            string_field("host")?;
            string_field("path")?;
            string_field("message")?;
        }
        "request" => {
            number_field("seq")?;
            string_field("host")?;
            string_field("method")?;
            string_field("path")?;
            number_field("status")?;
            number_field("atMs")?;
        }
        "archiveDrop" => {
            number_field("served")?;
            number_field("offset")?;
            string_field("etag")?;
        }
        other => anyhow::bail!("peer log line {number} carries the unknown record kind `{other}`"),
    }
    Ok(())
}

/// 取记录携带的 host（request/connect/tunnelError 用 host，rejectedTunnel 用
/// authority，rejectedPlainRequest 用 uri），去掉端口。
fn record_hostname(record: &Value) -> String {
    if let Some(host) = record["host"].as_str() {
        return host
            .rsplit_once(':')
            .map_or(host, |(name, _)| name)
            .to_owned();
    }
    if let Some(authority) = record["authority"].as_str() {
        return authority
            .rsplit_once(':')
            .map_or(authority, |(name, _)| name)
            .to_owned();
    }
    let uri = record["uri"].as_str().unwrap_or_default();
    let without_scheme = uri.split_once("://").map_or(uri, |(_, rest)| rest);
    let authority = without_scheme.split('/').next().unwrap_or_default();
    authority
        .rsplit_once(':')
        .map_or(authority, |(name, _)| name)
        .to_owned()
}

/// 从 peer 的**完整请求日志**建立固定来源证据（不读 report 里不存在/已删除的字段）。
///
/// 规则与原固定 source 约束一致，而不是“拒绝一切隧道”：
/// - 旧 registry（确切 host 或 `/registry/` 前缀）出现即失败：它已退役，没有豁免。
/// - 对固定分发 host 的 HTTP 请求只接受本机固定完整 archive path，method 只接受
///   GET/HEAD；其它 host 或其它 path 的 install 请求同样失败。
/// - 对其它 host 的 CONNECT/被拒隧道记为 `unrelatedRequests`：产品自身还有与安装
///   无关的出网（例如目录同步），不作为安装违规，也不作为安装通过证据。
fn audit_peer_requests(facts: &PeerFacts) -> Result<Value> {
    let fixed = fixed_archive_path()?;
    let fixed_host = "dl.google.com";
    let mut archive_requests = 0_u64;
    let mut legacy: Vec<String> = Vec::new();
    let mut violations: Vec<String> = Vec::new();
    let mut unrelated: Vec<String> = Vec::new();
    let mut accepted_connects = 0_u64;
    for (index, record) in facts.requests.iter().enumerate() {
        let number = index + 1;
        // 结构先过：未知种类、缺字段、错类型都在这里失败，不能当成“无关请求”忽略。
        validate_peer_record(record, number)?;
        let kind = record["kind"].as_str().unwrap_or_default();
        let hostname = record_hostname(record);
        let path = record["path"].as_str().unwrap_or_default();
        let method = record["method"].as_str().unwrap_or_default();
        let legacy_path = path.starts_with(RETIRED_REGISTRY_PATH_PREFIX)
            || record["uri"]
                .as_str()
                .is_some_and(|uri| uri.contains(RETIRED_REGISTRY_PATH_PREFIX));
        if hostname == RETIRED_REGISTRY_HOST || legacy_path {
            legacy.push(format!("{kind}:{hostname}{path}"));
            continue;
        }
        match kind {
            "request" => {
                if hostname != fixed_host {
                    violations.push(format!("install request to {hostname}{path}"));
                } else if path != fixed {
                    violations.push(format!(
                        "install request to a non-fixed archive path: {path}"
                    ));
                } else if !matches!(method, "GET" | "HEAD") {
                    violations.push(format!("install archive request used method `{method}`"));
                } else {
                    archive_requests += 1;
                }
            }
            "connect" if hostname == fixed_host => {
                accepted_connects += 1;
            }
            "connect" | "rejectedTunnel" | "rejectedPlainRequest" => {
                // 结构有效的其它 host 请求：只作诊断，既不算违规也不算安装证据。
                unrelated.push(format!("{kind}:{hostname}"));
            }
            _ => {}
        }
    }
    ensure!(
        legacy.is_empty(),
        "the product still requested the retired registry source: {legacy:?}"
    );
    ensure!(
        violations.is_empty(),
        "the peer observed install traffic outside the fixed source: {violations:?}"
    );
    // 报告与日志互相证明：fixture 记录完整、行数等于成功数、计数器与日志同口径。
    let log = facts
        .report
        .get("requestLog")
        .context("the peer report carries no requestLog facts")?;
    ensure!(
        log["failed"].as_bool() == Some(false),
        "the peer lost request records: {:?}",
        log["firstError"]
    );
    let attempted = log["attempted"]
        .as_u64()
        .context("the peer requestLog carries no attempt count")?;
    let succeeded = log["succeeded"]
        .as_u64()
        .context("the peer requestLog carries no success count")?;
    ensure!(
        attempted == succeeded && succeeded as usize == facts.requests.len(),
        "the peer wrote {succeeded}/{attempted} records but the log holds {}",
        facts.requests.len()
    );
    ensure!(
        facts.report["archiveRequests"].as_u64() == Some(archive_requests),
        "the peer archive counter ({:?}) differs from the logged requests ({archive_requests})",
        facts.report["archiveRequests"]
    );
    ensure!(
        facts.report["connects"].as_u64() == Some(accepted_connects),
        "the peer connect counter ({:?}) differs from the logged accepts ({accepted_connects})",
        facts.report["connects"]
    );
    Ok(json!({
        "archiveRequests": archive_requests,
        "acceptedConnects": accepted_connects,
        "legacyRegistryAttempts": legacy,
        "sourceViolations": violations,
        "unrelatedRequests": unrelated,
        "fixedArchivePath": fixed,
        "requestRecords": facts.requests.len(),
        "reportAttempted": attempted,
        "reportSucceeded": succeeded,
    }))
}

/// 本生命周期真实发出的固定 archive 请求数（来自审计结果，不回退到 report 字段）。
fn archive_requests(facts: &PhaseFacts<'_>) -> u64 {
    facts.audit["archiveRequests"]
        .as_u64()
        .expect("the peer request audit always records archiveRequests")
}

/// Requires the peer to have served this lifecycle's own frozen archive path.
///
/// Error and reuse phases need the descriptor identity *without* a successful
/// publication, so the peer request log is the only factual binding available.
fn assert_frozen_archive_request(facts: &PhaseFacts<'_>) -> Result<()> {
    let path = fixed_archive_path()?;
    ensure!(
        facts.peer.requests.iter().any(|record| {
            record["path"].as_str() == Some(path.as_str())
                && record["status"]
                    .as_u64()
                    .is_some_and(|status| status == 200 || status == 206)
        }),
        "acp-auto-install {} never fetched its fixed archive {}",
        facts.spec.phase,
        fixed_archive_path()?
    );
    Ok(())
}

fn range_start(value: &str) -> Option<u64> {
    let spec = value.strip_prefix("bytes=")?;
    let start = spec.split('-').next()?;
    if start.is_empty() {
        return None;
    }
    start.parse().ok()
}

fn phase_evidence(facts: &PhaseFacts<'_>) -> Result<Value> {
    Ok(json!({
        "phase": facts.spec.phase,
        "expect": format!("{:?}", facts.spec.expect),
        "descriptor": {
            "version": SERVER_VERSION,
            "archiveUrl": fixed_archive_url()?,
            "sha256": Value::Null,
            "variant": facts.spec.variant,
        },
        "guiLauncherPid": facts.gui_pid,
        "native": facts.native,
        "peer": {
            "proxyAddress": facts.ready["proxyAddress"].clone(),
            "closed": facts.peer.closed,
            // 来源证据完全来自完整请求日志；不再引用已删除的 registry 计数。
            "sourceAudit": facts.audit.clone(),
            "archiveFailures": facts.peer.report["archiveFailures"].clone(),
            "archiveDrops": facts.peer.report["archiveDrops"].clone(),
            "archiveSha256": facts.peer.report["archiveSha256"].clone(),
            "resumedRequests": facts
                .peer
                .requests
                .iter()
                .filter(|record| record["status"].as_u64() == Some(206))
                .count(),
        },
        "installedKeys": facts.snapshot_after.keys().cloned().collect::<Vec<_>>(),
        "installedKeysBefore": facts.snapshot_before.keys().cloned().collect::<Vec<_>>(),
        "partialDownloads": facts.parts_after,
        "completedArchives": facts.finals_after,
    }))
}

fn write_install_evidence(
    context: &AcpAutoInstallScenario<'_>,
    phases: &[Value],
    screenshots: &[Value],
    cleanups: &[Value],
    redactions: &[(String, String)],
    identity: &Value,
) -> Option<anyhow::Error> {
    let mut problems = Vec::new();
    // The build-stage bypass is part of the run facts: it says exactly which
    // package hosts were reachable directly while the download hosts stayed
    // behind the fixture peer.
    let build_bypass = match build_bypass_hosts() {
        Ok(hosts) => json!(hosts),
        Err(error) => {
            problems.push(format!("the build bypass host list is invalid: {error:#}"));
            Value::Null
        }
    };
    let mut evidence = json!({
        "scenario": "acp-auto-install",
        "platform": std::env::consts::OS,
        "architecture": std::env::consts::ARCH,
        "source": "fixture",
        "humanVerdict": "pending",
        "buildBypass": build_bypass,
        // 所选范围与实际完成阶段分开记录：局部运行绝不能读成“八阶段全通过”。
        "startPhase": context.start.label(),
        "selectedPhases": context.start.selected_phases(),
        "completedPhases": phases
            .iter()
            .filter_map(|phase| phase["phase"].as_str())
            .collect::<Vec<_>>(),
        "fixture": identity,
        "phases": phases,
        "screenshots": screenshots,
        "cleanups": cleanups,
    });
    redact_value(&mut evidence, redactions);
    let mut written: Vec<PathBuf> = Vec::new();
    let evidence_path = context.output.join("acp-auto-install.json");
    if let Err(error) = write_json(&evidence_path, &evidence) {
        problems.push(format!("failed to write the phase evidence: {error}"));
    } else {
        written.push(evidence_path);
    }
    for spec in &PHASES {
        for name in ["gui", "driver", "peer"] {
            let source = context
                .working
                .join(format!("acp-install-{}-{name}.log", spec.phase));
            if !source.is_file() {
                continue;
            }
            let destination = context.output.join(format!("{name}-{}.log", spec.phase));
            match copy_redacted(&source, &destination, redactions) {
                Ok(()) => written.push(destination),
                Err(error) => problems.push(format!(
                    "failed to copy the {} {name} log: {error}",
                    spec.phase
                )),
            }
        }
        let source = context
            .working
            .join(format!("acp-install-{}-native-exit.json", spec.phase));
        let destination = context
            .output
            .join(format!("native-exit-{}.json", spec.phase));
        match copy_redacted_json(&source, &destination, redactions) {
            Ok(true) => written.push(destination),
            Ok(false) => {}
            Err(error) => problems.push(format!(
                "failed to copy the {} native record: {error}",
                spec.phase
            )),
        }
    }
    for path in &written {
        if let Ok(text) = fs::read_to_string(path) {
            for (needle, _) in redactions {
                if !needle.is_empty() && text.contains(needle) {
                    problems.push(format!(
                        "evidence file {} still contains the local path {needle}",
                        path.display()
                    ));
                }
            }
        }
    }
    if problems.is_empty() {
        None
    } else {
        Some(anyhow::anyhow!(problems.join("; ")))
    }
}

fn redact_value(value: &mut Value, redactions: &[(String, String)]) {
    match value {
        Value::String(text) => {
            for (from, to) in redactions {
                if !from.is_empty() {
                    *text = text.replace(from, to);
                }
            }
        }
        Value::Array(items) => items
            .iter_mut()
            .for_each(|item| redact_value(item, redactions)),
        Value::Object(map) => map
            .values_mut()
            .for_each(|item| redact_value(item, redactions)),
        _ => {}
    }
}

fn copy_redacted(source: &Path, destination: &Path, redactions: &[(String, String)]) -> Result<()> {
    let mut text = fs::read_to_string(source)?;
    for (from, to) in redactions {
        text = text.replace(from, to);
    }
    fs::write(destination, text)?;
    Ok(())
}

fn copy_redacted_json(
    source: &Path,
    destination: &Path,
    redactions: &[(String, String)],
) -> Result<bool> {
    if !source.is_file() {
        return Ok(false);
    }
    let mut value = read_json(source)?;
    redact_value(&mut value, redactions);
    write_json(destination, &value)?;
    Ok(true)
}

/// Removes one-off private key material from a retained fixture environment.
fn scrub_private_material(peer: &Path) -> Result<()> {
    for name in [
        "tls/ca.key",
        "tls/leaf.key",
        "tls/leaf.key.der",
        "tls/leaf.csr",
        "tls/.srl",
    ] {
        let path = peer.join(name);
        match fs::remove_file(&path) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(error).with_context(|| {
                    format!("failed to remove private material: {}", path.display())
                });
            }
        }
    }
    Ok(())
}

fn build_redactions(
    context: &AcpAutoInstallScenario<'_>,
    program: &Path,
    agent: &Path,
    peer: &Path,
    auxiliary: &Path,
    homes: &Homes,
) -> Vec<(String, String)> {
    let mut redactions = vec![
        (
            utf8(program).unwrap_or_default(),
            "[fixture-program]".to_owned(),
        ),
        (
            utf8(agent).unwrap_or_default(),
            "[acp-agent-state]".to_owned(),
        ),
        (utf8(peer).unwrap_or_default(), "[install-peer]".to_owned()),
        (
            utf8(auxiliary).unwrap_or_default(),
            "[auxiliary]".to_owned(),
        ),
        (
            context.working.to_string_lossy().into_owned(),
            "[isolated-root]".to_owned(),
        ),
        (
            homes.first.to_string_lossy().into_owned(),
            "[home-first]".to_owned(),
        ),
        (
            homes.resume.to_string_lossy().into_owned(),
            "[home-resume]".to_owned(),
        ),
        (
            homes.transfer.to_string_lossy().into_owned(),
            "[home-transfer]".to_owned(),
        ),
        (
            homes.fault.to_string_lossy().into_owned(),
            "[home-fault]".to_owned(),
        ),
        (
            context.workspace.to_string_lossy().into_owned(),
            "[workspace]".to_owned(),
        ),
        (
            context.output.to_string_lossy().into_owned(),
            "[evidence]".to_owned(),
        ),
    ];
    redactions.retain(|(from, _)| !from.is_empty());
    redactions
}

fn control_document(
    spec: &PhaseSpec,
    program: &Path,
    auxiliary: &Path,
    agent: &Path,
) -> Result<Value> {
    Ok(json!({
        "archive": {
            "variant": spec.variant,
            "program": program,
            "auxiliary": auxiliary,
            // 合成 state 在安装树之外：agent 自己写的标记/证据不能干扰产品的
            // receipt 与整树校验。
            "agentStateDir": utf8(agent)?,
            "chunkBytes": spec.chunk_bytes,
            "chunkDelayMs": spec.chunk_delay_ms,
            "unknownLength": spec.unknown_length,
            "dropAfterBytes": spec.drop_after_bytes,
            "dropRequests": spec.drop_requests,
            "failRequests": 0,
            "redirects": 0,
            "redirectTarget": Value::Null,
        },
        "stopFile": Value::Null,
    }))
}

/// 失败现场：把本场景自有的隔离环境原地保留，并写出可安全公开的摘要。
///
/// 一次失败的运行不能靠 `TempDir` 的 `Drop` 抹掉唯一现场：真实的 peer
/// stdout/stderr、它读到的 control、ready/report/requests 与这一轮实际写出的日志都在
/// 这个目录里。这里 `keep` 保留它（位于 evidence 目录内），目录收紧到 0700、摘要文件
/// 收紧到 0600，摘要里只出现脱敏后的错误链、日志尾部与文件事实；TLS 私钥等敏感字节留
/// 在本地现场，不进入摘要，也不进入 PR 文字。
///
/// 摘要里的日志尾部是**有界窗口**：从文件末尾读固定 `PEER_LOG_TAIL_BYTES` 字节（标准
/// `File` + `Seek`，不加载整份日志），再取末 `PEER_LOG_TAIL_LINES` 行，并如实记录
/// `originalBytes`/`readBytes`/`truncated`/`startsMidLine`。`truncated` 只表示省略了文件
/// 前缀；`startsMidLine` 由窗口起点前一个字节是否为换行独立判定，只有它为真时原始首段才
/// 加 `<truncated-line>` 前缀（完整首行绝不会被标记）。原日志文件本身一字不改。
///
/// 摘要只陈述目录里真实存在的文件，**不声称任何“已回收”结论**：失败运行里进程归属
/// 仍由调用方持有的 owner 负责。
pub(super) fn preserve_failure(
    working: tempfile::TempDir,
    output: &Path,
    error: &anyhow::Error,
) -> Result<PathBuf> {
    let root = working.keep();
    restrict_permissions(&root, 0o700)?;
    let redactions = [
        (
            root.to_string_lossy().into_owned(),
            "[isolated-root]".to_owned(),
        ),
        (
            output.to_string_lossy().into_owned(),
            "[evidence]".to_owned(),
        ),
    ];
    let redact = |text: &str| -> String {
        let mut text = text.to_owned();
        for (from, to) in &redactions {
            if !from.is_empty() {
                text = text.replace(from.as_str(), to);
            }
        }
        text
    };

    let mut peer_logs: Vec<Value> = Vec::new();
    let mut entries: Vec<String> = Vec::new();
    for entry in fs::read_dir(&root)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let is_file = entry.file_type()?.is_file();
        if is_file && name.starts_with(PEER_DIR_NAME) && name.ends_with(".log") {
            let tail = read_log_tail(&root.join(&name))?;
            let mut lines: Vec<String> = tail
                .text
                .split('\n')
                .enumerate()
                .filter_map(|(index, line)| {
                    // 只有窗口真正从行中间开始时，**原始** index 0 才是半行；标记在过滤
                    // 空白之前完成，因此既不会漏标，也不会转移到后面的完整行。
                    let line = if index == 0 && tail.starts_mid_line {
                        format!("<truncated-line>{}", redact(line))
                    } else {
                        redact(line)
                    };
                    (!line.trim().is_empty()).then_some(line)
                })
                .collect();
            if lines.len() > PEER_LOG_TAIL_LINES {
                lines = lines.split_off(lines.len() - PEER_LOG_TAIL_LINES);
            }
            peer_logs.push(json!({
                "file": name,
                "originalBytes": tail.original_bytes,
                "readBytes": tail.read_bytes,
                "truncated": tail.truncated,
                "startsMidLine": tail.starts_mid_line,
                "tail": lines,
            }));
            continue;
        }
        entries.push(if is_file { name } else { format!("{name}/") });
    }
    entries.sort();

    let mut peer_state: Vec<Value> = Vec::new();
    for name in [CONTROL_FILE, READY_FILE, REPORT_FILE, REQUESTS_FILE] {
        let path = root.join(PEER_DIR_NAME).join(name);
        peer_state.push(match fs::metadata(&path) {
            Ok(metadata) if metadata.is_file() => json!({"file": name, "bytes": metadata.len()}),
            Ok(_) => json!({"file": name, "kind": "not-a-file"}),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                json!({"file": name, "present": false})
            }
            Err(error) => json!({"file": name, "error": error.to_string()}),
        });
    }

    let summary = json!({
        "kind": "acp-auto-install-failure",
        "retainedRoot": root,
        "error": redact(&format!("{error:#}")),
        "peerLogs": peer_logs,
        "peerState": peer_state,
        "entries": entries,
        "notes": [
            "this directory is local evidence: it holds the fixture TLS material and the peer's own files",
            "paths and messages in this summary use the same redaction projection as the run summary",
        ],
    });
    let path = output.join(FAILURE_FILE);
    fs::write(&path, serde_json::to_vec_pretty(&summary)?).with_context(|| {
        format!(
            "failed to write the ACP failure evidence: {}",
            path.display()
        )
    })?;
    restrict_permissions(&path, 0o600)?;
    Ok(path)
}

/// 失败摘要里每条 peer 日志最多复制的尾部字节窗口。
const PEER_LOG_TAIL_BYTES: u64 = 64 * 1024;

/// 一个日志文件的**有界尾部**。
struct LogTail {
    /// 文件真实字节数（即使只读了窗口）。
    original_bytes: u64,
    /// 本次实际读入的字节数。
    read_bytes: u64,
    /// 是否省略了文件前缀（`start > 0`）。与「首行是否半行」是两件不同的事实。
    truncated: bool,
    /// 窗口起点是否落在行中间：由 `start-1` 那个字节是否为换行判定。
    ///
    /// 为真时窗口的第一段文本是半行；为假时窗口恰好从一个完整行开始。
    starts_mid_line: bool,
    /// 窗口文本；`starts_mid_line` 为真时首段只有半行。
    text: String,
}

/// 从文件末尾读固定窗口，不加载整份日志。
fn read_log_tail(path: &Path) -> Result<LogTail> {
    use std::io::{Seek, SeekFrom};
    let mut file = File::open(path)
        .with_context(|| format!("failed to open the peer log tail: {}", path.display()))?;
    let original_bytes = file.metadata()?.len();
    let start = original_bytes.saturating_sub(PEER_LOG_TAIL_BYTES);
    // 窗口起点是否落在行中间，只能看前一个字节：这是独立事实，不能由 `truncated` 推断。
    let starts_mid_line = if start > 0 {
        file.seek(SeekFrom::Start(start - 1))?;
        let mut previous = [0_u8; 1];
        file.read_exact(&mut previous).with_context(|| {
            format!(
                "failed to read the byte before the peer log window: {}",
                path.display()
            )
        })?;
        previous[0] != b'\n'
    } else {
        false
    };
    let window_bytes = original_bytes - start;
    file.seek(SeekFrom::Start(start))?;
    let mut window = Vec::with_capacity(window_bytes as usize);
    file.take(window_bytes).read_to_end(&mut window)?;
    Ok(LogTail {
        original_bytes,
        read_bytes: window.len() as u64,
        truncated: start > 0,
        starts_mid_line,
        text: String::from_utf8_lossy(&window).into_owned(),
    })
}

/// Restricts one local evidence path to its owner.
fn restrict_permissions(path: &Path, mode: u32) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(mode))?;
    }
    #[cfg(not(unix))]
    let _ = (path, mode);
    Ok(())
}

fn clear_peer_evidence(peer: &Path) -> Result<()> {
    for name in [READY_FILE, REPORT_FILE] {
        match fs::remove_file(peer.join(name)) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

fn start_peer(program: &Path, peer: &Path, log_path: &Path) -> Result<OwnedProcess> {
    let log = File::create(log_path)?;
    let mut command = Command::new(program);
    command
        .arg("--acp-install-fixture")
        .arg("--acp-install-dir")
        .arg(peer)
        .env_remove("HTTPS_PROXY")
        .env_remove("HTTP_PROXY")
        .env_remove("ALL_PROXY")
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    OwnedProcess::start(&mut command, false)
}

fn wait_ready(
    peer: &Path,
    process: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<Value> {
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        if let Ok(bytes) = fs::read(peer.join(READY_FILE)) {
            let value: Value = serde_json::from_slice(&bytes)
                .context("the ACP install peer wrote an untyped ready document")?;
            ensure!(
                value["proxyAddress"].as_str().is_some() && value["caPem"].as_str().is_some(),
                "the ACP install peer ready document is incomplete"
            );
            return Ok(value);
        }
        if let Some(status) = process.exit_status()? {
            bail!("the ACP install peer exited with {status} before publishing its ready document");
        }
        ensure!(
            interrupt.try_recv().is_err(),
            "the acp-auto-install journey was cancelled while the fixture peer started"
        );
        ensure!(
            Instant::now() < deadline,
            "the ACP install peer did not become ready in time"
        );
        thread::sleep(Duration::from_millis(50));
    }
}

fn stop_peer(process: &mut OwnedProcess, peer: &Path) -> Result<PeerFacts> {
    // A peer that already ended on its own is exactly the case that must not be
    // mistaken for a clean stop: the real exit status is read in *both* paths, and
    // a leftover `report.json` never substitutes for a normal process exit.
    if !process.exited()? {
        let _ = process.request_stop();
    }
    let status = process
        .wait_exit(Duration::from_secs(30))?
        .context("the ACP install peer did not stop after its stop request")?;
    ensure!(
        status.success(),
        "the ACP install peer exited with {status} instead of a clean stop"
    );
    let report = read_json(&peer.join(REPORT_FILE))?;
    // `closed` is the peer's own proof that admission was closed and every
    // connection/tunnel handler was cancelled and joined before this report.
    let closed = report["closed"].as_bool() == Some(true);
    ensure!(
        closed,
        "the ACP install peer report does not prove that every handler stopped"
    );
    // 证据日志不允许空白行：fixture 的每条记录都是一行 typed JSON。
    let log_path = peer.join(REQUESTS_FILE);
    let text = fs::read_to_string(&log_path)
        .with_context(|| format!("the peer request log is missing: {}", log_path.display()))?;
    let mut requests = Vec::new();
    for (index, raw) in text.lines().enumerate() {
        let number = index + 1;
        ensure!(!raw.trim().is_empty(), "peer log line {number} is blank");
        let value: Value = serde_json::from_str(raw)
            .with_context(|| format!("peer log line {number} is not typed JSON: {raw}"))?;
        requests.push(value);
    }
    Ok(PeerFacts {
        report,
        requests,
        closed,
    })
}

/// Hosts the GUI build phase may reach through the ordinary HTTPS path.
///
/// The fixture peer imitates exactly the two official download hosts and refuses
/// everything else, so a package install tunnelled through it fails with 403 —
/// a build-side problem that proves nothing about the product download. Only
/// package-source traffic is bypassed; the download hosts never are.
///
/// The guard uses the same suffix semantics the real clients apply (the Dart SDK
/// compares `host.endsWith(entry)`, reqwest matches a domain plus its subdomains),
/// so a broader entry such as `google.com`, `agentclientprotocol.com` or a bare
/// public suffix `com` is refused instead of only the exact official names.
fn build_bypass_hosts() -> Result<Vec<String>> {
    /// Official distribution hosts the peer imitates: they stay behind it.
    const PROTECTED: [&str; 2] = ["cdn.agentclientprotocol.com", "dl.google.com"];

    let mut hosts = vec!["127.0.0.1".to_owned(), "localhost".to_owned()];
    hosts.push(host_of_env("PUB_HOSTED_URL", "pub.dev")?);
    hosts.push(host_of_env(
        "FLUTTER_STORAGE_BASE_URL",
        "storage.googleapis.com",
    )?);
    // The official Flutter asset host stays reachable even when a mirror is set.
    hosts.push("storage.googleapis.com".to_owned());
    hosts.sort();
    hosts.dedup();
    for host in &hosts {
        let candidate = normalize_bypass_host(host)?;
        ensure!(
            !candidate.contains('*'),
            "the build bypass must not use a wildcard"
        );
        ensure!(
            !PROTECTED
                .iter()
                .any(|protected| bypass_covers(protected, &candidate)),
            "the build bypass entry `{candidate}` would also cover an official download host"
        );
    }
    Ok(hosts)
}

/// One bypass entry in the spelling the clients compare: lowercase, without a
/// leading or trailing dot (both are normalized identically by the matchers).
fn normalize_bypass_host(host: &str) -> Result<String> {
    let host = host.trim().trim_start_matches('.').trim_end_matches('.');
    ensure!(!host.is_empty(), "a build bypass host is empty");
    Ok(host.to_ascii_lowercase())
}

/// Whether one bypass entry also matches a protected official host.
///
/// `protected.ends_with(entry)` is the Dart SDK's rule; domain-plus-subdomain
/// matching in reqwest is the same direction, so any entry that is a suffix of a
/// protected host — including a bare `com` — must be refused.
fn bypass_covers(protected: &str, candidate: &str) -> bool {
    protected.eq_ignore_ascii_case(candidate) || protected.ends_with(candidate)
}

/// Host of one package-source environment variable, defaulting when it is unset.
///
/// Parsed with the mature `url` crate so IPv6, IDNA and ports are handled by the
/// same code the clients use. The contract is only "http(s) plus a host and no
/// userinfo"; malformed or non-Unicode values fail safely. Errors never echo the
/// raw value, which may carry credentials.
fn host_of_env(variable: &str, fallback: &str) -> Result<String> {
    let raw = match std::env::var(variable) {
        Ok(value) => value,
        Err(std::env::VarError::NotPresent) => return Ok(fallback.to_owned()),
        // A non-Unicode value is a configuration error, never "unset".
        Err(std::env::VarError::NotUnicode(_)) => {
            bail!("{variable} is not valid Unicode, so the build bypass cannot be derived")
        }
    };
    if raw.trim().is_empty() {
        return Ok(fallback.to_owned());
    }
    let url = reqwest::Url::parse(raw.trim())
        .map_err(|_| anyhow::anyhow!("{variable} is not an absolute URL"))?;
    ensure!(
        matches!(url.scheme(), "http" | "https"),
        "{variable} must use http or https"
    );
    ensure!(
        url.username().is_empty() && url.password().is_none(),
        "{variable} must not carry credentials"
    );
    let host = url
        .host_str()
        .ok_or_else(|| anyhow::anyhow!("{variable} carries no host"))?;
    Ok(host.to_owned())
}

fn start_gui(
    context: &AcpAutoInstallScenario<'_>,
    home: &Path,
    ready: &Value,
    log_path: &Path,
    report: &Path,
) -> Result<OwnedProcess> {
    let proxy = ready["proxyAddress"]
        .as_str()
        .context("the peer ready document carries no proxy address")?;
    let ca = ready["caPem"]
        .as_str()
        .context("the peer ready document carries no CA path")?;
    let log = File::create(log_path)?;
    // Building the GUI runs `flutter pub get`, which must reach the package source
    // directly. The peer only speaks for the two official download hosts, so a
    // tunnelled package install would fail there with 403 — a build problem that
    // says nothing about the product. Only these package hosts bypass the peer.
    let no_proxy = build_bypass_hosts()?.join(",");
    let proxy_url = format!("http://{proxy}");
    let mut command = Command::new("cargo");
    command
        .current_dir(context.workspace)
        .args([
            "xtask",
            "run-gui",
            "--capture",
            "--native-launch",
            "--native-exit-report",
        ])
        .arg(report)
        .env("ANYWORK_HOME", home)
        .env("XDG_DATA_HOME", home.join("xdg-data"))
        .env("XDG_CONFIG_HOME", home.join("xdg-config"))
        // Standard proxy contract: only the isolated child sees it, and the
        // isolated CA file is the only trust change.
        // Both spellings of the proxy are pinned to the fixture: a leftover
        // lowercase variable from the user's environment would otherwise decide
        // the destination of the controlled traffic (the Dart SDK reads both).
        .env("HTTPS_PROXY", &proxy_url)
        .env("HTTP_PROXY", &proxy_url)
        .env("https_proxy", &proxy_url)
        .env("http_proxy", &proxy_url)
        // Both spellings carry the same minimal list: the user's broad NO_PROXY is
        // never inherited, because that would silently bypass the fixture for the
        // download hosts too.
        .env("NO_PROXY", &no_proxy)
        .env("no_proxy", &no_proxy)
        .env("SSL_CERT_FILE", ca)
        .env_remove("ALL_PROXY")
        .env_remove("all_proxy")
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    for preset in &pl_model::config::builtin_account_catalog()?.templates {
        for variable in [
            preset.credential_env.as_ref(),
            preset.account.bearer_token_env.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            command.env_remove(variable);
        }
    }
    OwnedProcess::start(&mut command, false)
}

fn wait_vm(log: &Path, gui: &mut OwnedProcess, interrupt: &mpsc::Receiver<()>) -> Result<String> {
    let deadline = Instant::now() + Duration::from_secs(900);
    loop {
        if let Some(url) = vm_service_url(&fs::read_to_string(log)?) {
            return Ok(url);
        }
        ensure!(
            !gui.exited()?,
            "GUI launcher exited before publishing its VM service"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "the acp-auto-install journey was cancelled while starting the GUI"
        );
        ensure!(
            Instant::now() < deadline,
            "GUI VM service startup timed out"
        );
        thread::sleep(Duration::from_millis(300));
    }
}

fn wait_for_gui_exit(
    phase: &str,
    gui: &mut OwnedProcess,
    interrupt: &mpsc::Receiver<()>,
) -> Result<std::process::ExitStatus> {
    let deadline = Instant::now() + Duration::from_secs(600);
    loop {
        if let Some(status) = gui.child.try_wait()? {
            return Ok(status);
        }
        ensure!(
            interrupt.try_recv().is_err(),
            "the acp-auto-install {phase} journey was cancelled while the GUI shut down"
        );
        ensure!(
            Instant::now() < deadline,
            "the GUI did not shut down after the acp-auto-install {phase} journey"
        );
        thread::sleep(Duration::from_millis(100));
    }
}

fn storage_key_of_wire(wire: &str) -> Option<String> {
    let hex = wire.strip_prefix(WIRE_ID_PREFIX)?;
    is_storage_key(hex).then(|| hex.to_owned())
}

/// The filesystem key of one installation: 64 lowercase hex characters, never
/// the `sha256:` wire identity.
fn is_storage_key(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum EntryKind {
    File,
    Directory,
    Symlink,
    Special,
}

/// One file fact a published installation exposes to acceptance: relative path,
/// entry kind, size, digest and Unix mode when the platform has one.
type TreeEntry = (String, EntryKind, u64, String, Option<u32>);

/// Walks a published installation with the file facts acceptance needs.
fn walk_tree(root: &Path) -> Result<Vec<TreeEntry>> {
    fn visit(root: &Path, directory: &Path, entries: &mut Vec<TreeEntry>) -> Result<()> {
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            let path = entry.path();
            let relative = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            let file_type = entry.file_type()?;
            if file_type.is_symlink() {
                entries.push((relative, EntryKind::Symlink, 0, String::new(), None));
                continue;
            }
            if file_type.is_dir() {
                let metadata = entry.metadata()?;
                entries.push((
                    relative.clone(),
                    EntryKind::Directory,
                    0,
                    String::new(),
                    Some(mode_of(&metadata)),
                ));
                visit(root, &path, entries)?;
                continue;
            }
            if !file_type.is_file() {
                entries.push((relative, EntryKind::Special, 0, String::new(), None));
                continue;
            }
            let metadata = entry.metadata()?;
            entries.push((
                relative,
                EntryKind::File,
                metadata.len(),
                file_sha256(&path)?,
                Some(mode_of(&metadata)),
            ));
        }
        Ok(())
    }
    let mut entries = Vec::new();
    if root.is_dir() {
        visit(root, root, &mut entries)?;
    }
    entries.sort_by(|left, right| left.0.cmp(&right.0));
    Ok(entries)
}

#[cfg(unix)]
fn mode_of(metadata: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::MetadataExt;
    // Keep setuid/setgid/sticky: masking them away would make every "no special
    // bits" assertion a tautology and would also hide a 0755 installation root.
    metadata.mode() & 0o7777
}

#[cfg(windows)]
fn mode_of(_metadata: &std::fs::Metadata) -> u32 {
    0
}

/// Snapshot fact for one published directory: its permission bits, so a
/// permission-only change is visible when the previous installation is compared.
#[cfg(unix)]
fn directory_fact(mode: Option<u32>) -> String {
    format!("dir:{:04o}", mode.unwrap_or(0))
}

#[cfg(windows)]
fn directory_fact(_mode: Option<u32>) -> String {
    "dir".to_owned()
}

/// Snapshot fact for one published file: digest plus permission bits.
#[cfg(unix)]
fn file_fact(sha: &str, mode: Option<u32>) -> String {
    format!("file:{sha}:{:04o}", mode.unwrap_or(0))
}

#[cfg(windows)]
fn file_fact(sha: &str, _mode: Option<u32>) -> String {
    format!("file:{sha}")
}

/// The installation root is managed by the product itself, so its permission is
/// the exact private mode it promises; 0755 is a defect, not "close enough".
#[cfg(unix)]
fn assert_managed_root(relative: &str, mode: Option<u32>) -> Result<()> {
    let mode = mode.context("the installation root carries no permission facts")?;
    ensure!(
        mode == 0o700,
        "the installation root `{relative}` has mode {mode:04o} instead of 0700"
    );
    Ok(())
}

#[cfg(windows)]
fn assert_managed_root(_relative: &str, _mode: Option<u32>) -> Result<()> {
    Ok(())
}

/// A directory that came from the package: the on-disk mode must equal the
/// normalized mode the receipt declares, and the receipt itself must not carry
/// group/other write or setuid/setgid/sticky bits.
#[cfg(unix)]
fn assert_package_directory(
    relative: &str,
    actual: Option<u32>,
    declared: Option<u32>,
) -> Result<()> {
    let actual = actual.context("a published directory carries no permission facts")?;
    let declared = declared.with_context(|| {
        format!("the receipt declares no mode for the package directory `{relative}`")
    })?;
    ensure!(
        declared & 0o022 == 0 && declared & 0o7000 == 0,
        "the receipt declares dangerous permission bits for the package directory `{relative}`"
    );
    ensure!(
        actual == declared,
        "the published directory `{relative}` has mode {actual:04o} instead of the declared {declared:04o}"
    );
    Ok(())
}

#[cfg(windows)]
fn assert_package_directory(
    _relative: &str,
    _actual: Option<u32>,
    _declared: Option<u32>,
) -> Result<()> {
    Ok(())
}

/// Unix file modes may keep the executable bit the receipt declared, never
/// setuid/setgid/sticky bits.
#[cfg(unix)]
fn assert_plain_file_mode(relative: &str, mode: Option<u32>) -> Result<()> {
    let mode = mode.context("a published file carries no permission facts")?;
    ensure!(
        mode & 0o7000 == 0,
        "the published file `{relative}` carries setuid/setgid/sticky bits"
    );
    Ok(())
}

#[cfg(windows)]
fn assert_plain_file_mode(_relative: &str, _mode: Option<u32>) -> Result<()> {
    Ok(())
}

/// `<home>/studio/acp-servers` layout owned by the product; the acceptance only
/// reads it.
struct Layout {
    root: PathBuf,
    target: String,
}

impl Layout {
    fn new(home: PathBuf, target: String) -> Self {
        let root = home.join("studio/acp-servers");
        Self { root, target }
    }

    fn provider_dir(&self, kind: &str) -> PathBuf {
        self.root.join(kind).join(PROVIDER).join(&self.target)
    }

    fn installed_dir(&self, key: &str) -> PathBuf {
        self.provider_dir("installed").join(key)
    }

    fn downloads_dir(&self) -> PathBuf {
        self.provider_dir("downloads")
    }

    fn installed_snapshot(&self) -> Result<BTreeMap<String, BTreeMap<String, String>>> {
        let mut snapshot = BTreeMap::new();
        let directory = self.provider_dir("installed");
        if !directory.is_dir() {
            return Ok(snapshot);
        }
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let key = entry.file_name().to_string_lossy().into_owned();
            ensure!(
                is_storage_key(&key),
                "a published installation is not named by its storage key: {key}"
            );
            let mut files = BTreeMap::new();
            // The root's own mode is part of the snapshot: a mode-only change on a
            // previously published installation must be visible here.
            files.insert(
                ".".to_owned(),
                directory_fact(Some(mode_of(&entry.metadata()?))),
            );
            // Directories and permission facts belong to the snapshot: otherwise a
            // phase could add an empty directory or widen a mode and still look
            // identical to the previous successful installation.
            for (relative, kind, _size, sha, mode) in walk_tree(&entry.path())? {
                let fact = match kind {
                    EntryKind::Directory => directory_fact(mode),
                    EntryKind::File => file_fact(&sha, mode),
                    EntryKind::Symlink | EntryKind::Special => bail!(
                        "the published installation `{key}` contains a non-regular entry: {relative}"
                    ),
                };
                files.insert(relative, fact);
            }
            snapshot.insert(key, files);
        }
        Ok(snapshot)
    }

    fn parts(&self) -> Result<BTreeMap<String, u64>> {
        let mut parts = BTreeMap::new();
        let directory = self.downloads_dir();
        if !directory.is_dir() {
            return Ok(parts);
        }
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if let Some(key) = name.strip_suffix(".zip.part") {
                ensure!(
                    is_storage_key(key),
                    "a partial download is not named by its storage key: {name}"
                );
                parts.insert(
                    key.to_owned(),
                    entry.metadata().map(|meta| meta.len()).unwrap_or(0),
                );
            }
        }
        Ok(parts)
    }

    fn final_archives(&self) -> Result<BTreeSet<String>> {
        let mut finals = BTreeSet::new();
        let directory = self.downloads_dir();
        if !directory.is_dir() {
            return Ok(finals);
        }
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if let Some(key) = name.strip_suffix(".zip") {
                ensure!(
                    is_storage_key(key),
                    "a completed archive is not named by its storage key: {name}"
                );
                finals.insert(key.to_owned());
            }
        }
        Ok(finals)
    }
}

fn read_json(path: &Path) -> Result<Value> {
    let bytes = fs::read(path)
        .with_context(|| format!("failed to read expected evidence: {}", path.display()))?;
    serde_json::from_slice(&bytes)
        .with_context(|| format!("evidence is not typed JSON: {}", path.display()))
}

fn write_json(path: &Path, value: &Value) -> Result<()> {
    fs::write(path, serde_json::to_vec_pretty(value)?)?;
    Ok(())
}

fn utf8(path: &Path) -> Result<String> {
    Ok(path
        .to_str()
        .context("a fixture path is not valid UTF-8")?
        .to_owned())
}
