import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

final class _ContractTransport extends AccountsTestTransport {
  _ContractTransport() {
    epoch = 'owner-1';
  }
  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async => AcpAuthCommandReply(
    receipt: StudioCommandReceipt(
      operationId: operationId,
      disposition: CommitDisposition.applied,
      targets: [testStamp('acp-auth', 1, epoch: epoch)],
      effect: EffectPoint.immediate,
      effective: true,
      durable: false,
    ),
    snapshot: _snapshot(1, AcpCheckingState(operationId: operationId.value)),
  );
}

const _verifyServer = AcpServerInfoView(name: 'antigravity', version: '1.2.3');
AcpAuthSnapshotView _snapshot(int revision, AcpAuthStateView state) =>
    AcpAuthSnapshotView(
      revision: revision,
      updatedAt: revision,
      accounts: [
        AcpAuthAccountView(
          accountId: 'acp-1',
          connectionRevision: 7,
          state: state,
        ),
      ],
    );
AccountsTestRuntime _client(_ContractTransport transport) {
  final runtime = AccountsTestRuntime(transport, clientId: 'acp-topic');
  runtime.seed(
    SettingsStateSnapshot(
      revision: 1,
      acpAccounts: const [
        AcpAccountSettingsView(
          accountId: 'acp-1',
          name: 'A',
          provider: AcpProviderView.antigravity,
          connectionRevision: 7,
        ),
      ],
    ),
  );
  addTearDown(runtime.close);
  return runtime;
}

void _emit(
  _ContractTransport transport,
  int revision,
  AcpAuthStateView state,
) => transport.emitAccount(
  AcpAuthFrame(
    testStamp('acp-auth', revision, epoch: transport.epoch),
    _snapshot(revision, state),
  ),
);

void main() {
  test(
    'scoped ACP owner consumes baseline and later frames through one reducer',
    () async {
      final transport = _ContractTransport();
      final client = _client(transport);
      expect(
        client.client.channels.activeTopicRefCountViews().containsKey(
          'acpAuth',
        ),
        isFalse,
        reason: 'The old GUI product topic is not a parallel owner',
      );
      final demand = client.domains.acp.observeAuth();
      addTearDown(demand.release);
      final source = await transport.attachedAccount(const AcpAuthTarget());
      _emit(
        transport,
        3,
        const AcpVerifiedState(checkedAt: 30, server: _verifyServer),
      );
      await client.domains.acp.auth.waitFor(
        (value) => value.stamp?.revision == 3,
      );
      expect(
        client.domains.acp.auth.value.value!.stateOf(
          'acp-1',
          connectionRevision: 7,
        ),
        isA<AcpVerifiedState>(),
      );
      _emit(transport, 4, const AcpCheckingState(operationId: 'op-4'));
      await client.domains.acp.auth.waitFor(
        (value) => value.stamp?.revision == 4,
      );
      _emit(transport, 3, const AcpUncheckedState());
      // A newer same-source frame is a deterministic drain barrier for the old
      // frame; it preserves checking rather than accepting its old baseline.
      _emit(transport, 5, const AcpCheckingState(operationId: 'op-4'));
      await client.domains.acp.auth.waitFor(
        (value) => value.stamp?.revision == 5,
      );
      expect(
        client.domains.acp.auth.value.value!.stateOf(
          'acp-1',
          connectionRevision: 7,
        ),
        isA<AcpCheckingState>(),
      );
      expect(client.domains.acp.auth.value.failure, isNull);
      await demand.release();
      await source.stopped.future;
      expect(source.closeCalls, 1);
    },
  );

  test(
    'page observation release cannot release the admitted ACP business owner',
    () async {
      final transport = _ContractTransport();
      final client = _client(transport);
      await client.domains.acp.check(const AcpAccountIdentity('acp-1'));
      final source = await transport.attachedAccount(const AcpAuthTarget());
      final page = client.domains.acp.observeAuth();
      final watched = client.domains.acp.auth.watchLatest((_) {});
      watched.observation.cancel();
      await page.release();
      expect(source.closed, isFalse);
      expect(source.closeCalls, 0);
      _emit(transport, 9, const AcpVerifiedState(checkedAt: 90, server: null));
      await client.domains.acp.auth.waitFor(
        (value) => value.stamp?.revision == 9,
      );
      expect(
        client.domains.acp.auth.value.value!.stateOf(
          'acp-1',
          connectionRevision: 7,
        ),
        isA<AcpVerifiedState>(),
      );
      await source.stopped.future;
      expect(source.closed, isTrue);
      expect(source.closeCalls, 1);
      expect((await client.close()).complete, isTrue);
    },
  );
}
