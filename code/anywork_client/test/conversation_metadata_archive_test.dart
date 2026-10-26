import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';
import 'package:test/test.dart';

import 'support/conversation_fixture.dart';
import 'support/scripted_feed.dart';
import 'support/thread_metadata_fixture.dart';
import 'support/timeline_transport.dart';

const _project = ProjectRecord(
  id: 'project',
  name: 'Project',
  path: '/workspace',
  sshAlias: null,
  updatedAt: 1,
);
const _selection = WorkspaceState(
  selection: WorkspaceSelection(
    projectId: 'project',
    threadId: 'A',
    needsOpen: false,
  ),
  selectionGeneration: 1,
  sealed: false,
);
const _unselected = WorkspaceState(
  selection: WorkspaceSelection(
    projectId: 'project',
    threadId: null,
    needsOpen: false,
  ),
  selectionGeneration: 0,
  sealed: false,
);
const _retryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'metadata-native',
    code: 'joinUnconfirmed',
    message: 'The original metadata owner still needs native join.',
    retryable: true,
    correlationId: 'metadata-original-close',
  ),
  recovery: CleanupRecovery.retryClose,
);

/// Test-owned teardown only. Each item is the real leaf returned by the real
/// Conversation factory; the tests explicitly mark which received confirmation.
final class _Scenario {
  _Scenario({FixtureConversationContext? context})
    : fixture = ConversationFixture(context: context) {
    addTearDown(close);
  }
  final ConversationFixture fixture;
  final captures = <WorkspaceArchiveCapture>[];
  final confirmed = <WorkspaceArchiveCapture>{};
  bool _closed = false;
  T keep<T extends WorkspaceArchiveCapture>(T capture) {
    captures.add(capture);
    return capture;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final closing = [
      for (final capture in captures)
        confirmed.contains(capture)
            ? capture.retryCleanup()
            : capture.releaseWithoutArchive(),
    ];
    fixture.repository.seal();
    for (final owner
        in fixture.context.metadataOwners.whereType<ScriptedThreadMetadata>()) {
      owner.releasePending();
    }
    for (final opening in fixture.timeline.requests) {
      if (!opening.result.isCompleted)
        opening.result.complete(
          TestTimelineConnection(
            // A Thread's Timeline carries only that Thread's own items.
            initial: baseline(
              1,
              items: [timelineItem(1, threadId: opening.threadId)],
            ),
          ),
        );
      final native = await opening.result.future;
      final connection = native is TimelineConnectionProbe
          ? native.native
          : native;
      if (connection is TestTimelineConnection &&
          connection.closeGate?.isCompleted == false)
        connection.closeGate!.complete();
    }
    final reports = await Future.wait([...closing, fixture.repository.close()]);
    expect([for (final report in reports) ...report.unresolved], isEmpty);
    expect(fixture.budget.usage, isEmpty);
  }
}

Future<T> _before<T, W>(Future<T> entered, Future<W> work) => Future.any([
  entered,
  work.then<T>(
    (_) => throw StateError(
      'The original work settled before its required native boundary',
    ),
    onError: (Object error, StackTrace stack) =>
        Error.throwWithStackTrace(error, stack),
  ),
]);

void _noUiSources(ConversationFixture fixture) {
  expect(fixture.context.recoveryRequests, isEmpty);
  expect(fixture.facets.execution, isEmpty);
  expect(fixture.facets.metrics, isEmpty);
  expect(fixture.facets.context, isEmpty);
  expect(fixture.facets.configuration, isEmpty);
  expect(fixture.facets.authoring, isEmpty);
  expect(fixture.timeline.requests, isEmpty);
}

final class _CreatedSource implements CreatedInputExecutionSource {
  @override
  String get threadId => 'created';
  @override
  String get inputId => 'native-input';
  @override
  String get runtimeEpoch => 'created-runtime';
  @override
  int get incarnation => 1;
  final feed = ScriptedFeed<ThreadExecutionFrame>(
    feedId: 'created-execution',
    sequenceOf: (frame) =>
        frame is ThreadExecutionData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! ThreadExecutionData,
  );
  int opens = 0;
  @override
  Future<FeedConnection<ThreadExecutionFrame>> openExecution() async {
    opens++;
    return feed;
  }
}

