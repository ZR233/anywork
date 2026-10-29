import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';

import 'support/accounts_test_runtime.dart';

final class _AcpTransport extends AccountsTestTransport {
  _AcpTransport() {
    epoch = 'test';
  }
  final startEntered = Completer<void>();
  final cancelEntered = <String, Completer<void>>{};
  int settingsRevision = 4;
  int saveCalls = 0;
  int startCalls = 0;
  int cancelCalls = 0;
  Object? saveFailure;
  final List<OperationId> saveOperations = [];
  final saveEntered = Completer<void>();
  Completer<void>? saveGate;
  bool saveDurable = true;
  bool includeSaveFrames = true;

  /// 命令回执携带的 snapshot revision；调用方可抬高以模拟更新的 topic 事实。
  int startRevision = 1;
  int cancelRevision = 2;

  /// 收到的取消请求（账号 + 目标 operation）：测试据此证明“取消打到了正确的操作”。
  final List<({String accountId, String targetOperationId})> cancelRequests =
      [];

  /// 每个账号的取消连接身份（默认 7，与单账号用例一致）。
  final Map<String, int> cancelConnectionRevisions = {};

  /// 按账号挂住取消，用于证明账号之间互不阻塞：只挂指定账号，其余立刻完成。
  final Set<String> holdCancelAccounts = {};
  final Map<String, Completer<void>> _cancelGates = {};

  Completer<void>? cancelGate(String accountId) => _cancelGates[accountId];

  void releaseCancel(String accountId) {
    final gate = _cancelGates.remove(accountId);
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// 保存的 ACP 配置行。
  List<AcpAccountSettingsView> accounts = const [];

  /// 命令回执必须是**全量** auth 快照；只回一个账号会让多账号用例误判旧条目消失。
  final Map<String, AcpAuthAccountView> authAccounts = {};

  /// 令 start 停在 transport 上，用于观察并发去重与迟到回执。
  Completer<void>? pendingStart;
  bool holdStart = false;
  StudioFailure? startFailure;
  AcpAuthActionView? lastAction;
  int? lastConnectionRevision;
  AcpAccountUpdateView? lastSaved;

  SettingsCommandReply _reply(OperationId operationId) {
    settingsRevision += 1;
    return accountReply(
      snapshot: SettingsStateSnapshot(
        revision: settingsRevision,
        acpAccounts: accounts,
      ),
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'settings',
            ownerEpoch: 'test',
            revision: settingsRevision,
          ),
        ],
        effect: EffectPoint.futureSession,
        effective: true,
        durable: saveDurable,
      ),
    );
  }

  AcpAuthSnapshotView _authSnapshot(int revision) => AcpAuthSnapshotView(
    revision: revision,
    updatedAt: revision,
    accounts: authAccounts.values.toList(growable: false),
  );

  @override
  Future<SettingsCommandReply> saveAcpAccount(
    int expectedSettingsRevision,
    AcpAccountUpdateView account, {
    required OperationId operationId,
  }) async {
    saveCalls += 1;
    saveOperations.add(operationId);
    if (!saveEntered.isCompleted) saveEntered.complete();
    lastSaved = account;
    await saveGate?.future;
    final failure = saveFailure;
    if (failure != null) throw failure;
    accounts = [
      AcpAccountSettingsView(
        accountId: account.accountId,
        name: account.name,
        provider: account.provider,
        connectionRevision: 7,
      ),
    ];
    final reply = _reply(operationId);
    return includeSaveFrames
        ? reply
        : SettingsCommandReply(
            snapshot: reply.snapshot,
            receipt: reply.receipt,
          );
  }

  @override
  Future<SettingsCommandReply> removeAcpAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async {
    accounts = [
      for (final account in accounts)
        if (account.accountId != accountId) account,
    ];
    return _reply(operationId);
  }

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    startCalls += 1;
    if (!startEntered.isCompleted) startEntered.complete();
    lastAction = action;
    lastConnectionRevision = expectedConnectionRevision;
    final failure = startFailure;
    if (failure != null) throw failure;
    authAccounts[accountId] = AcpAuthAccountView(
      accountId: accountId,
      connectionRevision: expectedConnectionRevision,
      state: AcpCheckingState(operationId: operationId.value),
    );
    final reply = AcpAuthCommandReply(
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'acp-auth',
            ownerEpoch: 'test',
            revision: startRevision,
          ),
        ],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
      snapshot: _authSnapshot(startRevision),
    );
    if (holdStart) {
      final gate = pendingStart = Completer<void>();
      await gate.future;
    }
    return reply;
  }

  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) async {
    cancelCalls += 1;
    cancelRequests.add((
      accountId: accountId,
      targetOperationId: targetOperationId.value,
    ));
    if (holdCancelAccounts.contains(accountId)) {
      cancelEntered.putIfAbsent(accountId, Completer<void>.new).complete();
      final gate = _cancelGates[accountId] = Completer<void>();
      await gate.future;
    }
    // revision 在真正完成时分配，模拟运行期按提交顺序发布。
    final revision = cancelRevision++;
    authAccounts[accountId] = AcpAuthAccountView(
      accountId: accountId,
      connectionRevision: cancelConnectionRevisions[accountId] ?? 7,
      state: const AcpCancelledState(),
    );
    return AcpAuthCommandReply(
      receipt: StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'acp-auth',
            ownerEpoch: 'test',
            revision: revision,
          ),
        ],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
      snapshot: _authSnapshot(revision),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

