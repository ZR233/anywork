import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:test/test.dart';

import 'support/updates_port_fixture.dart';

/// A retryable native close issue: the original task keeps its owner until a
/// real join proves the cancellation.
const _retryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'updates-native-close',
    code: 'cancelUnconfirmed',
    message: 'The original update task cancellation still needs a native join.',
    retryable: true,
    correlationId: 'update-cancel-join',
  ),
  recovery: CleanupRecovery.retryClose,
);

/// Drives the real domain owner against the scripted native port.
///
/// The old `StudioUpdateClient` is gone. Its request phases and restart intent
/// are now (a) canonical Updates value/brief, (b) operation ticket evidence and
/// (c) composition-layer `UpdateSettingsAction` state in
/// `code/anywork/lib/src/features/settings/updates/view_models/updates_view_model.dart`.
/// The assertions below target the domain facts those layers consume.
final class _UpdatesHarness {
  _UpdatesHarness({ResourceBudget? budget})
    : fixture = UpdatesPortFixture(resourceBudget: budget);

  final UpdatesPortFixture fixture;
  UpdatesRepository get repository => fixture.repository;
  UpdatesLifecycle get lifecycle => fixture.lifecycle;
  ResourceBudget get budget => fixture.budget;
  ScriptedUpdatesPort get port => fixture.port;

  UpdatesNativeFeed? _feed;
  int _valueIndex = 0;
  UpdatesNativeFeed get feed => _feed!;

  /// Starts the canonical feed and materializes [header]'s value through its
  /// own original read scope, exactly as production `loadValue` does.
  Future<void> start(UpdatesHeader header, UpdatesReadHeader read) async {
    final reading = repository.loadValue();
    _feed = (await port.feedOpened(0)).accept();
    await publish(header);
    await readTarget(read);
    await reading;
  }

  Future<void> publish(UpdatesHeader header) =>
      feed.publish(header, projectionRevision: header.reference.revision);

  /// The next original value scope the owner asks for, in its own order.
  Future<UpdatesValuePin> nextPin() async =>
      (await port.valueOpened(_valueIndex++)).accept();

  Future<UpdatesValuePin> readTarget(UpdatesReadHeader read) async {
    final pin = await nextPin();
    await pin.headerCalled.future;
    pin.headerReply.complete(read);
    return pin;
  }

  UpdatesReadTarget target(UpdatesHeader header) =>
      UpdatesReadTarget(origin: feed.origin, reference: header.reference);

  Future<CloseReport> close() => fixture.close();
}

UpdatesBrief? _brief(UpdatesRepository repository) =>
    repository.state.value.projection.header?.brief;

UpdatesValue? _value(UpdatesRepository repository) =>
    switch (repository.state.value.value) {
      ReadyReadValue<UpdatesValue, UpdatesReadRef>(:final current) =>
        current.value,
      _ => null,
    };

/// The old `StudioUpdateInstallResult.readyVersion` is now the acknowledged
/// value; a rejected/unknown dispatch carries no ready version at all.
String? _readyVersion(CommandResult<UpdatePreparationResult> result) =>
    switch (result) {
      CommittedCommandResult<UpdatePreparationResult>(:final value) ||
      AcknowledgedCommandResult<UpdatePreparationResult>(
        :final value,
      ) => value.readyVersion,
      RejectedCommandResult<UpdatePreparationResult>() ||
      UnknownOutcomeCommandResult<UpdatePreparationResult>() ||
      SyncFailedCommandResult<UpdatePreparationResult>() ||
      AcknowledgedSyncFailedCommandResult<UpdatePreparationResult>() => null,
    };

/// A settled operation keeps no command record or native task permit.
///
/// The canonical feed and its original value scopes legitimately hold readModel
/// permits while they are open, so a whole-budget assertion only belongs after
/// the owner has closed.
Future<void> _expectNoOperationOwners(_UpdatesHarness harness) async {
  // The operation settles before its original native task stops joining.
  await pumpEventQueue();
  expect(
    harness.budget.usage.where(
      (usage) => usage.kind == ResourceKind.pendingOperation,
    ),
    isEmpty,
    reason: 'the settled operation released its record permit',
  );
  expect(
    harness.budget.usage.where(
      (usage) => const {
        'updates-prepare',
        'updates-check',
        'updates-automatic',
      }.contains(usage.owner),
    ),
    isEmpty,
    reason: 'the settled native task released its permit',
  );
}

