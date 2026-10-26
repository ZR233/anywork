import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/acp_port_fixture.dart';

/// 取消走独立通道：只要 canonical 观察给出当前 operation 身份，即使 start 的受理
/// 仍在等待也能提交；同一接入同一时刻只允许一个在途取消意图，重复取消在到达
/// transport 之前就被拒绝，且不会吞掉第一次的结算。
void main() {
  test('a cancel is admitted and settled while the original start reply is pending', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    addTearDown(() async {
      final report = await repository.close();
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final feed = await establishAcpAuth(fixture);

    final ticket = repository.check(
      accountId: acpTestAccountId,
      expectedConnectionRevision: acpTestConnectionRevision,
    );
    final startCall = await fixture.port.authStarted(0);

    // The native start has not answered yet; the cancel must not queue behind it.
    final cancelling = repository.cancel(
      accountId: acpTestAccountId,
      targetOperationId: ticket.id.value,
    );
    final cancelCall = await fixture.port.authCancelled(0);
    expect(cancelCall.request.accountId, acpTestAccountId);
    expect(cancelCall.request.targetOperationId, ticket.id);
    expect(cancelCall.request.operationId, cancelling.id);
    expect(
      cancelling.id,
      isNot(ticket.id),
      reason: 'a cancel is its own operation, not the cancelled one',
    );
    expect(
      fixture.port.authStarts.single.reply.isCompleted,
      isFalse,
      reason: 'the cancel was admitted without the start reply',
    );

    final target = ticket.id.value;
    final cancellingSnapshot = acpAuthSnapshot(
      revision: 2,
      state: AcpAuthState.cancelling(operationId: target),
    );
    await feed.publishChanged(cancellingSnapshot, baseRevision: 1);
    cancelCall.accept(
      AcpAuthCommandReply(
        receipt: acpAuthReceipt(cancelling.id, revision: 2),
        snapshot: cancellingSnapshot,
      ),
    );
    expect(
      await cancelling.result,
      isA<CommittedCommandResult<AcpAuthSnapshot>>(),
    );
    expect(
      repository.state.value.stateOf(
        acpTestAccountId,
        connectionRevision: acpTestConnectionRevision,
      ),
      isA<AcpAuthCancelling>(),
    );

    // The original start now answers and settles on its own watermark.
    final checkingSnapshot = acpAuthSnapshot(
      revision: 3,
      state: AcpAuthState.checking(operationId: target),
    );
    await feed.publishChanged(checkingSnapshot, baseRevision: 2);
    startCall.accept(
      AcpAuthCommandReply(
        receipt: acpAuthReceipt(ticket.id, revision: 3),
        snapshot: checkingSnapshot,
      ),
    );
    expect(await ticket.result, isA<CommittedCommandResult<AcpAuthSnapshot>>());
    expect(
      fixture.port.authStarts,
      hasLength(1),
      reason: 'cancelling never replaced the accepted start with another one',
    );
    expect(repository.state.value.canonical?.revision, 3);
  });

  test('a duplicate cancel is refused before the transport and keeps the first intent', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    addTearDown(() async {
      final report = await repository.close();
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    final feed = await establishAcpAuth(
      fixture,
      state: const AcpAuthState.checking(operationId: 'op-current'),
    );

    final target = repository.state.value
        .stateOf(
          acpTestAccountId,
          connectionRevision: acpTestConnectionRevision,
        )
        .operationId;
    expect(target, 'op-current');

    final first = repository.cancel(
      accountId: acpTestAccountId,
      targetOperationId: target!,
    );
    final firstCall = await fixture.port.authCancelled(0);

    final duplicate = repository.cancel(
      accountId: acpTestAccountId,
      targetOperationId: target,
    );
    final duplicateResult = await duplicate.result;
    expect(duplicateResult, isA<RejectedCommandResult<AcpAuthSnapshot>>());
    expect(
      (duplicateResult as RejectedCommandResult<AcpAuthSnapshot>).error.code,
      StudioFailureCode.busy,
    );
    expect(
      fixture.port.authCancels,
      hasLength(1),
      reason: 'one in-flight cancel intent per account',
    );
    expect(
      firstCall.reply.isCompleted,
      isFalse,
      reason: 'the duplicate did not replace or finish the original cancel',
    );

    final firstSnapshot = acpAuthSnapshot(
      revision: 2,
      state: const AcpAuthState.cancelling(operationId: 'op-current'),
    );
    await feed.publishChanged(firstSnapshot, baseRevision: 1);
    firstCall.accept(
      AcpAuthCommandReply(
        receipt: acpAuthReceipt(first.id, revision: 2),
        snapshot: firstSnapshot,
      ),
    );
    expect(await first.result, isA<CommittedCommandResult<AcpAuthSnapshot>>());

    // De-duplication is scoped to the in-flight intent: a later operation on
    // the same account is cancellable again.
    final nextSnapshot = acpAuthSnapshot(
      revision: 3,
      state: const AcpAuthState.checking(operationId: 'op-next'),
    );
    await feed.publishChanged(nextSnapshot, baseRevision: 2);
    final next = repository.cancel(
      accountId: acpTestAccountId,
      targetOperationId: 'op-next',
    );
    final nextCall = await fixture.port.authCancelled(1);
    expect(nextCall.request.targetOperationId, const OperationId('op-next'));
    final nextCancelling = acpAuthSnapshot(
      revision: 4,
      state: const AcpAuthState.cancelling(operationId: 'op-next'),
    );
    await feed.publishChanged(nextCancelling, baseRevision: 3);
    nextCall.accept(
      AcpAuthCommandReply(
        receipt: acpAuthReceipt(next.id, revision: 4),
        snapshot: nextCancelling,
      ),
    );
    expect(await next.result, isA<CommittedCommandResult<AcpAuthSnapshot>>());
  });

  test(
    'a cancel without a usable target identity is a local argument error',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      await establishAcpAuth(fixture);

      final ticket = repository.cancel(
        accountId: acpTestAccountId,
        targetOperationId: '  ',
      );
      final result = await ticket.result;
      expect(result, isA<RejectedCommandResult<AcpAuthSnapshot>>());
      expect(
        (result as RejectedCommandResult<AcpAuthSnapshot>).error.code,
        StudioFailureCode.protocol,
      );
      expect(
        fixture.port.authCancels,
        isEmpty,
        reason: 'a local argument error creates no native cancel',
      );
    },
  );
}
