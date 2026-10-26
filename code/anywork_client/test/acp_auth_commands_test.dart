import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/acp_port_fixture.dart';

/// 命令回执只能证明受理：被拒绝、结果未知、已确认但观察失败必须是可区分的三类
/// 结果，`closing`／`cancelling` 不是完成。全部用例通过 `OperationTicket` 的公开
/// 结果和 canonical 观察判定，不读取 fake 的内部状态来“自证”。
const _nativeRefusal = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The scripted native boundary declined this check',
  retryable: false,
  correlationId: 'acp-native-refusal',
);

const _lostReply = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The bridge call failed without a typed rejection boundary',
  retryable: true,
  correlationId: 'acp-bridge-call',
);

void main() {
  test(
    'a typed native rejection settles as rejected and is never replayed',
    () async {
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
      final call = await fixture.port.authStarted(0);
      expect(call.request.operationId, ticket.id);
      expect(call.request.accountId, acpTestAccountId);
      expect(
        call.request.expectedConnectionRevision,
        acpTestConnectionRevision,
      );
      expect(call.request.action, const AcpAuthAction.check());

      call.reject(
        const CommandDispatchFailure.rejected(failure: _nativeRefusal),
      );
      final result = await ticket.result;
      expect(result, isA<RejectedCommandResult<AcpAuthSnapshot>>());
      expect(
        (result as RejectedCommandResult<AcpAuthSnapshot>).error,
        _nativeRefusal,
      );
      expect(ticket.state.value.receipt, isNull);
      expect(ticket.state.value.observed, isFalse);
      expect(ticket.state.value.isPending, isFalse);
      expect(
        fixture.port.authStarts,
        hasLength(1),
        reason: 'a rejection is a final answer, not a retry signal',
      );
      expect(
        repository.state.value.canonical?.revision,
        1,
        reason: 'a refused command publishes no canonical fact',
      );
      expect(feed.feed.closeCalls, 0);

      // A missing method id is a local argument error: no operation is created.
      final local = repository.authenticate(
        accountId: acpTestAccountId,
        expectedConnectionRevision: acpTestConnectionRevision,
        methodId: '   ',
      );
      final localResult = await local.result;
      expect(localResult, isA<RejectedCommandResult<AcpAuthSnapshot>>());
      expect(
        (localResult as RejectedCommandResult<AcpAuthSnapshot>).error.code,
        StudioFailureCode.protocol,
      );
      expect(
        fixture.port.authStarts,
        hasLength(1),
        reason: 'local validation never reaches the transport',
      );
    },
  );

  test(
    'a plain call failure is an unknown outcome that is never resent',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, hasLength(1));
        expect(report.unresolved.single.owner, startsWith('acp:action:'));
        expect(
          report.unresolved.single.issues.single.recovery,
          CleanupRecovery.terminal,
        );
      });
      await establishAcpAuth(fixture);

      final ticket = repository.check(
        accountId: acpTestAccountId,
        expectedConnectionRevision: acpTestConnectionRevision,
      );
      final call = await fixture.port.authStarted(0);
      call.fail(_lostReply);

      final result = await ticket.result;
      expect(result, isA<UnknownOutcomeCommandResult<AcpAuthSnapshot>>());
      expect(
        (result as UnknownOutcomeCommandResult<AcpAuthSnapshot>).error,
        _lostReply,
      );
      expect(
        ticket.state.value.isPending,
        isTrue,
        reason: 'an unknown outcome stays protected evidence',
      );
      expect(ticket.state.value.receipt, isNull);
      expect(
        fixture.port.authStarts,
        hasLength(1),
        reason: 'an unknown outcome is never automatically replayed',
      );
    },
  );

  test('a confirmed receipt whose observation fails keeps the receipt and never claims Clean', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    final feed = await establishAcpAuth(fixture);

    final ticket = repository.check(
      accountId: acpTestAccountId,
      expectedConnectionRevision: acpTestConnectionRevision,
    );
    final call = await fixture.port.authStarted(0);
    final receipt = acpAuthReceipt(ticket.id, revision: 2);
    call.accept(
      AcpAuthCommandReply(
        receipt: receipt,
        snapshot: acpAuthSnapshot(
          revision: 2,
          state: AcpAuthState.checking(operationId: ticket.id.value),
        ),
      ),
    );

    // The accepted watermark is never published; the source fails instead.
    await feed.listened;
    feed.sendFailure(
      const StudioFailure(
        code: StudioFailureCode.runtimeStopped,
        message: 'The acpAuth source has closed.',
        retryable: false,
        correlationId: 'acp-auth',
      ),
    );

    final result = await ticket.result;
    expect(result, isA<SyncFailedCommandResult<AcpAuthSnapshot>>());
    final settled = result as SyncFailedCommandResult<AcpAuthSnapshot>;
    expect(settled.receipt.operationId, ticket.id);
    expect(settled.receipt.targets.single, isA<ResourceStamp>());
    expect(ticket.state.value.receipt, receipt);
    expect(
      ticket.state.value.observed,
      isFalse,
      reason: 'a receipt is not its own evidence of observation',
    );
    expect(
      repository.state.value.canonical?.revision,
      1,
      reason: 'the acceptance snapshot is no canonical fact',
    );
    expect(
      repository.state.value.stateOf(
        acpTestAccountId,
        connectionRevision: acpTestConnectionRevision,
      ),
      isA<AcpAuthUnchecked>(),
      reason: 'an unobserved acceptance never becomes a login result',
    );

    final closeReport = await repository.close();
    expect(closeReport.complete, isFalse);
    expect(closeReport.unresolved.single.owner, startsWith('acp:action:'));
    final retried = await repository.retryCleanup(
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    );
    expect(
      retried.complete,
      isFalse,
      reason: 'an unobserved commit cannot be retried into a Clean report',
    );
    expect(retried.unresolved.single.owner, startsWith('acp:action:'));
  });

  test('closing and cancelling are non-terminal observations, not a finished login', () async {
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
    final call = await fixture.port.authStarted(0);
    final closing = acpAuthSnapshot(
      revision: 2,
      state: AcpAuthState.closing(operationId: ticket.id.value, failure: null),
    );
    call.accept(
      AcpAuthCommandReply(
        receipt: acpAuthReceipt(ticket.id, revision: 2),
        snapshot: closing,
      ),
    );
    await feed.publishChanged(closing, baseRevision: 1);

    expect(
      await ticket.result,
      isA<CommittedCommandResult<AcpAuthSnapshot>>(),
      reason: 'the receipt is real even while the process is closing',
    );
    final settling = repository.state.value.stateOf(
      acpTestAccountId,
      connectionRevision: acpTestConnectionRevision,
    );
    expect(settling, isA<AcpAuthClosing>());
    expect(settling.isBusy, isTrue);
    expect(settling.isSettled, isFalse);
    expect(settling, isNot(isA<AcpAuthVerified>()));
    expect(settling.operationId, ticket.id.value);

    final cancelling = acpAuthSnapshot(
      revision: 3,
      state: const AcpAuthState.cancelling(operationId: 'op-current'),
    );
    await feed.publishChanged(cancelling, baseRevision: 2);
    final cancelled = repository.state.value.stateOf(
      acpTestAccountId,
      connectionRevision: acpTestConnectionRevision,
    );
    expect(cancelled, isA<AcpAuthCancelling>());
    expect(cancelled.isBusy, isTrue);
    expect(cancelled.isSettled, isFalse);
    expect(cancelled, isNot(isA<AcpAuthCancelled>()));
    expect(
      repository.state.value.stateOf(
        acpTestAccountId,
        connectionRevision: acpTestConnectionRevision + 1,
      ),
      isA<AcpAuthUnchecked>(),
      reason: 'a connection identity that was never observed stays unchecked',
    );
  });

  test(
    'one account admits one operation at a time and releases it on settlement',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      addTearDown(() async {
        final report = await repository.close();
        expect(report.unresolved, isEmpty);
        expect(fixture.budget.usage, isEmpty);
      });
      final feed = await establishAcpAuth(fixture);

      final first = repository.check(
        accountId: acpTestAccountId,
        expectedConnectionRevision: acpTestConnectionRevision,
      );
      final firstCall = await fixture.port.authStarted(0);

      final second = repository.check(
        accountId: acpTestAccountId,
        expectedConnectionRevision: acpTestConnectionRevision,
      );
      final secondResult = await second.result;
      expect(secondResult, isA<RejectedCommandResult<AcpAuthSnapshot>>());
      expect(
        (secondResult as RejectedCommandResult<AcpAuthSnapshot>).error.code,
        StudioFailureCode.busy,
      );
      expect(
        fixture.port.authStarts,
        hasLength(1),
        reason: 'a duplicate start never creates a second process',
      );

      final firstSnapshot = acpAuthSnapshot(
        revision: 2,
        state: AcpAuthState.checking(operationId: first.id.value),
      );
      firstCall.accept(
        AcpAuthCommandReply(
          receipt: acpAuthReceipt(first.id, revision: 2),
          snapshot: firstSnapshot,
        ),
      );
      await feed.publishChanged(firstSnapshot, baseRevision: 1);
      expect(
        await first.result,
        isA<CommittedCommandResult<AcpAuthSnapshot>>(),
      );

      final third = repository.check(
        accountId: acpTestAccountId,
        expectedConnectionRevision: acpTestConnectionRevision,
      );
      final thirdCall = await fixture.port.authStarted(1);
      expect(thirdCall.request.operationId, third.id);
      final thirdSnapshot = acpAuthSnapshot(
        revision: 3,
        state: AcpAuthState.checking(operationId: third.id.value),
      );
      thirdCall.accept(
        AcpAuthCommandReply(
          receipt: acpAuthReceipt(third.id, revision: 3),
          snapshot: thirdSnapshot,
        ),
      );
      await feed.publishChanged(thirdSnapshot, baseRevision: 2);
      expect(
        await third.result,
        isA<CommittedCommandResult<AcpAuthSnapshot>>(),
      );
    },
  );
}
