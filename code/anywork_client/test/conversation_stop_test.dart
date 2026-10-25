import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_stop_fixture.dart' show stopFixture;
import 'support/conversation_stop_native.dart';

const _ordinaryFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The mailbox changed after a possible cancellation.',
  retryable: false,
  correlationId: 'stop-native-ordinary',
);
const _conversionFailure = StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'The native stop succeeded but its observation material could not be converted.',
  retryable: false,
  correlationId: 'stop-native-conversion',
);
const _readRetry = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'native-stop-read',
    code: 'originalScopePending',
    message: 'The original identity scope still needs native cleanup.',
    retryable: true,
    correlationId: 'stop-original-scope',
  ),
  recovery: CleanupRecovery.retryClose,
);

InterruptTurnReply _reply(
  StopInterrupt call,
  CommitReceipt receipt, {
  bool interrupted = true,
}) => InterruptTurnReply(
  threadId: call.threadId,
  turnId: call.turnId,
  interrupted: interrupted,
  receipt: receipt,
);

Future<({OperationTicket<Unit> ticket, StopInterrupt call})> _dispatch(
  StopFixture fixture,
  StopSource source, {
  int readIndex = 0,
  int interruptIndex = 0,
  String turnId = 'native-original-turn',
}) async {
  final origin = source.stamp;
  final target = source.session.execution.value.value!.activeTurn!.reference;
  final ticket = source.session.stopTurn(origin: origin, target: target);
  final opening = await fixture.reads.at(readIndex);
  expect(
    (opening.threadId, opening.reference, opening.origin),
    (source.session.threadId, target, origin),
  );
  final pin = await fixture.acceptRead(
    readIndex,
    turnId: ReadText.inline(text: turnId),
  );
  await pin.entered.future;
  await Future.any<void>([
    fixture.commands.interrupts.at(interruptIndex).then<void>((_) {}),
    ticket.result.then<void>(
      (result) => fail(
        'The original busy target must reach the native boundary: $result',
      ),
    ),
  ]);
  final call = await fixture.commands.interrupts.at(interruptIndex);
  expect(
    (call.threadId, call.turnId, call.operationId),
    (source.session.threadId, turnId, ticket.id),
  );
  return (ticket: ticket, call: call);
}

void _noStopResources(StopFixture fixture) {
  expect(
    fixture.budget.usage.where(
      (usage) =>
          usage.owner.startsWith('stop-dispatch:') ||
          usage.owner.startsWith('stop-evidence:') ||
          usage.owner.startsWith('thread-read:'),
    ),
    isEmpty,
  );
}

