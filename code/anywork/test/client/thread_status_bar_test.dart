import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/conversation/view_models/thread_context_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_metrics_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_status_view_model.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/timeline_drafts_environment.dart';
import '../../../anywork_client/test/support/timeline_transport.dart';

/// The former runtime projection is now split into independent canonical
/// facets. Exercise the actual feed owners and generated VMs, not a writable
/// workspace snapshot or a test copy of the status policy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('idle follows canonical context policy; a running request keeps its frozen limit', () async {
    final fixture = await _StatusFixture.open();
    final context = fixture.container.listen(
      threadContextViewModelProvider('thread-main'),
      (_, _) {},
    );
    addTearDown(context.close);
    await fixture.container.read(
      threadContextViewModelProvider('thread-main').future,
    );
    await fixture.context(_context(policyLimit: 14780, catalogRevision: 2));
    final idle = context.read().requireValue;
    expect(idle.displayLimit, 14780);
    expect(idle.currentPolicy?.contextWindow, 1050000);
    expect(
      idle.frozenUsage?.autoCompactLimit,
      922000,
      reason: 'catalog changes must not rewrite the historical request binding',
    );

    // Execution, not a local busy flag, chooses the frozen policy for a Turn.
    await fixture.native.emitExecution(
      draftExecution(
        status: ThreadStatus.running,
        active: const TurnBrief(
          reference: TurnReadRef(entry: 1, revision: 1),
          revision: 1,
          updatedAt: 1,
          state: TurnBriefState.running(
            startedAt: 1,
            phase: TurnPhase.responding,
          ),
        ),
      ),
    );
    expect(context.read().requireValue.displayLimit, 922000);
    expect(context.read().requireValue.currentPolicy?.autoCompactLimit, 14780);

    await fixture.native.emitExecution(draftExecution());
    await fixture.context(_context(policyLimit: null, catalogRevision: 3));
    expect(
      context.read().requireValue.displayLimit,
      isNull,
      reason: 'Unknown policy must not reuse an old threshold',
    );
    expect(context.read().requireValue.frozenUsage?.autoCompactLimit, 922000);

    // A late old facet frame must never restore the old catalog policy. The
    // repository may reject/reconnect that source, but last-known remains new.
    final feed = fixture.native.conversations.facets.context.single.feed;
    feed.emit(
      ThreadContextFrame.data(
        deliverySequence: 3,
        event: ThreadContextEvent.replace(
          stamp: draftFacet(ThreadFacet.context, 1),
          value: _context(policyLimit: 14780, catalogRevision: 2),
        ),
      ),
    );
    await fixture.native.conversations.repository
        .existingSession('thread-main')!
        .context
        .waitFor((state) => state.sync.phase != FacetSyncPhase.ready);
    expect(
      context.read().requireValue.displayLimit,
      isNull,
      reason: 'late catalog cannot undo the newer Unknown policy',
    );
  });

  test('throughput is isolated from context, capability chrome and unrelated execution facts', () async {
    final fixture = await _StatusFixture.open();
    final session = fixture.native.conversations.repository.existingSession(
      'thread-main',
    )!;
    fixture.composer.setText('keep this draft');
    await fixture.metrics(
      const ThreadMetricsValue(
        live: null,
        authoritative: AuthoritativeTurnMetrics(
          identity: MetricsIdentityRef(entry: 1),
          completionTokens: 25,
          responseMillis: 1000,
        ),
      ),
    );
    await fixture.context(_context(policyLimit: 14780));
    await fixture.configuration(
      session.configuration.value.value!.copyWith(activeSkillCount: 1),
    );

    var throughputNotifications = 0;
    var contextNotifications = 0;
    var chromeNotifications = 0;
    final throughputProvider = threadMetricsViewModelProvider('thread-main')
        .select((value) => value.asData?.value.tokensPerSecond);
    final contextProvider = threadContextViewModelProvider('thread-main')
        .select((value) => value.asData?.value.usedTokens);
    final chromeProvider = threadStatusViewModelProvider('thread-main')
        .select((value) => value.asData?.value.configuration?.value);
    final throughput = fixture.container.listen(
      throughputProvider,
      (_, _) => throughputNotifications++,
    );
    final context = fixture.container.listen(
      contextProvider,
      (_, _) => contextNotifications++,
    );
    final chrome = fixture.container.listen(
      chromeProvider,
      (_, _) => chromeNotifications++,
    );
    await Future.wait([
      fixture.container.read(
        threadMetricsViewModelProvider('thread-main').future,
      ),
      fixture.container.read(
        threadContextViewModelProvider('thread-main').future,
      ),
      fixture.container.read(
        threadStatusViewModelProvider('thread-main').future,
      ),
    ]);
    await fixture.container.pump();
    expect(throughput.read(), 25);
    expect(context.read(), 100);
    expect(chrome.read()?.activeSkillCount, 1);
    expect(chrome.read()?.activeMcp, ThreadCapabilitySupport.unsupported);
    expect(chrome.read()?.activeLsp, ThreadCapabilitySupport.unsupported);
    throughputNotifications = contextNotifications = chromeNotifications = 0;
    final observers = fixture.native.budget.used(ResourceKind.observer);
    final timelineConnections =
        fixture.native.conversations.timeline.requests.length;

    await fixture.metrics(
      const ThreadMetricsValue(
        live: LiveTurnMetrics(
          identity: MetricsIdentityRef(entry: 2),
          completionTokens: 10,
          responseMillis: null,
          state: TurnObservationState.live,
          observationSequence: 1,
        ),
        authoritative: AuthoritativeTurnMetrics(
          identity: MetricsIdentityRef(entry: 1),
          completionTokens: 25,
          responseMillis: 1000,
        ),
      ),
    );
    expect(
      throughput.read(),
      25,
      reason: 'a partial live sample must keep the confirmed Turn pair',
    );
    expect(contextNotifications, 0);
    expect(chromeNotifications, 0);

    await fixture.metrics(
      const ThreadMetricsValue(
        live: LiveTurnMetrics(
          identity: MetricsIdentityRef(entry: 2),
          completionTokens: 20,
          responseMillis: 500,
          state: TurnObservationState.live,
          observationSequence: 2,
        ),
        authoritative: AuthoritativeTurnMetrics(
          identity: MetricsIdentityRef(entry: 1),
          completionTokens: 25,
          responseMillis: 1000,
        ),
      ),
    );
    expect(throughput.read(), 40);
    expect(throughputNotifications, 1);
    expect(contextNotifications, 0);
    expect(chromeNotifications, 0);

    final beforeInvalidate = chrome.read();
    fixture.container.invalidate(threadStatusViewModelProvider('thread-main'));
    await fixture.container.read(
      threadStatusViewModelProvider('thread-main').future,
    );
    await fixture.container.pump();
    expect(
      chrome.read(),
      beforeInvalidate,
      reason:
          'rebuilding without canonical capability changes preserves the value',
    );
    expect(chromeNotifications, 0);

    await fixture.native.emitExecution(
      draftExecution(durable: 8).copyWith(
        activity: const ActivityBrief(
          reference: ActivityReadRef(entry: 4, revision: 1),
          revision: 1,
          kind: ThreadActivityKind.responding,
          toolCount: 0,
          backgroundCount: 0,
          activeCount: 0,
          hasLatestStarted: false,
        ),
      ),
    );
    expect(throughput.read(), 40);
    expect(throughputNotifications, 1);
    expect(contextNotifications, 0);
    expect(chromeNotifications, 0);

    await fixture.configuration(
      session.configuration.value.value!.copyWith(activeSkillCount: 2),
    );
    expect(chrome.read()?.activeSkillCount, 2);
    expect(chromeNotifications, 1);
    expect(throughput.read(), 40);
    expect(throughputNotifications, 1);
    expect(contextNotifications, 0);
    expect(
      fixture.native.conversations.timeline.requests,
      hasLength(timelineConnections),
    );
    expect(
      fixture.native.conversations.repository.existingSession('thread-main'),
      same(session),
    );

    final alt = fixture.container.listen(
      threadMetricsViewModelProvider('thread-alt'),
      (_, _) {},
    );
    await fixture.container.read(
      threadMetricsViewModelProvider('thread-alt').future,
    );
    expect(alt.read().requireValue.tokensPerSecond, isNull);
    alt.close();
    throughput.close();
    context.close();
    chrome.close();
    await fixture.container.pump();
    expect(
      fixture.native.conversations.repository.existingSession('thread-main'),
      same(session),
    );
    expect(fixture.composer.state.value.text, 'keep this draft');
    expect(
      fixture.native.budget.used(ResourceKind.observer),
      lessThan(observers),
    );
  });
}

