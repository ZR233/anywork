import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:test/test.dart';

import 'support/command_receipts_fixture.dart';

const _point = ContinuationView(id: 'original-point', sourceTurnId: null, reason: ContinuationReason.userStop, createdAt: 1, claimed: false);

Future<ReceiptFixture> _fixture() async {
  final fixture = ReceiptFixture();
  addTearDown(fixture.close);
  await fixture.establish();
  final opening = await fixture.owner.facets.executionOpened(0);
  await opening.feed.listened.future;
  opening.feed.emit(ThreadExecutionFrame.data(deliverySequence: 1,
    event: ThreadExecutionEvent.baseline(
      identity: ThreadFeedIdentity(feedId: opening.feed.feedId, runtimeEpoch: receiptEpoch,
        incarnation: 1, facet: ThreadFacet.execution, mode: opening.mode),
      stamp: receiptOrigin(ThreadFacet.execution, 1),
      value: const ThreadExecutionBaseline(status: ThreadStatus.idle, execution: null,
        continuation: _point, activeTurn: null, recentTerminalTurn: null,
        interactions: InteractionIndexHeader(reference: InteractionIndexRef(entry: 1, revision: 1), total: 0, pending: 0),
        activity: null, storage: null))));
  await opening.feed.acknowledged(1);
  return fixture;
}
OperationTicket<ContinueThreadReply> _continue(ReceiptFixture fixture, {OperationId? id, String point = 'original-point', int route = 1}) =>
    fixture.session.continueThread(origin: fixture.session.execution.value.stamp!, operationId: id,
      continuationId: point, expectedModelRouteRevision: route);
CommitReceipt _receipt(ContinueCall call) => commandReceipt(call.id, [
  receiptStamp('thread-input:${call.id.value}', 1),
  receiptStamp('thread-continuation:${call.continuationId}', 7),
], identity: true, effective: false);
ContinueThreadReply _reply(ContinueCall call) => ContinueThreadReply(threadId: call.threadId,
  inputId: call.id.value, continuationId: call.continuationId, cursor: 7, receipt: _receipt(call));
ContinuationOperationView _view(ContinueCall call, {bool durable = true, ContinuationOperationState state = const ContinuationOperationState.pending()}) =>
    ContinuationOperationView(threadId: call.threadId, operationId: call.id, inputId: call.id.value,
      continuationId: call.continuationId, acceptedSequence: 7, state: state, durable: durable, receipt: _receipt(call));

