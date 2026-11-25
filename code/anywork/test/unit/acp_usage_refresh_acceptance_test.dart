import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/accounts_test_runtime.dart';
import '../support/acp_usage_refresh.dart';
import '../support/observed.dart';

const _identity = AcpAccountIdentity('quota-acceptance');
const _usage = AcpUsageObservationView(
  checkedAt: 10,
  state: AcpUsageReadyView(
    groups: [AcpQuotaGroupView(name: 'Synthetic quota', limits: [])],
  ),
);

void main() {
  late _QuotaTransport port;
  late AccountsTestRuntime runtime;
  late AcpService service;

  setUp(() {
    port = _QuotaTransport();
    runtime = AccountsTestRuntime(port);
    runtime.seed(
      SettingsStateSnapshot(
        revision: 1,
        acpAccounts: [
          AcpAccountSettingsView(
            accountId: _identity.accountId,
            name: 'Synthetic quota account',
            template: AcpProviderView.antigravity,
            documentRevision: BigInt.one,
            connectionRevision: 7,
          ),
        ],
      ),
    );
    final initial = AcpAuthFrame(testStamp('acp-auth', 1), port.snapshot(1));
    port.baselines[initial.target] = initial;
    runtime.domains.acceptFrame(initial);
    service = runtime.domains.acp;
  });

  tearDown(() async {
    final report = await runtime.close();
    expect(report.unresolved, isEmpty);
    final transportReport = await port.lifecycleScope.close(
      budget: ClientCloseBudget(const Duration(seconds: 1)),
    );
    expect(transportReport.unresolved, isEmpty);
  });

  Future<AcpUsageRefresh> submit(Future<void> Function() trigger) =>
      AcpUsageRefresh.submit(
        service: service,
        mutations: runtime.board,
        accountId: _identity.accountId,
        connectionRevision: 7,
        trigger: trigger,
      );

  void expectCancelledWithOldUsage() {
    final entry = service.auth.value.value!.account(
      _identity.accountId,
      connectionRevision: 7,
    )!;
    expect(entry.activeOperation, isNull);
    expect(entry.state, isA<AcpVerifiedState>());
    expect(entry.usage, _usage);
    expect(port.cancelTarget, port.queryId);
    expect(runtime.board.operations, hasLength(2));
    expect(runtime.board.operations.first.failurePhase, isNull);
  }

  test(
    'cancel during the button action cannot masquerade as its query',
    () async {
      await expectLater(
        submit(() async {
          await service.queryUsage(_identity);
          await service.cancelAuth(_identity);
        }),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'reason',
            contains('exactly one'),
          ),
        ),
      );
      expectCancelledWithOldUsage();
    },
  );

  test(
    'cancel after admission rejects preserved ready usage while waiting',
    () async {
      final refresh = await submit(() async {
        await service.queryUsage(_identity);
      });
      // waitForReady registers its canonical observation synchronously before
      // this real service cancellation; no timer or guessed pump count is used.
      final rejected = expectLater(
        refresh.waitForReady(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'reason',
            contains('cancelled or replaced'),
          ),
        ),
      );
      await service.cancelAuth(_identity);
      await rejected;
      expectCancelledWithOldUsage();
    },
  );

  test(
    'fast completion accepts same-second unchanged quota without a busy frame',
    () async {
      final refresh = await submit(() async {
        await service.queryUsage(_identity);
        port.emitAccount(
          AcpAuthFrame(testStamp('acp-auth', 3), port.snapshot(3)),
        );
        await untilObserved(
          service.auth,
          (value) => value.value?.revision == 3,
        );
      });
      // The shared acceptance starts observing only after completion. checkedAt
      // and quota equal the baseline, just as a fast real refresh can do.
      expect(await refresh.waitForReady(), _usage.state);
      expect(runtime.board.operations, hasLength(1));
      expect(port.queryId, isNotNull);
    },
  );
}

// Only external command replies/feed frames are scripted. The service, command
// lane, MutationBoard and domain observations are the production implementations.
final class _QuotaTransport extends AccountsTestTransport {
  OperationId? queryId;
  OperationId? cancelTarget;

  AcpAuthSnapshotView snapshot(int revision, {OperationId? active}) =>
      AcpAuthSnapshotView(
        revision: revision,
        updatedAt: 10,
        accounts: [
          AcpAuthAccountView(
            accountId: _identity.accountId,
            connectionRevision: 7,
            connection: const AcpConnectionReadyState(),
            state: const AcpVerifiedState(checkedAt: 10, server: null),
            usage: _usage,
            activeOperation: active == null
                ? null
                : AcpAuthActiveOperationView(
                    operationId: active.value,
                    connectionRevision: 7,
                    action: const AcpQueryUsageActionView(),
                  ),
          ),
        ],
      );

  AcpAuthCommandReply reply(
    OperationId operationId,
    int revision, {
    OperationId? active,
  }) => AcpAuthCommandReply(
    receipt: StudioCommandReceipt(
      operationId: operationId,
      disposition: CommitDisposition.applied,
      targets: [testStamp('acp-auth', revision)],
      effect: EffectPoint.immediate,
      effective: true,
      durable: false,
    ),
    snapshot: snapshot(revision, active: active),
  );

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    expect(accountId, _identity.accountId);
    expect(expectedConnectionRevision, 7);
    expect(action, isA<AcpQueryUsageActionView>());
    queryId = operationId;
    return reply(operationId, 2, active: operationId);
  }

  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) async {
    expect(accountId, _identity.accountId);
    cancelTarget = targetOperationId;
    // The backend intentionally retains both Verified and the previous quota.
    return reply(operationId, 3);
  }
}
