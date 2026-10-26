import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/diagnostics/conversation_status_diagnostics.dart';
import 'package:anywork/src/features/conversation/view_models/thread_context_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_metrics_view_model.dart';

import '../../test_driver/runtime_event_evidence.dart';
import '../../test_driver/runtime_evidence_observation.dart';
import '../../test_driver/conversation_status_observation.dart';
import '../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/conversation_workspace_fixture.dart';

const _epoch = 'metrics-recorder-test';
const _live = LiveTurnMetrics(
  identity: MetricsIdentityRef(entry: 7),
  completionTokens: 0,
  responseMillis: 0,
  state: TurnObservationState.live,
  observationSequence: 1,
);

final class _Open {
  _Open(this.reference, this.origin);
  final MetricsIdentityRef reference;
  final ThreadFacetStamp origin;
  final result = Completer<MetricsIdentityReadConnection>();
}

final class _Port implements ConversationObservationPort {
  final feeds = FixtureConversationPort();
  final opens = <_Open>[];
  final _waiting = <int, Completer<_Open>>{};
  Future<_Open> opened(int index) => index < opens.length
      ? Future.value(opens[index])
      : _waiting.putIfAbsent(index, Completer<_Open>.new).future;
  @override
  Future<MetricsIdentityReadConnection> openMetricsIdentityRead(
    String id,
    MetricsIdentityRef reference, {
    required ThreadFacetStamp origin,
  }) {
    final call = _Open(reference, origin);
    opens.add(call);
    _waiting.remove(opens.length - 1)?.complete(call);
    return call.result.future;
  }

  @override
  Future<FeedConnection<ThreadExecutionFrame>> openThreadExecution(
    String id, {
    required ThreadObservationMode mode,
  }) => feeds.openThreadExecution(id, mode: mode);
  @override
  Future<FeedConnection<ThreadMetricsFrame>> openThreadMetrics(
    String id, {
    required ThreadObservationMode mode,
  }) => feeds.openThreadMetrics(id, mode: mode);
  @override
  Future<FeedConnection<ThreadContextFrame>> openThreadContext(
    String id, {
    required ThreadObservationMode mode,
  }) => feeds.openThreadContext(id, mode: mode);
  @override
  Future<FeedConnection<ThreadConfigurationFrame>> openThreadConfiguration(
    String id, {
    required ThreadObservationMode mode,
  }) => feeds.openThreadConfiguration(id, mode: mode);
  @override
  Future<FeedConnection<ThreadAuthoringFrame>> openThreadAuthoring(
    String id, {
    required ThreadObservationMode mode,
  }) => feeds.openThreadAuthoring(id, mode: mode);
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unscripted read: ${invocation.memberName}');
}

final class _Pin implements MetricsIdentityReadConnection {
  _Pin(ThreadFacetStamp origin, {int? sourceRevision})
    : headerValue = MetricsIdentityReadHeader(
        scope: ReadScopeIdentity(
          scopeId: 'identity-scope',
          runtimeEpoch: origin.runtimeEpoch,
          incarnation: origin.incarnation,
          sourceRevision: sourceRevision ?? origin.revision,
        ),
        turnId: const ReadText.inline(text: 'turn'),
        attemptId: const ReadText.inline(text: 'attempt'),
      );
  final MetricsIdentityReadHeader headerValue;
  final headerStarted = Completer<void>(), closeStarted = Completer<void>();
  Completer<MetricsIdentityReadHeader>? headerReply;
  Completer<FeedCloseReport>? closeReply;
  FeedCloseOutcome outcome = const FeedCloseOutcome.clean();
  int headerCalls = 0, closeCalls = 0, retryCalls = 0;
  bool sealed = false;
  @override
  Future<MetricsIdentityReadHeader> header() {
    if (sealed) {
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Original scripted identity is sealed',
        retryable: false,
        correlationId: 'pin',
      );
    }
    headerCalls++;
    if (!headerStarted.isCompleted) headerStarted.complete();
    return headerReply?.future ?? Future.value(headerValue);
  }

  @override
  void requestClose() => sealed = true;
  @override
  Future<FeedCloseReport> close() {
    closeCalls++;
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    return closeReply?.future ??
        Future.value(
          FeedCloseReport(feedId: 'identity-scope', outcome: outcome),
        );
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCalls++;
    return close();
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted identity text: ${invocation.memberName}',
  );
}

