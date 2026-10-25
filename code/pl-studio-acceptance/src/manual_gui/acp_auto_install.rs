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
//! home and one GUI through `--native-launch`, then starts the single Driver
//! journey `test_driver/acp_install_journey.dart VM_URL OUTPUT_DIR PHASE`. The
//! journey owns the UI actions and its own summary; this module owns the
//! environment, the isolated trust setup and the factual checks on the real
//! `<home>/studio/acp-servers` tree, the peer request log, the canonical driver
//! snapshots and the native exit record.
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
/// Driver journey owned by the Client/Dart side.
const JOURNEY: &str = "test_driver/acp_install_journey.dart";
/// Provider document identity.
const PROVIDER: &str = "antigravity";
/// Program member named by the registry `cmd`.
const PROGRAM_MEMBER: &str = "agy_acp_server.par";
/// Wire installation identity prefix.
const WIRE_ID_PREFIX: &str = "sha256:";
/// The only capture that carries the canonical connected snapshot this harness
/// cross-checks for a saved account.
const CONNECTED_CAPTURE: &str = "connected";
/// 取消中瞬态截图的名字（可选证据，但记录后仍按严格事实核验）。
const CANCELLING_CAPTURE: &str = "cancelling";
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
        // Peer-side pacing only: a ~30 MB package needs a real, watchable download
        // window so the Driver captures the actual downloading stage.
        chunk_bytes: 65_536,
        chunk_delay_ms: 20,
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
            "nativeFormRenderedAndCancelledWithoutSaving",
            "authFaultsAccountsUnchanged",
        ],
        required_captures: &[
            "authenticating",
            "verified",
            "authentication-failed",
            "auth-cancelled",
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
        chunk_delay_ms: 20,
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
        chunk_delay_ms: 20,
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
    let mut screenshots: Vec<Value> = Vec::new();
    let mut cleanups: Vec<Value> = Vec::new();
    // 已发布账本按**实际 home** 归属：同一个固定 descriptor/storage key 出现在两个
    // 隔离 home 里是两个物理安装，跨 home 的“被删除/被改”结论没有意义。
    let mut published: BTreeMap<PathBuf, BTreeMap<String, BTreeMap<String, String>>> =
        BTreeMap::new();
    let mut saved_accounts: BTreeMap<&'static str, Value> = BTreeMap::new();
    let mut previous_partial: Option<String> = None;
    let mut previous_operation: Option<String> = None;
    let mut previous_cancel: Option<Value> = None;
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
            let driver_log = context
                .working
                .join(format!("acp-install-{}-driver.log", spec.phase));
            let report = context
                .working
                .join(format!("acp-install-{}-native-exit.json", spec.phase));
            let mut gui = start_gui(context, home, &ready, &gui_log, &report)?;
            let gui_pid = gui.child.id();
            let mut driver: Option<OwnedProcess> = None;
            let mut driver_pid: Option<u32> = None;
            // One owning block for the whole lifecycle: journey, native exit
            // record and its validation all run here, so every failure is
            // reclaimed by the same cleanup path instead of bypassing it.
            let outcome = (|| -> Result<Value> {
                let vm_url = wait_vm(&gui_log, &mut gui, context.interrupt)?;
                let fixture_state = spec.needs_agent_state.then_some(agent.as_path());
                let started =
                    start_journey(context, home, spec, &vm_url, &driver_log, fixture_state)?;
                driver_pid = Some(started.child.id());
                driver = Some(started);
                let active = driver
                    .as_mut()
                    .context("install Driver handle is missing")?;
                let driver_status = wait_for_driver(
                    spec.phase,
                    active,
                    &mut gui,
                    context.output,
                    context.interrupt,
                )?;
                ensure!(
                    driver_status.success(),
                    "acp-auto-install {} journey failed with {driver_status} at stage `{}`",
                    spec.phase,
                    summary_stage(context.output, spec.phase)
                );
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
                        driver.as_mut(),
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
            if let Some(active) = driver.as_mut() {
                active.mark_reaped();
            }
            drop(driver.take());
            drop(gui);
            let peer_facts = stop_peer(&mut peer_process, &peer)?;
            let audit = audit_peer_requests(&peer_facts)?;
            let summary = validate_summary(context.output, spec, &target, saved_identity.as_ref())?;
            screenshots.extend(summary["captures"].as_array().cloned().unwrap_or_default());
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
            let capture_facts = ConnectedCapture::load(context.output, &summary, spec.phase)?;

            // 只把当前 home 自己已核实的账本交给本阶段断言；其它 home 的安装既不能
            // 被要求出现在这里，也不影响这里的结论。
            let home_published = published.get(home).cloned().unwrap_or_default();
            let facts = PhaseFacts {
                spec,
                layout: &layout,
                ready: &ready,
                summary: &summary,
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
                capture: &capture_facts,
                previous_ready_key: last_ready_key.as_deref(),
                program_sha: &program_sha,
                program_bytes,
                credential_present,
                saved_identity: saved_identity.as_ref(),
                native,
                gui_pid,
                driver_pid,
            };
            if spec.saves_identity {
                let saved = summary["savedAccount"].as_object().with_context(|| {
                    format!(
                        "acp-auto-install {} saved no account identity in its summary",
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
                ensure!(
                    saved
                        .get("connectionRevision")
                        .and_then(Value::as_i64)
                        .is_some(),
                    "acp-auto-install {} recorded no saved connection revision",
                    spec.phase
                );
                saved_accounts.insert(spec.phase, summary["savedAccount"].clone());
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
            let next_cancel = (spec.expect == Expect::Cancelled)
                .then(|| summary.get("cancelledOperation").cloned())
                .flatten();
            let next_operation = next_cancel
                .as_ref()
                .and_then(|cancelled| cancelled["operationId"].as_str())
                .map(str::to_owned);
            drop(facts);
            if spec.expect == Expect::Cancelled {
                ensure!(
                    next_partial.is_some(),
                    "acp-auto-install cancel left no partial download to continue"
                );
                let cancelled = next_cancel
                    .as_ref()
                    .context("acp-auto-install cancel reported no cancelledOperation facts")?;
                assert_cancelled_release(cancelled, spec, &ready)?;
                previous_partial = next_partial;
                previous_operation = next_operation;
                previous_cancel = next_cancel;
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
    spec: &'a PhaseSpec,
    layout: &'a Layout,
    ready: &'a Value,
    summary: &'a Value,
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
    capture: &'a ConnectedCapture,
    previous_ready_key: Option<&'a str>,
    /// Digest and length of the fixture binary that is also the packaged program.
    program_sha: &'a str,
    program_bytes: u64,
    credential_present: bool,
    /// `first` 记录的保存身份；认证类阶段必须用它而不是“最后一项/同名”猜。
    saved_identity: Option<&'a Value>,
    native: Value,
    gui_pid: u32,
    driver_pid: Option<u32>,
}

fn assert_phase(facts: &PhaseFacts<'_>) -> Result<Value> {
    let spec = facts.spec;
    let captures = facts.summary["captures"]
        .as_array()
        .context("the journey summary carries no captures")?;
    for required in spec.required_captures {
        ensure!(
            captures
                .iter()
                .any(|capture| capture["name"].as_str() == Some(*required)),
            "acp-auto-install {} is missing the required capture `{required}`",
            spec.phase
        );
    }
    if spec.require_preparation_required {
        ensure!(
            captures
                .iter()
                .any(|capture| capture["name"].as_str() == Some("prepare-required")),
            "acp-auto-install {} never observed the preparation-required state",
            spec.phase
        );
    }
    match spec.expect {
        Expect::Ready => {
            let entry = install_entry(facts.summary)?;
            assert_ready(facts, entry)?
        }
        // 认证类 phase 的 summary.install 可以为空：它从未进入安装表单。
        Expect::Auth => assert_auth_phase(facts)?,
        Expect::Cancelled => {
            let entry = install_entry(facts.summary)?;
            ensure!(
                entry_phase(entry) == Some("cancelled"),
                "acp-auto-install cancel ended in another phase: {:?}",
                entry_phase(entry)
            );
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
            // The cancel evidence has no release of its own, so it is bound to this
            // lifecycle through the peer's frozen archive plus the shared operation.
            assert_frozen_archive_request(facts)?;
            // 取消中瞬态截图可选，但“是否观察到”必须与真实记录一致。
            assert_cancelling_observation(facts)?;
        }
        Expect::Failed => {
            let entry = install_entry(facts.summary)?;
            let expected = spec
                .fault_code
                .context("a failed lifecycle must declare its typed failure code")?;
            ensure!(
                entry_phase(entry) == Some("failed"),
                "acp-auto-install {} did not end in a typed product failure: {:?}",
                spec.phase,
                entry_phase(entry)
            );
            ensure!(
                entry_failure_code(entry) == Some(expected),
                "acp-auto-install {} reported failure `{:?}` instead of `{expected}`",
                spec.phase,
                entry_failure_code(entry)
            );
            ensure!(
                entry_failure_retryable(entry).is_some(),
                "acp-auto-install {} failure carries no retryable flag",
                spec.phase
            );
            // The failure must belong to this lifecycle's frozen archive, not to an
            // unrelated descriptor the peer happened to serve earlier.
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

/// 认证类阶段的断言：只读验证，不产生安装操作。
///
/// 必须出现该阶段声明的全部 captured 证据，最终恢复合成 Verified，且 `first`
/// 记录的保存身份在阶段结束时仍以同一 id/provider 存在（revision 只允许前进）。
fn assert_auth_phase(facts: &PhaseFacts<'_>) -> Result<()> {
    let spec = facts.spec;
    let captures = facts.summary["captures"]
        .as_array()
        .context("the auth phase summary carries no captures")?;
    for required in spec.required_captures {
        ensure!(
            captures
                .iter()
                .any(|capture| capture["name"].as_str() == Some(*required)),
            "acp-auto-install {} is missing the required capture `{required}`",
            spec.phase
        );
    }
    ensure!(
        facts
            .summary
            .get("failedChecks")
            .and_then(Value::as_array)
            .is_none_or(|failed| failed.is_empty()),
        "acp-auto-install {} reported failed checks: {:?}",
        spec.phase,
        facts.summary.get("failedChecks")
    );
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
    ensure!(
        identity["connectionRevision"].as_u64().is_some(),
        "the saved identity `{account_id}` carries no current connection revision"
    );
    Ok(())
}

fn assert_ready(facts: &PhaseFacts<'_>, entry: &Value) -> Result<()> {
    let spec = facts.spec;
    ensure!(
        entry_phase(entry) == Some("ready"),
        "acp-auto-install {} did not reach the ready phase: {:?}",
        spec.phase,
        entry_phase(entry)
    );
    let program = entry["program"]
        .as_str()
        .context("the ready entry carries no program")?;
    // 客户端投影不再携带 argv：账号/就绪 DTO 只有固定发行身份。argv 只在内部
    // receipt 里核对，见 [`verify_installed`]。
    let reused = entry["reused"].as_bool();
    ensure!(
        reused.is_some(),
        "acp-auto-install {} ready entry carries no reused flag",
        spec.phase
    );

    let new_keys: Vec<String> = facts
        .snapshot_after
        .keys()
        .filter(|key| !facts.snapshot_before.contains_key(*key))
        .cloned()
        .collect();
    let key = if spec.require_reuse {
        ensure!(
            reused == Some(true),
            "acp-auto-install reuse did not report `reused: true`"
        );
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
    let expected_program = facts.layout.installed_dir(&key).join(facts.program_member);
    ensure!(
        expected_program.to_string_lossy() == program,
        "acp-auto-install {} ready program is not the published entry: {program}",
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
            // savedAccount 必须就是这次唯一新增的身份，不能是别的行或旧 revision。
            let saved = facts
                .summary
                .get("savedAccount")
                .context("the summary recorded no saved account identity")?;
            ensure!(
                saved["accountId"].as_str() == added[0]["accountId"].as_str(),
                "the summary savedAccount id is not the only new account of this phase"
            );
            // `connectionRevision` 只是 runtime 投影事实，desired 配置里没有这个字段：
            // 必须用 Driver 同一帧的 canonical 快照核对，而不是从配置行里“读”出来。
            let saved_revision = saved["connectionRevision"]
                .as_u64()
                .context("the summary savedAccount carries no connection revision")?;
            let added_id = added[0]["accountId"]
                .as_str()
                .context("the newly saved account carries no identity")?;
            ensure!(
                facts.capture.settings_revision(added_id)? == saved_revision,
                "the summary savedAccount revision differs from the canonical settings account"
            );
            assert_desired_account(&added[0])?;
            facts.capture.assert_account()?;
            assert_connection(facts, spec)?;
            facts
                .capture
                .assert_auth_outcome(spec.phase, facts.credential_present)?;
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
        let cancelled = facts
            .previous_cancel
            .context("the cancel lifecycle reported no cancelledOperation facts")?;
        assert_cancelled_release(cancelled, spec, facts.ready)?;
        let operation = entry_operation(facts.summary)?.unwrap_or_default();
        ensure!(
            !operation.trim().is_empty(),
            "acp-auto-install retry reported no operation identity"
        );
        ensure!(
            facts
                .previous_operation
                .is_some_and(|previous| !previous.is_empty() && previous != operation),
            "acp-auto-install retry did not start a new operation after cancellation"
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
    let mut seen: BTreeMap<u32, Vec<&'static str>> = BTreeMap::new();
    for event in facts.events {
        let name = match event {
            AcpFixtureEvent::Initialize { .. } => "initialize",
            AcpFixtureEvent::Authenticate { .. } => "authenticate",
            AcpFixtureEvent::SessionNew { .. } => "session/new",
            AcpFixtureEvent::Close { .. } => "close",
            AcpFixtureEvent::NoPrompt { .. } => "prompt",
            AcpFixtureEvent::AuthenticateReleased { .. } | AcpFixtureEvent::Disconnect { .. } => {
                continue;
            }
        };
        seen.entry(event_pid(event)).or_default().push(name);
    }
    ensure!(
        !facts.events.iter().any(|event| matches!(
            event,
            AcpFixtureEvent::NoPrompt { .. } | AcpFixtureEvent::Authenticate { .. }
        )),
        "acp-auto-install {} sent an ACP prompt or login request the user never asked for",
        spec.phase
    );
    ensure!(
        seen.values().any(|sequence| {
            let initialize = sequence.iter().position(|name| *name == "initialize");
            let session = sequence.iter().position(|name| *name == "session/new");
            matches!((initialize, session), (Some(init), Some(session)) if init < session)
        }),
        "acp-auto-install {} never completed one ACP connection (initialize → session/new); observed {:?}",
        spec.phase,
        seen
    );
    Ok(())
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

/// The canonical driver snapshot captured for the `connected` stage.
///
/// The file reference comes from the journey summary (`capture.snapshotFile`).
/// This harness never reconstructs a snapshot name and never picks the newest
/// file in the shared output directory: several lifecycles write into the same
/// directory, so a guessed name could silently read another phase's evidence.
struct ConnectedCapture {
    snapshot: Value,
    /// `summary.savedAccount` 记录的保存身份；断言只认这个 id。
    account_id: Option<String>,
}

impl ConnectedCapture {
    fn load(output: &Path, summary: &Value, phase: &str) -> Result<Self> {
        // 身份只认 `summary.savedAccount`：不能按名称或“列表最后一项”猜，否则
        // 预置旧账号与新保存账号的先后顺序会决定断言结论。
        let account_id = summary["savedAccount"]["accountId"]
            .as_str()
            .map(str::to_owned);
        let Some(capture) = summary["captures"].as_array().and_then(|captures| {
            captures
                .iter()
                .find(|capture| capture["name"].as_str() == Some(CONNECTED_CAPTURE))
        }) else {
            return Ok(Self {
                snapshot: Value::Null,
                account_id,
            });
        };
        let path = capture_artifact(output, capture, "snapshotFile", "snapshot", ".json", phase)?;
        let snapshot = read_json(&path)?;
        ensure!(
            snapshot.is_object(),
            "the {phase} connected snapshot is not a canonical snapshot object"
        );
        Ok(Self {
            snapshot,
            account_id,
        })
    }

    fn assert_account(&self) -> Result<()> {
        let account = self
            .account()
            .context("the connected snapshot carries no saved antigravity account")?;
        assert_saved_account(account)?;
        let expected = self
            .account_id
            .as_deref()
            .context("the connected summary recorded no saved account identity")?;
        ensure!(
            account["accountId"].as_str() == Some(expected),
            "the connected snapshot account is not the identity the phase saved"
        );
        Ok(())
    }

    fn account(&self) -> Option<&Value> {
        let accounts = self.snapshot["settings"]["acpAccounts"].as_array()?;
        match self.account_id.as_deref() {
            Some(expected) => accounts
                .iter()
                .find(|account| account["accountId"].as_str() == Some(expected)),
            None => accounts
                .iter()
                .rev()
                .find(|account| account["provider"].as_str() == Some(PROVIDER)),
        }
    }

    /// canonical settings 里该账号的当前 connection revision。
    ///
    /// 这是 runtime 投影事实，只有 Driver 的 canonical 快照持有；desired 配置没有它。
    fn settings_revision(&self, account_id: &str) -> Result<u64> {
        let accounts = self.snapshot["settings"]["acpAccounts"]
            .as_array()
            .context("the connected snapshot carries no canonical ACP account list")?;
        let account = accounts
            .iter()
            .find(|account| account["accountId"].as_str() == Some(account_id))
            .with_context(|| format!("the connected snapshot carries no account `{account_id}`"))?;
        account["connectionRevision"].as_u64().with_context(|| {
            format!("the connected snapshot account `{account_id}` carries no connection revision")
        })
    }

    /// The canonical auth observation for the saved account and its exact
    /// connection revision: `required` with no stored credential, or `verified`
    /// with a usable credential. No login request is allowed in this flow.
    fn assert_auth_outcome(&self, phase: &str, credential_present: bool) -> Result<()> {
        let account = self
            .account()
            .with_context(|| format!("{phase} connected snapshot carries no saved account"))?;
        let account_id = account["accountId"]
            .as_str()
            .with_context(|| format!("{phase} saved account carries no identity"))?;
        let revision = account["connectionRevision"]
            .as_i64()
            .with_context(|| format!("{phase} saved account carries no connection revision"))?;
        let auth = self.snapshot["settings"]["acpAuth"]
            .as_object()
            .with_context(|| format!("{phase} connected snapshot carries no acpAuth facts"))?;
        ensure!(
            auth.get("loaded").and_then(Value::as_bool) == Some(true),
            "{phase} acpAuth facts were never loaded"
        );
        let entries = auth
            .get("accounts")
            .and_then(Value::as_array)
            .with_context(|| format!("{phase} acpAuth facts carry no account list"))?;
        let observed = entries
            .iter()
            .find(|entry| {
                entry["accountId"].as_str() == Some(account_id)
                    && entry["connectionRevision"].as_i64() == Some(revision)
            })
            .with_context(|| {
                format!("{phase} acpAuth has no entry for the saved account connection")
            })?;
        let kind = observed["state"]["kind"]
            .as_str()
            .with_context(|| format!("{phase} acpAuth entry carries no state kind"))?;
        match kind {
            "required" => ensure!(
                !credential_present,
                "{phase} reports Required although the fake Agent already holds a credential"
            ),
            "verified" => ensure!(
                credential_present,
                "{phase} reports Verified although the fake Agent holds no credential"
            ),
            other => bail!("{phase} acpAuth state `{other}` is not a terminal check"),
        }
        Ok(())
    }
}

/// Resolves one capture artifact through the summary reference instead of a
/// guessed file name.
///
/// The journey writes every capture artifact with a run-phase segment
/// (`screenshot-<phase>-…png`, `snapshot-<phase>-…json`, `tree-<phase>-…txt`).
/// Requiring that segment keeps a later lifecycle from overwriting an earlier
/// phase's evidence while still letting an old summary point at its own file.
fn capture_artifact(
    output: &Path,
    capture: &Value,
    field: &str,
    prefix: &str,
    extension: &str,
    phase: &str,
) -> Result<PathBuf> {
    let name = capture[field]
        .as_str()
        .with_context(|| format!("a capture entry carries no `{field}` reference"))?;
    ensure!(
        !name.is_empty() && !name.contains(['/', '\\']) && !name.starts_with('.'),
        "capture `{field}` is not a bare evidence file name: {name}"
    );
    let expected = format!("{prefix}-{phase}-");
    ensure!(
        name.starts_with(&expected) && name.ends_with(extension),
        "capture `{field}` `{name}` does not belong to the {phase} lifecycle"
    );
    let path = output.join(name);
    ensure!(
        path.is_file(),
        "the {phase} capture `{field}` file is missing: {name}"
    );
    Ok(path)
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

/// The install entry the driver summary captured for the Antigravity provider.
fn install_entry(summary: &Value) -> Result<&Value> {
    let install = summary
        .get("install")
        .context("the journey summary carries no install facts")?;
    let installations = install["installations"]
        .as_array()
        .context("the journey install facts carry no installation list")?;
    installations
        .iter()
        .find(|entry| entry["provider"].as_str() == Some(PROVIDER))
        .context("the journey install facts carry no antigravity entry")
}

fn entry_phase(entry: &Value) -> Option<&str> {
    entry["phase"].as_str()
}

fn entry_operation(summary: &Value) -> Result<Option<&str>> {
    Ok(install_entry(summary)?["operationId"].as_str())
}

fn entry_failure_code(entry: &Value) -> Option<&str> {
    entry["failure"]["code"].as_str()
}

fn entry_failure_retryable(entry: &Value) -> Option<bool> {
    entry["failure"]["retryable"].as_bool()
}

/// Verifies the cancelled operation's own facts: same operation identity and the
/// exact frozen release the lifecycle was configured with.
fn assert_cancelled_release(cancelled: &Value, spec: &PhaseSpec, ready: &Value) -> Result<()> {
    let operation = cancelled["operationId"].as_str().unwrap_or_default();
    ensure!(
        !operation.trim().is_empty(),
        "acp-auto-install {} reported no cancelled operation identity",
        spec.phase
    );
    let release = cancelled["release"]
        .as_object()
        .context("cancelledOperation carries no frozen release")?;
    ensure!(
        release.get("version").and_then(Value::as_str) == Some(SERVER_VERSION),
        "acp-auto-install {} cancelled another release version",
        spec.phase
    );
    ensure!(
        release.get("archiveUrl").and_then(Value::as_str) == Some(fixed_archive_url()?.as_str()),
        "acp-auto-install {} cancelled another archive URL",
        spec.phase
    );
    ensure!(
        release.get("sha256") == Some(&Value::Null),
        "acp-auto-install {} cancelled another publisher digest",
        spec.phase
    );
    ensure!(
        release.get("target").and_then(Value::as_str)
            == ready.get("target").and_then(Value::as_str),
        "acp-auto-install {} cancelled another platform target",
        spec.phase
    );
    Ok(())
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
        "driverLauncherPid": facts.driver_pid,
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
        "summary": {
            "status": facts.summary["status"].clone(),
            "stage": facts.summary["stage"].clone(),
            "checks": facts.summary["checks"].clone(),
            "install": facts.summary["install"].clone(),
            "exitRequest": facts.summary["exitRequest"].clone(),
        },
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
            "--driver",
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

fn start_journey(
    context: &AcpAutoInstallScenario<'_>,
    home: &Path,
    spec: &PhaseSpec,
    vm_url: &str,
    log_path: &Path,
    fixture_state: Option<&Path>,
) -> Result<OwnedProcess> {
    ensure!(
        context.app_dir.join(JOURNEY).is_file(),
        "the acp-auto-install Driver journey is missing: {}",
        context.app_dir.join(JOURNEY).display()
    );
    let log = File::create(log_path)?;
    let mut command = driver_command(context.app_dir, JOURNEY);
    command
        .arg(vm_url)
        .arg(context.output)
        .arg(spec.phase)
        .env("ANYWORK_HOME", home)
        // 只有需要驱动合成认证的阶段才拿到绝对 state 目录：它是 fixture 侧的
        // 数据参数，不是产品启动参数。
        .args(fixture_state)
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
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

fn wait_for_driver(
    phase: &str,
    driver: &mut OwnedProcess,
    gui: &mut OwnedProcess,
    output: &Path,
    interrupt: &mpsc::Receiver<()>,
) -> Result<std::process::ExitStatus> {
    let deadline = Instant::now() + Duration::from_secs(1800);
    loop {
        if let Some(status) = driver.child.try_wait()? {
            return Ok(status);
        }
        ensure!(
            !gui.exited()?,
            "the GUI exited before the acp-auto-install {phase} journey completed"
        );
        ensure!(
            interrupt.try_recv().is_err(),
            "the acp-auto-install {phase} journey was cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "the acp-auto-install {phase} journey timed out at stage `{}`",
            summary_stage(output, phase)
        );
        thread::sleep(Duration::from_millis(100));
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

fn summary_stage(output: &Path, phase: &str) -> String {
    read_json(&output.join(format!("acp-auto-install-summary-{phase}.json")))
        .ok()
        .and_then(|value| value["stage"].as_str().map(str::to_owned))
        .unwrap_or_else(|| "unknown".to_owned())
}

/// Requires the journey's own summary to describe a completed lifecycle with the
/// exact Driver contract shape (boolean checks, captures with explicit
/// `file`/`snapshotFile`/`treeFile` references, empty failures for every phase,
/// typed shutdown and acknowledged exit).
fn validate_summary(
    output: &Path,
    spec: &PhaseSpec,
    target: &str,
    saved_identity: Option<&Value>,
) -> Result<Value> {
    let path = output.join(format!("acp-auto-install-summary-{}.json", spec.phase));
    let summary = read_json(&path)?;
    ensure!(
        summary["scenario"] == "acp-auto-install",
        "the {} journey summary names another scenario",
        spec.phase
    );
    ensure!(
        summary["phase"] == spec.phase,
        "the journey summary does not belong to the {} lifecycle",
        spec.phase
    );
    ensure!(
        summary["status"].as_str() == Some("completed"),
        "the {} journey summary status is not `completed`",
        spec.phase
    );
    ensure!(
        summary["stage"]
            .as_str()
            .is_some_and(|stage| !stage.trim().is_empty()),
        "the {} journey summary carries no stage",
        spec.phase
    );
    ensure!(
        summary["humanVerdict"].as_str() == Some("pending"),
        "the {} journey summary must keep the human verdict pending",
        spec.phase
    );
    ensure!(
        summary["shutdown"].as_str() == Some("completed"),
        "the {} journey summary does not prove a completed shutdown",
        spec.phase
    );
    let exit = summary
        .get("exitRequest")
        .context("the journey summary carries no exitRequest facts")?;
    ensure!(
        exit["requested"].as_bool() == Some(true) && exit["acknowledged"].as_bool() == Some(true),
        "the {} journey did not get its exit request acknowledged",
        spec.phase
    );
    let failed = summary["failedChecks"]
        .as_array()
        .context("the journey summary carries no failedChecks array")?;
    ensure!(
        failed.is_empty(),
        "the {} journey reported failed checks: {failed:?}",
        spec.phase
    );
    let failures = summary["failures"]
        .as_array()
        .context("the journey summary carries no failures array")?;
    // A product install failure is a typed entry state, never a harness failure:
    // every completed lifecycle must keep this list empty.
    ensure!(
        failures.is_empty(),
        "the {} journey reported harness failures: {failures:?}",
        spec.phase
    );
    assert_checks_clean(&summary["checks"], spec.phase)?;
    // 只有真正进入安装流程的 phase 才订阅安装事实：auth-faults/restart 在准备表单
    // 里没有安装订阅，要求它们 `installLoaded` 等于伪造一个不存在的订阅。
    let installation_phase = !matches!(spec.expect, Expect::Auth);
    if installation_phase {
        for required in ["installLoaded", "installRevisionRecorded"] {
            ensure!(
                summary["checks"][required].as_bool() == Some(true),
                "the {} journey check `{required}` is missing or false",
                spec.phase
            );
        }
    }
    // 每个 phase 必须**存在且为 true** 的真实 check：缺失不能被“checks 全 true”
    // 掩盖（那只是对已有项的全量断言）。
    for required in spec.required_checks {
        ensure!(
            summary["checks"][required].as_bool() == Some(true),
            "the {} journey check `{required}` is missing or not true",
            spec.phase
        );
    }
    let captures = summary["captures"]
        .as_array()
        .cloned()
        .context("the journey summary carries no captures")?;
    // 认证截图要用哪一条身份定位账号：
    // - `Save::New`（first/retry）保存的是**本 phase 自己**的账号，必须用本 phase 的
    //   `savedAccount`；沿用 first 的旧身份会把 retry（H3）错指到 H1 的 id。
    // - 其余 phase（auth-faults/restart）没有保存，继续用 first 记录的 id 定位，
    //   它们与当前 runtime 的 settings/auth revision 在同一帧内自洽相核。
    let capture_identity: Option<Value> = if spec.save == Save::New {
        let saved = summary
            .get("savedAccount")
            .context("the journey summary carries no savedAccount facts")?;
        ensure!(
            saved["accountId"].as_str().is_some_and(|id| !id.is_empty()),
            "the {} journey saved no account identity",
            spec.phase
        );
        ensure!(
            saved["connectionRevision"].as_u64().is_some(),
            "the {} journey saved no connection revision",
            spec.phase
        );
        Some(saved.clone())
    } else {
        saved_identity.cloned()
    };
    // Required captures belong to the phase's *final* operation: a fault phase may
    // have captured an earlier attempt as extra evidence, but the required name is
    // bound to the operation the summary ended in.
    let final_operation = if installation_phase {
        entry_operation(&summary)?.map(str::to_owned)
    } else {
        // 认证类 phase 的 summary.install 可以为空；它没有安装操作身份可核对。
        None
    };
    let cancelled_operation = summary
        .get("cancelledOperation")
        .and_then(|cancelled| cancelled["operationId"].as_str())
        .map(str::to_owned);
    for name in spec.required_captures {
        // 名字与 `capture_kind` 一一对应：这里只挑选本阶段声明的必需证据。
        let capture = captures
            .iter()
            .find(|capture| capture["name"].as_str() == Some(*name))
            .with_context(|| format!("the {} journey never captured `{name}`", spec.phase))?;
        validate_recorded_capture(
            output,
            spec,
            target,
            name,
            capture,
            final_operation.as_deref(),
            cancelled_operation.as_deref(),
            capture_identity.as_ref(),
        )?;
    }
    // 取消中的瞬态截图可选；一旦记录，就必须与其它阶段证据同样严格（同阶段、
    // 同非空 operation、真实截图与快照）。记录与否另由 `cancellingObservation`
    // 的观察结论约束，不能只靠一个布尔 check。
    if spec.expect == Expect::Cancelled
        && let Some(capture) = captures
            .iter()
            .find(|capture| capture["name"].as_str() == Some(CANCELLING_CAPTURE))
    {
        validate_recorded_capture(
            output,
            spec,
            target,
            CANCELLING_CAPTURE,
            capture,
            final_operation.as_deref(),
            cancelled_operation.as_deref(),
            capture_identity.as_ref(),
        )?;
    }
    if spec.required_captures.contains(&CONNECTED_CAPTURE) {
        // The journey's own auth checks must be terminal check facts: `Required`
        // (nothing stored) and `Verified` both count as a finished check, and a
        // login request is never part of this flow.
        for required in [
            "authObservedForConnection",
            "authReachedTerminalCheck",
            "authRecordedConnection",
        ] {
            ensure!(
                summary["checks"][required].as_bool() == Some(true),
                "the {} journey check `{required}` is missing or false",
                spec.phase
            );
        }
    }
    Ok(summary)
}

/// 一个 required capture 属于哪一类事实，决定它必须证明什么。
///
/// 固定 1.4.1 之后阶段分成两组：安装阶段（`progress`/`ready`/`cancelling`/…）必须
/// 带真实安装 phase 与同一次安装操作；认证阶段（`prepare-required`/`verified`/…）
/// 在准备表单里本来就没有安装订阅、也不需要安装 phase，因此只核 `acpAuth` 事实。
/// `connected` 是唯一同时要求两类事实的截图。
enum CaptureKind {
    /// 安装阶段截图。
    Install {
        phase: &'static str,
        failure: Option<&'static str>,
    },
    /// 连接截图：安装 Ready + 认证终态两个事实都核。
    Connected {
        install_phase: &'static str,
        auth: AuthExpectation,
    },
    /// 认证阶段截图：安装 phase 允许为 null。
    Auth(AuthExpectation),
    /// Native 表单回归截图：不得被伪造成安装 phase 或认证成功。
    Native,
}

/// 认证类截图必须证明的 `acpAuth` 事实。
struct AuthExpectation {
    /// 允许的 state kind。
    kinds: &'static [&'static str],
    /// 失败终态时必须匹配的 `(code, stage)`。`None` 表示不得是失败终态。
    failure: Option<(&'static str, &'static str)>,
    /// 该截图绑定的账号身份。
    account: AuthAccount,
}

/// 认证截图绑定哪个账号。
enum AuthAccount {
    /// 预置的旧账号基线：准备阶段还没有新 id，不能事后用保存的新 id 回填。
    Seed,
    /// `first`/`retry` 在 summary 里记录的保存身份。
    Saved,
}

/// Required capture name → 它承诺的事实类别。
///
/// 未列出的名字返回 `None`：一个 phase 要求了没有定义的 capture，本身就该失败，
/// 而不是按“可能没有安装 phase”放行。
/// 取消瞬态观察记录（`summary.cancellingObservation`）的消费端契约。
///
/// 字段分工是固定的：`capture` 是**枚举判别位**，只接受 `captured` /
/// `not-observed` / `phase-changed`；`reason` 只是非空的事实说明（例如“同 operation
/// 在首个快照里已到 Cancelled”），不参与判别，也不要求固定词。
///
/// - `capture == "captured"`：`observed == true`，且恰好一条合法的 `cancelling` 截图；
/// - `capture == "not-observed"`：`observed == false`，且没有该截图；
/// - `capture == "phase-changed"`：`observed == true`，且没有该截图——真实同一
///   operation 已进入后续取消阶段，不能用 `Cancelled` 或旧快照冒充该瞬态。
///
/// `capture` 为 null 或写成截图名（旧格式）、把 `reason` 当枚举值、`operationId` 与
/// `cancelledOperation` 不一致都是失败；字段缺失、未知 `capture` 取值、布尔与截图
/// 互相矛盾同样失败，不看 summary 的布尔 check。
fn assert_cancelling_observation(facts: &PhaseFacts<'_>) -> Result<()> {
    let spec = facts.spec;
    let observation = facts.summary["cancellingObservation"]
        .as_object()
        .with_context(|| {
            format!(
                "acp-auto-install {} recorded no cancellingObservation facts",
                spec.phase
            )
        })?;
    let cancelled_operation = facts.summary["cancelledOperation"]["operationId"]
        .as_str()
        .filter(|id| !id.trim().is_empty())
        .with_context(|| {
            format!(
                "acp-auto-install {} reported no cancelled operation identity",
                spec.phase
            )
        })?;
    let observed_operation = observation["operationId"]
        .as_str()
        .filter(|id| !id.trim().is_empty())
        .with_context(|| {
            format!(
                "acp-auto-install {} cancellingObservation carries no operation identity",
                spec.phase
            )
        })?;
    ensure!(
        observed_operation == cancelled_operation,
        "acp-auto-install {} observed cancelling on operation `{observed_operation}` instead of `{cancelled_operation}`",
        spec.phase
    );
    let observed = observation["observed"].as_bool().with_context(|| {
        format!(
            "acp-auto-install {} cancellingObservation carries no observed flag",
            spec.phase
        )
    })?;
    // `reason` 只是事实说明：非空即可，绝不当判别位。
    observation["reason"]
        .as_str()
        .filter(|reason| !reason.trim().is_empty())
        .with_context(|| {
            format!(
                "acp-auto-install {} cancellingObservation carries no reason fact",
                spec.phase
            )
        })?;
    // `capture` 是判别位：只接受三个冻结取值，null/截图名/未知值都拒绝。
    let capture = observation["capture"]
        .as_str()
        .filter(|capture| !capture.trim().is_empty())
        .with_context(|| {
            format!(
                "acp-auto-install {} cancellingObservation carries no capture discriminator",
                spec.phase
            )
        })?;
    let captures = facts.summary["captures"]
        .as_array()
        .context("the cancel summary carries no captures")?;
    let recorded = captures
        .iter()
        .filter(|capture| capture["name"].as_str() == Some(CANCELLING_CAPTURE))
        .count();
    match capture {
        "captured" => {
            ensure!(
                observed,
                "acp-auto-install {} claims a captured cancelling transient with observed=false",
                spec.phase
            );
            ensure!(
                recorded == 1,
                "acp-auto-install {} recorded {recorded} `{CANCELLING_CAPTURE}` captures for one observed transient",
                spec.phase
            );
        }
        "not-observed" => {
            ensure!(
                !observed,
                "acp-auto-install {} claims an unobserved cancelling transient with observed=true",
                spec.phase
            );
            ensure!(
                recorded == 0,
                "acp-auto-install {} recorded a `{CANCELLING_CAPTURE}` capture while reporting it unobserved",
                spec.phase
            );
        }
        "phase-changed" => {
            ensure!(
                observed,
                "acp-auto-install {} claims the transient moved on with observed=false",
                spec.phase
            );
            ensure!(
                recorded == 0,
                "acp-auto-install {} recorded a `{CANCELLING_CAPTURE}` capture although the transient moved on",
                spec.phase
            );
        }
        other => bail!(
            "acp-auto-install {} recorded an unknown cancelling observation capture `{other}`",
            spec.phase
        ),
    }
    Ok(())
}

/// 校验一条已记录截图：必需证据与可选瞬态走同一条严格事实链。
///
/// 名字必须来自 [`capture_kind`]；截图与快照必须是本阶段自己的真实产物，安装类
/// 截图还要在快照里核对同阶段、同 operation 与冻结描述符。
#[allow(clippy::too_many_arguments)]
fn validate_recorded_capture(
    output: &Path,
    spec: &PhaseSpec,
    target: &str,
    name: &str,
    capture: &Value,
    final_operation: Option<&str>,
    cancelled_operation: Option<&str>,
    capture_identity: Option<&Value>,
) -> Result<()> {
    ensure!(
        capture["screenshot"].as_bool() == Some(true),
        "capture `{name}` was not recorded as a real screenshot"
    );
    let kind = capture_kind(name)
        .with_context(|| format!("required capture `{name}` has no defined fact category"))?;
    let screenshot = capture_artifact(output, capture, "file", "screenshot", ".png", spec.phase)?;
    ensure!(
        selftest_png(&screenshot),
        "capture `{name}` has no real PNG screenshot: {}",
        screenshot.display()
    );
    let snapshot = capture_artifact(
        output,
        capture,
        "snapshotFile",
        "snapshot",
        ".json",
        spec.phase,
    )?;
    let snapshot_value = read_json(&snapshot)?;
    ensure!(
        snapshot_value.is_object(),
        "capture `{name}` recorded no canonical snapshot object"
    );
    match kind {
        CaptureKind::Install { phase, failure } => {
            ensure!(
                capture["phase"]
                    .as_str()
                    .is_some_and(|value| !value.trim().is_empty()),
                "capture `{name}` carries no observed install phase"
            );
            assert_capture_install_facts(
                name,
                capture,
                &snapshot_value,
                &InstallExpectation {
                    spec,
                    target,
                    phase,
                    failure,
                    final_operation,
                    cancelled_operation,
                },
            )?;
        }
        CaptureKind::Connected {
            install_phase,
            auth,
        } => {
            ensure!(
                capture["phase"]
                    .as_str()
                    .is_some_and(|value| !value.trim().is_empty()),
                "capture `{name}` carries no observed install phase"
            );
            assert_capture_install_facts(
                name,
                capture,
                &snapshot_value,
                &InstallExpectation {
                    spec,
                    target,
                    phase: install_phase,
                    failure: None,
                    final_operation,
                    cancelled_operation,
                },
            )?;
            assert_capture_auth_facts(name, &snapshot_value, spec, &auth, capture_identity)?;
        }
        CaptureKind::Auth(auth) => {
            // 认证截图不带安装 phase：这里既不允许、也不要求它伪造一个。
            assert_capture_auth_facts(name, &snapshot_value, spec, &auth, capture_identity)?;
        }
        CaptureKind::Native => {
            // Native 表单截图发生在安装已就绪的 home 里：允许 `phase: null`，
            // 也允许与它自己快照里 antigravity 条目的真实 phase 一致；但必须
            // 真的来自 Native 表单（settings.accounts + 控件树），且不据此声称
            // 安装或认证成功。
            let snapshot_phase = snapshot_value["settings"]["acpInstall"]["installations"]
                .as_array()
                .and_then(|entries| {
                    entries
                        .iter()
                        .find(|entry| entry["provider"].as_str() == Some(PROVIDER))
                })
                .and_then(|entry| entry["phase"].as_str());
            match capture["phase"].as_str() {
                Some(recorded) => ensure!(
                    Some(recorded) == snapshot_phase,
                    "the native form capture `{name}` claims install phase `{recorded}` but its snapshot shows `{snapshot_phase:?}`"
                ),
                None => ensure!(
                    capture["phase"].is_null(),
                    "the native form capture `{name}` carries a non-string install phase"
                ),
            }
            ensure!(
                snapshot_value["settings"]["accounts"].is_array(),
                "the native form capture `{name}` recorded no canonical Native account list"
            );
            let tree = capture_artifact(output, capture, "treeFile", "tree", ".txt", spec.phase)?;
            let tree_text = fs::read_to_string(&tree)?;
            ensure!(
                tree_text.to_lowercase().contains("account"),
                "the native form capture `{name}` recorded no Native form widget tree"
            );
        }
    }
    let tree = capture_artifact(output, capture, "treeFile", "tree", ".txt", spec.phase)?;
    let tree_text = fs::read_to_string(&tree)?;
    ensure!(
        !tree_text.trim().is_empty(),
        "capture `{name}` recorded an empty widget tree"
    );
    Ok(())
}

fn capture_kind(name: &str) -> Option<CaptureKind> {
    let install = |phase, failure| Some(CaptureKind::Install { phase, failure });
    let auth =
        |kinds: &'static [&'static str], failure: Option<(&'static str, &'static str)>, account| {
            Some(CaptureKind::Auth(AuthExpectation {
                kinds,
                failure,
                account,
            }))
        };
    match name {
        "progress" | "progress-resumed" | "progress-retry" => install("downloading", None),
        // 取消前的真实下载窗口：与 `progress` 同阶段，但绑定取消组的 operation。
        "downloading-before-cancel" => install("downloading", None),
        "ready" | "ready-reused" => install("ready", None),
        "cancelling" => install("cancelling", None),
        "cancelled" => install("cancelled", None),
        "failed-archive" => install("failed", Some("invalidArchive")),
        "connected" => Some(CaptureKind::Connected {
            install_phase: "ready",
            auth: AuthExpectation {
                kinds: &["required", "verified"],
                failure: None,
                account: AuthAccount::Saved,
            },
        }),
        // 准备阶段：绑定预置旧账号，且必须观察到 preparationRequired@prepare。
        "prepare-required" => auth(
            &["failed"],
            Some(("preparationRequired", "prepare")),
            AuthAccount::Seed,
        ),
        "authenticating" => auth(&["authenticating"], None, AuthAccount::Saved),
        "verified" => auth(&["verified"], None, AuthAccount::Saved),
        // Driver 的认证失败负例固定是 authenticate 阶段的 `authentication` 失败：
        // 任何其它 typed 失败（probe/protocol/…）都不算这一项通过。
        "authentication-failed" => auth(
            &["failed"],
            Some(("authentication", "authenticate")),
            AuthAccount::Saved,
        ),
        // 取消只有在真实进程收束后才发布终态 `cancelled`；`cancelling` 不是通过态。
        "auth-cancelled" => auth(&["cancelled"], None, AuthAccount::Saved),
        // 重启后的第一帧必须仍是 `unchecked`：不允许用上一次 runtime 的 Verified 冒充。
        "reopened" => auth(&["unchecked"], None, AuthAccount::Saved),
        "connected-reopened" => auth(&["verified"], None, AuthAccount::Saved),
        "native-form" => Some(CaptureKind::Native),
        _ => None,
    }
}

/// 安装类 capture 需要核对的上下文（集中在结构体里，避免长参数列表）。
struct InstallExpectation<'a> {
    spec: &'a PhaseSpec,
    target: &'a str,
    phase: &'static str,
    failure: Option<&'static str>,
    final_operation: Option<&'a str>,
    cancelled_operation: Option<&'a str>,
}

/// Requires the capture's own snapshot to show the install phase the capture
/// claims, for the antigravity entry, with this lifecycle's frozen descriptor.
///
/// Nothing here rewrites a snapshot or fills in a phase: a transient state that
/// could not be captured is reported as evidence the journey lacks, not repaired.
fn assert_capture_install_facts(
    name: &str,
    capture: &Value,
    snapshot: &Value,
    expected: &InstallExpectation<'_>,
) -> Result<()> {
    let phase = expected.phase;
    let recorded = capture["phase"]
        .as_str()
        .with_context(|| format!("capture `{name}` carries no observed install phase"))?;
    ensure!(
        recorded == phase,
        "capture `{name}` recorded install phase `{recorded}` but `{phase}` is required"
    );
    let install = &snapshot["settings"]["acpInstall"];
    ensure!(
        install["loaded"].as_bool() == Some(true),
        "capture `{name}` snapshot never loaded the install facts"
    );
    // 订阅事实必须来自这一帧的真实 snapshot，而不是 summary 里的布尔 check。
    ensure!(
        install["revision"].as_u64().is_some(),
        "capture `{name}` snapshot carries no integer install revision"
    );
    let entries = install["installations"]
        .as_array()
        .with_context(|| format!("capture `{name}` snapshot carries no installation list"))?;
    let entry = entries
        .iter()
        .find(|entry| entry["provider"].as_str() == Some(PROVIDER))
        .with_context(|| format!("capture `{name}` snapshot carries no antigravity entry"))?;
    ensure!(
        entry["phase"].as_str() == Some(phase),
        "capture `{name}` snapshot shows install phase `{:?}` instead of `{phase}`",
        entry["phase"].as_str()
    );
    let recorded_operation = entry["operationId"]
        .as_str()
        .with_context(|| format!("capture `{name}` snapshot carries no operation identity"))?;
    let final_operation = expected.final_operation.with_context(|| {
        format!(
            "the {} journey summary reported no final installation operation identity",
            expected.spec.phase
        )
    })?;
    ensure!(
        recorded_operation == final_operation,
        "capture `{name}` belongs to operation `{recorded_operation}` instead of the phase's final operation `{final_operation}`"
    );
    if let Some(cancelled) = expected.cancelled_operation {
        ensure!(
            cancelled == final_operation,
            "the cancelled operation `{cancelled}` is not the phase's final operation `{final_operation}`"
        );
    }
    // The snapshot entry embeds the canonical typed DTO: a failure is the nested
    // `failure` object (code/retryable/stage), never a flattened `failureCode`.
    let failure = &entry["failure"];
    match expected.failure {
        Some(code) => ensure!(
            failure["code"].as_str() == Some(code),
            "capture `{name}` snapshot shows failure `{:?}` instead of `{code}`",
            failure["code"].as_str()
        ),
        None => ensure!(
            failure.is_null(),
            "capture `{name}` snapshot shows an unexpected failure `{:?}`",
            failure["code"].as_str()
        ),
    }
    // Only the states that carry a frozen release can prove descriptor identity;
    // `cancelling`/`cancelled` carry none, and the harness never fabricates one.
    if matches!(phase, "downloading" | "ready") {
        // Same canonical shape: the frozen release is the nested `release` object.
        let release = &entry["release"];
        ensure!(
            release["version"].as_str() == Some(SERVER_VERSION),
            "capture `{name}` snapshot froze another release version"
        );
        ensure!(
            release["target"].as_str() == Some(expected.target),
            "capture `{name}` snapshot froze another platform target"
        );
        ensure!(
            release["archiveUrl"].as_str() == Some(fixed_archive_url()?.as_str()),
            "capture `{name}` snapshot froze another archive URL"
        );
        ensure!(
            release["sha256"].is_null(),
            "capture `{name}` snapshot froze another publisher digest"
        );
    }
    Ok(())
}

/// Requires the capture's snapshot to prove the `acpAuth` facts it claims.
///
/// 与安装截图不同：准备表单没有安装订阅，所以这里不看安装 phase，只核对当前
/// runtime 的 `acpAuth.loaded`、账号身份与连接 revision 的一致性，以及 state
/// kind（必要时还包括 typed failure code/stage）。
fn assert_capture_auth_facts(
    name: &str,
    snapshot: &Value,
    spec: &PhaseSpec,
    expected: &AuthExpectation,
    saved_identity: Option<&Value>,
) -> Result<()> {
    let account_id = match expected.account {
        AuthAccount::Seed => SEED_ACCOUNT_ID.to_owned(),
        AuthAccount::Saved => saved_identity
            .and_then(|identity| identity["accountId"].as_str())
            .with_context(|| {
                format!("capture `{name}` needs the saved identity recorded by the first phase")
            })?
            .to_owned(),
    };
    let auth = snapshot["settings"]["acpAuth"]
        .as_object()
        .with_context(|| format!("capture `{name}` snapshot carries no acpAuth facts"))?;
    ensure!(
        auth.get("loaded").and_then(Value::as_bool) == Some(true),
        "capture `{name}` snapshot never loaded the acpAuth facts"
    );
    let entries = auth
        .get("accounts")
        .and_then(Value::as_array)
        .with_context(|| format!("capture `{name}` snapshot carries no acpAuth account list"))?;
    let entry = entries
        .iter()
        .find(|entry| entry["accountId"].as_str() == Some(account_id.as_str()))
        .with_context(|| {
            format!("capture `{name}` snapshot carries no acpAuth entry for `{account_id}`")
        })?;
    let revision = entry["connectionRevision"].as_u64().with_context(|| {
        format!("capture `{name}` acpAuth entry carries no connection revision")
    })?;
    // 当前 runtime 的 settings 必须与认证观察使用同一个身份证：不盲信旧 runtime
    // 记下的数字，而是要求这一帧里两侧自洽。
    let accounts = snapshot["settings"]["acpAccounts"]
        .as_array()
        .with_context(|| format!("capture `{name}` snapshot carries no ACP account list"))?;
    let account = accounts
        .iter()
        .find(|account| account["accountId"].as_str() == Some(account_id.as_str()))
        .with_context(|| {
            format!("capture `{name}` snapshot carries no ACP account `{account_id}`")
        })?;
    ensure!(
        account["provider"].as_str() == Some(PROVIDER),
        "capture `{name}` account `{account_id}` changed provider"
    );
    ensure!(
        account["connectionRevision"].as_u64() == Some(revision),
        "capture `{name}` acpAuth revision differs from the current settings account revision"
    );
    let state = &entry["state"];
    let kind = state["kind"]
        .as_str()
        .with_context(|| format!("capture `{name}` acpAuth entry carries no state kind"))?;
    // 进行中的认证状态必须携带非空 operation；终态结构本身没有该字段。
    let in_flight = matches!(
        kind,
        "checking" | "authenticating" | "verifying" | "closing" | "cancelling"
    );
    if in_flight {
        ensure!(
            state["operationId"]
                .as_str()
                .is_some_and(|value| !value.trim().is_empty()),
            "capture `{name}` observed `{kind}` without a non-empty auth operation"
        );
    } else {
        ensure!(
            state.get("operationId").is_none_or(Value::is_null),
            "capture `{name}` observed terminal `{kind}` with a stale auth operation"
        );
    }
    ensure!(
        expected.kinds.contains(&kind),
        "capture `{name}` observed acpAuth kind `{kind}`, expected one of {:?}",
        expected.kinds
    );
    match expected.failure {
        Some((code, stage)) => {
            ensure!(
                state["failure"]["code"].as_str() == Some(code),
                "capture `{name}` reports failure `{:?}` instead of `{code}`",
                state["failure"]["code"]
            );
            ensure!(
                state["failure"]["stage"].as_str() == Some(stage),
                "capture `{name}` reports failure stage `{:?}` instead of `{stage}`",
                state["failure"]["stage"]
            );
        }
        None if kind == "failed" => {
            // 认证失败的具体枚举值由 Driver 选中的故障点决定；这里只要求它是一个
            // 带 code/stage 的 typed 失败，而不是空对象或字符串。
            ensure!(
                state["failure"]["code"]
                    .as_str()
                    .is_some_and(|code| !code.is_empty()),
                "capture `{name}` failed without a typed failure code"
            );
            ensure!(
                state["failure"]["stage"]
                    .as_str()
                    .is_some_and(|value| !value.is_empty()),
                "capture `{name}` failed without a typed failure stage"
            );
            ensure!(
                state["failure"]["retryable"].as_bool().is_some(),
                "capture `{name}` failed without a retryable flag"
            );
        }
        None => ensure!(
            state.get("failure").is_none_or(Value::is_null),
            "capture `{name}` carries a failure although it must be a clean observation"
        ),
    }
    if !expected.kinds.contains(&"failed") {
        ensure!(
            kind != "failed",
            "capture `{name}` ended in a typed failure although phase {} expects a clean state",
            spec.phase
        );
    }
    Ok(())
}

/// Every typed check must be a real `true`; the driver's checks map is boolean.
fn assert_checks_clean(checks: &Value, phase: &str) -> Result<()> {
    let map = checks
        .as_object()
        .with_context(|| format!("the {phase} journey checks are not a boolean map"))?;
    ensure!(
        !map.is_empty(),
        "the {phase} journey reported no checks at all"
    );
    for (name, value) in map {
        ensure!(
            value.as_bool().is_some(),
            "the {phase} journey check `{name}` is not a boolean"
        );
        ensure!(
            value.as_bool() == Some(true),
            "the {phase} journey check `{name}` is false"
        );
    }
    Ok(())
}

fn selftest_png(path: &Path) -> bool {
    let mut header = [0_u8; 8];
    File::open(path)
        .and_then(|mut file| file.read_exact(&mut header))
        .is_ok_and(|()| header == [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A])
}

/// `sha256:<64 lowercase hex>` → the filesystem storage key.
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
