import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart' show ThreadStatus;
import 'package:test/test.dart';

import 'support/controlled_timers.dart';
import 'support/conversation_fixture.dart';
import 'support/drafts_fixture.dart' show DraftsFixture;
import 'support/scripted_feed.dart';
import 'support/timeline_transport.dart';

const _runtime = 'thread-session-runtime';
const _cancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'Release this test\'s original native boundary during teardown.',
  retryable: false,
  correlationId: 'thread-session-cleanup',
);

ThreadFacetStamp _stamp(ThreadFacet facet, int revision, int incarnation) =>
    ThreadFacetStamp(
      runtimeEpoch: _runtime,
      incarnation: incarnation,
      facet: facet,
      revision: revision,
    );

ThreadFeedIdentity _identity(
  String feedId,
  ThreadFacet facet,
  ThreadObservationMode mode,
  int incarnation,
) => ThreadFeedIdentity(
  feedId: feedId,
  runtimeEpoch: _runtime,
  incarnation: incarnation,
  facet: facet,
  mode: mode,
);

/// One scripted facet feed: delivery sequence and revision advance
/// mechanically, every business fact is supplied by the test.
final class _FacetFeed<F> {
  _FacetFeed(this.opening, this.facet, {this.incarnation = 1});
  final FacetOpen<F> opening;
  final ThreadFacet facet;
  final int incarnation;
  int revision = 0;
  int sequence = 0;

  ScriptedFeed<F> get feed => opening.feed;
  ThreadFeedIdentity get identity =>
      _identity(feed.feedId, facet, opening.mode, incarnation);
  ThreadFacetStamp stamp(int at) => _stamp(facet, at, incarnation);

  /// A data frame joins its real ACK; a control frame has none by contract.
  Future<void> deliver(F frame) async {
    await feed.listened.future;
    feed.emit(frame);
    await feed.acknowledged(sequence);
  }

  Future<void> sendControl(F frame) async {
    await feed.listened.future;
    feed.emit(frame);
  }

  /// A deliberately invalid data frame: it is emitted without inventing an ACK
  /// the owner will never send for rejected material.
  Future<void> sendUnacknowledged(F frame) async {
    await feed.listened.future;
    feed.emit(frame);
  }
}

final class _AuthoringFeed extends _FacetFeed<ThreadAuthoringFrame> {
  _AuthoringFeed(FacetOpen<ThreadAuthoringFrame> opening, {int incarnation = 1})
    : super(opening, ThreadFacet.authoring, incarnation: incarnation);

  Future<void> baseline({PlanBrief? plan}) async {
    revision = 1;
    sequence = 1;
    await deliver(
      ThreadAuthoringFrame.data(
        deliverySequence: sequence,
        event: ThreadAuthoringEvent.baseline(
          identity: identity,
          stamp: stamp(revision),
          value: ThreadAuthoringBaseline(
            todo: null,
            plan: plan,
            workflow: null,
            progress: ThreadCapabilitySupport.unsupported,
          ),
        ),
      ),
    );
  }

  Future<void> planChange(PlanBrief? plan) async {
    final previous = revision;
    revision = previous + 1;
    sequence++;
    await deliver(
      ThreadAuthoringFrame.data(
        deliverySequence: sequence,
        event: ThreadAuthoringEvent.change(
          stamp: stamp(revision),
          baseRevision: previous,
          value: ThreadAuthoringChange(
            todo: const TodoReplacement.unchanged(),
            plan: PlanReplacement.replace(value: plan),
            workflow: const WorkflowReplacement.unchanged(),
          ),
        ),
      ),
    );
  }
}

final class _MetricsFeed extends _FacetFeed<ThreadMetricsFrame> {
  _MetricsFeed(FacetOpen<ThreadMetricsFrame> opening, {int incarnation = 1})
    : super(opening, ThreadFacet.metrics, incarnation: incarnation);

  Future<void> baseline(ThreadMetricsValue value) async {
    revision = 1;
    sequence = 1;
    await deliver(
      ThreadMetricsFrame.data(
        deliverySequence: sequence,
        event: ThreadMetricsEvent.baseline(
          identity: identity,
          stamp: stamp(revision),
          value: value,
        ),
      ),
    );
  }