final class _Fixture {
  _Fixture({this.terminal = false}) {
    operations = OperationRegistry(clientId: 'metrics-test', budget: budget);
    final assembly = createConversationRepository(
      port: port,
      context: FixtureConversationContext(),
      commands: const UnscriptedConversationCommands(),
      timeline: timeline,
      budget: budget,
      operations: operations,
      agentDirectory: () => workspaceOwner.workspace.agents,
    );
    repository = assembly.repository;
    demand = assembly.demand;
    workspaceOwner = ConversationWorkspaceFixture(
      budget: budget,
      operations: operations,
      archive: assembly.archive,
    );
    addTearDown(() async {
      await workspaceOwner.close();
      final report = await repository.close(
        deadline: DateTime.now().add(const Duration(seconds: 3)),
      );
      if (terminal) {
        expect(report.unresolved, isNotEmpty);
        expect(
          report.unresolved
              .expand((resource) => resource.issues)
              .any(
                (issue) =>
                    issue.diagnostic.code == 'fixtureTerminal' &&
                    issue.recovery == CleanupRecovery.terminal,
              ),
          isTrue,
        );
      } else {
        expect(report.unresolved, isEmpty);
        expect(budget.usage, isEmpty);
      }
    });
  }
  final bool terminal;
  final budget = ResourceBudget();
  final port = _Port();
  final timeline = TimelineOpenQueue();
  late final OperationRegistry operations;
  late final ConversationWorkspaceFixture workspaceOwner;
  late final ConversationRepository repository;
  late final ConversationDemand demand;
  late ConversationSession session;
  int revision = 1;
  int contextRevision = 0;
  ThreadFacetStamp get stamp => ThreadFacetStamp(
    runtimeEpoch: _epoch,
    incarnation: 1,
    facet: ThreadFacet.metrics,
    revision: revision,
  );
  Future<void> establish({
    LiveTurnMetrics? live,
    AuthoritativeTurnMetrics? authoritative,
  }) async {
    demand.select(threadId: 'thread', needsOpen: false, selectionGeneration: 1);
    session = repository.active.value!;
    session.timeline.attachConsumer((_) {});
    final opening = await timeline.opened(0);
    opening.result.complete(
      TestTimelineConnection(initial: baseline(1, items: [timelineItem(1)])),
    );
    await session.timeline.ready;
    final feed = port.feeds.metrics.single.feed;
    await feed.listened.future;
    feed.emit(
      ThreadMetricsFrame.data(
        deliverySequence: 1,
        event: ThreadMetricsEvent.baseline(
          identity: ThreadFeedIdentity(
            feedId: feed.feedId,
            runtimeEpoch: _epoch,
            incarnation: 1,
            facet: ThreadFacet.metrics,
            mode: ThreadObservationMode.live,
          ),
          stamp: stamp,
          value: ThreadMetricsValue(live: live, authoritative: authoritative),
        ),
      ),
    );
    await feed.acknowledged(1);
  }

  Future<void> publish(
    LiveTurnMetrics? live, {
    AuthoritativeTurnMetrics? authoritative,
  }) async {
    revision++;
    final feed = port.feeds.metrics.single.feed;
    feed.emit(
      ThreadMetricsFrame.data(
        deliverySequence: revision,
        event: ThreadMetricsEvent.replace(
          stamp: stamp,
          value: ThreadMetricsValue(live: live, authoritative: authoritative),
        ),
      ),
    );
    await feed.acknowledged(revision);
  }

