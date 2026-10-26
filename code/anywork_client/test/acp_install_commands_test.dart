import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/acp_port_fixture.dart';

/// 安装是共享资产：同一 provider/宿主目标同时最多一个操作，取消按
/// provider + 目标 operation 去重，且与认证 owner 的水位、通道和关闭过程完全独立。
void main() {
  test(
    'a preparation is accepted under its operation and binds a draft intent',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.install;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      final feed = await establishAcpInstall(fixture);

      final ticket = repository.prepare(AcpProvider.antigravity);
      final call = await fixture.port.installStarted(0);
      expect(call.request.provider, AcpProvider.antigravity);
      expect(call.request.operationId, ticket.id);

      final resolving = acpInstallSnapshot(
        revision: 2,
        state: AcpInstallState.resolving(operationId: ticket.id.value),
      );
      call.accept(
        AcpInstallCommandReply(
          receipt: acpInstallReceipt(ticket.id, revision: 2),
          snapshot: resolving,
        ),
      );
      await feed.publishChanged(resolving, baseRevision: 1);

      final result = await ticket.result;
      expect(result, isA<CommittedCommandResult<AcpInstallSnapshot>>());
      expect(
        (result as CommittedCommandResult<AcpInstallSnapshot>).value
            .stateOf(AcpProvider.antigravity)
            .operationId,
        ticket.id.value,
        reason: 'the acceptance snapshot names the accepted operation',
      );

      final state = repository.state.value.stateOf(AcpProvider.antigravity);
      final intent = AcpPreparationIntent.fresh(
        provider: AcpProvider.antigravity,
      ).claim(ticket.id.value);
      expect(intent.accepts(state, provider: AcpProvider.antigravity), isTrue);
      expect(
        AcpPreparationIntent.fresh(provider: AcpProvider.antigravity)
            .claim('op-foreign')
            .accepts(state, provider: AcpProvider.antigravity),
        isFalse,
        reason: 'another operation never becomes this draft result',
      );
      expect(
        intent.resolve(state, provider: AcpProvider.antigravity),
        isNull,
        reason: 'a resolving operation is not a prepared server',
      );
      expect(repository.state.value.canonical?.revision, 2);
      expect(feed.feed.closeCalls, 0);
    },
  );

  test(
    'an acceptance that names another operation keeps its receipt but no Clean',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.install;
      final feed = await establishAcpInstall(fixture);

      final ticket = repository.prepare(AcpProvider.antigravity);
      final call = await fixture.port.installStarted(0);
      call.accept(
        AcpInstallCommandReply(
          receipt: acpInstallReceipt(ticket.id, revision: 2),
          snapshot: acpInstallSnapshot(
            revision: 2,
            state: const AcpInstallState.resolving(operationId: 'op-foreign'),
          ),
        ),
      );

      final result = await ticket.result;
      expect(result, isA<SyncFailedCommandResult<AcpInstallSnapshot>>());
      final settled = result as SyncFailedCommandResult<AcpInstallSnapshot>;
      expect(settled.receipt.operationId, ticket.id);
      expect(ticket.state.value.receipt, settled.receipt);
      expect(ticket.state.value.observed, isFalse);
      expect(
        repository.state.value.canonical?.revision,
        1,
        reason: 'an unrelated acceptance snapshot is never adopted',
      );

      await feed.listened;
      final closeReport = await repository.close();
      expect(closeReport.complete, isFalse);
      expect(closeReport.unresolved.single.owner, startsWith('acp:action:'));
    },
  );

  test(
    'one provider admits one preparation and releases it on settlement',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.install;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      final feed = await establishAcpInstall(fixture);

      final first = repository.prepare(AcpProvider.antigravity);
      await fixture.port.installStarted(0);

      final second = repository.prepare(AcpProvider.antigravity);
      final secondResult = await second.result;
      expect(secondResult, isA<RejectedCommandResult<AcpInstallSnapshot>>());
      expect(
        (secondResult as RejectedCommandResult<AcpInstallSnapshot>).error.code,
        StudioFailureCode.busy,
      );
      expect(
        fixture.port.installStarts,
        hasLength(1),
        reason: 'a busy provider never starts a second download',
      );

      final resolving = acpInstallSnapshot(
        revision: 2,
        state: AcpInstallState.resolving(operationId: first.id.value),
      );
      await feed.publishChanged(resolving, baseRevision: 1);
      fixture.port.installStarts.single.accept(
        AcpInstallCommandReply(
          receipt: acpInstallReceipt(first.id, revision: 2),
          snapshot: resolving,
        ),
      );
      expect(
        await first.result,
        isA<CommittedCommandResult<AcpInstallSnapshot>>(),
      );
      // The admission release belongs to the same owner settlement.
      await pumpEventQueue();

      final third = repository.prepare(AcpProvider.antigravity);
      final thirdCall = await fixture.port.installStarted(1);
      expect(thirdCall.request.operationId, third.id);

      final nextResolving = acpInstallSnapshot(
        revision: 3,
        state: AcpInstallState.resolving(operationId: third.id.value),
      );
      await feed.publishChanged(nextResolving, baseRevision: 2);
      thirdCall.accept(
        AcpInstallCommandReply(
          receipt: acpInstallReceipt(third.id, revision: 3),
          snapshot: nextResolving,
        ),
      );
      expect(
        await third.result,
        isA<CommittedCommandResult<AcpInstallSnapshot>>(),
      );
    },
  );

  test(
    'a cancellation is de-duplicated per provider and target, not per provider',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.install;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      final feed = await establishAcpInstall(
        fixture,
        state: AcpInstallState.downloading(
          operationId: 'op-install',
          release: acpRelease(),
          progress: const AcpInstallProgress(
            completedBytes: 10,
            totalBytes: 100,
            bytesPerSecond: 4,
          ),
          retryCount: 0,
        ),
      );

      final target = repository.state.value
          .stateOf(AcpProvider.antigravity)
          .operationId;
      expect(target, 'op-install');

      final first = repository.cancel(
        AcpProvider.antigravity,
        targetOperationId: target!,
      );
      final firstCall = await fixture.port.installCancelled(0);
      expect(firstCall.request.provider, AcpProvider.antigravity);
      expect(
        firstCall.request.targetOperationId,
        const OperationId('op-install'),
      );

      final duplicate = repository.cancel(
        AcpProvider.antigravity,
        targetOperationId: target,
      );
      final duplicateResult = await duplicate.result;
      expect(duplicateResult, isA<RejectedCommandResult<AcpInstallSnapshot>>());
      expect(
        (duplicateResult as RejectedCommandResult<AcpInstallSnapshot>)
            .error
            .code,
        StudioFailureCode.busy,
      );
      expect(fixture.port.installCancels, hasLength(1));

      // Another target is a different intent and is admitted in parallel.
      final other = repository.cancel(
        AcpProvider.antigravity,
        targetOperationId: 'op-older',
      );
      final otherCall = await fixture.port.installCancelled(1);
      expect(
        otherCall.request.targetOperationId,
        const OperationId('op-older'),
      );
      expect(other.id, isNot(first.id));

      final cancelling = acpInstallSnapshot(
        revision: 2,
        state: const AcpInstallState.cancelling(operationId: 'op-install'),
      );
      await feed.publishChanged(cancelling, baseRevision: 1);
      firstCall.accept(
        AcpInstallCommandReply(
          receipt: acpInstallReceipt(first.id, revision: 2),
          snapshot: cancelling,
        ),
      );
      expect(
        await first.result,
        isA<CommittedCommandResult<AcpInstallSnapshot>>(),
      );

      final olderCancelling = acpInstallSnapshot(
        revision: 3,
        state: const AcpInstallState.cancelling(operationId: 'op-older'),
      );
      await feed.publishChanged(olderCancelling, baseRevision: 2);
      otherCall.accept(
        AcpInstallCommandReply(
          receipt: acpInstallReceipt(other.id, revision: 3),
          snapshot: olderCancelling,
        ),
      );
      expect(
        await other.result,
        isA<CommittedCommandResult<AcpInstallSnapshot>>(),
      );
    },
  );

  test('authentication cancellation and shutdown never touch the shared installation', () async {
    final fixture = AcpPortFixture();
    addTearDown(() async {
      await fixture.auth.close();
      await fixture.install.close();
    });
    final authFeed = await establishAcpAuth(
      fixture,
      state: const AcpAuthState.checking(operationId: 'op-auth'),
    );
    final installFeed = await establishAcpInstall(
      fixture,
      state: AcpInstallState.downloading(
        operationId: 'op-install',
        release: acpRelease(),
        progress: const AcpInstallProgress(
          completedBytes: 1,
          totalBytes: null,
          bytesPerSecond: null,
        ),
        retryCount: 0,
      ),
    );

    final preparing = fixture.install.prepare(AcpProvider.antigravity);
    final prepareCall = await fixture.port.installStarted(0);

    final cancelling = fixture.auth.cancel(
      accountId: acpTestAccountId,
      targetOperationId: 'op-auth',
    );
    final cancelCall = await fixture.port.authCancelled(0);
    final authCancelling = acpAuthSnapshot(
      revision: 2,
      state: const AcpAuthState.cancelling(operationId: 'op-auth'),
    );
    await authFeed.publishChanged(authCancelling, baseRevision: 1);
    cancelCall.accept(
      AcpAuthCommandReply(
        receipt: acpAuthReceipt(cancelling.id, revision: 2),
        snapshot: authCancelling,
      ),
    );
    expect(
      await cancelling.result,
      isA<CommittedCommandResult<AcpAuthSnapshot>>(),
    );

    expect(
      fixture.port.installCancels,
      isEmpty,
      reason: 'cancelling a login does not cancel a shared installation',
    );
    expect(fixture.install.state.value.canonical?.revision, 1);
    expect(
      fixture.install.state.value.stateOf(AcpProvider.antigravity).operationId,
      'op-install',
      reason: 'the download operation is still the current one',
    );

    // The accepted preparation still completes after the auth cancel.
    final resolving = acpInstallSnapshot(
      revision: 2,
      state: AcpInstallState.resolving(operationId: preparing.id.value),
    );
    await installFeed.publishChanged(resolving, baseRevision: 1);
    prepareCall.accept(
      AcpInstallCommandReply(
        receipt: acpInstallReceipt(preparing.id, revision: 2),
        snapshot: resolving,
      ),
    );
    expect(
      await preparing.result,
      isA<CommittedCommandResult<AcpInstallSnapshot>>(),
    );
    await pumpEventQueue();

    // Closing the authentication owner leaves the installation owner open.
    final authReport = await fixture.auth.close();
    expect(authReport.unresolved, isEmpty);
    expect(
      installFeed.feed.requestCloseCalls,
      0,
      reason: 'the install subscription belongs to another owner',
    );
    expect(
      fixture.install.state.value.projection.sync.phase,
      ResourceSyncPhase.ready,
    );
    final afterAuthClose = fixture.install.prepare(AcpProvider.antigravity);
    final afterCall = await fixture.port.installStarted(1);
    expect(afterCall.request.operationId, afterAuthClose.id);
    expect(
      fixture.install.state.value.stateOf(AcpProvider.antigravity).isBusy,
      isTrue,
    );

    final closing = acpInstallSnapshot(
      revision: 3,
      state: AcpInstallState.closing(
        operationId: afterAuthClose.id.value,
        failure: null,
      ),
    );
    await installFeed.publishChanged(closing, baseRevision: 2);
    afterCall.accept(
      AcpInstallCommandReply(
        receipt: acpInstallReceipt(afterAuthClose.id, revision: 3),
        snapshot: closing,
      ),
    );
    expect(
      await afterAuthClose.result,
      isA<CommittedCommandResult<AcpInstallSnapshot>>(),
    );
  });
}
