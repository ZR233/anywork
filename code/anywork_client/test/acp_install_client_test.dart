import 'dart:async';

import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

const _release = AcpInstallReleaseView(
  version: '1.4.1',
  target: 'linux-x86_64',
  archiveUrl: 'https://dl.google.com/agy-extensions/releases/a.zip',
);
AcpInstallSnapshotView _snapshot(int revision, AcpInstallStateView state) =>
    AcpInstallSnapshotView(
      revision: revision,
      updatedAt: revision,
      installations: [
        AcpInstallEntryView(
          provider: AcpProviderView.antigravity,
          state: state,
        ),
      ],
    );

final class _InstallTransport extends AccountsTestTransport {
  _InstallTransport() {
    epoch = 'owner-1';
  }
  Completer<void>? pendingStart;
  final startEntered = Completer<void>();
  int startCalls = 0;
  int cancelCalls = 0;
  OperationId? lastStart;
  OperationId? lastCancelTarget;
  AcpProviderView? lastCancelProvider;
  @override
  Future<AcpInstallCommandReply> startAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
  }) async {
    startCalls++;
    lastStart = operationId;
    if (!startEntered.isCompleted) startEntered.complete();
    await pendingStart?.future;
    return _reply(
      operationId,
      _snapshot(1, AcpResolvingState(operationId: operationId.value)),
    );
  }

  AcpInstallCommandReply _reply(
    OperationId operation,
    AcpInstallSnapshotView snapshot,
  ) => AcpInstallCommandReply(
    receipt: StudioCommandReceipt(
      operationId: operation,
      disposition: CommitDisposition.applied,
      targets: [testStamp('acp-install', snapshot.revision, epoch: epoch)],
      effect: EffectPoint.immediate,
      effective: true,
      durable: false,
    ),
    snapshot: snapshot,
  );
  @override
  Future<AcpInstallCommandReply> cancelAcpInstall({
    required OperationId operationId,
    required AcpProviderView provider,
    required OperationId targetOperationId,
  }) async {
    cancelCalls++;
    lastCancelTarget = targetOperationId;
    lastCancelProvider = provider;
    final reply = _reply(
      operationId,
      _snapshot(
        2,
        AcpInstallCancellingState(operationId: targetOperationId.value),
      ),
    );
    pendingStart?.complete();
    pendingStart = null;
    return reply;
  }
}

AccountsTestRuntime _client(_InstallTransport transport) {
  final client = AccountsTestRuntime(transport, clientId: 'acp-install');
  addTearDown(client.close);
  return client;
}