AccountsTestRuntime _client(_AcpTransport transport) {
  final runtime = AccountsTestRuntime(transport, clientId: 'acp');
  runtime.seed(
    SettingsStateSnapshot(
      revision: transport.settingsRevision,
      acpAccounts: transport.accounts,
    ),
  );
  addTearDown(runtime.close);
  return runtime;
}

Future<void> _saveConfirmationReady(AccountsTestRuntime runtime) async {
  // Join the mutation, then queue behind its awaiting composition's resumption.
  // These barriers do not depend on wall-clock timing or poll a state change.
  await runtime.coordinator.enqueue(() async {});
  await runtime.coordinator.enqueue(() async {});
}

void _apply(AccountsTestRuntime runtime, AcpAuthSnapshotView snapshot) {
  final transport = runtime.transport as _AcpTransport;
  transport.authAccounts
    ..clear()
    ..addEntries(
      snapshot.accounts.map((account) => MapEntry(account.accountId, account)),
    );
  runtime.domains.acceptFrame(
    AcpAuthFrame(
      testStamp('acp-auth', snapshot.revision, epoch: 'test'),
      snapshot,
    ),
  );
}

AcpAuthStateView _stateOf(
  AccountsTestRuntime runtime,
  String id, {
  required int connectionRevision,
}) =>
    (runtime.domains.acp.auth.value.value ?? const AcpAuthSnapshotView.empty())
        .stateOf(id, connectionRevision: connectionRevision);
AcpAccountSettingsView? _saved(AccountsTestRuntime runtime, String id) =>
    (runtime.domains.accounts.details(AcpAccountIdentity(id)).value.value
            as AcpAccountDetails?)
        ?.account;

const _update = AcpAccountUpdateView(
  accountId: 'acp-1',
  name: 'Antigravity',
  provider: AcpProviderView.antigravity,
);

