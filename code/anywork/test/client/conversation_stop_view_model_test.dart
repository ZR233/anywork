import 'dart:async';

import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/conversation_stop_native.dart';
import 'support/conversation_stop_view_model_fixture.dart';

void main() {
  test('the VM rejects an old A callback after A-B-A even with the same page and Turn entry', () async {
    final fixture = await ConversationStopViewModelFixture.create();
    final page = ConversationStopPage(isCurrent: () => true);
    fixture.vm.deferStopPage(page);
    final oldCallback = fixture.vm.captureStop(page)!;
    final oldSource = fixture.initial;
    expect((await fixture.stop.owner.demand.retire('A')).complete, isTrue);
    await fixture.stop.select(threadId: 'B');
    final replacement = await fixture.stop.select(
      threadId: 'A',
      incarnation: 2,
    );
    await fixture.waitFor(
      (state) => state.execution?.stamp == replacement.stamp,
    );
    expect(replacement.session, isNot(same(oldSource.session)));
    await oldCallback();
    expect(
      fixture.stop.reads.values,
      isEmpty,
      reason: 'The stale UI capability must be rejected before even opening a new identity scope',
    );
    expect(fixture.stop.commands.interrupts.values, isEmpty);

    final action = await fixture.dispatch(page);
    expect(fixture.stop.reads.values.single.origin, replacement.stamp);
    expect(fixture.stop.reads.values.single.reference, stopTurn(7).reference);
    acceptStop(action.call);
    await action.operation.state.waitFor((state) => state.receipt != null);
    await replacement.deliver(active: null, status: ThreadStatus.idle);
    await action.settled;
    await fixture.waitFor((state) => state.stop?.operation?.effective == true);
    expect(
      fixture.vm.stopStateFor(page)?.operation?.id,
      action.call.operationId,
    );
    expect(fixture.stop.commands.interrupts.values, hasLength(1));
  });

  test('covering a page retires its callback but returning observes the original completed Stop', () async {
    final fixture = await ConversationStopViewModelFixture.create();
    final page = ConversationStopPage(isCurrent: () => true);
    fixture.vm.deferStopPage(page);
    final oldCallback = fixture.vm.captureStop(page)!;
    final action = await fixture.dispatch(page);
    var settled = false;
    final settling = action.settled.then((_) {
      settled = true;
    });
    acceptStop(action.call);
    final accepted = await fixture.waitFor(
      (state) => state.stop?.accepted == true,
    );
    expect(
      (
        accepted.stop!.operation!.observed,
        accepted.stop!.operation!.effective,
        settled,
      ),
      (false, false, false),
    );
    expect(
      fixture.vm.captureStop(page),
      isNull,
      reason: 'Accepted without Observed blocks duplicate Stop',
    );

    final visibleObservers = action.operation.state.observerCount;
    final detached = Completer<void>();
    final released = fixture.stop.budget.watchAvailability(
      ResourceKind.observer,
      () {
        if (action.operation.state.observerCount == visibleObservers - 1 &&
            !detached.isCompleted) {
          detached.complete();
        }
      },
    );
    addTearDown(released.cancel);
    page.retire();
    fixture.vm.deferStopPage(page);
    await detached.future;
    released.cancel();
    expect(fixture.vm.stopStateFor(page), isNull);
    await oldCallback();
    expect(fixture.stop.commands.interrupts.values, hasLength(1));
    await fixture.initial.deliver(active: null, status: ThreadStatus.idle);
    await settling;

    final returned = ConversationStopPage(isCurrent: () => true);
    fixture.vm.deferStopPage(returned);
    await fixture.waitFor((state) => state.stop?.operation?.effective == true);
    final value = fixture.vm.stopStateFor(returned)!;
    expect(value.intent, accepted.stop!.intent);
    expect(value.operation!.id, action.call.operationId);
    expect(
      (
        value.operation!.observed,
        value.operation!.effective,
        value.operation!.durable,
      ),
      (true, true, false),
    );
    expect(value.result, isA<CommittedCommandResult<Unit>>());
    expect(
      fixture.vm.captureStop(returned),
      isNull,
      reason: 'Returning observes the same ticket even though the Turn is no longer busy',
    );
    expect(fixture.stop.reads.values, hasLength(1));
    expect(fixture.stop.commands.interrupts.values, hasLength(1));
  });

  test('full VM disposal releases its Accepted waiter while SDK evidence and native metadata close remain owned', () async {
    final fixture = await ConversationStopViewModelFixture.create();
    final page = ConversationStopPage(isCurrent: () => true);
    final vm = fixture.vm;
    vm.deferStopPage(page);
    final action = await fixture.dispatch(page);
    acceptStop(action.call);
    await fixture.waitFor((state) => state.stop?.accepted == true);
    final nativeMetadata = fixture.workspacePort.threads.single.native!.feed;
    final nativeClose = nativeMetadata.closeReceipt =
        Completer<FeedCloseReport>();
    final visibleObservers = action.operation.state.observerCount;

    fixture.disposePresentation();
    await nativeMetadata.closeStarted.future;
    // This must finish before any terminal evidence or native close reply. A
    // disposed VM must not be held by its otherwise unbounded ticket.result.
    await action.settled;
    expect(page.isCurrent, isFalse);
    expect(vm.captureStop(page), isNull);
    expect(
      action.operation.state.observerCount,
      visibleObservers - 1,
      reason: 'Only the UI watch leaves; the real SDK operation still observes its original evidence',
    );
    expect(
      (
        action.operation.state.value.receipt?.operationId,
        action.operation.state.value.observed,
        action.operation.state.value.effective,
      ),
      (action.call.operationId, false, false),
    );
    expect(
      fixture.initial.opening.feed.closeCalls,
      0,
      reason: 'Disposing the presentation cannot close the active SDK Session',
    );

    final pending = await fixture.workspace.close(deadline: DateTime.utc(2000));
    expect(pending.complete, isFalse);
    expect(
      pending.unresolved,
      isNotEmpty,
      reason: 'The original Workspace still reports the actual native metadata close responsibility',
    );
    expect(nativeClose.isCompleted, isFalse);
    nativeClose.complete(
      FeedCloseReport(
        feedId: nativeMetadata.feedId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await fixture.workspace.retryCleanup()).complete, isTrue);

    await fixture.initial.deliver(active: null, status: ThreadStatus.idle);
    await action.operation.state.waitFor(
      (state) => state.observed && state.effective,
    );
    expect(action.operation.state.value.durable, isFalse);
    expect(fixture.stop.commands.interrupts.values, hasLength(1));
    expect(
      fixture.stop.owner.repository.existingSession('A'),
      same(fixture.initial.session),
    );
  });
}
