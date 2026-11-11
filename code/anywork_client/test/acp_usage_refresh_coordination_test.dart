import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/acp.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

/// 只脚本化传输层；准入、去重、Busy 切面与等待协调全部在真实 SDK 中执行。
final class _AcpUsageTransport extends AccountsTestTransport {
  _AcpUsageTransport() {
    epoch = 'test';
  }

  int settingsRevision = 3;
  int startRevision = 1;
  String authEpoch = 'test';
  int startCalls = 0;
  final List<
    ({
      String accountId,
      AcpAuthActionView action,
      int connectionRevision,
      OperationId operationId,
    })
  >
  startRequests = [];
  final Map<String, AcpAuthAccountView> authAccounts = {};
  final Map<String, List<Object>> startFailures = {};
  final Set<String> holdStartAccounts = {};
  final Map<String, Completer<void>> startEntered = {};
  final Map<String, Completer<void>> _startGates = {};

  void scriptStartFailure(String accountId, Object failure) =>
      startFailures.putIfAbsent(accountId, () => <Object>[]).add(failure);

  void releaseStart(String accountId) {
    final gate = _startGates.remove(accountId);
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  AcpAuthSnapshotView _snapshot(int revision) => AcpAuthSnapshotView(
    revision: revision,
    updatedAt: revision,
    accounts: authAccounts.values.toList(growable: false),
  );

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    startCalls += 1;
    startRequests.add((
      accountId: accountId,
      action: action,
      connectionRevision: expectedConnectionRevision,
      operationId: operationId,
    ));
    final entered = startEntered.putIfAbsent(accountId, Completer<void>.new);
    if (!entered.isCompleted) entered.complete();
    if (holdStartAccounts.contains(accountId)) {
      final gate = Completer<void>();
      _startGates[accountId] = gate;
      await gate.future;
    }
    final failures = startFailures[accountId];
    if (failures != null && failures.isNotEmpty) throw failures.removeAt(0);
    authAccounts[accountId] = AcpAuthAccountView(
      accountId: accountId,
      connectionRevision: expectedConnectionRevision,
      state: AcpCheckingState(operationId: operationId.value),
      // 与真实 owner 同一契约：busy 状态与活动操作投影来自同一受理身份。
      activeOperation: AcpAuthActiveOperationView(
        operationId: operationId.value,
        connectionRevision: expectedConnectionRevision,
        action: action,
      ),
    );
    final revision = startRevision++;
    return AcpAuthCommandReply(
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [testStamp('acp-auth', revision, epoch: authEpoch)],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
      snapshot: _snapshot(revision),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

const _identity = AcpAccountIdentity('acp-1');
const _detailTarget = AccountDetailTarget(_identity);

final _account = AcpAccountSettingsView(
  accountId: 'acp-1',
  name: 'Antigravity',
  template: AcpProviderView.antigravity,
  documentRevision: BigInt.one,
  connectionRevision: 7,
);

AccountsTestRuntime _client(
  _AcpUsageTransport transport, {
  List<AcpAccountSettingsView> accounts = const [],
}) {
  final runtime = AccountsTestRuntime(transport, clientId: 'acp-usage');
  runtime.seed(
    SettingsStateSnapshot(
      revision: transport.settingsRevision,
      acpAccounts: accounts,
    ),
  );
  addTearDown(runtime.close);
  return runtime;
}

void _applyAuth(
  AccountsTestRuntime runtime,
  AcpAuthSnapshotView snapshot, {
  String epoch = 'test',
}) {
  final transport = runtime.transport as _AcpUsageTransport;
  transport.authAccounts
    ..clear()
    ..addEntries(
      snapshot.accounts.map((account) => MapEntry(account.accountId, account)),
    );
  runtime.domains.acceptFrame(
    AcpAuthFrame(
      testStamp('acp-auth', snapshot.revision, epoch: epoch),
      snapshot,
    ),
  );
}

AccountDetailFrame _detailFrame(
  AcpAccountSettingsView account,
  int revision, {
  String epoch = 'test',
}) => AccountDetailFrame(
  testStamp('settings', revision, epoch: epoch),
  AcpAccountIdentity(account.accountId),
  AcpAccountDetails(account),
);

void _applyConnection(
  AccountsTestRuntime runtime,
  AcpAccountSettingsView account,
  int revision,
) {
  runtime.domains.acceptFrame(
    AccountDetailFrame(
      testStamp('settings', revision, epoch: 'test'),
      AcpAccountIdentity(account.accountId),
      AcpAccountDetails(account),
    ),
  );
}

StudioFailure _busyFailure(String? detailsJson) => StudioFailure(
  code: StudioFailureCode.busy,
  message: 'An ACP operation is already active',
  retryable: false,
  correlationId: 'test-acp-busy',
  detailsJson: detailsJson,
);

String _busyDetails({
  required String accountId,
  required int connectionRevision,
  required int snapshotRevision,
  required String operationId,
  required int activeConnectionRevision,
  required String action,
}) => jsonEncode({
  'acpAuthBusy': {
    'accountId': accountId,
    'connectionRevision': connectionRevision,
    'snapshotRevision': snapshotRevision,
    'activeOperation': {
      'operationId': operationId,
      'connectionRevision': activeConnectionRevision,
      'action': {'action': action},
    },
  },
});

Future<void> _pump() => Future<void>.delayed(Duration.zero);

Matcher _failure(String correlationId) => isA<StudioFailure>().having(
  (failure) => failure.correlationId,
  'correlationId',
  correlationId,
);

const _oldFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'retired account observation failed',
  retryable: true,
  correlationId: 'old-detail-fail',
);

const _newFailure = StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'new account observation failed',
  retryable: true,
  correlationId: 'new-detail-fail',
);

Future<TestAccountObservation> _attachedDetail(_AcpUsageTransport transport) =>
    transport.attachedAccount(_detailTarget);

bool _detailReleased(_AcpUsageTransport transport) {
  final attached = transport.observations[_detailTarget];
  return attached == null || attached.isEmpty;
}

Future<void> _entered(_AcpUsageTransport transport, String accountId) =>
    transport.startEntered.putIfAbsent(accountId, Completer<void>.new).future;

void main() {
  test(
    'two requests before the first await submit exactly one usage query',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      final first = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final second = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      expect(await first.result, AcpUsageRefreshDisposition.started);
      expect(await second.result, AcpUsageRefreshDisposition.joined);
      expect(transport.startCalls, 1);
      expect(
        transport.startRequests.single.action,
        isA<AcpQueryUsageActionView>(),
      );
      expect(transport.startRequests.single.connectionRevision, 7);
    },
  );