void main() {
  test('Stop reads the frozen UTF-8 identity through normal same-entry progress and joins terminal proof that preceded its receipt', () async {
    final fixture = await stopFixture();
    const threadId = ' 会话 A\t';
    const prefix = ' \t原始/';
    const suffix = 'α⚙️ \n';
    const turnId = '$prefix$suffix';
    final source = await fixture.select(threadId: threadId);
    final origin = source.stamp;
    final target = stopTurn(7).reference;
    final ticket = source.session.stopTurn(origin: origin, target: target);
    expect(ticket.state.value.receipt, isNull);
    final opening = await fixture.reads.at(0);
    final pin = await fixture.acceptRead(
      0,
      scriptText: true,
      turnId: ReadText.deferred(
        fieldId: 41,
        utf8Bytes: utf8.encode(turnId).length,
      ),
    );
    await pin.entered.future;
    final firstText = await pin.texts.at(
      0,
    ); // The original ID query is really waiting.
    expect(
      (firstText.fieldId, firstText.offset, firstText.maxBytes),
      (41, 0, 65536),
    );
    await source.deliver(
      active: stopTurn(7, revision: 2),
      status: ThreadStatus.running,
    );
    expect(fixture.commands.interrupts.values, isEmpty);
    expect(
      (opening.threadId, opening.reference, opening.origin),
      (threadId, target, origin),
    );
    firstText.reply.complete(
      TextChunk(
        fieldId: 41,
        offset: 0,
        text: prefix,
        nextOffset: utf8.encode(prefix).length,
      ),
    );
    final lastText = await pin.texts.at(1);
    expect(
      (lastText.fieldId, lastText.offset),
      (41, utf8.encode(prefix).length),
    );
    lastText.reply.complete(
      TextChunk(
        fieldId: 41,
        offset: lastText.offset,
        text: suffix,
        nextOffset: null,
      ),
    );
    final call = await fixture.commands.interrupts.at(0);
    expect(
      (call.threadId, call.turnId, call.operationId),
      (threadId, turnId, ticket.id),
      reason: 'Neither whitespace nor non-ASCII identity may be trimmed, normalized or replaced by entry',
    );
    expect(fixture.reads.values, hasLength(1));
    expect(pin.closes.values, hasLength(1));
    expect(ticket.state.value.receipt, isNull);

    await source.deliver(active: null, status: ThreadStatus.idle);
    expect(
      (
        ticket.state.value.observed,
        ticket.state.value.effective,
        ticket.state.value.durable,
      ),
      (false, false, false),
      reason: 'Even an original terminal fact cannot manufacture a missing cancellation receipt',
    );
    final receipt = stopReceipt(ticket.id);
    call.reply.complete(_reply(call, receipt));
    final result = await ticket.result;
    expect(result, isA<CommittedCommandResult<Unit>>());
    expect((result as CommittedCommandResult<Unit>).receipt, receipt);
    expect(
      (
        ticket.state.value.observed,
        ticket.state.value.effective,
        ticket.state.value.durable,
      ),
      (true, true, false),
    );
    expect(
      fixture.owner.operations.observations.lookup(ticket.id)!.state.value,
      ticket.state.value,
    );
    expect((await fixture.owner.repository.close()).complete, isTrue);
    expect(fixture.commands.interrupts.values, hasLength(1));
    _noStopResources(fixture);
  });

  test('a NoChange Stop receipt is only acceptance and leaving UI does not revoke the original evidence demand', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final action = await _dispatch(fixture, source);
    final receipt = stopReceipt(
      action.ticket.id,
      disposition: CommitDisposition.noChange,
    );
    action.call.reply.complete(
      _reply(action.call, receipt, interrupted: false),
    );
    await action.ticket.state.waitFor((state) => state.receipt != null);
    expect(action.ticket.state.value.receipt, receipt);
    expect(
      (
        action.ticket.state.value.observed,
        action.ticket.state.value.effective,
        action.ticket.state.value.durable,
      ),
      (false, false, false),
    );
    fixture.owner.deselect();
    await fixture.owner.facets.configuration.single.feed.closeStarted.future;
    expect(
      source.opening.feed.closeCalls,
      0,
      reason: 'Actual UI retirement must leave this operation\'s Execution source alive',
    );
    await source.deliver(
      active: stopTurn(7, revision: 2),
      status: ThreadStatus.running,
    );
    expect(
      (action.ticket.state.value.observed, action.ticket.state.value.effective),
      (false, false),
      reason: 'A later busy revision of the same entry is not terminal proof',
    );
    source.send(active: null, status: ThreadStatus.idle);
    // The result can settle before Effective; UI retirement may also close the
    // source before its ACK. Wait for the public operation proof, not either one.
    await action.ticket.state.waitFor(
      (state) => state.observed && state.effective,
    );
    final result = await action.ticket.result;
    expect(result, isA<CommittedCommandResult<Unit>>());
    expect((result as CommittedCommandResult<Unit>).receipt, receipt);
    expect(
      (
        action.ticket.state.value.observed,
        action.ticket.state.value.effective,
        action.ticket.state.value.durable,
      ),
      (true, true, false),
    );
    expect((await fixture.owner.repository.close()).complete, isTrue);
    expect(fixture.commands.interrupts.values, hasLength(1));
    _noStopResources(fixture);
  });

  test('a target that ended during its entered identity read is rejected locally without dispatching another active Turn', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final ticket = source.session.stopTurn(
      origin: source.stamp,
      target: stopTurn(7).reference,
    );
    await fixture.reads.at(0);
    final header = Completer<TurnReadHeader>();
    final pin = await fixture.acceptRead(0, headerReply: header);
    await pin.entered.future;
    await source.deliver(active: stopTurn(8), status: ThreadStatus.running);
    header.complete(pin.value);
    await Future.any<void>([
      ticket.result.then<void>((_) {}),
      fixture.commands.interrupts
          .at(0)
          .then<void>(
            (_) => fail(
              'The frozen target ended; a new active entry cannot redirect Stop',
            ),
          ),
    ]);
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<Unit>>());
    expect(
      (result as RejectedCommandResult<Unit>).error.code,
      StudioFailureCode.superseded,
    );
    expect(fixture.commands.interrupts.values, isEmpty);
    expect(fixture.reads.values.single.reference, stopTurn(7).reference);
    expect(
      source.session.execution.value.value!.activeTurn!.reference,
      stopTurn(8).reference,
    );
    expect((await fixture.owner.repository.close()).complete, isTrue);
    _noStopResources(fixture);
  });

  test('A-B-A keeps admitted old Stop on its original Session while late old proof and reply cannot settle the new incarnation', () async {
    final fixture = await stopFixture();
    final oldSource = await fixture.select(threadId: 'A');
    final old = await _dispatch(fixture, oldSource, turnId: 'old-native-turn');
    await fixture.owner.demand.retire('A', deadline: DateTime.utc(2000));
    await fixture.select(threadId: 'B');
    final current = await fixture.select(threadId: 'A', incarnation: 2);
    expect(current.session, isNot(same(oldSource.session)));
    final stale = oldSource.session.stopTurn(
      origin: current.stamp,
      target: stopTurn(7).reference,
    );
    expect(await stale.result, isA<RejectedCommandResult<Unit>>());
    expect(fixture.commands.interrupts.values, hasLength(1));
    final newer = await _dispatch(
      fixture,
      current,
      readIndex: 1,
      interruptIndex: 1,
      turnId: 'new-native-turn',
    );
    expect(newer.ticket.id, isNot(old.ticket.id));
    expect(
      fixture.owner.operations.observations.latest('stop:A')!.id,
      newer.ticket.id,
    );

    expect(old.call.reply.isCompleted, isFalse);
    final oldTerminalSequence = oldSource.send(
      active: null,
      status: ThreadStatus.idle,
    );
    // With this original dispatch still pending, cleanup cannot retire its
    // source. Its real ACK proves the old handoff finished before reply release.
    await oldSource.opening.feed.acknowledged(oldTerminalSequence);
    expect(old.call.reply.isCompleted, isFalse);
    final oldReceipt = stopReceipt(old.ticket.id);
    old.call.reply.complete(_reply(old.call, oldReceipt));
    await old.ticket.state.waitFor(
      (state) => state.observed && state.effective,
    );
    final oldResult = await old.ticket.result;
    expect(oldResult, isA<CommittedCommandResult<Unit>>());
    expect((oldResult as CommittedCommandResult<Unit>).receipt, oldReceipt);
    expect(
      (
        old.ticket.state.value.observed,
        old.ticket.state.value.effective,
        old.ticket.state.value.durable,
      ),
      (true, true, false),
    );
    expect(
      (
        newer.ticket.state.value.receipt,
        newer.ticket.state.value.observed,
        newer.ticket.state.value.effective,
      ),
      (null, false, false),
      reason: 'Same Thread/entry in another incarnation is not this new owner\'s terminal proof',
    );
    expect(
      fixture.owner.repository.existingSession('A'),
      same(current.session),
    );
    expect(
      fixture.owner.operations.observations.latest('stop:A')!.id,
      newer.ticket.id,
    );
    expect(
      fixture.commands.interrupts.values.map(
        (call) => (call.threadId, call.turnId, call.operationId),
      ),
      [
        ('A', 'old-native-turn', old.ticket.id),
        ('A', 'new-native-turn', newer.ticket.id),
      ],
    );
    final receipt = stopReceipt(newer.ticket.id);
    newer.call.reply.complete(_reply(newer.call, receipt));
    await newer.ticket.state.waitFor((state) => state.receipt != null);
    await current.deliver(
      active: stopTurn(7, revision: 2),
      status: ThreadStatus.running,
    );
    expect(newer.ticket.state.value.observed, isFalse);
    await current.deliver(active: null, status: ThreadStatus.idle);
    expect(await newer.ticket.result, isA<CommittedCommandResult<Unit>>());
    expect(
      (newer.ticket.state.value.effective, newer.ticket.state.value.durable),
      (true, false),
    );
    expect((await fixture.owner.repository.close()).complete, isTrue);
    expect(fixture.commands.interrupts.values, hasLength(2));
    _noStopResources(fixture);
  });

  test('post-dispatch ordinary InvalidArgument stays Unknown after terminal, unlike a genuine rejected dispatch of a new operation', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final first = await _dispatch(fixture, source);
    first.call.reply.completeError(_ordinaryFailure);
    final original = await first.ticket.result;
    expect(original, isA<UnknownOutcomeCommandResult<Unit>>());
    expect(
      (original as UnknownOutcomeCommandResult<Unit>).error,
      same(_ordinaryFailure),
    );
    fixture.retainedOperations.add((
      ticket: first.ticket,
      phase: OperationFailurePhase.unknownOutcome,
    ));
    await source.deliver(active: null, status: ThreadStatus.idle);
    expect(
      (
        first.ticket.state.value.receipt,
        first.ticket.state.value.observed,
        first.ticket.state.value.effective,
      ),
      (null, false, false),
    );
    expect(
      first.ticket.state.value.failurePhase,
      OperationFailurePhase.unknownOutcome,
    );
    expect(first.ticket.state.value.error, same(_ordinaryFailure));
    expect(await first.ticket.result, same(original));
    await source.deliver(active: stopTurn(8), status: ThreadStatus.running);
    final next = await _dispatch(
      fixture,
      source,
      readIndex: 1,
      interruptIndex: 1,
      turnId: 'another-native-turn',
    );
    next.call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: _ordinaryFailure),
    );
    final rejected = await next.ticket.result;
    expect(rejected, isA<RejectedCommandResult<Unit>>());
    expect(
      (rejected as RejectedCommandResult<Unit>).error,
      same(_ordinaryFailure),
    );
    expect(
      fixture.commands.interrupts.values.map((call) => call.operationId),
      [first.ticket.id, next.ticket.id],
      reason: 'Only the explicit next user operation dispatches; Unknown is never retried',
    );
    expect((await fixture.owner.repository.close()).complete, isTrue);
    expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
    expect(await first.ticket.result, same(original));
    expect(fixture.commands.interrupts.values, hasLength(2));
    _noStopResources(fixture);
  });

  test('a successful native reply with bad receipt and an explicitly confirmed conversion failure never fall back to Unknown', () async {
    for (final badReply in [true, false]) {
      final fixture = await stopFixture();
      final source = await fixture.select();
      final action = await _dispatch(fixture, source);
      if (badReply) {
        action.call.reply.complete(
          _reply(action.call, stopReceipt(const OperationId('foreign-stop'))),
        );
      } else {
        action.call.reply.completeError(
          const CommandDispatchFailure.confirmedWithoutUsableReceipt(
            failure: _conversionFailure,
          ),
        );
      }
      final first = await action.ticket.result;
      expect(first, isA<AcknowledgedSyncFailedCommandResult<Unit>>());
      final failure = first as AcknowledgedSyncFailedCommandResult<Unit>;
      expect(failure.value, const Unit());
      expect(failure.error.code, StudioFailureCode.protocol);
      if (!badReply) expect(failure.error, same(_conversionFailure));
      expect(
        (
          action.ticket.state.value.acknowledged,
          action.ticket.state.value.receipt,
          action.ticket.state.value.failurePhase,
        ),
        (true, null, OperationFailurePhase.syncFailed),
      );
      await source.deliver(active: null, status: ThreadStatus.idle);
      expect(
        (
          action.ticket.state.value.observed,
          action.ticket.state.value.effective,
          action.ticket.state.value.durable,
        ),
        (false, false, false),
        reason: 'A later terminal cannot repair a missing usable receipt',
      );
      expect((await fixture.owner.repository.close()).complete, isTrue);
      expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
      expect(await action.ticket.result, same(first));
      expect(fixture.commands.interrupts.values, hasLength(1));
      _noStopResources(fixture);
    }
  });

  test('a valid committed-but-unobserved receipt survives source closure without treating that control as terminal proof', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final action = await _dispatch(fixture, source);
    final receipt = stopReceipt(action.ticket.id);
    action.call.reply.completeError(
      CommandDispatchFailure.committedButUnobserved(
        receipt: receipt,
        failure: _conversionFailure,
      ),
    );
    final original = await action.ticket.result;
    expect(original, isA<SyncFailedCommandResult<Unit>>());
    final failed = original as SyncFailedCommandResult<Unit>;
    expect((failed.receipt, failed.error), (receipt, _conversionFailure));
    expect(failed.error, same(_conversionFailure));
    fixture.retainedOperations.add((
      ticket: action.ticket,
      phase: OperationFailurePhase.syncFailed,
    ));
    source.opening.feed.emit(
      ThreadExecutionFrame.closed(
        identity: source.identity,
        reason: ThreadFeedClosedReason.runtimeStopped,
      ),
    );
    await action.ticket.state.waitFor(
      (state) => state.evidenceError?.code == StudioFailureCode.runtimeStopped,
    );
    expect(
      (
        action.ticket.state.value.receipt,
        action.ticket.state.value.observed,
        action.ticket.state.value.effective,
        action.ticket.state.value.durable,
      ),
      (receipt, false, false, false),
    );
    expect((await fixture.owner.repository.close()).complete, isTrue);
    expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
    expect(action.ticket.state.value.receipt, receipt);
    expect(await action.ticket.result, same(original));
    expect(fixture.commands.interrupts.values, hasLength(1));
    _noStopResources(fixture);
  });

  test('close retains an entered native Stop dispatch and reentrant receipt notification joins it without resending', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final action = await _dispatch(fixture, source);
    Future<CloseReport>? reentrant;
    final watch = action.ticket.state.watch((state) {
      if (state.receipt != null && reentrant == null)
        reentrant = fixture.owner.repository.close();
    });
    addTearDown(watch.cancel);
    var completed = false;
    final closing = fixture.owner.repository.close().then((report) {
      completed = true;
      return report;
    });
    final pending = await fixture.owner.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(pending.complete, isFalse);
    expect(
      pending.unresolved.any(
        (item) => item.owner == 'stop:${action.ticket.id.value}',
      ),
      isTrue,
    );
    expect(completed, isFalse);
    expect(
      fixture.budget.usage.any(
        (usage) =>
            usage.kind == ResourceKind.pendingOperation &&
            usage.owner == 'stop-dispatch:${action.ticket.id.value}',
      ),
      isTrue,
    );
    final receipt = stopReceipt(action.ticket.id);
    action.call.reply.complete(_reply(action.call, receipt));
    final first = await action.ticket.result;
    expect(
      first,
      isA<SyncFailedCommandResult<Unit>>(),
      reason: 'The original acceptance is preserved, but sealed evidence can no longer prove a terminal',
    );
    final failed = first as SyncFailedCommandResult<Unit>;
    expect(failed.receipt, receipt);
    expect(failed.error.code, StudioFailureCode.cancelled);
    expect((await closing).complete, isTrue);
    expect(reentrant, isNotNull);
    expect((await reentrant!).complete, isTrue);
    watch.cancel();
    fixture.retainedOperations.add((
      ticket: action.ticket,
      phase: OperationFailurePhase.syncFailed,
    ));
    expect(
      (
        action.ticket.state.value.receipt,
        action.ticket.state.value.observed,
        action.ticket.state.value.effective,
        action.ticket.state.value.durable,
      ),
      (receipt, false, false, false),
    );
    expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
    expect(await action.ticket.result, same(first));
    expect(fixture.commands.interrupts.values, hasLength(1));
    expect(fixture.pins.single.closes.values, hasLength(1));
    _noStopResources(fixture);
  });

  test('an original identity-scope close failure retains its real read permit and cleanup retries that handle without dispatching Stop', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final ticket = source.session.stopTurn(
      origin: source.stamp,
      target: stopTurn(7).reference,
    );
    await fixture.reads.at(0);
    final pin = await fixture.acceptRead(0, manualClose: true);
    await pin.entered.future;
    final nativeClose = await pin.closes.at(0);
    expect(
      fixture.commands.interrupts.values,
      isEmpty,
      reason: 'The original identity scope has not joined',
    );
    Future<CloseReport>? retrying;
    final retryWatch = ticket.state.watch((state) {
      // Enter the explicit retry through a real synchronous Registry callback,
      // before the rejected work schedules its ordinary background cleanup.
      if (state.failurePhase == OperationFailurePhase.rejected &&
          retrying == null) {
        retrying = fixture.owner.repository.retryCleanup();
      }
    });
    addTearDown(retryWatch.cancel);
    nativeClose.reply.complete(
      FeedCloseReport(
        feedId: pin.value.scope.scopeId,
        outcome: FeedCloseOutcome.unresolved(issues: [_readRetry]),
      ),
    );
    final first = await ticket.result;
    expect(
      first,
      isA<RejectedCommandResult<Unit>>(),
      reason: 'A pre-dispatch read cleanup failure is known non-dispatch',
    );
    final rejected = first as RejectedCommandResult<Unit>;
    expect(rejected.error.correlationId, 'stop-read-cleanup');
    expect(rejected.error.code, StudioFailureCode.unavailable);
    final retry = await pin.closes.at(
      1,
    ); // The same native handle is actually waiting in retryClose.
    expect(retry.retry, isTrue);
    final unresolved = await fixture.owner.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(
      unresolved.unresolved.expand((item) => item.issues),
      contains(_readRetry),
    );
    expect(
      fixture.budget.usage
          .singleWhere((usage) => usage.owner == 'thread-read:thread')
          .phase,
      ResourcePhase.unresolved,
    );
    expect(
      fixture.budget.usage.any(
        (usage) => usage.owner == 'stop-evidence:${ticket.id.value}',
      ),
      isTrue,
    );
    expect(
      fixture.budget.usage.any((usage) => usage.owner == 'thread-read:thread'),
      isTrue,
    );
    retry.reply.complete(
      FeedCloseReport(
        feedId: pin.value.scope.scopeId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect(retrying, isNotNull);
    expect((await retrying!).complete, isTrue);
    retryWatch.cancel();
    expect(await ticket.result, same(first));
    expect(fixture.reads.values, hasLength(1));
    expect(pin.closes.values.map((call) => call.retry), [false, true]);
    expect(
      fixture.commands.interrupts.values,
      isEmpty,
      reason: 'Cleanup is not a retry of the rejected business intention',
    );
    _noStopResources(fixture);
  });
}