void main() {
  test(
    'admitted unknown save returns settlement without checking or resending',
    () async {
      final failure = StateError('save response lost');
      final transport = _AcpTransport()
        ..saveFailure = failure
        ..saveGate = Completer<void>();
      final client = _client(transport);

      // A dispatched loss must settle, not throw or replay the save intent.
      final pending = client.domains.acp.saveAndConnect(_update);
      await transport.saveEntered.future;
      final handle = client.board.lookup(transport.saveOperations.single)!;
      OperationState? publishedFailure;
      final observer = handle.state.watch((next) {
        if (next.failurePhase == null || publishedFailure != null) return;
        publishedFailure = next;
        handle.accept(
          CommitReceipt(
            operationId: handle.id,
            disposition: CommitDisposition.applied,
            targets: [testStamp('settings', 5, epoch: 'test')],
            effect: EffectPoint.futureSession,
            durable: true,
            requiresIdentityObservation: true,
          ),
        );
        client.domains.acceptFrame(
          AccountDetailFrame(
            testStamp('settings', 5, epoch: 'test'),
            const AcpAccountIdentity('acp-1'),
            const AcpAccountDetails(
              AcpAccountSettingsView(
                accountId: 'acp-1',
                name: 'Antigravity',
                provider: AcpProviderView.antigravity,
                connectionRevision: 7,
              ),
            ),
          ),
        );
      });
      addTearDown(observer.cancel);
      transport.saveGate!.complete();
      final result = await pending;
      observer.cancel();
      expect(result.checkFailure, isNull);
      expect(result.saved, isNull);
      final operation = result.operation;
      expect(operation, same(publishedFailure));
      expect(operation.id, transport.saveOperations.single);
      expect(operation.target, 'account:acp:acp-1');
      expect(operation.failurePhase, OperationPhase.unknownOutcome);
      expect(operation.error, same(failure));
      expect(operation.receipt, isNull);
      expect(operation.observed, isFalse);
      expect(handle.state.value.failurePhase, isNull);
      expect(handle.state.value.observed, isTrue);
      expect(transport.saveCalls, 1);
      expect(transport.startCalls, 0);
      expect(client.board.lookup(operation.id)!.state.observerCount, 0);
    },
  );

  test('before admission errors still throw without transport', () async {
    final transport = _AcpTransport();
    final client = _client(transport);
    // Exhaust admission, rather than failing an already admitted request.
    final capacity = client.budget.capacities[ResourceKind.pendingOperation]!;
    for (var i = 0; i < capacity; i++) {
      client.board.begin(target: 'occupied:$i');
    }
    await expectLater(
      client.domains.acp.saveAndConnect(_update),
      throwsA(isA<ResourceBudgetExceeded>()),
    );
    expect(transport.saveCalls, 0);
    expect(transport.startCalls, 0);
  });

  test('admitted known rejection preserves draft and original error', () async {
    final failure = ArgumentError('invalid account');
    final transport = _AcpTransport()..saveFailure = failure;
    final client = _client(transport);
    const draft = DraftStamp(draftId: 'editor', revision: 3);
    final result = await client.domains.acp.saveAndConnect(
      _update,
      draft: draft,
    );
    expect(result.operation.id, transport.saveOperations.single);
    expect(result.operation.draft, draft);
    expect(result.operation.failurePhase, OperationPhase.rejected);
    expect(result.operation.error, same(failure));
    expect(result.saved, isNull);
    expect(result.checkFailure, isNull);
    expect(transport.startCalls, 0);
    expect(client.board.lookup(result.operation.id)!.state.observerCount, 0);
    // Independent save returns its own failure snapshot for a distinct intent.
    final independent = await client.domains.acp.save(_update);
    expect(transport.saveOperations, hasLength(2));
    expect(independent.id, transport.saveOperations.last);
    expect(independent.id, isNot(result.operation.id));
    expect(independent.failurePhase, OperationPhase.rejected);
    expect(independent.error, same(failure));
    expect(independent.receipt, isNull);
  });

  test(
    'receipt application failure returns syncFailed with receipt facts',
    () async {
      final transport = _AcpTransport()..saveGate = Completer<void>();
      final client = _client(transport);
      final failure = StateError('canonical settings apply failed');
      client.domains.onSettings = (_) => throw failure;
      final pending = client.domains.acp.saveAndConnect(_update);
      await transport.saveEntered.future;
      final handle = client.board.lookup(transport.saveOperations.single)!;
      OperationState? publishedFailure;
      final observer = handle.state.watch((next) {
        if (next.failurePhase == null || publishedFailure != null) return;
        publishedFailure = next;
        handle.accept(next.receipt!);
        client.domains.acceptFrame(
          AccountDetailFrame(
            testStamp('settings', transport.settingsRevision, epoch: 'test'),
            const AcpAccountIdentity('acp-1'),
            AcpAccountDetails(transport.accounts.single),
          ),
        );
      });
      addTearDown(observer.cancel);
      transport.saveGate!.complete();
      final result = await pending;
      observer.cancel();
      expect(result.operation, same(publishedFailure));
      expect(result.operation.id, transport.saveOperations.single);
      expect(result.operation.failurePhase, OperationPhase.syncFailed);
      expect(result.operation.error, same(failure));
      expect(result.operation.receipt?.operationId, result.operation.id);
      expect(result.operation.durable, isTrue);
      expect(result.operation.observed, isFalse);
      expect(handle.state.value.failurePhase, isNull);
      expect(handle.state.value.observed, isTrue);
      expect(result.saved, isNull);
      expect(result.checkFailure, isNull);
      expect(transport.startCalls, 0);
    },
  );

  test(
    'check waits for same save receipt, target observation and durability',
    () async {
      final transport = _AcpTransport()
        ..saveGate = Completer<void>()
        ..saveDurable = false
        ..includeSaveFrames = false;
      final client = _client(transport);
      final pending = client.domains.acp.saveAndConnect(_update);
      await transport.saveEntered.future;
      final operation = client.board.lookup(transport.saveOperations.single)!;
      expect(operation.state.value.receipt, isNull);
      expect(transport.startCalls, 0);
      transport.saveGate!.complete();
      // Draining the write lane is an event barrier, not a time delay.
      await _saveConfirmationReady(client);
      expect(operation.state.value.receipt, isNotNull);
      expect(operation.state.value.observed, isFalse);
      expect(transport.startCalls, 0);
      client.domains.acceptFrame(
        AccountDetailFrame(
          testStamp('settings', transport.settingsRevision, epoch: 'test'),
          const AcpAccountIdentity('acp-1'),
          AcpAccountDetails(transport.accounts.single),
        ),
      );
      expect(operation.state.value.observed, isTrue);
      expect(operation.state.value.durable, isFalse);
      expect(transport.startCalls, 0);
      operation.markDurable();
      final result = await pending;
      expect(result.operation.id, operation.id);
      expect(result.operation.observed, isTrue);
      expect(result.operation.durable, isTrue);
      expect(result.operation.failurePhase, isNull);
      expect(result.saved?.accountId, 'acp-1');
      expect(transport.lastConnectionRevision, 7);
      expect(transport.startCalls, 1);
      expect(operation.state.observerCount, 0);
    },
  );

  test(
    'same-target newer intent cannot replace waiting save identity or draft',
    () async {
      final transport = _AcpTransport()..saveDurable = false;
      final client = _client(transport);
      const draft = DraftStamp(draftId: 'first-editor', revision: 8);
      final pending = client.domains.acp.saveAndConnect(_update, draft: draft);
      await transport.saveEntered.future;
      await _saveConfirmationReady(client);
      final first = client.board.lookup(transport.saveOperations.single)!;
      expect(first.state.value.observed, isTrue);
      expect(
        first.state.observerCount,
        2,
        reason: 'retention and confirmation wait',
      );
      final newer = await client.domains.acp.save(
        _update,
        draft: const DraftStamp(draftId: 'newer-editor', revision: 1),
      );
      expect(newer.id, isNot(first.id));
      expect(transport.startCalls, 0);
      first.markDurable();
      final result = await pending;
      expect(result.operation.id, first.id);
      expect(result.operation.draft, draft);
      expect(result.saved?.accountId, 'acp-1');
      expect(transport.saveCalls, 2);
      expect(transport.startCalls, 1);
      expect(first.state.observerCount, 0);
    },
  );

  test(
    'waiting save preserves existing failure and releases both subscriptions',
    () async {
      final transport = _AcpTransport()..saveDurable = false;
      final client = _client(transport);
      final pending = client.domains.acp.saveAndConnect(_update);
      await transport.saveEntered.future;
      await _saveConfirmationReady(client);
      final operation = client.board.lookup(transport.saveOperations.single)!;
      expect(operation.state.observerCount, 2);
      final failure = StateError('original unknown outcome');
      var advanced = false;
      final observer = operation.state.watch((next) {
        if (next.failurePhase == null || advanced) return;
        advanced = true;
        operation.accept(next.receipt!);
        operation.markDurable();
      });
      addTearDown(observer.cancel);
      final publishedFailure = operation.unknownOutcome(failure);
      final result = await pending;
      observer.cancel();
      expect(result.operation, same(publishedFailure));
      expect(result.operation.failurePhase, OperationPhase.unknownOutcome);
      expect(result.operation.error, same(failure));
      expect(result.operation.receipt, isNotNull);
      expect(result.operation.observed, isTrue);
      expect(result.operation.durable, isFalse);
      expect(operation.state.value.failurePhase, isNull);
      expect(operation.state.value.durable, isTrue);
      expect(result.saved, isNull);
      expect(result.checkFailure, isNull);
      expect(transport.startCalls, 0);
      expect(operation.state.observerCount, 0);
    },
  );

  test('detail observation failure settles save but leaves SDK target observation owned', () async {
    final transport = _AcpTransport()..includeSaveFrames = false;
    final client = _client(transport);
    final pending = client.domains.acp.saveAndConnect(_update);
    await transport.saveEntered.future;
    await _saveConfirmationReady(client);
    final operation = client.board.lookup(transport.saveOperations.single)!;
    final target = AccountDetailTarget(const AcpAccountIdentity('acp-1'));
    final observation = await transport.attachedAccount(target);
    final failure = const StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'detail feed failed',
      retryable: true,
      correlationId: 'save-feed',
    );
    OperationState? publishedFailure;
    final observer = operation.state.watch((next) {
      if (next.failurePhase == null || publishedFailure != null) return;
      publishedFailure = next;
      // The SDK confirmation consumes reentrant proof before syncFailed returns.
      client.domains.acceptFrame(
        AccountDetailFrame(
          testStamp('settings', transport.settingsRevision, epoch: 'test'),
          const AcpAccountIdentity('acp-1'),
          AcpAccountDetails(transport.accounts.single),
        ),
      );
    });
    addTearDown(observer.cancel);
    observation.fail(failure);
    final result = await pending;
    observer.cancel();
    expect(result.operation, same(publishedFailure));
    expect(result.operation.failurePhase, OperationPhase.syncFailed);
    expect(result.operation.receipt, isNotNull);
    expect(result.operation.durable, isTrue);
    expect(result.operation.observed, isFalse);
    expect(result.operation.error, same(failure));
    expect(result.saved, isNull);
    expect(result.checkFailure, isNull);
    expect(transport.startCalls, 0);
    expect(operation.state.observerCount, 0);
    expect(operation.state.value.observed, isTrue);
    // Repeated late proof cannot alter the frozen failure or auto-connect.
    client.domains.acceptFrame(
      AccountDetailFrame(
        testStamp('settings', transport.settingsRevision, epoch: 'test'),
        const AcpAccountIdentity('acp-1'),
        AcpAccountDetails(transport.accounts.single),
      ),
    );
    expect(operation.state.value.observed, isTrue);
    expect(operation.state.value.failurePhase, OperationPhase.syncFailed);
    expect(
      result.operation.observed,
      isFalse,
      reason: 'returned snapshot is frozen',
    );
    expect(transport.startCalls, 0, reason: 'late proof never auto-connects');
  });

  for (final close in [false, true]) {
    test(
      '${close ? 'close' : 'owner retirement'} terminates save confirmation and joins',
      () async {
        final transport = _AcpTransport()..saveDurable = false;
        final client = _client(transport);
        final pending = client.domains.acp.saveAndConnect(_update);
        await transport.saveEntered.future;
        await _saveConfirmationReady(client);
        final operation = client.board.lookup(transport.saveOperations.single)!;
        expect(operation.state.observerCount, 2);
        if (close) {
          final report = await client.close();
          expect(report.unresolved, isEmpty);
        } else {
          client.domains.adoptOwnerEpoch('replacement');
          client.domains.adoptOwnerEpoch('test');
        }
        final result = await pending;
        expect(result.operation.id, operation.id);
        expect(result.operation.failurePhase, OperationPhase.syncFailed);
        expect(result.operation.receipt, isNotNull);
        expect(result.operation.observed, isTrue);
        expect(result.saved, isNull);
        expect(result.checkFailure, isNull);
        expect(transport.startCalls, 0);
        expect(operation.state.observerCount, 0);
      },
    );
  }
  test(
    'reducer accepts the first snapshot at revision zero and keeps order',
    () {
      final store = _client(_AcpTransport());
      expect(store.domains.acp.auth.value.value, isNull);
      expect(
        _stateOf(store, 'acp-1', connectionRevision: 7),
        isA<AcpUncheckedState>(),
      );

      _apply(
        store,
        const AcpAuthSnapshotView(
          revision: 0,
          updatedAt: 10,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpUncheckedState(),
            ),
          ],
        ),
      );
      expect(store.domains.acp.auth.value.value, isNotNull);
      expect(
        _stateOf(store, 'acp-1', connectionRevision: 7),
        isA<AcpUncheckedState>(),
      );

      _apply(
        store,
        const AcpAuthSnapshotView(
          revision: 2,
          updatedAt: 12,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpCheckingState(operationId: 'op-1'),
            ),
          ],
        ),
      );
      expect(
        _stateOf(store, 'acp-1', connectionRevision: 7),
        isA<AcpCheckingState>(),
      );

      // 迟到或重复事实不得回退当前状态。
      _apply(
        store,
        const AcpAuthSnapshotView(
          revision: 1,
          updatedAt: 11,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpUncheckedState(),
            ),
          ],
        ),
      );
      expect(
        _stateOf(store, 'acp-1', connectionRevision: 7),
        isA<AcpCheckingState>(),
      );
      expect(store.domains.acp.auth.value.stamp!.revision, 2);
    },
  );

  test(
    'transport failure keeps last canonical snapshot without inventing success',
    () async {
      final store = _client(_AcpTransport());
      _apply(
        store,
        const AcpAuthSnapshotView(
          revision: 3,
          updatedAt: 10,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(
                checkedAt: 10,
                server: AcpServerInfoView(
                  name: 'antigravity',
                  version: '1.0.0',
                ),
              ),
            ),
          ],
        ),
      );
      final demand = store.domains.acp.observeAuth();
      addTearDown(demand.release);
      final source = await store.transport.attachedAccount(
        const AcpAuthTarget(),
      );
      source.fail(
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'channel closed',
          retryable: true,
          correlationId: 'auth-observation',
        ),
      );
      await store.domains.acp.auth.waitFor((value) => value.failure != null);
      expect(
        store.domains.acp.auth.value.failure!.code,
        StudioFailureCode.unavailable,
      );
      expect(
        _stateOf(store, 'acp-1', connectionRevision: 7),
        isA<AcpVerifiedState>(),
      );
    },
  );

  test(
    'save then failed check keeps the saved account and does not resave',
    () async {
      final transport = _AcpTransport()
        ..startFailure = const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'ACP server did not start',
          retryable: true,
          correlationId: 'test-acp',
        );
      final client = _client(transport);

      final result = await client.domains.acp.saveAndConnect(_update);

      expect(result.saved, isNotNull);
      final saved = result.saved!;
      expect(saved.accountId, 'acp-1');
      expect(saved.connectionRevision, 7);
      expect(result.operation.id, transport.saveOperations.single);
      expect(result.operation.failurePhase, isNull);
      expect(result.operation.observed, isTrue);
      expect(result.operation.durable, isTrue);
      expect(result.checkFailure?.code, StudioFailureCode.unavailable);
      expect(transport.saveCalls, 1);
      expect(transport.startCalls, 1);
      expect(
        client.domains.accounts.state.value.accounts
            .where((a) => a.identity is AcpAccountIdentity)
            .map((a) => a.identity.accountId),
        ['acp-1'],
      );
    },
  );

  test(
    'check submits the canonical connection revision and reduces the reply',
    () async {
      final transport = _AcpTransport();
      final client = _client(transport);
      await client.domains.acp.saveAndConnect(_update);

      // 保存意图只带身份与显示名：受管 program/argv 由产品固定发行决定。
      expect(transport.lastSaved?.accountId, 'acp-1');
      expect(transport.lastSaved?.name, 'Antigravity');
      expect(transport.lastConnectionRevision, 7);
      expect(transport.lastAction, isA<AcpCheckActionView>());
      expect(
        _stateOf(client, 'acp-1', connectionRevision: 7),
        isA<AcpCheckingState>(),
      );
    },
  );

  test(
    'login sends the chosen method and cancel hits the current operation',
    () async {
      final transport = _AcpTransport();
      final client = _client(transport);
      await client.domains.acp.saveAndConnect(_update);

      _apply(
        client,
        AcpAuthSnapshotView(
          revision: 2,
          updatedAt: 2,
          accounts: const [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 2, server: null),
            ),
          ],
        ),
      );
      transport.startRevision = 3;
      transport.cancelRevision = 4;
      await client.domains.acp.login(
        const AcpAccountIdentity('acp-1'),
        methodId: 'oauth',
      );
      expect(transport.lastAction, isA<AcpAuthenticateActionView>());

      final cancelled = await client.domains.acp.cancelAuth(
        const AcpAccountIdentity('acp-1'),
      );
      expect(cancelled.accounts.single.state, isA<AcpCancelledState>());
    },
  );

  test(
    'a second start for the same account is rejected before transport',
    () async {
      final transport = _AcpTransport()..holdStart = true;
      final client = _client(transport);
      final connecting = client.domains.acp.saveAndConnect(_update);
      // 保存完成、check 已登记并挂在 transport 上。
      await transport.startEntered.future;
      expect(transport.startCalls, 1);

      await expectLater(
        client.domains.acp.check(const AcpAccountIdentity('acp-1')),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.busy,
          ),
        ),
      );
      expect(transport.startCalls, 1);

      transport.pendingStart!.complete();
      final result = await connecting;
      expect(result.checkFailure, isNull);
      expect(transport.startCalls, 1);

      // 完成后的新意图仍被受理：去重不吞掉后续动作。
      transport.holdStart = false;
      _apply(
        client,
        AcpAuthSnapshotView(
          revision: 2,
          updatedAt: 2,
          accounts: const [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 2, server: null),
            ),
          ],
        ),
      );
      transport.startRevision = 3;
      await client.domains.acp.check(const AcpAccountIdentity('acp-1'));
      expect(transport.startCalls, 2);
    },
  );

  test(
    'cancel refuses an operation owned by another connection identity',
    () async {
      final transport = _AcpTransport();
      final client = _client(transport);
      await client.domains.acp.saveAndConnect(_update);
      // 同一账号 ID 但连接身份已前进：旧 operation 不得被当作当前操作取消。
      _apply(
        client,
        const AcpAuthSnapshotView(
          revision: 12,
          updatedAt: 300,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 6,
              state: AcpAuthenticatingState(
                operationId: 'old-op',
                methodId: 'oauth',
              ),
            ),
          ],
        ),
      );
      expect(
        _stateOf(client, 'acp-1', connectionRevision: 7),
        isA<AcpUncheckedState>(),
      );
      await expectLater(
        client.domains.acp.cancelAuth(const AcpAccountIdentity('acp-1')),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.notFound,
          ),
        ),
      );
    },
  );

  test(
    'cancel without an active operation fails instead of faking a cancel',
    () async {
      final transport = _AcpTransport();
      final client = _client(transport);
      await client.domains.acp.saveAndConnect(_update);
      _apply(
        client,
        const AcpAuthSnapshotView(
          revision: 9,
          updatedAt: 200,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpCancelledState(),
            ),
          ],
        ),
      );

      await expectLater(
        client.domains.acp.cancelAuth(const AcpAccountIdentity('acp-1')),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.notFound,
          ),
        ),
      );
    },
  );

  test('closing state is reduced as busy and keeps the operation identity', () {
    final store = _client(_AcpTransport());
    _apply(
      store,
      const AcpAuthSnapshotView(
        revision: 4,
        updatedAt: 40,
        accounts: [
          AcpAuthAccountView(
            accountId: 'acp-1',
            connectionRevision: 7,
            state: AcpClosingState(
              operationId: 'op-close',
              failure: AcpAuthFailureView(
                code: AcpAuthFailureCodeView.cleanup,
                stage: AcpAuthStageView.cleanup,
                message: 'ACP process is still exiting',
                retryable: true,
              ),
            ),
          ),
        ],
      ),
    );
    final state = _stateOf(store, 'acp-1', connectionRevision: 7);
    expect(state, isA<AcpClosingState>());
    expect(state.isBusy, isTrue);
    expect(state.isSettled, isFalse);
    expect(state.operationId, 'op-close');
    expect(
      (state as AcpClosingState).failure?.code,
      AcpAuthFailureCodeView.cleanup,
    );
  });

  test(
    'cancel bypasses a pending start and its late reply cannot undo it',
    () async {
      final transport = _AcpTransport();
      final client = _client(transport);
      await client.domains.acp.saveAndConnect(_update);

      _apply(
        client,
        AcpAuthSnapshotView(
          revision: 2,
          updatedAt: 2,
          accounts: const [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpVerifiedState(checkedAt: 2, server: null),
            ),
          ],
        ),
      );
      // topic 先给出 Authenticating 与 operation 身份（start 命令本身还没回执）。
      final authenticating = const AcpAuthSnapshotView(
        revision: 5,
        updatedAt: 50,
        accounts: [
          AcpAuthAccountView(
            accountId: 'acp-1',
            connectionRevision: 7,
            state: AcpAuthenticatingState(
              operationId: 'op-auth',
              methodId: 'browser',
            ),
          ),
        ],
      );
      _apply(client, authenticating);

      transport
        ..holdStart = true
        ..cancelRevision = 6;
      final pendingStart = client.domains.acp.check(
        const AcpAccountIdentity('acp-1'),
      );
      await transport.startEntered.future;

      // 关键：cancel 不得等待 start 释放；start 仍挂在 transport 上。
      final cancelled = await client.domains.acp
          .cancelAuth(const AcpAccountIdentity('acp-1'))
          .timeout(const Duration(seconds: 5));
      expect(transport.cancelCalls, 1);
      expect(cancelled.accounts.single.state, isA<AcpCancelledState>());
      expect(
        _stateOf(client, 'acp-1', connectionRevision: 7),
        isA<AcpCancelledState>(),
      );

      // 迟到的 start 回执（revision 1）进入同一 reducer，但不得覆盖更晚的终态。
      transport.pendingStart!.complete();
      await pendingStart;
      expect(client.domains.acp.auth.value.stamp!.revision, 6);
      expect(
        _stateOf(client, 'acp-1', connectionRevision: 7),
        isA<AcpCancelledState>(),
      );
    },
  );

  test(
    'pending cancel on one account does not block cancel on another',
    () async {
      final transport = _AcpTransport()
        ..holdCancelAccounts.add('acp-1')
        ..cancelRevision = 40
        ..cancelConnectionRevisions['acp-1'] = 5
        ..cancelConnectionRevisions['acp-2'] = 9;
      final client = _client(transport);
      client.seed(
        SettingsStateSnapshot(
          revision: 1,
          acpAccounts: [
            const AcpAccountSettingsView(
              accountId: 'acp-1',
              name: 'A',
              provider: AcpProviderView.antigravity,
              connectionRevision: 5,
            ),
            AcpAccountSettingsView(
              accountId: 'acp-2',
              name: 'B',
              provider: AcpProviderView.antigravity,
              connectionRevision: 9,
            ),
          ],
        ),
      );
      _apply(
        client,
        const AcpAuthSnapshotView(
          revision: 30,
          updatedAt: 30,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 5,
              state: AcpAuthenticatingState(
                operationId: 'op-a',
                methodId: 'browser',
              ),
            ),
            AcpAuthAccountView(
              accountId: 'acp-2',
              connectionRevision: 9,
              state: AcpAuthenticatingState(
                operationId: 'op-b',
                methodId: 'browser',
              ),
            ),
          ],
        ),
      );

      final first = client.domains.acp.cancelAuth(
        const AcpAccountIdentity('acp-1'),
      );
      await transport.cancelEntered
          .putIfAbsent('acp-1', Completer<void>.new)
          .future;
      // A 的取消仍挂在 transport 上；B 的取消必须立刻到达并完成。
      final second = await client.domains.acp
          .cancelAuth(const AcpAccountIdentity('acp-2'))
          .timeout(const Duration(seconds: 5));
      expect(
        second.account('acp-2', connectionRevision: 9)!.state,
        isA<AcpCancelledState>(),
      );
      expect(transport.cancelRequests.length, 2);
      expect(transport.cancelRequests[0].accountId, 'acp-1');
      expect(transport.cancelRequests[0].targetOperationId, 'op-a');
      expect(transport.cancelRequests[1].accountId, 'acp-2');
      expect(transport.cancelRequests[1].targetOperationId, 'op-b');

      transport.releaseCancel('acp-1');
      await first.timeout(const Duration(seconds: 5));
      expect(
        _stateOf(client, 'acp-1', connectionRevision: 5),
        isA<AcpCancelledState>(),
      );
      expect(
        _stateOf(client, 'acp-2', connectionRevision: 9),
        isA<AcpCancelledState>(),
      );
    },
  );

  test(
    'busy from a stale owner keeps the saved config and recovers after closing',
    () async {
      final transport = _AcpTransport()
        ..startFailure = const StudioFailure(
          code: StudioFailureCode.busy,
          message: 'The previous ACP operation is still closing',
          retryable: true,
          correlationId: 'test-acp-busy',
        );
      final client = _client(transport);

      final result = await client.domains.acp.saveAndConnect(_update);
      // 保存是已成立事实：Busy 只是“连接未完成”。
      expect(result.saved, isNotNull);
      final saved = result.saved!;
      expect(saved.accountId, 'acp-1');
      expect(saved.connectionRevision, 7);
      expect(result.operation.id, transport.saveOperations.single);
      expect(result.operation.failurePhase, isNull);
      expect(result.checkFailure?.code, StudioFailureCode.busy);
      expect(_saved(client, 'acp-1')?.connectionRevision, 7);

      // 新连接身份在旧 owner 收束期间显示 Closing（旧 operation），随后 Unchecked。
      _apply(
        client,
        const AcpAuthSnapshotView(
          revision: 20,
          updatedAt: 200,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpClosingState(operationId: 'op-old'),
            ),
          ],
        ),
      );
      final closing = _stateOf(client, 'acp-1', connectionRevision: 7);
      expect(closing, isA<AcpClosingState>());
      expect(closing.isBusy, isTrue);
      _apply(
        client,
        const AcpAuthSnapshotView(
          revision: 21,
          updatedAt: 201,
          accounts: [
            AcpAuthAccountView(
              accountId: 'acp-1',
              connectionRevision: 7,
              state: AcpUncheckedState(),
            ),
          ],
        ),
      );
      expect(
        _stateOf(client, 'acp-1', connectionRevision: 7),
        isA<AcpUncheckedState>(),
      );

      // 收束后显式 check 新 probe，配置仍是已保存事实。
      transport
        ..startFailure = null
        ..startRevision = 22;
      await client.domains.acp.check(const AcpAccountIdentity('acp-1'));
      expect(client.domains.acp.auth.value.stamp!.revision, 22);
      expect(
        _stateOf(client, 'acp-1', connectionRevision: 7),
        isA<AcpCheckingState>(),
      );
      expect(_saved(client, 'acp-1')?.connectionRevision, 7);
    },
  );

  test('removing the account drops it from canonical settings', () async {
    final transport = _AcpTransport();
    final client = _client(transport);
    await client.domains.acp.saveAndConnect(_update);
    await client.domains.acp.remove(const AcpAccountIdentity('acp-1'));
    expect(client.domains.accounts.state.value.accounts, isEmpty);
  });
}