  Future<void> publishContext(ThreadContextValue value) async {
    final feed = port.feeds.context.single.feed;
    await feed.listened.future;
    final revision = ++contextRevision;
    final stamp = ThreadFacetStamp(
      runtimeEpoch: _epoch,
      incarnation: 1,
      facet: ThreadFacet.context,
      revision: revision,
    );
    feed.emit(
      ThreadContextFrame.data(
        deliverySequence: revision,
        event: revision == 1
            ? ThreadContextEvent.baseline(
                identity: ThreadFeedIdentity(
                  feedId: feed.feedId,
                  runtimeEpoch: _epoch,
                  incarnation: 1,
                  facet: ThreadFacet.context,
                  mode: ThreadObservationMode.live,
                ),
                stamp: stamp,
                value: value,
              )
            : ThreadContextEvent.replace(stamp: stamp, value: value),
      ),
    );
    await feed.acknowledged(revision);
  }

  RuntimeEventEvidenceRecorder recorder({int factLimit = 4096}) {
    final recorder = RuntimeEventEvidenceRecorder(factLimit: factLimit);
    addTearDown(() async {
      final report = await recorder.close(
        deadline: DateTime.now().add(const Duration(seconds: 3)),
      );
      expect(report.complete, !terminal);
    });
    return recorder;
  }
}

