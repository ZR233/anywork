// Antigravity（ACP）官方 server 自动准备 + 保存/认证的真实 bridge 人工验收旅程。
//
// 用法（由 pl-studio-acceptance 的 `acp-auto-install` 场景驱动）：
//   cargo dart test_driver/acp_install_journey.dart VM_URL OUTPUT_DIR PHASE \
//     [FIXTURE_STATE_DIR]
//
// PHASE：first | auth-faults | restart | resume | cancel | retry | reuse |
//        faults-unsafe-zip。仅 auth-faults 接受且必须提供绝对合成状态目录。
//
// 输出 `OUTPUT_DIR/acp-auto-install-summary-<phase>.json`：
// scenario/phase/status/stage/checks/failedChecks/captures/failures/install/
// shutdown/exitRequest/humanVerdict，以及真实保存后的 savedAccount 和取消瞬态观察。
// cancellingObservation 记录 canonical 观察与可选截图结果，不声称瞬态一定已渲染。
// 旅程只驱动 GUI
// 与只读 canonical 快照；auth-faults 只控制 harness 明确传入的合成 fixture 目录，
// 不修改 Google 凭据、产品配置或网络 peer，不用固定 sleep 制造状态；截图前必须等真实
// 可见阶段。所有等待与关闭都有界，失败仍走真实退出/回收。
//
// 同一 OUTPUT_DIR 顺序跑多个 phase：三类证据文件
// （`screenshot-`/`snapshot-`/`tree-<phase>-<ordinal>-<name>`）都带 phase 段，
// 后一阶段不会覆盖前一阶段的产物；captures 同时用 `file`/`snapshotFile`/
// `treeFile` 显式给出引用，消费者不需要从文件名猜快照。
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';

import 'acp_fixture.dart';
import 'flutter_driver_session.dart';
import 'window_control.dart';

const _scenario = 'acp-auto-install';

const _settingsOpen = 'settings-open';
const _settingsPage = 'settings-page';
const _settingsAccountsTab = 'settings-tab-accounts';
const _accountAdd = 'account-add';
const _accountSave = 'account-save';
const _accountCancel = 'account-cancel';
final _acpCheck = AccountViewKeyValues.acpAction('check');
final _acpLogin = AccountViewKeyValues.acpAction('login');
final _acpCancelAuth = AccountViewKeyValues.acpAction('cancelAuthentication');
const _acpBack = 'account-back';
final _installPrepare = AccountViewKeyValues.acpAction('prepare');
final _installCancel = AccountViewKeyValues.acpAction('cancelPreparation');

const _antigravityToken = 'acp-antigravity';
const _providerWire = 'antigravity';

const _controlWait = Duration(seconds: 20);
const _startupWait = Duration(seconds: 90);
const _installWait = Duration(minutes: 15);
const _closeWait = Duration(seconds: 5);

const _phases = {
  'first',
  'auth-faults',
  'restart',
  'resume',
  'cancel',
  'retry',
  'reuse',
  'faults-unsafe-zip',
};

/// Local generations may advance while waiting for the initial observation.
/// The offered action, not a fixed generation, proves local preparation ended.
bool _isUnclaimedSharedReady(Map? editor, Map? panel) {
  final generation = panel?['preparationGeneration'];
  final actions = panel?['actions'];
  return generation is int &&
      generation >= 0 &&
      panel?['phase'] == 'ready' &&
      panel?['claimedOperationId'] == null &&
      panel?['preparedForEditor'] == false &&
      editor?['canSave'] == false &&
      actions is List &&
      actions.contains('usePrepared');
}

/// The production panel uses plain Text/SelectableText for status, facts and
/// progress. Only a complete, identified panel can prove a label is absent.
bool _acpPanelHasText(Map<String, dynamic> root, String text) {
  if (root['widgetRuntimeType'] != 'AcpAccountPanel') {
    throw StateError('no production ACP panel diagnostics');
  }
  var found = false;
  var textNodes = 0;
  void visit(Map node) {
    final children = node['children'];
    if (node['truncated'] == true ||
        (node['hasChildren'] == true &&
            (children is! List || children.isEmpty))) {
      throw StateError('ACP panel diagnostics were truncated');
    }
    final properties = node['properties'];
    final type = node['widgetRuntimeType'];
    if (type == 'Offstage') {
      final flags = properties is List
          ? properties
                .whereType<Map>()
                .where((property) => property['name'] == 'offstage')
                .toList()
          : const <Map>[];
      if (flags.length != 1 || flags.single['value'] is! bool) {
        throw StateError('ACP panel has no observed offstage flag');
      }
      if (flags.single['value'] == true) return;
    }
    if (type == 'Text' || type == 'SelectableText') {
      final values = properties is List
          ? properties
                .whereType<Map>()
                .where((property) => property['name'] == 'data')
                .toList()
          : const <Map>[];
      if (values.length != 1 || values.single['value'] is! String) {
        throw StateError('ACP panel text diagnostics are incomplete');
      }
      textNodes++;
      if (values.single['value'] == text) found = true;
    }
    if (children is List) {
      for (final child in children) {
        if (child is! Map) {
          throw StateError('invalid ACP panel diagnostic child');
        }
        visit(child);
      }
    }
  }

  visit(root);
  if (textNodes == 0) throw StateError('ACP panel has no observed text');
  return found;
}

Future<void> main(List<String> args) async {
  final phase = args.length >= 3 ? args[2] : null;
  if (phase == null ||
      !_phases.contains(phase) ||
      args.length != (phase == 'auth-faults' ? 4 : 3) ||
      (phase == 'auth-faults' && !Directory(args[3]).isAbsolute)) {
    stderr.writeln(
      'usage: acp_install_journey.dart VM_URL OUTPUT_DIR '
      '${_phases.join('|')} [FIXTURE_STATE_DIR (auth-faults only)]',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(args[1]);
  await output.create(recursive: true);
  final journey = _Journey(
    output: output,
    phase: phase,
    fixture: phase == 'auth-faults'
        ? AcpFixture(stateDir: Directory(args[3]))
        : null,
  );
  FlutterDriverSession? driver;
  try {
    driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
    journey.attach(driver);
    await journey.run();
  } on Object catch (error, stackTrace) {
    stderr.writeln('$_scenario $phase failed at ${journey.stage}: $error');
    stderr.writeln('$stackTrace');
    await journey.recordFailure(error: error, stackTrace: stackTrace);
  } finally {
    // 关闭有界；关闭超时/未知异常一律是失败证据（包括已请求退出的情形）。
    try {
      await driver?.close().timeout(_closeWait);
    } catch (error) {
      stderr.writeln('$_scenario $phase: driver close failed: $error');
      journey.recordCloseFailure(error);
    }
    // 只有这里同时拥有“业务结果 + 退出确认 + close 结果”，最终 summary 在此
    // 一次性完整落盘；成功不会被先前某次写入覆盖，失败也保留最后证据。
    try {
      final status = await journey.writeFinalSummary();
      if (status != 'completed') exitCode = 1;
    } on Object catch (error, stackTrace) {
      stderr.writeln('$_scenario $phase: writing summary failed: $error');
      stderr.writeln('$stackTrace');
      exitCode = 1;
    }
  }
}

/// 最终 summary 的状态判定：全部条件为真才算 completed。
///
/// 通过要求：旅程走到成功终点、没有失败项、`failedChecks` 为空、typed shutdown
/// 真实 completed，并且退出请求被确认。close 失败稍后由 [acpInstallSummaryPayload]
/// 之外的调用方追加为失败项，因此这里以最终 failures 为准。
String acpInstallFinalStatus({
  required bool succeeded,
  required Map<String, bool> checks,
  required List<Map<String, Object?>> failures,
  required String? shutdown,
  required Map<String, Object?>? exitRequest,
}) {
  final failedChecks = checks.entries
      .where((entry) => !entry.value)
      .map((entry) => entry.key)
      .toList(growable: false);
  final acknowledged =
      exitRequest?['requested'] == true && exitRequest?['acknowledged'] == true;
  final completed =
      succeeded &&
      checks.isNotEmpty &&
      failures.isEmpty &&
      failedChecks.isEmpty &&
      shutdown == 'completed' &&
      acknowledged;
  return completed ? 'completed' : 'failed';
}

/// Driver 的独立验收期望，不消费生产映射或被测 release 的 target。
/// manual-gui 的 Driver 与 backend 同机，以官方 ABI API 和实际 OS 固定宿主。
Map<String, Object?> _requireFixedRelease(Object? release) {
  final (target, archive) = switch ((Platform.operatingSystem, Abi.current())) {
    ('linux', Abi.linuxX64) => (
      'linux-x86_64',
      'linux/agy-acp-server-1.4.1-linux-x86_64.zip',
    ),
    ('linux', Abi.linuxArm64) => (
      'linux-aarch64',
      'linux/agy-acp-server-1.4.1-linux-arm64.zip',
    ),
    ('windows', Abi.windowsX64) => (
      'windows-x86_64',
      'windows/agy-acp-server-1.4.1-windows-x86_64.zip',
    ),
    ('windows', Abi.windowsArm64) => (
      'windows-aarch64',
      'windows/agy-acp-server-1.4.1-windows-arm64.zip',
    ),
    _ => throw StateError(
      'unsupported acceptance backend: '
      '${Platform.operatingSystem}/${Abi.current()}',
    ),
  };
  final archiveUrl = 'https://dl.google.com/agy-extensions/releases/$archive';
  if (release is! Map ||
      release['version'] != '1.4.1' ||
      release['target'] != target ||
      release['archiveUrl'] != archiveUrl ||
      !release.containsKey('sha256') ||
      release['sha256'] != null) {
    throw StateError(
      'expected complete fixed release 1.4.1/$target/$archiveUrl '
      'with sha256=null, observed $release',
    );
  }
  return {
    'version': release['version'],
    'target': release['target'],
    'archiveUrl': release['archiveUrl'],
    'sha256': release['sha256'],
  };
}

bool _cancelledOperationValid(Object? install, Object? cancelled) {
  if (cancelled is! Map ||
      install is! Map ||
      install['loaded'] != true ||
      install['installations'] is! List) {
    return false;
  }
  final operation = cancelled['operationId'];
  if (operation is! String || operation.trim().isEmpty) {
    return false;
  }
  final entries = (install['installations'] as List)
      .whereType<Map>()
      .where((entry) => entry['provider'] == _providerWire)
      .toList();
  if (entries.length != 1 ||
      entries.single['phase'] != 'cancelled' ||
      entries.single['operationId'] != operation) {
    return false;
  }
  try {
    _requireFixedRelease(cancelled['release']);
    return true;
  } on StateError {
    return false;
  }
}

const _cancelActionChecks = [
  'cancelActionSent',
  'cancelHasOperation',
  'cancelReleaseCaptured',
  'cancelledKeepsOriginalOperation',
  'cancelledDidNotSave',
];
const _cancelRequiredChecks = [
  ..._cancelActionChecks,
  'cancelledOperationRecorded',
  'cancellingObservationRecorded',
];

bool _cancellingObservationValid(
  Object? observation,
  Object? cancelled,
  Object? captures,
) {
  if (observation is! Map ||
      cancelled is! Map ||
      captures is! List ||
      !captures.every((entry) => entry is Map)) {
    return false;
  }
  final operation = observation['operationId'];
  final reason = observation['reason'];
  if (operation is! String ||
      operation.trim().isEmpty ||
      operation != cancelled['operationId'] ||
      reason is! String ||
      reason.trim().isEmpty) {
    return false;
  }
  final matching = captures
      .whereType<Map>()
      .where((entry) => entry['name'] == 'cancelling')
      .toList();
  return switch (observation['capture']) {
    'captured' =>
      observation['observed'] == true &&
          matching.length == 1 &&
          matching.single['phase'] == 'cancelling' &&
          matching.single['screenshot'] == true &&
          const ['file', 'snapshotFile', 'treeFile'].every((key) {
            final reference = matching.single[key];
            return reference is String && reference.trim().isNotEmpty;
          }),
    'not-observed' => observation['observed'] == false && matching.isEmpty,
    'phase-changed' => observation['observed'] == true && matching.isEmpty,
    _ => false,
  };
}

/// 供 first/retry 的后续生命周期消费完成证据；不会修改旧文件或相信顶层 status 自证。
void requireAcpInstallCompletedSummary(
  Map<String, dynamic> summary, {
  required String phase,
}) {
  final checks = summary['checks'];
  final failed = summary['failedChecks'];
  final failures = summary['failures'];
  final exit = summary['exitRequest'];
  final trusted =
      summary['scenario'] == _scenario &&
      summary['phase'] == phase &&
      summary['status'] == 'completed' &&
      checks is Map &&
      checks.isNotEmpty &&
      checks.values.every((check) => check == true) &&
      (phase != 'cancel' ||
          (_cancelRequiredChecks.every((key) => checks[key] == true) &&
              _cancelledOperationValid(
                summary['install'],
                summary['cancelledOperation'],
              ) &&
              _cancellingObservationValid(
                summary['cancellingObservation'],
                summary['cancelledOperation'],
                summary['captures'],
              ))) &&
      failed is List &&
      failed.isEmpty &&
      failures is List &&
      failures.isEmpty &&
      summary['shutdown'] == 'completed' &&
      exit is Map &&
      exit['requested'] == true &&
      exit['acknowledged'] == true;
  if (!trusted) {
    throw StateError('$phase evidence is not a trusted completion');
  }
}

/// Driver 最终 summary 的唯一构造入口：请求/确认事实与状态在同一次构造里确定。
Map<String, Object?> acpInstallSummaryPayload({
  required String phase,
  required String stage,
  required bool succeeded,
  required Map<String, bool> checks,
  required List<Map<String, Object?>> captures,
  required List<Map<String, Object?>> failures,
  required Map<String, dynamic> install,
  required String? shutdown,
  required Map<String, Object?>? exitRequest,
  Map<String, Object?>? cancelledOperation,
  Map<String, Object?>? cancellingObservation,
  Map<String, Object?>? savedAccount,
}) {
  final savedId = savedAccount?['accountId'];
  final finalChecks = {
    ...checks,
    if (phase == 'first' || phase == 'retry')
      'savedAccountIdentityRecorded':
          savedId is String &&
          savedId.isNotEmpty &&
          savedAccount?['connectionRevision'] is int,
    if (phase == 'cancel') ...{
      for (final key in _cancelActionChecks) key: checks[key] == true,
      'cancelledOperationRecorded': _cancelledOperationValid(
        install,
        cancelledOperation,
      ),
      'cancellingObservationRecorded': _cancellingObservationValid(
        cancellingObservation,
        cancelledOperation,
        captures,
      ),
    },
  };
  final failedChecks = finalChecks.entries
      .where((entry) => !entry.value)
      .map((entry) => entry.key)
      .toList(growable: false);
  final payload = <String, Object?>{
    'scenario': _scenario,
    'phase': phase,
    'status': acpInstallFinalStatus(
      succeeded: succeeded && checks.isNotEmpty,
      checks: finalChecks,
      failures: failures,
      shutdown: shutdown,
      exitRequest: exitRequest,
    ),
    'stage': stage,
    'checks': finalChecks,
    'failedChecks': failedChecks,
    'captures': captures,
    'failures': failures,
    'install': install,
    'shutdown': shutdown ?? 'not-requested',
    'exitRequest': exitRequest,
    'humanVerdict': 'pending',
  };
  if (cancelledOperation != null) {
    payload['cancelledOperation'] = cancelledOperation;
  }
  if (phase == 'cancel' || cancellingObservation != null) {
    payload['cancellingObservation'] = cancellingObservation;
  }
  if (savedAccount != null) payload['savedAccount'] = savedAccount;
  return payload;
}

/// 单条截图证据的唯一构造入口：三类产物文件名都带 phase 段。
///
/// 同一 OUTPUT_DIR 会顺序跑多个 phase（first/resume/cancel/retry/reuse/
/// auth-faults/restart/faults-*），阶段内的 ordinal 会从 0 重新计数；文件名不含 phase 段时
/// 后一阶段会覆盖前一阶段的截图/快照/树，前阶段 summary 的引用随之指错证据。
///
/// `phase` 仍是**观察到的安装阶段**（idle/downloading/ready/…），与运行 phase
/// 分开：消费者按字段读快照与树，不从文件名推断任何状态。
Map<String, Object?> acpInstallCaptureEntry({
  required String phase,
  required int ordinal,
  required String name,
  required String? installPhase,
}) {
  return {
    'name': name,
    'file': 'screenshot-$phase-$ordinal-$name.png',
    'screenshot': true,
    'snapshotFile': 'snapshot-$phase-$ordinal-$name.json',
    'treeFile': 'tree-$phase-$ordinal-$name.txt',
    'phase': installPhase,
  };
}

/// 真实写入一组截图/快照/树，返回摘要里引用的 capture 条目。
///
/// 这是证据落盘的唯一实现：生产 `_capture` 与验收测试走同一路径，条目里的
/// `file`/`snapshotFile`/`treeFile` 就是刚写出的文件本身，不是另算的名字。
Future<Map<String, Object?>> writeAcpInstallCapture({
  required Directory output,
  required String phase,
  required int ordinal,
  required String name,
  required String? installPhase,
  required List<int> screenshot,
  required String snapshot,
  required String tree,
}) async {
  final entry = acpInstallCaptureEntry(
    phase: phase,
    ordinal: ordinal,
    name: name,
    installPhase: installPhase,
  );
  await File('${output.path}/${entry['file']}').writeAsBytes(screenshot);
  await File('${output.path}/${entry['snapshotFile']}').writeAsString(snapshot);
  await File('${output.path}/${entry['treeFile']}').writeAsString(tree);
  return entry;
}

/// canonical ACP 账号视图：账号配置与已加载的认证连接身份各有自己的事实源。
///
/// 配置用于“旧账号原样保留”的判定；connectionRevision 只有在 acpAuth 已加载，且
/// 与本快照配置的 configuredConnectionRevision 匹配时才可供认证使用。异步认证
/// 观察暂缺不等于配置被改写，也不能用配置字段替代已加载认证事实。
Map<String, Map<String, Object?>> acpAccountsView(
  Map<String, dynamic> snapshot,
) {
  final settings = snapshot['settings'];
  if (settings is! Map) return const {};
  final accounts = settings['acpAccounts'];
  if (accounts is! List) return const {};
  final revisions = <String, int>{};
  final auth = settings['acpAuth'];
  if (auth is Map && auth['loaded'] == true) {
    final entries = auth['accounts'];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        final id = entry['accountId'];
        final revision = entry['connectionRevision'];
        if (id is String && revision is int) revisions[id] = revision;
      }
    }
  }
  final view = <String, Map<String, Object?>>{};
  for (final account in accounts) {
    if (account is! Map) continue;
    final id = account['accountId'];
    if (id is! String || id.isEmpty) continue;
    if (view.containsKey(id)) throw StateError('duplicate ACP accountId: $id');
    final configuredRevision = account['connectionRevision'];
    view[id] = <String, Object?>{
      'name': account['name'],
      'configuredConnectionRevision': configuredRevision,
      'connectionRevision':
          configuredRevision is int && revisions[id] == configuredRevision
          ? configuredRevision
          : null,
    };
  }
  return view;
}