void main() {
  test('a confirmed pre-admission rejection can be retried without leaking an owner', () async {
    final harness = _UpdatesHarness();
    final repository = harness.repository;
    final port = harness.port;
    await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
    final rejected = repository.prepare();
    final open = await port.preparationOpened(0);
    open.reply.completeError(
      const CommandDispatchFailure.rejected(
        failure: StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'Update state changed',
          retryable: false,
          correlationId: 'updates',
        ),
      ),
    );
    final first = await rejected.result;
    expect(
      first,
      isA<RejectedCommandResult<UpdatePreparationResult>>().having(
        (result) => result.error.code,
        'error code',
        StudioFailureCode.conflict,
      ),
    );
    expect(_readyVersion(first), isNull);
    await _expectNoOperationOwners(harness);
    final retry = repository.prepare();
    final retryOpen = await port.preparationOpened(1);
    expect(
      port.preparations,
      hasLength(2),
      reason: 'a confirmed rejection releases the original owner',
    );
    expect(retryOpen.expectedRevision, 1);
    expect(retryOpen.version, updatesTestVersion);
    final task = retryOpen.accept();
    task.startReply.complete();
    await harness.publish(readyUpdateHeader(2));
    task.finishReply.complete(harness.target(readyUpdateHeader(2)));
    await harness.readTarget(readyUpdateRead(2));
    expect(_readyVersion(await retry.result), updatesTestVersion);
    await _expectNoOperationOwners(harness);
    expect((await harness.close()).complete, isTrue);
    expect(harness.budget.usage, isEmpty);
  });

  test(
    'request feedback is immediate, repeated clicks share one preparation',
    () async {
      final harness = _UpdatesHarness();
      final repository = harness.repository;
      final port = harness.port;
      await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
      final ticket = repository.prepare();
      expect(
        ticket.state.value.isPending,
        isTrue,
        reason:
            'the request is pending before any native await; the settings VM '
            'derives its Preparing action from this evidence',
      );
      expect(identical(repository.prepare(), ticket), isTrue);
      final open = await port.preparationOpened(0);
      expect(port.preparations, hasLength(1));
      final task = open.accept();
      task.startReply.complete();
      await harness.publish(readyUpdateHeader(2));
      expect(_brief(repository), isA<ReadyUpdatesBrief>());
      expect(
        ticket.state.value.isPending,
        isTrue,
        reason: 'Ready alone is not a resource completion ACK',
      );
      task.finishReply.complete(harness.target(readyUpdateHeader(2)));
      final pin = await harness.nextPin();
      await pin.headerCalled.future;
      expect(
        ticket.state.value.isPending,
        isTrue,
        reason: 'serving the original value header is not the ACK either',
      );
      pin.headerReply.complete(readyUpdateRead(2));
      expect(_readyVersion(await ticket.result), updatesTestVersion);
      expect(ticket.state.value.acknowledged, isTrue);
      expect(_value(repository), isA<ReadyUpdatesValue>());
      expect((await harness.close()).complete, isTrue);
      expect(harness.budget.usage, isEmpty);
    },
  );

  test('cancel before the native handle arrives cancels its owner and clears the ready intent', () async {
    final harness = _UpdatesHarness();
    final repository = harness.repository;
    final port = harness.port;
    await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
    final prepare = repository.prepare();
    final open = await port.preparationOpened(0);
    final cancel = repository.cancelPreparation();
    expect(cancel.state.value.isPending, isTrue);
    final task = open.accept();
    final cancelled = await cancel.result;
    expect(cancelled, isA<AcknowledgedCommandResult<Unit>>());
    expect(task.calls, ['cancel', 'close']);
    expect(
      task.startCalled.isCompleted,
      isFalse,
      reason: 'the cancelled preparation never issues its start',
    );
    expect(task.closed, isTrue);
    expect(_readyVersion(await prepare.result), isNull);
    await _expectNoOperationOwners(harness);
    expect((await harness.close()).complete, isTrue);
    expect(harness.budget.usage, isEmpty);
  });

  test(
    'cancel racing Ready cannot restart, even when the verified cache survives',
    () async {
      final harness = _UpdatesHarness();
      final repository = harness.repository;
      final port = harness.port;
      await harness.start(readyUpdateHeader(1), readyUpdateRead(1));
      expect(_value(repository), isA<ReadyUpdatesValue>());
      final prepare = repository.prepare();
      final open = await port.preparationOpened(0);
      expect(open.expectedRevision, 1);
      final task = open.accept();
      // Cancel wins the command race while the verified Ready value stays.
      final cancel = repository.cancelPreparation();
      expect(cancel.state.value.isPending, isTrue);
      final cancelled = await cancel.result;
      expect(task.calls, [
        'cancel',
        'close',
      ], reason: 'the late handle is cancelled and joined by its own owner');
      expect(cancelled, isA<AcknowledgedCommandResult<Unit>>());
      final result = await prepare.result;
      expect(result, isA<RejectedCommandResult<UpdatePreparationResult>>());
      expect(
        _readyVersion(result),
        isNull,
        reason:
            'no restart intent is published; the settings VM ownsRestart guard '
            'additionally requires the latest intent to be the preparation',
      );
      expect(
        _value(repository),
        isA<ReadyUpdatesValue>(),
        reason: 'the verified Ready value survives cancellation',
      );
      await _expectNoOperationOwners(harness);
      expect((await harness.close()).complete, isTrue);
      expect(harness.budget.usage, isEmpty);
    },
  );

  test(
    'download failure ends preparation without an exit and releases resources',
    () async {
      final harness = _UpdatesHarness();
      final repository = harness.repository;
      final port = harness.port;
      await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
      final prepare = repository.prepare();
      final open = await port.preparationOpened(0);
      final task = open.accept();
      task.startReply.complete();
      await harness.publish(installFailedUpdateHeader(2));
      task.finishReply.complete(harness.target(installFailedUpdateHeader(2)));
      await harness.readTarget(installFailedUpdateRead(2));
      final result = await prepare.result;
      expect(_readyVersion(result), isNull);
      expect(_brief(repository), isA<InstallFailedUpdatesBrief>());
      final value = _value(repository);
      expect(value, isA<InstallFailedUpdatesValue>());
      expect((value! as InstallFailedUpdatesValue).error.retryable, isTrue);
      await _expectNoOperationOwners(harness);
      expect((await harness.close()).complete, isTrue);
      expect(harness.budget.usage, isEmpty);
    },
  );

  test('manual update joins an existing background download', () async {
    final harness = _UpdatesHarness();
    final repository = harness.repository;
    final port = harness.port;
    await harness.start(downloadingUpdateHeader(1), downloadingUpdateRead(1));
    expect(_value(repository), isA<DownloadingUpdatesValue>());
    final pending = repository.prepare();
    expect(identical(repository.prepare(), pending), isTrue);
    final open = await port.preparationOpened(0);
    expect(
      port.preparations,
      hasLength(1),
      reason: 'an ongoing background download must accept the restart intent',
    );
    expect(open.expectedRevision, 1);
    final task = open.accept();
    task.startReply.complete();
    await harness.publish(readyUpdateHeader(2));
    task.finishReply.complete(harness.target(readyUpdateHeader(2)));
    await harness.readTarget(readyUpdateRead(2));
    expect(_readyVersion(await pending.result), updatesTestVersion);
    await _expectNoOperationOwners(harness);
    expect((await harness.close()).complete, isTrue);
    expect(harness.budget.usage, isEmpty);
  });

  test(
    'close joins a coalesced check failure and releases its RPC budget',
    () async {
      final harness = _UpdatesHarness();
      final repository = harness.repository;
      final port = harness.port;
      final check = repository.check();
      expect(identical(repository.check(), check), isTrue);
      final call = await port.checkOpened(0);
      expect(port.checks, hasLength(1));
      expect(harness.budget.used(ResourceKind.pendingOperation), 1);
      var closeFinished = false;
      final closing = repository.close().then((report) {
        closeFinished = true;
        return report;
      });
      await pumpEventQueue();
      expect(
        closeFinished,
        isFalse,
        reason: 'close joins the admitted check instead of dropping it',
      );
      expect(harness.budget.used(ResourceKind.pendingOperation), 1);
      call.reply.completeError(
        const CommandDispatchFailure.rejected(
          failure: StudioFailure(
            code: StudioFailureCode.unavailable,
            message: 'check rejected',
            retryable: true,
            correlationId: 'updates-test',
          ),
        ),
      );
      expect(await check.result, isA<RejectedCommandResult<Unit>>());
      expect(
        (await closing).complete,
        isTrue,
        reason:
            'a completed business failure leaves no native cleanup obligation',
      );
      expect(harness.budget.used(ResourceKind.pendingOperation), 0);
      expect((await repository.retryCleanup()).complete, isTrue);
      expect(port.checks, hasLength(1), reason: 'cleanup must never replay');
      expect(harness.budget.usage, isEmpty);
    },
  );

  test('a check past the close deadline retains budget until its real terminal reply', () async {
    final harness = _UpdatesHarness();
    final repository = harness.repository;
    final port = harness.port;
    final check = repository.check();
    final call = await port.checkOpened(0);
    final report = await repository.close(deadline: DateTime.utc(2000));
    expect(report.complete, isFalse);
    // The old single-close Future is now one close responsibility: a later
    // caller observes it and cannot extend the original deadline.
    final joined = await repository.close(deadline: DateTime.utc(2099));
    expect(
      joined.unresolved.map((entry) => entry.owner),
      report.unresolved.map((entry) => entry.owner),
      reason: 'a second caller joins the original close responsibility',
    );
    expect(
      report.unresolved.where((entry) => entry.owner == 'updates-check'),
      isNotEmpty,
      reason: 'the old "update-rpc:check" owner is the admitted check task',
    );
    expect(
      harness.budget.usage.map((usage) => usage.owner),
      containsAll(<String>['updates-check', 'updates-test:1']),
    );
    expect(
      harness.budget.usage.map((usage) => usage.phase),
      everyElement(isNot(ResourcePhase.unresolved)),
      reason:
          'a deadline only stops this observation; the admitted check keeps '
          'its real permit until its terminal reply',
    );
    call.reply.completeError(
      const CommandDispatchFailure.rejected(
        failure: StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'late check rejected',
          retryable: true,
          correlationId: 'updates-test',
        ),
      ),
    );
    expect(await check.result, isA<RejectedCommandResult<Unit>>());
    await pumpEventQueue();
    expect(harness.budget.usage, isEmpty);
    expect((await repository.retryCleanup()).complete, isTrue);
    expect(port.checks, hasLength(1));
  });

  test(
    'a check cannot enter transport without a pending-operation permit',
    () async {
      final harness = _UpdatesHarness(
        budget: ResourceBudget(capacities: {ResourceKind.pendingOperation: 0}),
      );
      expect(
        () => harness.repository.check(),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'error code',
            StudioFailureCode.overloaded,
          ),
        ),
      );
      expect(harness.port.checks, isEmpty);
      expect((await harness.repository.close()).complete, isTrue);
      expect(harness.budget.usage, isEmpty);
    },
  );

  test('automatic startup belongs to the owner, is once, and waits for canonical readiness', () async {
    final harness = _UpdatesHarness();
    final port = harness.port;
    expect(
      () => harness.lifecycle.startAutomaticOnce(),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'error code',
          StudioFailureCode.unavailable,
        ),
      ),
      reason: 'no automatic dispatch before a canonical value exists',
    );
    expect(port.automatic, isEmpty);
    await harness.start(readyUpdateHeader(1), readyUpdateRead(1));
    final ticket = harness.lifecycle.startAutomaticOnce();
    expect(identical(harness.lifecycle.startAutomaticOnce(), ticket), isTrue);
    final call = await port.automaticOpened(0);
    expect(
      port.automatic,
      hasLength(1),
      reason: 'startup is once per owner, never per observation',
    );
    expect(call.operationId, ticket.id);
    final task = call.accept();
    task.startReply.complete();
    task.finishReply.complete(harness.target(readyUpdateHeader(1)));
    expect(
      await ticket.result,
      const CommandResult<Unit>.acknowledged(value: Unit()),
    );
    await task.closeCalled.future;
    expect(task.calls.where((call) => call == 'start'), ['start']);
    expect(task.calls.where((call) => call == 'finish'), ['finish']);
    await pumpEventQueue();
    expect(
      task.closed,
      isTrue,
      reason: 'the original owner closes its producer; no shutdown RPC repeats',
    );
    expect(
      identical(harness.lifecycle.startAutomaticOnce(), ticket),
      isTrue,
      reason: 'the once ticket outlives its task; observation never restarts',
    );
    expect(port.automatic, hasLength(1));
    expect((await harness.close()).complete, isTrue);
    expect(harness.budget.usage, isEmpty);
  });

  test('automatic cleanup failure retains its owner until a real cancel ACK', () async {
    final harness = _UpdatesHarness();
    final repository = harness.repository;
    final port = harness.port;
    await harness.start(readyUpdateHeader(1), readyUpdateRead(1));
    final ticket = harness.lifecycle.startAutomaticOnce();
    final call = await port.automaticOpened(0);
    final task = call.accept()
      ..closeReceipt = Completer<UpdateTaskCloseReport>()
      ..retryReceipt = Completer<UpdateTaskCloseReport>();
    task.startReply.complete();
    task.finishReply.complete(harness.target(readyUpdateHeader(1)));
    expect(
      await ticket.result,
      const CommandResult<Unit>.acknowledged(value: Unit()),
    );
    await task.closeCalled.future;
    var closed = false;
    final closing = repository.close().then((report) {
      closed = true;
      return report;
    });
    await pumpEventQueue();
    expect(
      closed,
      isFalse,
      reason: 'an operation result is not the native task close receipt',
    );
    task.closeReceipt!.complete(
      UpdateTaskCloseReport(
        identity: task.identity,
        outcome: FeedCloseOutcome.unresolved(issues: [_retryIssue]),
      ),
    );
    final unresolved = await closing;
    expect(unresolved.complete, isFalse);
    final original = unresolved.unresolved
        .where(
          (resource) =>
              resource.owner == 'updates-automatic' &&
              resource.issues.contains(_retryIssue),
        )
        .single;
    expect(original.issues, [_retryIssue]);
    expect(
      harness.budget.used(ResourceKind.pendingOperation),
      0,
      reason:
          'the cancel RPC ended, while its native producer still owns a permit',
    );
    expect(
      harness.budget.usage.any(
        (usage) =>
            usage.owner == 'updates-automatic' &&
            usage.phase == ResourcePhase.unresolved,
      ),
      isTrue,
    );
    final retry = repository.retryCleanup();
    await Future.any([
      task.retryCalled.future,
      retry.then<void>(
        (_) => throw StateError(
          'cleanup reused the old report without retrying the native task',
        ),
      ),
    ]);
    task.retryReceipt!.complete(
      UpdateTaskCloseReport(
        identity: task.identity,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await retry).complete, isTrue);
    expect(
      port.automatic,
      hasLength(1),
      reason: 'retrying cleanup never repeats startup',
    );
    expect(task.calls.where((call) => call == 'start'), ['start']);
    expect(original.issues, [_retryIssue]);
    expect(harness.budget.usage, isEmpty);
  });

  test(
    'observation ends without dropping the operation or its handoff ACK',
    () async {
      final harness = _UpdatesHarness();
      final repository = harness.repository;
      final port = harness.port;
      await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
      final observer = repository.state.watch((_) {});
      var complete = false;
      final prepare = repository.prepare();
      final result = prepare.result.then((value) {
        complete = true;
        return value;
      });
      final open = await port.preparationOpened(0);
      expect(open.expectedRevision, 1);
      expect(open.version, updatesTestVersion);
      final task = open.accept();
      observer.cancel();
      task.startReply.complete();
      await harness.publish(readyUpdateHeader(2));
      task.finishReply.complete(harness.target(readyUpdateHeader(2)));
      await harness.readTarget(readyUpdateRead(2));
      expect(complete, isFalse);
      expect(
        harness.budget.used(ResourceKind.readModel),
        greaterThan(0),
        reason: 'the live native task keeps its permit without any observer',
      );
      expect(_readyVersion(await result), updatesTestVersion);
      expect(prepare.state.value.acknowledged, isTrue);
      expect(_value(repository), isA<ReadyUpdatesValue>());
      await pumpEventQueue();
      expect(task.calls.where((call) => call == 'close'), hasLength(1));
      expect(task.closed, isTrue);
      expect((await harness.close()).complete, isTrue);
      expect(harness.budget.usage, isEmpty);
    },
  );

  test('late preparation handle is cancelled by its original owner after the close deadline', () async {
    final harness = _UpdatesHarness();
    final repository = harness.repository;
    final port = harness.port;
    await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
    final prepare = repository.prepare();
    final open = await port.preparationOpened(0);
    final deadlineReport = await repository.close(deadline: DateTime.utc(2000));
    expect(deadlineReport.complete, isFalse);
    final joined = await repository.close(deadline: DateTime.utc(2099));
    expect(
      joined.unresolved.map((entry) => entry.owner),
      deadlineReport.unresolved.map((entry) => entry.owner),
      reason: 'a second caller joins the original close responsibility',
    );
    expect(
      deadlineReport.unresolved.where(
        (entry) => entry.owner == 'updates-prepare',
      ),
      isNotEmpty,
    );
    expect(harness.budget.used(ResourceKind.pendingOperation), 1);
    final task = open.accept();
    final result = await prepare.result;
    expect(result, isA<RejectedCommandResult<UpdatePreparationResult>>());
    expect(_readyVersion(result), isNull);
    expect(task.calls, ['cancel', 'close']);
    expect(task.startCalled.isCompleted, isFalse);
    await pumpEventQueue();
    expect(harness.budget.used(ResourceKind.pendingOperation), 0);
    await _expectNoOperationOwners(harness);
    expect(
      (await repository.retryCleanup()).complete,
      isTrue,
      reason: 'the original owner cancelled its late handle, so cleanup joins',
    );
    expect(harness.budget.usage, isEmpty);
  });

  test('a failed handoff keeps the strong handle and budget until cleanup is confirmed', () async {
    final harness = _UpdatesHarness();
    final repository = harness.repository;
    final port = harness.port;
    await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
    final prepare = repository.prepare();
    final open = await port.preparationOpened(0);
    final task = open.accept();
    task.startReply.complete();
    task.finishReply.completeError(StateError('native handoff failed'));
    final result = await prepare.result;
    expect(
      result,
      isA<UnknownOutcomeCommandResult<UpdatePreparationResult>>(),
      reason: 'a lost native finish reply never proves the handle was clean',
    );
    final report = await repository.close();
    expect(report.complete, isFalse);
    final original = report.unresolved
        .where((resource) => resource.owner == 'updates-prepare')
        .single;
    expect(
      original.issues.map((issue) => issue.recovery),
      contains(CleanupRecovery.terminal),
      reason: 'the old "update:1" owner keeps a terminal issue, never disposed',
    );
    expect(
      harness.budget.usage.map((usage) => usage.owner),
      containsAll(<String>['updates-test:1', 'updates-prepare']),
    );
    expect(
      harness.budget.usage
          .where(
            (usage) =>
                usage.owner == 'updates-test:1' ||
                usage.owner == 'updates-prepare',
          )
          .map((usage) => usage.phase),
      everyElement(ResourcePhase.unresolved),
    );
    final retry = await repository.retryCleanup();
    expect(
      retry.complete,
      isFalse,
      reason: 'a terminal finish failure is never resolved by replaying close',
    );
    expect(
      retry.unresolved.where((entry) => entry.owner == 'updates-prepare'),
      isNotEmpty,
    );
  });

  test(
    'an unknown preparation reply is retained and never automatically replayed',
    () async {
      final harness = _UpdatesHarness();
      final repository = harness.repository;
      final port = harness.port;
      await harness.start(availableUpdateHeader(1), availableUpdateRead(1));
      final prepare = repository.prepare();
      final open = await port.preparationOpened(0);
      open.reply.completeError(StateError('reply lost'));
      expect(
        await prepare.result,
        isA<UnknownOutcomeCommandResult<UpdatePreparationResult>>(),
      );
      await pumpEventQueue();
      expect(
        () => repository.prepare(),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'error code',
            StudioFailureCode.conflict,
          ),
        ),
      );
      expect(
        port.preparations,
        hasLength(1),
        reason: 'an unknown reply is never automatically replayed',
      );
      expect(harness.budget.used(ResourceKind.pendingOperation), 1);
      expect((await repository.close()).complete, isFalse);
    },
  );
}
