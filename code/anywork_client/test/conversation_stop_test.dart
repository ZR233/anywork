import 'dart:async';

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
  message: 'The native stop succeeded but conversion failed.',
  retryable: false,
  correlationId: 'stop-native-conversion',
);
StopExecutionReply _reply(
  StopInterrupt call, {
  bool stopped = true,
  CommitReceipt? receipt,
}) => StopExecutionReply(
  threadId: call.threadId,
  executionId: call.executionId,
  stopped: stopped,
  receipt:
      receipt ??
      stopReceipt(
        call.operationId,
        disposition: stopped
            ? CommitDisposition.applied
            : CommitDisposition.noChange,
      ),
);

Future<({OperationTicket<Unit> ticket, StopInterrupt call})> _dispatch(
  StopFixture fixture,
  StopSource source, {
  int index = 0,
  String executionId = 'execution-7',
}) async {
  final admission = source.session.stopExecution(
    origin: source.stamp,
    executionId: executionId,
  );
  expect(admission, isA<StopExecutionOperation>());
  final ticket = (admission as StopExecutionOperation).ticket;
  final call = await fixture.commands.interrupts.at(index);
  expect(
    (call.threadId, call.executionId, call.operationId),
    (source.session.threadId, executionId, ticket.id),
  );
  expect(
    fixture.reads.values,
    isEmpty,
    reason: 'Preparation has no Turn and Stop must not read or activate one.',
  );
  return (ticket: ticket, call: call);
}