/// 两份 canonical 配置是否一致；列表顺序与认证到达顺序不改变配置事实。
bool acpAccountsEqual(
  Map<String, Map<String, Object?>> left,
  Map<String, Map<String, Object?>> right,
) {
  return left.length == right.length && acpOldAccountsIntact(left, right);
}

/// 本次保存新增的 accountId：只认基线里**没有**的身份。
///
/// 真实产品按目录的 `suggestId(unique)` 新建账号、后端按 id insert 允许覆盖，因此
/// “旧 accountId 的连接代次变了”不是新增，而是把历史账号改写——绝不能当成功。
List<String> acpAddedAccountIds(
  Map<String, Map<String, Object?>> now,
  Map<String, Map<String, Object?>> baseline,
) {
  return <String>[
    for (final entry in now.entries)
      if (!baseline.containsKey(entry.key)) entry.key,
  ];
}

/// 基线里的账号必须原样保留：改写或丢失都说明这次保存不是“新增一条”。
bool acpOldAccountsIntact(
  Map<String, Map<String, Object?>> now,
  Map<String, Map<String, Object?>> baseline,
) {
  for (final entry in baseline.entries) {
    final other = now[entry.key];
    if (other == null) return false;
    // Summary identity includes the canonical connection revision. Provider
    // details are deliberately not opened for every list row or compared as
    // an always-null placeholder here.
    for (final field in const ['name', 'configuredConnectionRevision']) {
      if (other[field] != entry.value[field]) return false;
    }
  }
  return true;
}

/// 保存等待的判定。ambiguous/tampered 必须立刻失败，不能继续等“后面也许只剩
/// 一个候选”来掩盖问题；ready 则结束等待并固定新账号身份。
enum AcpSaveVerdict {
  /// 旧账号完好，尚无新账号或唯一新账号尚未加载认证代次 → 继续等。
  pending,

  /// 唯一新增账号且连接代次已落定 → 身份可用。
  ready,

  /// 出现多个新增账号 → 立刻失败，不挑一个。
  ambiguous,

  /// 旧账号被改写或丢失 → 立刻失败（正常保存是新增，不覆盖旧 id）。
  tampered,
}

AcpSaveVerdict acpSaveVerdict(
  Map<String, Map<String, Object?>> now,
  Map<String, Map<String, Object?>> baseline,
) {
  final added = acpAddedAccountIds(now, baseline);
  if (added.length > 1) return AcpSaveVerdict.ambiguous;
  if (!acpOldAccountsIntact(now, baseline)) return AcpSaveVerdict.tampered;
  if (added.isEmpty) return AcpSaveVerdict.pending;
  return now[added.single]!['connectionRevision'] is int
      ? AcpSaveVerdict.ready
      : AcpSaveVerdict.pending;
}

typedef AcpAccountIdentity = ({String accountId, int connectionRevision});

/// 保存等待直接使用此判定。歧义和旧账号改写立即抛出，不消费后续快照“等绿”。
AcpAccountIdentity? acpSavedAccountIdentity(
  Map<String, Map<String, Object?>> now,
  Map<String, Map<String, Object?>> baseline,
) {
  switch (acpSaveVerdict(now, baseline)) {
    case AcpSaveVerdict.pending:
      return null;
    case AcpSaveVerdict.ambiguous:
      throw StateError(
        'save created multiple accounts: ${acpAddedAccountIds(now, baseline)}',
      );
    case AcpSaveVerdict.tampered:
      throw StateError('save modified or dropped an existing ACP account');
    case AcpSaveVerdict.ready:
      final id = acpAddedAccountIds(now, baseline).single;
      return (
        accountId: id,
        connectionRevision: now[id]!['connectionRevision']! as int,
      );
  }
}

/// required 认证截图的精确身份与终态；terminal 状态没有 operation 时不伪造。
class AcpAuthCapture {
  const AcpAuthCapture({
    required this.identity,
    required this.kind,
    this.operationId,
    this.failureCode,
    this.failureStage,
  });

  final AcpAccountIdentity identity;
  final String kind;
  final String? operationId;
  final String? failureCode;
  final String? failureStage;
}

Map<String, dynamic>? acpObservedAuthState(
  Map<String, dynamic> snapshot,
  AcpAccountIdentity identity,
) {
  if (acpAccountsView(snapshot)[identity.accountId]?['connectionRevision'] !=
      identity.connectionRevision) {
    return null;
  }
  final auth = (snapshot['settings'] as Map?)?['acpAuth'];
  if (auth is! Map || auth['loaded'] != true || auth['accounts'] is! List) {
    return null;
  }
  for (final entry in auth['accounts'] as List) {
    if (entry is! Map ||
        entry['accountId'] != identity.accountId ||
        entry['connectionRevision'] != identity.connectionRevision) {
      continue;
    }
    final state = entry['state'];
    return state is Map ? state.cast<String, dynamic>() : null;
  }
  return null;
}

/// _capture 在截图前后调用同一入口，旧账号/旧代次/不同操作或失败码都不能冒充。
Map<String, dynamic> requireAcpAuthCapture(
  Map<String, dynamic> snapshot,
  AcpAuthCapture expected,
) {
  final state = acpObservedAuthState(snapshot, expected.identity);
  if (state == null || state['kind'] != expected.kind) {
    throw StateError(
      'auth capture expected ${expected.identity} ${expected.kind}, observed $state',
    );
  }
  final operation = state['operationId'];
  if (expected.operationId != null &&
      (expected.operationId!.isEmpty || operation != expected.operationId)) {
    throw StateError(
      'auth capture operation changed from ${expected.operationId} to $operation',
    );
  }
  if (const {
        'checking',
        'authenticating',
        'verifying',
        'cancelling',
        'closing',
      }.contains(expected.kind) &&
      (operation is! String || operation.isEmpty)) {
    throw StateError('auth capture ${expected.kind} has no operation');
  }
  final failure = state['failure'];
  if (expected.failureCode != null &&
      (failure is! Map ||
          failure['code'] != expected.failureCode ||
          (expected.failureStage != null &&
              failure['stage'] != expected.failureStage))) {
    throw StateError('auth capture failure changed: $failure');
  }
  return state;
}

Map<String, dynamic> _requireAcpInstallEntry(Map<String, dynamic> snapshot) {
  final install = (snapshot['settings'] as Map?)?['acpInstall'];
  if (install is! Map ||
      install['loaded'] != true ||
      install['installations'] is! List) {
    throw StateError('install capture is not loaded');
  }
  final entries = (install['installations'] as List)
      .whereType<Map>()
      .where((entry) => entry['provider'] == _providerWire)
      .toList();
  if (entries.length != 1) {
    throw StateError('install capture requires one provider entry');
  }
  return entries.single.cast<String, dynamic>();
}

/// required 安装截图只接受已加载、同 provider、同非空 operation 的真实阶段。
String requireAcpInstallCapture(
  Map<String, dynamic> snapshot, {
  required String phase,
  String? operationId,
}) {
  final entry = _requireAcpInstallEntry(snapshot);
  final operation = entry['operationId'];
  if (entry['phase'] != phase ||
      operation is! String ||
      operation.isEmpty ||
      (operationId != null && operation != operationId)) {
    throw StateError(
      'install capture expected $phase/$operationId, '
      'observed ${entry['phase']}/$operation',
    );
  }
  if (phase == 'downloading' || phase == 'ready') {
    _requireFixedRelease(entry['release']);
  }
  return operation;
}

/// unsafe ZIP 场景的真实验收判定；text 必须由 failure 控件的 Driver 读取提供。
bool acpUnsafeArchiveFailureReadable(
  Map<String, dynamic> snapshot, {
  required String operationId,
  required String text,
}) {
  requireAcpInstallCapture(snapshot, phase: 'failed', operationId: operationId);
  final failure = _requireAcpInstallEntry(snapshot)['failure'];
  return failure is Map &&
      failure['code'] == 'invalidArchive' &&
      failure['retryable'] is bool &&
      failure['retryable'] == false &&
      text.trim().isNotEmpty;
}

