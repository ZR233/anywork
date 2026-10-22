// Antigravity（ACP）账号接入的真实 bridge 人工验收旅程。
//
// 用法（由 pl-studio-acceptance 的 acp-account 场景驱动，参数顺序与 harness 一致）：
//   cargo dart test_driver/acp_account_journey.dart \
//     VM_URL OUTPUT_DIR FIXTURE_PROGRAM FIXTURE_STATE_DIR
//
// 生命周期由 `ANYWORK_ACCEPTANCE_ACP_PHASE=first|restart|faults` 选择，不增加位置参数。
// 每个 phase 写 `OUTPUT_DIR/acp-account-summary-<phase>.json`：`scenario`/`phase`/
// `verdict: pending`/`status`/`stage`/`shutdown`/`failedChecks`/`captures`/`scenarios`。
//
// 每个需要“重新登录”的子场景都在 `_beginScenario` 里显式重置 **自己** 的 fake 控制文件
// （`auth-started`/`auth-release`，按需清 `authenticated`），并记录事件水位；后续证据只
// 接受该水位之后、且 PID 属于本次尝试的记录。旅程不写生产认证状态、不轮询等待固定时长
// 来“证明”状态。
//
// 收尾：typed 清理回执必须为 `completed` → 写摘要 → `request-app-exit` 触发正常退出。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'tool_probe.dart';
import 'window_control.dart';

const _settingsOpen = 'settings-open';
const _settingsPage = 'settings-page';
const _settingsAccountsTab = 'settings-tab-accounts';
const _accountAdd = 'account-add';
const _accountTemplatePicker = 'account-template-picker';
const _accountTemplateList = 'account-template-list';
const _accountCancel = 'account-cancel';
const _accountSave = 'account-save';
const _accountBaseUrl = 'account-base-url';
const _accountBaseUrlInput = 'account-base-url-input';
const _accountApiKey = 'account-api-key';
const _accountEdit = 'account-edit';
const _accountEditorScroll = 'account-editor-scroll';
const _acpProgram = 'acp-account-program';
const _acpProgramInput = 'acp-account-program-input';
const _acpProgramBrowse = 'acp-account-program-browse';
const _acpArgs = 'acp-account-args';
const _acpArgsHeader = 'acp-account-args-header';
const _acpArgsBody = 'acp-account-args-body';
const _acpArgsAdd = 'acp-account-args-add';
const _acpCheck = 'acp-account-check';
const _acpLogin = 'acp-account-login';
const _acpCancelAuth = 'acp-account-cancel-auth';
const _acpRemove = 'acp-account-remove';
const _acpDone = 'acp-account-done';
const _acpBack = 'acp-account-back';

const _phaseEnv = 'ANYWORK_ACCEPTANCE_ACP_PHASE';

/// 统一选项身份：ACP 侧由 provider wire 值构成，不作为协议猜测依据。
const _antigravityToken = 'acp-antigravity';

/// 界面控件的等待预算：每个等待都必须有界并以具体阶段失败，
/// 而不是交给 harness 的总超时。
const _controlWait = Duration(seconds: 20);
const _startupWait = Duration(seconds: 90);

/// 结构性存在性探查的预算：只用于“元素是否在树里”这类正向确认。
const _probeWait = Duration(seconds: 2);

/// 失败取证的单个步骤预算：每一步独立有界，任一失败都不影响原始旅程错误。
const _failureEvidenceWait = Duration(seconds: 20);

/// 失败取证时逐个探查的稳定控件键：只读存在性，用于区分“没构建/没展开/没进该页”。
const _diagnosticKeys = <String>[
  _settingsOpen,
  _settingsPage,
  _settingsAccountsTab,
  _accountAdd,
  _accountTemplatePicker,
  _accountTemplateList,
  _acpProgram,
  _acpProgramInput,
  _acpArgs,
  _acpArgsHeader,
  _acpArgsBody,
  _acpArgsAdd,
  'acp-account-arg-0-input',
  'acp-account-arg-remove-0',
  _accountSave,
  _accountEdit,
  _acpCheck,
];