void main() {
  test('valid original source with no execution returns a pure non-error result before any operation or request', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    await source.deliver(active: null, status: ThreadStatus.idle);
    final records = fixture.owner.operations.observations.records.value;
    final budget = List.of(fixture.budget.usage);
    final result = source.session.stopExecution(
      origin: source.stamp,
      executionId: 'formerly-displayed',
    );
    expect(result, isA<StopNoExecution>());
    expect((result as StopNoExecution).threadId, source.session.threadId);
    expect(fixture.owner.operations.observations.records.value, records);
    expect(fixture.budget.usage, budget);
    expect(fixture.commands.interrupts.values, isEmpty);
    expect(fixture.reads.values, isEmpty);
    expect(
      () => source.session.stopExecution(origin: source.stamp, executionId: ''),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'empty execution',
          StudioFailureCode.superseded,
        ),
      ),
    );
    expect(
      source.session.stopExecution(origin: source.stamp, executionId: ' \n'),
      isA<StopNoExecution>(),
      reason: 'Execution identity is opaque and nonempty; admission must not trim it.',
    );
    expect(
      () => source.session.stopExecution(
        origin: source.stamp.copyWith(incarnation: 2),
        executionId: 'formerly-displayed',
      ),
      throwsA(isA<StudioFailure>()),
    );
    expect(fixture.owner.operations.observations.records.value, records);
    expect(fixture.budget.usage, budget);
  });
  test('execution and continuation replacements independently distinguish unchanged from explicit clear, without Turn inference', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    const point = ContinuationView(
      id: 'point',
      sourceTurnId: null,
      reason: null,
      createdAt: 7,
      claimed: false,
    );
    Future<void> change(
      int revision,
      ExecutionReplacement execution,
      ContinuationReplacement continuation,
    ) async {
      source.opening.feed.emit(
        ThreadExecutionFrame.data(
          deliverySequence: revision,
          event: ThreadExecutionEvent.change(
            stamp: source.stamp.copyWith(revision: revision),
            baseRevision: revision - 1,
            value: ThreadExecutionChange(
              status: null,
              turns: null,
              interactions: null,
              execution: execution,
              continuation: continuation,
              activity: const ActivityReplacement.unchanged(),
              storage: const StorageReplacement.unchanged(),
            ),
          ),
        ),
      );
      await source.opening.feed.acknowledged(revision);
    }

    await change(
      2,
      const ExecutionReplacement.unchanged(),
      const ContinuationReplacement.replace(value: point),
    );
    expect(source.session.execution.value.value!.execution!.id, 'execution-7');
    expect(source.session.execution.value.value!.continuation, point);
    await change(
      3,
      const ExecutionReplacement.unchanged(),
      const ContinuationReplacement.unchanged(),
    );
    expect(source.session.execution.value.value!.continuation, point);
    await change(
      4,
      const ExecutionReplacement.replace(value: null),
      const ContinuationReplacement.replace(value: null),
    );
    final value = source.session.execution.value.value!;
    expect(value.execution, isNull);
    expect(value.continuation, isNull);
    expect(
      value.activeTurn,
      isNotNull,
      reason: 'Old Turn summaries cannot recreate explicitly cleared canonical execution facts.',
    );
  });
  test('preparing Stop without a Turn shares its pending ticket after execution clears and settles only its original reply', () async {
    final fixture = await stopFixture();
    final source = await fixture.select(threadId: '原 会话');
    const execution = AgentExecution(
      id: ' 执行\n😀 ',
      phase: AgentExecutionPhase.preparing,
      turnId: null,
    );
    await source.deliver(
      active: null,
      status: ThreadStatus.idle,
      execution: execution,
    );
    final original = source.stamp;
    final action = await _dispatch(fixture, source, executionId: execution.id);
    expect(
      (source.session.stopExecution(
        origin: original,
        executionId: execution.id,
      ) as StopExecutionOperation).ticket,
      same(action.ticket),
    );
    await source.deliver(
      active: null,
      status: ThreadStatus.idle,
      execution: null,
    );
    final records = fixture.owner.operations.observations.records.value;
    final budget = List.of(fixture.budget.usage);
    expect(
      action.call.reply.isCompleted,
      isFalse,
      reason: 'The native Stop reply is still genuinely in flight.',
    );
    expect(
      (source.session.stopExecution(
        origin: original,
        executionId: execution.id,
      ) as StopExecutionOperation).ticket,
      same(action.ticket),
    );
    expect(fixture.owner.operations.observations.records.value, records);
    expect(fixture.budget.usage, budget);
    expect(
      (
        action.ticket.state.value.receipt,
        action.ticket.state.value.observed,
        action.ticket.state.value.effective,
        action.ticket.state.value.durable,
      ),
      (null, false, false, false),
    );
    expect(fixture.commands.interrupts.values, hasLength(1));
    final receipt = stopReceipt(action.ticket.id);
    action.call.reply.complete(_reply(action.call, receipt: receipt));
    await action.ticket.state.waitFor(
      (state) => state.effective || state.failurePhase != null,
    );
    expect(
      (
        action.ticket.state.value.receipt,
        action.ticket.state.value.observed,
        action.ticket.state.value.effective,
      ),
      (receipt, true, true),
    );
    expect(await action.ticket.result, isA<CommittedCommandResult<Unit>>());
    expect(action.ticket.state.value.durable, isFalse);
    expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
    expect(
      source.session.stopExecution(origin: original, executionId: execution.id),
      isA<StopNoExecution>(),
      reason:
          'A physically released Stop cannot be revived by its old callback.',
    );
    expect(
      fixture.owner.operations.observations.records.value,
      hasLength(records.length),
    );
    expect(fixture.commands.interrupts.values, hasLength(1));
  });

  for (final framesFirst in [true, false]) {
    for (final stopped in [true, false]) {
      test(
        'accepted Stop stays original after UI retirement (framesFirst=$framesFirst, stopped=$stopped)',
        () async {
          final fixture = await stopFixture();
          final source = await fixture.select();
          final action = await _dispatch(fixture, source);
          fixture.owner.deselect();
          if (framesFirst)
            await source.deliver(active: null, status: ThreadStatus.idle);
          action.call.reply.complete(_reply(action.call, stopped: stopped));
          await action.ticket.state.waitFor((state) => state.receipt != null);
          if (!framesFirst) {
            expect(action.ticket.state.value.effective, isFalse);
            for (final phase in AgentExecutionPhase.values) {
              await source.deliver(
                active: null,
                status: ThreadStatus.idle,
                execution: stopExecutionValue(7, phase: phase),
              );
              expect(
                (
                  action.ticket.state.value.observed,
                  action.ticket.state.value.effective,
                ),
                (false, false),
                reason: 'Even after a genuine receipt, Idle with the same execution is not terminal proof.',
              );
            }
            source.send(active: null, status: ThreadStatus.idle);
          }
          await action.ticket.state.waitFor((state) => state.effective);
          expect(
            await action.ticket.result,
            isA<CommittedCommandResult<Unit>>(),
          );
          expect(
            action.ticket.state.value.receipt!.disposition,
            stopped ? CommitDisposition.applied : CommitDisposition.noChange,
          );
          expect((await fixture.owner.repository.close()).complete, isTrue);
        },
      );
    }
  }

  test(
    'stale execution is rejected without dispatching the successor',
    () async {
      final fixture = await stopFixture();
      final source = await fixture.select();
      final old = source.stamp;
      await source.deliver(
        active: stopTurn(8),
        status: ThreadStatus.running,
        execution: stopExecutionValue(8),
      );
      expect(
        () => source.session.stopExecution(
          origin: old,
          executionId: 'execution-7',
        ),
        throwsA(
          isA<StudioFailure>().having(
            (error) => error.code,
            'stale execution',
            StudioFailureCode.superseded,
          ),
        ),
      );
      expect(fixture.commands.interrupts.values, isEmpty);
      expect(
        source.session.execution.value.value!.execution!.id,
        'execution-8',
      );
    },
  );

  test(
    'A-B-A replacement cannot borrow an old page callback or old Stop proof',
    () async {
      final fixture = await stopFixture();
      final original = await fixture.select(threadId: 'A');
      final action = await _dispatch(fixture, original);
      final oldOrigin = original.stamp;
      await fixture.select(threadId: 'B');
      final replacement = await fixture.select(threadId: 'A', incarnation: 2);
      expect(replacement.session, isNot(same(original.session)));
      expect(
        () => original.session.stopExecution(
          origin: oldOrigin,
          executionId: 'execution-7',
        ),
        throwsA(isA<StudioFailure>()),
      );
      expect(fixture.commands.interrupts.values, hasLength(1));
      action.call.reply.complete(_reply(action.call));
      original.send(active: null, status: ThreadStatus.idle);
      await action.ticket.state.waitFor((state) => state.effective);
      expect(
        replacement.session.execution.value.value!.execution!.id,
        'execution-7',
      );
      expect(replacement.session.execution.value.stamp!.incarnation, 2);
    },
  );

  test('ordinary post-dispatch failure remains Unknown even after original execution ends', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final action = await _dispatch(fixture, source);
    action.call.reply.completeError(_ordinaryFailure);
    expect(
      await action.ticket.result,
      isA<UnknownOutcomeCommandResult<Unit>>(),
    );
    expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
    await source.deliver(active: null, status: ThreadStatus.idle);
    expect(
      source.session.stopExecution(
        origin: source.stamp,
        executionId: action.call.executionId,
      ),
      isA<StopNoExecution>(),
    );
    expect(
      action.ticket.state.value.failurePhase,
      OperationFailurePhase.unknownOutcome,
    );
    expect(
      (action.ticket.state.value.observed, action.ticket.state.value.effective),
      (false, false),
    );
    fixture.retainedOperations.add((
      ticket: action.ticket,
      phase: OperationFailurePhase.unknownOutcome,
    ));
  });

  test(
    'known rejection is not Unknown and does not cancel another execution',
    () async {
      final fixture = await stopFixture();
      final source = await fixture.select();
      final action = await _dispatch(fixture, source);
      action.call.reply.completeError(
        const CommandDispatchFailure.rejected(failure: _ordinaryFailure),
      );
      expect(await action.ticket.result, isA<RejectedCommandResult<Unit>>());
      expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
      await source.deliver(active: null, status: ThreadStatus.idle);
      expect(
        source.session.stopExecution(
          origin: source.stamp,
          executionId: action.call.executionId,
        ),
        isA<StopNoExecution>(),
      );
      expect(
        action.ticket.state.value.failurePhase,
        OperationFailurePhase.rejected,
      );
      expect(fixture.commands.interrupts.values, hasLength(1));
    },
  );

  test('committed-but-unobserved retains its receipt without inventing source-closure proof', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final action = await _dispatch(fixture, source);
    final receipt = stopReceipt(action.ticket.id);
    action.call.reply.completeError(
      CommandDispatchFailure.committedButUnobserved(
        failure: _conversionFailure,
        receipt: receipt,
      ),
    );
    expect(await action.ticket.result, isA<SyncFailedCommandResult<Unit>>());
    source.opening.feed.emit(
      ThreadExecutionFrame.closed(
        identity: source.identity,
        reason: ThreadFeedClosedReason.runtimeStopped,
      ),
    );
    await action.ticket.state.waitFor((state) => state.evidenceError != null);
    expect(action.ticket.state.value.receipt, receipt);
    expect(action.ticket.state.value.effective, isFalse);
    fixture.retainedOperations.add((
      ticket: action.ticket,
      phase: OperationFailurePhase.syncFailed,
    ));
  });

  test('foreign-operation success receipt and confirmed conversion failure remain acknowledged sync failures after late terminal', () async {
    for (final foreignReceipt in [true, false]) {
      final fixture = await stopFixture();
      final source = await fixture.select();
      final action = await _dispatch(fixture, source);
      if (foreignReceipt) {
        action.call.reply.complete(
          _reply(
            action.call,
            receipt: stopReceipt(const OperationId('foreign-stop')),
          ),
        );
      } else {
        action.call.reply.completeError(
          const CommandDispatchFailure.confirmedWithoutUsableReceipt(
            failure: _conversionFailure,
          ),
        );
      }
      final original = await action.ticket.result;
      expect(original, isA<AcknowledgedSyncFailedCommandResult<Unit>>());
      final result = original as AcknowledgedSyncFailedCommandResult<Unit>;
      expect(result.value, const Unit());
      expect(result.error.code, StudioFailureCode.protocol);
      if (!foreignReceipt) expect(result.error, same(_conversionFailure));
      expect(
        (
          action.ticket.state.value.acknowledged,
          action.ticket.state.value.receipt,
          action.ticket.state.value.failurePhase,
        ),
        (true, null, OperationFailurePhase.syncFailed),
      );
      expect(
        action.ticket.state.value.isPending,
        isFalse,
        reason: 'A receiptless native acknowledgement settles the Registry permit without inventing observation.',
      );
      await source.deliver(active: null, status: ThreadStatus.idle);
      expect(
        (
          action.ticket.state.value.observed,
          action.ticket.state.value.effective,
          action.ticket.state.value.durable,
        ),
        (false, false, false),
      );
      expect(action.ticket.state.value.receipt, isNull);
      expect((await fixture.owner.repository.close()).complete, isTrue);
      expect((await fixture.owner.repository.retryCleanup()).complete, isTrue);
      expect(await action.ticket.result, same(original));
      expect(fixture.commands.interrupts.values, hasLength(1));
      expect(
        action.ticket.state.value.failurePhase,
        OperationFailurePhase.syncFailed,
      );
      expect(action.ticket.state.value.acknowledged, isTrue);
      expect(
        fixture.budget.usage,
        isEmpty,
        reason: 'All native dispatch/observation work joined; the accurate acknowledged result remains readable.',
      );
    }
  });

  test('close truly joins an entered native Stop and never resends', () async {
    final fixture = await stopFixture();
    final source = await fixture.select();
    final action = await _dispatch(fixture, source);
    var done = false;
    final closing = fixture.owner.repository.close().then((report) {
      done = true;
      return report;
    });
    expect(done, isFalse);
    final snapshot = await fixture.owner.repository.close(
      deadline: DateTime.now(),
    );
    expect(snapshot.complete, isFalse);
    expect(fixture.commands.interrupts.values, hasLength(1));
    action.call.reply.complete(_reply(action.call));
    await action.ticket.result;
    expect((await closing).complete, isTrue);
    expect(done, isTrue);
    fixture.retainedOperations.add((
      ticket: action.ticket,
      phase: OperationFailurePhase.syncFailed,
    ));
  });
}