void main() {
  test('pure membership observes before current and does not consume the stale watch snapshot or activate UI sources', () async {
    final native = ScriptedThreadMetadata(
      'A',
      initial: metadataState(record: fixtureThread('A')),
    );
    const replacementOrigin = ProductReadOrigin(
      ownerEpoch: 'metadata-native',
      incarnation: 2,
    );
    native.afterWatch = () => native.source.publish(
      metadataState(
        origin: replacementOrigin,
        phase: ResourceSyncPhase.connecting,
      ),
    );
    final context = FixtureConversationContext()..metadata = (_) => native;
    final scenario = _Scenario(context: context);
    final fixture = scenario.fixture;
    fixture.repository.session('A');
    final capture = scenario.keep(
      fixture.archive.captureProject('project', frozenSelection: _unselected),
    );
    final preparing = capture.prepare(_project);
    await _before(native.retryCalled.future, preparing);
    expect(native.source.observerCount, 1);
    expect(native.retryCalls, 1);
    native.source.publish(
      metadataState(record: fixtureThread('A'), origin: replacementOrigin),
    );
    native.queryReply.complete();
    await preparing;
    expect(context.metadataOwners.single, same(native));
    expect(context.metadataRequests, ['A']);
    _noUiSources(fixture);
    expect((await capture.releaseWithoutArchive()).complete, isTrue);
    expect(native.closed.isCompleted, isTrue);
  });

  test('readError, source failure, foreign owner/value and closed metadata fail the original prepare instead of empty membership or another owner', () async {
    for (final kind in [
      'readError',
      'source',
      'foreignOwner',
      'foreign',
      'closed',
    ]) {
      final native = ScriptedThreadMetadata(
        kind == 'foreignOwner' ? 'other' : 'A',
        initial: metadataState(),
      );
      final context = FixtureConversationContext()..metadata = (_) => native;
      final scenario = _Scenario(context: context);
      final fixture = scenario.fixture;
      fixture.repository.session('A');
      final capture = scenario.keep(
        fixture.archive.captureProject('project', frozenSelection: _unselected),
      );
      final preparing = capture.prepare(_project);
      if (kind == 'foreignOwner') {
        await expectLater(
          preparing,
          throwsA(
            isA<StudioFailure>().having(
              (error) => error.code,
              'code',
              StudioFailureCode.protocol,
            ),
          ),
        );
        expect(
          native.retryCalls,
          0,
          reason: 'The foreign owner is closed, never queried or replaced with another owner',
        );
        expect(context.metadataRequests, ['A']);
        expect(context.metadataOwners, [native]);
        _noUiSources(fixture);
        expect((await capture.releaseWithoutArchive()).complete, isTrue);
        expect(native.closed.isCompleted, isTrue);
        await scenario.close();
        continue;
      }
      await _before(native.retryCalled.future, preparing);
      const failure = StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The original metadata lookup failed.',
        retryable: false,
        correlationId: 'metadata-original-failure',
      );
      final rejected = expectLater(
        preparing,
        throwsA(
          kind == 'readError' || kind == 'source'
              ? same(failure)
              : isA<StudioFailure>().having(
                  (error) => error.code,
                  'code',
                  kind == 'foreign'
                      ? StudioFailureCode.protocol
                      : StudioFailureCode.cancelled,
                ),
        ),
      );
      native.source.publish(switch (kind) {
        'readError' => metadataState(readError: failure),
        'source' => metadataState(
          phase: ResourceSyncPhase.failed,
          sourceError: failure,
        ),
        'foreign' => metadataState(record: fixtureThread('other')),
        _ => metadataState(phase: ResourceSyncPhase.closed),
      });
      // The pure query itself succeeds: only the original public metadata
      // state can settle this failure, so ignoring readError cannot pass via
      // a second error from the retry Future.
      native.queryReply.complete();
      await rejected;
      expect(context.metadataOwners, [native]);
      expect(context.metadataRequests, ['A']);
      expect(native.retryCalls, 1);
      _noUiSources(fixture);
      expect((await capture.releaseWithoutArchive()).complete, isTrue);
      expect(native.closed.isCompleted, isTrue);
      await scenario.close();
    }
  });

  test('a pre-seal reservation may start its original read, but ready value and original Unresolved close remain separate recoverable responsibilities', () async {
    final native = ScriptedThreadMetadata('A', initial: metadataState())
      ..closeReply = Completer<CloseReport>()
      ..retryCloseReply = Completer<CloseReport>();
    final context = FixtureConversationContext()..metadata = (_) => native;
    final scenario = _Scenario(context: context);
    final fixture = scenario.fixture;
    fixture.repository.session('A');
    final capture = scenario.keep(
      fixture.archive.captureProject('project', frozenSelection: _unselected),
    );
    expect(
      context.metadataRequests,
      isEmpty,
      reason: 'Synchronous capture reserves but does not start metadata',
    );
    fixture.repository.seal();
    expect(
      () => fixture.archive.captureProject(
        'project',
        frozenSelection: _unselected,
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    final preparing = capture.prepare(_project);
    await _before(native.retryCalled.future, preparing);
    native.source.publish(metadataState(record: fixtureThread('A')));
    await preparing;
    await native.closeCalled.future;
    final pending = await capture.releaseWithoutArchive(
      deadline: DateTime.utc(2000),
    );
    expect(
      pending.complete,
      isFalse,
      reason: 'Ready metadata is not native/query join',
    );
    expect(
      pending.unresolved
          .expand((resource) => resource.issues)
          .any((issue) => issue.recovery == CleanupRecovery.awaitCompletion),
      isTrue,
    );
    final original = UnresolvedResource(
      owner: 'native-metadata-A',
      attemptId: const AttemptId(501),
      issues: [_retryIssue],
    );
    native.closeReply!.complete(CloseReport(unresolved: [original]));
    native.queryReply.complete();
    final unresolved = await capture.releaseWithoutArchive();
    expect(
      unresolved.unresolved,
      contains(original),
      reason:
          'Keep the original native owner/attempt and full typed close issue',
    );
    final retry = capture.retryCleanup();
    await _before(native.retryCloseCalled.future, retry);
    native.retryCloseReply!.complete(CloseReport(unresolved: []));
    expect((await retry).complete, isTrue);
    expect(native.closed.isCompleted, isTrue);
    expect(
      native.retryCalls,
      1,
      reason: 'Cleanup cannot start another metadata query',
    );
    expect(context.metadataRequests, ['A']);
    _noUiSources(fixture);
    expect((await fixture.repository.close()).complete, isTrue);
  });

  test('known pure metadata does not turn Recovery unknown or blocked into UI admission or require a second owner for archive membership', () async {
    for (final blocked in [false, true]) {
      const failure = StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'Original Recovery is not allowed.',
        retryable: true,
        correlationId: 'metadata-recovery-gate',
      );
      final context = FixtureConversationContext()
        ..recovery = (_) async => blocked
            ? const ConversationRecoveryAccess.blocked(error: failure)
            : const ConversationRecoveryAccess.unknown(error: failure);
      final scenario = _Scenario(context: context);
      final fixture = scenario.fixture;
      final session = fixture.select('A');
      final failed = await session.execution.waitFor(
        (state) => state.sync.phase == FacetSyncPhase.failed,
      );
      expect(failed.sync.error, same(failure));
      final metadataOwner = context.metadataOwners.single;
      final capture = scenario.keep(
        fixture.archive.captureProject('project', frozenSelection: _selection),
      );
      await capture.prepare(_project);
      expect(context.metadataOwners.single, same(metadataOwner));
      expect(context.metadataRequests, ['A']);
      expect(context.recoveryRequests, [fixtureThread('A')]);
      expect(fixture.facets.execution, isEmpty);
      expect(fixture.facets.metrics, isEmpty);
      expect(fixture.facets.context, isEmpty);
      expect(fixture.facets.configuration, isEmpty);
      expect(fixture.facets.authoring, isEmpty);
      expect(fixture.timeline.requests, isEmpty);
      expect((await capture.releaseWithoutArchive()).complete, isTrue);
      await scenario.close();
    }
  });

  test('an old confirmed capture joins its original late Timeline open without clearing the newer same-ID Session and UI token', () async {
    final scenario = _Scenario();
    final fixture = scenario.fixture;
    final old = fixture.select('A');
    old.timeline.attachConsumer((_) {});
    final late = await fixture.timeline.opened(0);
    fixture.deselect();
    final capture = scenario.keep(
      fixture.archive.captureThread(
        'A',
        frozenSelection: _unselected.copyWith(selectionGeneration: 2),
      ),
    );
    await capture.prepare(fixtureThread('A'));
    final current = fixture.select('A');
    current.timeline.attachConsumer((_) {});
    final currentNative = TimelineConnectionProbe(
      TestTimelineConnection(
        initial: baseline(
          1,
          subscriptionId: 'new-A',
          items: [timelineItem(1, threadId: 'A')],
        ),
      ),
    );
    (await fixture.timeline.opened(1)).result.complete(currentNative);
    await current.timeline.ready;
    await currentNative.acknowledged(1);
    scenario.confirmed.add(capture);
    final confirmation = ArchiveThreadResult(
      archivedRootId: 'A',
      removedThreadIds: ['A'],
      nextRoot: null,
    );
    final pending = await capture.afterArchived(
      confirmation,
      deadline: DateTime.utc(2000),
    );
    expect(pending.complete, isFalse);
    expect(fixture.repository.active.value, same(current));
    expect(fixture.repository.existingSession('A'), same(current));
    final oldNative = TestTimelineConnection(
      initial: baseline(
        9,
        subscriptionId: 'old-A',
        items: [timelineItem(9, threadId: 'A')],
      ),
    )..closeGate = Completer<void>();
    late.result.complete(oldNative);
    await oldNative.closeStarted.future;
    expect(fixture.repository.active.value, same(current));
    oldNative.closeGate!.complete();
    await oldNative.closeCompleted.future;
    expect((await capture.retryCleanup()).complete, isTrue);
    expect((await capture.afterArchived(confirmation)).complete, isTrue);
    await expectLater(
      capture.afterArchived(
        ArchiveThreadResult(
          archivedRootId: 'A',
          removedThreadIds: ['A', 'other'],
          nextRoot: null,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.conflict,
        ),
      ),
    );
    expect(current, isNot(same(old)));
    expect(fixture.repository.active.value, same(current));
    expect(currentNative.native.disposeCalls, 0);
    expect(fixture.timeline.requests, hasLength(2));
  });

  test('created-only membership stays pure and a confirmed UI archive cannot cancel the operation execution lease', () async {
    final scenario = _Scenario();
    final fixture = scenario.fixture;
    final session = fixture.repository.session('created');
    final source = _CreatedSource();
    final lease = fixture.demand.retainForCreatedInput(
      session,
      receipt: SubmitPromptReceipt(
        threadId: 'created',
        inputId: 'native-input',
        cursor: 1,
        requestDigest: "sha256:${'a'.padRight(64, 'a')}",
      ),
      source: source,
    );
    addTearDown(lease.release);
    await source.feed.listened.future;
    const stamp = ThreadFacetStamp(
      runtimeEpoch: 'created-runtime',
      incarnation: 1,
      facet: ThreadFacet.execution,
      revision: 1,
    );
    source.feed.emit(
      const ThreadExecutionFrame.data(
        deliverySequence: 1,
        event: ThreadExecutionEvent.baseline(
          identity: ThreadFeedIdentity(
            feedId: 'created-execution',
            runtimeEpoch: 'created-runtime',
            incarnation: 1,
            facet: ThreadFacet.execution,
            mode: ThreadObservationMode.live,
          ),
          stamp: stamp,
          value: ThreadExecutionBaseline(
            status: ThreadStatus.idle,
            activeTurn: null,
            recentTerminalTurn: null,
            interactions: InteractionIndexHeader(
              reference: InteractionIndexRef(entry: 1, revision: 1),
              total: 0,
              pending: 0,
            ),
            activity: null,
            storage: null,
          ),
        ),
      ),
    );
    expect(await lease.ready, stamp);
    await source.feed.acknowledged(1);
    expect(fixture.context.metadataRequests, isEmpty);
    final project = scenario.keep(
      fixture.archive.captureProject('project', frozenSelection: _unselected),
    );
    await project.prepare(_project);
    expect(fixture.context.metadataRequests, ['created']);
    _noUiSources(fixture);
    expect((await project.releaseWithoutArchive()).complete, isTrue);
    final beforeUi = scenario.keep(
      fixture.archive.captureThread('created', frozenSelection: _unselected),
    );
    await beforeUi.prepare(fixtureThread('created'));
    final recoveryEntered = Completer<void>();
    final recoveryReply = Completer<ConversationRecoveryAccess>();
    fixture.context.recovery = (_) {
      recoveryEntered.complete();
      return recoveryReply.future;
    };
    addTearDown(() {
      if (!recoveryReply.isCompleted)
        recoveryReply.complete(const ConversationRecoveryAccess.allowed());
    });
    expect(
      fixture.select('created'),
      same(session),
      reason: 'The UI now borrows the already operation-owned Session',
    );
    await recoveryEntered.future;
    recoveryReply.complete(const ConversationRecoveryAccess.allowed());
    final uiMetrics = await fixture.facets.metricsOpened(0);
    await uiMetrics.feed.listened.future;
    // The user-selected Session owns exactly one UI Timeline connection; it is
    // real native work that the archive retirement has to join, not a read.
    final uiTimeline = TestTimelineConnection(
      initial: baseline(
        1,
        subscriptionId: 'created-ui',
        items: [timelineItem(1, threadId: 'created')],
      ),
    );
    (await fixture.timeline.opened(0)).result.complete(uiTimeline);
    await uiTimeline.subscribed.future;
    final confirmation = ArchiveThreadResult(
      archivedRootId: 'created',
      removedThreadIds: ['created'],
      nextRoot: null,
    );
    scenario.confirmed.add(beforeUi);
    expect((await beforeUi.afterArchived(confirmation)).complete, isTrue);
    expect(
      fixture.repository.active.value,
      same(session),
      reason: 'A pre-UI capture cannot retire the same owner\'s newer UI token',
    );
    expect(uiMetrics.feed.closeCalls, 0);
    final createdSelection = _selection.copyWith(
      selection: const WorkspaceSelection(
        projectId: 'project',
        threadId: 'created',
        needsOpen: false,
      ),
    );
    final thread = scenario.keep(
      fixture.archive.captureThread(
        'created',
        frozenSelection: createdSelection,
      ),
    );
    await thread.prepare(fixtureThread('created'));
    scenario.confirmed.add(thread);
    expect((await thread.afterArchived(confirmation)).complete, isTrue);
    expect(fixture.repository.active.value, isNull);
    expect(source.feed.requestCloseCalls, 0);
    expect(lease.execution, same(session.execution));
    expect(lease.execution.value.sync.phase, FacetSyncPhase.ready);
    expect(source.opens, 1);
    expect(fixture.context.metadataRequests, ['created', 'created']);
    expect(fixture.context.recoveryRequests, [fixtureThread('created')]);
    expect(uiMetrics.feed.closeStarted.isCompleted, isTrue);
    expect(
      fixture.facets.execution,
      isEmpty,
      reason: 'UI/archive never substitute an ordinary activating source for the original creation source',
    );
    expect(
      fixture.timeline.requests,
      hasLength(1),
      reason:
          'Only the UI borrow owns a Timeline connection, never the archive',
    );
    lease.release();
    await source.feed.closeStarted.future;
    expect((await fixture.repository.close()).complete, isTrue);
    expect(fixture.operations.observations.records.value, isEmpty);
  });
}