void main() {
  test('empty baseline keeps target separate and stop joins the real read/close before publishing evidence', () async {
    final fixture = _Fixture();
    await fixture.establish();
    final recorder = fixture.recorder();
    final observers = fixture.session.metrics.observerCount;
    final start = await recorder.start(
      conversations: fixture.repository,
      threadId: 'thread',
      turnId: 'turn',
    );
    expect(start['ok'], isTrue);
    final initial = start['baseline'] as Map;
    expect(initial['observedIdentity'], isNull);
    expect(initial['live'], isNull);
    expect(fixture.port.opens, isEmpty);
    await fixture.publish(_live);
    final opening = await fixture.port.opened(0);
    final pin = _Pin(opening.origin)
      ..headerReply = Completer<MetricsIdentityReadHeader>()
      ..closeReply = Completer<FeedCloseReport>();
    opening.result.complete(pin);
    await pin.headerStarted.future;
    await fixture.publish(
      _live.copyWith(
        observationSequence: 2,
        completionTokens: 12,
        responseMillis: 30,
      ),
    );
    await fixture.publish(null);
    var completed = false;
    final stopping = recorder.stop().then((value) {
      completed = true;
      return value;
    });
    final repeated = recorder.stop();
    expect(fixture.session.metrics.observerCount, observers);
    pin.headerReply!.complete(pin.headerValue);
    await pin.closeStarted.future;
    expect(
      completed,
      isFalse,
      reason: 'Observer cancellation did not join the blocked native close',
    );
    pin.closeReply!.complete(
      FeedCloseReport(
        feedId: 'identity-scope',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final result = await stopping;
    final evidence = DriverRuntimePublishEvidence.parse(
      result,
      expectedThreadId: 'thread',
      expectedTurnId: 'turn',
    );
    expect(evidence.boundedAndClosed, isTrue);
    expect(evidence.identityStable, isTrue);
    expect(evidence.liveSequenceIncreasing, isTrue);
    expect(evidence.liveMetricsRevisionsIncreasing, isTrue);
    expect(evidence.clearedAfterLive, isTrue);
    expect(evidence.liveFacts.first.completionTokens, 0);
    expect(evidence.liveFacts.first.responseMillis, 0);
    expect(
      opening.origin.revision,
      2,
      reason: 'Header source uses first frozen origin, not later revision 3/4',
    );
    expect(
      fixture.port.opens,
      hasLength(1),
      reason: 'Only the verified pure-ID association is reused',
    );
    expect(pin.closeCalls, 1);
    expect((await repeated)['errorCode'], 'alreadyStopped');
    expect(fixture.repository.active.value, same(fixture.session));
    expect(
      () => DriverRuntimePublishEvidence.parse(
        {...result, 'streamEpoch': 1},
        expectedThreadId: 'thread',
        expectedTurnId: 'turn',
      ),
      throwsStateError,
    );
    final legacyFacts = [
      for (final value in result['facts'] as List)
        Map<String, Object?>.of((value as Map).cast<String, Object?>()),
    ];
    legacyFacts[1]['live'] = <String, Object?>{
      ...(legacyFacts[1]['live'] as Map).cast<String, Object?>(),
      'latestContextTokens': 0,
    };
    expect(
      () => DriverRuntimePublishEvidence.parse(
        {...result, 'facts': legacyFacts},
        expectedThreadId: 'thread',
        expectedTurnId: 'turn',
      ),
      throwsStateError,
    );
  });

  test('starting claims the run and Superseded is a failed pure read, not a fake resource issue or current rebind', () async {
    final fixture = _Fixture();
    await fixture.establish(live: _live);
    final recorder = fixture.recorder();
    final starting = recorder.start(
      conversations: fixture.repository,
      threadId: 'thread',
      turnId: 'turn',
    );
    final opening = await fixture.port.opened(0);
    final duplicate = await recorder.start(
      conversations: fixture.repository,
      threadId: 'thread',
      turnId: 'turn',
    );
    expect(duplicate['errorCode'], 'alreadyRecording');
    final pin = _Pin(opening.origin)
      ..headerReply = Completer<MetricsIdentityReadHeader>();
    opening.result.complete(pin);
    await pin.headerStarted.future;
    pin.headerReply!.completeError(
      const StudioFailure(
        code: StudioFailureCode.superseded,
        message: 'private-native-error-body',
        retryable: true,
        correlationId: 'original-superseded',
      ),
    );
    expect((await starting)['ok'], isFalse);
    final result = await recorder.stop();
    expect(result['ok'], isFalse);
    expect(result['readsJoined'], isTrue);
    expect(result['scopesClosed'], isTrue);
    expect(result['closeUnresolved'], isEmpty);
    expect((result['failure'] as Map)['code'], 'superseded');
    expect(jsonEncode(result), isNot(contains('private-native-error-body')));
    expect(fixture.port.opens, hasLength(1));
    expect(fixture.session.metrics.value.sync.phase, FacetSyncPhase.ready);
    expect(
      (await recorder.start(
        conversations: fixture.repository,
        threadId: 'thread',
        turnId: 'turn',
      ))['errorCode'],
      'runCompleted',
    );
  });

  test('shutdown seals before late scope return and retains original opening until its true close joins', () async {
    final fixture = _Fixture();
    await fixture.establish(live: _live);
    final recorder = fixture.recorder();
    final starting = recorder.start(
      conversations: fixture.repository,
      threadId: 'thread',
      turnId: 'turn',
    );
    final opening = await fixture.port.opened(0);
    final pending = await recorder.close(deadline: DateTime.utc(2000));
    expect(pending.complete, isFalse);
    expect(
      pending.unresolved
          .expand((resource) => resource.issues)
          .every((issue) => issue.recovery == CleanupRecovery.awaitCompletion),
      isTrue,
    );
    final pin = _Pin(opening.origin)..closeReply = Completer<FeedCloseReport>();
    opening.result.complete(pin);
    await pin.closeStarted.future;
    expect(
      pin.headerCalls,
      0,
      reason: 'Shutdown cannot dispatch header/text after the late open',
    );
    pin.closeReply!.complete(
      FeedCloseReport(
        feedId: 'identity-scope',
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    expect((await recorder.retryCleanup()).complete, isTrue);
    expect((await starting)['errorCode'], 'cancelledByShutdown');
    expect(fixture.repository.active.value, same(fixture.session));
  });

  test('a bounded stop during start settles the start receipt but retains its original pending scope join', () async {
    final fixture = _Fixture();
    await fixture.establish(live: _live);
    final recorder = fixture.recorder();
    final starting = recorder.start(
      conversations: fixture.repository,
      threadId: 'thread',
      turnId: 'turn',
    );
    final opening = await fixture.port.opened(0);
    final pin = _Pin(opening.origin)
      ..headerReply = Completer<MetricsIdentityReadHeader>();
    opening.result.complete(pin);
    await pin.headerStarted.future;
    final stopped = await recorder.stop(deadline: DateTime.utc(2000));
    expect(stopped['ok'], isFalse);
    expect(stopped['readsJoined'], isFalse);
    expect(stopped['errorCode'], 'closeUnresolved');
    expect(
      (await starting)['ok'],
      isFalse,
      reason: 'An expired stop must not strand its original starting receipt',
    );
    pin.headerReply!.complete(pin.headerValue);
    expect((await recorder.retryCleanup()).complete, isTrue);
    expect(fixture.port.opens, hasLength(1));
    expect(pin.closeCalls, 1);
  });

  test('terminal native close issues survive later Clean and output only their safe typed metadata', () async {
    final fixture = _Fixture(terminal: true);
    await fixture.establish(live: _live);
    final recorder = fixture.recorder();
    final starting = recorder.start(
      conversations: fixture.repository,
      threadId: 'thread',
      turnId: 'turn',
    );
    final opening = await fixture.port.opened(0);
    final pin = _Pin(opening.origin)
      ..outcome = FeedCloseOutcome.unresolved(
        issues: [
          const FeedCloseIssue(
            diagnostic: StudioShutdownIssue(
              stage: 'native',
              code: 'fixtureTerminal',
              message: 'private-native-close-body',
              retryable: false,
              correlationId: 'native-close-id',
            ),
            recovery: CleanupRecovery.terminal,
          ),
        ],
      );
    opening.result.complete(pin);
    expect((await starting)['ok'], isFalse);
    final result = await recorder.stop();
    expect(result['scopesClosed'], isFalse);
    expect(result['closeUnresolved'], isNotEmpty);
    expect(jsonEncode(result), isNot(contains('private-native-close-body')));
    pin.outcome = const FeedCloseOutcome.clean();
    final retained = await recorder.retryCleanup();
    expect(retained.complete, isFalse);
    expect(pin.retryCalls, 0);
    expect(pin.closeCalls, 1);
    expect(
      retained.unresolved
          .expand((resource) => resource.issues)
          .every((issue) => issue.recovery == CleanupRecovery.terminal),
      isTrue,
    );
  });

  test('facts plus admitted read and queued metadata overflow fails without trimming or leaking the read', () async {
    final fixture = _Fixture();
    await fixture.establish();
    final recorder = fixture.recorder(factLimit: 4);
    expect(
      (await recorder.start(
        conversations: fixture.repository,
        threadId: 'thread',
        turnId: 'turn',
      ))['ok'],
      isTrue,
    );
    await fixture.publish(_live);
    final opening = await fixture.port.opened(0);
    final pin = _Pin(opening.origin)
      ..headerReply = Completer<MetricsIdentityReadHeader>();
    opening.result.complete(pin);
    await pin.headerStarted.future;
    await fixture.publish(_live.copyWith(observationSequence: 2));
    await fixture.publish(null);
    pin.headerReply!.complete(pin.headerValue);
    final result = await recorder.stop();
    expect(result['ok'], isFalse);
    expect(result['overflowed'], isTrue);
    expect(result['errorCode'], 'factOverflow');
    expect(result['factCount'], 1);
    expect(result['readsJoined'], isTrue);
    expect(result['scopesClosed'], isTrue);
    expect(fixture.port.opens, hasLength(1));
    expect(pin.closeCalls, 1);
  });

  test('header cannot substitute a later Metrics revision for the scope original frozen origin', () async {
    final fixture = _Fixture();
    await fixture.establish(live: _live);
    final recorder = fixture.recorder();
    final starting = recorder.start(
      conversations: fixture.repository,
      threadId: 'thread',
      turnId: 'turn',
    );
    final opening = await fixture.port.opened(0);
    await fixture.publish(_live.copyWith(observationSequence: 2));
    final pin = _Pin(opening.origin, sourceRevision: fixture.revision);
    expect(opening.origin.revision, 1);
    expect(fixture.revision, 2);
    opening.result.complete(pin);
    expect((await starting)['ok'], isFalse);
    final result = await recorder.stop();
    expect((result['failure'] as Map)['code'], 'protocol');
    expect(result['scopesClosed'], isTrue);
    expect(result['closeUnresolved'], isEmpty);
    expect(fixture.port.opens, hasLength(1));
  });

  test('real Context and Metrics AsyncNotifiers keep zero, cumulative counts and independent updates across live clear', () async {
    final fixture = _Fixture();
    const authoritative = AuthoritativeTurnMetrics(
      identity: MetricsIdentityRef(entry: 8),
      completionTokens: 25,
      responseMillis: 1000,
    );
    await fixture.establish(authoritative: authoritative);
    const usage = ContextUsage(
      hasIncompleteUsage: false,
      contextWindow: null,
      maxContextWindow: null,
      autoCompactLimit: null,
      latestContextTokens: 100,
      promptTokens: 200,
      completionTokens: 42,
      cachedPromptTokens: 50,
      cacheWriteTokens: 0,
      reasoningTokens: 7,
      inferenceCount: 3,
      totalTokens: 242,
      cacheUsage: CacheUsageSummary(
        inputTokens: 200,
        cacheReadTokens: 50,
        hitRate: .25,
        hasIncompleteUsage: false,
      ),
      estimatedCostCount: 0,
      estimatedCacheSavingCount: 0,
      hasUnpricedUsage: false,
      promptGeneration: null,
      prefixChangedReason: null,
      updatedAt: 1,
    );
    final initial = ThreadContextValue(
      usage: usage,
      currentPolicy: null,
      liveContext: null,
      details: const ContextReadRef(entry: 9, revision: 1),
    );
    await fixture.publishContext(initial);
    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(fixture.repository),
      ],
    );
    addTearDown(container.dispose);
    var metricsChanges = 0, contextChanges = 0;
    final metrics = container.listen(
      threadMetricsViewModelProvider('thread')
          .select((value) => value.asData?.value.tokensPerSecond),
      (_, _) => metricsChanges++,
    );
    final context = container.listen(
      threadContextViewModelProvider('thread')
          .select((value) => value.asData?.value.usedTokens),
      (_, _) => contextChanges++,
    );
    addTearDown(metrics.close);
    addTearDown(context.close);
    await container.read(threadMetricsViewModelProvider('thread').future);
    await container.read(threadContextViewModelProvider('thread').future);
    expect(metrics.read(), 25);
    expect(context.read(), 100);
    metricsChanges = 0;
    contextChanges = 0;
    await fixture.publish(
      _live.copyWith(completionTokens: 10, responseMillis: null),
      authoritative: authoritative,
    );
    expect(
      metrics.read(),
      25,
      reason: 'Partial live cannot borrow the previous denominator',
    );
    expect(metricsChanges, 0);
    expect(contextChanges, 0);
    await fixture.publish(
      _live.copyWith(
        observationSequence: 2,
        completionTokens: 20,
        responseMillis: 500,
      ),
      authoritative: authoritative,
    );
    expect(metrics.read(), 40);
    expect(contextChanges, 0);
    await fixture.publishContext(
      initial.copyWith(
        liveContext: const LiveContext(
          identity: MetricsIdentityRef(entry: 7),
          latestContextTokens: 0,
          state: TurnObservationState.live,
        ),
      ),
    );
    expect(context.read(), 0);
    expect(metrics.read(), 40);
    final snapshot = <String, dynamic>{
      'driverDiagnostics': <String, Object?>{
        'schemaVersion': 2,
        ...conversationStatusDiagnostics(fixture.session),
      },
    };
    final canonicalContext = driverContextObservation(snapshot);
    expect(canonicalContext.liveLatestContextTokens, 0);
    expect(canonicalContext.completionTokens, 42);
    expect(canonicalContext.contextWindow, isNull);
    await fixture.publish(null, authoritative: authoritative);
    expect(metrics.read(), 25);
    expect(context.read(), 0);
    await fixture.publishContext(
      initial.copyWith(details: const ContextReadRef(entry: 9, revision: 3)),
    );
    expect(
      context.read(),
      100,
      reason: 'Metrics clear never clears canonical Context usage',
    );
    expect(
      fixture.port.opens,
      isEmpty,
      reason: 'Read-only projections do not materialize native identity/detail scopes',
    );
    expect(fixture.repository.active.value, same(fixture.session));
  });
}
