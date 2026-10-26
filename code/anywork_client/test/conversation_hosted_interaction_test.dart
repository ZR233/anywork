import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:test/test.dart';

import 'support/command_receipts_fixture.dart';
import 'support/profile_native_pin.dart';

const _reference = InteractionReadRef(entry: 3, revision: 1);
const _brief = InteractionBrief(reference: _reference, revision: 1, kind: InteractionKind.userInput,
  status: InteractionStatus.pending, createdAt: 1, updatedAt: 1);
ReadScopeIdentity _scope(String id, int revision) => ReadScopeIdentity(scopeId: id,
  runtimeEpoch: receiptEpoch, incarnation: 1, sourceRevision: revision);
final class _IndexPin extends ProfileNativePin implements InteractionIndexReadConnection {
  _IndexPin() : super('host-index');
  @override
  Future<InteractionIndexReadHeader> header() async => InteractionIndexReadHeader(scope: _scope(id, 1), total: 1, pending: 1);
  @override
  Future<InteractionBriefPage> entries({int offset = 0, int limit = 32}) async =>
      InteractionBriefPage(scope: _scope(id, 1), offset: 0, total: 1, items: [_brief], nextOffset: null);
}
Future<ReceiptFixture> _fixture({InteractionPurposeRead purpose = const InteractionPurposeRead.general(),
  Future<void> Function(InteractionReadRef, ThreadFacetStamp)? beforeDetail,
  bool registerTeardown = true,
}) async {
  final fixture = ReceiptFixture();
  if (registerTeardown) addTearDown(fixture.close);
  await fixture.establish();
  fixture.owner.facets.interactionIndexOpen = (thread, reference, origin) async {
    expect(thread, 'thread');
    expect(origin, receiptOrigin(ThreadFacet.execution, 1));
    return _IndexPin();
  };
  fixture.owner.facets.interactionOpen = (thread, reference, origin) async {
    expect(thread, 'thread', reason: 'The read capability belongs to the host, not a selected child.');
    if (beforeDetail != null) await beforeDetail(reference, origin);
    return ReceiptInteractionPin('child-question', reference.revision, origin, targetThreadId: 'child', purpose: purpose);
  };
  fixture.owner.facets.interactionResolve = (thread, id, revision, origin) async => _reference.copyWith(revision: revision);
  final opening = await fixture.owner.facets.executionOpened(0);
  await opening.feed.listened.future;
  opening.feed.emit(ThreadExecutionFrame.data(deliverySequence: 1, event: ThreadExecutionEvent.baseline(
    identity: ThreadFeedIdentity(feedId: opening.feed.feedId, runtimeEpoch: receiptEpoch, incarnation: 1,
      facet: ThreadFacet.execution, mode: opening.mode), stamp: receiptOrigin(ThreadFacet.execution, 1),
    value: const ThreadExecutionBaseline(status: ThreadStatus.waitingInteraction,
      activeTurn: null, recentTerminalTurn: null, activity: null, storage: null,
      interactions: InteractionIndexHeader(reference: InteractionIndexRef(entry: 1, revision: 1), total: 1, pending: 1)))));
  await opening.feed.acknowledged(1);
  await fixture.session.loadInteractionsPage();
  return fixture;
}