ThreadContextValue _context({
  required int? policyLimit,
  int catalogRevision = 1,
}) => ThreadContextValue(
  usage: const ContextUsage(
    hasIncompleteUsage: false,
    contextWindow: 1050000,
    maxContextWindow: null,
    autoCompactLimit: 922000,
    latestContextTokens: 100,
    promptTokens: 100,
    completionTokens: 25,
    cachedPromptTokens: 0,
    cacheWriteTokens: 0,
    reasoningTokens: 0,
    inferenceCount: 1,
    totalTokens: 125,
    cacheUsage: CacheUsageSummary(
      inputTokens: 100,
      cacheReadTokens: 0,
      hitRate: 0,
      hasIncompleteUsage: false,
    ),
    estimatedCostCount: 0,
    estimatedCacheSavingCount: 0,
    hasUnpricedUsage: false,
    promptGeneration: 1,
    prefixChangedReason: null,
    updatedAt: 1,
  ),
  liveContext: null,
  currentPolicy: CurrentContextPolicy(
    sources: ConfigProjectionStamp(
      settingsRevision: 1,
      modelCatalogRevision: catalogRevision,
      closing: false,
    ),
    modeRevision: 1,
    routeRevision: 1,
    contextWindow: 1050000,
    maxContextWindow: null,
    inputTokenLimit: 922000,
    autoCompactLimit: policyLimit,
    unavailable: null,
    adjustment: null,
  ),
  details: const ContextReadRef(entry: 3, revision: 1),
);

