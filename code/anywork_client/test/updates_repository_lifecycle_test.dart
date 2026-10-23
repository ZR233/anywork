import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';
import 'package:test/test.dart';

import 'support/updates_port_fixture.dart';

const _retryIssue = FeedCloseIssue(diagnostic: StudioShutdownIssue(
  stage: 'updates-native-close', code: 'cancelUnconfirmed',
  message: 'The original automatic task cancellation still needs a native join.',
  retryable: true, correlationId: 'automatic-cancel-join'), recovery: CleanupRecovery.retryClose);

void main() {
  test('automatic cleanup retains the original task and typed retry issue, then joins it before closing feed and reads', () async {
    final fixture = UpdatesPortFixture();
    final repository = fixture.repository;
    final port = fixture.port;
    addTearDown(() async {
      final report = await fixture.close();
      expect(report.unresolved, isEmpty);
      expect(fixture.budget.usage, isEmpty);
    });
    expect(port.feeds, isEmpty);
    final reading = repository.loadValue();
    final feed = (await port.feedOpened(0)).accept();
    await feed.publish(idleUpdateHeader(1), projectionRevision: 1);
    await reading;
    final ticket = fixture.lifecycle.startAutomaticOnce();
    expect(fixture.lifecycle.startAutomaticOnce(), same(ticket));
    final call = await port.automaticOpened(0);
    expect(call.operationId, ticket.id);
    final task = call.accept()..closeReceipt = Completer<UpdateTaskCloseReport>()
      ..retryReceipt = Completer<UpdateTaskCloseReport>();
    await Future.wait([task.finishCalled.future, task.startCalled.future]);
    expect(task.calls, ['finish', 'start']);
    expect(task.identity.operationId, ticket.id);
    task.startReply.complete();
    final target = UpdatesReadTarget(origin: feed.origin, reference: idleUpdateHeader(1).reference);
    task.finishReply.complete(target);
    final value = await port.valueOpened(0);
    expect(value.target, target, reason: 'The result reads the actual finish target, not a later canonical value');
    final pin = value.accept();
    await pin.headerCalled.future;
    pin.headerReply.complete(const UpdatesReadHeader.idle(revision: 1, updatedAt: 1));
    expect(await ticket.result, const CommandResult<Unit>.acknowledged(value: Unit()));
    await task.closeCalled.future;
    var closed = false;
    final closing = repository.close().then((report) { closed = true; return report; });
    expect(closed, isFalse, reason: 'An operation result is not the native task close receipt');
    expect(feed.feed.requestCloseCalls, 0);
    expect(pin.closed, isFalse);
    task.closeReceipt!.complete(UpdateTaskCloseReport(identity: task.identity,
      outcome: FeedCloseOutcome.unresolved(issues: [_retryIssue])));
    final unresolved = await closing;
    expect(unresolved.complete, isFalse);
    final original = unresolved.unresolved.where((resource) => resource.owner == 'updates-automatic' &&
      resource.issues.contains(_retryIssue)).single;
    expect(original.issues, [_retryIssue]);
    expect(feed.feed.requestCloseCalls, 0, reason: 'An unresolved task cannot start the feed/read close phase');
    expect(feed.feed.closeCalls, 0);
    expect(pin.closed, isFalse);
    expect(fixture.budget.usage.any((usage) => usage.owner == 'updates-automatic' &&
      usage.phase == ResourcePhase.unresolved), isTrue);

    final retry = repository.retryCleanup();
    await Future.any([
      task.retryCalled.future,
      retry.then<void>((_) => throw StateError('Cleanup reused the old report without retrying the original native task')),
    ]);
    expect(feed.feed.closeCalls, 0);
    task.retryReceipt!.complete(UpdateTaskCloseReport(identity: task.identity, outcome: const FeedCloseOutcome.clean()));
    expect((await retry).complete, isTrue);
    expect(task.closed, isTrue);
    expect(pin.closed, isTrue);
    expect(feed.feed.cancellationStarted.isCompleted, isTrue);
    expect(feed.feed.closeCalls, 1);
    expect(task.calls.where((call) => call == 'start'), ['start']);
    expect(task.calls.where((call) => call == 'finish'), ['finish']);
    expect(task.calls.where((call) => call == 'cancel'), ['cancel']);
    expect(task.calls.where((call) => call == 'retryClose'), ['retryClose']);
    expect(port.automatic.single.operationId, ticket.id, reason: 'Cleanup never opens or dispatches another automatic task');
    expect(original.issues, [_retryIssue], reason: 'Later Clean cannot mutate the captured original report');
    expect(fixture.budget.usage, isEmpty);
  });
}