  Future<void> replace(ThreadMetricsValue value) async {
    revision++;
    sequence++;
    await deliver(
      ThreadMetricsFrame.data(
        deliverySequence: sequence,
        event: ThreadMetricsEvent.replace(stamp: stamp(revision), value: value),
      ),
    );
  }

  Future<void> resyncRequired() async {
    sequence++;
    await sendControl(
      ThreadMetricsFrame.resyncRequired(
        identity: identity,
        reason: ThreadResyncReason.sourceLagged,
      ),
    );
  }

  Future<void> ended() async {
    sequence++;
    await sendControl(
      ThreadMetricsFrame.closed(
        identity: identity,
        reason: ThreadFeedClosedReason.requested,
      ),
    );
  }
}

final class _ExecutionFeed extends _FacetFeed<ThreadExecutionFrame> {
  _ExecutionFeed(FacetOpen<ThreadExecutionFrame> opening, {int incarnation = 1})
    : super(opening, ThreadFacet.execution, incarnation: incarnation);

  Future<void> baseline({
    ThreadStatus status = ThreadStatus.idle,
    TurnBrief? active,
    TurnBrief? recentTerminal,
  }) async {
    revision = 1;
    sequence = 1;
    await deliver(
      ThreadExecutionFrame.data(
        deliverySequence: sequence,
        event: ThreadExecutionEvent.baseline(
          identity: identity,
          stamp: stamp(revision),
          value: ThreadExecutionBaseline(
            status: status,
            activeTurn: active,
            recentTerminalTurn: recentTerminal,
            interactions: const InteractionIndexHeader(
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
  }

  Future<void> change({
    int? baseRevision,
    ThreadStatus? status,
    TurnBrief? active,
    TurnBrief? recentTerminal,
  }) async {
    final previous = revision;
    revision = previous + 1;
    sequence++;
    await deliver(
      ThreadExecutionFrame.data(
        deliverySequence: sequence,
        event: ThreadExecutionEvent.change(
          stamp: stamp(revision),
          baseRevision: baseRevision ?? previous,
          value: ThreadExecutionChange(
            status: status,
            turns: TurnsReplacement(
              activeTurn: active,
              recentTerminalTurn: recentTerminal,
            ),
            interactions: null,
            activity: const ActivityReplacement.unchanged(),
            storage: const StorageReplacement.unchanged(),
          ),
        ),
      ),
    );
  }

  Future<void> failure(StudioFailure error) async {
    sequence++;
    await sendControl(
      ThreadExecutionFrame.failure(identity: identity, error: error),
    );
  }
}

/// One scripted native Plan document scope: identity and body are the test's.
final class _PlanPin implements PlanDocumentReadConnection {
  _PlanPin(this.readHeader, this.readDocument);
  final PlanDocumentReadHeader readHeader;
  final PlanDocumentValue readDocument;
  int closeCalls = 0;
  bool requested = false;

  @override
  Future<PlanDocumentReadHeader> header() async => readHeader;
  @override
  Future<PlanDocumentValue> document() async => readDocument;
  @override
  void requestClose() => requested = true;
  @override
  Future<FeedCloseReport> close() async {
    closeCalls++;
    return FeedCloseReport(
      feedId: readHeader.scope.scopeId,
      outcome: const FeedCloseOutcome.clean(),
    );
  }

  @override
  Future<FeedCloseReport> retryClose() => close();
}

ReadScopeIdentity _scope(ThreadFacetStamp origin, int index) =>
    ReadScopeIdentity(
      scopeId: 'plan-scope-$index',
      runtimeEpoch: origin.runtimeEpoch,
      incarnation: origin.incarnation,
      sourceRevision: origin.revision,
    );

/// Full owner teardown: release only this test's unanswered native boundaries,
/// then require the real Repository to report a complete close.
Future<void> _closeOwner(ConversationFixture owner) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  for (final request in owner.timeline.requests) {
    if (!request.result.isCompleted) {
      request.result.complete(
        TestTimelineConnection(
          initial: baseline(
            1,
            subscriptionId: 'late-${owner.timeline.requests.indexOf(request)}',
          ),
        ),
      );
    }
  }
  for (final plan in owner.facets.plans) {
    if (!plan.reply.isCompleted) plan.reply.completeError(_cancelled);
  }
  final report = await owner.repository.close(deadline: deadline);
  expect(report.complete, isTrue);
}

Matcher _failureMatcher(StudioFailureCode code) =>
    isA<StudioFailure>().having((failure) => failure.code, 'code', code);

TurnBrief _turn(int entry, {int revision = 1}) => TurnBrief(
  reference: TurnReadRef(entry: entry, revision: revision),
  revision: revision,
  updatedAt: revision,
  state: const TurnBriefState.running(startedAt: 1, phase: TurnPhase.thinking),
);

ThreadMetricsValue _authoritative(int completionTokens) => ThreadMetricsValue(
  live: null,
  authoritative: AuthoritativeTurnMetrics(
    identity: const MetricsIdentityRef(entry: 1),
    completionTokens: completionTokens,
    responseMillis: 1,
  ),
);

ThreadMetricsValue _live(int? completionTokens) => ThreadMetricsValue(
  live: LiveTurnMetrics(
    identity: const MetricsIdentityRef(entry: 1),
    completionTokens: completionTokens,
    responseMillis: null,
    state: TurnObservationState.live,
    observationSequence: 1,
  ),
  authoritative: null,
);

void main() {
  test('approved plan markdown is read through its own scope instead of being copied into state', () async {
    final fixture = ConversationFixture();
    addTearDown(() => _closeOwner(fixture));
    final session = fixture.select('thread');
    final authoring = _AuthoringFeed(await fixture.facets.authoringOpened(0));
    final approved = PlanBrief(
      revision: 7,
      state: PlanPhase.approved,
      document: const PlanDocumentRef(version: 3, contentHash: 'hash-v3'),
      updatedAt: 1,
    );
    await authoring.baseline(plan: approved);
    expect(session.authoring.value.value!.plan, approved);
    expect(session.authoring.value.value!.plan!.state, PlanPhase.approved);

    final origin = authoring.stamp(authoring.revision);
    final opening = session.openPlanDocument(
      approved.document!,
      origin: origin,
    );
    final call = await fixture.facets.planOpened(0);
    expect(call.threadId, 'thread');
    expect(call.reference, approved.document);
    expect(call.origin, origin);
    final scopeIdentity = _scope(origin, 0);
    final firstPin = call.accept(
      _PlanPin(
        PlanDocumentReadHeader(
          scope: scopeIdentity,
          version: 3,
          contentHash: 'hash-v3',
        ),
        PlanDocumentValue(
          scope: scopeIdentity,
          version: 3,
          contentHash: 'hash-v3',
          markdown: '# Approved plan\n\nKeep the current document.',
        ),
      ),
    ) as _PlanPin;
    final scope = await opening;
    expect((await scope.header()).version, 3);
    expect(
      (await scope.document()).markdown,
      '# Approved plan\n\nKeep the current document.',
    );

    final revised = PlanBrief(
      revision: 8,
      state: PlanPhase.approved,
      document: const PlanDocumentRef(version: 4, contentHash: 'hash-v4'),
      updatedAt: 2,
    );
    await authoring.planChange(revised);
    expect(session.authoring.value.value!.plan, revised);
    final revisedOrigin = authoring.stamp(authoring.revision);
    final revisedScope = session.openPlanDocument(
      revised.document!,
      origin: revisedOrigin,
    );
    final revisedCall = await fixture.facets.planOpened(1);
    expect(revisedCall.reference, revised.document);
    final revisedIdentity = _scope(revisedOrigin, 1);
    revisedCall.accept(
      _PlanPin(
        PlanDocumentReadHeader(
          scope: revisedIdentity,
          version: 4,
          contentHash: 'hash-v4',
        ),
        PlanDocumentValue(
          scope: revisedIdentity,
          version: 4,
          contentHash: 'hash-v4',
          markdown: '# Revised approved plan\n\nUse the replacement body.',
        ),
      ),
    );
    expect(
      (await (await revisedScope).document()).markdown,
      '# Revised approved plan\n\nUse the replacement body.',
    );
    expect(
      () => session.openPlanDocument(approved.document!, origin: revisedOrigin),
      throwsA(_failureMatcher(StudioFailureCode.superseded)),
      reason: 'a superseded document identity can never be re-read',
    );

    await authoring.planChange(null);
    expect(session.authoring.value.value!.plan, isNull);
    expect(
      () => session.openPlanDocument(
        revised.document!,
        origin: authoring.stamp(authoring.revision),
      ),
      throwsA(_failureMatcher(StudioFailureCode.superseded)),
      reason: 'an absent plan has no readable document identity',
    );
    await scope.close();
    expect(
      firstPin.closeCalls,
      1,
      reason: 'closing the borrowed scope joins its original native scope once',
    );
  });

  test(
    'content capacity recovery keeps facet synchronization independent',
    () async {
      final fixture = ConversationFixture();
      addTearDown(() => _closeOwner(fixture));
      final session = fixture.select('thread');
      final execution = _ExecutionFeed(await fixture.facets.executionOpened(0));
      await execution.baseline(status: ThreadStatus.running, active: _turn(7));
      expect(session.execution.value.sync.phase, FacetSyncPhase.ready);
      expect(session.execution.value.sync.error, isNull);

      final frames = <StudioTimelineFrame>[];
      final patched = Completer<StudioTimelinePatchFrame>();
      final lease = session.timeline.attachConsumer((frame) {
        frames.add(frame);
        if (frame is StudioTimelinePatchFrame && !patched.isCompleted) {
          patched.complete(frame);
        }
      });
      final refused = await fixture.timeline.opened(0);
      refused.result.completeError(
        const StudioFailure(
          code: StudioFailureCode.overloaded,
          message: 'The content handle budget is exhausted.',
          retryable: false,
          correlationId: 'timeline-capacity',
        ),
      );
      await session.timeline.state.waitFor(
        (state) => state.phase == TimelineConnectionPhase.failed,
      );
      expect(
        session.timeline.state.value.error!.code,
        StudioFailureCode.overloaded,
      );
      expect(
        session.execution.value.sync.phase,
        FacetSyncPhase.ready,
        reason: 'content admission never decides Thread state synchronization',
      );
      expect(session.execution.value.sync.error, isNull);

      session.timeline.refresh();
      final recovered = await fixture.timeline.opened(1);
      final connection = TestTimelineConnection(
        initial: baseline(1, subscriptionId: 'recovered'),
      );
      recovered.result.complete(connection);
      await session.timeline.ready;
      expect(session.timeline.state.value.phase, TimelineConnectionPhase.ready);
      expect(session.execution.value.sync.phase, FacetSyncPhase.ready);

      await execution.failure(
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'runtime offline',
          retryable: false,
          correlationId: 'execution-failure',
        ),
      );
      await session.execution.waitFor(
        (state) => state.sync.phase == FacetSyncPhase.failed,
      );
      connection.emit(patch(1, 2, subscriptionId: 'recovered'));
      expect(
        (await patched.future).patch.from,
        1,
        reason: 'the recovered attempt delivers its own patch to its consumer',
      );
      expect(
        session.execution.value.sync.phase,
        FacetSyncPhase.failed,
        reason: 'content progress cannot clear a real Thread state failure',
      );
      expect(session.execution.value.sync.error!.message, 'runtime offline');
      await lease.close();
    },
  );

  test('progress and terminal usage are observed while automatic retries stay bounded', () async {
    final timers = ControlledTimers();
    await runZoned(() async {
      final fixture = ConversationFixture();
      addTearDown(() => _closeOwner(fixture));
      final session = fixture.select('thread');
      var metrics = _MetricsFeed(await fixture.facets.metricsOpened(0));
      await metrics.baseline(_live(1));
      var opens = 1;
      expect(session.metrics.value.value!.live!.completionTokens, 1);

      // Real progress between outages never widens the per-demand retry bound;
      // the owner's explicit retry is the supported recovery (the settings VM
      // calls `ConversationSession.retry(ThreadFacet.metrics)`).
      for (var attempt = 0; attempt < 3; attempt++) {
        await metrics.replace(_live(attempt + 2));
        expect(
          session.metrics.value.value!.live!.completionTokens,
          attempt + 2,
        );
        await metrics.resyncRequired();
        await session.metrics.waitFor(
          (state) => state.sync.phase == FacetSyncPhase.reconnecting,
        );
        expect(
          session.metrics.value.value!.live!.completionTokens,
          attempt + 2,
          reason: 'the last valid metrics value survives the outage',
        );
        await timers.fireNext();
        final reopened = _MetricsFeed(
          await fixture.facets.metricsOpened(opens),
        );
        opens++;
        expect(
          reopened.opening.feed.feedId,
          isNot(metrics.opening.feed.feedId),
        );
        await reopened.baseline(_live(attempt + 3));
        expect(session.metrics.value.sync.phase, FacetSyncPhase.ready);
        metrics = reopened;
      }

      // One outage more than the per-demand retry bound: no timer is left and
      // the owner keeps the last valid value until an explicit retry.
      await metrics.resyncRequired();
      await session.metrics.waitFor(
        (state) =>
            state.sync.phase == FacetSyncPhase.reconnecting ||
            state.sync.phase == FacetSyncPhase.failed,
      );
      expect(
        session.metrics.value.sync.phase,
        FacetSyncPhase.failed,
        reason: 'automatic retries are bounded per demand',
      );
      expect(session.metrics.value.sync.retryExhausted, isTrue);
      expect(timers.hasPending, isFalse);

      final before = fixture.facets.metrics.length;
      await session.retry(ThreadFacet.metrics);
      expect(fixture.facets.metrics, hasLength(before + 1));
      final retried = _MetricsFeed(await fixture.facets.metricsOpened(before));
      await retried.baseline(_authoritative(20000));
      expect(session.metrics.value.sync.phase, FacetSyncPhase.ready);
      expect(
        session.metrics.value.value!.authoritative!.completionTokens,
        20000,
        reason: 'the terminal usage is observed after the explicit retry',
      );
    }, zoneSpecification: timers.specification);
  });

  for (final ended in [false, true]) {
    test(
      'facet-only ${ended ? 'EOF' : 'lagged'} outages exhaust their own bounded retries',
      () async {
        final timers = ControlledTimers();
        await runZoned(() async {
          final fixture = ConversationFixture();
          addTearDown(() => _closeOwner(fixture));
          final session = fixture.select('thread');
          var metrics = _MetricsFeed(await fixture.facets.metricsOpened(0));
          await metrics.baseline(_live(1));
          var opens = 1;
          while (true) {
            if (ended) {
              await metrics.opening.feed.close();
            } else {
              await metrics.resyncRequired();
            }
            await session.metrics.waitFor(
              (state) =>
                  state.sync.phase == FacetSyncPhase.reconnecting ||
                  state.sync.phase == FacetSyncPhase.failed,
            );
            if (session.metrics.value.sync.phase == FacetSyncPhase.failed)
              break;
            await timers.fireNext();
            metrics = _MetricsFeed(await fixture.facets.metricsOpened(opens));
            opens++;
            await metrics.baseline(_live(1));
            expect(
              session.metrics.value.sync.phase,
              FacetSyncPhase.ready,
              reason: 'a retried attempt resumes from its own baseline',
            );
            expect(opens, lessThanOrEqualTo(4));
          }
          expect(
            session.metrics.value.sync.retryExhausted,
            isTrue,
            reason: 'a facet-only outage never renews its own retry budget',
          );
          expect(timers.hasPending, isFalse);
          expect(
            fixture.facets.metrics,
            hasLength(4),
            reason: 'one initial attempt plus exactly three retries',
          );
        }, zoneSpecification: timers.specification);
      },
    );
  }

  test(
    'a genuine facet revision gap keeps the last valid owner facts',
    () async {
      final fixture = ConversationFixture();
      addTearDown(() => _closeOwner(fixture));
      final session = fixture.select('thread');
      final execution = _ExecutionFeed(await fixture.facets.executionOpened(0));
      await execution.baseline(status: ThreadStatus.running, active: _turn(7));
      await execution.change(
        status: ThreadStatus.running,
        active: _turn(7, revision: 2),
      );
      expect(session.execution.value.stamp!.revision, 2);
      await execution.sendUnacknowledged(
        ThreadExecutionFrame.data(
          deliverySequence: execution.sequence + 1,
          event: ThreadExecutionEvent.change(
            stamp: execution.stamp(execution.revision + 1),
            baseRevision: 9,
            value: ThreadExecutionChange(
              status: ThreadStatus.running,
              turns: TurnsReplacement(
                activeTurn: _turn(9),
                recentTerminalTurn: null,
              ),
              interactions: null,
              activity: const ActivityReplacement.unchanged(),
              storage: const StorageReplacement.unchanged(),
            ),
          ),
        ),
      );
      await session.execution.waitFor(
        (state) => state.sync.phase == FacetSyncPhase.failed,
      );
      expect(
        session.execution.value.sync.error!.message,
        contains('The facet revision is not continuous.'),
      );
      expect(
        session.execution.value.stamp!.revision,
        2,
        reason: 'a gap cannot advance the delivered revision',
      );
      expect(session.execution.value.value!.activeTurn, _turn(7, revision: 2));
      expect(
        fixture.facets.execution,
        hasLength(1),
        reason: 'a continuity violation is never replayed automatically',
      );
      await session.retry(ThreadFacet.execution);
      expect(fixture.facets.execution, hasLength(2));
      final reopened = _ExecutionFeed(
        await fixture.facets.executionOpened(1),
        incarnation: 2,
      );
      await reopened.baseline(status: ThreadStatus.idle);
      expect(session.execution.value.sync.phase, FacetSyncPhase.ready);
      expect(session.execution.value.value!.activeTurn, isNull);
    },
  );

  test('re-entering the same selection keeps the session, its sources and the draft owner', () async {
    final drafts = DraftsFixture();
    addTearDown(drafts.close);
    final startDraft = drafts.repository.start('project');
    startDraft.setText('draft before navigation');
    final draftState = startDraft.state.value;
    final composer = drafts.repository.composer('thread');
    composer.setText('composer text');
    final conversations = drafts.conversations;
    final session = conversations.select('thread');
    final timelineLease = session.timeline.attachConsumer((_) {});
    final opening = await conversations.timeline.opened(0);
    opening.result.complete(
      TestTimelineConnection(initial: baseline(3, subscriptionId: 'owned')),
    );
    await session.timeline.ready;
    final sources = conversations.facets.execution.length;

    conversations.demand.select(
      threadId: 'thread',
      needsOpen: false,
      selectionGeneration: 1,
    );
    expect(
      conversations.repository.active.value,
      same(session),
      reason: 'a repeated selection demand never rebuilds the owner',
    );
    expect(conversations.facets.execution, hasLength(sources));
    expect(conversations.timeline.requests, hasLength(1));
    expect(
      (session.timeline as dynamic).state.value.phase,
      TimelineConnectionPhase.ready,
    );
    expect(identical(drafts.repository.start('project'), startDraft), isTrue);
    expect(startDraft.state.value.text, 'draft before navigation');
    expect(startDraft.state.value.stamp, draftState.stamp);
    expect(composer.state.value.text, 'composer text');
    await conversations.demand.retire(
      'thread',
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(composer.state.value.text, 'composer text');
    expect(startDraft.state.value.text, 'draft before navigation');
    await timelineLease.close();
  });

  test(
    'two owners never share a same-id session, timeline baseline or draft',
    () async {
      final left = ConversationFixture(clientId: 'left');
      final right = ConversationFixture(clientId: 'right');
      addTearDown(() => _closeOwner(left));
      addTearDown(() => _closeOwner(right));
      final leftSession = left.select('thread');
      final rightSession = right.select('thread');
      expect(identical(leftSession, rightSession), isFalse);
      final leftLease = leftSession.timeline.attachConsumer((_) {});
      final rightLease = rightSession.timeline.attachConsumer((_) {});
      final leftOpening = await left.timeline.opened(0);
      final rightOpening = await right.timeline.opened(0);
      leftOpening.result.complete(
        TestTimelineConnection(initial: baseline(1, subscriptionId: 'left')),
      );
      rightOpening.result.complete(
        TestTimelineConnection(initial: baseline(6, subscriptionId: 'right')),
      );
      expect((await leftSession.timeline.ready).baseline.version, 1);
      expect((await rightSession.timeline.ready).baseline.version, 6);
      await left.repository.close();
      expect(right.timeline.requests, hasLength(1));
      expect(
        rightSession.timeline.state.value.phase,
        TimelineConnectionPhase.ready,
      );
      await leftLease.close();
      await rightLease.close();
    },
  );

  test(
    'a late open and a first-baseline failure close their own connection',
    () async {
      final fixture = ConversationFixture();
      addTearDown(() => _closeOwner(fixture));
      final session = fixture.select('thread');
      final lease = session.timeline.attachConsumer((_) {});
      final late = await fixture.timeline.opened(0);
      await fixture.demand.retire('thread', deadline: DateTime.utc(2000));
      final connection = TestTimelineConnection(initial: baseline(99));
      late.result.complete(connection);
      await connection.closeCompleted.future;
      expect(
        connection.wasSubscribed,
        isFalse,
        reason: 'a late handle of a retired demand is closed, never subscribed',
      );
      expect(
        session.timeline.state.value.phase,
        isNot(TimelineConnectionPhase.ready),
      );

      final next = fixture.select('thread');
      final failed = TestTimelineConnection();
      final nextLease = next.timeline.attachConsumer((_) {});
      final opening = await fixture.timeline.opened(1);
      opening.result.complete(failed);
      await failed.subscribed.future;
      failed.emitStreamError(StateError('initial failed'));
      await failed.closeCompleted.future;
      await next.timeline.state.waitFor(
        (state) =>
            state.phase == TimelineConnectionPhase.reconnecting ||
            state.phase == TimelineConnectionPhase.failed,
      );
      expect(
        next.execution.value.sync.phase,
        isNot(FacetSyncPhase.failed),
        reason: 'a first content baseline failure never pollutes Thread state',
      );
      await lease.close();
      await nextLease.close();
    },
  );

  test('A to B to A never reuses an old timeline baseline', () async {
    final fixture = ConversationFixture();
    addTearDown(() => _closeOwner(fixture));
    final first = fixture.select('A');
    final firstLease = first.timeline.attachConsumer((_) {});
    final firstOpening = await fixture.timeline.opened(0);
    final old = TestTimelineConnection(
      initial: baseline(
        5,
        subscriptionId: 'first',
        items: [timelineItem(5, threadId: 'A')],
      ),
    );
    firstOpening.result.complete(old);
    await first.timeline.ready;
    await firstLease.close();
    await fixture.demand.retire(
      'A',
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(old.closeCalls, greaterThanOrEqualTo(1));

    fixture.select('B');
    final betweenOpening = await fixture.timeline.opened(1);
    betweenOpening.result.completeError(_cancelled);
    final reopened = fixture.select('A');
    expect(
      reopened,
      isNot(same(first)),
      reason: 'A-B-A selects a new incarnation, never the retired owner',
    );
    final delivered = Completer<StudioTimelinePatchFrame>();
    final secondLease = reopened.timeline.attachConsumer((frame) {
      if (frame is StudioTimelinePatchFrame && !delivered.isCompleted) {
        delivered.complete(frame);
      }
    });
    final secondOpening = await fixture.timeline.opened(2);
    final replacement = TestTimelineConnection(
      initial: baseline(
        1,
        subscriptionId: 'second',
        items: [timelineItem(1, threadId: 'A')],
      ),
    );
    secondOpening.result.complete(replacement);
    final ready = await reopened.timeline.ready;
    expect(ready.baseline.subscriptionId, 'second');
    expect(ready.baseline.version, 1);
    replacement.emit(patch(1, 2, subscriptionId: 'second'));
    expect(
      (await delivered.future).patch.from,
      1,
      reason: 'the new attempt continues only from its own baseline',
    );
    await replacement.acknowledged(2);
    expect(replacement.ackedThrough, 2);
    await secondLease.close();
  });

  test(
    'content demand belongs to the session, not to a Thread facet baseline',
    () async {
      final fixture = ConversationFixture();
      addTearDown(() => _closeOwner(fixture));
      final session = fixture.select('thread');
      final lease = session.timeline.attachConsumer((_) {});
      final opening = await fixture.timeline.opened(0);
      expect(opening.threadId, 'thread');
      final connection = TestTimelineConnection(initial: baseline(2));
      opening.result.complete(connection);
      final ready = await session.timeline.ready;
      expect(ready.baseline.version, 2);
      expect(
        session.execution.value.value,
        isNull,
        reason: 'content is admitted without any Thread status baseline',
      );
      expect(
        session.execution.value.sync.phase,
        isNot(FacetSyncPhase.ready),
        reason: 'no Thread status baseline was ever delivered',
      );
      await lease.close();
      expect(connection.closeCalls, greaterThanOrEqualTo(1));
    },
  );
}
