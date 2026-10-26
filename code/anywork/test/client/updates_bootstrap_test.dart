import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../anywork_client/test/support/startup_port_fixture.dart';
import '../../../anywork_client/test/support/timeline_transport.dart';
import '../../../anywork_client/test/support/updates_port_fixture.dart';
import 'support/bootstrap_workspace_fixture.dart';
import 'support/updates_bootstrap_fixture.dart';

void main() {
  test('RuntimeReady starts the observed full-value gate and neither an old ref nor an old origin can dispatch automatic work', () async {
    final harness = UpdatesBootstrapFixture();
    final updates = harness.updates;
    final initial = updates.repository.state.value;
    expect(
      (initial.projection.stamp, initial.projection.header, initial.value),
      (null, null, null),
    );
    expect(
      updates.port.feeds,
      isEmpty,
      reason: 'Repository construction is not native subscription admission',
    );
    expect(harness.startupPort.initializeCalls, 0);
    final admitted = <UpdatesReadTarget>[];
    updates.port.openingFeed = () =>
        expect(updates.repository.state.observerCount, greaterThan(0));
    updates.port.openingAutomatic = () {
      final state = updates.repository.state.value;
      final current =
          (state.value as ReadyReadValue<UpdatesValue, UpdatesReadRef>).current;
      admitted.add(
        UpdatesReadTarget(origin: current.origin, reference: current.reference),
      );
    };
    final starting = harness.bootstrap.start();
    expect(harness.bootstrap.start(), same(starting));
    final runtimeTicket = harness.startup.start();
    await harness.startupPort.runtimeCalled.future;
    expect(
      updates.port.feeds,
      isEmpty,
      reason: 'A native startup attempt is not yet RuntimeReady',
    );
    await harness.startupPort.completeReady();
    final runtimeResult = await runtimeTicket.result;
    final feed = (await beforeCompletion(
      updates.port.feedOpened(0),
      starting,
      'Bootstrap completed before its gate',
    )).accept();
    await feed.publish(availableUpdateHeader(1), projectionRevision: 1);
    final oldRef = await beforeCompletion(
      updates.port.valueOpened(0),
      starting,
      'Header alone must not pass the gate',
    );
    final oldRefPin = oldRef.accept();
    await beforeCompletion(
      oldRefPin.headerCalled.future,
      starting,
      'The full original value must actually be read',
    );
    expect(
      updates.repository.state.value.projection.sync.phase,
      ResourceSyncPhase.ready,
    );
    expect(
      updates.repository.state.value.value,
      isA<LoadingReadValue<UpdatesValue, UpdatesReadRef>>(),
    );
    expect(updates.port.automatic, isEmpty);

    await feed.publish(availableUpdateHeader(2), projectionRevision: 2);
    oldRefPin.headerReply.complete(availableUpdateRead(1));
    final oldOrigin = await beforeCompletion(
      updates.port.valueOpened(1),
      starting,
      'The old ref may not authorize the new header',
    );
    expect(
      oldOrigin.target,
      UpdatesReadTarget(
        origin: updatesTestOrigin,
        reference: availableUpdateHeader(2).reference,
      ),
    );
    final oldOriginPin = oldOrigin.accept();
    await beforeCompletion(
      oldOriginPin.headerCalled.future,
      starting,
      'The replacement ref needs its own value',
    );
    expect(updates.port.automatic, isEmpty);

    feed.replaceOwner();
    final nextFeed =
        (await beforeCompletion(
          updates.port.feedOpened(1),
          starting,
          'Old origin replacement is still a gate',
        )).accept(
          origin: const ProductReadOrigin(
            ownerEpoch: 'updates-native',
            incarnation: 2,
          ),
        );
    await nextFeed.publish(availableUpdateHeader(2), projectionRevision: 1);
    oldOriginPin.headerReply.complete(availableUpdateRead(2));
    final current = await beforeCompletion(
      updates.port.valueOpened(2),
      starting,
      'Same ref in another origin must not borrow the old value',
    );
    final currentTarget = UpdatesReadTarget(
      origin: nextFeed.origin,
      reference: availableUpdateHeader(2).reference,
    );
    expect(current.target, currentTarget);
    expect(updates.port.automatic, isEmpty);
    final currentPin = current.accept();
    await beforeCompletion(
      currentPin.headerCalled.future,
      starting,
      'Only the current full value passes',
    );
    currentPin.headerReply.complete(availableUpdateRead(2));
    expect(await starting, same(runtimeResult));
    final taskOpen = await updates.port.automaticOpened(0);
    final task = taskOpen.accept();
    await Future.wait([task.finishCalled.future, task.startCalled.future]);
    expect(task.calls.take(2), ['finish', 'start']);
    expect(task.identity.operationId, harness.tickets.single.id);
    expect(admitted, [currentTarget]);
    task.startReply.complete();
    task.finishReply.complete(currentTarget);
    expect(
      await harness.tickets.single.result,
      const CommandResult<Unit>.acknowledged(value: Unit()),
    );
    expect(await harness.bootstrap.start(), same(runtimeResult));
    expect(harness.attachments, [ScriptedStartupPort.ready]);
    expect(harness.startupPort.attempts, [41]);
    expect(updates.port.automatic, hasLength(1));
  });

  test('explicit Bootstrap retries subscription, source and materialization failures using the original RuntimeReady without automatic recovery', () async {
    final budget = ResourceBudget(
      capacities: {
        ResourceKind.observer: 3,
        ResourceKind.readModel: 256,
        ResourceKind.pendingOperation: 64,
      },
    );
    final held = [
      for (var index = 0; index < 2; index++)
        budget.acquire(ResourceKind.observer, owner: 'test-held-$index'),
    ];
    addTearDown(() {
      for (final permit in held) {
        permit.release();
      }
    });
    final harness = UpdatesBootstrapFixture(resourceBudget: budget);
    final updates = harness.updates;
    harness.startupPort.progress.closeReceipt = Completer<FeedCloseReport>();
    final first = harness.bootstrap.start();
    final firstFailure = typedFailure(first);
    final runtimeTicket = harness.startup.start();
    await harness.startupPort.completeReady();
    final original = await runtimeTicket.result;
    final subscriptionFailure = await Future.any([
      firstFailure,
      updates.port
          .feedOpened(0)
          .then<StudioFailure>(
            (_) => throw StateError(
              'Read admission preceded the Updates observer whose budget must reject this gate',
            ),
          ),
    ]);
    expect(subscriptionFailure.code, StudioFailureCode.overloaded);
    expect(
      subscriptionFailure.details,
      const StudioFailureDetails.resourceLimit(
        resource: 'observer',
        capacity: 3,
      ),
    );
    expect(
      updates.port.feeds,
      isEmpty,
      reason:
          'Subscription failure must precede the read that could open a feed',
    );
    expect(updates.port.automatic, isEmpty);
    expect(harness.attachments, [ScriptedStartupPort.ready]);

    final released = Completer<void>();
    final availability = budget.watchAvailability(ResourceKind.observer, () {
      if (budget.used(ResourceKind.observer) == 0 && !released.isCompleted) {
        released.complete();
      }
    });
    addTearDown(availability.cancel);
    for (final permit in held) {
      permit.release();
    }
    await harness.startupPort.progress.closeStarted.future;
    harness.startupPort.progress.closeReceipt!.complete(
      FeedCloseReport(
        feedId: harness.startupPort.progress.feedId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    await released.future;
    availability.cancel();
    expect(
      updates.port.feeds,
      isEmpty,
      reason: 'Freeing capacity is not an implicit Bootstrap retry',
    );

    final second = harness.bootstrap.start();
    expect(second, isNot(same(first)));
    expect(harness.bootstrap.start(), same(second));
    final source = (await beforeCompletion(
      updates.port.feedOpened(0),
      second,
      'Explicit attach retry must restart the gate',
    )).accept();
    await source.publish(availableUpdateHeader(1), projectionRevision: 1);
    final originalOpen = await beforeCompletion(
      updates.port.valueOpened(0),
      second,
      'The source failure must interrupt an entered read',
    );
    final originalPin = originalOpen.accept();
    await originalPin.headerCalled.future;
    const sourceFailure = StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'The native Updates subscription failed.',
      retryable: true,
      correlationId: 'updates-source-failed',
    );
    final failedSource = updates.repository.state.waitFor(
      (state) => state.projection.sync.phase == ResourceSyncPhase.failed,
    );
    source.fail(sourceFailure);
    await failedSource;
    expect(
      updates.repository.state.value.projection.sync.error,
      same(sourceFailure),
    );
    expect(updates.port.automatic, isEmpty);

    // An independent pure Repository read may recover canonical state while
    // Bootstrap's original native read still owns its reply. It cannot retry
    // that failed gate or erase the failure which the gate already observed.
    final recovery = updates.repository.loadValue();
    final recovered = (await beforeCompletion(
      updates.port.feedOpened(1),
      second,
      'The failed gate still owns its original read',
    )).accept();
    await recovered.publish(idleUpdateHeader(2), projectionRevision: 1);
    await recovery;
    expect(
      updates.repository.state.value.value,
      isA<ReadyReadValue<UpdatesValue, UpdatesReadRef>>(),
    );
    expect(updates.port.automatic, isEmpty);
    expect(harness.attachments, hasLength(2));
    originalPin.headerReply.complete(availableUpdateRead(1));
    expect(
      await typedFailure(second),
      same(sourceFailure),
      reason: 'Later canonical Ready cannot erase the original gate failure after its read finally joins',
    );

    await recovered.publish(availableUpdateHeader(3), projectionRevision: 2);
    final third = harness.bootstrap.start();
    final valueOpen = await beforeCompletion(
      updates.port.valueOpened(1),
      third,
      'The recovered source still needs its full value',
    );
    final pin = valueOpen.accept();
    await pin.headerCalled.future;
    const readFailure = StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'The original update value failed.',
      retryable: true,
      correlationId: 'updates-value-failed',
    );
    pin.headerReply.completeError(readFailure);
    expect(await typedFailure(third), same(readFailure));
    expect(
      (updates.repository.state.value.value
              as FailedReadValue<UpdatesValue, UpdatesReadRef>)
          .error,
      same(readFailure),
    );
    expect(harness.attachments, [
      ScriptedStartupPort.ready,
      ScriptedStartupPort.ready,
      ScriptedStartupPort.ready,
    ]);
    await recovered.publish(idleUpdateHeader(4), projectionRevision: 3);
    expect(
      updates.repository.state.value.value,
      isA<ReadyReadValue<UpdatesValue, UpdatesReadRef>>(),
    );
    expect(
      updates.port.automatic,
      isEmpty,
      reason: 'A canonical Ready notification cannot retry a failed gate',
    );
    expect(harness.attachments, hasLength(3));

    final retry = harness.bootstrap.start();
    expect(await retry, same(original));
    expect(harness.attachments, [
      for (var index = 0; index < 4; index++) ScriptedStartupPort.ready,
    ]);
    final call = await updates.port.automaticOpened(0);
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: updatesTestCancelled),
    );
    expect(
      await harness.tickets.single.result,
      const CommandResult<Unit>.rejected(error: updatesTestCancelled),
    );
    expect(await harness.bootstrap.start(), same(original));
    expect(harness.startupPort.initializeCalls, 1);
    expect(harness.startupPort.prepareCalls, 1);
    expect(harness.startupPort.progressCalls, 1);
    expect(harness.startupPort.attempts, [41]);
    expect(updates.port.feeds, hasLength(2));
    expect(updates.port.automatic, hasLength(1));
  });

  test('real Workspace binding rolls back failed registration, survives attach read retry once and seals only its own forwarding', () async {
    final budget = ResourceBudget(
      capacities: {...ResourceBudget().capacities, ResourceKind.observer: 32},
    );
    final harness = UpdatesBootstrapFixture(
      resourceBudget: budget,
      withWorkspaceBinding: true,
    );
    final components = harness.selection!;
    final workspace = components.workspace;
    final updates = harness.updates;
    expect([
      components.port.projects,
      components.port.threads,
      components.port.restores,
    ], everyElement(isEmpty));
    expect(workspace.state.observerCount, 0);
    expect(components.demand.calls, isEmpty);
    harness.startupPort.progress.closeReceipt = Completer<FeedCloseReport>();
    final runtime = harness.startup.start();
    await harness.startupPort.runtimeCalled.future;
    expect(
      workspace.state.observerCount,
      0,
      reason: 'Native startup admission does not attach selection',
    );
    await harness.startupPort.completeReady();
    final originalReady = await runtime.result;
    final restoreA = workspace.restoreThread('A');
    (await components.port.restoreOpened(0)).reply.complete(fixtureThread('A'));
    expect(
      await restoreA.result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    final originalSelection = workspace.state.value;
    expect(originalSelection.selection.threadId, 'A');
    final originalOpen = await components.port.firstThreadOpen.future;
    await components.port.firstProjectOpen.future;
    await harness.startupPort.progress.closeStarted.future;
    // Real public observer-budget failure, not a throwing spy or production hook.
    final remaining =
        budget.capacities[ResourceKind.observer]! -
        budget.used(ResourceKind.observer);
    final held = [
      for (var index = 0; index < remaining; index++)
        budget.acquire(
          ResourceKind.observer,
          owner: 'binding-registration-pressure-$index',
        ),
    ];
    addTearDown(() {
      for (final permit in held) {
        permit.release();
      }
    });
    final first = harness.bootstrap.start();
    final registrationError = await typedFailure(first);
    expect(registrationError.code, StudioFailureCode.overloaded);
    expect(
      registrationError.details,
      const StudioFailureDetails.resourceLimit(
        resource: 'observer',
        capacity: 32,
      ),
    );
    expect(workspace.state.observerCount, 0);
    expect(components.demand.calls, isEmpty);
    expect(
      updates.port.feeds,
      isEmpty,
      reason: 'Selection registration precedes the automatic gate',
    );
    for (final permit in held) {
      permit.release();
    }
    harness.startupPort.progress.closeReceipt!.complete(
      FeedCloseReport(
        feedId: harness.startupPort.progress.feedId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );

    final second = harness.bootstrap.start();
    expect(harness.bootstrap.start(), same(second));
    final feed = (await beforeCompletion(
      updates.port.feedOpened(0),
      second,
      'Explicit retry must attach the real binding',
    )).accept();
    expect(components.demand.calls, [selectionDelivery(originalSelection)]);
    expect(components.demand.observerCounts, [
      1,
    ], reason: 'The real observer is installed before forwarding current');
    expect(workspace.state.observerCount, 1);
    final sessionA = components.conversation.active.value!;
    expect(sessionA.threadId, 'A');
    final firstMetrics = await components.facets.metricsOpened(0);
    await firstMetrics.feed.listened.future;
    expect(firstMetrics.threadId, 'A');
    final timelineA = await components.timeline.opened(0);
    expect(timelineA.threadId, 'A');
    final nativeTimelineA = TestTimelineConnection(initial: baseline(1));
    timelineA.result.complete(nativeTimelineA);
    await feed.publish(availableUpdateHeader(1), projectionRevision: 1);
    final value = (await beforeCompletion(
      updates.port.valueOpened(0),
      second,
      'The attach read must actually enter',
    )).accept();
    await value.headerCalled.future;
    const readFailure = StudioFailure(
      code: StudioFailureCode.unavailable,
      message: 'The original attach value failed.',
      retryable: true,
      correlationId: 'binding-attach-value',
    );
    value.headerReply.completeError(readFailure);
    expect(await typedFailure(second), same(readFailure));
    expect(
      workspace.state.observerCount,
      1,
      reason: 'Later attach failure retains the one successful binding',
    );

    final beforeChange = components.demand.calls.length;
    final restoreB = workspace.restoreThread('B');
    (await components.port.restoreOpened(1)).reply.complete(fixtureThread('B'));
    final restoredB = await restoreB.result;
    expect(
      restoredB,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    final selectedB = workspace.state.value;
    expect(selectedB.selection.threadId, 'B');
    expect(components.demand.calls.skip(beforeChange), hasLength(1));
    expect(
      selectedB.selectionGeneration,
      (restoredB as AcknowledgedCommandResult<WorkspaceSelectionResult>)
          .value
          .intent
          .generation,
    );
    expect(
      selectedB.selectionGeneration,
      greaterThan(originalSelection.selectionGeneration),
    );
    expect(components.demand.calls.skip(beforeChange), [
      selectionDelivery(selectedB),
    ]);
    final sessionB = components.conversation.active.value!;
    expect(sessionB.threadId, 'B');
    expect(sessionB, isNot(same(sessionA)));
    await nativeTimelineA.closeCompleted.future;
    final beforeRetry = components.demand.calls.length;
    await feed.publish(idleUpdateHeader(2), projectionRevision: 2);
    expect(
      updates.port.automatic,
      isEmpty,
      reason: 'Canonical recovery cannot retry the failed attach',
    );
    final retry = harness.bootstrap.start();
    expect(harness.bootstrap.start(), same(retry));
    expect(await retry, same(originalReady));
    expect(
      components.demand.calls,
      hasLength(beforeRetry),
      reason:
          'Successful binding does not forward current again on attach retry',
    );
    expect(
      components.demand.observerCounts.every((count) => count == 1),
      isTrue,
    );
    expect(workspace.state.observerCount, 1);
    expect(components.conversation.active.value, same(sessionB));
    final automatic = await updates.port.automaticOpened(0);
    automatic.reply.completeError(
      const CommandDispatchFailure.rejected(failure: updatesTestCancelled),
    );
    expect(
      await harness.tickets.single.result,
      const CommandResult<Unit>.rejected(error: updatesTestCancelled),
    );
    expect(await harness.bootstrap.start(), same(originalReady));
    expect(harness.attachments, [
      for (var index = 0; index < 3; index++) ScriptedStartupPort.ready,
    ]);
    expect(
      (
        harness.startupPort.initializeCalls,
        harness.startupPort.prepareCalls,
        harness.startupPort.progressCalls,
      ),
      (1, 1, 1),
    );
    expect(harness.startupPort.attempts, [41]);
    expect(updates.port.automatic, hasLength(1));

    sessionB.timeline.attachConsumer((_) {});
    final lateTimeline = await components.timeline.opened(1);
    expect(lateTimeline.threadId, 'B');
    components.binding.seal();
    expect((await components.binding.close()).complete, isTrue);
    expect(workspace.state.observerCount, 0);
    await expectLater(
      Future<void>.sync(components.binding.start),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    final sealedCalls = components.demand.calls.length;
    final restoreC = workspace.restoreThread('C');
    (await components.port.restoreOpened(2)).reply.complete(fixtureThread('C'));
    expect(
      await restoreC.result,
      isA<AcknowledgedCommandResult<WorkspaceSelectionResult>>(),
    );
    expect(workspace.state.value.selection.threadId, 'C');
    expect(components.demand.calls, hasLength(sealedCalls));
    expect(
      components.conversation.active.value,
      same(sessionB),
      reason: 'Binding close neither forwards C nor closes the original domain',
    );
    expect(
      components.facets.metrics
          .singleWhere((call) => call.threadId == 'B')
          .feed
          .requestCloseCalls,
      0,
    );
    workspace.seal();
    components.conversation.seal();
    final pending = await Future.wait([
      workspace.close(deadline: DateTime.utc(2000)),
      components.conversation.close(deadline: DateTime.utc(2000)),
    ]);
    expect(
      pending.every((report) => !report.complete),
      isTrue,
      reason: 'The real original opens remain domain-owned after binding close',
    );
    expect(components.demand.calls, hasLength(sealedCalls));
    final nativeDirectory = originalOpen.accept()
      ..feed.closeReceipt = Completer<FeedCloseReport>();
    components.port.acceptPendingOpens();
    final nativeTimeline = TestTimelineConnection(initial: baseline(1))
      ..closeGate = Completer<void>();
    lateTimeline.result.complete(nativeTimeline);
    await Future.wait([
      nativeDirectory.feed.closeStarted.future,
      nativeTimeline.closeStarted.future,
    ]);
    final closing = await Future.wait([
      workspace.retryCleanup(deadline: DateTime.utc(2000)),
      components.conversation.retryCleanup(deadline: DateTime.utc(2000)),
    ]);
    expect(
      closing.every((report) => !report.complete),
      isTrue,
      reason: 'Late handles still require their actual native close receipts',
    );
    nativeDirectory.feed.closeReceipt!.complete(
      FeedCloseReport(
        feedId: nativeDirectory.feed.feedId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    nativeTimeline.closeGate!.complete();
    expect((await workspace.retryCleanup()).complete, isTrue);
    expect((await components.conversation.retryCleanup()).complete, isTrue);
    await nativeTimeline.closeCompleted.future;
    await harness.close();
    expect(budget.usage, isEmpty);
  });

  test('an accepted automatic ticket is reused after rejected or Unknown results even when its source later fails', () async {
    for (final unknown in [false, true]) {
      final harness = UpdatesBootstrapFixture();
      final updates = harness.updates;
      final starting = harness.bootstrap.start();
      await harness.startupPort.completeReady();
      final feed = (await beforeCompletion(
        updates.port.feedOpened(0),
        starting,
        'The gate must read its own source',
      )).accept();
      await feed.publish(idleUpdateHeader(1), projectionRevision: 1);
      final runtimeResult = await starting;
      final ticket = harness.tickets.single;
      final call = await updates.port.automaticOpened(0);
      const failure = StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'The automatic operation failed.',
        retryable: true,
        correlationId: 'automatic-once-failed',
      );
      if (unknown) {
        harness.expectedTerminalCorrelation = failure.correlationId;
        final task = call.accept();
        await Future.wait([task.finishCalled.future, task.startCalled.future]);
        expect(task.calls.take(2), ['finish', 'start']);
        expect(task.identity.operationId, ticket.id);
        task.startReply.complete();
        task.finishReply.completeError(
          const CommandDispatchFailure.unknownOutcome(failure: failure),
        );
        expect(
          await ticket.result,
          const CommandResult<Unit>.unknownOutcome(error: failure),
        );
      } else {
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: failure),
        );
        expect(
          await ticket.result,
          const CommandResult<Unit>.rejected(error: failure),
        );
      }
      final failedSource = updates.repository.state.waitFor(
        (state) => state.projection.sync.phase == ResourceSyncPhase.failed,
      );
      feed.fail(
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'Source failed after ticket acceptance.',
          retryable: true,
          correlationId: 'after-automatic-ticket',
        ),
      );
      await failedSource;
      final joined = Completer<void>();
      void observeNativeJoin() {
        if (joined.isCompleted) return;
        final remaining = updates.budget.used(ResourceKind.readModel);
        final expected = unknown ? 1 : 0;
        if (remaining < expected) {
          joined.completeError(
            StateError(
              'UnknownOutcome released its original task owner without terminal resolution',
            ),
          );
        } else if (remaining == expected) {
          joined.complete();
        }
      }

      final releases = updates.budget.watchAvailability(
        ResourceKind.readModel,
        observeNativeJoin,
      );
      addTearDown(releases.cancel);
      observeNativeJoin();
      await joined.future;
      releases.cancel();
      final feedCalls = updates.port.feeds.length;
      final readCalls = updates.port.values.length;
      expect(
        await harness.automatic.startAfterRuntimeReady(
          ScriptedStartupPort.ready,
        ),
        same(ticket),
      );
      expect(await harness.bootstrap.start(), same(runtimeResult));
      expect(harness.attachments, [ScriptedStartupPort.ready]);
      expect(harness.startupPort.attempts, [41]);
      expect(
        (updates.port.feeds.length, updates.port.values.length),
        (feedCalls, readCalls),
      );
      expect(updates.port.automatic.single.operationId, ticket.id);
      await harness.close();
    }
  });

  test('seal joins the original pending open or entered read and domain close still waits for the actual native close receipt', () async {
    for (final enterHeader in [false, true]) {
      final harness = UpdatesBootstrapFixture();
      final updates = harness.updates;
      final starting = harness.bootstrap.start();
      final runtimeTicket = harness.startup.start();
      await harness.startupPort.completeReady();
      final original = await runtimeTicket.result;
      final feed = (await beforeCompletion(
        updates.port.feedOpened(0),
        starting,
        'The gate must remain pending',
      )).accept();
      await feed.publish(availableUpdateHeader(1), projectionRevision: 1);
      final opened = await beforeCompletion(
        updates.port.valueOpened(0),
        starting,
        'The original open must have entered',
      );
      UpdatesValuePin? pin;
      if (enterHeader) {
        pin = opened.accept()..closeReceipt = Completer<FeedCloseReport>();
        await pin.headerCalled.future;
      }
      final outcome = starting.then<Object>(
        (value) => value,
        onError: (Object error, StackTrace stack) {
          if (error is StudioFailure &&
              error.code == StudioFailureCode.cancelled) {
            return error;
          }
          Error.throwWithStackTrace(error, stack);
        },
      );
      var gateJoined = false;
      var bootstrapJoined = false;
      var domainJoined = false;
      final gateClose = harness.automatic
          .close(deadline: DateTime.utc(2000))
          .then((report) {
            gateJoined = true;
            return report;
          });
      final bootstrapClose = harness.bootstrap
          .close(deadline: DateTime.utc(2000))
          .then((report) {
            bootstrapJoined = true;
            return report;
          });
      final domainClose = updates.repository.close().then((report) {
        domainJoined = true;
        return report;
      });
      await beforeCompletion(
        feed.feed.closeStarted.future,
        Future.any([gateClose, bootstrapClose, domainClose]),
        'A deadline or seal cannot complete an owner whose original open/read has not joined',
      );
      expect(
        (gateJoined, bootstrapJoined, domainJoined),
        (false, false, false),
      );
      pin ??= opened.accept()..closeReceipt = Completer<FeedCloseReport>();
      await pin.closeCalled.future;
      if (enterHeader) pin.headerReply.complete(availableUpdateRead(1));
      expect((await gateClose).complete, isTrue);
      expect((await bootstrapClose).complete, isTrue);
      final result = await outcome;
      if (enterHeader) {
        expect(result, same(original));
      } else {
        expect(
          result,
          isA<StudioFailure>().having(
            (error) => error.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        );
      }
      expect(
        domainJoined,
        isFalse,
        reason: 'App gate cleanup is not the native read-scope close ACK',
      );
      expect(pin.closed, isFalse);
      pin.closeReceipt!.complete(
        FeedCloseReport(
          feedId: pin.id,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
      expect((await domainClose).complete, isTrue);
      expect(pin.closed, isTrue);
      expect(updates.port.automatic, isEmpty);
      await expectLater(
        harness.bootstrap.start(),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'code',
            StudioFailureCode.cancelled,
          ),
        ),
      );
      await harness.close();
      expect(updates.budget.usage, isEmpty);
    }
  });

  test('disabled local startup or domain controls do no Updates work and never fabricate canonical Disabled or Idle', () async {
    for (final localDisabled in [true, false]) {
      final harness = UpdatesBootstrapFixture(
        localEnabled: !localDisabled,
        controlsEnabled: localDisabled,
      );
      final updates = harness.updates;
      final unknown = updates.repository.state.value;
      final starting = harness.bootstrap.start();
      await harness.startupPort.completeReady();
      final result = await starting;
      expect(
        result,
        const CommandResult<RuntimeReady>.acknowledged(
          value: ScriptedStartupPort.ready,
        ),
      );
      expect(
        await harness.automatic.startAfterRuntimeReady(
          ScriptedStartupPort.ready,
        ),
        isNull,
      );
      expect(await harness.bootstrap.start(), same(result));
      expect(updates.repository.state.value, same(unknown));
      expect(
        (unknown.projection.stamp, unknown.projection.header, unknown.value),
        (null, null, null),
      );
      expect(updates.repository.state.observerCount, 0);
      expect(updates.port.feeds, isEmpty);
      expect(updates.port.values, isEmpty);
      expect(updates.port.automatic, isEmpty);
      expect(harness.startupPort.attempts, [41]);
      await harness.close();
    }
  });
}