void main() {
  test('duplicate continue shares the original ticket/future, freezes the route and proves durable Pending through its named read', () async {
    final fixture = await _fixture();
    final ticket = _continue(fixture);
    final call = await fixture.commands.continuations.at(0);
    final repeated = _continue(fixture);
    expect(repeated, same(ticket));
    expect(repeated.result, same(ticket.result));
    expect((call.threadId, call.continuationId, call.routeRevision), ('thread', 'original-point', 1));
    expect(() => _continue(fixture, id: ticket.id, point: 'other-point'), throwsA(isA<StudioFailure>()));
    await fixture.publishConfiguration(2, route: 2);
    call.reply.complete(_reply(call));
    final read = await fixture.commands.continuationReads.at(0);
    expect((read.threadId, read.id), ('thread', ticket.id));
    expect(ticket.state.value.observed, isFalse);
    final firstQuery = fixture.session.readContinuationOperation(ticket.id);
    read.reply.complete(_view(call));
    await firstQuery;
    expect(await ticket.result, isA<CommittedCommandResult<ContinueThreadReply>>());
    await ticket.state.waitFor((state) => state.durable);
    expect((ticket.state.value.observed, ticket.state.value.effective, ticket.state.value.durable), (true, false, true));
    expect(fixture.commands.continuations.values, hasLength(1));
    expect(call.routeRevision, 1, reason: 'A later route publication cannot mutate the original control input.');
    final query = fixture.session.readContinuationOperation(ticket.id);
    (await fixture.commands.continuationReads.at(1)).reply.complete(_view(call, state: const ContinuationOperationState.consumed(turnId: 'actual-admitted-turn')));
    expect((await query)!.state, const ContinuationOperationState.consumed(turnId: 'actual-admitted-turn'));
    expect(ticket.state.value.effective, isTrue);
  });

  test('Unknown continue is queried under the same operation, not re-sent or rebound to a current route', () async {
    final fixture = await _fixture();
    final ticket = _continue(fixture);
    final call = await fixture.commands.continuations.at(0);
    call.reply.completeError(const CommandDispatchFailure.unknownOutcome(failure: receiptConflict));
    expect(await ticket.result, isA<UnknownOutcomeCommandResult<ContinueThreadReply>>());
    final initial = await fixture.commands.continuationReads.at(0);
    final firstQuery = fixture.session.readContinuationOperation(ticket.id);
    initial.reply.complete(null);
    await firstQuery;
    expect(_continue(fixture, id: ticket.id), same(ticket));
    final querying = fixture.session.readContinuationOperation(ticket.id);
    final read = await fixture.commands.continuationReads.at(1);
    expect(read.id, ticket.id);
    read.reply.complete(_view(call, state: const ContinuationOperationState.discarded()));
    await querying;
    expect(ticket.state.value.failurePhase, isNull);
    expect((ticket.state.value.observed, ticket.state.value.effective, ticket.state.value.durable), (true, false, true));
    expect(fixture.commands.continuations.values, hasLength(1));
  });

  test('Busy after accepted save retains the real committed receipt rather than becoming Rejected', () async {
    final fixture = await _fixture();
    final ticket = _continue(fixture);
    final call = await fixture.commands.continuations.at(0);
    const busy = StudioFailure(code: StudioFailureCode.busy, message: 'Accepted, waiting for storage',
      retryable: true, correlationId: 'continuation-awaiting-storage');
    call.reply.completeError(CommandDispatchFailure.committedButUnobserved(failure: busy, receipt: _receipt(call)));
    expect(await ticket.result, isA<SyncFailedCommandResult<ContinueThreadReply>>());
    expect(ticket.state.value.failurePhase, OperationFailurePhase.syncFailed);
    expect(ticket.state.value.receipt, _receipt(call));
    (await fixture.commands.continuationReads.at(0)).reply.complete(_view(call, state: const ContinuationOperationState.discarded()));
    await ticket.state.waitFor((state) => state.durable);
    expect(ticket.state.value.failurePhase, isNot(OperationFailurePhase.rejected));
    expect(fixture.commands.continuations.values, hasLength(1));
  });

  test('native accepted Busy without a receipt stays acknowledged and recovers only the original operation', () async {
    final fixture = await _fixture();
    final ticket = _continue(fixture);
    final call = await fixture.commands.continuations.at(0);
    const acceptedBusy = StudioFailure(code: StudioFailureCode.busy, message: 'The control input was accepted while saving',
      retryable: true, correlationId: 'native-control-accepted', details: StudioFailureDetails.reason(reason: 'executionInProgress'));
    // Adapter classification of Control/ContinuationAccepted{accepted:true}
    // with this exact original Thread/operation; there is no invented receipt.
    call.reply.completeError(const CommandDispatchFailure.confirmedWithoutUsableReceipt(failure: acceptedBusy));
    expect(await ticket.result, isA<AcknowledgedSyncFailedCommandResult<ContinueThreadReply>>());
    expect(ticket.state.value.acknowledged, isTrue);
    expect(ticket.state.value.receipt, isNull);
    final read = await fixture.commands.continuationReads.at(0);
    expect((read.threadId, read.id), (call.threadId, call.id));
    read.reply.complete(_view(call));
    await ticket.state.waitFor((state) => state.durable);
    expect((ticket.state.value.observed, ticket.state.value.effective, ticket.state.value.durable), (true, false, true));
    expect(ticket.state.value.failurePhase, isNot(OperationFailurePhase.rejected));
    expect(_continue(fixture, id: ticket.id), same(ticket));
    expect(fixture.commands.continuations.values, hasLength(1));
  });

  test('close joins the actual continuation query, not merely its accepted result', () async {
    final fixture = await _fixture();
    final ticket = _continue(fixture);
    final call = await fixture.commands.continuations.at(0);
    call.reply.complete(_reply(call));
    final read = await fixture.commands.continuationReads.at(0);
    var joined = false;
    final closing = fixture.owner.repository.close().then((report) { joined = true; return report; });
    expect(joined, isFalse);
    read.reply.complete(_view(call));
    await ticket.result;
    expect((await closing).complete, isTrue);
    expect(joined, isTrue);
    expect(fixture.commands.continuations.values, hasLength(1));
  });

  for (final nativeOutcome in ['receipt', 'acknowledged', 'unknown']) {
    for (final queryFails in [false, true]) {
      test('close before dispatch reply keeps original settlement ($nativeOutcome, queryFails=$queryFails)', () async {
        final fixture = await _fixture();
        final ticket = _continue(fixture);
        final call = await fixture.commands.continuations.at(0);
        expect(fixture.owner.budget.used(ResourceKind.pendingOperation), 2);
        var closed = false;
        final closing = fixture.owner.repository.close().then((report) { closed = true; return report; });
        expect(closed, isFalse);
        if (nativeOutcome == 'receipt') {
          call.reply.complete(_reply(call));
        } else if (nativeOutcome == 'acknowledged') {
          call.reply.completeError(const CommandDispatchFailure.confirmedWithoutUsableReceipt(failure: receiptConflict));
        } else {
          call.reply.completeError(const CommandDispatchFailure.unknownOutcome(failure: receiptConflict));
}
        final read = await fixture.commands.continuationReads.at(0);
        expect((read.threadId, read.id), (call.threadId, call.id));
        expect(fixture.owner.budget.used(ResourceKind.pendingOperation), 1, reason: 'Settlement borrows the original owner, not a new business-operation permit.');
        expect(closed, isFalse, reason: 'Close cannot finish while the real original read is held.');
        await expectLater(fixture.session.readContinuationOperation(ticket.id), throwsA(isA<StudioFailure>().having((error) => error.code, 'new public read after seal', StudioFailureCode.cancelled)));
        if (queryFails) {
          read.reply.completeError(receiptConflict);
        } else {
          read.reply.complete(_view(call));
        }
        final first = await closing;
        expect(closed, isTrue);
        if (queryFails) {
          expect(first.complete, isFalse);
          expect(first.unresolved.expand((resource) => resource.issues).any((issue) => issue.recovery == CleanupRecovery.retryClose), isTrue);
          expect(fixture.owner.budget.used(ResourceKind.pendingOperation), 1);
          var retried = false;
          final retry = fixture.owner.repository.retryCleanup().then((report) { retried = true; return report; });
          final second = await fixture.commands.continuationReads.at(1);
          expect((second.threadId, second.id), (call.threadId, call.id));
          expect(retried, isFalse);
          second.reply.complete(_view(call));
          expect((await retry).complete, isTrue);
          expect(fixture.commands.continuationReads.values, hasLength(2));
        } else {
          expect(first.complete, isTrue);
          expect(fixture.commands.continuationReads.values, hasLength(1));
        }
        expect((ticket.state.value.observed, ticket.state.value.effective, ticket.state.value.durable), (true, false, true));
        expect(fixture.commands.continuations.values, hasLength(1));
        expect(fixture.commands.continuations.values.single.id, ticket.id);
        expect(fixture.owner.budget.usage, isEmpty);
      });
    }
  }

  test('not-yet-visible and nondurable Pending settlement retain a retryable original owner until actual durability', () async {
    final fixture = await _fixture();
    final ticket = _continue(fixture);
    final call = await fixture.commands.continuations.at(0);
    final closing = fixture.owner.repository.close();
    call.reply.completeError(const CommandDispatchFailure.unknownOutcome(failure: receiptConflict));
    (await fixture.commands.continuationReads.at(0)).reply.complete(null);
    expect((await closing).complete, isFalse);
    final firstRetry = fixture.owner.repository.retryCleanup();
    final pending = await fixture.commands.continuationReads.at(1);
    expect(pending.id, ticket.id);
    pending.reply.complete(_view(call, durable: false));
    expect((await firstRetry).complete, isFalse);
    expect((ticket.state.value.effective, ticket.state.value.durable), (false, false));
    final secondRetry = fixture.owner.repository.retryCleanup();
    final durable = await fixture.commands.continuationReads.at(2);
    expect((durable.threadId, durable.id), (call.threadId, ticket.id));
    durable.reply.complete(_view(call));
    expect((await secondRetry).complete, isTrue);
    expect((ticket.state.value.effective, ticket.state.value.durable), (false, true));
    expect(fixture.commands.continuations.values, hasLength(1));
    expect(fixture.owner.budget.usage, isEmpty);
  });
}