void main() {
  test('hosted reference keeps original child target while the ordinary same-Session guard stays intact', () async {
    final readEntered = Completer<void>();
    final readReply = Completer<void>();
    final fixture = await _fixture(beforeDetail: (reference, origin) async {
      if (reference.revision != 2) return;
      expect((reference.entry, origin), (3, receiptOrigin(ThreadFacet.execution, 2)));
      readEntered.complete();
      await readReply.future;
    });
    addTearDown(() { if (!readReply.isCompleted) readReply.complete(); });
    final item = fixture.session.interactions.value.current!.items.single;
    expect((item.interactionId, item.targetThreadId, item.reference), ('child-question', 'child', _reference));
    final origin = fixture.session.execution.value.stamp!;
    final resolution = UserInputResolutionCommand(answers: []);
    final ordinary = fixture.session.respondInteraction(origin: origin, interactionId: item.interactionId,
      expectedInteractionRevision: 1, resolution: resolution);
    expect(await ordinary.result, isA<RejectedCommandResult<InteractionCommandReply>>());
    expect(fixture.commands.interactions.values, isEmpty, reason: 'Knowing an arbitrary interaction ID is not a hosted capability.');
    final scope = await fixture.session.openHostedInteraction(origin: origin, reference: item.reference, targetThreadId: 'child');
    expect((await scope.header()).threadId, const ReadText.inline(text: 'child'));
    expect((await scope.close()).complete, isTrue);
    final ticket = fixture.session.respondHostedInteraction(origin: origin, reference: item.reference,
      targetThreadId: 'child', interactionId: item.interactionId, expectedInteractionRevision: 1, resolution: resolution);
    final call = await fixture.commands.interactions.at(0);
    expect((call.hostThreadId, call.interactionId, call.revision, call.id),
      ('thread', 'child-question', 1, ticket.id));
    call.reply.complete(receiptInteractionReply(call, targetThreadId: 'child'));
    await ticket.state.waitFor((state) => state.receipt != null);
    expect(fixture.session.interactions.value.current!.index.reference.revision, 1);
    expect(readEntered.isCompleted, isFalse, reason: 'The new native locator is not exposed at the old index/source revision.');
    final source = fixture.owner.facets.execution.single;
    source.feed.emit(ThreadExecutionFrame.data(deliverySequence: 2,
      event: ThreadExecutionEvent.change(stamp: receiptOrigin(ThreadFacet.execution, 2), baseRevision: 1,
        value: ThreadExecutionChange(status: ThreadStatus.idle, turns: null,
          interactions: InteractionDelta(baseIndexRevision: 1,
            index: const InteractionIndexHeader(reference: InteractionIndexRef(entry: 1, revision: 2), total: 0, pending: 0),
            upserted: [], removedEntries: [3], terminalFacts: [_brief.copyWith(
              reference: const InteractionReadRef(entry: 3, revision: 2), revision: 2, status: InteractionStatus.resolved, updatedAt: 2)]),
          activity: const ActivityReplacement.unchanged(), storage: const StorageReplacement.unchanged()))));
    await source.feed.acknowledged(2);
    await readEntered.future;
    expect(ticket.state.value.observed, isFalse, reason: 'A matching reliable fact only grants the exact read; the reply DTO is not read evidence.');
    expect(fixture.session.interactions.value.current!.items, isEmpty);
    expect(() => fixture.session.openHostedInteraction(origin: receiptOrigin(ThreadFacet.execution, 2),
      reference: const InteractionReadRef(entry: 3, revision: 2), targetThreadId: 'child'), throwsA(isA<StudioFailure>()));
    readReply.complete();
    expect(await ticket.result, isA<CommittedCommandResult<InteractionCommandReply>>());
    expect(fixture.owner.repository.existingSession('child'), isNull);
    expect(fixture.owner.repository.active.value, same(fixture.session));
  });

  test('hosted child Plan remains diagnostic and cannot be resolved from the root', () async {
    final fixture = await _fixture(purpose: const InteractionPurposeRead.planConfirmation(expectedRevision: 1,
      operationId: ReadText.inline(text: 'plan-operation'), argumentHash: ReadText.inline(text: 'arguments'), planHash: ReadText.inline(text: 'plan')));
    final ticket = fixture.session.respondHostedInteraction(origin: fixture.session.execution.value.stamp!,
      reference: _reference, targetThreadId: 'child', interactionId: 'child-question', expectedInteractionRevision: 1,
      resolution: UserInputResolutionCommand(answers: []));
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<InteractionCommandReply>>());
    expect((result as RejectedCommandResult<InteractionCommandReply>).error.code, StudioFailureCode.permissionDenied);
    expect(fixture.commands.interactions.values, isEmpty);
    expect(fixture.owner.repository.existingSession('child'), isNull);
  });

  test('closing cancels the original hosted revision wait without a new read, resend or fabricated observation', () async {
    var upgradedReads = 0;
    final fixture = await _fixture(registerTeardown: false, beforeDetail: (reference, _) async {
      if (reference.revision == 2) upgradedReads++;
    });
    addTearDown(() async { await fixture.owner.repository.close(); });
    final ticket = fixture.session.respondHostedInteraction(origin: fixture.session.execution.value.stamp!,
      reference: _reference, targetThreadId: 'child', interactionId: 'child-question', expectedInteractionRevision: 1,
      resolution: UserInputResolutionCommand(answers: []));
    final call = await fixture.commands.interactions.at(0);
    call.reply.complete(receiptInteractionReply(call, targetThreadId: 'child'));
    await ticket.state.waitFor((state) => state.receipt != null);
    final report = await fixture.owner.repository.close();
    expect(report.complete, isFalse, reason: 'The real receipt remains committed-but-unobserved, not successful.');
    expect(await ticket.result, isA<SyncFailedCommandResult<InteractionCommandReply>>());
    expect((ticket.state.value.observed, ticket.state.value.effective), (false, true));
    expect(upgradedReads, 0);
    expect(fixture.commands.interactions.values, hasLength(1));
  });
}
