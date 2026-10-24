import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/acp_fixture.dart';
import '../../test_driver/acp_install_journey.dart';

/// 独立于被测 Driver 与生产 mapping，按 design/28 的四条发布合同准备本机样例。
Map<String, Object?> _hostRelease() {
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
      'summary contract requires a supported desktop backend',
    ),
  };
  return {
    'version': '1.4.1',
    'target': target,
    'archiveUrl': 'https://dl.google.com/agy-extensions/releases/$archive',
    'sha256': null,
  };
}

/// Driver 最终 summary 的真实构造入口（`writeFinalSummary` 用的同一函数）。
///
/// 这里验证“完成/失败两条最终 summary 都带 exitRequest 的 request+ack 事实”，
/// close 失败会在落盘前把 completed 覆盖为 failed，以及同一 OUTPUT_DIR 顺序跑
/// 多个 phase 时截图/快照/树的文件名互不覆盖、captures 显式给出三类引用。
Map<String, Object?> _payload({
  required bool succeeded,
  required String? shutdown,
  required Map<String, Object?>? exitRequest,
  List<Map<String, Object?>> failures = const [],
  Map<String, bool> checks = const {'ok': true},
  Map<String, Object?>? savedAccount = const {
    'accountId': 'new-managed-account',
    'connectionRevision': 8,
  },
}) => acpInstallSummaryPayload(
  phase: 'first',
  stage: 'complete',
  succeeded: succeeded,
  checks: checks,
  captures: [
    acpInstallCaptureEntry(
      phase: 'first',
      ordinal: 0,
      name: 'progress',
      installPhase: 'resolving',
    ),
  ],
  failures: failures,
  install: const {'loaded': true, 'revision': 3, 'installations': []},
  shutdown: shutdown,
  exitRequest: exitRequest,
  savedAccount: savedAccount,
);

const _cancelChecks = {
  'cancelActionSent': true,
  'cancelHasOperation': true,
  'cancelReleaseCaptured': true,
  'cancelledKeepsOriginalOperation': true,
  'cancelledDidNotSave': true,
};

Map<String, Object?> _cancelDescriptor() => {
  'operationId': 'cancel-this-run',
  'release': _hostRelease(),
};

Map<String, Object?> _cancelPayload({
  required Map<String, Object?>? cancelledOperation,
  Map<String, Object?>? observation = const {
    'operationId': 'cancel-this-run',
    'observed': false,
    'capture': 'not-observed',
    'reason': 'First canonical observation was Cancelled.',
  },
  List<Map<String, Object?>> optionalCaptures = const [],
  Map<String, bool> checks = _cancelChecks,
}) => acpInstallSummaryPayload(
  phase: 'cancel',
  stage: 'complete',
  succeeded: true,
  checks: checks,
  failures: const [],
  captures: [
    acpInstallCaptureEntry(
      phase: 'cancel',
      ordinal: 0,
      name: 'downloading-before-cancel',
      installPhase: 'downloading',
    ),
    ...optionalCaptures,
    acpInstallCaptureEntry(
      phase: 'cancel',
      ordinal: 2,
      name: 'cancelled',
      installPhase: 'cancelled',
    ),
  ],
  install: const {
    'loaded': true,
    'revision': 4,
    'installations': [
      {
        'provider': 'antigravity',
        'phase': 'cancelled',
        'operationId': 'cancel-this-run',
      },
    ],
  },
  shutdown: 'completed',
  exitRequest: const {'requested': true, 'acknowledged': true},
  cancelledOperation: cancelledOperation,
  cancellingObservation: observation,
);

