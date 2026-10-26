import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:test/test.dart';

import 'support/command_receipts_fixture.dart';
import 'support/conversation_stop_fixture.dart';
import 'support/conversation_stop_native.dart';

Future<ReceiptFixture> _fixture() async {
  final fixture = ReceiptFixture();
  addTearDown(fixture.close);
  await fixture.establish();
  return fixture;
}

OperationTicket<ThreadModelRouteCommandReply> _route(
  ReceiptFixture fixture, {
  String model = 'alpha',
  OperationId? operationId,
  int? expectedRouteRevision,
  int? expectedSettingsRevision,
}) => fixture.session.setThreadModelRoute(
  origin: fixture.session.configuration.value.stamp!,
  operationId: operationId,
  accountId: 'account',
  modelId: model,
  expectedModelRouteRevision:
      expectedRouteRevision ??
      fixture.session.configuration.value.value!.modelRoute!.revision,
  expectedSettingsRevision:
      expectedSettingsRevision ??
      fixture.session.configuration.value.value!.sources.settingsRevision,
);

Future<void> _observed(OperationObservation operation) =>
    operation.state.waitFor((state) => state.observed).then((_) {});

Future<void> _assertCanonicalModel(ReceiptFixture fixture, String model) async {
  final source = fixture.session.configuration.value;
  final scope = await fixture.session.openConfiguration(
    source.value!.details,
    origin: source.stamp!,
  );
  try {
    expect((await scope.header()).route!.modelId, ReadText.inline(text: model));
  } finally {
    expect((await scope.close()).complete, isTrue);
  }
}

final _resolution = UserInputResolutionCommand(
  answers: [
    UserInputAnswerCommand(questionId: 'question', answers: ['Continue']),
  ],
);
OperationTicket<InteractionCommandReply> _respond(
  ReceiptFixture fixture,
  String id,
) => fixture.session.respondInteraction(
  origin: fixture.session.execution.value.stamp!,
  interactionId: id,
  expectedInteractionRevision: 1,
  resolution: _resolution,
);