final class _StatusFixture {
  _StatusFixture(this.native, this.composer, this.container);
  final TimelineDraftsEnvironment native;
  final ComposerDraft composer;
  final ProviderContainer container;
  int _metricsRevision = 0;
  int _contextRevision = 0;
  int _configurationRevision = 1;

  static Future<_StatusFixture> open() async {
    final native = await openTimelineDraftsEnvironment();
    final composer = await native.composer(threadId: 'thread-main');
    final opening = await native.conversations.timeline.opened(0);
    opening.result.complete(
      TestTimelineConnection(initial: baseline(1, items: [])),
    );
    await native.conversations.repository
        .existingSession('thread-main')!
        .timeline
        .ready;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        conversationRepositoryProvider.overrideWithValue(
          native.conversations.repository,
        ),
      ],
    );
    addTearDown(container.dispose);
    return _StatusFixture(native, composer, container);
  }

  Future<void> metrics(ThreadMetricsValue value) async {
    final feed = native.conversations.facets.metrics.single.feed;
    await feed.listened.future;
    final revision = ++_metricsRevision;
    feed.emit(
      ThreadMetricsFrame.data(
        deliverySequence: revision,
        event: revision == 1
            ? ThreadMetricsEvent.baseline(
                identity: draftFeed(
                  feed.feedId,
                  ThreadFacet.metrics,
                  ThreadObservationMode.live,
                ),
                stamp: draftFacet(ThreadFacet.metrics, revision),
                value: value,
              )
            : ThreadMetricsEvent.replace(
                stamp: draftFacet(ThreadFacet.metrics, revision),
                value: value,
              ),
      ),
    );
    await feed.acknowledged(revision);
  }

  Future<void> context(ThreadContextValue value) async {
    final feed = native.conversations.facets.context.single.feed;
    await feed.listened.future;
    final revision = ++_contextRevision;
    feed.emit(
      ThreadContextFrame.data(
        deliverySequence: revision,
        event: revision == 1
            ? ThreadContextEvent.baseline(
                identity: draftFeed(
                  feed.feedId,
                  ThreadFacet.context,
                  ThreadObservationMode.live,
                ),
                stamp: draftFacet(ThreadFacet.context, revision),
                value: value,
              )
            : ThreadContextEvent.replace(
                stamp: draftFacet(ThreadFacet.context, revision),
                value: value,
              ),
      ),
    );
    await feed.acknowledged(revision);
  }

  Future<void> configuration(ThreadConfigurationValue value) async {
    final feed = native.conversations.facets.configuration.single.feed;
    final revision = ++_configurationRevision;
    feed.emit(
      ThreadConfigurationFrame.data(
        deliverySequence: revision,
        event: ThreadConfigurationEvent.replace(
          stamp: draftFacet(ThreadFacet.configuration, revision),
          value: value,
        ),
      ),
    );
    await feed.acknowledged(revision);
  }
}