Future<void> main(List<String> args) async {
  final phase = Platform.environment[_phaseEnv];
  if (args.length != 4 ||
      !const {'first', 'restart', 'faults'}.contains(phase)) {
    stderr.writeln(
      'usage: $_phaseEnv=first|restart|faults '
      'acp_account_journey.dart VM_URL OUTPUT_DIR FIXTURE_PROGRAM '
      'FIXTURE_STATE_DIR',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(args[1]);
  await output.create(recursive: true);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  final journey = _Journey(
    driver: driver,
    output: output,
    fixture: _Fixture(program: args[2], stateDir: Directory(args[3])),
    phase: phase!,
  );
  try {
    await journey.run();
  } on Object catch (error, stackTrace) {
    // 阶段/目标键在 dispatch 前已记录；原始错误与栈同时进 stderr 与失败证据文件。
    stderr.writeln(
      'acp-account ${journey.phase} failed at ${journey.stage}: $error',
    );
    stderr.writeln('$stackTrace');
    await journey.recordFailure(error: error, stackTrace: stackTrace);
    exitCode = 1;
  } finally {
    await driver.close().timeout(const Duration(seconds: 5), onTimeout: () {});
  }
}

class _Journey {
  _Journey({
    required this.driver,
    required this.output,
    required this.fixture,
    required this.phase,
  });

  final FlutterDriverSession driver;
  final Directory output;
  final _Fixture fixture;
  final String phase;

  final Map<String, bool> checks = {};
  final List<Map<String, Object?>> captures = [];
  final List<Map<String, Object?>> scenarios = [];
  int _captureIndex = 0;
  String stage = 'starting';

  /// 当前步骤名。`stage` 在**每次 dispatch 之前**更新为 `步骤:动作:目标`，
  /// 因此任何错误类型（包括 Driver 包装后的 `DriverError`）失败时都能定位到具体
  /// key/动作，不依赖解析错误字符串。
  String _step = 'starting';

  void _enterStep(String step) {
    _step = step;
    stage = step;
  }

  _ScenarioBoundary? _boundary;
  WindowGeometry? _originalWindow;
  double? _narrowedLayoutRight;
  String? _shutdownEvidenceFile;
  String _shutdownWriteError = '';

  /// 写 shutdown 证据失败时的**底层**栈（区别于失败的旅程自带外层栈）。
  String _shutdownWriteStackTrace = '';

  /// typed shutdown 的**完整** reply（先存内存，再尝试写盘）。
  Map<String, dynamic>? _shutdownReply;

  /// 真实观察到的 shutdown 状态：初值 not-requested，收到 reply 后以 reply 为准。
  String _shutdownState = 'not-requested';
  int? _guiPid;

  Future<void> run() async {
    await _openAccounts();
    switch (phase) {
      case 'first':
        await _firstLifecycle();
      case 'restart':
        await _restartLifecycle();
      case 'faults':
        await _faultsLifecycle();
    }
  }

  // ── 生命周期 ──

  Future<void> _firstLifecycle() async {
    await _beginScenario('layout-form');
    final baseline = await _snapshot();
    checks['startsWithoutAcpAccounts'] = _acpAccounts(baseline).isEmpty;
    await _capture('accounts-empty');

    await _openTemplatePicker();
    // 先把 ACP 选项真正滚入视口，再拍摄与点击：离屏项存在不等于可见。
    // ACP 组在最前，方向朝列表起点；已在视口内时本步骤不移动内容。
    await _ensureTemplateVisible(_antigravityToken, dyScroll: 200);
    await _capture('antigravity-template');
    await _chooseTemplate(_antigravityToken, dyScroll: 200);
    // 真实添加表单的默认态（高级 argv 折叠）：不是 fake 填充后的样子。
    await _capture('antigravity-form-default');

    // fixture 的 typed argv 完整替换官方模板默认值（fake 需要自己的参数）。
    await _fillForm(program: fixture.program, args: _fixtureArgs());
    checks['programFieldVisible'] = await _present(_acpProgram);
    checks['programBrowseVisible'] = await _present(_acpProgramBrowse);
    // 缺席是正向断言：只有 `waitForAbsent` 正常完成才为 true（fail-closed）。
    checks['nativeApiKeyFieldAbsent'] = !(await _visible(_accountApiKey));
    await _capture('antigravity-form');

    await _narrowWindow(width: 720, height: 860);
    // 缩窄后先证明仍是**同一编辑现场**且文本未丢，再拍窄窗图：图名不能证明是表单。
    await _assertAcpDraftRetained(
      program: fixture.program,
      args: _fixtureArgs(),
      label: 'narrow',
    );
    await _capture('antigravity-form-narrow');
    await _restoreWindow();
    await _assertAcpDraftRetained(
      program: fixture.program,
      args: _fixtureArgs(),
      label: 'restored',
    );
    await _setText(_acpProgramInput, _longProgramPath());
    await _capture('antigravity-form-long-path');
    await _setText(_acpProgramInput, fixture.program);

    // S1：首次保存并连接 + 登录（fake 从无凭据开始）。
    await _beginScenario('first-login', clearCredential: true);
    await _saveAndConnect();
    final accountId = await _awaitSingleAccount('required');
    checks['savedThenRequired'] = true;
    await _capture('required');

    // 快速重复输入：第一次点击后立刻再点一次（canonical 还没把页面切到登录中），
    // 只允许一次受理。第二次点击的失败**只有**在确认入口已消失时才算正常；
    // 其他错误（含 stack）原样上抛，不用吞异常制造“重复点击已被阻止”的证据。
    stage = '$_step:first-login-tap';
    // 首次登录证据只取**登录点击之后**的子窗口：之前的 check 探测属于不同 PID。
    await _markEvidenceFrom('first-login-auth');
    await driver.tap(find.byValueKey(_acpLogin));
    stage = '$_step:duplicate-login-tap';
    try {
      await driver.tap(find.byValueKey(_acpLogin));
    } on Object catch (error, stackTrace) {
      // 只有**正向 `waitForAbsent` 正常完成**才接受这次点击失败；仍在/传输故障都上抛。
      try {
        await _waitForAbsent(_acpLogin, timeout: _probeWait);
      } on Object {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    await _awaitState(accountId, 'authenticating');
    final started = await _waitForAttempt(
      'first-login-auth',
      (evidence) => evidence.authenticatePid != null,
    );
    checks['fixtureAuthenticateObserved'] = started;
    // 只有正向确认入口缺席才算“重复输入被阻止”，不用 !present 推断。
    checks['duplicateStartPrevented'] = !(await _visible(_acpLogin));
    checks['cancelReachableWhileAuthenticating'] = await _present(
      _acpCancelAuth,
    );
    await _capture('authenticating');
    await fixture.releaseAuth();
    await _awaitState(accountId, 'verified');
    checks['credentialPersisted'] = await fixture.markerExists('authenticated');
    await _capture('verified');
    // C6：同一次尝试必须是同 PID 的 Authenticate → Released → SessionNew。
    final firstEvidence = await _attemptEvidence('first-login-auth');
    checks['duplicateInputSingleAdmission'] =
        firstEvidence.authenticateCount == 1;
    checks['firstAttemptSamePidChain'] =
        firstEvidence.authenticatePid != null &&
        firstEvidence.releasedPid == firstEvidence.authenticatePid &&
        firstEvidence.sessionNewPid == firstEvidence.authenticatePid &&
        firstEvidence.releasedAfterAuthenticate &&
        firstEvidence.sessionNewAfterReleaseForAttempt;

    // S2：重新检查（同一账号，不重建）。
    await _beginScenario('recheck');
    await _tap('acp-account-done');
    await _awaitRow(accountId);
    await _openDetails(accountId);
    await _tapCheckAndAwait(accountId, 'verified');
    checks['recheckSameAccount'] = _acpAccounts(await _snapshot()).length == 1;
    final recheck = await _attemptEvidence('recheck');
    checks['recheckWithoutAuthenticate'] = recheck.authenticateCount == 0;
    // P2：必须证明这次真的探测过（同 PID initialize → session/new），不能只看旧成功。
    checks['recheckProbeObserved'] = recheck.coversProbe;
    await _capture('recheck-verified');

    // S3：探针失败与恢复。
    await _beginScenario('probe-failure');
    await fixture.patchBehavior(probe: 'fail');
    final probeFailed = await _tapCheckAndAwait(accountId, 'failed');
    checks['probeFailureTyped'] = _isAnyCode(probeFailed, accountId, const {
      'probe',
      'protocol',
    });
    await _capture('probe-failed');
    await fixture.patchBehavior(probe: 'normal');
    await _tapCheckAndAwait(accountId, 'verified');
    checks['probeRecovered'] = true;

    // S4：对端断线失败与恢复。
    await _beginScenario('disconnect');
    await fixture.patchBehavior(disconnect: true);
    final disconnected = await _tapCheckAndAwait(accountId, 'failed');
    checks['disconnectFailureTyped'] = _isAnyCode(
      disconnected,
      accountId,
      const {'transport', 'protocol', 'io', 'cleanup', 'timeout'},
    );
    await _capture('disconnect-failed');
    await fixture.patchBehavior(disconnect: false);
    await _tapCheckAndAwait(accountId, 'verified');
    checks['disconnectRecovered'] = true;

    // S5：启动失败（不可用程序）→ 就地说明 → 恢复配置。
    await _beginScenario('startup-failure');
    final beforeEdit = _acpAccount(await _snapshot(), accountId);
    await _editProgram(_missingProgramPath());
    final startupFailed = await _awaitState(accountId, 'failed');
    checks['startupFailureTyped'] = _isAnyCode(startupFailed, accountId, const {
      'startup',
      'missingExecutable',
      'io',
    });
    checks['savedAccountSurvivedStartupFailure'] =
        _acpAccount(startupFailed, accountId) != null;
    final afterEdit = _acpAccount(startupFailed, accountId);
    checks['connectionRevisionAdvanced'] =
        afterEdit?['connectionRevision'] != null &&
        afterEdit?['connectionRevision'] != beforeEdit?['connectionRevision'];
    await _capture('startup-failed');
    await _editProgram(fixture.program);
    await _awaitState(accountId, 'verified');
    checks['startupRecovered'] = true;

    // S6：取消等待中的登录（不放行），随后用一次成功登录还原凭据。
    await _beginScenario('cancel', clearCredential: true);
    await fixture.patchBehavior(authentication: 'wait');
    await _tapCheckAndAwait(accountId, 'required');
    await _tap(_acpLogin);
    await _awaitState(accountId, 'authenticating');
    await _tap(_acpCancelAuth);
    await _awaitState(accountId, 'cancelled');
    checks['cancelObservedByFixture'] = await _waitForAttempt(
      'cancel',
      (evidence) => evidence.isOrderedCancellation,
    );
    // 场景起点已清空自己的 marker：仍不存在即本次没有放行。
    checks['cancelWithoutReleaseMarker'] = !await fixture.markerExists(
      'auth-release',
    );
    checks['cancelLeftNoCredential'] = !await fixture.markerExists(
      'authenticated',
    );
    checks['cancelNoPostReleaseProbe'] = !(await _attemptEvidence('cancel'))
        .sessionNewAfterReleaseForAttempt;
    await _capture('cancelled');
    // 取消后回到需要登录，再走一次真实登录把凭据还原（first 阶段结束时必须存在）。
    await _tapCheckAndAwait(accountId, 'required');
    await _tap(_acpLogin);
    await _awaitState(accountId, 'authenticating');
    await fixture.releaseAuth();
    await _awaitState(accountId, 'verified');
    checks['cancelRecovered'] = true;

    // S7：Native 表单非回归。
    await _beginScenario('native-regression');
    // 此刻仍在 ACP 成功详情，`account-add` 不可用：先用产品既有 Done 回到列表。
    await _returnToAccountList();
    await _openTemplatePicker();
    final nativeToken = _firstNativeTemplate(await _snapshot());
    checks['nativeTemplatePresent'] = nativeToken != null;
    if (nativeToken != null) {
      // Native 回归用同一套可见性逻辑：先滚入视口再点击（Native 组在 ACP 之后）。
      await _ensureTemplateVisible(nativeToken, dyScroll: -200);
      await _tap('account-template-option-$nativeToken');
      await _waitFor(_accountBaseUrl);
      checks['nativeApiKeyFieldVisible'] = await _present(_accountApiKey);
      // Native 也验证宽窄保留：共享布局改动不能弄丢 Native 的未保存输入。
      const nativeBaseUrl = 'https://fixture.invalid/v1';
      await _setText(_accountBaseUrlInput, nativeBaseUrl);
      await _narrowWindow(width: 720, height: 860);
      await _assertTextRetained(
        _accountBaseUrlInput,
        nativeBaseUrl,
        label: 'native-narrow',
      );
      await _restoreWindow();
      await _assertTextRetained(
        _accountBaseUrlInput,
        nativeBaseUrl,
        label: 'native-restored',
      );
      await _capture('native-form');
      await _tap(_accountCancel);
      await _waitForAbsent(_accountBaseUrl);
    }

    await _finish(accountId: accountId, expectCredential: true);
  }

  Future<void> _restartLifecycle() async {
    await _beginScenario('persisted');
    final baseline = await _snapshot();
    final accounts = _acpAccounts(baseline);
    checks['persistedSingleAccount'] = accounts.length == 1;
    if (accounts.isEmpty) {
      throw StateError('restart lifecycle found no saved ACP account');
    }
    final accountId = '${accounts.single['accountId']}';
    // 初始 Unchecked 必须是**已加载的真实条目**：空快照、revision 未到或条目缺失
    // 都不构成证据（revision 0 本身是合法已加载水位，不能用 >0 代替 loaded）。
    final loaded = await _until(
      'initial-unchecked',
      (state) =>
          _acpAuthLoaded(state) &&
          _observedKind(state, accountId) == 'unchecked',
    );
    checks['acpAuthLoaded'] = _acpAuthLoaded(loaded);
    checks['initialStateUnchecked'] =
        _observedKind(loaded, accountId) == 'unchecked';
    checks['fixtureCredentialPersisted'] = await fixture.markerExists(
      'authenticated',
    );
    await _openDetails(accountId);
    await _capture('persisted-account');

    await _narrowWindow(width: 760, height: 860);
    // 详情页窄窗：必须仍是同一账号详情（不是被重建回列表）。
    if (!await _visible('acp-account-detail-$accountId')) {
      throw StateError('restart-narrow: the ACP detail view was recreated');
    }
    checks['detailRetained:restart-narrow'] = true;
    await _capture('persisted-account-narrow');
    await _restoreWindow();

    final checked = await _tapCheckAndAwait(accountId, 'verified');
    final evidence = await _attemptEvidence('persisted');
    checks['checkedWithoutAuthenticate'] = evidence.authenticateCount == 0;
    checks['restartProbeObserved'] = evidence.coversProbe;
    final account = _acpAccount(checked, accountId);
    checks['restartConfigUnchanged'] =
        account?['program'] == fixture.program &&
        _sameArgs(account?['args'], _fixtureArgs());
    await _capture('recheck-verified');
    await _finish(accountId: accountId, expectCredential: true);
  }

  Future<void> _faultsLifecycle() async {
    final accounts = _acpAccounts(await _snapshot());
    checks['persistedSingleAccount'] = accounts.length == 1;
    if (accounts.isEmpty) {
      throw StateError('faults lifecycle found no saved ACP account');
    }
    final accountId = '${accounts.single['accountId']}';

    // S1：检查 → Required → 认证真实失败。
    await _beginScenario('authentication-failure', clearCredential: true);
    await _openDetails(accountId);
    await _tapCheckAndAwait(accountId, 'required');
    await _tap(_acpLogin);
    final failed = await _awaitState(accountId, 'failed');
    checks['authenticationFailureTyped'] = _isAnyCode(failed, accountId, const {
      'authentication',
      'protocol',
    });
    checks['savedAccountSurvivedFailure'] =
        _acpAccount(failed, accountId) != null;
    await _capture('authentication-failed');

    // S2：改为等待 → 登录 → 取消（不写 release）。
    await _beginScenario('cancel', clearCredential: true);
    await fixture.patchBehavior(authentication: 'wait');
    await _tapCheckAndAwait(accountId, 'required');
    await _tap(_acpLogin);
    await _awaitState(accountId, 'authenticating');
    await _tap(_acpCancelAuth);
    await _awaitState(accountId, 'cancelled');
    checks['cancelObservedByFixture'] = await _waitForAttempt(
      'cancel',
      (evidence) => evidence.isOrderedCancellation,
    );
    checks['cancelWithoutReleaseMarker'] = !await fixture.markerExists(
      'auth-release',
    );
    checks['cancelLeftNoCredential'] = !await fixture.markerExists(
      'authenticated',
    );
    checks['cancelNoPostReleaseProbe'] = !(await _attemptEvidence('cancel'))
        .sessionNewAfterReleaseForAttempt;
    await _capture('cancelled');

    // S3：在真实等待中的登录里删除接入（旧 operation 必须被撤代并收束）。
    await _beginScenario('delete-in-flight', clearCredential: true);
    await _tapCheckAndAwait(accountId, 'required');
    await _tap(_acpLogin);
    await _awaitState(accountId, 'authenticating');
    // 真实在途：fake 已受理 authenticate（auth-started / authenticate 事件）。
    checks['deleteStartedFromRealPendingLogin'] = await _waitForAttempt(
      'delete-in-flight',
      (evidence) => evidence.authenticatePid != null,
    );
    final beforeDelete = _authEntry(await _snapshot(), accountId);
    checks['deleteStartedFromActiveOperation'] = beforeDelete?['state'] != null;
    await _tap(_acpRemove);
    await _awaitAcpAccountCount(0);
    checks['deleteRemovesAccount'] = true;
    // 真实收束证据：fake 在该 PID 上收到取消/EOF，而不是靠固定等待。
    // 真实收束证据：同 PID、login 受理后有序释放，且释放后没有再用该进程探测。
    checks['deleteCancelledInFlightLogin'] = await _waitForAttempt(
      'delete-in-flight',
      (evidence) => evidence.isOrderedCancellation,
    );
    checks['deleteWroteNoRelease'] = !await fixture.markerExists(
      'auth-release',
    );
    checks['deleteLeftNoCredential'] = !await fixture.markerExists(
      'authenticated',
    );
    checks['deleteNoPostReleaseProbe'] = !(await _attemptEvidence(
      'delete-in-flight',
    )).sessionNewAfterReleaseForAttempt;
    checks['deleteKeptRemoved'] = _acpAccounts(await _snapshot()).isEmpty;
    await _capture('delete-removed');

    // S4：按同一 fixture 配置重建（配置必须保留，参数不来自官方默认值）。
    await _beginScenario('rebuild');
    await _openTemplatePicker();
    await _chooseTemplate(_antigravityToken, dyScroll: 200);
    await _fillForm(program: fixture.program, args: _fixtureArgs());
    await _saveAndConnect();
    final rebuiltId = await _awaitSingleAccount('required');
    final rebuilt = await _snapshot();
    final rebuiltAccount = _acpAccount(rebuilt, rebuiltId);
    checks['rebuiltConfigMatchesFixture'] =
        rebuiltAccount?['program'] == fixture.program &&
        _sameArgs(rebuiltAccount?['args'], _fixtureArgs());
    await _capture('rebuilt-required');

    // S5：在真实等待中的登录里改配置（同一真实程序，只调换 argv 顺序）。
    //
    // 产品语义是“保存并连接”：保存会自己发起 check。因此保存后可能直接进入
    // Checking/Required（自动 probe 已被受理）；也可能因旧 owner 仍持有资源而被
    // Busy 拒绝 → Closing(旧 op) → Unchecked。两条都是合法路径，但都必须在本窗口
    // 看到一次**新的真实 probe**；不由领域 revision 或假设的 Busy 决定。
    await _beginScenario('config-change-in-flight', clearCredential: true);
    await _tapCheckAndAwait(rebuiltId, 'required');
    await _tap(_acpLogin);
    await _awaitState(rebuiltId, 'authenticating');
    checks['configChangeStartedFromRealPendingLogin'] = await _waitForAttempt(
      'config-change-in-flight',
      (evidence) => evidence.authenticatePid != null,
    );
    final beforeChange = await _snapshot();
    final oldOperation = _stateOperationId(beforeChange, rebuiltId);
    final oldConnectionRevision = _acpAccount(
      beforeChange,
      rebuiltId,
    )?['connectionRevision'];
    checks['configChangeStartedFromActiveOperation'] =
        oldOperation != null && oldConnectionRevision != null;
    // 水位放在旧 authenticate 已被观察到之后：窗口允许旧 Released，但不能再有 authenticate。
    final changeFrom = await fixture.eventCount();
    checks['changeWindowExcludesOldAuthenticate'] =
        (await _evidenceSince(changeFrom)).authenticateCount == 0;
    await _editArgs(_alternateArgs());
    final change = await _convergeAfterConfigSave(
      accountId: rebuiltId,
      previousConnectionRevision: oldConnectionRevision! as int,
      eventsFrom: changeFrom,
    );
    checks['configChangeRevisionAdvanced'] =
        change.connectionRevision != oldConnectionRevision;
    final changedAccount = _acpAccount(change.snapshot, rebuiltId);
    checks['savedConfigSurvivedBusy'] =
        changedAccount != null &&
        changedAccount['program'] == fixture.program &&
        _sameArgs(changedAccount['args'], _alternateArgs());
    // 新身份绝不能把旧 operation 的成功当成自己的结果（Closing 投影旧 op 是允许的）。
    checks['newIdentityNeverShowsOldSuccess'] =
        change.firstKindAfterChange != 'verified' &&
        change.firstKindAfterChange != 'authenticating' &&
        (change.firstOperationId != oldOperation ||
            change.firstKindAfterChange == 'closing' ||
            change.firstKindAfterChange == 'unchecked');
    checks['changedIdentityEndsAtRequired'] = change.settledKind == 'required';
    checks['changePathProbeObserved'] =
        change.autoProbe || change.explicitProbe;
    await _capture('config-changed');

    // 恢复原 argv：同一个收敛 helper（自动 check 也可能直接成功）。
    final restoreFrom = await fixture.eventCount();
    await _editArgs(_fixtureArgs());
    final restore = await _convergeAfterConfigSave(
      accountId: rebuiltId,
      previousConnectionRevision: change.connectionRevision,
      eventsFrom: restoreFrom,
    );
    final restoredAccount = _acpAccount(restore.snapshot, rebuiltId);
    checks['configRestoredToFixture'] =
        restoredAccount?['program'] == fixture.program &&
        _sameArgs(restoredAccount?['args'], _fixtureArgs());
    checks['restoreProbeObserved'] = restore.autoProbe || restore.explicitProbe;
    checks['restoredIdentitySettles'] = restore.settledKind == 'required';

    // S6：登录中正常退出（active-operation shutdown）。
    await _beginScenario('active-shutdown', clearCredential: true);
    await _tapCheckAndAwait(rebuiltId, 'required');
    await _tap(_acpLogin);
    await _awaitState(rebuiltId, 'authenticating');
    checks['activeOperationAtShutdown'] = true;
    await _capture('active-operation');
    await _finish(
      accountId: rebuiltId,
      expectCredential: false,
      afterShutdown: () async {
        // C6：只接受本次尝试（水位之后、同 PID）的释放证据。
        checks['shutdownCancelledThisAttempt'] = await _waitForAttempt(
          'active-shutdown',
          (evidence) => evidence.isOrderedCancellation,
        );
        checks['shutdownWroteNoRelease'] = !await fixture.markerExists(
          'auth-release',
        );
        checks['shutdownLeftNoCredential'] = !await fixture.markerExists(
          'authenticated',
        );
        checks['shutdownNoPostReleaseProbe'] = !(await _attemptEvidence(
          'active-shutdown',
        )).sessionNewAfterReleaseForAttempt;
      },
    );
  }

  /// 收尾：typed 清理回执 → 摘要 → 正常应用退出请求。
  Future<void> _finish({
    required String accountId,
    required bool expectCredential,
    Future<void> Function()? afterShutdown,
  }) async {
    checks['exactlyOneSavedAccount'] =
        _acpAccounts(await _snapshot()).length == 1;
    checks['credentialMatchesExpectation'] =
        await fixture.markerExists('authenticated') == expectCredential;
    var failed = _failedChecks();
    if (failed.isNotEmpty) throw StateError('failed checks: $failed');
    final cleanup = await _requestShutdown();
    if (cleanup != 'completed') {
      throw StateError('typed shutdown cleanup was $cleanup');
    }
    if (afterShutdown != null) await afterShutdown();
    failed = _failedChecks();
    if (failed.isNotEmpty) throw StateError('failed checks: $failed');
    stage = 'complete';
    await _writeSummary(status: 'complete', shutdown: cleanup);
    await _requestExit();
  }

  List<String> _failedChecks() => [
    for (final entry in checks.entries)
      if (!entry.value) entry.key,
  ];

  // ── 场景边界 ──

  /// 配置保存（产品语义为“保存并连接”）之后的收敛与证据。
  ///
  /// 两条合法路径：
  /// - 自动 check 已被受理并完成（本窗口内出现新的同 PID initialize → session/new，
  ///   且没有 authenticate）→ 直接以 Required 为终态，**不重复显式 check**；
  /// - 自动 check 因旧 owner 仍持有资源被 Busy 拒绝 → Closing(旧 op) → Unchecked，
  ///   保存事实仍在，随后显式 check 一次并同样验证新 probe。
  ///
  /// 不依赖领域 revision、不 sleep、不假定必然 Busy。
  Future<_ConfigSaveConvergence> _convergeAfterConfigSave({
    required String accountId,
    required int previousConnectionRevision,
    required int eventsFrom,
  }) async {
    final changed = await _until('connection-identity-advanced', (state) {
      final account = _acpAccount(state, accountId);
      final revision = account?['connectionRevision'];
      return revision is int && revision != previousConnectionRevision;
    });
    final firstKind = _stateKind(changed, accountId);
    final firstOperation = _stateOperationId(changed, accountId);
    final connectionRevision =
        _acpAccount(changed, accountId)!['connectionRevision']! as int;

    final deadline = DateTime.now().add(const Duration(seconds: 180));
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await _snapshot();
      final kind = _stateKind(snapshot, accountId);
      final entry = _authEntry(snapshot, accountId);
      final autoProbe = (await _evidenceSince(eventsFrom)).coversProbe;
      if (autoProbe && (kind == 'required' || kind == 'verified')) {
        return _ConfigSaveConvergence(
          snapshot: snapshot,
          connectionRevision: connectionRevision,
          autoProbe: true,
          explicitProbe: false,
          settledKind: kind,
          firstKindAfterChange: firstKind,
          firstOperationId: firstOperation,
        );
      }
      if (!autoProbe && entry != null && kind == 'unchecked') {
        // Busy 路径：旧 owner 已收束并显式发布 Unchecked，再自己探测一次。
        final recheckFrom = await fixture.eventCount();
        final reprobed = await _tapCheckAndAwait(accountId, 'required');
        final explicitProbe = (await _evidenceSince(recheckFrom)).coversProbe;
        return _ConfigSaveConvergence(
          snapshot: reprobed,
          connectionRevision: connectionRevision,
          autoProbe: false,
          explicitProbe: explicitProbe,
          settledKind: _stateKind(reprobed, accountId),
          firstKindAfterChange: firstKind,
          firstOperationId: firstOperation,
        );
      }
      if (kind == 'failed') {
        // 真正的失败如实暴露，不当作收敛成功。
        return _ConfigSaveConvergence(
          snapshot: snapshot,
          connectionRevision: connectionRevision,
          autoProbe: autoProbe,
          explicitProbe: false,
          settledKind: kind,
          firstKindAfterChange: firstKind,
          firstOperationId: firstOperation,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError(
      'ACP config change did not settle (kind=${_stateKind(await _snapshot(), accountId)})',
    );
  }

  /// 记录一次受控子场景：重置 **自己** 的 fake 控制文件并锁定事件水位。
  ///
  /// 每个需要重新登录的子场景都必须调用它：否则上一轮留下的 `auth-release` 会让下一
  /// 次等待立即成功，`auth-started`/`authenticated` 也会让“无凭据/未受理”的断言失真。
  Future<void> _beginScenario(
    String name, {
    bool clearCredential = false,
  }) async {
    final from = await fixture.eventCount();
    await fixture.resetOwnControls(clearCredential: clearCredential);
    _boundary = _ScenarioBoundary(
      name: name,
      eventsFrom: from,
      clearedCredential: clearCredential,
    );
    scenarios.add({
      'name': name,
      'eventsFrom': from,
      'clearedCredential': clearCredential,
    });
  }

  Future<bool> _waitForAttempt(
    String name,
    bool Function(_AttemptEvidence evidence) predicate, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (predicate(await _attemptEvidence(name))) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// 只取给定水位之后的记录（用于场景内的子窗口，例如收束后的显式 check）。
  Future<_AttemptEvidence> _evidenceSince(int from) async =>
      _AttemptEvidence.from(await fixture.eventsSince(from));

  /// 只记录事件水位（不动 fixture 控制文件）：把证据窗口切到某个动作之后。
  Future<void> _markEvidenceFrom(String name) async {
    final from = await fixture.eventCount();
    scenarios.add({
      'name': name,
      'eventsFrom': from,
      'clearedCredential': false,
    });
  }

  /// 只取本场景水位之后的记录；PID 结论来自同一批记录。
  Future<_AttemptEvidence> _attemptEvidence(String name) async {
    final scenario = scenarios.firstWhere((entry) => entry['name'] == name);
    final from = scenario['eventsFrom']! as int;
    return _AttemptEvidence.from(await fixture.eventsSince(from));
  }

  // ── 账号 UI ──

  Future<void> _openAccounts() async {
    _enterStep('open-accounts');
    await _waitFor(_settingsOpen, timeout: _startupWait);
    await _tap(_settingsOpen, timeout: _startupWait);
    await _waitFor(_settingsPage);
    await _waitFor(_settingsAccountsTab);
    await _tap(_settingsAccountsTab);
    await _waitFor(_accountAdd);
  }

  Future<void> _openTemplatePicker() async {
    _enterStep('open-template-picker');
    await _tap(_accountAdd);
    await _waitFor(_accountTemplatePicker);
  }

  /// 把目标选项真正滚入视口：可见性由 Driver 的官方滚动能力确认，
  /// 不以“元素存在”、截图文件名或坐标点击代替。
  Future<void> _ensureTemplateVisible(
    String token, {
    required double dyScroll,
  }) async {
    _enterStep('ensure-visible:$token');
    await driver.scrollUntilVisible(
      find.byValueKey(_accountTemplateList),
      find.byValueKey('account-template-option-$token'),
      dyScroll: dyScroll,
      timeout: _controlWait,
    );
    await _waitFor('account-template-option-$token');
  }

  Future<void> _chooseTemplate(String token, {required double dyScroll}) async {
    await _ensureTemplateVisible(token, dyScroll: dyScroll);
    _enterStep('choose-template:$token');
    await _tap('account-template-option-$token');
    await _waitFor(_acpProgram);
  }

  /// 账号编辑器正文是惰性 `ListView`：目标可能尚未构建（离屏），
  /// 因此先用官方滚动把它真正带进视口，再点击/读取，不用坐标或 sleep。
  Future<void> _revealInEditor(String key, {double dyScroll = -200}) async {
    stage = '$_step:reveal:$key';
    await driver.scrollUntilVisible(
      find.byValueKey(_accountEditorScroll),
      find.byValueKey(key),
      dyScroll: dyScroll,
      timeout: _controlWait,
    );
  }

  /// 真实展开态：官方 `ExpansionTile` 公开的 `Expansible.controller.isExpanded`
  /// （既有 ToolProbe `observe` 入口）。不读私有 State，也不自造第二份展开状态。
  Future<bool> _probeArgsExpanded() async {
    final result = await driver.sendCommand(
      ToolProbe(find.byValueKey(_acpArgs), 'observe'),
    );
    final samples = result['samples'];
    if (samples is! List || samples.isEmpty) {
      throw StateError('ToolProbe observe returned no samples for $_acpArgs');
    }
    final sample = samples.last;
    if (sample is! Map) {
      throw StateError('ToolProbe observe sample is not a map for $_acpArgs');
    }
    final expanded = sample['expanded'];
    if (expanded is! bool) {
      throw StateError('ToolProbe expanded is not bool: $expanded');
    }
    return expanded;
  }

  Future<bool> _argsExpanded() async {
    stage = '$_step:probe-args-expanded';
    return _probeArgsExpanded();
  }

  /// 展开高级 argv：先让标题行真正可见，再按**官方展开事实**决定是否点击；
  /// 已展开时不再点击（否则会折叠回去），点击后等真实 `isExpanded` 为真。
  Future<void> _ensureArgsExpanded() async {
    // 不替换外层步骤名：失败时仍需看到是 fill-acp-form / edit-acp-args 的哪一步。
    stage = '$_step:ensure-args-expanded';
    await _revealInEditor(_acpArgs);
    if (await _argsExpanded()) return;
    // 只点真实标题行；rawTap 是项目既有的 Linux 原生入口，不依赖 hitTestable 预过滤。
    stage = '$_step:raw-tap:$_acpArgsHeader';
    await driver.rawTap(find.byValueKey(_acpArgsHeader));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (await _argsExpanded()) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('advanced argv did not report expanded=true');
  }

  Future<void> _fillForm({
    required String program,
    required List<String> args,
  }) async {
    _enterStep('fill-acp-form');
    await _setText(_acpProgramInput, program);
    await _rewriteArgs(args);
  }

  /// 当前高级参数行数：从**真实键集合**正向探测（下标连续，没有 gap）。
  ///
  /// 每行存在由 `waitFor` 正常完成证明，边界不存在由 `waitForAbsent` 正常完成证明；
  /// 两者都无法确认时（含连接故障）`_visible` 会抛错，不会把未知当成 0。
  /// 不硬编码官方模板默认值，也不为 fixture 加旁路；探测本身有上限。
  Future<int> _currentArgCount() async {
    var count = 0;
    while (count < 32 && await _visible('acp-account-arg-$count')) {
      count += 1;
    }
    if (count == 32) {
      throw StateError('argv rows exceeded the bounded probe limit');
    }
    return count;
  }

  /// 逐项替换高级 argv（模板默认值/旧参数先被清空）。
  ///
  /// 每次按**当前真实行数**从末尾删起：被删行之后的旧帧不会再被下一次 reveal
  /// 当作目标；每次删除后显式等待该键消失，每次添加后显式等待新行出现，
  /// 不用 sleep，也不靠旧帧推断。
  Future<void> _rewriteArgs(List<String> args) async {
    await _ensureArgsExpanded();
    var count = await _currentArgCount();
    while (count > 0) {
      final last = count - 1;
      await _revealInEditor('acp-account-arg-remove-$last');
      await _tap('acp-account-arg-remove-$last');
      await _waitForAbsent('acp-account-arg-remove-$last');
      count -= 1;
    }
    if (await _visible('acp-account-arg-0')) {
      throw StateError('argv rows are not empty after removal');
    }
    for (var index = 0; index < args.length; index++) {
      await _revealInEditor(_acpArgsAdd);
      await _tap(_acpArgsAdd);
      await _waitFor('acp-account-arg-$index');
      await _setText('acp-account-arg-$index-input', args[index]);
    }
  }

  /// 只改 argv（程序不变）形成新的连接身份。
  Future<void> _editArgs(List<String> args) async {
    _enterStep('edit-acp-args');
    await _tap(_accountEdit);
    await _waitFor(_acpProgram);
    await _rewriteArgs(args);
    await _saveAndConnect();
  }

  Future<void> _saveAndConnect() async {
    _enterStep('save-and-connect');
    await _tap(_accountSave);
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(deadline)) {
      // 表单关闭必须正向确认；无法确认时 `_visible` 抛错，不当作“已保存”。
      if (!await _visible(_acpProgram)) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('save-and-connect never left the ACP form');
  }

  Future<void> _editProgram(String program) async {
    _enterStep('edit-acp-program');
    await _tap(_accountEdit);
    await _waitFor(_acpProgram);
    await _setText(_acpProgramInput, program);
    await _saveAndConnect();
  }

  Future<void> _openDetails(String accountId) async {
    _enterStep('open-acp-details');
    await _awaitRow(accountId);
    await _tap('acp-account-row-$accountId');
    await _waitFor('acp-account-detail-$accountId');
  }

  /// 从 ACP 详情回到账号列表：Done 是成功态的收束入口，Back 是其余态的入口。
  /// 两者都是产品已有出口；不改添加按钮语义，也不靠隐藏侧栏绕过。
  Future<void> _returnToAccountList() async {
    stage = '$_step:return-to-account-list';
    if (await _visible(_acpDone)) {
      await _tap(_acpDone);
    } else if (await _visible(_acpBack)) {
      await _tap(_acpBack);
    } else {
      throw StateError('no product exit from the ACP details view');
    }
    await _waitFor(_accountAdd);
  }

  Future<void> _awaitRow(String accountId) async {
    _enterStep('await-acp-row');
    await _waitFor('acp-account-row-$accountId');
  }

  /// 输入文本后以**真实 `getText`** 结果确认落地，不以光标动画停止或固定等待判断。
  ///
  /// 点击与读取都用真实输入控件自己的键；步骤与目标在 dispatch 前写入 [stage]。
  Future<void> _setText(String inputKey, String value) async {
    await _revealInEditor(inputKey);
    await _tap(inputKey);
    stage = '$_step:enter-text:$inputKey';
    await driver.enterText(value);
    await _waitFor(inputKey);
    final String actual;
    stage = '$_step:read-text:$inputKey';
    try {
      actual = await driver
          .getText(find.byValueKey(inputKey))
          .timeout(_controlWait);
    } on Object {
      // 只读读取失败/超时：保留阶段与目标，原错误原样上抛（不重连、不重放输入）。
      stage = '$_step:read-text-failed:$inputKey';
      rethrow;
    }
    if (actual != value) {
      throw StateError('$inputKey kept "$actual" instead of "$value"');
    }
  }

  Future<void> _tap(String key, {Duration timeout = _controlWait}) async {
    await _waitFor(key, timeout: timeout);
    stage = '$_step:tap:$key';
    await driver.tap(find.byValueKey(key));
  }

  /// 有界控件等待。阶段在 dispatch **之前**写入，因此任何错误类型（包括 Driver
  /// 包装后的 `DriverError`）失败时都已带上步骤与目标键。
  Future<void> _waitFor(String key, {Duration timeout = _controlWait}) async {
    stage = '$_step:wait:$key';
    await driver.waitFor(find.byValueKey(key), timeout: timeout);
  }

  Future<void> _waitForAbsent(
    String key, {
    Duration timeout = _controlWait,
  }) async {
    stage = '$_step:absent:$key';
    await driver.waitForAbsent(find.byValueKey(key), timeout: timeout);
  }

  // ── canonical 断言 ──

  Future<Map<String, dynamic>> _snapshot() => driver.readSnapshot();

  /// 点击检查并等到**新的** canonical 观察：只等“已是 Verified”会立即命中旧成功。
  Future<Map<String, dynamic>> _tapCheckAndAwait(
    String accountId,
    String kind,
  ) async {
    // 基线必须来自**同一 snapshot** 里已加载、且属于本账号当前连接身份的真实条目：
    // 全局 loaded 成立、或其它账号/旧连接身份有水位，都不构成目标证据。
    // `_authEntry` 内部按 accountId + 当前 connectionRevision 双匹配。
    final observed = await _until(
      'acp-auth-target-entry',
      (state) =>
          _acpAuthLoaded(state) &&
          _acpAccount(state, accountId) != null &&
          _authEntry(state, accountId) != null,
    );
    final before = _authRevision(observed);
    await _tap(_acpCheck);
    await _until(
      'auth-revision-advanced',
      (snapshot) => _authRevision(snapshot) > before,
    );
    return _awaitState(accountId, kind);
  }

  Future<Map<String, dynamic>> _awaitState(String accountId, String kind) =>
      _until(
        'state:$kind',
        (snapshot) => _stateKind(snapshot, accountId) == kind,
      );

  Future<String> _awaitSingleAccount(String kind) async {
    final snapshot = await _until('single-account:$kind', (state) {
      final accounts = _acpAccounts(state);
      if (accounts.length != 1) return false;
      final id = '${accounts.single['accountId']}';
      return _stateKind(state, id) == kind;
    });
    return '${_acpAccounts(snapshot).single['accountId']}';
  }

  Future<void> _awaitAcpAccountCount(int count) => _until(
    'acp-account-count:$count',
    (state) => _acpAccounts(state).length == count,
  );

  Future<Map<String, dynamic>> _until(
    String label,
    bool Function(Map<String, dynamic>) predicate, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    stage = '$_step:$label';
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await _snapshot();
      if (predicate(snapshot)) return snapshot;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('canonical ACP state did not settle: $label');
  }

  bool _isAnyCode(
    Map<String, dynamic> snapshot,
    String accountId,
    Set<String> codes,
  ) {
    final code = _failureCode(snapshot, accountId);
    return code != null && codes.contains(code);
  }

  // ── 证据 ──

  Future<void> _capture(String name) async {
    stage = '$_step:capture:$name';
    final snapshot = await _snapshot();
    final ordinal = _captureIndex++;
    final file = 'screenshot-$ordinal-$name.png';
    await File('${output.path}/$file').writeAsBytes(await driver.screenshot());
    await File('${output.path}/snapshot-$ordinal-$name.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
    );
    final tree = await driver.renderTree();
    await File('${output.path}/tree-$ordinal-$name.txt').writeAsString(tree);
    captures.add({
      'name': name,
      'file': file,
      'screenshot': true,
      'tree': true,
      'stage': stage,
      'scenario': _boundary?.name,
    });
  }

  /// 失败收尾：先做**有界**取证，再写 failed 摘要。
  ///
  /// 任一取证/写盘失败只记录原因并写 stderr，绝不覆盖 `main` 里传播的原始旅程错误；
  /// 证据存在也不改变 `status: failed`。
  Future<void> recordFailure({Object? error, StackTrace? stackTrace}) async {
    final diagnostics = <String, Object?>{
      'scenario': 'acp-account',
      'phase': phase,
      'stage': stage,
      'scenarioBoundary': _boundary?.name,
      'checks': checks,
      // 真实 shutdown 状态 + 完整 typed reply（内存优先；写盘失败单独记录）。
      'shutdown': _shutdownState,
      'shutdownEvidenceFile': ?_shutdownEvidenceFile,
      'shutdownReply': ?_shutdownReply,
      if (_shutdownWriteError.isNotEmpty)
        'shutdownWriteError': _shutdownWriteError,
      // 写盘本身的栈：与下面旅程错误的外层栈分开记录，避免互相覆盖。
      if (_shutdownWriteStackTrace.isNotEmpty)
        'shutdownWriteStackTrace': _shutdownWriteStackTrace,
      // 原始错误与栈只记录、不失真；收集证据失败不会覆盖它们。
      if (error != null) 'error': '$error',
      if (stackTrace != null) 'stackTrace': '$stackTrace',
    };
    await _collectFailureEvidence(diagnostics);
    try {
      // 用**真实观察到的** shutdown 状态（degraded/completed/…），不回退成未请求。
      await _writeSummary(status: 'failed', shutdown: _shutdownState);
    } on Object catch (error) {
      stderr.writeln('acp journey: failed to write summary: $error');
    }
    try {
      await File('${output.path}/acp-account-failure-$phase.json')
          .writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(diagnostics)}\n',
          );
    } on Object catch (error) {
      stderr.writeln(
        'acp journey: failed to write failure diagnostics: $error',
      );
    }
  }

  /// 失败路径的只读取证：截图 / snapshot / render tree / 关键控件存在性。
  ///
  /// 每步独立预算；失败原因写进 [diagnostics] 而不是抛出，避免遮蔽原始错误。
  Future<void> _collectFailureEvidence(Map<String, Object?> diagnostics) async {
    final ordinal = _captureIndex++;
    final base = '$ordinal-failure';
    try {
      final snapshot = await _snapshot().timeout(_failureEvidenceWait);
      await File('${output.path}/snapshot-$base.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
      );
      diagnostics['snapshotFile'] = 'snapshot-$base.json';
    } on Object catch (error) {
      diagnostics['snapshotError'] = '$error';
    }
    try {
      final bytes = await driver.screenshot().timeout(_failureEvidenceWait);
      final file = 'screenshot-$base.png';
      await File('${output.path}/$file').writeAsBytes(bytes);
      captures.add({
        'name': 'failure',
        'file': file,
        'screenshot': true,
        'stage': stage,
        'scenario': _boundary?.name,
      });
      diagnostics['screenshotFile'] = file;
    } on Object catch (error) {
      diagnostics['screenshotError'] = '$error';
    }
    try {
      final tree = await driver.renderTree().timeout(_failureEvidenceWait);
      await File('${output.path}/tree-$base.txt').writeAsString(tree);
      diagnostics['treeFile'] = 'tree-$base.txt';
    } on Object catch (error) {
      diagnostics['treeError'] = '$error';
    }
    // 关键控件存在性：只读、逐个有界；用于区分“没构建/没展开/没进入该页”。
    final presence = <String, bool>{};
    for (final key in _diagnosticKeys) {
      presence[key] = await _presentQuiet(
        key,
        timeout: const Duration(milliseconds: 800),
      );
    }
    diagnostics['controls'] = presence;
    // 高级 argv 的真实展开态（官方 `Expansible.controller.isExpanded`）。
    // 只读；不可用时记录原因，仍不改动原始错误与 status。
    if (presence[_acpArgs] == true) {
      try {
        diagnostics['argvExpanded'] = await _probeArgsExpanded();
      } on Object catch (error) {
        diagnostics['argvExpandedError'] = '$error';
      }
    }
  }

  Future<void> _writeSummary({
    required String status,
    required String shutdown,
  }) async {
    final payload = {
      'scenario': 'acp-account',
      'phase': phase,
      'verdict': 'pending',
      'status': status,
      'stage': stage,
      'shutdown': shutdown,
      'failedChecks': _failedChecks(),
      'checks': checks,
      'captures': captures,
      'scenarios': scenarios,
      'program': fixture.program,
    };
    await File(
      '${output.path}/acp-account-summary-$phase.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
  }

  // ── 宿主操作 ──

  Future<void> _requestExit() async {
    stage = '$_step:request-app-exit';
    try {
      await driver.requestData(
        'request-app-exit',
        timeout: const Duration(seconds: 30),
      );
    } catch (_) {
      // 退出开始后 Driver 连接可能先断开；这不是失败证据。
    }
  }

  /// 请求 typed shutdown 并落盘其完整 reply。
  ///
  /// 内存中的 reply 与真实状态先于写盘保存：缺证据时失败摘要仍报告真实关闭结果，
  /// 不会回落成 not-requested；而写盘失败本身即取证失败（见
  /// [_ShutdownEvidenceFailure]），旅程不得在没有 shutdown 证据的情况下判通过。
  Future<String> _requestShutdown() async {
    stage = 'typed-shutdown';
    final raw = await driver.requestData(
      'shutdown',
      timeout: const Duration(seconds: 120),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw StateError('shutdown reply is not an object');
    final reply = decoded.cast<String, dynamic>();
    // 先保存内存中的**完整** typed reply 与真实状态，再尝试写盘：写盘失败不能把
    // “业务关闭已发生”改回 not-requested。
    _shutdownReply = reply;
    _shutdownState = '${reply['shutdown']}';
    final file = 'acp-shutdown-$phase.json';
    try {
      await File(
        '${output.path}/$file',
      ).writeAsString('${const JsonEncoder.withIndent('  ').convert(reply)}\n');
      _shutdownEvidenceFile = file;
    } on Object catch (error, writeStackTrace) {
      _shutdownWriteError = '$error';
      // 底层写盘栈单独保留：包装错误由 `main` 再收集外层栈，两者互不覆盖。
      _shutdownWriteStackTrace = '$writeStackTrace';
      stderr.writeln('acp journey: failed to write shutdown evidence: $error');
      stderr.writeln('$writeStackTrace');
      // 写盘失败即取证失败：业务关闭**已经发生**（`_shutdownState` 保留真实值，
      // 失败摘要据此报告），但缺少 shutdown 证据的旅程不得判通过，也不能被当成
      // 未请求关闭。
      throw _ShutdownEvidenceFailure(
        file: file,
        shutdown: _shutdownState,
        cause: error,
        causeStackTrace: writeStackTrace,
      );
    }
    return _shutdownState;
  }

  /// 缩小窗口并确认布局真的变了。窄窗是本计划必验项：pid/resize 失败必须明确失败，
  /// 不能静默跳过（跳过会让“窄窗已覆盖”变成无证据的声明）。
  Future<void> _narrowWindow({required int width, required int height}) async {
    final pid = await _pid();
    if (pid == null) {
      throw StateError('driver exposed no GUI pid for window resize');
    }
    final before = await _awaitLayoutRightEdge();
    final result = resizeOwnedWindow(guiPid: pid, width: width, height: height);
    if (!result.resized) {
      throw StateError('cannot resize the GUI window (${result.reason})');
    }
    _originalWindow ??= result.original;
    _guiPid = pid;
    _narrowedLayoutRight = await _awaitLayoutRightEdge(below: before - 1);
    checks['narrowWindowResized'] = true;
  }

  Future<void> _restoreWindow() async {
    final original = _originalWindow;
    final pid = _guiPid;
    if (original == null || pid == null) return;
    final narrowed = _narrowedLayoutRight;
    final restored = resizeOwnedWindow(
      guiPid: pid,
      width: original.width,
      height: original.height,
    );
    if (!restored.resized) {
      throw StateError(
        'acp journey: could not restore the GUI window (${restored.reason})',
      );
    }
    await _awaitLayoutRightEdge(above: narrowed == null ? null : narrowed + 1);
  }

  /// 窗口尺寸变化后的**真实布局条件**：设置页根的右边缘必须随窗口改变。
  ///
  /// 不等待“无待处理帧”或光标动画停止（聚焦输入会持续产生帧），也不用固定 sleep
  /// 冒充布局就绪。只读几何命令自带 5s 预算，整体再受本轮 timeout 约束。
  Future<double> _awaitLayoutRightEdge({
    double? below,
    double? above,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    stage = '$_step:layout-width:below=$below,above=$above';
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final right = (await driver.getBottomRight(
          find.byValueKey(_settingsPage),
        )).dx;
        if ((below == null || right < below) &&
            (above == null || right > above)) {
          return right;
        }
      } on Object catch (error) {
        // 尚未完成布局：在预算内重试只读几何读取。
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'window layout did not settle (below=$below above=$above, '
      'last=${lastError ?? 'unchanged'})',
    );
  }

  Future<int?> _pid() async {
    // 生产 Driver 入口按**原始 message** 分派（`pid`/`shutdown`/`request-app-exit`
    // 都是纯字符串命令）；查询同样有界，不把无超时请求留在旅程里。
    stage = '$_step:query-pid';
    final raw = await driver.requestData(
      'pid',
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final pid = decoded['pid'];
    return pid is int ? pid : int.tryParse('$pid');
  }

  /// 正向存在探针（只用于“存在”类 check）：失败即 false → 该 check 失败。
  /// **不能**用于“缺席”类断言，缺席必须用 [_visible] 的正向 `waitForAbsent`。
  Future<bool> _present(String key) async {
    try {
      await driver.waitFor(
        find.byValueKey(key),
        timeout: const Duration(seconds: 10),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _presentQuiet(
    String key, {
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    try {
      await driver.waitFor(find.byValueKey(key), timeout: timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 正向存在/缺席判定：存在由 `waitFor` 正常完成证明，缺席由 `waitForAbsent`
  /// 正常完成证明。两者都无法确认时（含连接/传输故障）原样抛错——
  /// 绝不把“未知”当成 false，也不把诊断用探针的 false 当作通过判据。
  Future<bool> _visible(String key, {Duration timeout = _probeWait}) async {
    stage = '$_step:probe:$key';
    try {
      await driver.waitFor(find.byValueKey(key), timeout: timeout);
      return true;
    } on Object catch (error, stackTrace) {
      try {
        await driver.waitForAbsent(find.byValueKey(key), timeout: timeout);
        return false;
      } on Object {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  /// 真实文本保留断言：读取输入控件本体；不等即失败（截图名不能替代证据）。
  Future<void> _assertTextRetained(
    String inputKey,
    String expected, {
    required String label,
  }) async {
    _enterStep('retain-text:$label');
    await _revealInEditor(inputKey);
    final String actual;
    try {
      actual = await driver
          .getText(find.byValueKey(inputKey))
          .timeout(_controlWait);
    } on Object {
      stage = '$_step:read-text-failed:$inputKey';
      rethrow;
    }
    if (actual != expected) {
      throw StateError('$label: "$inputKey" lost its text ("$actual")');
    }
    checks['textRetained:$label'] = true;
  }

  /// ACP 编辑现场保留：程序与每个 argv 的真实文本都必须在（跨 820 断点）。
  ///
  /// 若布局重建丢了草稿，argv 行会随之消失，这里会以具体 key 的
  /// `reveal`/`read-text` 失败暴露，而不是拍到一张“已是列表页”的图当表单证据。
  Future<void> _assertAcpDraftRetained({
    required String program,
    required List<String> args,
    required String label,
  }) async {
    _enterStep('retain-draft:$label');
    await _assertTextRetained(
      _acpProgramInput,
      program,
      label: '$label/program',
    );
    for (var index = 0; index < args.length; index++) {
      await _assertTextRetained(
        'acp-account-arg-$index-input',
        args[index],
        label: '$label/argv$index',
      );
    }
    checks['draftRetained:$label'] = true;
  }

  List<String> _fixtureArgs() => [
    '--acp-stdio',
    '--acp-state-dir',
    fixture.stateDir.path,
  ];

  String _longProgramPath() =>
      '${fixture.stateDir.path}/'
      'antigravity-gateway-server-with-a-very-long-executable-name/bin/server';

  String _missingProgramPath() =>
      '${fixture.stateDir.path}/missing-acp-server/host';

  /// 与 fixture 等价但顺序不同的 argv：同一个可执行文件、同一个 state 目录。
  List<String> _alternateArgs() => [
    '--acp-state-dir',
    fixture.stateDir.path,
    '--acp-stdio',
  ];
}

/// shutdown 取证写盘失败。
///
/// 业务关闭**已经发生**（[shutdown] 是内存里真实观察到的 typed 状态），只是证据文件
/// 没有落盘；旅程必须失败，不能在没有 shutdown 证据时判通过，也不能把关闭结果误报成
/// 未请求。原始写盘错误与其栈保留为 [cause] / [causeStackTrace]，分别进入失败摘要的
/// `shutdownWriteError` / `shutdownWriteStackTrace`。
final class _ShutdownEvidenceFailure implements Exception {
  const _ShutdownEvidenceFailure({
    required this.file,
    required this.shutdown,
    required this.cause,
    required this.causeStackTrace,
  });

  final String file;
  final String shutdown;
  final Object cause;

  /// 底层写盘异常的栈；外层抛出栈由 `main` 收集，二者分开保留。
  final StackTrace causeStackTrace;

  @override
  String toString() =>
      'failed to write shutdown evidence $file '
      '(typed shutdown: $shutdown): $cause';
}

/// 一次“保存并连接”之后的收敛结果（两条合法路径的统一形状）。
class _ConfigSaveConvergence {
  _ConfigSaveConvergence({
    required this.snapshot,
    required this.connectionRevision,
    required this.autoProbe,
    required this.explicitProbe,
    required this.settledKind,
    required this.firstKindAfterChange,
    required this.firstOperationId,
  });

  final Map<String, dynamic> snapshot;
  final int connectionRevision;
  final bool autoProbe;
  final bool explicitProbe;
  final String settledKind;
  final String firstKindAfterChange;
  final String? firstOperationId;
}

class _ScenarioBoundary {
  _ScenarioBoundary({
    required this.name,
    required this.eventsFrom,
    required this.clearedCredential,
  });

  final String name;
  final int eventsFrom;
  final bool clearedCredential;
}

/// 一个场景窗口内的 fake 证据；只由该窗口之后的记录推导。
///
/// `AuthenticateReleased` 在“等待后放行”和“被取消”两个分支都会写，因此它本身既不能
/// 证明成功、也不能证明某次取消；必须结合本场景水位、同 PID、`sessionNew` 顺序与
/// `auth-release`/`authenticated` 标记才能得出结论。检查（probe）则看同 PID 的
/// initialize → session/new 且**没有** authenticate。
class _AttemptEvidence {
  _AttemptEvidence({
    required this.authenticatePid,
    required this.authenticateCount,
    required this.releasedPid,
    required this.sessionNewPid,
    required this.sessionNewCount,
    required this.initializePid,
    required this.initializeCount,
    required this.releasedAfterAuthenticate,
    required this.sessionNewAfterRelease,
    required this.sessionNewAfterReleaseForAttempt,
    required this.sessionNewAfterInitialize,
  });

  factory _AttemptEvidence.from(List<Map<String, dynamic>> events) {
    var authenticateIndex = -1;
    int? authenticatePid;
    var authenticateCount = 0;
    var releasedIndex = -1;
    int? releasedPid;
    var sessionNewIndex = -1;
    int? sessionNewPid;
    var sessionNewCount = 0;
    var sessionNewAfterReleaseForAttempt = false;
    var initializeIndex = -1;
    int? initializePid;
    var initializeCount = 0;
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final name = '${event['event']}';
      final pid = event['pid'] is int ? event['pid'] as int : null;
      if (name == 'authenticate') {
        authenticateCount += 1;
        if (authenticatePid == null) {
          authenticatePid = pid;
          authenticateIndex = index;
        }
      } else if (name == 'authenticateReleased') {
        if (authenticatePid != null && pid == authenticatePid) {
          releasedPid ??= pid;
          if (releasedIndex < 0) {
            releasedIndex = index;
          }
        }
      } else if (name == 'sessionNew') {
        sessionNewCount += 1;
        if (sessionNewPid == null) {
          sessionNewPid = pid;
          sessionNewIndex = index;
        }
        if (authenticatePid != null &&
            pid == authenticatePid &&
            releasedIndex >= 0 &&
            index > releasedIndex) {
          sessionNewAfterReleaseForAttempt = true;
        }
      } else if (name == 'initialize') {
        initializeCount += 1;
        if (initializePid == null) {
          initializePid = pid;
          initializeIndex = index;
        }
      }
    }
    return _AttemptEvidence(
      authenticatePid: authenticatePid,
      authenticateCount: authenticateCount,
      releasedPid: releasedPid,
      sessionNewPid: sessionNewPid,
      sessionNewCount: sessionNewCount,
      initializePid: initializePid,
      initializeCount: initializeCount,
      releasedAfterAuthenticate:
          authenticateIndex >= 0 && releasedIndex > authenticateIndex,
      sessionNewAfterRelease:
          releasedIndex >= 0 &&
          sessionNewIndex >= 0 &&
          sessionNewIndex > releasedIndex,
      sessionNewAfterReleaseForAttempt: sessionNewAfterReleaseForAttempt,
      sessionNewAfterInitialize:
          initializeIndex >= 0 &&
          sessionNewIndex >= 0 &&
          sessionNewIndex > initializeIndex,
    );
  }

  final int? authenticatePid;
  final int authenticateCount;
  final int? releasedPid;
  final int? sessionNewPid;
  final int sessionNewCount;
  final int? initializePid;
  final int initializeCount;
  final bool releasedAfterAuthenticate;
  final bool sessionNewAfterRelease;
  final bool sessionNewAfterReleaseForAttempt;
  final bool sessionNewAfterInitialize;

  /// 本次窗口确实做了一次连接检查：同 PID 的 initialize → session/new，且没有登录。
  bool get coversProbe =>
      initializeCount >= 1 &&
      sessionNewCount >= 1 &&
      authenticateCount == 0 &&
      initializePid == sessionNewPid &&
      sessionNewAfterInitialize;

  /// 本次窗口是一次真实收束：同 PID、login 被受理后按顺序释放，且释放后没有再用
  /// 该进程做 session/new（即不是“放行成功后的校验”）。
  bool get isOrderedCancellation =>
      authenticatePid != null &&
      releasedPid == authenticatePid &&
      releasedAfterAuthenticate &&
      !sessionNewAfterReleaseForAttempt;
}

/// fake ACP Agent 的状态目录：只操作它自己的控制文件与证据。
class _Fixture {
  _Fixture({required this.program, required this.stateDir});

  final String program;
  final Directory stateDir;

  File get _behavior => File('${stateDir.path}/behavior.json');
  File _marker(String name) => File('${stateDir.path}/$name');

  Future<Map<String, dynamic>> _readBehavior() async {
    if (!_behavior.existsSync()) {
      return {'authentication': 'success', 'probe': 'normal'};
    }
    final decoded = jsonDecode(await _behavior.readAsString());
    if (decoded is! Map) throw StateError('behavior.json is not an object');
    return decoded.cast<String, dynamic>();
  }

  /// 修改 fake 行为；未指定的键保持 harness 设定的值。
  Future<void> patchBehavior({
    String? authentication,
    String? probe,
    bool? disconnect,
  }) async {
    final current = await _readBehavior();
    final next = {
      ...current,
      'authentication': authentication ?? current['authentication'],
      'probe': probe ?? current['probe'],
      'disconnect': disconnect ?? current['disconnect'] ?? false,
    };
    await _behavior.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(next)}\n',
    );
  }

  /// 重置本场景自己的控制文件：release/started 必须清掉，否则下一次等待立即成功。
  Future<void> resetOwnControls({required bool clearCredential}) async {
    for (final name in const ['auth-started', 'auth-release']) {
      final file = _marker(name);
      if (file.existsSync()) file.deleteSync();
    }
    if (clearCredential) {
      final credential = _marker('authenticated');
      if (credential.existsSync()) credential.deleteSync();
    }
  }

  Future<void> releaseAuth() =>
      _marker('auth-release').writeAsString('release\n');

  Future<bool> markerExists(String name) async => _marker(name).exists();

  Future<int> eventCount() async => (await events()).length;

  Future<List<Map<String, dynamic>>> eventsSince(int from) async {
    final events = await this.events();
    if (from >= events.length) return const [];
    return events.sublist(from);
  }

  Future<List<Map<String, dynamic>>> events() async {
    final file = File('${stateDir.path}/events.jsonl');
    if (!file.existsSync()) return const [];
    final lines = await file.readAsLines();
    final events = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        events.add((jsonDecode(line) as Map).cast<String, dynamic>());
      } on FormatException {
        // 仍在写入的最后一行忽略；完整行必须是 typed 记录。
        continue;
      }
    }
    return events;
  }
}

/// canonical 快照读取：`settings.acpAccounts` 与 `settings.acpAuth`。
List<Map<String, dynamic>> _acpAccounts(Map<String, dynamic> snapshot) {
  final settings = snapshot['settings'];
  if (settings is! Map) return const [];
  final accounts = settings['acpAccounts'];
  if (accounts is! List) return const [];
  return [
    for (final account in accounts) (account as Map).cast<String, dynamic>(),
  ];
}

Map<String, dynamic>? _acpAccount(Map<String, dynamic> snapshot, String id) =>
    _acpAccounts(snapshot)
        .where((account) => account['accountId'] == id)
        .firstOrNull;

/// canonical ACP 观察是否已加载；缺失或非 `true` 都不算事实。
bool _acpAuthLoaded(Map<String, dynamic> snapshot) {
  final settings = snapshot['settings'];
  if (settings is! Map) return false;
  final auth = settings['acpAuth'];
  if (auth is! Map) return false;
  return auth['loaded'] == true;
}

/// 认证观察的 canonical revision；未加载或类型不符即如实失败，绝不以 0 伪造
/// “已前进”证据。
int _authRevision(Map<String, dynamic> snapshot) {
  if (!_acpAuthLoaded(snapshot)) {
    throw StateError('settings.acpAuth is not loaded yet');
  }
  final auth = (snapshot['settings'] as Map)['acpAuth'] as Map;
  final revision = auth['revision'];
  if (revision is! int) {
    throw StateError('settings.acpAuth.revision is not an int: $revision');
  }
  return revision;
}

/// 认证观察只在 **账号身份 + 连接身份** 同时匹配时可用。
Map<String, dynamic>? _authEntry(Map<String, dynamic> snapshot, String id) {
  final account = _acpAccount(snapshot, id);
  final revision = account?['connectionRevision'];
  if (revision == null) return null;
  final settings = snapshot['settings'];
  if (settings is! Map) return null;
  final auth = settings['acpAuth'];
  if (auth is! Map) return null;
  final accounts = auth['accounts'];
  if (accounts is! List) return null;
  for (final entry in accounts) {
    if (entry is! Map) continue;
    if (entry['accountId'] != id) continue;
    if (entry['connectionRevision'] != revision) continue;
    return entry.cast<String, dynamic>();
  }
  return null;
}

/// 实际观察到的 canonical 状态；未加载、无条目或连接身份不匹配时返回 null。
///
/// null **不是** unchecked：只有对端真的发布了 `Unchecked` 条目才算未检查。
String? _observedKind(Map<String, dynamic> snapshot, String id) {
  if (!_acpAuthLoaded(snapshot)) return null;
  final state = _authEntry(snapshot, id)?['state'];
  return state is Map ? '${state['kind']}' : null;
}

/// 诊断/等待用的描述；没有事实时明确写 `unloaded`，不冒充 `unchecked`。
String _stateKind(Map<String, dynamic> snapshot, String id) =>
    _observedKind(snapshot, id) ?? 'unloaded';

String? _stateOperationId(Map<String, dynamic> snapshot, String id) {
  final state = _authEntry(snapshot, id)?['state'];
  return state is Map ? state['operationId'] as String? : null;
}

String? _failureCode(Map<String, dynamic> snapshot, String id) {
  final failure = _authEntry(snapshot, id)?['state'];
  if (failure is! Map) return null;
  final value = failure['failure'];
  return value is Map ? value['code'] as String? : null;
}

bool _sameArgs(Object? value, List<String> expected) {
  if (value is! List || value.length != expected.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if ('${value[index]}' != expected[index]) return false;
  }
  return true;
}

String? _firstNativeTemplate(Map<String, dynamic> snapshot) {
  final settings = snapshot['settings'];
  if (settings is! Map) return null;
  final templates = settings['nativeTemplates'];
  if (templates is! List || templates.isEmpty) return null;
  return '${templates.first}';
}