  test(
    'an already admitted usage query is joined without a new submission',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      await service.queryUsage(_identity);
      expect(transport.startCalls, 1);
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      expect(await request.result, AcpUsageRefreshDisposition.joined);
      expect(transport.startCalls, 1);
      expect(
        transport.startRequests.single.action,
        isA<AcpQueryUsageActionView>(),
      );
    },
  );

  test(
    'refresh waits for a local check to finish and then admits once',
    () async {
      final transport = _AcpUsageTransport()..holdStartAccounts.add('acp-1');
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      final check = service.check(_identity);
      await _entered(transport, 'acp-1');
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      expect(transport.startCalls, 1);
      transport.releaseStart('acp-1');
      await check;
      // 已受理的检查仍占用同连接槽位：刷新继续等待，不并行提交。
      expect(transport.startCalls, 1);
      _applyAuth(
        client,
        const AcpAuthSnapshotView(
          revision: 5,
          updatedAt: 5,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 5, server: null),
            ),
          ],
        ),
      );
      await _pump();
      expect(transport.startCalls, 2);
      transport.releaseStart('acp-1');
      expect(await request.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 2);
      expect(transport.startRequests[1].action, isA<AcpQueryUsageActionView>());
      expect(transport.startRequests[1].connectionRevision, 7);
    },
  );

  test(
    'refresh recovers after a local check is rejected at the transport',
    () async {
      final transport = _AcpUsageTransport()
        ..holdStartAccounts.add('acp-1')
        ..scriptStartFailure(
          'acp-1',
          const StudioFailure(
            code: StudioFailureCode.conflict,
            message: 'revision conflict',
            retryable: false,
            correlationId: 'test-check',
          ),
        );
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      final check = service.check(_identity);
      await _entered(transport, 'acp-1');
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      expect(transport.startCalls, 1);
      transport.releaseStart('acp-1');
      await expectLater(
        check,
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.conflict,
          ),
        ),
      );
      await _pump();
      expect(transport.startCalls, 2);
      transport.releaseStart('acp-1');
      expect(await request.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 2);
      expect(transport.startRequests[1].action, isA<AcpQueryUsageActionView>());
    },
  );

  test(
    'an external queryUsage busy facet is joined even without a busy frame',
    () async {
      final transport = _AcpUsageTransport()
        ..scriptStartFailure(
          'acp-1',
          _busyFailure(
            _busyDetails(
              accountId: 'acp-1',
              connectionRevision: 7,
              snapshotRevision: 4,
              operationId: 'ext-query',
              activeConnectionRevision: 7,
              action: 'queryUsage',
            ),
          ),
        );
      final client = _client(transport, accounts: [_account]);
      final request = client.domains.acp.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      expect(await request.result, AcpUsageRefreshDisposition.joined);
      expect(transport.startCalls, 1);
      final snapshot =
          client.domains.acp.auth.value.value ??
          const AcpAuthSnapshotView.empty();
      expect(
        snapshot.stateOf('acp-1', connectionRevision: 7),
        isA<AcpUncheckedState>(),
        reason: 'busy 帧被跳过时不得伪造本地忙碌状态',
      );
    },
  );

  test('an external check busy waits for evidence then submits once', () async {
    final transport = _AcpUsageTransport()
      ..scriptStartFailure(
        'acp-1',
        _busyFailure(
          _busyDetails(
            accountId: 'acp-1',
            connectionRevision: 7,
            snapshotRevision: 4,
            operationId: 'ext-check',
            activeConnectionRevision: 7,
            action: 'check',
          ),
        ),
      );
    final client = _client(transport, accounts: [_account]);
    final service = client.domains.acp;
    final request = service.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    await _pump();
    expect(transport.startCalls, 1);
    var settled = false;
    unawaited(
      request.result.then(
        (_) => settled = true,
        onError: (Object _, StackTrace _) {},
      ),
    );
    expect(settled, isFalse);
    _applyAuth(
      client,
      const AcpAuthSnapshotView(
        revision: 6,
        updatedAt: 6,
        accounts: [
          AcpAuthAccountView(
            accountId: 'acp-1',
            connectionRevision: 7,
            state: AcpVerifiedState(checkedAt: 6, server: null),
          ),
        ],
      ),
    );
    expect(await request.result, AcpUsageRefreshDisposition.started);
    expect(transport.startCalls, 2);
    expect(
      transport.startRequests[1].operationId,
      isNot(transport.startRequests[0].operationId),
      reason: '重新准入使用新的操作身份，不重用被拒意图',
    );
    await _pump();
    expect(transport.startCalls, 2);
  });

  for (final (label, failure) in [
    ('no details', _busyFailure(null)),
    ('malformed json', _busyFailure('not-json')),
    ('truncated facet', _busyFailure('{"acpAuthBusy":{"accountId":"acp-1"}}')),
    (
      'unknown action',
      _busyFailure(
        _busyDetails(
          accountId: 'acp-1',
          connectionRevision: 7,
          snapshotRevision: 4,
          operationId: 'ext-op',
          activeConnectionRevision: 7,
          action: 'login',
        ),
      ),
    ),
    (
      'foreign account',
      _busyFailure(
        _busyDetails(
          accountId: 'acp-other',
          connectionRevision: 7,
          snapshotRevision: 4,
          operationId: 'ext-op',
          activeConnectionRevision: 7,
          action: 'queryUsage',
        ),
      ),
    ),
  ]) {
    test(
      'busy rejection with $label keeps the original error and never resends',
      () async {
        final transport = _AcpUsageTransport()
          ..scriptStartFailure('acp-1', failure);
        final client = _client(transport, accounts: [_account]);
        final request = client.domains.acp.requestUsageRefresh(
          _identity,
          connectionRevision: 7,
        );
        await expectLater(
          request.result,
          throwsA(
            isA<StudioFailure>()
                .having((error) => error.code, 'code', StudioFailureCode.busy)
                .having(
                  (error) => error.detailsJson,
                  'detailsJson',
                  failure.detailsJson,
                ),
          ),
        );
        expect(transport.startCalls, 1);
        await _pump();
        expect(transport.startCalls, 1);
      },
    );
  }

  test('an issued attempt with unknown outcome is never resent', () async {
    final transport = _AcpUsageTransport()
      ..scriptStartFailure('acp-1', StateError('response lost'));
    final client = _client(transport, accounts: [_account]);
    final request = client.domains.acp.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    await expectLater(request.result, throwsA(isA<StateError>()));
    expect(transport.startCalls, 1);
    await _pump();
    expect(transport.startCalls, 1);
  });

  test(
    'cancelPending revokes its own intent without affecting other waiters',
    () async {
      final transport = _AcpUsageTransport()..holdStartAccounts.add('acp-1');
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      final check = service.check(_identity);
      await _entered(transport, 'acp-1');
      final first = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final second = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      first.cancelPending();
      expect(await first.result, AcpUsageRefreshDisposition.cancelled);
      expect(transport.startCalls, 1);
      transport.releaseStart('acp-1');
      await check;
      _applyAuth(
        client,
        const AcpAuthSnapshotView(
          revision: 5,
          updatedAt: 5,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 5, server: null),
            ),
          ],
        ),
      );
      await _pump();
      expect(transport.startCalls, 2);
      transport.releaseStart('acp-1');
      expect(await second.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 2);
      expect(
        transport.startRequests.last.action,
        isA<AcpQueryUsageActionView>(),
      );
    },
  );

  test('a replaced connection revokes the frozen intent', () async {
    final transport = _AcpUsageTransport()..holdStartAccounts.add('acp-1');
    final client = _client(transport, accounts: [_account]);
    final service = client.domains.acp;
    final check = service.check(_identity);
    await _entered(transport, 'acp-1');
    final request = service.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    _applyConnection(
      client,
      AcpAccountSettingsView(
        accountId: 'acp-1',
        name: 'Antigravity',
        template: AcpProviderView.antigravity,
        documentRevision: BigInt.one,
        connectionRevision: 8,
      ),
      4,
    );
    expect(await request.result, AcpUsageRefreshDisposition.cancelled);
    expect(transport.startCalls, 1);
    transport.releaseStart('acp-1');
    await check;
    expect(transport.startCalls, 1);
  });

  test('owner replacement revokes unissued intents', () async {
    final transport = _AcpUsageTransport()..holdStartAccounts.add('acp-1');
    final client = _client(transport, accounts: [_account]);
    final service = client.domains.acp;
    final check = service.check(_identity);
    await _entered(transport, 'acp-1');
    final request = service.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    client.domains.adoptOwnerEpoch('replacement');
    expect(await request.result, AcpUsageRefreshDisposition.cancelled);
    expect(transport.startCalls, 1);
    transport.releaseStart('acp-1');
    await expectLater(check, throwsA(anything));
  });

  test('two accounts coordinate independently of each other', () async {
    final transport = _AcpUsageTransport()..holdStartAccounts.add('acp-1');
    final client = _client(
      transport,
      accounts: [
        _account,
        AcpAccountSettingsView(
          accountId: 'acp-2',
          name: 'Backup',
          template: AcpProviderView.antigravity,
          documentRevision: BigInt.one,
          connectionRevision: 9,
        ),
      ],
    );
    final service = client.domains.acp;
    final slow = service.requestUsageRefresh(_identity, connectionRevision: 7);
    await _entered(transport, 'acp-1');
    final fast = service.requestUsageRefresh(
      const AcpAccountIdentity('acp-2'),
      connectionRevision: 9,
    );
    expect(await fast.result, AcpUsageRefreshDisposition.started);
    var slowSettled = false;
    unawaited(
      slow.result.then(
        (_) => slowSettled = true,
        onError: (Object _, StackTrace _) {},
      ),
    );
    await _pump();
    expect(slowSettled, isFalse);
    transport.releaseStart('acp-1');
    expect(await slow.result, AcpUsageRefreshDisposition.started);
    expect(transport.startCalls, 2);
    expect(transport.startRequests.map((request) => request.accountId), [
      'acp-1',
      'acp-2',
    ]);
  });

  test('a withdrawn attempt never reaches the transport on cancel', () async {
    final transport = _AcpUsageTransport();
    final client = _client(transport);
    final request = client.domains.acp.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    final observation = await _attachedDetail(transport);
    expect(transport.accountReads, isEmpty);
    request.cancelPending();
    expect(await request.result, AcpUsageRefreshDisposition.cancelled);
    await observation.stopped;
    await _pump();
    expect(observation.closed, isTrue);
    expect(_detailReleased(transport), isTrue);
    observation.emit(_detailFrame(_account, 4));
    await _pump();
    expect(transport.startCalls, 0);
    expect(transport.accountReads, isEmpty);
  });

  test(
    'cancelling one waiter lets the remaining waiter start exactly once',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport);
      final service = client.domains.acp;
      final first = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final second = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final observation = await _attachedDetail(transport);
      await _pump();
      first.cancelPending();
      expect(await first.result, AcpUsageRefreshDisposition.cancelled);
      expect(observation.closed, isFalse);
      transport.emitAccount(_detailFrame(_account, 4));
      expect(await second.result, AcpUsageRefreshDisposition.joined);
      expect(transport.startCalls, 1);
      await _pump();
      expect(transport.startCalls, 1);
      expect(transport.accountReads, isEmpty);
    },
  );

  test(
    'the last waiter cancelling releases the evidence wait and observation',
    () async {
      final transport = _AcpUsageTransport()
        ..scriptStartFailure(
          'acp-1',
          _busyFailure(
            _busyDetails(
              accountId: 'acp-1',
              connectionRevision: 7,
              snapshotRevision: 4,
              operationId: 'ext-check',
              activeConnectionRevision: 7,
              action: 'check',
            ),
          ),
        );
      final client = _client(transport, accounts: [_account]);
      final request = client.domains.acp.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      await _pump();
      expect(transport.startCalls, 1);
      bool authAttached() {
        final attached = transport.observations[const AcpAuthTarget()];
        return attached != null && attached.isNotEmpty;
      }

      expect(authAttached(), isTrue);
      request.cancelPending();
      expect(await request.result, AcpUsageRefreshDisposition.cancelled);
      await _pump();
      expect(authAttached(), isFalse);
      expect(transport.startCalls, 1);
    },
  );

  test(
    'a connection replacement during the unissued window settles cancelled',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport);
      final request = client.domains.acp.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      await _attachedDetail(transport);
      transport.emitAccount(
        _detailFrame(
          AcpAccountSettingsView(
            accountId: 'acp-1',
            name: 'Antigravity',
            template: AcpProviderView.antigravity,
            documentRevision: BigInt.one,
            connectionRevision: 8,
          ),
          4,
        ),
      );
      expect(await request.result, AcpUsageRefreshDisposition.cancelled);
      expect(transport.startCalls, 0);
      expect(transport.accountReads, isEmpty);
    },
  );

  test(
    'an owner replacement during the unissued window settles cancelled',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport);
      final request = client.domains.acp.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final observation = await _attachedDetail(transport);
      client.domains.adoptOwnerEpoch('replacement');
      observation.emit(_detailFrame(_account, 4));
      expect(await request.result, AcpUsageRefreshDisposition.cancelled);
      expect(transport.startCalls, 0);
      expect(transport.accountReads, isEmpty);
    },
  );

  test(
    'cancelling after issue leaves the retained business to its owner',
    () async {
      final transport = _AcpUsageTransport()
        ..holdStartAccounts.add('acp-1')
        ..scriptStartFailure('acp-1', StateError('response lost'));
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      await _entered(transport, 'acp-1');
      expect(transport.startCalls, 1);
      request.cancelPending();
      expect(await request.result, AcpUsageRefreshDisposition.cancelled);
      transport.releaseStart('acp-1');
      await _pump();
      // 已发出的业务交给原 owner 结算（未知结果保留观察）；取消不得重发。
      expect(transport.startCalls, 1);
      await expectLater(
        service.check(_identity),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.busy,
          ),
        ),
      );
      expect(transport.startCalls, 1);
    },
  );

  test('close wakes an evidence wait and settles it as cancelled', () async {
    final transport = _AcpUsageTransport()
      ..scriptStartFailure(
        'acp-1',
        _busyFailure(
          _busyDetails(
            accountId: 'acp-1',
            connectionRevision: 7,
            snapshotRevision: 4,
            operationId: 'ext-check',
            activeConnectionRevision: 7,
            action: 'check',
          ),
        ),
      );
    final client = _client(transport, accounts: [_account]);
    final request = client.domains.acp.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    await _pump();
    expect(transport.startCalls, 1);
    await client.close();
    expect(await request.result, AcpUsageRefreshDisposition.cancelled);
    expect(transport.startCalls, 1);
  });

  test(
    'a stale generation queue retires bound unissued waiters as cancelled',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport);
      final service = client.domains.acp;
      final stale = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final held = await _attachedDetail(transport);
      transport.authEpoch = 'replacement';
      transport.baselines[_detailTarget] = _detailFrame(
        _account,
        5,
        epoch: 'replacement',
      );
      client.domains.adoptOwnerEpoch('replacement');
      final fresh = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      // 旧观察已关闭：迟到的旧 owner 帧不能启动旧请求。
      held.emit(_detailFrame(_account, 4));
      expect(await stale.result, AcpUsageRefreshDisposition.cancelled);
      expect(await fresh.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 1);
      await _pump();
      expect(transport.startCalls, 1);
      expect(transport.accountReads, isEmpty);
    },
  );

  test(
    'evidence from a retired owner snapshot never settles the wait',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport, accounts: [_account]);
      // 旧 owner 已发布 rev 15 的终态；换代后它会作为残留观察保留。
      _applyAuth(
        client,
        const AcpAuthSnapshotView(
          revision: 15,
          updatedAt: 15,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 15, server: null),
            ),
          ],
        ),
      );
      transport.authEpoch = 'replacement';
      transport.baselines[_detailTarget] = _detailFrame(
        _account,
        5,
        epoch: 'replacement',
      );
      client.domains.adoptOwnerEpoch('replacement');
      transport.scriptStartFailure(
        'acp-1',
        _busyFailure(
          _busyDetails(
            accountId: 'acp-1',
            connectionRevision: 7,
            snapshotRevision: 12,
            operationId: 'ext-check',
            activeConnectionRevision: 7,
            action: 'check',
          ),
        ),
      );
      final request = client.domains.acp.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      await _pump();
      // 旧 owner 的残留快照（rev 15 ≥ 12 且已终态）不得立即充当证据。
      expect(transport.startCalls, 1);
      _applyAuth(
        client,
        const AcpAuthSnapshotView(
          revision: 13,
          updatedAt: 13,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 13, server: null),
            ),
          ],
        ),
        epoch: 'replacement',
      );
      expect(await request.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 2);
    },
  );

  test(
    'a waiter joining before admission shares the original unknown outcome',
    () async {
      final transport = _AcpUsageTransport()
        ..scriptStartFailure('acp-1', StateError('response lost'));
      final client = _client(transport);
      final service = client.domains.acp;
      final first = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final second = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      await _attachedDetail(transport);
      transport.emitAccount(_detailFrame(_account, 4));
      await expectLater(first.result, throwsA(isA<StateError>()));
      await expectLater(second.result, throwsA(isA<StateError>()));
      expect(transport.startCalls, 1);
      await _pump();
      expect(transport.startCalls, 1);
      expect(transport.accountReads, isEmpty);
    },
  );

  test(
    'joining a pending direct usage query settles joined on its receipt',
    () async {
      final transport = _AcpUsageTransport()..holdStartAccounts.add('acp-1');
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      final direct = service.queryUsage(_identity);
      await _entered(transport, 'acp-1');
      expect(transport.startCalls, 1);
      // 卡片在 port 已进入且回执未到时加入：这不是本队列发出的查询。
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      transport.releaseStart('acp-1');
      await direct;
      expect(await request.result, AcpUsageRefreshDisposition.joined);
      expect(transport.startCalls, 1);
      await _pump();
      expect(transport.startCalls, 1);
    },
  );

  test(
    'joining a pending direct usage query shares its unknown outcome',
    () async {
      final transport = _AcpUsageTransport()
        ..holdStartAccounts.add('acp-1')
        ..scriptStartFailure('acp-1', StateError('response lost'));
      final client = _client(transport, accounts: [_account]);
      final service = client.domains.acp;
      final direct = service.queryUsage(_identity);
      await _entered(transport, 'acp-1');
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      transport.releaseStart('acp-1');
      await expectLater(direct, throwsA(isA<StateError>()));
      await expectLater(request.result, throwsA(isA<StateError>()));
      expect(transport.startCalls, 1);
      await _pump();
      expect(transport.startCalls, 1);
    },
  );

  test(
    'cancelling the last waiter frees the slot while its detail read is stuck',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport);
      final service = client.domains.acp;
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final observation = await _attachedDetail(transport);
      expect(observation.closed, isFalse);
      expect(transport.accountReads, isEmpty);
      request.cancelPending();
      expect(await request.result, AcpUsageRefreshDisposition.cancelled);
      await observation.stopped;
      await _pump();
      expect(observation.closed, isTrue);
      expect(_detailReleased(transport), isTrue);
      expect(transport.accountReads, isEmpty);
      observation.emit(_detailFrame(_account, 9));
      await _pump();
      expect(transport.startCalls, 0);
      // 自己的监听、demand 与 active 已释放：同账号新 check 不 busy。
      // 直接 check 仍走原详情读取，与协调路径的可取消观察无关。
      final freshRead = Completer<AccountDomainFrame>()
        ..complete(_detailFrame(_account, 4));
      transport.accountRead = (target) => freshRead.future;
      await service.check(_identity);
      expect(transport.startCalls, 1);
      expect(transport.startRequests.single.action, isA<AcpCheckActionView>());
      final report = await client.close();
      expect(report.unresolved, isEmpty);
      expect(transport.accountReads, isNotEmpty);
    },
  );

  test(
    'an authoritative new connection frame withdraws the stuck admission',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport);
      final service = client.domains.acp;
      final request = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final observation = await _attachedDetail(transport);
      expect(transport.accountReads, isEmpty);
      // 新连接修订帧先于原读取到达：冻结意图立即撤销。
      _applyConnection(
        client,
        AcpAccountSettingsView(
          accountId: 'acp-1',
          name: 'Antigravity',
          template: AcpProviderView.antigravity,
          documentRevision: BigInt.one,
          connectionRevision: 8,
        ),
        4,
      );
      expect(await request.result, AcpUsageRefreshDisposition.cancelled);
      expect(observation.closed, isTrue);
      // 新连接的刷新可以立即开始并真实提交。
      final renewed = service.requestUsageRefresh(
        _identity,
        connectionRevision: 8,
      );
      expect(await renewed.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 1);
      // 已关闭观察上的迟到旧连接帧不发 port，也不覆盖新连接。
      observation.emit(_detailFrame(_account, 9));
      await _pump();
      expect(transport.startCalls, 1);
      expect(transport.startRequests.single.connectionRevision, 8);
      final current = client.domains.accounts.details(_identity).value.value;
      expect(
        current,
        isA<AcpAccountDetails>().having(
          (detail) => detail.account.connectionRevision,
          'connectionRevision',
          8,
        ),
      );
    },
  );

  test('the first observation frame starts exactly one usage query', () async {
    final transport = _AcpUsageTransport();
    final client = _client(transport);
    final service = client.domains.acp;
    final first = service.requestUsageRefresh(_identity, connectionRevision: 7);
    final second = service.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    await _attachedDetail(transport);
    transport.emitAccount(_detailFrame(_account, 4));
    expect(await first.result, AcpUsageRefreshDisposition.started);
    expect(await second.result, AcpUsageRefreshDisposition.joined);
    expect(transport.startCalls, 1);
    transport.emitAccount(_detailFrame(_account, 5));
    await _pump();
    expect(transport.startCalls, 1);
    expect(transport.accountReads, isEmpty);
  });

  test('an observation failure is visible and does not start', () async {
    final transport = _AcpUsageTransport();
    final client = _client(transport);
    final request = client.domains.acp.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    final observation = await _attachedDetail(transport);
    const failure = StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'account observation failed',
      retryable: true,
      correlationId: 'detail-fail',
    );
    observation.fail(failure);
    await expectLater(
      request.result,
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.correlationId,
          'correlationId',
          'detail-fail',
        ),
      ),
    );
    expect(transport.startCalls, 0);
    expect(transport.accountReads, isEmpty);
    await _pump();
    expect(transport.startCalls, 0);
  });

  test(
    'a retained failure does not hide already loaded same-owner details',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport, accounts: [_account]);
      final demand = client.domains.accounts.observeDetails(_identity);
      final observation = await _attachedDetail(transport);
      observation.fail(_oldFailure);
      await observation.stopped;
      await demand.release();
      await _pump();
      final request = client.domains.acp.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      expect(await request.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 1);
      expect(transport.accountReads, isEmpty);
    },
  );

  test(
    'retry after a retired failure waits for the new slot first frame',
    () async {
      final transport = _AcpUsageTransport();
      final client = _client(transport);
      final service = client.domains.acp;
      final failed = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      final retired = await _attachedDetail(transport);
      retired.fail(_oldFailure);
      await expectLater(failed.result, throwsA(_failure('old-detail-fail')));
      await retired.stopped;
      await _pump();
      final retry = service.requestUsageRefresh(
        _identity,
        connectionRevision: 7,
      );
      var settled = false;
      unawaited(
        retry.result.then(
          (_) => settled = true,
          onError: (Object _, StackTrace _) => settled = true,
        ),
      );
      await _pump();
      expect(settled, isFalse);
      expect(transport.startCalls, 0);
      final opened = await _attachedDetail(transport);
      expect(opened.closed, isFalse);
      expect(identical(opened, retired), isFalse);
      transport.emitAccount(_detailFrame(_account, 4));
      expect(await retry.result, AcpUsageRefreshDisposition.started);
      expect(transport.startCalls, 1);
      await _pump();
      expect(transport.startCalls, 1);
      expect(transport.accountReads, isEmpty);
    },
  );

  test('a new slot failure after retry settles the new error', () async {
    final transport = _AcpUsageTransport();
    final client = _client(transport);
    final service = client.domains.acp;
    final failed = service.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    final retired = await _attachedDetail(transport);
    retired.fail(_oldFailure);
    await expectLater(failed.result, throwsA(_failure('old-detail-fail')));
    await retired.stopped;
    await _pump();
    final retry = service.requestUsageRefresh(_identity, connectionRevision: 7);
    final opened = await _attachedDetail(transport);
    expect(identical(opened, retired), isFalse);
    opened.fail(_newFailure);
    await expectLater(retry.result, throwsA(_failure('new-detail-fail')));
    expect(transport.startCalls, 0);
    expect(transport.accountReads, isEmpty);
  });

  test('cancelling a retry releases its listener and demand', () async {
    final transport = _AcpUsageTransport();
    final client = _client(transport);
    final service = client.domains.acp;
    final failed = service.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    final retired = await _attachedDetail(transport);
    retired.fail(_oldFailure);
    await expectLater(failed.result, throwsA(_failure('old-detail-fail')));
    await retired.stopped;
    await _pump();
    final retry = service.requestUsageRefresh(_identity, connectionRevision: 7);
    final opened = await _attachedDetail(transport);
    retry.cancelPending();
    expect(await retry.result, AcpUsageRefreshDisposition.cancelled);
    await opened.stopped;
    await _pump();
    expect(opened.closed, isTrue);
    expect(_detailReleased(transport), isTrue);
    opened.emit(_detailFrame(_account, 4));
    await _pump();
    expect(transport.startCalls, 0);
    expect(transport.accountReads, isEmpty);
  });

  test('an old owner failure is not judged as the new source', () async {
    final transport = _AcpUsageTransport();
    final client = _client(transport);
    final service = client.domains.acp;
    final failed = service.requestUsageRefresh(
      _identity,
      connectionRevision: 7,
    );
    final retired = await _attachedDetail(transport);
    retired.fail(_oldFailure);
    await expectLater(failed.result, throwsA(_failure('old-detail-fail')));
    await retired.stopped;
    transport.authEpoch = 'replacement';
    client.domains.adoptOwnerEpoch('replacement');
    final retry = service.requestUsageRefresh(_identity, connectionRevision: 7);
    var settled = false;
    unawaited(
      retry.result.then(
        (_) => settled = true,
        onError: (Object _, StackTrace _) => settled = true,
      ),
    );
    await _pump();
    expect(settled, isFalse);
    final opened = await _attachedDetail(transport);
    opened.emit(_detailFrame(_account, 4));
    await _pump();
    expect(settled, isFalse);
    expect(transport.startCalls, 0);
    transport.emitAccount(_detailFrame(_account, 5, epoch: 'replacement'));
    expect(await retry.result, AcpUsageRefreshDisposition.started);
    expect(transport.startCalls, 1);
    expect(transport.accountReads, isEmpty);
  });
}
