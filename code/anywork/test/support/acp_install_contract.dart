// ACP install/auth/usage 摘要契约。独立于 GUI 旅程，
// 按固定 1.4.1 发行合同核验 summary、保存身份、取消观察与用量快照。
import 'dart:ffi';
import 'dart:io';

const _scenario = 'acp-auto-install';
const _providerWire = 'antigravity';

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

/// 独立于生产映射的验收期望，以官方 ABI API 和实际 OS 固定宿主。
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

/// 最终 summary 的唯一构造入口：请求/确认事实与状态在同一次构造里确定。
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

Map<String, dynamic>? acpObservedUsage(
  Map<String, dynamic> snapshot,
  AcpAccountIdentity identity,
) {
  final auth = (snapshot['settings'] as Map?)?['acpAuth'];
  final entries = auth is Map && auth['loaded'] == true
      ? auth['accounts']
      : null;
  if (entries is! List) return null;
  for (final entry in entries) {
    if (entry is! Map ||
        entry['accountId'] != identity.accountId ||
        entry['connectionRevision'] != identity.connectionRevision) {
      continue;
    }
    final usage = entry['usage'];
    return usage is Map ? usage.cast<String, dynamic>() : null;
  }
  return null;
}

/// A query stays busy until the protocol and process have both been closed.
bool acpUsageQueryReady(
  String? authKind, {
  required int revision,
  required int afterRevision,
  required bool hasUsage,
}) => switch (authKind) {
  'checking' || 'verifying' || 'closing' => false,
  'verified' => revision > afterRevision && hasUsage,
  _ => throw StateError(
    'ACP usage query ended without successful authentication: $authKind',
  ),
};

/// Verify the fixed native fixture report without deriving expected values from
/// the observed snapshot. This binds quota data to the account identity saved by
/// the actual first journey and rejects partial or extra fixture groups/limits.
Map<String, dynamic> requireAcpFixtureUsage(
  Map<String, dynamic> snapshot,
  AcpAccountIdentity identity,
) {
  if (acpObservedAuthState(snapshot, identity)?['kind'] != 'verified') {
    throw StateError('ACP quota capture has no current verified identity');
  }
  final usage = acpObservedUsage(snapshot, identity);
  if (usage == null || usage['checkedAt'] is! int) {
    throw StateError('ACP usage observation is absent for $identity');
  }
  final state = usage['state'];
  if (state is! Map || state['kind'] != 'ready' || state['groups'] is! List) {
    throw StateError('ACP usage did not reach ready: $state');
  }
  final groups = (state['groups'] as List).whereType<Map>().toList();
  if (groups.length != 2 ||
      groups[0]['name'] != 'Gemini Models' ||
      groups[1]['name'] != 'Disabled Models') {
    throw StateError('ACP quota groups changed: $groups');
  }
  final weeklyLimits = groups[0]['limits'];
  final disabledLimits = groups[1]['limits'];
  if (weeklyLimits is! List ||
      weeklyLimits.length != 2 ||
      disabledLimits is! List ||
      disabledLimits.length != 1) {
    throw StateError('ACP quota limits are incomplete: $groups');
  }
  final weekly = weeklyLimits[0];
  final burst = weeklyLimits[1];
  final legacy = disabledLimits[0];
  if (weekly is! Map ||
      weekly['label'] != 'Weekly Limit Remaining' ||
      weekly['remaining'] is! Map ||
      weekly['remaining']['kind'] != 'percentage' ||
      weekly['remaining']['value'] != 91 ||
      weekly['nextResetAt'] != 1790929320) {
    throw StateError('ACP weekly quota changed: $weekly');
  }
  if (burst is! Map ||
      burst['label'] != 'Burst Limit' ||
      burst['remaining'] is! Map ||
      burst['remaining']['kind'] != 'units' ||
      burst['remaining']['value'] != 1234 ||
      burst['nextResetAt'] != null) {
    throw StateError('ACP burst quota changed: $burst');
  }
  if (legacy is! Map ||
      legacy['label'] != 'Legacy Limit' ||
      legacy['remaining'] is! Map ||
      legacy['remaining']['kind'] != 'disabled' ||
      legacy['nextResetAt'] != null) {
    throw StateError('ACP disabled quota changed: $legacy');
  }
  return usage;
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

/// unsafe ZIP 场景的真实验收判定；text 必须来自 failure 控件的真实可见文本。
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
