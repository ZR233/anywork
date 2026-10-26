import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/composer_environment.dart';
import 'support/selector_conversation_port.dart';
import 'support/selector_environment.dart';

Future<({SelectorEnvironment env, ConversationSession session})> _open(ThreadExecutionBaseline initial) async {
  final env = SelectorEnvironment();
  env.conversationPort.initialExecution = initial;
  addTearDown(env.close);
  await env.establish(catalog: false);
  await env.selectThread(composerThreadId);
  final session = env.conversations.existingSession(composerThreadId)!;
  await waitLatest(session.execution, (value) => value.sync.phase == FacetSyncPhase.ready);
  await waitLatest(session.configuration, (value) => value.sync.phase == FacetSyncPhase.ready);
  return (env: env, session: session);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NoExecution is synchronous: no native request, no operation mutation, and stale sources still reject', () async {
    final fixture = await _open(selectorExecution());
    final stamp = fixture.session.execution.value.stamp!;
    final usage = List.of(fixture.env.budget.usage);
    final admission = fixture.session.stopExecution(origin: stamp, executionId: 'already-finished');
    expect(admission, isA<StopNoExecution>().having((value) => value.threadId, 'thread', composerThreadId));
    expect(fixture.env.commands.interrupts.values, isEmpty);
    expect(fixture.env.budget.usage, usage, reason: 'No ticket or mutation is registered');
    expect(() => fixture.session.stopExecution(origin: stamp.copyWith(incarnation: stamp.incarnation + 1), executionId: 'already-finished'), throwsA(isA<StudioFailure>()));
    expect(() => fixture.session.stopExecution(origin: stamp.copyWith(revision: stamp.revision + 1), executionId: 'already-finished'), throwsA(isA<StudioFailure>()));
    expect(fixture.env.commands.interrupts.values, isEmpty);
  });

  test('preparing/awaiting execution without a Turn can stop; reply, observed terminal and effect are independent', () async {
    for (final phase in const [AgentExecutionPhase.preparing, AgentExecutionPhase.awaitingStorage, AgentExecutionPhase.awaitingAdmission]) {
      final fixture = await _open(selectorExecution(execution: AgentExecution(id: 'execution-$phase', phase: phase, turnId: null)));
      final origin = fixture.session.execution.value.stamp!;
      expect(() => fixture.session.stopExecution(origin: origin, executionId: 'foreign-execution'), throwsA(isA<StudioFailure>()));
      expect(fixture.env.commands.interrupts.values, isEmpty);
      final admission = fixture.session.stopExecution(origin: origin, executionId: 'execution-$phase') as StopExecutionOperation;
      final call = await fixture.env.commands.interrupts.at(0);
      expect((call.threadId, call.executionId), (composerThreadId, 'execution-$phase'));
      // The observer wins first. Idle is not accepted and cannot complete the ticket.
      await fixture.env.conversationPort.publishExecution(selectorExecution());
      expect(admission.ticket.state.value.observed, isFalse);
      expect(admission.ticket.state.value.receipt, isNull);
      final retained = fixture.session.stopExecution(origin: origin, executionId: 'execution-$phase') as StopExecutionOperation;
      expect(retained.ticket.id, admission.ticket.id,
        reason: '同owner的较新完整来源已无execution时，原未释放票据仍优先于NoExecution');
      expect(fixture.env.commands.interrupts.values, hasLength(1));
      call.reply.complete(StopExecutionReply(threadId: call.threadId, executionId: call.executionId, stopped: true, receipt: composerReceipt(call.operationId)));
      final result = await admission.ticket.result;
      expect(result, isA<CommittedCommandResult<Unit>>());
      expect(admission.ticket.state.value.observed, isTrue);
      expect(admission.ticket.state.value.effective, isTrue);
      expect(admission.ticket.state.value.durable, isFalse);
      expect(fixture.env.commands.interrupts.values, hasLength(1));
      expect(fixture.env.conversationPort.turn, isNull, reason: 'Stop does not require or manufacture a Turn read');
    }
  });

  test('accepted continuation queries exactly its operation, Pending is not consumed by Idle or durability', () async {
    final fixture = await _open(selectorExecution(continuation: composerContinuation));
    final ticket = fixture.session.continueThread(origin: fixture.session.execution.value.stamp!, continuationId: composerContinuation.id, expectedModelRouteRevision: 8);
    final operation = ticket.id;
    final call = await fixture.env.commands.continues.at(0);
    expect((call.threadId, call.operationId, call.continuationId, call.routeRevision), (composerThreadId, operation, composerContinuation.id, 8));
    var nativeView = composerContinuationView(call);
    fixture.env.commands.continuationQuery = (thread, id) async {
      expect((thread, id), (composerThreadId, operation));
      return nativeView;
    };
    call.reply.complete(ContinueThreadReply(threadId: call.threadId, inputId: operation.value, continuationId: call.continuationId, cursor: 7, receipt: composerReceipt(operation)));
    await ticket.state.waitFor((state) => state.receipt != null);
    await fixture.env.conversationPort.publishExecution(selectorExecution());
    expect(ticket.state.value.observed, isFalse, reason: 'A feed without the point is not typed result evidence');
    final pending = await fixture.session.readContinuationOperation(operation);
    expect(pending!.state, isA<PendingContinuation>());
    expect(ticket.state.value.observed, isTrue);
    expect(ticket.state.value.durable, isTrue);
    expect(ticket.state.value.effective, isFalse, reason: 'Durable Pending has not entered a Turn');
    nativeView = composerContinuationView(call, state: const ContinuationOperationState.consumed(turnId: 'new-turn'));
    final consumed = await fixture.session.readContinuationOperation(operation);
    expect(consumed!.state, const ContinuationOperationState.consumed(turnId: 'new-turn'));
    expect(ticket.state.value.effective, isTrue);
    expect(fixture.env.commands.continues.values, hasLength(1));
    expect(fixture.env.commands.prompts.values, isEmpty);
    expect(fixture.env.commands.acceptances.values, isEmpty, reason: 'Ordinary input reads never settle a control continuation');
    await ticket.result;
  });

  test('the same operation with a different continuation or route conflicts, not another native mutation', () async {
    final fixture = await _open(selectorExecution(continuation: composerContinuation));
    final origin = fixture.session.execution.value.stamp!;
    final ticket = fixture.session.continueThread(origin: origin, continuationId: composerContinuation.id, expectedModelRouteRevision: 8);
    final operation = ticket.id;
    final call = await fixture.env.commands.continues.at(0);
    expect(() => fixture.session.continueThread(origin: origin, operationId: operation, continuationId: 'other-point', expectedModelRouteRevision: 8), throwsA(isA<StudioFailure>()));
    expect(() => fixture.session.continueThread(origin: origin, operationId: operation, continuationId: composerContinuation.id, expectedModelRouteRevision: 9), throwsA(isA<StudioFailure>()));
    fixture.env.commands.continuationQuery = (thread, id) async => composerContinuationView(call, state: const ContinuationOperationState.discarded());
    call.reply.complete(ContinueThreadReply(threadId: call.threadId, inputId: operation.value, continuationId: call.continuationId, cursor: 7, receipt: composerReceipt(operation)));
    await ticket.state.waitFor((state) => state.receipt != null);
    final discarded = await fixture.session.readContinuationOperation(operation);
    expect(discarded!.state, isA<DiscardedContinuation>());
    expect(ticket.state.value.effective, isFalse);
    expect(fixture.env.commands.continues.values, hasLength(1));
  });

  test('Unknown continuation is not resent: only an exact operation read recovers real acceptance', () async {
    final fixture = await _open(selectorExecution(continuation: composerContinuation));
    final origin = fixture.session.execution.value.stamp!;
    final ticket = fixture.session.continueThread(origin: origin, continuationId: composerContinuation.id, expectedModelRouteRevision: 8);
    final operation = ticket.id;
    final call = await fixture.env.commands.continues.at(0);
    call.reply.completeError(StateError('response lost after native dispatch'));
    expect(await ticket.result, isA<UnknownOutcomeCommandResult<ContinueThreadReply>>());
    final repeated = fixture.session.continueThread(origin: origin, operationId: operation, continuationId: composerContinuation.id, expectedModelRouteRevision: 8);
    expect(repeated.id, operation);
    expect(fixture.env.commands.continues.values, hasLength(1));
    final queried = Completer<void>();
    fixture.env.commands.continuationQuery = (thread, id) async {
      expect((thread, id), (composerThreadId, operation));
      queried.complete();
      return composerContinuationView(call, state: const ContinuationOperationState.consumed(turnId: 'recovered-turn'));
    };
    final reading = fixture.session.readContinuationOperation(operation);
    await queried.future;
    final recovered = await reading;
    expect(recovered!.state, const ContinuationOperationState.consumed(turnId: 'recovered-turn'));
    expect((ticket.state.value.observed, ticket.state.value.effective, ticket.state.value.durable), (true, true, true));
    expect(fixture.env.commands.continues.values, hasLength(1));
  });
}