/// tap 返回不等于后端已受理，起点可以仍是 Downloading；之后只能单向收束。
enum AcpCancelPhase { downloading, cancelling, closing, cancelled }

AcpCancelPhase requireAcpCancelProgress(
  Map<String, dynamic> snapshot, {
  required String operationId,
  required AcpCancelPhase previous,
}) {
  final phase = switch (_requireAcpInstallEntry(snapshot)['phase']) {
    'downloading' => AcpCancelPhase.downloading,
    'cancelling' => AcpCancelPhase.cancelling,
    'closing' => AcpCancelPhase.closing,
    'cancelled' => AcpCancelPhase.cancelled,
    final other => throw StateError(
      'unexpected phase after cancel action: $other',
    ),
  };
  requireAcpInstallCapture(
    snapshot,
    phase: phase.name,
    operationId: operationId,
  );
  if (phase.index < previous.index) {
    throw StateError(
      'cancel operation $operationId regressed from ${previous.name} to ${phase.name}',
    );
  }
  return phase;
}

class _Journey {
  _Journey({required this.output, required this.phase, this.fixture}) {
    _step = phase;
    stage = phase;
  }

  FlutterDriverSession? _driver;
  FlutterDriverSession get driver => _driver!;
  void attach(FlutterDriverSession driver) => _driver = driver;

  final Directory output;
  final String phase;
  final AcpFixture? fixture;

  final Map<String, bool> checks = {};
  final List<Map<String, Object?>> captures = [];
  final List<Map<String, Object?>> failures = [];

  String stage = '';
  String _step = '';
  int _captureIndex = 0;
  String? _shutdownState;

  /// 业务 shutdown 是否已请求过：失败路径不重复请求来“补一条好看的记录”。
  bool _shutdownRequested = false;

  /// request-app-exit 是否已发出（只用于避免重复请求，不表示退出已确认）。
  bool _exitRequestAttempted = false;

  /// 退出请求的真实结果：{requested, acknowledged, error?}。
  Map<String, Object?>? _exitRequest;

  /// 旅程是否走到成功终点（typed shutdown completed + 退出已被请求）。
  bool _succeeded = false;

  /// 最后一份成功读取的 canonical 快照：连接断开后写证据不再发起请求。
  Map<String, dynamic>? _lastSnapshot;

  /// cancel 阶段冻结的取消身份（含完整 release），供 retry 阶段核对同一描述符。
  Map<String, dynamic>? _cancelledOperation;
  Map<String, Object?>? _cancellingObservation;
  Map<String, Object?>? _savedAccount;
  String? _activeInstallOperation;
  String? _activeInstallEditorId;
  String? _activeInstallTargetId;
  Map<String, Object?>? _preparationSelection;

  /// 本 phase 任何准备/保存副作用之前的 canonical ACP 账号基线。
  ///
  /// 各 phase 是独立 GUI/runtime，home 分组由 harness 决定。不能从其它阶段的
  /// 列表是否为空猜本阶段起点，“有没有保存”只能相对此基线判断。
  Map<String, Map<String, Object?>> _accountsBaseline = const {};
  bool _accountsBaselineReady = false;
  bool _savingNewAccount = false;

  Future<void> run() async {
    await _openAccounts();
    await _readAccountsBaseline();
    if (const {'first', 'resume', 'cancel'}.contains(phase) &&
        _accountsBaseline.isEmpty) {
      throw StateError('$phase requires a canonical pre-existing ACP baseline');
    }
    if (phase == 'first') await _prepareRequired();
    if (!const {'auth-faults', 'restart', 'retry'}.contains(phase)) {
      await _openTemplatePicker();
      if (phase == 'first') await _capture('template-menu-open');
      await _chooseTemplate(_antigravityToken, dyScroll: 200);
    }
    switch (phase) {
      case 'first':
        await _firstPhase();
      case 'auth-faults':
        await _authFaultsPhase();
      case 'restart':
        await _restartPhase();
      case 'resume':
        await _resumePhase();
      case 'cancel':
        await _cancelPhase();
      case 'retry':
        await _retryPhase();
      case 'reuse':
        await _reusePhase();
      case 'faults-unsafe-zip':
        await _faultPhase('invalidArchive', 'failed-archive');
    }
    await _finish();
  }

  // ── 导航 ──

  Future<void> _openAccounts() async {
    _enterStep('open-accounts');
    await _waitFor(_settingsOpen, timeout: _startupWait);
    await _tap(_settingsOpen, timeout: _startupWait);
    await _waitFor(_settingsPage);
    await _waitFor(_settingsAccountsTab);
    await _tap(_settingsAccountsTab);
    await _waitFor(_accountAdd);
    await _until(
      'committed-account-list',
      (snapshot) => _hasAccountList(_presentation(snapshot)),
    );
  }