void main() {
  test('manual compaction waits for its owner, rejects duplicate dispatch and exposes failure', () async {
    final fixture = await _fixture();
    final origin = fixture.session.context.value.stamp!;
    final pending = fixture.session.compactThread(origin: origin);
    final initial = await fixture.commands.compactions.at(0);
    expect(pending.state.value.isPending, isTrue);
    expect(
      () => fixture.session.compactThread(origin: origin),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'duplicate dispatch',
          StudioFailureCode.conflict,
        ),
      ),
    );
    expect(fixture.commands.compactions.values, hasLength(1));
    const refused = StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'compression failed',
      retryable: false,
      correlationId: 'compact-refused',
    );
    initial.reply.completeError(
      const CommandDispatchFailure.rejected(failure: refused),
    );
    expect(
      await pending.result,
      const CommandResult<Unit>.rejected(error: refused),
    );
    expect(pending.state.value.failurePhase, OperationFailurePhase.rejected);
    final retry = fixture.session.compactThread(origin: origin);
    final next = await fixture.commands.compactions.at(1);
    expect(fixture.commands.compactions.values, hasLength(2));
    expect(next.threadId, 'thread');
    next.reply.complete();
    expect(
      await retry.result,
      const CommandResult<Unit>.acknowledged(value: Unit()),
    );
    expect(retry.state.value.isPending, isFalse);
  });

  test('route conflict refresh replaces only its configuration binding and preserves Timeline', () async {
    final fixture = await _fixture();
    await fixture.publishConfiguration(41, route: 3);
    final first = _route(fixture);
    final initial = await fixture.commands.routes.at(0);
    initial.reply.completeError(
      const CommandDispatchFailure.rejected(failure: receiptConflict),
    );
    expect(
      await first.result,
      const CommandResult<ThreadModelRouteCommandReply>.rejected(
        error: receiptConflict,
      ),
    );
    final old = fixture.configuration;
    old.feed.emit(
      ThreadConfigurationFrame.resyncRequired(
        identity: ThreadFeedIdentity(
          feedId: old.feed.feedId,
          runtimeEpoch: receiptEpoch,
          incarnation: 1,
          facet: ThreadFacet.configuration,
          mode: old.mode,
        ),
        reason: ThreadResyncReason.revisionGap,
      ),
    );
    final replacement = await fixture.owner.facets.configurationOpened(1);
    await replacement.feed.listened.future;
    expect(fixture.owner.facets.configuration, hasLength(2));
    expect(fixture.session.configuration.value.stamp!.revision, 41);
    expect(
      fixture.commands.routes.values,
      hasLength(1),
      reason: 'await the replacement baseline; no automatic resend',
    );
    fixture.configuration = replacement;
    fixture.sequence = 0;
    await fixture.publishConfiguration(7, route: 4, settings: 2);
    final retry = _route(fixture, operationId: first.id);
    final next = await fixture.commands.routes.at(1);
    expect(fixture.commands.routes.values, hasLength(2));
    expect(next.id, initial.id);
    expect(next.routeRevision, 4);
    expect(next.settingsRevision, 2);
    fixture.owner.operations.observe(receiptStamp('settings', 2));
    next.reply.complete(
      receiptRouteReply(next, 4, disposition: CommitDisposition.noChange),
    );
    expect(
      await retry.result,
      isA<CommittedCommandResult<ThreadModelRouteCommandReply>>(),
    );
    await _observed(retry);
    await fixture.publishConfiguration(8, route: 4, settings: 2);
    expect(fixture.session.configuration.value.stamp!.revision, 8);
    expect(fixture.session.configuration.value.value!.modelRoute!.revision, 4);
    await _assertCanonicalModel(fixture, 'alpha');
    expect(
      fixture.session.configuration.value.sync.phase,
      FacetSyncPhase.ready,
    );
    expect((await fixture.session.timeline.ready).baseline.version, 300);
    expect(fixture.owner.timeline.requests, hasLength(1));
    expect(
      fixture.session.timeline.state.value.phase,
      TimelineConnectionPhase.ready,
    );
  });

  for (final closeRepository in [false, true]) {
    test(
      'route refresh baseline wait ends on ${closeRepository ? 'Repository close' : 'Session retire'} while cleanup stays owned',
      () async {
        final fixture = await _fixture();
        final first = _route(fixture);
        final call = await fixture.commands.routes.at(0);
        call.reply.completeError(
          const CommandDispatchFailure.rejected(failure: receiptConflict),
        );
        final rejected = await first.result;
        expect(
          rejected,
          const CommandResult<ThreadModelRouteCommandReply>.rejected(
            error: receiptConflict,
          ),
        );
        final old = fixture.configuration;
        old.feed.emit(
          ThreadConfigurationFrame.resyncRequired(
            identity: ThreadFeedIdentity(
              feedId: old.feed.feedId,
              runtimeEpoch: receiptEpoch,
              incarnation: 1,
              facet: ThreadFacet.configuration,
              mode: old.mode,
            ),
            reason: ThreadResyncReason.revisionGap,
          ),
        );
        final replacement = await fixture.owner.facets.configurationOpened(1);
        await replacement.feed.listened.future;
        final cleanup = Completer<FeedCloseReport>();
        replacement.feed.closeReceipt = cleanup;
        final closing = closeRepository
            ? fixture.owner.repository.close(deadline: DateTime.utc(2000))
            : fixture.owner.demand.retire(
                'thread',
                deadline: DateTime.utc(2000),
              );
        await replacement.feed.closeStarted.future;
        expect(await first.result, same(rejected));
        expect(
          fixture.commands.routes.values,
          hasLength(1),
          reason: 'Retired observation cannot replay even a known conflict',
        );
        expect(
          fixture.owner.budget.usage
              .where((item) => item.owner.startsWith('configuration:thread'))
              .single
              .phase,
          ResourcePhase.retiring,
        );
        expect((await closing).complete, isFalse);
        cleanup.complete(
          FeedCloseReport(
            feedId: replacement.feed.feedId,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
        expect(
          (await fixture.owner.repository.retryCleanup()).complete,
          isTrue,
        );
        expect(
          fixture.owner.budget.usage.where(
            (item) => item.owner.startsWith('configuration:thread'),
          ),
          isEmpty,
        );
      },
    );
  }

  test('Repository close owns a refresh still joining its previous configuration binding', () async {
    final fixture = await _fixture();
    final first = _route(fixture);
    final call = await fixture.commands.routes.at(0);
    call.reply.completeError(
      const CommandDispatchFailure.rejected(failure: receiptConflict),
    );
    expect(
      await first.result,
      const CommandResult<ThreadModelRouteCommandReply>.rejected(
        error: receiptConflict,
      ),
    );
    final cleanup = Completer<FeedCloseReport>();
    final source = fixture.configuration;
    source.feed.closeReceipt = cleanup;
    source.feed.emit(
      ThreadConfigurationFrame.resyncRequired(
        identity: ThreadFeedIdentity(
          feedId: source.feed.feedId,
          runtimeEpoch: receiptEpoch,
          incarnation: 1,
          facet: ThreadFacet.configuration,
          mode: source.mode,
        ),
        reason: ThreadResyncReason.revisionGap,
      ),
    );
    await source.feed.closeStarted.future;
    expect(fixture.owner.facets.configuration, hasLength(1));
    final closing = fixture.owner.repository.close();
    expect(fixture.commands.routes.values, hasLength(1));
    expect(
      fixture.owner.budget.usage
          .where((item) => item.owner.startsWith('configuration:thread'))
          .single
          .phase,
      ResourcePhase.retiring,
    );
    cleanup.complete(
      FeedCloseReport(
        feedId: source.feed.feedId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await closing).complete, isTrue);
    expect(
      fixture.owner.facets.configuration,
      hasLength(1),
      reason: 'close prevents replacement',
    );
    expect(fixture.owner.budget.usage, isEmpty);
  });

  for (final framesFirst in [false, true]) {
    for (final interrupted in [false, true]) {
      test(
        'actual stop waits for its captured execution (framesFirst=$framesFirst, interrupted=$interrupted)',
        () async {
          final fixture = await stopFixture();
          final source = await fixture.select();
          await source.session.timeline.ready;
          final baselineObservers = fixture.budget.used(ResourceKind.observer);
          final operation = (source.session.stopExecution(
            origin: source.stamp,
            executionId: 'execution-7',
          ) as StopExecutionOperation).ticket;
          expect(
            operation.state.value.receipt,
            isNull,
            reason: 'The operation exists before the command first awaits',
          );
          final call = await fixture.commands.interrupts.at(0);
          expect(
            (call.operationId, call.threadId, call.executionId),
            (operation.id, 'thread', 'execution-7'),
          );
          expect(
            fixture.budget.usage.where(
              (item) =>
                  item.kind == ResourceKind.observer &&
                  (item.owner.startsWith('stop-evidence:') ||
                      item.owner.startsWith('operation:')),
            ),
            unorderedEquals([
              ResourceUsage(
                kind: ResourceKind.observer,
                owner: 'stop-evidence:${operation.id.value}',
                phase: ResourcePhase.active,
              ),
              ResourceUsage(
                kind: ResourceKind.observer,
                owner: 'operation:${operation.id.value}',
                phase: ResourcePhase.active,
              ),
            ]),
          );
          expect(
            fixture.budget.used(ResourceKind.observer),
            baselineObservers + 2,
            reason: 'The new registry also budgets Stop\'s original-operation watch; both exact owners are asserted above',
          );
          fixture.owner.deselect();
          if (framesFirst)
            await source.deliver(active: null, status: ThreadStatus.idle);
          call.reply.complete(
            StopExecutionReply(
              threadId: call.threadId,
              executionId: call.executionId,
              stopped: interrupted,
              receipt: stopReceipt(
                call.operationId,
                disposition: interrupted
                    ? CommitDisposition.applied
                    : CommitDisposition.noChange,
              ),
            ),
          );
          await operation.state.waitFor((state) => state.receipt != null);
          expect(
            operation.state.value.receipt!.disposition,
            interrupted
                ? CommitDisposition.applied
                : CommitDisposition.noChange,
          );
          if (!framesFirst) {
            expect(operation.state.value.isPending, isTrue);
            expect(
              operation.state.value.effective,
              isFalse,
              reason: 'An interrupt ACK does not prove the execution ended',
            );
            expect(
              fixture.owner.operations.observations
                  .latest('stop:thread')!
                  .state
                  .value
                  .isPending,
              isTrue,
            );
            await source.deliver(
              active: stopTurn(7, revision: 2),
              execution: stopExecutionValue(7),
              status: ThreadStatus.running,
            );
            expect(
              operation.state.value.observed,
              isFalse,
              reason: 'Unrelated owner facts do not confirm the captured execution',
            );
            source.send(active: null, status: ThreadStatus.idle);
          }
          await _observed(operation);
          expect(await operation.result, isA<CommittedCommandResult<Unit>>());
          expect(
            (
              operation.state.value.observed,
              operation.state.value.effective,
              operation.state.value.durable,
            ),
            (true, true, false),
          );
          expect(operation.state.value.isPending, isFalse);
          expect((await fixture.owner.repository.close()).complete, isTrue);
          expect(fixture.budget.used(ResourceKind.observer), 0);
        },
      );
    }
  }

  test('resource receipts cannot bypass their canonical version barrier', () {
    final board = OperationRegistry(
      clientId: 'client',
      budget: ResourceBudget(),
    );
    final operation = board.begin<Unit>(target: 'settings');
    operation.accepted(
      const Unit(),
      commandReceipt(operation.ticket.id, [receiptStamp('settings', 2)]),
    );
    expect(operation.ticket.state.value.effective, isTrue);
    expect(operation.ticket.state.value.isPending, isTrue);
    operation.identityObserved();
    expect(
      operation.ticket.state.value.observed,
      isFalse,
      reason: 'Identity evidence cannot bypass a target version',
    );
    board.observe(receiptStamp('settings', 2));
    expect(operation.ticket.state.value.observed, isTrue);
  });

  for (final framesFirst in [false, true]) {
    test(
      'actual interaction waits for original canonical resolution (framesFirst=$framesFirst)',
      () async {
        final fixture = await _fixture();
        fixture.scriptInteraction('interaction');
        // The real execution feed supplies this Session's source credential.
        final opening = fixture.owner.facets.execution.single;
        await opening.feed.listened.future;
        opening.feed.emit(
          ThreadExecutionFrame.data(
            deliverySequence: 1,
            event: ThreadExecutionEvent.baseline(
              identity: ThreadFeedIdentity(
                feedId: opening.feed.feedId,
                runtimeEpoch: receiptEpoch,
                incarnation: 1,
                facet: ThreadFacet.execution,
                mode: opening.mode,
              ),
              stamp: receiptOrigin(ThreadFacet.execution, 1),
              value: const ThreadExecutionBaseline(
                status: ThreadStatus.idle,
                activeTurn: null,
                recentTerminalTurn: null,
                interactions: InteractionIndexHeader(
                  reference: InteractionIndexRef(entry: 10, revision: 1),
                  total: 0,
                  pending: 0,
                ),
                activity: null,
                storage: null,
              ),
            ),
          ),
        );
        await opening.feed.acknowledged(1);
        final ticket = _respond(fixture, 'interaction');
        final call = await fixture.commands.interactions.at(0);
        expect(call.id, ticket.id);
        expect(call.interactionId, 'interaction');
        expect(call.resolution, same(_resolution));
        if (framesFirst) fixture.interactionProofs['interaction']!.complete();
        call.reply.complete(receiptInteractionReply(call));
        await ticket.state.waitFor((state) => state.receipt != null);
        if (!framesFirst) {
          await fixture.interactionReads['interaction']!.future;
          expect(ticket.state.value.isPending, isTrue);
          expect(
            ticket.state.value.effective,
            isTrue,
            reason: 'Effect and canonical observation remain independent',
          );
          final pending = await fixture.session.openInteraction(
            interactionId: 'interaction',
            expectedRevision: 1,
            expectedIncarnation: 1,
          );
          expect(
            (await pending.header()).state,
            isA<PendingInteractionRead>(),
            reason: 'The response never deletes canonical facts',
          );
          expect((await pending.close()).complete, isTrue);
          expect(
            fixture.owner.operations.observations
                .latest('interaction:interaction')!
                .state
                .value
                .isPending,
            isTrue,
          );
          fixture.owner.operations.observe(
            receiptStamp('interaction:unrelated', 2),
          );
          expect(ticket.state.value.observed, isFalse);
          fixture.interactionProofs['interaction']!.complete();
        }
        await _observed(ticket);
        expect(
          await ticket.result,
          isA<CommittedCommandResult<InteractionCommandReply>>(),
        );
        expect(ticket.state.value.observed, isTrue);
        expect(ticket.state.value.durable, isFalse);
        expect(ticket.state.value.isPending, isFalse);
      },
    );
  }

  test('old interaction ACK cannot clear a newer interaction intent', () async {
    final fixture = await _fixture();
    fixture.scriptInteraction('x');
    fixture.scriptInteraction('y');
    final opening = fixture.owner.facets.execution.single;
    await opening.feed.listened.future;
    opening.feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: 1,
        event: ThreadExecutionEvent.baseline(
          identity: ThreadFeedIdentity(
            feedId: opening.feed.feedId,
            runtimeEpoch: receiptEpoch,
            incarnation: 1,
            facet: ThreadFacet.execution,
            mode: opening.mode,
          ),
          stamp: receiptOrigin(ThreadFacet.execution, 1),
          value: const ThreadExecutionBaseline(
            status: ThreadStatus.idle,
            activeTurn: null,
            recentTerminalTurn: null,
            interactions: InteractionIndexHeader(
              reference: InteractionIndexRef(entry: 10, revision: 1),
              total: 0,
              pending: 0,
            ),
            activity: null,
            storage: null,
          ),
        ),
      ),
    );
    await opening.feed.acknowledged(1);
    final x = _respond(fixture, 'x');
    final callX = await fixture.commands.interactions.at(0);
    fixture.interactionProofs['x']!.complete();
    final y = _respond(fixture, 'y');
    final callY = await fixture.commands.interactions.at(1);
    expect(
      fixture.owner.operations.observations.latest('interaction:y')!.id,
      y.id,
    );
    callX.reply.complete(receiptInteractionReply(callX));
    await x.result;
    await _observed(x);
    expect(
      fixture.owner.operations.observations
          .lookup(callX.id)!
          .state
          .value
          .observed,
      isTrue,
    );
    expect(
      fixture.owner.operations.observations.latest('interaction:y')!.id,
      y.id,
    );
    expect(y.state.value.isPending, isTrue);
    callY.reply.complete(receiptInteractionReply(callY));
    await y.state.waitFor((state) => state.receipt != null);
    await fixture.interactionReads['y']!.future;
    expect(
      fixture.owner.operations.observations.latest('interaction:y')!.id,
      y.id,
    );
    expect(y.state.value.isPending, isTrue);
    fixture.interactionProofs['y']!.complete();
    await _observed(y);
    expect(
      await y.result,
      isA<CommittedCommandResult<InteractionCommandReply>>(),
    );
    expect(y.state.value.isPending, isFalse);
  });

  for (final framesFirst in [false, true]) {
    test(
      'actual mode command preserves its pending intent until all target frames (framesFirst=$framesFirst)',
      () async {
        final fixture = await _fixture();
        final ticket = fixture.session.setThreadMode(
          origin: fixture.session.configuration.value.stamp!,
          mode: 'task',
        );
        final call = await fixture.commands.modes.at(0);
        expect(
          call.id,
          fixture.owner.operations.observations.latest('mode:thread')!.id,
        );
        final receipt = commandReceipt(call.id, [
          receiptStamp('thread-mode:thread', 2),
          receiptStamp('thread-directory', 2),
        ]);
        if (framesFirst) {
          await fixture.publishConfiguration(2);
          fixture.owner.operations.observe(receiptStamp('thread-directory', 2));
        }
        call.reply.complete(receipt);
        await ticket.state.waitFor((state) => state.receipt != null);
        expect(
          ticket.state.value.receipt!.disposition,
          CommitDisposition.applied,
          reason: 'An equal observation version never implies NoChange',
        );
        if (!framesFirst) {
          expect(ticket.state.value.isPending, isTrue);
          fixture.owner.operations.observe(
            const ResourceStamp(
              resourceKey: 'thread-mode:thread',
              ownerEpoch: 'another-runtime',
              revision: 200,
            ),
          );
          fixture.owner.operations.observe(receiptStamp('thread-directory', 2));
          expect(
            ticket.state.value.observed,
            isFalse,
            reason: 'Every target and owner epoch must match',
          );
          expect(
            fixture.owner.operations.observations
                .latest('mode:thread')!
                .state
                .value
                .isPending,
            isTrue,
          );
          await fixture.publishConfiguration(2);
        }
        await _observed(ticket);
        expect(
          await ticket.result,
          CommandResult<CommitReceipt>.committed(
            value: receipt,
            receipt: receipt,
          ),
        );
        expect(ticket.state.value.observed, isTrue);
        expect(ticket.state.value.durable, isFalse);
        expect(ticket.state.value.isPending, isFalse);
      },
    );
  }

  test(
    'actual route X late acknowledgement cannot clear Y pending intent',
    () async {
      final fixture = await _fixture();
      final first = _route(fixture);
      final x = await fixture.commands.routes.at(0);
      final second = _route(
        fixture,
        model: 'beta',
        expectedRouteRevision: 2,
        expectedSettingsRevision: 2,
      );
      expect(
        fixture.owner.operations.observations.latest('route:thread')!.id,
        second.id,
      );
      await fixture.publishConfiguration(2);
      fixture.owner.operations.observe(receiptStamp('settings', 2));
      x.reply.complete(receiptRouteReply(x, 2));
      expect(
        await first.result,
        isA<CommittedCommandResult<ThreadModelRouteCommandReply>>(),
      );
      await _observed(first);
      final y = await fixture.commands.routes.at(1);
      expect(y.id, isNot(x.id));
      expect((y.model, y.routeRevision, y.settingsRevision), ('beta', 2, 2));
      expect(first.state.value.observed, isTrue);
      expect(
        fixture.owner.operations.observations.latest('route:thread')!.id,
        second.id,
      );
      fixture.owner.operations.observe(receiptStamp('settings', 3));
      y.reply.complete(receiptRouteReply(y, 3, settings: 3));
      await second.state.waitFor((state) => state.receipt != null);
      expect(second.state.value.isPending, isTrue);
      expect(
        fixture.owner.operations.observations.latest('route:thread')!.id,
        second.id,
      );
      expect(
        fixture.session.configuration.value.value!.modelRoute!.revision,
        2,
        reason: 'A control response does not write the Thread mirror',
      );
      await _assertCanonicalModel(fixture, 'alpha');
      await fixture.publishConfiguration(3, model: 'beta');
      await _observed(second);
      await _assertCanonicalModel(fixture, 'beta');
      expect(
        await second.result,
        isA<CommittedCommandResult<ThreadModelRouteCommandReply>>(),
      );
      expect(second.state.value.observed, isTrue);
      expect(second.state.value.isPending, isFalse);
    },
  );

  test('actual mode command preserves explicit NoChange with equal resource versions', () async {
    final fixture = await _fixture();
    final ticket = fixture.session.setThreadMode(
      origin: fixture.session.configuration.value.stamp!,
      mode: 'task',
    );
    final call = await fixture.commands.modes.at(0);
    fixture.owner.operations.observe(receiptStamp('thread-directory', 1));
    call.reply.complete(
      commandReceipt(call.id, [
        receiptStamp('thread-mode:thread', 1),
        receiptStamp('thread-directory', 1),
      ], disposition: CommitDisposition.noChange),
    );
    expect(await ticket.result, isA<CommittedCommandResult<CommitReceipt>>());
    await _observed(ticket);
    expect(ticket.state.value.receipt!.disposition, CommitDisposition.noChange);
    expect(ticket.state.value.observed, isTrue);
  });

  test('actual command close seals admission and joins an in-flight response', () async {
    final fixture = await _fixture();
    final ticket = fixture.session.setThreadMode(
      origin: fixture.session.configuration.value.stamp!,
      mode: 'task',
    );
    final call = await fixture.commands.modes.at(0);
    fixture.owner.operations.observe(receiptStamp('thread-directory', 1));
    var settled = false;
    final closing = fixture.owner.repository.close().then((report) {
      settled = true;
      return report;
    });
    expect(settled, isFalse);
    expect(
      () => fixture.session.setThreadMode(
        origin: receiptOrigin(ThreadFacet.configuration, 1),
        mode: 'task',
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'sealed admission',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    call.reply.complete(
      commandReceipt(call.id, [
        receiptStamp('thread-mode:thread', 1),
        receiptStamp('thread-directory', 1),
      ]),
    );
    await ticket.result;
    final report = await closing;
    expect(
      report.complete,
      isTrue,
      reason:
          '${report.unresolved.map((resource) => (resource.owner, resource.issues.map((issue) => (issue.diagnostic.stage, issue.diagnostic.message, issue.recovery)).toList())).toList()}',
    );
    expect(settled, isTrue);
  });
}