void main() {
  test('unsafe archive 失败要求同 op、invalidArchive/false 与真实非空控件文本', () {
    Map<String, dynamic> snapshot({
      Object? retryable = false,
      bool hasFlag = true,
      String code = 'invalidArchive',
      String operation = 'unsafe-this-run',
      String phase = 'failed',
    }) => {
      'settings': {
        'acpInstall': {
          'loaded': true,
          'revision': 10,
          'installations': [
            {
              'provider': 'antigravity',
              'phase': phase,
              'operationId': operation,
              'failure': {'code': code, if (hasFlag) 'retryable': retryable},
            },
          ],
        },
      },
    };
    bool readable(Map<String, dynamic> state, String text) =>
        acpUnsafeArchiveFailureReadable(
          state,
          operationId: 'unsafe-this-run',
          text: text,
        );

    expect(readable(snapshot(), '  Package rejected  '), isTrue);
    for (final invalid in [
      snapshot(retryable: true),
      snapshot(retryable: null),
      snapshot(retryable: 'false'),
      snapshot(hasFlag: false),
      snapshot(code: 'network'),
    ]) {
      expect(readable(invalid, 'Package rejected'), isFalse);
    }
    for (final empty in ['', '  \n\t ']) {
      expect(readable(snapshot(), empty), isFalse);
    }
    for (final invalid in [
      snapshot(operation: 'other-operation'),
      snapshot(operation: ''),
      snapshot(phase: 'ready'),
    ]) {
      expect(() => readable(invalid, 'Package rejected'), throwsStateError);
    }
  });

  test('a completed run keeps request+ack facts in the final summary', () {
    final payload = _payload(
      succeeded: true,
      shutdown: 'completed',
      exitRequest: const {'requested': true, 'acknowledged': true},
    );
    expect(payload['status'], 'completed');
    expect(payload['scenario'], 'acp-auto-install');
    expect(payload['phase'], 'first');
    expect(payload['humanVerdict'], 'pending');
    expect(payload['failedChecks'], isEmpty);
    expect(payload['failures'], isEmpty);
    expect(payload['shutdown'], 'completed');
    expect(payload['exitRequest'], {'requested': true, 'acknowledged': true});
    expect(payload['captures'], hasLength(1));
    expect(payload['savedAccount'], {
      'accountId': 'new-managed-account',
      'connectionRevision': 8,
    });
  });

  test('an unacknowledged exit request fails the run and is recorded', () {
    final payload = _payload(
      succeeded: true,
      shutdown: 'completed',
      exitRequest: const {
        'requested': true,
        'acknowledged': false,
        'error': 'TimeoutException after 0:00:30',
      },
    );
    expect(payload['status'], 'failed');
    final exit = payload['exitRequest'] as Map;
    expect(exit['requested'], isTrue);
    expect(exit['acknowledged'], isFalse);
    expect(exit['error'], contains('TimeoutException'));
  });

  test('a later close failure overwrites a completed run as failed', () {
    final payload = _payload(
      succeeded: true,
      shutdown: 'completed',
      exitRequest: const {'requested': true, 'acknowledged': true},
      failures: const [
        {'stage': 'complete', 'error': 'driver close failed: WebSocket closed'},
      ],
    );
    expect(payload['status'], 'failed');
    expect(payload['failures'], hasLength(1));
    // 退出请求事实仍保留，便于区分“退出已确认但收束失败”。
    expect((payload['exitRequest'] as Map)['acknowledged'], isTrue);
  });

  test('a degraded shutdown or empty checks cannot pass', () {
    expect(
      _payload(
        succeeded: true,
        shutdown: 'degraded',
        exitRequest: const {'requested': true, 'acknowledged': true},
      )['status'],
      'failed',
    );
    expect(
      acpInstallFinalStatus(
        succeeded: true,
        checks: const {},
        failures: const [],
        shutdown: 'completed',
        exitRequest: const {'requested': true, 'acknowledged': true},
      ),
      'failed',
    );
    expect(
      _payload(
        succeeded: true,
        shutdown: 'completed',
        exitRequest: const {'acknowledged': true},
      )['status'],
      'failed',
    );
    final missingIdentity = _payload(
      succeeded: true,
      shutdown: 'completed',
      exitRequest: const {'requested': true, 'acknowledged': true},
      savedAccount: null,
    );
    expect(missingIdentity['status'], 'failed');
    expect(
      missingIdentity['failedChecks'],
      contains('savedAccountIdentityRecorded'),
    );
    expect(
      _payload(
        succeeded: true,
        shutdown: 'completed',
        exitRequest: const {'requested': true, 'acknowledged': true},
        checks: const {'ok': false},
      )['status'],
      'failed',
    );
    expect(
      _payload(
        succeeded: false,
        shutdown: 'completed',
        exitRequest: const {'requested': true, 'acknowledged': true},
      )['status'],
      'failed',
    );
  });

  test('cancel 完成必须有同一终态操作的完整固定 descriptor', () {
    final release = _hostRelease();
    Map<String, Object?> payload(Map<String, Object?>? cancelled) =>
        _cancelPayload(cancelledOperation: cancelled);
    final valid = {'operationId': 'cancel-this-run', 'release': release};
    expect(payload(valid)['status'], 'completed');
    for (final invalid in <Map<String, Object?>?>[
      null,
      const {'operationId': 'cancel-this-run'},
      {
        'operationId': 'cancel-this-run',
        'release': {'version': '1.4.1'},
      },
      {
        'operationId': 'cancel-this-run',
        'release': {...release}..remove('sha256'),
      },
      {'operationId': '', 'release': release},
      {'operationId': 'different-operation', 'release': release},
      {
        'operationId': 'cancel-this-run',
        'release': {...release, 'target': 'other-host'},
      },
      {
        'operationId': 'cancel-this-run',
        'release': {
          ...release,
          'archiveUrl':
              'https://dl.google.com/agy-extensions/releases/wrong.zip',
        },
      },
    ]) {
      final summary = payload(invalid);
      expect(summary['status'], 'failed', reason: '$invalid');
      expect(summary['failedChecks'], contains('cancelledOperationRecorded'));
    }
  });

  test('cancel 摘要缺少瞬态观察记录必须失败，不能默认为未观察到', () {
    final summary = _cancelPayload(
      cancelledOperation: _cancelDescriptor(),
      observation: null,
    );
    expect(summary['status'], 'failed');
    expect(summary['failedChecks'], contains('cancellingObservationRecorded'));
  });

  test('三种取消瞬态结果都可完成，但摘要和 retry 消费拒绝矛盾、缺失和未知值', () {
    final capture = acpInstallCaptureEntry(
      phase: 'cancel',
      ordinal: 1,
      name: 'cancelling',
      installPhase: 'cancelling',
    );
    const base = {
      'operationId': 'cancel-this-run',
      'observed': true,
      'capture': 'captured',
      'reason':
          'Same operation remained Cancelling before and after screenshot.',
    };
    for (final (observation, optional) in [
      (base, [capture]),
      (
        {
          ...base,
          'observed': false,
          'capture': 'not-observed',
          'reason': 'First canonical observation was Cancelled.',
        },
        <Map<String, Object?>>[],
      ),
      (
        {
          ...base,
          'capture': 'phase-changed',
          'reason':
              'The same operation reached Closing while collecting screenshot.',
        },
        <Map<String, Object?>>[],
      ),
    ]) {
      final summary = _cancelPayload(
        cancelledOperation: _cancelDescriptor(),
        observation: observation,
        optionalCaptures: optional,
      );
      expect(summary['status'], 'completed');
      expect(summary['cancellingObservation'], observation);
      expect(
        () => requireAcpInstallCompletedSummary(summary, phase: 'cancel'),
        returnsNormally,
      );
    }

    void rejects(
      Map<String, Object?>? observation,
      List<Map<String, Object?>> optional,
    ) {
      final summary = _cancelPayload(
        cancelledOperation: _cancelDescriptor(),
        observation: observation,
        optionalCaptures: optional,
      );
      expect(summary['status'], 'failed', reason: '$observation / $optional');
      expect(
        summary['failedChecks'],
        contains('cancellingObservationRecorded'),
      );
      // 外部文件即使自称 completed、把 check 强改 true，也必须独立核验内容后拒绝。
      final forged = {
        ...summary,
        'status': 'completed',
        'failedChecks': const [],
        'checks': {
          ...(summary['checks'] as Map),
          'cancellingObservationRecorded': true,
        },
      };
      expect(
        () => requireAcpInstallCompletedSummary(forged, phase: 'cancel'),
        throwsStateError,
      );
    }

    rejects(null, []);
    rejects({...base}..remove('reason'), [capture]);
    rejects({...base, 'reason': ' '}, [capture]);
    rejects({...base}..remove('operationId'), [capture]);
    rejects({...base}..remove('observed'), [capture]);
    rejects({...base}..remove('capture'), [capture]);
    rejects({...base, 'operationId': 'other-operation'}, [capture]);
    rejects({...base, 'capture': 'unknown'}, []);
    rejects({...base, 'observed': 'true'}, [capture]);
    rejects({...base, 'observed': false}, [capture]);
    rejects(base, []);
    rejects(base, [capture, capture]);
    rejects(base, [
      {...capture, 'phase': 'cancelled'},
    ]);
    rejects(base, [
      {...capture}..remove('treeFile'),
    ]);
    rejects({...base, 'capture': 'not-observed'}, []);
    rejects({...base, 'capture': 'not-observed', 'observed': false}, [capture]);
    rejects({...base, 'capture': 'phase-changed', 'observed': false}, []);
    rejects({...base, 'capture': 'phase-changed'}, [capture]);
  });

  test('没有真实取消动作、身份错误或旧 failed 摘要仍拒绝，消费者不追改证据', () {
    final valid = _cancelPayload(cancelledOperation: _cancelDescriptor());
    final noAction = _cancelPayload(
      cancelledOperation: _cancelDescriptor(),
      checks: {..._cancelChecks}..remove('cancelActionSent'),
    );
    expect(noAction['status'], 'failed');
    expect(noAction['failedChecks'], contains('cancelActionSent'));
    final invalidInputs = [
      {
        ...valid,
        'status': 'failed',
        'failures': [
          {'error': 'earlier capture failed'},
        ],
      },
      {...valid}..remove('cancellingObservation'),
      {
        ...valid,
        'cancelledOperation': {
          ..._cancelDescriptor(),
          'operationId': 'wrong-op',
        },
      },
      noAction,
    ];
    for (final summary in invalidInputs) {
      final before = jsonEncode(summary);
      expect(
        () => requireAcpInstallCompletedSummary(summary, phase: 'cancel'),
        throwsStateError,
      );
      expect(jsonEncode(summary), before);
    }
  });

  test('取消观察只接受同 op 单向前进，正常跳过瞬态不放宽异常、倒退或身份变化', () {
    Map<String, dynamic> snapshot(
      String phase, {
      String? operation = 'cancel-this-run',
    }) => {
      'settings': {
        'acpInstall': {
          'loaded': true,
          'revision': 3,
          'installations': [
            {
              'provider': 'antigravity',
              'phase': phase,
              'operationId': operation,
              if (phase == 'downloading') 'release': _hostRelease(),
            },
          ],
        },
      },
    };
    for (final phases in [
      ['downloading', 'cancelling', 'cancelling', 'closing', 'cancelled'],
      ['downloading', 'cancelled'],
      ['downloading', 'closing', 'cancelled'],
      ['cancelling', 'cancelled'],
    ]) {
      var previous = AcpCancelPhase.downloading;
      for (final phase in phases) {
        previous = requireAcpCancelProgress(
          snapshot(phase),
          operationId: 'cancel-this-run',
          previous: previous,
        );
      }
      expect(previous, AcpCancelPhase.cancelled);
    }
    for (final (current, previous) in [
      ('ready', AcpCancelPhase.cancelling),
      ('failed', AcpCancelPhase.cancelling),
      ('unknown', AcpCancelPhase.downloading),
      ('idle', AcpCancelPhase.downloading),
      ('downloading', AcpCancelPhase.cancelling),
      ('cancelling', AcpCancelPhase.closing),
      ('closing', AcpCancelPhase.cancelled),
    ]) {
      expect(
        () => requireAcpCancelProgress(
          snapshot(current),
          operationId: 'cancel-this-run',
          previous: previous,
        ),
        throwsStateError,
      );
    }
    for (final operation in ['another-operation', '', null]) {
      expect(
        () => requireAcpCancelProgress(
          snapshot('cancelled', operation: operation),
          operationId: 'cancel-this-run',
          previous: AcpCancelPhase.cancelling,
        ),
        throwsStateError,
      );
    }
  });

  test('两个运行 phase 用真实写入函数写出 6 个产物且互不覆盖', () async {
    final dir = await Directory.systemTemp.createTemp('acp-install-captures-');
    addTearDown(() => dir.delete(recursive: true));

    // 同一 ordinal/name、仅运行 phase 不同：生产里每个 phase 的 _captureIndex
    // 都从 0 起，因此这正是会互相覆盖的组合。
    final first = await writeAcpInstallCapture(
      output: dir,
      phase: 'first',
      ordinal: 0,
      name: 'layout-current',
      installPhase: 'downloading',
      screenshot: const [0x89, 0x50, 0x4E, 0x47, 1, 1, 1],
      snapshot: '{"phase":"downloading","run":"first"}\n',
      tree: 'tree first\n',
    );
    final second = await writeAcpInstallCapture(
      output: dir,
      phase: 'reuse',
      ordinal: 0,
      name: 'layout-current',
      installPhase: 'ready',
      screenshot: const [0x89, 0x50, 0x4E, 0x47, 2, 2, 2],
      snapshot: '{"phase":"ready","run":"second"}\n',
      tree: 'tree second\n',
    );

    final refs = <String>{
      for (final entry in [first, second]) ...[
        entry['file']! as String,
        entry['snapshotFile']! as String,
        entry['treeFile']! as String,
      ],
    };
    expect(refs, hasLength(6));
    for (final name in refs) {
      expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
    }

    // 第二次写入没有覆盖第一次：内容仍是各自写入的字节与文本。
    Future<List<int>> png(Map<String, Object?> entry) async =>
        (await File('${dir.path}/${entry['file']}').readAsBytes()).toList();
    Future<String> text(Map<String, Object?> entry, String key) =>
        File('${dir.path}/${entry[key]}').readAsString();
    expect(await png(first), [0x89, 0x50, 0x4E, 0x47, 1, 1, 1]);
    expect(await png(second), [0x89, 0x50, 0x4E, 0x47, 2, 2, 2]);
    expect(await text(first, 'snapshotFile'), contains('"run":"first"'));
    expect(await text(second, 'snapshotFile'), contains('"run":"second"'));
    expect(await text(first, 'treeFile'), 'tree first\n');
    expect(await text(second, 'treeFile'), 'tree second\n');

    // 最终 summary 直接引用这些真实产物，状态判定不受影响。
    final payload = acpInstallSummaryPayload(
      phase: 'reuse',
      stage: 'complete',
      succeeded: true,
      checks: const {'ok': true},
      captures: [first, second],
      failures: const [],
      install: const {'loaded': true, 'revision': 4, 'installations': []},
      shutdown: 'completed',
      exitRequest: const {'requested': true, 'acknowledged': true},
    );
    expect(payload['status'], 'completed');
    final captures = (payload['captures']! as List).cast<Map>();
    expect(captures, hasLength(2));
    for (final entry in captures) {
      for (final key in ['file', 'snapshotFile', 'treeFile']) {
        final name = entry[key]! as String;
        expect(refs, contains(name));
        expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
      }
    }
  });

  // ── 账号身份/基线：各 phase 共享隔离 home，first 保存的账号会留给后面的 phase ──

  Map<String, dynamic> snapshotWith({
    required List<Map<String, Object?>> accounts,
    List<Map<String, Object?>> auth = const [],
    bool authLoaded = true,
  }) => {
    'settings': {
      'acpAccounts': accounts,
      'acpAuth': {'loaded': authLoaded, 'revision': 1, 'accounts': auth},
    },
  };

  Map<String, Object?> accountEntry({
    String id = 'antigravity',
    String name = 'Antigravity',
    int revision = 1,
  }) => {
    'accountId': id,
    'name': name,
    'provider': 'antigravity',
    'connectionRevision': revision,
  };

  Map<String, Object?> authEntry({
    String id = 'antigravity',
    int revision = 1,
  }) => {
    'accountId': id,
    'connectionRevision': revision,
    'state': const {'kind': 'required'},
  };

  test('保存身份只认新增 accountId，旧 id 改代次属改写而非新增', () {
    final empty = acpAccountsView(
      snapshotWith(accounts: const []),
      provider: 'antigravity',
    );
    final saved = acpAccountsView(
      snapshotWith(accounts: [accountEntry()], auth: [authEntry()]),
      provider: 'antigravity',
    );
    expect(acpAddedAccountIds(saved, empty), ['antigravity']);
    expect(acpSaveVerdict(saved, empty), AcpSaveVerdict.ready);
    // 历史账号原样留在配置里 → 没有本次保存证据（旧实现会误命中它）。
    expect(acpAddedAccountIds(saved, saved), isEmpty);
    expect(acpSaveVerdict(saved, saved), AcpSaveVerdict.pending);
    // 同一 accountId 只是连接代次变了：不是新增，而是把历史账号改写 → 终局失败。
    final rewritten = acpAccountsView(
      snapshotWith(
        accounts: [accountEntry(revision: 2)],
        auth: [authEntry(revision: 2)],
      ),
      provider: 'antigravity',
    );
    expect(acpAddedAccountIds(rewritten, saved), isEmpty);
    expect(acpSaveVerdict(rewritten, saved), AcpSaveVerdict.tampered);
    expect(() => acpSavedAccountIdentity(rewritten, saved), throwsStateError);
    final renamedOld = acpAccountsView(
      snapshotWith(
        accounts: [accountEntry(name: 'Replaced')],
        auth: [authEntry()],
      ),
      provider: 'antigravity',
    );
    expect(() => acpSavedAccountIdentity(renamedOld, saved), throwsStateError);
  });

  test('多个新增账号是终局失败，不在等待里挑一个', () {
    final empty = acpAccountsView(
      snapshotWith(accounts: const []),
      provider: 'antigravity',
    );
    final ambiguous = acpAccountsView(
      snapshotWith(
        accounts: [
          accountEntry(),
          accountEntry(id: 'antigravity-2'),
        ],
        auth: [
          authEntry(),
          authEntry(id: 'antigravity-2'),
        ],
      ),
      provider: 'antigravity',
    );
    final added = acpAddedAccountIds(ambiguous, empty);
    expect(added, hasLength(2));
    expect(added.toSet(), {'antigravity', 'antigravity-2'});
    // 终局判定：首次观察到两个新增就必须失败，不能是 pending 继续消费后续快照。
    expect(acpSaveVerdict(ambiguous, empty), AcpSaveVerdict.ambiguous);
    expect(acpSaveVerdict(ambiguous, empty), isNot(AcpSaveVerdict.pending));
    final laterSingle = acpAccountsView(
      snapshotWith(accounts: [accountEntry()], auth: [authEntry()]),
      provider: 'antigravity',
    );
    var observations = 0;
    AcpAccountIdentity? waitForIdentity() {
      for (final view in [ambiguous, laterSingle]) {
        observations += 1;
        final identity = acpSavedAccountIdentity(view, empty);
        if (identity != null) return identity;
      }
      return null;
    }

    expect(waitForIdentity, throwsStateError);
    expect(observations, 1, reason: '不能消费后来消失的歧义来掩盖首次多写');
  });

  test('唯一新增账号也要等连接代次落定才算可用身份', () {
    final empty = acpAccountsView(
      snapshotWith(accounts: const []),
      provider: 'antigravity',
    );
    // 账号已出现但 acpAuth 还没写入代次 → 继续等，不拿 null 代次去核对。
    final pendingRevision = acpAccountsView(
      snapshotWith(accounts: [accountEntry()]),
      provider: 'antigravity',
    );
    expect(acpAddedAccountIds(pendingRevision, empty), ['antigravity']);
    expect(acpSaveVerdict(pendingRevision, empty), AcpSaveVerdict.pending);
    // 代次落定 → 可用身份。
    final settled = acpAccountsView(
      snapshotWith(accounts: [accountEntry()], auth: [authEntry()]),
      provider: 'antigravity',
    );
    expect(acpSaveVerdict(settled, empty), AcpSaveVerdict.ready);
    // 旧账号丢失同样是终局失败。
    expect(acpSaveVerdict(empty, settled), AcpSaveVerdict.tampered);
  });

  test('“没保存”= 账号配置与基线一致，不是列表为空', () {
    final baseline = acpAccountsView(
      snapshotWith(accounts: [accountEntry()], auth: [authEntry()]),
      provider: 'antigravity',
    );
    // 历史账号仍在但配置未变 → 未保存成立（旧实现的“必须为空”会误判失败）。
    final unchanged = acpAccountsView(
      snapshotWith(accounts: [accountEntry()], auth: [authEntry()]),
      provider: 'antigravity',
    );
    expect(acpAccountsEqual(unchanged, baseline), isTrue);
    // 账号列表顺序不影响结论（身份按 accountId 建）。
    final reordered = acpAccountsView(
      snapshotWith(
        accounts: [accountEntry(id: 'z-second')],
        auth: [authEntry()],
      ),
      provider: 'antigravity',
    );
    expect(acpAccountsEqual(reordered, baseline), isFalse);
    // 名称被改写也不能被准备或新建保存掩盖。
    final rewritten = acpAccountsView(
      snapshotWith(
        accounts: [accountEntry(name: 'Overwritten')],
        auth: [authEntry()],
      ),
      provider: 'antigravity',
    );
    expect(acpAccountsEqual(rewritten, baseline), isFalse);
    // 新连接代次
    final resaved = acpAccountsView(
      snapshotWith(
        accounts: [accountEntry(revision: 2)],
        auth: [authEntry(revision: 2)],
      ),
      provider: 'antigravity',
    );
    expect(acpAccountsEqual(resaved, baseline), isFalse);
    // 账号被丢掉
    final dropped = acpAccountsView(
      snapshotWith(accounts: const []),
      provider: 'antigravity',
    );
    expect(acpAccountsEqual(dropped, baseline), isFalse);
  });

  test('账号视图按真实 accountId 建身份，不用显示名', () {
    final view = acpAccountsView(
      snapshotWith(
        accounts: [
          accountEntry(),
          accountEntry(id: 'second'),
        ],
        auth: [
          authEntry(),
          authEntry(id: 'second'),
        ],
      ),
      provider: 'antigravity',
    );
    expect(view.keys, ['antigravity', 'second']);
    expect(view['antigravity']!['connectionRevision'], 1);
  });

  test('acpAuth 未加载时不合成连接代次', () {
    final view = acpAccountsView(
      snapshotWith(accounts: [accountEntry()], authLoaded: false),
      provider: 'antigravity',
    );
    expect(view['antigravity']!['connectionRevision'], isNull);
  });

  test('认证代次必须匹配当前 canonical 配置，不采纳迟到的旧连接条目', () {
    final stale = acpAccountsView(
      snapshotWith(
        accounts: [accountEntry(revision: 9)],
        auth: [authEntry(revision: 7)],
      ),
      provider: 'antigravity',
    );
    expect(stale['antigravity']!['connectionRevision'], isNull);
    expect(acpSaveVerdict(stale, const {}), AcpSaveVerdict.pending);
    final current = acpAccountsView(
      snapshotWith(
        accounts: [accountEntry(revision: 9)],
        auth: [authEntry(revision: 9)],
      ),
      provider: 'antigravity',
    );
    expect(current['antigravity']!['connectionRevision'], 9);
    expect(acpSaveVerdict(current, const {}), AcpSaveVerdict.ready);
  });

  test('同一组配置与认证记录重排仍相等，认证尚未到达不伪造配置改写', () {
    final baseline = acpAccountsView(
      snapshotWith(
        accounts: [
          accountEntry(),
          accountEntry(id: 'second', revision: 4),
        ],
        auth: [
          authEntry(),
          authEntry(id: 'second', revision: 4),
        ],
      ),
      provider: 'antigravity',
    );
    final reordered = acpAccountsView(
      snapshotWith(
        accounts: [
          accountEntry(id: 'second', revision: 4),
          accountEntry(),
        ],
        auth: [
          authEntry(id: 'second', revision: 4),
          authEntry(),
        ],
      ),
      provider: 'antigravity',
    );
    expect(acpAccountsEqual(reordered, baseline), isTrue);
    final awaitingAuth = acpAccountsView(
      snapshotWith(
        accounts: [
          accountEntry(id: 'second', revision: 4),
          accountEntry(),
        ],
        authLoaded: false,
      ),
      provider: 'antigravity',
    );
    expect(acpOldAccountsIntact(awaitingAuth, baseline), isTrue);
  });

  test('required 认证截图绑定已加载的账号、配置代次、阶段与本次操作', () {
    const identity = (accountId: 'antigravity', connectionRevision: 3);
    Map<String, dynamic> state({
      String id = 'antigravity',
      int revision = 3,
      String kind = 'authenticating',
      String? operation = 'login-this-run',
      bool loaded = true,
    }) => snapshotWith(
      accounts: [accountEntry(revision: 3)],
      authLoaded: loaded,
      auth: [
        {
          ...authEntry(id: id, revision: revision),
          'state': {'kind': kind, 'operationId': operation},
        },
      ],
    );
    const expected = AcpAuthCapture(
      identity: identity,
      kind: 'authenticating',
      operationId: 'login-this-run',
    );
    expect(requireAcpAuthCapture(state(), expected)['kind'], 'authenticating');
    for (final invalid in [
      state(loaded: false),
      state(id: 'other-account'),
      state(revision: 2),
      state(kind: 'verified'),
      state(operation: 'another-login'),
      state(operation: null),
    ]) {
      expect(() => requireAcpAuthCapture(invalid, expected), throwsStateError);
    }
  });

  test('required 安装截图拒绝截图前后的阶段漂移、空操作或操作替换', () {
    Map<String, dynamic> state({
      String phase = 'downloading',
      String? operation = 'prepare-this-run',
      bool loaded = true,
    }) => {
      'settings': {
        'acpInstall': {
          'loaded': loaded,
          'revision': 0,
          'installations': [
            {
              'provider': 'antigravity',
              'phase': phase,
              'operationId': operation,
              'release': _hostRelease(),
            },
          ],
        },
      },
    };
    final operation = requireAcpInstallCapture(state(), phase: 'downloading');
    expect(operation, 'prepare-this-run');
    for (final invalid in [
      state(phase: 'ready'),
      state(operation: ''),
      state(operation: null),
      state(operation: 'new-prepare'),
      state(loaded: false),
    ]) {
      expect(
        () => requireAcpInstallCapture(
          invalid,
          phase: 'downloading',
          operationId: operation,
        ),
        throwsStateError,
      );
    }
  });

  test('下载与 Ready 证据都独立核本机固定 target、完整 URL、版本和无 publisher SHA', () {
    final release = _hostRelease();
    Map<String, dynamic> snapshot(String phase, Object? descriptor) => {
      'settings': {
        'acpInstall': {
          'loaded': true,
          'revision': 1,
          'installations': [
            {
              'provider': 'antigravity',
              'phase': phase,
              'operationId': 'prepare-this-run',
              'release': descriptor,
            },
          ],
        },
      },
    };
    for (final phase in ['downloading', 'ready']) {
      expect(
        requireAcpInstallCapture(snapshot(phase, release), phase: phase),
        'prepare-this-run',
      );
      for (final invalid in [
        null,
        {...release, 'target': 'other-host'},
        {
          ...release,
          'archiveUrl':
              'https://dl.google.com/agy-extensions/releases/wrong.zip',
        },
        {
          ...release,
          'archiveUrl': '${release['archiveUrl']}'.replaceFirst(
            'agy-extensions/releases/',
            '',
          ),
        },
        {...release, 'version': '1.4.2'},
        {...release, 'sha256': '0' * 64},
        {...release}..remove('sha256'),
      ]) {
        expect(
          () =>
              requireAcpInstallCapture(snapshot(phase, invalid), phase: phase),
          throwsStateError,
          reason: '$phase $invalid',
        );
      }
    }
  });

  test('取消归因拒绝同 attempt PID 的任何 sessionNew，保水位并忽略其它检查 PID', () async {
    final dir = await Directory.systemTemp.createTemp('acp-cancel-evidence-');
    addTearDown(() => dir.delete(recursive: true));
    final fixture = AcpFixture(stateDir: dir);
    final events = File('${dir.path}/events.jsonl');
    const history = [
      {'event': 'authenticate', 'pid': 10},
      {'event': 'authenticateReleased', 'pid': 10},
      {'event': 'sessionNew', 'pid': 10},
    ];
    Future<void> write(List<Map<String, Object>> attempt) async {
      await events.writeAsString(
        '${[...history, ...attempt].map(jsonEncode).join('\n')}\n',
      );
    }

    const accepted = {'event': 'authenticate', 'pid': 20};
    const released = {'event': 'authenticateReleased', 'pid': 20};
    const session = {'event': 'sessionNew', 'pid': 20};
    await write([
      accepted,
      {'event': 'sessionNew', 'pid': 30},
      released,
    ]);
    expect(
      (await fixture.evidenceSince(history.length)).isOrderedCancellation,
      isTrue,
    );
    for (final illegal in [
      [session, accepted, released],
      [accepted, session, released],
      [accepted, released, session],
    ]) {
      await write(illegal);
      expect(
        (await fixture.evidenceSince(history.length)).isOrderedCancellation,
        isFalse,
        reason: '$illegal',
      );
    }
  });

  test('behavior patch 保留未指定字段，只有显式参数可以重置 probe/disconnect', () async {
    final dir = await Directory.systemTemp.createTemp('acp-behavior-patch-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/behavior.json');
    const original = {
      'authentication': 'fail',
      'probe': 'fail',
      'disconnect': true,
      'serverInfo': {'name': 'synthetic-agent', 'version': '1.4.1'},
      'agentCapability': {'experimental': true},
    };
    await file.writeAsString(jsonEncode(original));
    final fixture = AcpFixture(stateDir: dir);
    await fixture.patchBehavior(authentication: 'wait');
    expect(jsonDecode(await file.readAsString()), {
      ...original,
      'authentication': 'wait',
    });
    await fixture.patchBehavior(
      authentication: 'success',
      probe: 'normal',
      disconnect: false,
    );
    expect(jsonDecode(await file.readAsString()), {
      ...original,
      'authentication': 'success',
      'probe': 'normal',
      'disconnect': false,
    });
    await fixture.patchBehavior(probe: 'fail');
    expect(jsonDecode(await file.readAsString()), {
      ...original,
      'authentication': 'success',
      'disconnect': false,
    });
  });
}