  Future<void> _openTemplatePicker() async {
    _enterStep('open-template-picker');
    await _tap(_accountAdd);
    stage = '$_step:template-picker-ready';
    final ready = await _until('template-picker-ready', (snapshot) {
      final editor = _presentation(snapshot)?['editor'] as Map?;
      final editorId = editor?['editorId'];
      final target = editor?['target'];
      final templates =
          snapshot['settings']?['accountDomains']?['templates'] as Map?;
      return _hasAccountEditor(_presentation(snapshot)) &&
          _isAccountPage(_presentation(snapshot), 'create') &&
          editor?['creating'] == true &&
          editor?['stale'] == false &&
          editor?['saving'] == false &&
          editorId is String &&
          editorId.isNotEmpty &&
          target is Map &&
          const {'native', 'acp'}.contains(target['kind']) &&
          target['id'] is String &&
          (target['id'] as String).isNotEmpty &&
          templates?['loaded'] == true &&
          templates?['usable'] == true;
    });
    final editor = _presentation(ready)!['editor'] as Map;
    final target = editor['target'] as Map;
    final templates = ready['settings']['accountDomains']['templates'] as Map;
    final nativeTemplates = ready['settings']['nativeTemplates'];
    stdout.writeln(
      '$stage ${jsonEncode({
        'editorId': editor['editorId'],
        'target': {'kind': target['kind'], 'id': target['id']},
        'creating': editor['creating'],
        'stale': editor['stale'],
        'saving': editor['saving'],
        'templatesLoaded': templates['loaded'],
        'templatesUsable': templates['usable'],
        'nativeTemplatesCount': nativeTemplates is List ? nativeTemplates.length : null,
      })}',
    );
    await driver.waitFor(find.byValueKey('account-template-selector'));
    stage = '$_step:tap:account-template-selector-toggle';
    await driver.rawTap(
      find.descendant(
        of: find.byValueKey('account-template-selector'),
        matching: find.byType('IconButton'),
      ),
      timeout: _controlWait,
    );
  }

  /// The picker now belongs to an already-open creation draft. Selecting a
  /// different template resolves that draft through the production dialog.
  Future<bool> _selectTemplate(String token) async {
    final before = await _snapshot();
    final presentation = _presentation(before);
    final editor = presentation?['editor'] as Map?;
    if (!_hasAccountEditor(presentation) ||
        !_isAccountPage(presentation, 'create') ||
        editor == null ||
        editor['creating'] != true ||
        editor['saving'] != false) {
      throw StateError('template selection has no idle creation editor');
    }
    final nativeTemplates = before['settings']['nativeTemplates'] as List;
    final bool sameTemplate;
    if (token == _antigravityToken) {
      sameTemplate =
          editor['target']?['kind'] == 'acp' &&
          presentation?['acp']?['providerId'] == _providerWire;
    } else {
      sameTemplate =
          editor['target']?['kind'] == 'native' &&
          nativeTemplates.isNotEmpty &&
          nativeTemplates.first == token;
    }
    await _tap(_templateKey(token));
    if (!sameTemplate && editor['dirty'] == true) {
      final dialog = find.byType('AccountUnsavedChangesDialog');
      await driver.waitFor(dialog);
      await driver.rawTap(
        find.descendant(
          of: dialog,
          matching: find.text((await _usageLabels())['discard'] as String),
        ),
      );
      await driver.waitForAbsent(dialog);
    }
    return !sameTemplate;
  }

  String _templateKey(String token) => AccountViewKeyValues.template(
    token == _antigravityToken ? 'acp' : 'native',
    token == _antigravityToken ? _providerWire : token,
  );

  Map<String, dynamic>? _presentation(Map<String, dynamic> snapshot) =>
      (snapshot['driverDiagnostics']?['accountsPresentation'] as Map?)
          ?.cast<String, dynamic>();

  Future<SerializableFinder> _editorScroll() async {
    final presentation = _presentation(await _snapshot());
    final editor = presentation?['editor'] as Map?;
    if (!_hasAccountEditor(presentation) || editor == null) {
      throw StateError('no committed and observed editor');
    }
    final target = editor['target'] as Map?;
    if (editor['editorId'] is! String ||
        (editor['editorId'] as String).isEmpty ||
        target?['id'] is! String ||
        (target!['id'] as String).isEmpty) {
      throw StateError('the current editor has no observed typed identity');
    }
    final viewType = switch (target['kind']) {
      'native' => 'NativeAccountEditorView',
      'acp' => 'AcpAccountEditorView',
      _ => throw StateError('the current editor has an unknown account kind'),
    };
    final view = find.descendant(
      of: find.byValueKey(_settingsPage),
      matching: find.byType(viewType),
    );
    final scaffold = find.descendant(
      of: view,
      matching: find.byType('AccountEditorScaffold'),
    );
    // The scaffold's Expanded content first enters this outer scroll view,
    // before any field or selectable text can introduce an inner scroll owner.
    return find.descendant(
      of: scaffold,
      matching: find.byType('SingleChildScrollView'),
      firstMatchOnly: true,
    );
  }

  Future<Map<String, dynamic>> _usageLabels() async => (jsonDecode(
    await driver.requestData('account-usage-state'),
  ) as Map)['labels'].cast<String, dynamic>();

  SerializableFinder get _panel => find.byType('AcpAccountPanel');

  Future<void> _waitPanelStatus(Map<String, dynamic> snapshot) async {
    final status = _presentation(snapshot)?['acp']?['status'];
    if (status is! String || status.isEmpty) {
      throw StateError('no observed ACP panel status');
    }
    await driver.waitFor(
      find.descendant(of: _panel, matching: find.text(status)),
    );
  }

  Future<bool> _panelTextPresent(String text) async {
    final diagnostics = await driver.sendCommand(
      GetDiagnosticsTree(
        find.descendant(of: find.byValueKey(_settingsPage), matching: _panel),
        DiagnosticsType.widget,
        subtreeDepth: 128,
        timeout: _controlWait,
      ),
    );
    return _acpPanelHasText(diagnostics, text);
  }

  Future<void> _ensureTemplateVisible(
    String token, {
    required double dyScroll,
  }) async {
    final option = find.byValueKey(_templateKey(token));
    stage = '$_step:wait-template-option:$token';
    await driver.waitFor(option, timeout: _controlWait);
    stage = '$_step:scroll-template:$token';
    await driver.scrollUntilVisible(
      find.ancestor(
        of: option,
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      option,
      dyScroll: dyScroll,
      timeout: _controlWait,
    );
  }

  Future<void> _chooseTemplate(
    String token, {
    required double dyScroll,
    String? retryOfOperation,
  }) async {
    await _ensureTemplateVisible(token, dyScroll: dyScroll);
    // A cold list has no install demand. Freeze that unknown provenance rather
    // than waiting here for an observation only the editor can own.
    final before = await _snapshot();
    final oldOperation = _operationId(before);
    final oldEditorId = _presentation(before)?['editor']?['editorId'];
    _enterStep('choose-template:$token');
    if (phase == 'first') await _capture('template-visible-$token');
    final switched = await _selectTemplate(token);
    await driver.waitFor(_panel);
    await _watchBaseline();
    if (!switched && _phaseOf(await _snapshot()) != 'ready') {
      // Default ACP opens only a draft; unlike an explicit template switch,
      // it must not admit installation until the user presses Prepare.
      await _tapPanelAction(AccountViewKeyValues.acpAction('prepare'));
    }
    final started = await _until('template-selection-operation', (snapshot) {
      if (!_hasAccountEditor(_presentation(snapshot)) ||
          !_isAccountPage(_presentation(snapshot), 'create') ||
          !_installLoaded(snapshot) ||
          _install(snapshot)['stale'] == true) {
        return false;
      }
      final editor = _presentation(snapshot)?['editor'];
      final panel = _presentation(snapshot)?['acp'];
      final editorId = editor?['editorId'];
      final targetId = editor?['target']?['id'];
      final operation = _operationId(snapshot);
      if (editorId is! String ||
          editorId.isEmpty ||
          (switched && editorId == oldEditorId) ||
          editor?['creating'] != true ||
          editor?['target']?['kind'] != 'acp' ||
          targetId is! String ||
          targetId.isEmpty ||
          panel?['target']?['kind'] != 'acp' ||
          panel?['target']?['id'] != targetId ||
          panel?['editorId'] != editorId ||
          panel?['creating'] != true ||
          panel?['providerId'] != _providerWire ||
          operation == null ||
          operation.isEmpty) {
        return false;
      }
      if (_installLoaded(before) &&
          _phaseOf(before) == 'ready' &&
          (operation != oldOperation ||
              panel?['claimedOperationId'] != null ||
              panel?['preparedForEditor'] == true)) {
        throw StateError(
          'selecting a template replaced or implicitly claimed shared Ready',
        );
      }
      // Observing shared Ready is also legal, including a cold editor whose
      // pre-click install mirror was unknown. It is not a new admission.
      if (_phaseOf(snapshot) == 'ready' &&
          _isUnclaimedSharedReady(editor as Map?, panel as Map?)) {
        return true;
      }
      if (operation == oldOperation || operation == retryOfOperation) {
        return false;
      }
      // A nonempty operation alone is not evidence when the pre-click install
      // value was unknown: the selected editor must own this admission.
      if (panel?['claimedOperationId'] != operation ||
          panel?['preparationGeneration'] is! int ||
          (panel['preparationGeneration'] as int) <= 0) {
        return false;
      }
      if (_phaseOf(snapshot) != 'ready' && editor?['canSave'] != false) {
        throw StateError('an unfinished preparation enabled account saving');
      }
      if (_phaseOf(snapshot) == 'ready' &&
          (panel?['preparedForEditor'] != true || editor?['canSave'] != true)) {
        return false;
      }
      return true;
    }, timeout: _startupWait);
    _activeInstallOperation = _operationId(started);
    _activeInstallEditorId =
        _presentation(started)?['editor']?['editorId'] as String;
    _activeInstallTargetId =
        _presentation(started)?['editor']?['target']?['id'] as String;
    final sharedReady =
        _presentation(started)?['acp']?['preparedForEditor'] == false &&
        _phaseOf(started) == 'ready';
    _preparationSelection = {
      'action': switched ? 'templateSelection' : 'explicitPrepare',
      'beforeLoaded': _installLoaded(before),
      'beforeStamp': _install(before)['stamp'],
      'beforeOperationId': oldOperation,
      'beforePhase': _installLoaded(before) ? _phaseOf(before) : null,
      'retryOfOperation': retryOfOperation,
      'editorId': _activeInstallEditorId,
      'target': {'kind': 'acp', 'id': _activeInstallTargetId},
      'operationId': _activeInstallOperation,
      'phaseAtAdmissionObservation': _phaseOf(started),
      'outcome': sharedReady ? 'sharedReadyUnclaimed' : 'newPreparation',
    };
    if (sharedReady) {
      if (phase != 'reuse') {
        throw StateError(
          '$phase requires a fresh fixture preparation, but the observed baseline was already shared Ready',
        );
      }
      await _usePreparedForEditor(started);
    } else {
      checks['templateSelectionStartedFreshOperation'] = true;
    }
    checks['managedPreparationVisible'] = true;
    checks['saveGateMatchesPreparationPhase'] = true;
  }

  Future<void> _tap(String key, {Duration timeout = _controlWait}) async {
    await _waitFor(key, timeout: timeout);
    stage = '$_step:tap:$key';
    await driver.rawTap(find.byValueKey(key));
  }

  Future<void> _tapPanelAction(String key) async {
    final presentation = _presentation(await _snapshot());
    final SerializableFinder owner;
    if (_hasAccountEditor(presentation)) {
      owner = await _editorScroll();
    } else {
      final account = presentation?['navigation']?['account'];
      if (account is! Map ||
          account['kind'] != 'acp' ||
          account['id'] is! String ||
          !_hasAccountDetails(presentation, 'acp', account['id'] as String)) {
        throw StateError('no observed account host for ACP panel action');
      }
      final details = find.descendant(
        of: find.byValueKey(_settingsPage),
        matching: find.byType('AccountDetailsView'),
      );
      owner = find.descendant(of: details, matching: find.byType('ListView'));
    }
    final panel = find.descendant(of: owner, matching: _panel);
    await _tapInAccountBody(
      key,
      // Panel domain actions are not the editor footer's Cancel intent.
      owner: owner,
      target: find.descendant(of: panel, matching: find.byValueKey(key)),
      dyScroll: -200,
    );
  }

  Future<void> _tapInAccountBody(
    String key, {
    required SerializableFinder owner,
    required SerializableFinder target,
    required double dyScroll,
  }) async {
    final deadline = DateTime.now().add(_controlWait);
    Duration remaining() {
      final budget = deadline.difference(DateTime.now());
      if (budget <= Duration.zero) {
        throw StateError('account body action $key exceeded $_controlWait');
      }
      return budget;
    }

    stage = '$_step:reveal:$key';
    await driver.scrollUntilVisible(
      owner,
      target,
      dyScroll: dyScroll,
      timeout: remaining(),
    );
    stage = '$_step:tappable:$key';
    final budget = remaining();
    await driver.sendCommand(
      WaitForTappable(
        target,
        timeout: budget < FlutterDriverSession.geometryDeadline
            ? budget
            : FlutterDriverSession.geometryDeadline,
      ),
    );
    // Progress may keep scheduling frames. Wait only for this real control to
    // be hittable, then issue exactly one tap; never replay a side effect.
    stage = '$_step:tap:$key';
    await driver.tap(target, timeout: remaining());
  }

  Future<void> _waitFor(String key, {Duration timeout = _controlWait}) async {
    stage = '$_step:wait:$key';
    await driver.waitFor(find.byValueKey(key), timeout: timeout);
  }

  Future<void> _waitForAbsent(String key, {Duration timeout = _controlWait}) =>
      driver.waitForAbsent(find.byValueKey(key), timeout: timeout);

  Future<void> _openDetails(AcpAccountIdentity identity) async {
    _enterStep('open-acp-details:${identity.accountId}');
    await _tap(AccountViewKeyValues.row('acp', identity.accountId));
    await driver.waitFor(find.byType('AcpAccountPanel'));
    await _until(
      'selected-acp-details',
      (snapshot) => _hasAccountDetails(
        _presentation(snapshot),
        'acp',
        identity.accountId,
      ),
    );
    // Only this real UI action creates the auth observer. Now require the
    // target's loaded auth identity to match the frozen configuration identity.
    await _until('selected-acp-auth-loaded', (snapshot) {
      if (snapshot['settings']?['accountDomains']?['summaries']?['loaded'] !=
          true) {
        return false;
      }
      if (_accounts(
            snapshot,
          )[identity.accountId]?['configuredConnectionRevision'] !=
          identity.connectionRevision) {
        throw StateError('selected ACP configuration identity changed');
      }
      return _authState(snapshot, identity) != null;
    }, timeout: _startupWait);
  }

  Future<void> _returnToAccounts() async {
    final details = find.descendant(
      of: find.byValueKey(_settingsPage),
      matching: find.byType('AccountDetailsView'),
    );
    // Panel actions can scroll the top Back control offscreen. The details
    // host remains mounted even when that lazy ListView child is absent.
    await _tapInAccountBody(
      _acpBack,
      owner: find.descendant(of: details, matching: find.byType('ListView')),
      target: find.descendant(of: details, matching: find.byValueKey(_acpBack)),
      dyScroll: 200,
    );
    await _waitFor(_accountAdd);
    await _until(
      'details-back-committed-account-list',
      (snapshot) => _hasAccountList(_presentation(snapshot)),
    );
  }

  Future<void> _revealInEditor(String key, {double dyScroll = -200}) async {
    stage = '$_step:reveal:$key';
    final owner = await _editorScroll();
    await driver.scrollUntilVisible(
      owner,
      find.descendant(of: owner, matching: find.byValueKey(key)),
      dyScroll: dyScroll,
      timeout: _controlWait,
    );
  }

  // ── canonical 观察 ──

  Future<Map<String, dynamic>> _snapshot() async {
    final snapshot = await driver.readSnapshot();
    _lastSnapshot = snapshot;
    if (_accountsBaselineReady) {
      final accounts = _accounts(snapshot);
      if (_savingNewAccount) {
        // 在每次真实观察中拒绝旧 id 改写和多写，不能在下一次观察中“消失后变绿”。
        acpSavedAccountIdentity(accounts, _accountsBaseline);
        final savedId = _savedAccount?['accountId'];
        if (savedId is String &&
            accounts[savedId]?['configuredConnectionRevision'] !=
                _savedAccount?['connectionRevision']) {
          throw StateError(
            'the newly saved account disappeared or changed identity',
          );
        }
      } else if (!acpAccountsEqual(accounts, _accountsBaseline)) {
        throw StateError(
          'canonical ACP accounts changed without a save action',
        );
      }
    }
    return snapshot;
  }

  Map<String, dynamic> _install(Map<String, dynamic> snapshot) {
    final settings = snapshot['settings'];
    if (settings is! Map) return const {};
    final install = settings['acpInstall'];
    if (install is! Map) return const {};
    return install.cast<String, dynamic>();
  }

  bool _installLoaded(Map<String, dynamic> snapshot) =>
      _install(snapshot)['loaded'] == true;

  Map<String, dynamic>? _entry(Map<String, dynamic> snapshot) {
    final installations = _install(snapshot)['installations'];
    if (installations is! List) return null;
    for (final entry in installations) {
      if (entry is Map && entry['provider'] == _providerWire) {
        return entry.cast<String, dynamic>();
      }
    }
    return null;
  }

  String? _phaseOf(Map<String, dynamic> snapshot) =>
      _entry(snapshot)?['phase'] as String?;

  String? _operationId(Map<String, dynamic> snapshot) =>
      _entry(snapshot)?['operationId'] as String?;

  Map<String, dynamic>? _progressOf(Map<String, dynamic> snapshot) {
    final progress = _entry(snapshot)?['progress'];
    return progress is Map ? progress.cast<String, dynamic>() : null;
  }

  Map<String, dynamic>? _releaseOf(Map<String, dynamic> snapshot) {
    final release = _entry(snapshot)?['release'];
    return release is Map ? release.cast<String, dynamic>() : null;
  }

  Map<String, dynamic>? _failureOf(Map<String, dynamic> snapshot) {
    final failure = _entry(snapshot)?['failure'];
    return failure is Map ? failure.cast<String, dynamic>() : null;
  }

  Future<void> _watchBaseline() async {
    stage = '$_step:await-install-baseline';
    await _until(
      'acp-install-loaded',
      (state) => _installLoaded(state),
      timeout: _startupWait,
    );
    checks['installLoaded'] = true;
    checks['installRevisionRecorded'] =
        _install(await _snapshot())['revision'] is int;
  }

  Map<String, Map<String, Object?>> _accounts(Map<String, dynamic> snapshot) =>
      acpAccountsView(snapshot);

  /// The list owns summaries, not auth. Configuration identities are sufficient
  /// for a no-write baseline; target auth is awaited only after opening details.
  Future<void> _readAccountsBaseline() async {
    stage = '$_step:await-accounts-baseline';
    final state = await _until('acp-accounts-loaded', (snapshot) {
      final settings = snapshot['settings'];
      if (settings is! Map) return false;
      final domains = settings['accountDomains'];
      if (domains is! Map ||
          domains['summaries'] is! Map ||
          domains['summaries']['loaded'] != true) {
        return false;
      }
      if (settings['acpAccounts'] is! List) return false;
      // 已存在账号的连接代次也必须已经给出，否则这条基线不构成可靠身份。
      return _accounts(snapshot).values
          .every((view) => view['configuredConnectionRevision'] is int);
    }, timeout: _startupWait);
    _accountsBaseline = _accounts(state);
    _accountsBaselineReady = true;
    checks['accountsBaselineReady'] = true;
  }

  Map<String, dynamic>? _authState(
    Map<String, dynamic> snapshot,
    AcpAccountIdentity identity,
  ) => acpObservedAuthState(snapshot, identity);

  int _authRevision(Map<String, dynamic> snapshot) {
    final auth = (snapshot['settings'] as Map?)?['acpAuth'];
    final revision = auth is Map && auth['loaded'] == true
        ? auth['revision']
        : null;
    if (revision is! int) {
      throw StateError('canonical acpAuth revision is not loaded');
    }
    return revision;
  }

  Future<Map<String, dynamic>> _awaitAuth(
    AcpAccountIdentity identity,
    String kind, {
    int? afterRevision,
  }) => _until('auth:${identity.accountId}:$kind', (state) {
    if (afterRevision != null && _authRevision(state) <= afterRevision) {
      return false;
    }
    final auth = _authState(state, identity);
    if (auth?['kind'] == 'failed' && kind != 'failed') {
      throw StateError('ACP ${identity.accountId} failed: ${auth?['failure']}');
    }
    return auth?['kind'] == kind;
  }, timeout: _startupWait);

  Future<Map<String, dynamic>> _checkAndAwait(
    AcpAccountIdentity identity,
    String kind,
  ) async {
    final baseline = await _until(
      'auth-target-loaded',
      (state) => _authState(state, identity) != null,
      timeout: _startupWait,
    );
    final before = _authRevision(baseline);
    await _tapPanelAction(_acpCheck);
    return _awaitAuth(identity, kind, afterRevision: before);
  }

  AcpAccountIdentity _configuredIdentityFor(
    String accountId,
    Map<String, dynamic> state,
  ) {
    final revision = _accounts(
      state,
    )[accountId]?['configuredConnectionRevision'];
    if (revision is! int) {
      throw StateError('no loaded configuration identity for $accountId');
    }
    return (accountId: accountId, connectionRevision: revision);
  }

  // ── 阶段 ──

  /// first 先检查真正的旧账号。缺安装属于 prepare 阶段，检查不能隐式下载/保存。
  Future<void> _prepareRequired() async {
    if (_accountsBaseline.length != 1) {
      throw StateError('first requires exactly one seeded ACP account');
    }
    final identity = _configuredIdentityFor(
      _accountsBaseline.keys.single,
      await _snapshot(),
    );
    await _openDetails(identity);
    final failed = await _checkAndAwait(identity, 'failed');
    final failure = _authState(failed, identity)?['failure'];
    if (failure is! Map ||
        failure['code'] != 'preparationRequired' ||
        failure['stage'] != 'prepare') {
      throw StateError(
        'seed check must fail preparationRequired@prepare: $failure',
      );
    }
    checks['seedPreparationRequired'] = true;
    _assertAccountsUnchanged(failed, 'seedCheckDidNotChangeAccounts');
    await _capture(
      'prepare-required',
      expectedAuth: AcpAuthCapture(
        identity: identity,
        kind: 'failed',
        failureCode: 'preparationRequired',
        failureStage: 'prepare',
      ),
    );
    await _returnToAccounts();
  }

  /// first：完整准备 → 显式保存唯一新身份 → 真实检查终态。
  Future<void> _firstPhase() async {
    await _prepareToDownloading('progress');
    await _prepareToReady('ready');
    await _adaptiveCaptures();
    await _reopenAndClaimPrepared();
    await _saveAndObserve('connected');
  }

  /// A ready installation is shared, but a fresh editor must explicitly claim
  /// it. Reopening uses real leave confirmation and does not prepare again.
  Future<void> _reopenAndClaimPrepared() async {
    final before = await _snapshot();
    final oldEditor = _presentation(before)?['editor'] as Map?;
    if (!_hasAccountEditor(_presentation(before)) ||
        oldEditor == null ||
        _operationId(before) != _activeInstallOperation) {
      throw StateError('ready claim has no current editor/installation');
    }
    await _revealInEditor(_accountCancel);
    await _tap(_accountCancel);
    if (oldEditor['dirty'] == true || oldEditor['saving'] == true) {
      await driver.waitFor(find.byType('AccountUnsavedChangesDialog'));
      await driver.tap(
        find.descendant(
          of: find.byType('AccountUnsavedChangesDialog'),
          matching: find.text((await _usageLabels())['discard'] as String),
        ),
      );
    }
    await _waitFor(_accountAdd);
    await _until(
      'cancel-committed-account-list',
      (snapshot) => _hasAccountList(_presentation(snapshot)),
    );
    await _openTemplatePicker();
    await _ensureTemplateVisible(_antigravityToken, dyScroll: 200);
    final beforeSelection = await _snapshot();
    if (!_installLoaded(beforeSelection) ||
        _phaseOf(beforeSelection) != 'ready' ||
        _operationId(beforeSelection) != _activeInstallOperation) {
      throw StateError(
        'shared ready baseline was lost before template selection',
      );
    }
    await _selectTemplate(_antigravityToken);
    await driver.waitFor(_panel);
    final unclaimed = await _until('fresh-editor-shared-ready', (snapshot) {
      if (_installLoaded(snapshot) &&
          _operationId(snapshot) != _activeInstallOperation) {
        throw StateError('reopening shared Ready started another preparation');
      }
      final editor = _presentation(snapshot)?['editor'];
      final panel = _presentation(snapshot)?['acp'];
      if (editor?['editorId'] is String &&
          editor?['editorId'] != oldEditor['editorId'] &&
          (panel?['claimedOperationId'] != null ||
              panel?['preparedForEditor'] == true)) {
        throw StateError('reopening shared Ready implicitly claimed it');
      }
      return _hasAccountEditor(_presentation(snapshot)) &&
          editor?['editorId'] is String &&
          editor?['editorId'] != oldEditor['editorId'] &&
          editor?['creating'] == true &&
          editor?['target']?['kind'] == 'acp' &&
          panel?['editorId'] == editor?['editorId'] &&
          panel?['target']?['kind'] == 'acp' &&
          panel?['target']?['id'] == editor?['target']?['id'] &&
          panel?['providerId'] == _providerWire &&
          _isUnclaimedSharedReady(editor as Map?, panel as Map?);
    });
    await _usePreparedForEditor(unclaimed);
  }

  Future<void> _usePreparedForEditor(Map<String, dynamic> unclaimed) async {
    final editor = _presentation(unclaimed)?['editor'] as Map;
    final panel = _presentation(unclaimed)?['acp'] as Map;
    if (!_isUnclaimedSharedReady(editor, panel) ||
        _operationId(unclaimed) != _activeInstallOperation) {
      throw StateError('shared ready implicitly authorized a fresh editor');
    }
    final beforeGeneration = panel['preparationGeneration'] as int;
    _assertAccountsUnchanged(unclaimed, 'sharedReadyDidNotSave');
    checks['sharedReadyRequiresExplicitClaim'] = true;
    await _tapPanelAction(AccountViewKeyValues.acpAction('usePrepared'));
    final claimed = await _until('explicit-prepared-claim', (snapshot) {
      if (_installLoaded(snapshot) &&
          _operationId(snapshot) != _activeInstallOperation) {
        throw StateError('usePrepared started a replacement installation');
      }
      final currentEditor = _presentation(snapshot)?['editor'];
      final currentPanel = _presentation(snapshot)?['acp'];
      return _hasAccountEditor(_presentation(snapshot)) &&
          currentEditor?['editorId'] == editor['editorId'] &&
          currentEditor?['target']?['kind'] == 'acp' &&
          currentEditor?['target']?['id'] == editor['target']['id'] &&
          currentPanel?['editorId'] == editor['editorId'] &&
          currentPanel?['target']?['kind'] == 'acp' &&
          currentPanel?['target']?['id'] == editor['target']['id'] &&
          currentEditor?['canSave'] == true &&
          currentPanel?['preparedForEditor'] == true &&
          currentPanel?['preparationGeneration'] is int &&
          (currentPanel['preparationGeneration'] as int) > beforeGeneration &&
          currentPanel?['claimedOperationId'] == _activeInstallOperation;
    });
    if (_operationId(claimed) != _activeInstallOperation) {
      throw StateError('usePrepared started a replacement installation');
    }
    _activeInstallEditorId = editor['editorId'] as String;
    _activeInstallTargetId = editor['target']['id'] as String;
    checks['explicitUsePreparedClaimsSameOperation'] = true;
    await _capture('explicit-prepared-claim', expectedInstallPhase: 'ready');
  }

  /// resume 使用 H2 自己的已有账号基线，不假设它与 first 共用 home。
  Future<void> _resumePhase() async {
    await _prepareToDownloading('progress-resumed');
    await _prepareToReady('ready');
    _assertAccountsUnchanged(await _snapshot(), 'resumeDidNotSave');
  }

  Future<AcpAccountIdentity> _firstSavedIdentity() async {
    final first = await _readCompletedSummary('first');
    final saved = first['savedAccount'];
    if (saved is! Map ||
        saved['accountId'] is! String ||
        saved['connectionRevision'] is! int) {
      throw StateError('first summary has no savedAccount identity');
    }
    final id = saved['accountId'] as String;
    if (id.isEmpty || !_accountsBaseline.containsKey(id)) {
      throw StateError('first saved account $id is absent in this runtime');
    }
    // The previous runtime's revision is evidence only. The current summary
    // supplies the configuration identity; opening details will observe auth.
    return _configuredIdentityFor(id, await _snapshot());
  }

  Future<void> _restartPhase() async {
    final identity = await _firstSavedIdentity();
    await _openDetails(identity);
    await _awaitAuth(identity, 'unchecked');
    checks['authLoadedUncheckedAfterRestart'] = true;
    await _capture(
      'reopened',
      expectedAuth: AcpAuthCapture(identity: identity, kind: 'unchecked'),
    );
    final beforeInstall = _install(await _snapshot());
    final checked = await _checkAndAwait(identity, 'verified');
    _requireServerVersion(checked, identity);
    _assertAccountsUnchanged(checked, 'restartAccountsUnchanged');
    checks['explicitCheckVerifiedAfterRestart'] = true;
    // 检查只读验证安装，不要求重启后的 install 必须 Ready，更不隐式 prepare。
    checks['restartCheckDidNotPrepare'] =
        jsonEncode(_install(checked)) == jsonEncode(beforeInstall);
    await _capture(
      'connected-reopened',
      expectedAuth: AcpAuthCapture(identity: identity, kind: 'verified'),
    );
  }

  Future<void> _authFaultsPhase() async {
    final fixture = this.fixture!;
    await fixture.validate();
    final identity = await _firstSavedIdentity();
    await _openDetails(identity);

    // 真正等待中的登录 → 放行 → 同 PID session/new 校验，不手写 credential。
    _enterStep('fixture-first-login');
    await _resetFixture(authentication: 'wait');
    await _fixtureCheckRequired(identity, 'initial');
    await _successfulFixtureLogin(identity, captureAuthenticating: true);
    await _capture(
      'verified',
      expectedAuth: AcpAuthCapture(identity: identity, kind: 'verified'),
    );

    // 协议认证失败：原账号与身份必须保留，不能把先前 Verified 当成本次结果。
    _enterStep('fixture-authentication-failure');
    await _resetFixture(authentication: 'fail');
    await _fixtureCheckRequired(identity, 'failure');
    final failureFrom = await fixture.eventCount();
    final failureRevision = _authRevision(await _snapshot());
    await _tapPanelAction(_acpLogin);
    final failed = await _awaitAuth(
      identity,
      'failed',
      afterRevision: failureRevision,
    );
    final failure = _authState(failed, identity)?['failure'];
    if (failure is! Map ||
        failure['code'] != 'authentication' ||
        failure['stage'] != 'authenticate') {
      throw StateError(
        'expected authentication@authenticate, observed $failure',
      );
    }
    final failureEvidence = await _waitForAttempt(
      failureFrom,
      (evidence) =>
          evidence.authenticatePid != null && evidence.authenticateCount == 1,
    );
    checks['authenticationFailedForThisAttempt'] =
        failureEvidence.authenticateCount == 1 &&
        !await fixture.markerExists('authenticated');
    await _capture(
      'authentication-failed',
      expectedAuth: AcpAuthCapture(
        identity: identity,
        kind: 'failed',
        failureCode: 'authentication',
        failureStage: 'authenticate',
      ),
    );

    // 等待中的认证取消；Cancelled 必须是在真实进程收束后发布的终态。
    _enterStep('fixture-auth-cancel');
    await _resetFixture(authentication: 'wait');
    await _fixtureCheckRequired(identity, 'cancel');
    final cancelFrom = await fixture.eventCount();
    await _tapPanelAction(_acpLogin);
    final authenticating = await _awaitAuth(identity, 'authenticating');
    final operation = _authState(authenticating, identity)?['operationId'];
    if (operation is! String || operation.isEmpty) {
      throw StateError('pending fixture login has no operation');
    }
    final pending = await _waitForAttempt(
      cancelFrom,
      (evidence) => evidence.authenticatePid != null,
    );
    await _waitFixtureMarker('auth-started');
    await _tapPanelAction(_acpCancelAuth);
    await _awaitAuth(identity, 'cancelled');
    final cancelled = await _waitForAttempt(
      cancelFrom,
      (evidence) => evidence.isOrderedCancellation,
    );
    checks['authCancellationJoinedThisPid'] =
        cancelled.authenticatePid == pending.authenticatePid &&
        !await fixture.markerExists('auth-release') &&
        !await fixture.markerExists('authenticated');
    await _capture(
      'auth-cancelled',
      expectedAuth: AcpAuthCapture(identity: identity, kind: 'cancelled'),
    );

    // 在旧进程已收束后放入迟到 release，再做一次明确的只读检查作为观察屏障。
    // Required + 旧 PID 无 session/new 证明迟到放行没有变成旧操作的成功。
    _enterStep('fixture-late-release');
    await fixture.releaseAuth();
    await _fixtureCheckRequired(identity, 'after-late-release');
    final late = await fixture.evidenceSince(cancelFrom);
    checks['lateReleaseCannotReviveCancelledLogin'] =
        late.isOrderedCancellation &&
        late.authenticatePid == pending.authenticatePid &&
        !await fixture.markerExists('authenticated');

    // 这是取消后的显式恢复，不是重试失败副作用来制造绿色；给 restart 留真实凭据。
    _enterStep('fixture-restore-verified');
    await _resetFixture(authentication: 'wait');
    await _fixtureCheckRequired(identity, 'restore');
    await _successfulFixtureLogin(identity);
    checks['syntheticCredentialRestoredForRestart'] = await fixture
        .markerExists('authenticated');
    await _nativeFormRegression();
    _assertAccountsUnchanged(await _snapshot(), 'authFaultsAccountsUnchanged');
  }

  Future<void> _resetFixture({required String authentication}) async {
    await fixture!.resetOwnControls(clearCredential: true);
    await fixture!.patchBehavior(
      authentication: authentication,
      probe: 'normal',
      disconnect: false,
    );
  }

  Future<void> _fixtureCheckRequired(
    AcpAccountIdentity identity,
    String label,
  ) async {
    final from = await fixture!.eventCount();
    final checked = await _checkAndAwait(identity, 'required');
    _requireServerVersion(checked, identity);
    await _waitForAttempt(from, (evidence) => evidence.coversProbe);
    checks['freshFixtureProbe:$label'] = true;
  }

  Future<void> _successfulFixtureLogin(
    AcpAccountIdentity identity, {
    bool captureAuthenticating = false,
  }) async {
    final from = await fixture!.eventCount();
    await _tapPanelAction(_acpLogin);
    final state = await _awaitAuth(identity, 'authenticating');
    final operation = _authState(state, identity)?['operationId'];
    if (operation is! String || operation.isEmpty) {
      throw StateError('authenticating requires a nonempty operation');
    }
    final started = await _waitForAttempt(
      from,
      (evidence) => evidence.authenticatePid != null,
    );
    await _waitFixtureMarker('auth-started');
    if (captureAuthenticating) {
      await _capture(
        'authenticating',
        expectedAuth: AcpAuthCapture(
          identity: identity,
          kind: 'authenticating',
          operationId: operation,
        ),
      );
    }
    await fixture!.releaseAuth();
    final verified = await _awaitAuth(identity, 'verified');
    _requireServerVersion(verified, identity);
    final completed = await _waitForAttempt(
      from,
      (evidence) => evidence.coversSuccessfulLogin,
    );
    if (completed.authenticatePid != started.authenticatePid ||
        !await fixture!.markerExists('authenticated')) {
      throw StateError(
        'login did not verify this PID and persist synthetic credential',
      );
    }
    checks[captureAuthenticating
            ? 'firstLoginSamePidChain'
            : 'restoreLoginSamePidChain'] =
        true;
  }

  Future<AcpAttemptEvidence> _waitForAttempt(
    int from,
    bool Function(AcpAttemptEvidence) predicate,
  ) async {
    final deadline = DateTime.now().add(_startupWait);
    while (DateTime.now().isBefore(deadline)) {
      final evidence = await fixture!.evidenceSince(from);
      if (predicate(evidence)) return evidence;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'fixture evidence did not converge after event watermark $from',
    );
  }

  Future<void> _waitFixtureMarker(String marker) async {
    final deadline = DateTime.now().add(_controlWait);
    while (DateTime.now().isBefore(deadline)) {
      if (await fixture!.markerExists(marker)) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('fixture did not write $marker in this attempt');
  }

  void _requireServerVersion(
    Map<String, dynamic> snapshot,
    AcpAccountIdentity identity,
  ) {
    final server = _authState(snapshot, identity)?['server'];
    if (server is! Map || server['version'] != '1.4.1') {
      throw StateError(
        'verified fixture must report the actual server version 1.4.1: $server',
      );
    }
  }

  Future<void> _nativeFormRegression() async {
    await _returnToAccounts();
    _enterStep('native-form-regression');
    final before = await _snapshot();
    final nativeBefore = _nativeConfiguration(before);
    // Opening the production picker declares template demand; snapshots only
    // observe the directory and must not load it on behalf of the UI.
    await _openTemplatePicker();
    late final Map<String, dynamic> templateSnapshot;
    Map? catalog;
    try {
      templateSnapshot = await _until('native-template-directory-loaded', (
        snapshot,
      ) {
        catalog = snapshot['settings']['accountDomains']['templates'] as Map;
        return catalog!['loaded'] == true;
      });
    } on Object {
      stderr.writeln('Native template directory observation: $catalog');
      rethrow;
    }
    final templates = (templateSnapshot['settings'] as Map)['nativeTemplates'];
    if (catalog!['usable'] != true ||
        templates is! List ||
        templates.isEmpty ||
        templates.first is! String ||
        (templates.first as String).isEmpty) {
      throw StateError(
        'no real Native template is available for form regression; '
        'catalog=$catalog templates=$templates',
      );
    }
    final token = templates.first as String;
    // Creation allocates the first free id for this real template within its
    // account kind. Check that target, rather than assuming the bare token is
    // unused or treating a previously selected ACP account as the new target.
    final occupied = {
      for (final account
          in (before['settings']['accountDomains']['accounts'] as List)
              .cast<Map>())
        if (account['kind'] == 'native') account['id'],
    };
    var expectedTarget = token;
    for (var suffix = 2; occupied.contains(expectedTarget); suffix++) {
      expectedTarget = '$token-$suffix';
    }
    await _ensureTemplateVisible(token, dyScroll: -200);
    await _selectTemplate(token);
    final deadline = DateTime.now().add(_controlWait);
    Duration remaining() {
      final budget = deadline.difference(DateTime.now());
      if (budget <= Duration.zero) {
        throw StateError('Native form editor exceeded $_controlWait');
      }
      return budget;
    }

    String? editorId;
    bool editorReady(Map<String, dynamic> snapshot) {
      final presentation = _presentation(snapshot);
      final editor = presentation?['editor'] as Map?;
      if (editorId != null &&
          editor != null &&
          (editor['editorId'] != editorId ||
              editor['target']?['kind'] != 'native' ||
              editor['target']?['id'] != expectedTarget ||
              editor['creating'] != true)) {
        throw StateError('Native form editor identity changed');
      }
      if (!_hasAccountEditor(presentation) ||
          editor?['target']?['kind'] != 'native' ||
          editor?['creating'] != true) {
        return false;
      }
      if (editor?['target']?['id'] != expectedTarget) {
        throw StateError('Native template created an unexpected target');
      }
      final id = editor?['editorId'];
      if (id is! String || id.isEmpty) return false;
      editorId ??= id;
      return editor?['stale'] == false &&
          editor?['saving'] == false &&
          presentation?['mountedViews']?['nativeEditor']?['editorId'] == id;
    }

    final ready = await _until(
      'native-template-editor-mounted',
      editorReady,
      timeout: remaining(),
    ).timeout(remaining());
    final initialRevision = _presentation(ready)?['editor']?['draftRevision'];
    if (initialRevision is! int || initialRevision < 0) {
      throw StateError('Native form editor has no observed draft revision');
    }
    final endpoint = AccountViewKeyValues.editorField(editorId!, 'endpoint');
    final credential = AccountViewKeyValues.editorField(
      editorId!,
      'credential',
    );
    final nativeView = find.descendant(
      of: find.byValueKey(_settingsPage),
      matching: find.byType('NativeAccountEditorView'),
    );
    final endpointField = find.descendant(
      of: nativeView,
      matching: find.byValueKey(endpoint),
    );
    await driver.waitFor(endpointField, timeout: remaining());
    await driver.waitFor(
      find.descendant(of: nativeView, matching: find.byValueKey(credential)),
      timeout: remaining(),
    );
    await _revealInEditor(endpoint).timeout(remaining());
    if (!editorReady(await _snapshot().timeout(remaining()))) {
      throw StateError('Native form editor lost readiness before input');
    }
    final input = find.descendant(
      of: endpointField,
      matching: find.byType('EditableText'),
    );
    await driver.tap(input, timeout: remaining());
    const baseUrl = 'https://fixture.invalid/v1';
    await driver.enterText(baseUrl).timeout(remaining());
    await _until('native-form-input-owned', (snapshot) {
      if (!editorReady(snapshot)) return false;
      final editor = _presentation(snapshot)!['editor'] as Map;
      final revision = editor['draftRevision'];
      return editor['dirty'] == true &&
          revision is int &&
          revision > initialRevision;
    }, timeout: remaining()).timeout(remaining());
    if (await driver.getText(input).timeout(remaining()) != baseUrl) {
      throw StateError('Native form did not retain its actual input');
    }
    await _capture('native-form').timeout(remaining());
    if (!editorReady(await _snapshot().timeout(remaining())) ||
        await driver.getText(input).timeout(remaining()) != baseUrl) {
      throw StateError('Native form owner or raw input changed before cancel');
    }
    await _revealInEditor(_accountCancel);
    await _tap(_accountCancel);
    await driver.waitFor(find.byType('AccountUnsavedChangesDialog'));
    await driver.tap(
      find.descendant(
        of: find.byType('AccountUnsavedChangesDialog'),
        matching: find.text((await _usageLabels())['discard'] as String),
      ),
    );
    await _waitForAbsent(endpoint);
    await _until(
      'native-cancel-committed-account-list',
      (snapshot) => _hasAccountList(_presentation(snapshot)),
    );
    final after = await _snapshot();
    checks['nativeFormRenderedAndCancelledWithoutSaving'] =
        _nativeConfiguration(after) == nativeBefore;
  }

  String _nativeConfiguration(Map<String, dynamic> snapshot) {
    final domains = snapshot['settings']['accountDomains'] as Map;
    final summaries = domains['accounts'] as List;
    final configured = [
      for (final entry in summaries.cast<Map>())
        if (entry['kind'] == 'native')
          {
            for (final field in const [
              'kind',
              'id',
              'name',
              'isDefault',
              'billingKind',
              'billingKindOverride',
              'credentialReady',
              'usageQueryRevision',
            ])
              field: entry[field],
          },
    ]..sort((left, right) => '${left['id']}'.compareTo('${right['id']}'));
    // The query identity covers credential/endpoint semantics without exposing
    // either. Catalog observation/loading stamps are not account config writes.
    return jsonEncode(configured);
  }

  void _assertAccountsUnchanged(Map<String, dynamic> state, String check) {
    final same = acpAccountsEqual(_accounts(state), _accountsBaseline);
    checks[check] = same;
    if (!same) throw StateError('$check: canonical ACP accounts changed');
  }

  /// cancel：瞬态取图可选，真实动作、同 op 的终态取图与账号不变仍是必需。
  Future<void> _cancelPhase() async {
    await _waitDownloading();
    final downloading = await _snapshot();
    final operationId = requireAcpInstallCapture(
      downloading,
      phase: 'downloading',
      operationId: _activeInstallOperation,
    );
    checks['cancelHasOperation'] = true;
    // 取消前冻结真实身份与完整描述符：retry 阶段据此证明“同 cancel 描述符”。
    final releaseBefore = _requireFixedRelease(_releaseOf(downloading));
    _cancelledOperation = {
      'operationId': operationId,
      'release': releaseBefore,
    };
    checks['cancelReleaseCaptured'] = true;
    await _capture(
      'downloading-before-cancel',
      expectedInstallPhase: 'downloading',
    );
    // 取消是显式动作：点面板里的“取消下载”，不靠离开页面。
    await _tapPanelAction(_installCancel);
    checks['cancelActionSent'] = true;

    stage = '$_step:await-cancelling';
    var current = AcpCancelPhase.downloading;
    await _until('acp-install-cancellation-progress', (state) {
      current = requireAcpCancelProgress(
        state,
        operationId: operationId,
        previous: current,
      );
      return current != AcpCancelPhase.downloading;
    }, timeout: _controlWait);
    if (current == AcpCancelPhase.cancelling) {
      current = await _captureCancelling(operationId);
    } else {
      _cancellingObservation = {
        'operationId': operationId,
        'observed': false,
        'capture': 'not-observed',
        'reason':
            'The first canonical cancellation phase observed after the '
            'successful tap was ${current.name}; no Cancelling snapshot was observed.',
      };
    }

    final cancelled = await _until('acp-install-cancelled', (state) {
      current = requireAcpCancelProgress(
        state,
        operationId: operationId,
        previous: current,
      );
      return current == AcpCancelPhase.cancelled;
    }, timeout: _installWait);
    checks['cancelledKeepsOriginalOperation'] =
        _operationId(cancelled) == operationId;
    // Cancelled DTO 不携带 release；完整 descriptor 只取取消前同 op 的下载事实，
    // 保存在 cancelledOperation 中供下个 runtime 的 retry 精确核对。
    _assertAccountsUnchanged(cancelled, 'cancelledDidNotSave');
    await _capture('cancelled', expectedInstallPhase: 'cancelled');
  }

  /// 仅在确实观察过 Cancelling 后尝试；正常前进返回结构化结果，其余错误原样失败。
  Future<AcpCancelPhase> _captureCancelling(String operationId) async {
    stage = '$_step:capture:cancelling';
    final before = await _snapshot();
    final beforePhase = requireAcpCancelProgress(
      before,
      operationId: operationId,
      previous: AcpCancelPhase.cancelling,
    );
    if (beforePhase != AcpCancelPhase.cancelling) {
      _cancellingObservation = {
        'operationId': operationId,
        'observed': true,
        'capture': 'phase-changed',
        'reason':
            'A canonical Cancelling snapshot was observed, then the same '
            'operation reached ${beforePhase.name} before screenshot collection.',
      };
      return beforePhase;
    }
    final screenshot = await driver.screenshot().timeout(_controlWait);
    final tree = await driver.renderTree().timeout(_controlWait);
    final after = await _snapshot();
    final afterPhase = requireAcpCancelProgress(
      after,
      operationId: operationId,
      previous: beforePhase,
    );
    if (afterPhase == AcpCancelPhase.cancelling) {
      await _writeCapture('cancelling', before, screenshot, tree);
      _cancellingObservation = {
        'operationId': operationId,
        'observed': true,
        'capture': 'captured',
        'reason':
            'Canonical snapshots before and after the real screenshot '
            'both remained Cancelling for the same nonempty operation.',
      };
    } else {
      // 未通过同 phase 核对的字节不写盘、不加入 captures，不能冒充瞬态证据。
      _cancellingObservation = {
        'operationId': operationId,
        'observed': true,
        'capture': 'phase-changed',
        'reason':
            'The same operation advanced from Cancelling to '
            '${afterPhase.name} during screenshot collection; collected bytes '
            'were not recorded as Cancelling evidence.',
      };
    }
    return afterPhase;
  }

  /// retry：与上一轮 cancel 的成功证据严格比对后，重新准备同一冻结描述符。
  ///
  /// 每个 phase 是独立 GUI/runtime 生命周期，因此起点允许 Idle；这里不要求
  /// canonical 恢复 Cancelled，而是从 `acp-auto-install-summary-cancel.json`
  /// 取回真实取消身份，再由新 operation 成功证明同一描述符可重试。
  Future<void> _retryPhase() async {
    final previous = await _readCompletedSummary('cancel');
    final cancelled = previous['cancelledOperation'];
    if (cancelled is! Map) {
      throw StateError('cancel summary has no cancelledOperation');
    }
    final previousOperation = cancelled['operationId'];
    if (previousOperation is! String || previousOperation.trim().isEmpty) {
      throw StateError('cancel summary cancelledOperation is incomplete');
    }
    final previousRelease = _requireFixedRelease(cancelled['release']);
    checks['retryHasCancelEvidence'] = true;

    _enterStep('retry-prepare');
    // This phase is a new runtime, so selecting the template is the explicit
    // retry UI action. Validate prior cancellation before that side effect and
    // require a fresh operation instead of clicking Prepare a second time.
    await _openTemplatePicker();
    await _chooseTemplate(
      _antigravityToken,
      dyScroll: 200,
      retryOfOperation: previousOperation,
    );
    checks['retryTemplateActionSent'] = true;
    await _prepareToDownloading('progress-retry');
    final before = await _snapshot();
    final operationId = _operationId(before);
    final release = _requireFixedRelease(_releaseOf(before));
    checks['retryOperationIsFresh'] =
        operationId != null && operationId != previousOperation;
    checks['retryReleaseMatchesCancel'] =
        release['version'] == previousRelease['version'] &&
        release['target'] == previousRelease['target'] &&
        release['archiveUrl'] == previousRelease['archiveUrl'] &&
        release['sha256'] == previousRelease['sha256'];
    await _prepareToReady('ready');
    await _saveAndObserve('connected');
  }

  /// 读取同 OUTPUT_DIR 的 cancel 完成证据；不完整即停止，不猜历史。
  Future<Map<String, dynamic>> _readCompletedSummary(
    String previousPhase,
  ) async {
    final file = File('${output.path}/$_scenario-summary-$previousPhase.json');
    if (!file.existsSync()) {
      throw StateError('missing $previousPhase evidence: ${file.path}');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw StateError('$previousPhase evidence is not an object');
    }
    final summary = decoded.cast<String, dynamic>();
    requireAcpInstallCompletedSummary(summary, phase: previousPhase);
    return summary;
  }

  /// reuse：新 runtime 选择模板触发一次准备；不保存，包 GET=0 由 peer 核验。
  Future<void> _reusePhase() async {
    await _prepareToReady('ready-reused');
    checks['reusedBadgeVisible'] = await _panelTextPresent(
      (await _usageLabels())['installReused'] as String,
    );
    final entry = _entry(await _snapshot());
    checks['reuseFlagTrue'] = entry?['reused'] == true;
    _assertAccountsUnchanged(await _snapshot(), 'reuseDidNotSave');
  }

  /// unsafe archive 可以按真实 Failed 结束；不为形式强加额外副作用重试。
  Future<void> _faultPhase(String expectedCode, String captureName) async {
    final failed = await _until(
      'acp-install-failed:$expectedCode',
      (state) =>
          _thisInstallOperation(state, 'failed') &&
          _failureOf(state)?['code'] == expectedCode,
      timeout: _installWait,
    );
    checks['failureCodeIs$expectedCode'] = true;
    await driver.waitFor(
      find.descendant(of: _panel, matching: find.byType('AccountInlineError')),
    );
    checks['failureVisible'] = true;
    checks['failureHasOperation'] = _operationId(failed)?.isNotEmpty == true;
    final operationId = _activeInstallOperation;
    if (operationId == null || operationId.isEmpty) {
      throw StateError('unsafe archive failure has no active operation');
    }
    final failureText = await driver
        .getText(
          find.descendant(
            of: find.descendant(
              of: _panel,
              matching: find.byType('AccountInlineError'),
            ),
            matching: find.byType('Text'),
          ),
        )
        .timeout(_controlWait);
    checks['failureReadable'] = acpUnsafeArchiveFailureReadable(
      await _snapshot(),
      operationId: operationId,
      text: failureText,
    );
    _assertAccountsUnchanged(failed, 'archiveFailureDidNotSave');
    await _capture(captureName, expectedInstallPhase: 'failed');
  }

  // ── 共用动作 ──

  /// 下载总量是否为「未知」由外部场景决定，而不是由当前快照碰巧取到什么决定。
  ///
  /// first 对着 unknown length 的真实响应；resume/retry 对着官方 Content-Length，
  /// 两者不能共用同一断言，否则合法 known total 会被记成未知而整轮失败。
  bool get _downloadTotalUnknownByContract => phase == 'first';

  bool _thisInstallOperation(Map<String, dynamic> state, String expectedPhase) {
    if (_activeInstallOperation == null ||
        _activeInstallEditorId == null ||
        _activeInstallTargetId == null) {
      throw StateError('no preparation was admitted by the template action');
    }
    if (_operationId(state) != _activeInstallOperation) {
      throw StateError(
        'install switched from $_activeInstallOperation to ${_operationId(state)}',
      );
    }
    final editor = _presentation(state)?['editor'];
    final panel = _presentation(state)?['acp'];
    if (!_hasAccountEditor(_presentation(state)) ||
        editor?['editorId'] != _activeInstallEditorId ||
        panel?['editorId'] != _activeInstallEditorId ||
        editor?['target']?['kind'] != 'acp' ||
        editor?['target']?['id'] != _activeInstallTargetId ||
        panel?['target']?['kind'] != 'acp' ||
        panel?['target']?['id'] != _activeInstallTargetId ||
        panel?['claimedOperationId'] != _activeInstallOperation) {
      throw StateError(
        'preparation lost its selected editor/operation binding',
      );
    }
    if (_phaseOf(state) == 'failed' && expectedPhase != 'failed') {
      throw StateError('installation failed: ${_failureOf(state)}');
    }
    if (_phaseOf(state) != 'ready' && editor?['canSave'] != false) {
      throw StateError('an unfinished preparation enabled account saving');
    }
    return _phaseOf(state) == expectedPhase;
  }

  Future<void> _prepareToDownloading(String captureName) async {
    await _waitDownloading();
    checks['downloadingShowsBytes'] = true;
    await driver.waitFor(
      find.descendant(
        of: _panel,
        matching: find.byType('LinearProgressIndicator'),
      ),
    );
    checks['progressBarVisible'] = true;
    final panel = _presentation(await _snapshot())?['acp'];
    checks['progressTextVisible'] =
        panel?['progressLabel'] is String &&
        await _panelTextPresent(panel['progressLabel'] as String);
    await _waitPanelStatus(await _snapshot());
    checks['stageVisible'] = true;
    final current = await _snapshot();
    final progress = _progressOf(current);
    final completed = progress?['completedBytes'];
    final total = progress?['totalBytes'];
    if (_downloadTotalUnknownByContract) {
      // first 的外部场景是 unknown length：总量必须真的是 None，进度按不定呈现，
      // 不允许用伪造百分比冒充已知总量。
      checks['unknownTotalStaysIndeterminate'] =
          progress != null &&
          total == null &&
          completed is int &&
          completed > 0;
      // The production panel uses a progress bar plus exact byte text, not a
      // percent Text widget. Unknown total must keep that bar indeterminate.
      checks['unknownTotalIndeterminateProgress'] =
          _presentation(current)?['acp']?['progress'] == null;
    } else {
      // resume/retry 的外部场景带官方 Content-Length：总量必须为正，进度落在
      // 0 < completed < total 的真实中途，呈现 fraction 必须匹配真实字节比。
      checks['knownTotalShowsRealProgress'] =
          total is int &&
          total > 0 &&
          completed is int &&
          completed > 0 &&
          completed < total;
      final fraction = _presentation(current)?['acp']?['progress'];
      checks['knownTotalHasDeterminateProgress'] =
          fraction is num &&
          fraction > 0 &&
          fraction < 1 &&
          fraction == completed / total;
    }
    final retryCount = _entry(current)?['retryCount'];
    checks['retryCountRenderedWhenPresent'] =
        retryCount is! int || retryCount == 0
        ? true
        : await _panelTextPresent(
                (await _usageLabels())['installRetries'] as String,
              ) &&
              await _panelTextPresent(
                (await _usageLabels())['installRetryValues'][_providerWire]
                    as String,
              );
    await _capture(captureName, expectedInstallPhase: 'downloading');
  }

  Future<void> _waitDownloading() async {
    stage = '$_step:await-downloading';
    await _until('acp-install-downloading', (state) {
      if (_phaseOf(state) == 'ready') {
        throw StateError(
          'download finished before required progress could be observed',
        );
      }
      if (!_thisInstallOperation(state, 'downloading')) return false;
      final progress = _progressOf(state);
      if (progress == null) return false;
      final completed = progress['completedBytes'];
      if (completed is! int || completed <= 0) return false;
      final total = progress['totalBytes'];
      // 未知总量是真实形态：只要有真实字节就接受。
      return total is! int || completed < total;
    }, timeout: _installWait);
  }

  Future<void> _prepareToReady(String captureName) async {
    stage = '$_step:await-ready';
    final ready = await _until(
      'acp-install-ready',
      (state) => _thisInstallOperation(state, 'ready'),
      timeout: _installWait,
    );
    final entry = _entry(ready);
    final program = entry?['program'];
    _requireFixedRelease(_releaseOf(ready));
    checks['readyHasProgram'] = program is String && program.isNotEmpty;
    checks['readyHasRelease'] = true;
    await _waitPanelStatus(ready);
    checks['readyBadgeVisible'] =
        _presentation(ready)?['acp']?['phase'] == 'ready';
    checks['versionFactVisible'] = await _panelTextPresent('1.4.1');
    // This editor selected the template and owns the admission. Do not hide a
    // lost binding by silently claiming shared Ready here; that is exercised
    // separately by _reopenAndClaimPrepared's explicit usePrepared action.
    final claimed = await _until(
      'editor-claims-prepared',
      (snapshot) =>
          _thisInstallOperation(snapshot, 'ready') &&
          _presentation(snapshot)?['acp']?['preparedForEditor'] == true &&
          _presentation(snapshot)?['editor']?['canSave'] == true,
    );
    checks['preparedExplicitlyOwned'] =
        _presentation(claimed)?['acp']?['claimedOperationId'] ==
        _activeInstallOperation;
    // Existence is not footer visibility or hit-testability; reveal at the tap.
    await _waitFor(_accountSave, timeout: const Duration(seconds: 2));
    checks['saveVisibleAfterReady'] = true;
    await _waitForAbsent(_installPrepare);
    checks['prepareHiddenAfterReady'] = true;
    checks['readyDoesNotPretendClosing'] =
        _presentation(claimed)?['acp']?['phase'] == 'ready';
    await _capture(captureName, expectedInstallPhase: 'ready');
  }

  /// 保存只认一个此前不存在的 accountId，不再把安装 program/args 当账号字段。
  Future<void> _saveAndObserve(String captureName) async {
    // 保存意图前的即时基线：既用来识别本次保存，也用来证明 prepare 没提前保存。
    // 与 phase 基线比对是必须的——只看即时基线会把 prepare 期间的提前保存掩盖掉。
    final beforeSaveState = await _snapshot();
    _assertAccountsUnchanged(
      beforeSaveState,
      'prepareDidNotSaveAccountsBeforeSave',
    );
    final beforeSave = _accounts(beforeSaveState);

    _enterStep('save-and-connect');
    _savingNewAccount = true;
    await _revealInEditor(_accountSave);
    await _tap(_accountSave);

    stage = '$_step:await-saved-account';
    // 身份要等稳定：唯一**新增** accountId，且它的连接代次已经真实落定。
    // 多个新增或旧账号被改写/丢失都是终局失败——不在等待里继续消费，指望
    // “稍后只剩一个候选”把覆盖/多写掩盖过去。
    final saved = await _until('saved-account', (state) {
      return acpSavedAccountIdentity(_accounts(state), beforeSave) != null;
    }, timeout: _startupWait);
    final accounts = _accounts(saved);
    final identity = acpSavedAccountIdentity(accounts, beforeSave)!;
    _savedAccount = {
      'accountId': identity.accountId,
      'connectionRevision': identity.connectionRevision,
    };
    checks['savedAccountIdentityIsFresh'] = true;
    // 其他账号必须原样保留：本次保存不能改动或丢失历史条目（等待期已强制，
    // 这里把结论真正记进 summary）。
    checks['savedKeepsOtherAccounts'] = acpOldAccountsIntact(
      accounts,
      beforeSave,
    );
    checks['savedHasConnectionRevision'] = true;

    stage = '$_step:await-auth-observation';
    // 只接受真实的检查终态：Required（需要登录）/ Verified（可用）都算检查完成；
    // Failed 直接失败输出；Checking/Unchecked/Closing 等必须继续等，不能用
    // “已有条目”冒充检查完成。
    const terminal = {'required', 'verified'};
    final connected = await _until('auth-observation-terminal', (state) {
      // 等待检查时仍监测新增歧义和旧账号改写，不能只在第一次保存观察时核对。
      final observed = acpSavedAccountIdentity(_accounts(state), beforeSave);
      if (observed == null) return false;
      if (observed != identity) {
        throw StateError(
          'saved account identity changed during connection check',
        );
      }
      final auth = _authState(state, identity);
      final kind = auth?['kind'];
      if (kind == 'failed') {
        throw StateError(
          'ACP connection check failed for ${identity.accountId}: ${auth?['failure']}',
        );
      }
      return kind is String && terminal.contains(kind);
    }, timeout: _startupWait);
    final authState = _authState(connected, identity)!;
    _requireServerVersion(connected, identity);
    checks['authObservedForConnection'] = true;
    checks['authReachedTerminalCheck'] =
        authState['kind'] == 'required' || authState['kind'] == 'verified';
    // 记录本次检查的权威身份，防止把旧的 Verified 当成当前结果。
    checks['authRecordedConnection'] = true;
    await _until(
      'save-committed-acp-details',
      (snapshot) => _hasAccountDetails(
        _presentation(snapshot),
        'acp',
        identity.accountId,
      ),
    );
    await _capture(
      captureName,
      expectedInstallPhase: 'ready',
      expectedAuth: AcpAuthCapture(
        identity: identity,
        kind: authState['kind'] as String,
      ),
    );
  }

  /// 宽窗/断点两侧/窄窗的真实布局截图。
  ///
  /// 只有确实调整了窗口才记“已复现该宽度”；无法调整时仍如实留一张当前布局图，
  /// 不伪造窗口尺寸，也不让缺少窗口控制把整个准备阶段判失败（由 root 看图复核）。
  Future<void> _adaptiveCaptures() async {
    final pid = await _guiPid();
    if (pid == null) {
      await _capture('layout-current');
      checks['layoutFallbackCaptured'] = true;
      return;
    }
    final sizes = <(int, int, String)>[
      (1280, 900, 'layout-wide-1280'),
      (880, 900, 'layout-wide-880'),
      (760, 900, 'layout-narrow-760'),
    ];
    WindowGeometry? original;
    try {
      for (final size in sizes) {
        final before = (await driver.getBottomRight(
          find.byValueKey(_settingsPage),
        )).dx;
        final result = resizeOwnedWindow(
          guiPid: pid,
          width: size.$1,
          height: size.$2,
        );
        if (!result.resized) {
          if (original == null) {
            await _capture('layout-current');
            checks['layoutFallbackCaptured'] = true;
            return;
          }
          throw StateError('owned window resize failed: ${result.reason}');
        }
        original ??= result.original;
        checks['windowResizeAvailable'] = true;
        // Native helper 使用物理像素，Driver 使用逻辑坐标。只比对实际变化方向，
        // 不把 Windows DPI 或 Linux 缩放误当成布局失败。
        final previousWidth = result.original!.width;
        if (previousWidth != size.$1) {
          await _awaitLayoutChange(
            before: before,
            shrinking: size.$1 < previousWidth,
          );
        }
        await _capture(size.$3, expectedInstallPhase: 'ready');
        checks['captured-${size.$3}'] = true;
      }
    } finally {
      if (original != null) {
        final restored = resizeOwnedWindow(
          guiPid: pid,
          width: original.width,
          height: original.height,
        );
        if (!restored.resized) {
          throw StateError(
            'could not restore owned window: ${restored.reason}',
          );
        }
      }
    }
  }

  Future<void> _awaitLayoutChange({
    required double before,
    required bool shrinking,
  }) async {
    final deadline = DateTime.now().add(_controlWait);
    while (DateTime.now().isBefore(deadline)) {
      final right = (await driver.getBottomRight(
        find.byValueKey(_settingsPage),
      )).dx;
      if (shrinking ? right < before - 1 : right > before + 1) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'owned window layout did not change from $before (shrinking=$shrinking)',
    );
  }

  Future<int?> _guiPid() async {
    stage = '$_step:query-pid';
    try {
      final raw = await driver.requestData(
        'pid',
        timeout: const Duration(seconds: 15),
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final pid = decoded['pid'];
      return pid is int ? pid : int.tryParse('$pid');
    } catch (_) {
      return null;
    }
  }

  // ── 证据 ──

  Future<Map<String, dynamic>> _until(
    String label,
    bool Function(Map<String, dynamic> snapshot) predicate, {
    Duration timeout = _controlWait,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var last = <String, dynamic>{};
    while (DateTime.now().isBefore(deadline)) {
      last = await _snapshot();
      if (predicate(last)) return last;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    stage = '$_step:timeout:$label';
    throw StateError(
      '$_scenario $phase did not reach $label within $timeout; '
      'phase=${_phaseOf(last)} operation=${_operationId(last)}',
    );
  }

  /// 记录一条截图证据。
  ///
  /// [expectedInstallPhase] 用于已记录的安装截图：canonical 快照、截图与树不可能
  /// 原子，画面可能已经跨到下一阶段。因此要求**拍图前后两次观察都**仍处于该阶段，
  /// 且两次属于**同一个 operation**（阶段相同但换了 operation 也不是这张图要的
  /// 那一次准备），才允许以该 required 名记录；任一条件不符即如实失败（错误里写明
  /// 真实转变），绝不用旧快照冒充另一阶段的画面。前后稳定只是必要条件，画面是否
  /// 真符合预期仍由人工逐图判定。
  Future<void> _capture(
    String name, {
    String? expectedInstallPhase,
    AcpAuthCapture? expectedAuth,
  }) async {
    stage = '$_step:capture:$name';
    if (expectedAuth != null) {
      await driver.waitFor(_panel);
      if (!_hasAccountDetails(
        _presentation(await _snapshot()),
        'acp',
        expectedAuth.identity.accountId,
      )) {
        throw StateError('auth capture is not showing target details');
      }
      await _waitPanelStatus(await _snapshot());
    }
    final before = await _snapshot();
    String? beforeOperation;
    if (expectedInstallPhase != null) {
      beforeOperation = requireAcpInstallCapture(
        before,
        phase: expectedInstallPhase,
        operationId: _activeInstallOperation,
      );
    }
    Map<String, dynamic>? beforeAuth;
    if (expectedAuth != null) {
      beforeAuth = requireAcpAuthCapture(before, expectedAuth);
    }
    final screenshot = await driver.screenshot().timeout(_controlWait);
    final tree = await driver.renderTree().timeout(_controlWait);
    final after = await _snapshot();
    if (expectedInstallPhase != null) {
      requireAcpInstallCapture(
        after,
        phase: expectedInstallPhase,
        operationId: beforeOperation,
      );
    }
    if (expectedAuth != null) {
      final afterAuth = requireAcpAuthCapture(after, expectedAuth);
      if (beforeAuth?['operationId'] != afterAuth['operationId']) {
        throw StateError(
          'capture $name changed auth operation during screenshot',
        );
      }
    }
    await _writeCapture(name, before, screenshot, tree);
  }

  Future<void> _writeCapture(
    String name,
    Map<String, dynamic> snapshot,
    List<int> screenshot,
    String tree,
  ) async {
    captures.add(
      await writeAcpInstallCapture(
        output: output,
        phase: phase,
        ordinal: _captureIndex++,
        name: name,
        installPhase: _phaseOf(snapshot),
        screenshot: screenshot,
        snapshot: '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
        tree: tree,
      ),
    );
  }

  Future<void> _finish() async {
    final failedChecks = _failedChecks();
    if (failedChecks.isNotEmpty) {
      throw StateError('failed checks: $failedChecks');
    }
    stage = '$_step:typed-shutdown';
    final shutdown = await _typedShutdown();
    if (shutdown != 'completed') {
      throw StateError('typed shutdown cleanup was $shutdown');
    }
    stage = 'complete';
    _succeeded = true;
    // 退出请求必须真正被确认：超时/未知异常不能被当成“已退出”。
    // summary 不在这里写：最终状态由 finally 汇总 close 结果后一次落盘。
    final acknowledged = await _requestExit();
    if (!acknowledged) {
      throw StateError(
        'request-app-exit was not acknowledged: '
        '${_exitRequest?['error'] ?? 'unknown error'}',
      );
    }
  }

  /// 有界请求 typed shutdown，返回实际结果（完成/降级/未知），不冒充。
  Future<String> _typedShutdown() async {
    _shutdownRequested = true;
    try {
      final raw = await driver.requestData(
        'shutdown',
        timeout: const Duration(seconds: 120),
      );
      final decoded = jsonDecode(raw);
      final value = decoded is Map ? decoded['shutdown'] : null;
      _shutdownState = value == null ? 'unknown' : '$value';
    } on Object catch (error) {
      // 连接已断或超时都只能如实记为 unknown；不让请求本身再挂起证据。
      _shutdownState = 'unknown';
      stderr.writeln('$_scenario $phase: shutdown request failed: $error');
    }
    return _shutdownState ?? 'unknown';
  }

  Future<void> recordFailure({
    required Object error,
    required StackTrace stackTrace,
  }) async {
    failures.add({
      'stage': stage,
      'error': '$error',
      'stackTrace': '$stackTrace',
    });
    // 失败路径也要有界地请求 typed shutdown，并记录它真实给出的结果；
    // 已请求过就不重复请求（不用第二次请求改写既有事实）。
    if (_driver != null) {
      if (!_shutdownRequested) await _typedShutdown();
      if (!_exitRequestAttempted) await _requestExit();
    }
    // 不在这里落盘：最终 summary 由 finally 统写，避免早写一次被覆盖。
  }

  /// Driver 连接关闭失败：不向已断连接请求快照，只用最后已知事实改判失败。
  ///
  /// 无论此前是否请求过退出，关闭超时或未知异常都是失败证据：追加 failure、
  /// summary 改 `failed`，退出码由调用方置非 0；不存在“正常断连”的豁免。
  void recordCloseFailure(Object error) {
    failures.add({'stage': stage, 'error': 'driver close failed: $error'});
  }

  /// 最终 summary：唯一的落盘点（拥有 business/exit/close 三方结果）。
  ///
  /// 只读 `_lastSnapshot`，不向可能已断开的连接再请求快照；写文件失败向上抛出，
  /// 由调用方置非 0。
  Future<String> writeFinalSummary() async {
    final payload = acpInstallSummaryPayload(
      phase: phase,
      stage: stage,
      succeeded: _succeeded,
      checks: checks,
      captures: captures,
      failures: failures,
      install: _install(_lastSnapshot ?? const <String, dynamic>{}),
      shutdown: _shutdownState,
      exitRequest: _exitRequest,
      cancelledOperation: _cancelledOperation,
      cancellingObservation: _cancellingObservation,
      savedAccount: _savedAccount,
    );
    if (_preparationSelection != null) {
      payload['preparationSelection'] = _preparationSelection;
    }
    await File(
      '${output.path}/$_scenario-summary-$phase.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
    return '${payload['status']}';
  }

  /// 请求应用退出；返回是否得到驱动确认。请求事实与确认分开记录。
  Future<bool> _requestExit() async {
    stage = '$_step:request-app-exit';
    _exitRequestAttempted = true;
    try {
      final raw = await driver.requestData(
        'request-app-exit',
        timeout: const Duration(seconds: 30),
      );
      final reply = jsonDecode(raw);
      if (reply is! Map || reply['exit'] != 'exit_requested') {
        throw StateError(
          'request-app-exit returned no exit_requested acknowledgement: $raw',
        );
      }
      _exitRequest = {'requested': true, 'acknowledged': true};
      return true;
    } on Object catch (error) {
      _exitRequest = {
        'requested': true,
        'acknowledged': false,
        'error': '$error',
      };
      return false;
    }
  }

  List<String> _failedChecks() => [
    for (final entry in checks.entries)
      if (!entry.value) entry.key,
  ];

  void _enterStep(String step) {
    _step = step;
    stage = step;
  }
}

// Read-only schema-v3 predicates: a missing resource is never a location ACK.
bool _isAccountPage(Map? value, String page, {String? kind, String? id}) {
  final navigation = value?['navigation'];
  return value?['schemaVersion'] == 3 &&
      navigation is Map &&
      navigation['source'] == 'goRouter' &&
      navigation['page'] == page &&
      (kind == null || navigation['account']?['kind'] == kind) &&
      (id == null || navigation['account']?['id'] == id);
}

bool _hasAccountEditor(Map? value) {
  final editor = value?['editor'];
  if (editor is! Map) return false;
  final creating = editor['creating'] == true;
  final target = editor['target'];
  if (target is! Map ||
      !const {'native', 'acp'}.contains(target['kind']) ||
      target['id'] is! String ||
      (target['id'] as String).isEmpty) {
    return false;
  }
  if (!_isAccountPage(
    value,
    creating ? 'create' : 'edit',
    kind: creating ? null : target['kind'] as String,
    id: creating ? null : target['id'] as String,
  )) {
    return false;
  }
  final entry = value?['navigation']?['entry'];
  final mounted =
      value?['mountedViews']?[target['kind'] == 'native'
          ? 'nativeEditor'
          : 'acpEditor'];
  return entry is Map &&
      entry['kind'] == (creating ? 'creating' : 'editing') &&
      entry['routeEntryId'] is String &&
      (entry['routeEntryId'] as String).isNotEmpty &&
      (creating ||
          (entry['target']?['kind'] == target['kind'] &&
              entry['target']?['id'] == target['id'])) &&
      value?['resourceStatus']?['editorSession'] == 'active' &&
      value?['resourceStatus']?['editor'] == 'observed' &&
      editor['editorId'] is String &&
      (editor['editorId'] as String).isNotEmpty &&
      mounted?['visible'] == true &&
      mounted?['editorId'] == editor['editorId'];
}

bool _hasAccountDetails(Map? value, String kind, String id) =>
    _isAccountPage(value, 'details', kind: kind, id: id) &&
    value?['resourceStatus']?['details'] == 'observed' &&
    value?['details']?['target']?['kind'] == kind &&
    value?['details']?['target']?['id'] == id &&
    value?['details']?['observed'] == true &&
    value?['details']?['stale'] == false &&
    value?['mountedViews']?['details']?['visible'] == true;

bool _hasAccountList(Map? value) =>
    _isAccountPage(value, 'list') &&
    value?['resourceStatus']?['list'] == 'observed' &&
    value?['list']?['phase'] == 'ready' &&
    value?['mountedViews']?['list']?['visible'] == true;