void _apply(
  AccountsTestRuntime client,
  int revision,
  AcpInstallStateView state,
) => client.domains.acceptFrame(
  AcpInstallFrame(
    testStamp('acp-install', revision, epoch: 'owner-1'),
    _snapshot(revision, state),
  ),
);
void _emit(
  _InstallTransport transport,
  int revision,
  AcpInstallStateView state,
) => transport.emitAccount(
  AcpInstallFrame(
    testStamp('acp-install', revision, epoch: transport.epoch),
    _snapshot(revision, state),
  ),
);
void main() {
  test(
    'scoped install owner treats revision zero as a real observation',
    () async {
      final transport = _InstallTransport();
      final client = _client(transport);
      final page = client.domains.acp.observeInstall();
      addTearDown(page.release);
      await transport.attachedAccount(const AcpInstallTarget());
      _emit(transport, 0, const AcpInstallIdleState());
      await client.domains.acp.install.waitFor((value) => value.loaded);
      expect(client.domains.acp.install.value.stamp!.revision, 0);
      final snapshot = await client.domains.acp.prepare(
        AcpProviderView.antigravity,
      );
      expect(snapshot.revision, 1);
      final operation = client.board.operations.last;
      expect(operation.target, 'acp-install:antigravity');
      expect(operation.observed, isTrue);
      expect(operation.isPending, isFalse);
      expect(client.budget.used(ResourceKind.pendingOperation), 0);
    },
  );
  test('a matching event before admission still satisfies the same operation receipt', () async {
    final transport = _InstallTransport()..pendingStart = Completer<void>();
    final client = _client(transport);
    _apply(client, 0, const AcpInstallIdleState());
    final pending = client.domains.acp.prepare(AcpProviderView.antigravity);
    await transport.startEntered.future;
    final page = client.domains.acp.observeInstall();
    addTearDown(page.release);
    await transport.attachedAccount(const AcpInstallTarget());
    _emit(
      transport,
      2,
      AcpDownloadingState(
        operationId: transport.lastStart!.value,
        release: _release,
        progress: const AcpInstallProgressView(
          completedBytes: 2048,
          totalBytes: 4096,
        ),
      ),
    );
    await client.domains.acp.install.waitFor(
      (value) => value.stamp?.revision == 2,
    );
    transport.pendingStart!.complete();
    await pending;
    final operation = client.board.operations.last;
    expect(operation.observed, isTrue);
    expect(operation.isPending, isFalse);
    expect(
      client.domains.acp.install.value.value!.stateOf(
        AcpProviderView.antigravity,
      ),
      isA<AcpDownloadingState>(),
    );
    expect(client.domains.acp.install.value.stamp!.revision, 2);
  });
  test('cancel runs on its own lane while start is still pending', () async {
    final transport = _InstallTransport()..pendingStart = Completer<void>();
    final client = _client(transport);
    final starting = client.domains.acp.prepare(AcpProviderView.antigravity);
    await transport.startEntered.future;
    _apply(
      client,
      1,
      AcpResolvingState(operationId: transport.lastStart!.value),
    );
    final cancelled = await client.domains.acp.cancelPreparation(
      AcpProviderView.antigravity,
    );
    expect(transport.cancelCalls, 1);
    expect(transport.lastCancelTarget, transport.lastStart);
    expect(transport.lastCancelProvider, AcpProviderView.antigravity);
    expect(
      cancelled.stateOf(AcpProviderView.antigravity),
      isA<AcpInstallCancellingState>(),
    );
    await starting;
    await expectLater(
      client.domains.acp.prepare(AcpProviderView.antigravity),
      throwsA(
        isA<StudioFailure>().having(
          (e) => e.code,
          'code',
          StudioFailureCode.busy,
        ),
      ),
    );
    _apply(
      client,
      3,
      AcpInstallCancelledState(operationId: transport.lastStart!.value),
    );
    await expectLater(
      client.domains.acp.prepare(AcpProviderView.antigravity),
      completes,
    );
  });
  test('a duplicate start is rejected before touching the transport', () async {
    final transport = _InstallTransport()..pendingStart = Completer<void>();
    final client = _client(transport);
    final first = client.domains.acp.prepare(AcpProviderView.antigravity);
    await transport.startEntered.future;
    await expectLater(
      client.domains.acp.prepare(AcpProviderView.antigravity),
      throwsA(
        isA<StudioFailure>().having(
          (e) => e.code,
          'code',
          StudioFailureCode.busy,
        ),
      ),
    );
    expect(transport.startCalls, 1);
    transport.pendingStart!.complete();
    await first;
  });
  test('leaving a page releases only its own observation, not the accepted download', () async {
    final transport = _InstallTransport();
    final client = _client(transport);
    await client.domains.acp.prepare(AcpProviderView.antigravity);
    final source = await transport.attachedAccount(const AcpInstallTarget());
    _emit(
      transport,
      3,
      AcpDownloadingState(
        operationId: transport.lastStart!.value,
        release: _release,
        progress: const AcpInstallProgressView(
          completedBytes: 10,
          totalBytes: 20,
        ),
      ),
    );
    await client.domains.acp.install.waitFor(
      (value) => value.stamp?.revision == 3,
    );
    final page = client.domains.acp.observeInstall();
    await page.release();
    expect(source.closed, isFalse);
    expect(source.closeCalls, 0);
    expect(transport.cancelCalls, 0);
    expect(
      client.domains.acp.install.value.value!
          .stateOf(AcpProviderView.antigravity)
          .operationId,
      transport.lastStart!.value,
    );
    _emit(
      transport,
      4,
      AcpInstallCancelledState(operationId: transport.lastStart!.value),
    );
    await source.stopped.future;
    expect(source.closeCalls, 1);
  });
  test('a draft intent only accepts its own provider and operation', () {
    final intent = const AcpPreparationIntent(
      provider: AcpProviderView.antigravity,
    );
    final ready = AcpInstallReadyState(
      operationId: 'op-a',
      server: AcpInstalledServerView(
        installationId: 'installation-a',
        release: _release,
        program: '/servers/a/program',
        readyAt: 10,
      ),
    );
    // 没有认领时不能凭“同品牌”自动填入。
    expect(
      intent.resolve(ready, provider: AcpProviderView.antigravity),
      isNull,
    );
    expect(
      intent.availableElsewhere(ready, provider: AcpProviderView.antigravity),
      isNotNull,
    );

    final claimed = intent.claim('op-a');
    expect(
      claimed.resolve(ready, provider: AcpProviderView.antigravity)?.program,
      '/servers/a/program',
    );
    // 其他操作的就绪结果不可回填。
    final other = AcpInstallReadyState(
      operationId: 'op-b',
      server: AcpInstalledServerView(
        installationId: 'installation-b',
        release: _release,
        program: '/servers/b/program',
      ),
    );
    expect(
      claimed.resolve(other, provider: AcpProviderView.antigravity),
      isNull,
    );

    // 换来源推进代次：绑定被清空，旧结果只能显式认领。
    final renewed = claimed.renewed();
    expect(renewed.generation, claimed.generation + 1);
    expect(renewed.operationId, isNull);
    expect(
      renewed.resolve(ready, provider: AcpProviderView.antigravity),
      isNull,
    );
  });
}
