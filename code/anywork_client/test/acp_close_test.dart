import 'dart:async';

import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/acp_port_fixture.dart';

/// 关闭语义：`seal()` 只封闭准入，`close()` 才 join 在途命令与订阅；清理失败如实
/// 保留 unresolved（不伪造 Clean），`retryCleanup()` 重试原始 native close 而不是
/// 重放业务命令。
const _closingRefusal = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The scripted native operation was cancelled by the owner seal',
  retryable: false,
  correlationId: 'acp-close-refusal',
);

const _retryableCloseIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'acp-native-close',
    code: 'cancelUnconfirmed',
    message: 'The original acpAuth feed close still needs a native join.',
    retryable: true,
    correlationId: 'acp-close',
  ),
  recovery: CleanupRecovery.retryClose,
);

void main() {
  test('seal refuses new commands, subscriptions and reads locally', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    addTearDown(() async {
      final report = await repository.close();
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    await establishAcpAuth(fixture);

    repository.seal();

    // A sealed owner refuses admission synchronously: no ticket, no native call.
    expect(
      () => repository.check(
        accountId: acpTestAccountId,
        expectedConnectionRevision: acpTestConnectionRevision,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    expect(
      fixture.port.authStarts,
      isEmpty,
      reason: 'a sealed owner never reaches the transport',
    );

    expect(
      () => repository.synchronize(),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    expect(
      () => repository.observe(),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    expect(
      () => repository.readCanonical(),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    expect(
      fixture.port.authReads,
      isEmpty,
      reason: 'a sealed owner issues no bounded read',
    );
  });

  test('close joins the in-flight command and reports it until the original reply arrives', () async {
    final fixture = AcpPortFixture();
    final repository = fixture.auth;
    final feed = await establishAcpAuth(fixture);

    final ticket = repository.check(
      accountId: acpTestAccountId,
      expectedConnectionRevision: acpTestConnectionRevision,
    );
    final call = await fixture.port.authStarted(0);

    // A deadline bounds only this observation of cleanup, never the join.
    final bounded = await repository.close(deadline: DateTime.now());
    expect(bounded.complete, isFalse);
    final pending = bounded.unresolved
        .where((resource) => resource.owner.startsWith('acp:action:'))
        .toList();
    expect(pending, isNotEmpty);
    expect(
      pending
          .expand((resource) => resource.issues)
          .map((issue) => issue.diagnostic.code),
      containsAll(<String>['acpActionPending', 'workPending']),
      reason: 'the accepted command is still joined, not dropped',
    );
    expect(
      pending
          .expand((resource) => resource.issues)
          .where((issue) => issue.diagnostic.code == 'acpActionPending')
          .single
          .recovery,
      CleanupRecovery.awaitCompletion,
    );
    expect(
      ticket.state.value.receipt,
      isNull,
      reason: 'a pending native start has no receipt yet',
    );
    expect(
      feed.feed.closeCalls,
      1,
      reason: 'the subscription close is independent of the command join',
    );

    // The original native answer arrives after the seal and settles its own
    // ticket; the command is never replayed on the closed owner.
    call.reject(
      const CommandDispatchFailure.rejected(failure: _closingRefusal),
    );
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<AcpAuthSnapshot>>());
    expect(
      (result as RejectedCommandResult<AcpAuthSnapshot>).error,
      _closingRefusal,
    );
    expect(fixture.port.authStarts, hasLength(1));

    final retried = await repository.retryCleanup(
      deadline: DateTime.now().add(const Duration(seconds: 1)),
    );
    expect(retried.complete, isTrue);
    expect(
      repository.state.value.projection.sync.phase,
      ResourceSyncPhase.closed,
      reason: 'the canonical source is closed only after a real Clean report',
    );
    expect(fixture.budget.usage, isEmpty);
  });

  test(
    'a failed native close is reported unresolved and retried by retryCleanup',
    () async {
      final fixture = AcpPortFixture();
      final repository = fixture.auth;
      final feed = await establishAcpAuth(fixture);
      final nativeClose = Completer<FeedCloseReport>();
      feed.feed.closeReceipt = nativeClose;

      final closing = repository.close();
      await feed.feed.closeStarted.future;
      nativeClose.complete(
        FeedCloseReport(
          feedId: feed.feed.feedId,
          outcome: FeedCloseOutcome.unresolved(issues: [_retryableCloseIssue]),
        ),
      );

      final unresolved = await closing;
      expect(unresolved.complete, isFalse);
      final owner = unresolved.unresolved.singleWhere(
        (resource) => resource.owner == 'acp-auth:feed',
      );
      expect(owner.issues, contains(_retryableCloseIssue));
      expect(
        repository.state.value.projection.sync.phase,
        isNot(ResourceSyncPhase.closed),
        reason: 'an unresolved close never publishes a closed source',
      );
      expect(
        fixture.budget.usage.any(
          (usage) =>
              usage.owner == 'acp-auth:feed' &&
              usage.phase == ResourcePhase.unresolved,
        ),
        isTrue,
      );

      // The retry joins the same native connection and only then reports Clean.
      final retryReceipt = Completer<FeedCloseReport>();
      feed.feed.closeReceipt = retryReceipt;
      final retrying = repository.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      await pumpEventQueue();
      expect(
        feed.feed.retryCloseCalls,
        1,
        reason: 'cleanup retries the original native close, not the command',
      );
      retryReceipt.complete(
        FeedCloseReport(
          feedId: feed.feed.feedId,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );

      final retried = await retrying;
      expect(retried.complete, isTrue);
      expect(
        repository.state.value.projection.sync.phase,
        ResourceSyncPhase.closed,
      );
      expect(fixture.budget.usage, isEmpty);
    },
  );

  test('the two owners close on their own channels and reports', () async {
    final fixture = AcpPortFixture();
    final authFeed = await establishAcpAuth(fixture);
    final installFeed = await establishAcpInstall(fixture);
    final installClose = Completer<FeedCloseReport>();
    installFeed.feed.closeReceipt = installClose;

    final authReport = await fixture.auth.close();
    expect(authReport.complete, isTrue);
    expect(authFeed.feed.closeCalls, 1);
    expect(
      installFeed.feed.closeCalls,
      0,
      reason: 'closing one owner never closes the other subscription',
    );

    final closing = fixture.install.close();
    await installFeed.feed.closeStarted.future;
    installClose.complete(
      FeedCloseReport(
        feedId: installFeed.feed.feedId,
        outcome: FeedCloseOutcome.unresolved(issues: [_retryableCloseIssue]),
      ),
    );
    final installReport = await closing;
    expect(installReport.complete, isFalse);
    expect(installReport.unresolved.single.owner, 'acp-install:feed');
    expect(
      fixture.auth.state.value.projection.sync.phase,
      ResourceSyncPhase.closed,
      reason: 'the auth report is not affected by the install failure',
    );

    final retryReceipt = Completer<FeedCloseReport>();
    installFeed.feed.closeReceipt = retryReceipt;
    final retrying = fixture.install.retryCleanup(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
    await pumpEventQueue();
    retryReceipt.complete(
      FeedCloseReport(
        feedId: installFeed.feed.feedId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await retrying).complete, isTrue);
    expect(fixture.budget.usage, isEmpty);
  });
}
