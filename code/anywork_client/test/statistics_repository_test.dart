import 'dart:async';

import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/statistics_ports.dart';
import 'package:test/test.dart';

import 'support/scripted_feed.dart';
import 'support/statistics_test_port.dart';

/// Hang guard only: every wait is released by a real native reply or an
/// observable repository publication, never by a sleep.
const _guard = Duration(seconds: 5);

const _origin = ProductReadOrigin(
  ownerEpoch: 'statistics-native',
  incarnation: 1,
);
const _otherOrigin = ProductReadOrigin(
  ownerEpoch: 'statistics-native',
  incarnation: 2,
);
const _summaryRef = PerformanceSummariesReadRef(entry: 1, revision: 1);
const _summaryRef2 = PerformanceSummariesReadRef(entry: 5, revision: 1);
const _summaryRef3 = PerformanceSummariesReadRef(entry: 7, revision: 1);
const _historyRef = PerformanceHistoryReadRef(entry: 2, revision: 1);
const _historyRef2 = PerformanceHistoryReadRef(entry: 6, revision: 1);

Matcher _code(StudioFailureCode code) =>
    isA<StudioFailure>().having((failure) => failure.code, 'code', code);

Future<void> _expectClean(
  StatisticsRepository repository,
  ResourceBudget budget,
) async {
  final report = await repository.close(deadline: DateTime.now().add(_guard));
  expect(report.complete, isTrue);
  expect(budget.usage, isEmpty);
}

Future<StatisticsState> _waitFor(
  StatisticsRepository repository,
  bool Function(StatisticsState state) predicate,
) => repository.state.waitFor(predicate).timeout(_guard);

/// Complete native read ledger of both lanes: scope opens, headers, index
/// pages, entity reads, effort pages and text chunks, plus every identity scope.
/// A status-only publication must leave it byte-identical.
List<String> _readLedger(ScriptedStatisticsPort port) => [
  for (final read in port.summariesReads)
    'summaries#${read.ordinal} header=${read.headerCalls}'
        ' entries=${read.entriesOffsets}'
        ' entities=${[for (final ref in read.entityReads) ref.entry]}'
        ' efforts=${[for (final page in read.effortPages) '${page.listId}@${page.offset}']}'
        ' text=${[for (final text in read.textReads) '${text.fieldId}@${text.offset}']}',
  for (final read in port.historyReads)
    'history#${read.ordinal} header=${read.headerCalls}'
        ' entries=${read.entriesOffsets}'
        ' entities=${[for (final ref in read.entityReads) ref.entry]}'
        ' text=${[for (final text in read.textReads) '${text.fieldId}@${text.offset}']}',
  for (final read in port.summaryIdentityReads)
    'summaryIdentity#${read.ordinal} header=${read.headerCalls}'
        ' text=${[for (final text in read.textReads) '${text.fieldId}@${text.offset}']}',
  for (final read in port.effortIdentityReads)
    'effortIdentity#${read.ordinal} header=${read.headerCalls}'
        ' text=${[for (final text in read.textReads) '${text.fieldId}@${text.offset}']}',
  for (final read in port.sampleIdentityReads)
    'sampleIdentity#${read.ordinal} header=${read.headerCalls}'
        ' text=${[for (final text in read.textReads) '${text.fieldId}@${text.offset}']}',
];

PerformanceCounters _counters() => const PerformanceCounters(
  sampleCount: 1,
  completionTokens: 100,
  totalTtftMillis: 300,
  ttftSampleCount: 1,
  totalResponseMillis: 1300,
  tokensPerSecond: 100.0,
  averageTtftMillis: 300.0,
  averageResponseMillis: 1300.0,
);

/// Complete summaries material of one read reference. `missingEntries` breaks
/// only the index continuity so the protocol path can be exercised.
SummariesMaterialScript _summaries({
  required int total,
  int collectionRevision = 1,
  int effortsForFirst = 0,
  int missingEntries = 0,
  String account = 'account',
  int identityRevision = 1,
  StatisticsTestGate? entriesGate,
  StatisticsTestText? deferredDisplay,
}) => SummariesMaterialScript(
  collection: ProductCollectionRef(
    entry: 3,
    revision: collectionRevision,
    total: total,
  ),
  entries: [
    for (var index = 0; index < total - missingEntries; index++)
      ProductEntityRef(entry: 100 + index, revision: 1),
  ],
  entities: {
    for (var index = 0; index < total; index++)
      100 + index: PerformanceSummaryRead(
        identity: PerformanceSummaryIdentityRef(
          entry: 1000 + index,
          revision: identityRevision,
        ),
        counters: _counters(),
        effortBreakdowns: TypedListRef(
          listId: 2000 + index,
          total: index == 0 ? effortsForFirst : 0,
        ),
      ),
  },
  efforts: {
    2000: [
      for (var index = 0; index < effortsForFirst; index++)
        PerformanceEffortRead(
          identity: PerformanceEffortIdentityRef(
            entry: 5000 + index,
            revision: 1,
          ),
          counters: _counters(),
        ),
    ],
  },
  identities: {
    for (var index = 0; index < total; index++)
      1000 + index: PerformanceSummaryIdentityRead(
        accountId: ReadText.inline(text: '$account-$index'),
        accountDisplayName: index == 0 && deferredDisplay != null
            ? deferredDisplay.read
            : ReadText.inline(text: 'Account $index'),
        modelId: ReadText.inline(text: 'model-$index'),
      ),
  },
  effortIdentities: {
    for (var index = 0; index < effortsForFirst; index++)
      5000 + index: PerformanceEffortIdentityRead(
        effort: index == 0 ? null : ReadText.inline(text: 'effort-$index'),
      ),
  },
  deferredTexts: [if (deferredDisplay != null) deferredDisplay],
  entriesGate: entriesGate,
);

/// Complete history material of one read reference.
HistoryMaterialScript _history({
  required int total,
  int collectionRevision = 1,
  int missingEntries = 0,
  String account = 'account',
  int identityRevision = 1,
  StatisticsTestGate? entriesGate,
  StatisticsTestText? deferredDisplay,
}) => HistoryMaterialScript(
  collection: ProductCollectionRef(
    entry: 4,
    revision: collectionRevision,
    total: total,
  ),
  entries: [
    for (var index = 0; index < total - missingEntries; index++)
      ProductEntityRef(entry: 300 + index, revision: 1),
  ],
  entities: {
    for (var index = 0; index < total; index++)
      300 + index: PerformanceSampleRead(
        identity: PerformanceSampleIdentityRef(
          entry: 7000 + index,
          revision: identityRevision,
        ),
        counters: PerformanceSampleCounters(
          completedAt: 1769904000 - index * 60,
          completionTokens: 10 + index,
          ttftMillis: 100,
          decodeMillis: 200,
          totalResponseMillis: 300,
          tokensPerSecond: 50.0,
        ),
      ),
  },
  identities: {
    for (var index = 0; index < total; index++)
      7000 + index: PerformanceSampleIdentityRead(
        accountId: ReadText.inline(text: account),
        accountDisplayName: index == 0 && deferredDisplay != null
            ? deferredDisplay.read
            : ReadText.inline(text: 'Alpha'),
        modelId: ReadText.inline(text: 'model-$index'),
        sentModel: ReadText.inline(text: 'model-$index'),
        reportedModel: null,
        modelMatchState: ModelMatchState.matched,
        effort: ReadText.inline(text: index == 0 ? 'high' : 'low'),
      ),
  },
  deferredTexts: [if (deferredDisplay != null) deferredDisplay],
  entriesGate: entriesGate,
);

FeedCloseOutcome _unconfirmedClose(String correlationId) =>
    FeedCloseOutcome.unresolved(
      issues: [
        FeedCloseIssue(
          diagnostic: StudioShutdownIssue(
            stage: 'test',
            code: 'busy',
            message: 'The scripted native close is not confirmed yet.',
            retryable: true,
            correlationId: correlationId,
          ),
          recovery: CleanupRecovery.retryClose,
        ),
      ],
    );

Future<void> _listen(
  ScriptedFeed<PerformanceSummariesFrame> summaries,
  ScriptedFeed<PerformanceHistoryFrame> history,
) async {
  await summaries.listened.future.timeout(_guard);
  await history.listened.future.timeout(_guard);
}

void main() {
  test(
    'a hidden page opens neither feed and has no synchronisation duty',
    () async {
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
      );
      final budget = ResourceBudget();
      final repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      expect(repository.state.value.snapshot, isNull);
      expect(repository.state.value.sync.phase, ResourceSyncPhase.idle);
      await expectLater(
        repository.synchronize(),
        throwsA(_code(StudioFailureCode.invalidArgument)),
      );
      await expectLater(
        repository.retrySync(),
        throwsA(_code(StudioFailureCode.invalidArgument)),
      );
      expect(port.summariesOpenCalls, 0);
      expect(port.historyOpenCalls, 0);

      repository.seal();
      expect(
        () => repository.acquireVisibleDemand(),
        throwsA(_code(StudioFailureCode.cancelled)),
      );
    },
  );

  test('both complete sides are materialised across every page before one snapshot is published', () async {
    final display = StatisticsTestText(9, 'Account 0 display', chunkBytes: 6);
    final summaries = _summaries(
      total: 129,
      effortsForFirst: 129,
      deferredDisplay: display,
    );
    final history = _history(total: 129);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
      identityTexts: [display],
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);

    final snapshot = repository.state.value.snapshot;
    expect(repository.state.value.sync.phase, ResourceSyncPhase.ready);
    expect(snapshot, isNotNull);
    expect(snapshot!.revision, 1);
    expect(snapshot.summaries, hasLength(129));
    expect(snapshot.summaries.first.effortBreakdowns, hasLength(129));
    expect(
      snapshot.summaries.first.effortBreakdowns.first.identity.effort,
      isNull,
    );
    expect(
      snapshot.summaries.first.effortBreakdowns[1].identity.effort,
      'effort-1',
    );
    expect(snapshot.summaries.first.identity.accountDisplayName, display.text);
    expect(snapshot.history, hasLength(129));

    final summaryRead = port.summariesReads.single;
    expect(summaryRead.headerCalls, 1);
    expect(summaryRead.entriesOffsets, [0, 32, 64, 96, 128]);
    expect(
      summaryRead.effortPages
          .where((page) => page.listId == 2000)
          .map((page) => page.offset),
      [0, 32, 64, 96, 128],
    );
    expect(
      [
        for (final identity in port.summaryIdentityReads)
          for (final text in identity.textReads)
            if (text.fieldId == display.fieldId) text.offset,
      ],
      [0, 6, 12],
      reason: 'The pinned identity text is read in its own scope, in order',
    );
    final historyRead = port.historyReads.single;
    expect(historyRead.headerCalls, 1);
    expect(historyRead.entriesOffsets, [0, 32, 64, 96, 128]);
    expect(port.summaryIdentityReads, hasLength(129));
    expect(port.effortIdentityReads, hasLength(129));
    expect(port.sampleIdentityReads, hasLength(129));
    expect(
      port.summaryIdentityReads.every((read) => read.headerCalls == 1),
      isTrue,
    );

    lease.release();
  });

  test('one side acknowledges its own complete material without waiting for the other', () async {
    final gate = StatisticsTestGate();
    final summaries = _summaries(total: 1);
    final history = _history(total: 2, entriesGate: gate);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );

    await summaryFeed.acknowledged(1).timeout(_guard);
    expect(
      historyFeed.acknowledgements,
      isEmpty,
      reason: 'The summary side must not hold the history delivery window',
    );
    expect(repository.state.value.snapshot, isNull);
    expect(repository.state.value.sync.phase, ResourceSyncPhase.connecting);

    gate.release.complete();
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    expect(repository.state.value.snapshot!.history, hasLength(2));

    lease.release();
  });

  test('a business revision gap keeps the last snapshot and disagreeing metadata fails the attempt', () async {
    final firstSummaries = _summaries(total: 1, effortsForFirst: 1);
    final firstHistory = _history(total: 1);
    final nextSummaries = _summaries(total: 2, collectionRevision: 2);
    final nextHistory = _history(total: 1, collectionRevision: 2);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: firstSummaries},
      historyScripts: {_historyRef: firstHistory},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: firstSummaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: firstHistory.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    final ready = repository.state.value.snapshot;
    expect(ready, isNotNull);

    port.summaryScripts[_summaryRef2] = nextSummaries;
    summaryFeed.emit(
      summariesChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _summaryRef2,
        collection: nextSummaries.collection,
        baseCollectionRevision: 1,
      ),
    );
    await summaryFeed.acknowledged(2).timeout(_guard);
    expect(
      repository.state.value.snapshot,
      ready,
      reason: 'One side alone never replaces the paired snapshot',
    );
    expect(repository.state.value.sync.phase, ResourceSyncPhase.ready);

    historyFeed.emit(
      historyChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _historyRef,
        collection: nextHistory.collection,
        baseCollectionRevision: 1,
        updatedAt: 1769904001,
      ),
    );
    final failed = await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.failed,
    );
    expect(failed.sync.error!.code, StudioFailureCode.protocol);
    expect(failed.snapshot, ready);
    expect(historyFeed.acknowledgements, [1]);
    expect(summaryFeed.acknowledgements, [1, 2]);

    lease.release();
  });

  test('a status-only republication advances the header without reopening or re-reading material', () async {
    final summaryText = StatisticsTestText(
      9,
      'Account 0 display',
      chunkBytes: 6,
    );
    final sampleText = StatisticsTestText(
      19,
      'Sample zero display',
      chunkBytes: 5,
    );
    final summaries = _summaries(
      total: 1,
      effortsForFirst: 2,
      deferredDisplay: summaryText,
    );
    final history = _history(total: 2, deferredDisplay: sampleText);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
      identityTexts: [summaryText, sampleText],
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    final first = repository.state.value.snapshot!;
    // The ledger must already prove real paged effort, identity and text reads on
    // both lanes before its invariance means anything.
    final readsBefore = _readLedger(port);
    expect(
      port.summariesReads.single.effortPages,
      isNotEmpty,
      reason: 'The scenario must materialise a real effort list',
    );
    expect(port.effortIdentityReads, hasLength(2));
    expect(port.summaryIdentityReads.single.textReads, isNotEmpty);
    expect(port.sampleIdentityReads.first.textReads, isNotEmpty);

    summaryFeed.emit(
      summariesChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _summaryRef,
        collection: ProductCollectionRef(
          entry: 3,
          revision: 2,
          total: summaries.collection.total,
        ),
        baseCollectionRevision: 1,
        statisticsPending: true,
      ),
    );
    await summaryFeed.acknowledged(2).timeout(_guard);
    historyFeed.emit(
      historyChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _historyRef,
        collection: ProductCollectionRef(
          entry: 4,
          revision: 2,
          total: history.collection.total,
        ),
        baseCollectionRevision: 1,
        statisticsPending: true,
      ),
    );
    await historyFeed.acknowledged(2).timeout(_guard);
    await _waitFor(repository, (state) => state.snapshot?.revision == 2);

    final state = repository.state.value;
    expect(state.sync.phase, ResourceSyncPhase.ready);
    expect(state.snapshot!.statisticsPending, isTrue);
    expect(state.snapshot!.summaries, first.summaries);
    expect(state.snapshot!.history, first.history);
    // Header, index page, entity, effort page, identity and text-chunk records of
    // both lanes stay exactly as they were; no scope, page or chunk is re-read.
    expect(_readLedger(port), readsBefore);
    expect(port.summariesReads, hasLength(1));
    expect(port.historyReads, hasLength(1));
    expect(port.summaryIdentityReads, hasLength(1));
    expect(port.sampleIdentityReads, hasLength(2));
    expect(port.summariesOpenCalls, 1);
    expect(port.historyOpenCalls, 1);
    expect(port.summariesReads.single.headerCalls, 1);

    lease.release();
  });

  test(
    'a new material on one side keeps the other side reference and material',
    () async {
      final summaries = _summaries(total: 1, effortsForFirst: 1);
      final history = _history(total: 1);
      final nextSummaries = _summaries(total: 2, collectionRevision: 2);
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
        summaryScripts: {_summaryRef: summaries},
        historyScripts: {_historyRef: history},
      );
      final budget = ResourceBudget();
      final repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      final lease = repository.acquireVisibleDemand();
      final summaryFeed = await port.summariesAt(1).timeout(_guard);
      final historyFeed = await port.historyAt(1).timeout(_guard);
      await _listen(summaryFeed, historyFeed);
      summaryFeed.emit(
        summariesBaseline(
          feedId: 'summaries',
          origin: _origin,
          revision: 1,
          reference: _summaryRef,
          collection: summaries.collection,
        ),
      );
      historyFeed.emit(
        historyBaseline(
          feedId: 'history',
          origin: _origin,
          revision: 1,
          reference: _historyRef,
          collection: history.collection,
        ),
      );
      await summaryFeed.acknowledged(1).timeout(_guard);
      await historyFeed.acknowledged(1).timeout(_guard);
      await repository.synchronize().timeout(_guard);
      final historyRead = port.historyReads.single;

      port.summaryScripts[_summaryRef2] = nextSummaries;
      summaryFeed.emit(
        summariesChange(
          origin: _origin,
          deliverySequence: 2,
          revision: 2,
          baseRevision: 1,
          reference: _summaryRef2,
          collection: nextSummaries.collection,
          baseCollectionRevision: 1,
        ),
      );
      await summaryFeed.acknowledged(2).timeout(_guard);
      historyFeed.emit(
        historyChange(
          origin: _origin,
          deliverySequence: 2,
          revision: 2,
          baseRevision: 1,
          reference: _historyRef,
          collection: ProductCollectionRef(
            entry: 4,
            revision: 2,
            total: history.collection.total,
          ),
          baseCollectionRevision: 1,
        ),
      );
      await historyFeed.acknowledged(2).timeout(_guard);
      await _waitFor(repository, (state) => state.snapshot?.revision == 2);

      final snapshot = repository.state.value.snapshot!;
      expect(snapshot.summaries, hasLength(2));
      expect(snapshot.history, hasLength(1));
      expect(snapshot.historyReference, _historyRef);
      expect(port.summariesReads, hasLength(2));
      expect(port.historyReads, hasLength(1));
      expect(historyRead.headerCalls, 1);
      expect(historyRead.entityReads, hasLength(1));

      lease.release();
    },
  );

  test('a retired attempt joins its feeds before the next demand and reuse stays inside one origin', () async {
    final summaries = _summaries(total: 1, effortsForFirst: 1);
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final firstLease = repository.acquireVisibleDemand();
    final firstSummaryFeed = await port.summariesAt(1).timeout(_guard);
    final firstHistoryFeed = await port.historyAt(1).timeout(_guard);
    await _listen(firstSummaryFeed, firstHistoryFeed);
    firstSummaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    firstHistoryFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await firstSummaryFeed.acknowledged(1).timeout(_guard);
    await firstHistoryFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    final first = repository.state.value.snapshot!;

    firstLease.release();
    await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.idle,
    );

    final secondLease = repository.acquireVisibleDemand();
    final secondSummaryFeed = await port.summariesAt(2).timeout(_guard);
    final secondHistoryFeed = await port.historyAt(2).timeout(_guard);
    expect(firstSummaryFeed.closeStarted.isCompleted, isTrue);
    expect(firstHistoryFeed.closeStarted.isCompleted, isTrue);
    expect(
      port.summariesReads,
      hasLength(1),
      reason: 'Unchanged material keeps its complete values and read scope',
    );
    expect(port.historyReads, hasLength(1));

    await _listen(secondSummaryFeed, secondHistoryFeed);
    secondSummaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    secondHistoryFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await secondSummaryFeed.acknowledged(1).timeout(_guard);
    await secondHistoryFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    expect(repository.state.value.snapshot, first);
    expect(port.summariesReads, hasLength(1));
    expect(port.summaryIdentityReads, hasLength(1));

    secondLease.release();
    await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.idle,
    );

    final thirdLease = repository.acquireVisibleDemand();
    final thirdSummaryFeed = await port.summariesAt(3).timeout(_guard);
    final thirdHistoryFeed = await port.historyAt(3).timeout(_guard);
    await _listen(thirdSummaryFeed, thirdHistoryFeed);
    thirdSummaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _otherOrigin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    thirdHistoryFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _otherOrigin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await thirdSummaryFeed.acknowledged(1).timeout(_guard);
    await thirdHistoryFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    expect(repository.state.value.snapshot!.origin, _otherOrigin);
    expect(
      port.summariesReads,
      hasLength(2),
      reason: 'Another authority origin never reuses material values',
    );
    expect(port.historyReads, hasLength(2));
    expect(port.summaryReadOpens.map((open) => open.origin), [
      _origin,
      _otherOrigin,
    ]);

    thirdLease.release();
  });

  test('a page from a retired generation never publishes and reopening waits for its real join', () async {
    final pageGate = StatisticsTestGate();
    final firstSummaries = _summaries(total: 1);
    final firstHistory = _history(total: 1, entriesGate: pageGate);
    // The reopened material pins its own identity revision: the same origin and
    // the same complete identity reference may never carry two frozen values, so
    // a material that labels rows differently declares a newer revision instead
    // of silently replacing the retired attempt's declaration.
    final reopenedSummaries = _summaries(
      total: 1,
      account: 'reopened',
      identityRevision: 2,
    );
    final reopenedHistory = _history(
      total: 1,
      account: 'reopened',
      identityRevision: 2,
    );
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: firstSummaries},
      historyScripts: {_historyRef: firstHistory},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final firstLease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: firstSummaries.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: firstHistory.collection,
      ),
    );
    await pageGate.entered.future.timeout(_guard);
    expect(repository.state.value.snapshot, isNull);

    firstLease.release();
    expect(repository.state.value.sync.phase, ResourceSyncPhase.idle);
    final reopenedLease = repository.acquireVisibleDemand();
    expect(
      port.summariesOpenCalls,
      1,
      reason: 'The replacement opens only after the retired page joined',
    );
    expect(port.historyOpenCalls, 1);

    pageGate.release.complete();
    final reopenedSummaryFeed = await port.summariesAt(2).timeout(_guard);
    final reopenedHistoryFeed = await port.historyAt(2).timeout(_guard);
    expect(
      historyFeed.acknowledgements,
      isEmpty,
      reason: 'A late material of a retired attempt is never confirmed',
    );
    expect(port.historyReads.single.closed, isTrue);

    port.summaryScripts[_summaryRef2] = reopenedSummaries;
    port.historyScripts[_historyRef2] = reopenedHistory;
    await _listen(reopenedSummaryFeed, reopenedHistoryFeed);
    reopenedSummaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef2,
        collection: reopenedSummaries.collection,
      ),
    );
    reopenedHistoryFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef2,
        collection: reopenedHistory.collection,
      ),
    );
    await reopenedSummaryFeed.acknowledged(1).timeout(_guard);
    await reopenedHistoryFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);

    final snapshot = repository.state.value.snapshot!;
    expect(snapshot.summaries.single.identity.accountId, 'reopened-0');
    expect(snapshot.history.single.identity.accountId, 'reopened');

    reopenedLease.release();
  });

  test('a failed material stays visibly failed and only an explicit retry opens fresh resources', () async {
    final brokenSummaries = _summaries(total: 2, missingEntries: 1);
    final firstHistory = _history(total: 1);
    final recoveredSummaries = _summaries(total: 1, collectionRevision: 2);
    final recoveredHistory = _history(total: 1, collectionRevision: 2);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: brokenSummaries},
      historyScripts: {_historyRef: firstHistory},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    StudioFailure? failure;
    StatisticsSnapshot? snapshotAtFailure;
    Object? retryError;
    var retried = false;
    final observation = repository.state.watch((state) {
      if (state.sync.phase != ResourceSyncPhase.failed || retried) return;
      retried = true;
      failure = state.sync.error;
      snapshotAtFailure = state.snapshot;
      unawaited(
        repository.retrySync().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            retryError = error;
          },
        ),
      );
    });
    addTearDown(observation.cancel);

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: brokenSummaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: firstHistory.collection,
      ),
    );

    final reopenedSummaryFeed = await port.summariesAt(2).timeout(_guard);
    final reopenedHistoryFeed = await port.historyAt(2).timeout(_guard);
    expect(retried, isTrue);
    expect(retryError, isNull);
    expect(failure!.code, StudioFailureCode.protocol);
    expect(
      snapshotAtFailure,
      isNull,
      reason: 'A failed first publication is never a known empty collection',
    );
    expect(summaryFeed.acknowledgements, isEmpty);
    expect(port.summariesReads.first.closed, isTrue);

    port.summaryScripts[_summaryRef2] = recoveredSummaries;
    port.historyScripts[_historyRef2] = recoveredHistory;
    await _listen(reopenedSummaryFeed, reopenedHistoryFeed);
    reopenedSummaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef2,
        collection: recoveredSummaries.collection,
      ),
    );
    reopenedHistoryFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef2,
        collection: recoveredHistory.collection,
      ),
    );
    await reopenedSummaryFeed.acknowledged(1).timeout(_guard);
    await reopenedHistoryFeed.acknowledged(1).timeout(_guard);
    await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.ready,
    );
    expect(repository.state.value.snapshot!.summaries, hasLength(1));
    expect(port.summariesOpenCalls, 2);

    observation.cancel();
    lease.release();
  });

  test('an unconfirmed close keeps its permits and retry cleanup reuses the same handles', () async {
    final summaries = _summaries(total: 1);
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);

    summaryFeed.outcome = _unconfirmedClose('statistics-summaries');
    historyFeed.outcome = _unconfirmedClose('statistics-history');
    final unresolved = await repository
        .close(deadline: DateTime.now().add(_guard))
        .timeout(_guard);
    expect(unresolved.complete, isFalse);
    expect(unresolved.unresolved, hasLength(2));
    expect(
      unresolved.unresolved.every(
        (resource) => resource.issues.any(
          (issue) => issue.recovery == CleanupRecovery.retryClose,
        ),
      ),
      isTrue,
    );
    expect(budget.used(ResourceKind.readModel), 2);
    expect(
      budget.usage.every((usage) => usage.phase == ResourcePhase.unresolved),
      isTrue,
    );
    expect(repository.state.value.sync.phase, ResourceSyncPhase.ready);
    expect(summaryFeed.closeCalls, 1);
    expect(historyFeed.closeCalls, 1);
    expect(port.summariesOpenCalls, 1);

    summaryFeed.outcome = const FeedCloseOutcome.clean();
    historyFeed.outcome = const FeedCloseOutcome.clean();
    final retried = await repository
        .retryCleanup(deadline: DateTime.now().add(_guard))
        .timeout(_guard);
    expect(retried.complete, isTrue);
    expect(summaryFeed.retryCloseCalls, 1);
    expect(historyFeed.retryCloseCalls, 1);
    expect(port.summariesOpenCalls, 1);
    expect(budget.usage, isEmpty);
    expect(repository.state.value.sync.phase, ResourceSyncPhase.closed);
    expect(repository.state.value.snapshot, isNotNull);

    lease.release();
  });

  test(
    'close joins an in-flight page and never publishes its late material',
    () async {
      final summaries = _summaries(total: 1);
      final history = _history(total: 1);
      final pageGate = StatisticsTestGate();
      final nextSummaries = _summaries(total: 2, collectionRevision: 2);
      final nextHistory = _history(
        total: 1,
        collectionRevision: 2,
        entriesGate: pageGate,
      );
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
        summaryScripts: {_summaryRef: summaries},
        historyScripts: {_historyRef: history},
      );
      final budget = ResourceBudget();
      final repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      final lease = repository.acquireVisibleDemand();
      final summaryFeed = await port.summariesAt(1).timeout(_guard);
      final historyFeed = await port.historyAt(1).timeout(_guard);
      await _listen(summaryFeed, historyFeed);
      summaryFeed.emit(
        summariesBaseline(
          feedId: 'summaries',
          origin: _origin,
          revision: 1,
          reference: _summaryRef,
          collection: summaries.collection,
        ),
      );
      historyFeed.emit(
        historyBaseline(
          feedId: 'history',
          origin: _origin,
          revision: 1,
          reference: _historyRef,
          collection: history.collection,
        ),
      );
      await summaryFeed.acknowledged(1).timeout(_guard);
      await historyFeed.acknowledged(1).timeout(_guard);
      await repository.synchronize().timeout(_guard);

      port.summaryScripts[_summaryRef2] = nextSummaries;
      port.historyScripts[_historyRef2] = nextHistory;
      summaryFeed.emit(
        summariesChange(
          origin: _origin,
          deliverySequence: 2,
          revision: 2,
          baseRevision: 1,
          reference: _summaryRef2,
          collection: nextSummaries.collection,
          baseCollectionRevision: 1,
        ),
      );
      await summaryFeed.acknowledged(2).timeout(_guard);
      historyFeed.emit(
        historyChange(
          origin: _origin,
          deliverySequence: 2,
          revision: 2,
          baseRevision: 1,
          reference: _historyRef2,
          collection: nextHistory.collection,
          baseCollectionRevision: 1,
        ),
      );
      await pageGate.entered.future.timeout(_guard);
      final paged = port.historyReads.last;

      var closeFinished = false;
      final closing = repository.close(deadline: DateTime.now().add(_guard));
      unawaited(
        closing.then<void>(
          (_) {
            closeFinished = true;
          },
          onError: (Object error, StackTrace stack) {
            closeFinished = true;
          },
        ),
      );
      await paged.closeStarted.future.timeout(_guard);
      expect(
        closeFinished,
        isFalse,
        reason: 'Close must join the admitted page before releasing its permit',
      );
      expect(budget.used(ResourceKind.readModel), greaterThan(0));

      pageGate.release.complete();
      final report = await closing.timeout(_guard);
      expect(report.complete, isTrue);
      expect(budget.usage, isEmpty);
      expect(repository.state.value.snapshot!.revision, 1);
      expect(repository.state.value.sync.phase, ResourceSyncPhase.closed);

      lease.release();
    },
  );

  test('close joins an in-flight acknowledgement and keeps the original prefix', () async {
    final summaries = _summaries(total: 1, effortsForFirst: 1);
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    // Both acknowledgements are gated before any delivery: `ackThrough`
    // suspends on its own native receipt after validating its prefix, so the
    // frame's material is already complete while neither side has confirmed
    // the delivery itself.
    final summariesAck = Completer<void>();
    final historyAck = Completer<void>();
    summaryFeed.ackReceipt = summariesAck;
    historyFeed.ackReceipt = historyAck;
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    // Every page, identity and text read of both lanes is joined and one
    // snapshot is published, while both acknowledgements still sit inside the
    // native call and are therefore unfinished.
    await repository.synchronize().timeout(_guard);
    await summaryFeed.acknowledgementEntered.future.timeout(_guard);
    await historyFeed.acknowledgementEntered.future.timeout(_guard);
    final published = repository.state.value.snapshot!;
    expect(published.revision, 1);
    expect(published.summaries.single.effortBreakdowns, hasLength(1));
    expect(published.history.single.identity.accountId, 'account');
    expect(port.summariesReads.single.entriesOffsets, isNotEmpty);
    expect(port.summariesReads.single.entityReads, isNotEmpty);
    expect(port.historyReads.single.entityReads, isNotEmpty);
    expect(
      summaryFeed.acknowledgements,
      isEmpty,
      reason: 'The acknowledgement entered the native call but has not ended',
    );
    expect(historyFeed.acknowledgements, isEmpty);

    var closeFinished = false;
    final closing = repository.close(deadline: DateTime.now().add(_guard));
    unawaited(
      closing.then<void>(
        (_) {
          closeFinished = true;
        },
        onError: (Object error, StackTrace stack) {
          closeFinished = true;
        },
      ),
    );
    await summaryFeed.closeStarted.future.timeout(_guard);
    await historyFeed.closeStarted.future.timeout(_guard);
    expect(
      closeFinished,
      isFalse,
      reason:
          'Close must join the admitted acknowledgement before releasing its '
          'permit',
    );
    // The exact owners still holding a read permit while the acknowledgement is
    // in flight: both feeds of attempt 1, generation 1
    // (`statistics:1:<lane>:1`, `statistics_attempt.dart` `_openSummaries`) and
    // both pinned material read scopes (`statistics:1:<lane>-read`,
    // `_summariesPin`/`_historyPin`), all retired by the close still joining
    // them. An extra or missing owner is a real leak, so this is a multiset
    // comparison, not a lower bound.
    expect(
      [
        for (final usage in budget.usage)
          if (usage.kind == ResourceKind.readModel)
            '${usage.owner}:${usage.phase.name}',
      ]..sort(),
      [
        'statistics:1:history-read:retiring',
        'statistics:1:history:1:retiring',
        'statistics:1:summaries-read:retiring',
        'statistics:1:summaries:1:retiring',
      ]..sort(),
      reason: 'The unconfirmed acknowledgement keeps exactly its own owners',
    );
    expect(summaryFeed.acknowledgements, isEmpty);
    expect(historyFeed.acknowledgements, isEmpty);

    summariesAck.complete();
    historyAck.complete();
    final report = await closing.timeout(_guard);
    expect(report.complete, isTrue);
    // The original prefix is confirmed exactly once after the real join. A
    // lane that had never entered its acknowledgement would have exited the
    // delivery loop on close and never recorded one here.
    expect(summaryFeed.acknowledgements, [1]);
    expect(historyFeed.acknowledgements, [1]);
    expect(budget.usage, isEmpty);
    expect(repository.state.value.sync.phase, ResourceSyncPhase.closed);
    expect(repository.state.value.snapshot, published);

    lease.release();
  });

  test('visible leases share one attempt while separate repositories keep their own feeds', () async {
    final budget = ResourceBudget();
    final otherBudget = ResourceBudget();
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: _summaries(total: 1)},
      historyScripts: {_historyRef: _history(total: 1)},
    );
    final otherPort = ScriptedStatisticsPort(
      origin: _otherOrigin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: _summaries(total: 1, account: 'other')},
      historyScripts: {_historyRef: _history(total: 1, account: 'other')},
    );
    final repository = createStatisticsRepository(port: port, budget: budget);
    final other = createStatisticsRepository(
      port: otherPort,
      budget: otherBudget,
    );
    addTearDown(() => _expectClean(repository, budget));
    addTearDown(() => _expectClean(other, otherBudget));

    final firstLease = repository.acquireVisibleDemand();
    final secondLease = repository.acquireVisibleDemand();
    final otherLease = other.acquireVisibleDemand();
    // Acquiring a lease starts the attempt without opening a native feed inside
    // the acquisition itself: the opens are admitted asynchronously, and a second
    // lease never starts another attempt.
    expect(port.summariesOpenCalls, 0);
    expect(port.historyOpenCalls, 0);
    expect(otherPort.summariesOpenCalls, 0);

    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    final otherSummaryFeed = await otherPort.summariesAt(1).timeout(_guard);
    final otherHistoryFeed = await otherPort.historyAt(1).timeout(_guard);
    // Two visible leases of one repository share a single attempt, and each
    // repository keeps its own feeds.
    expect(
      port.summariesOpenCalls,
      1,
      reason: 'Two visible leases of one repository share a single attempt',
    );
    expect(port.historyOpenCalls, 1);
    expect(otherPort.summariesOpenCalls, 1);
    expect(otherPort.historyOpenCalls, 1);
    await _listen(summaryFeed, historyFeed);
    await _listen(otherSummaryFeed, otherHistoryFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: ProductCollectionRef(entry: 3, revision: 1, total: 1),
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: ProductCollectionRef(entry: 4, revision: 1, total: 1),
      ),
    );
    otherSummaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _otherOrigin,
        revision: 1,
        reference: _summaryRef,
        collection: ProductCollectionRef(entry: 3, revision: 1, total: 1),
      ),
    );
    otherHistoryFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _otherOrigin,
        revision: 1,
        reference: _historyRef,
        collection: ProductCollectionRef(entry: 4, revision: 1, total: 1),
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await otherSummaryFeed.acknowledged(1).timeout(_guard);
    await otherHistoryFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    await other.synchronize().timeout(_guard);
    expect(
      port.summariesOpenCalls,
      1,
      reason: 'Two visible leases of one repository share a single attempt',
    );
    expect(port.historyOpenCalls, 1);
    expect(otherPort.summariesOpenCalls, 1);
    expect(otherPort.historyOpenCalls, 1);
    expect(repository.state.value.snapshot!.origin, _origin);
    expect(other.state.value.snapshot!.origin, _otherOrigin);

    firstLease.release();
    firstLease.release();
    expect(
      summaryFeed.requestCloseCalls,
      0,
      reason: 'A second release is not a second demand release',
    );
    expect(repository.state.value.sync.phase, ResourceSyncPhase.ready);

    secondLease.release();
    await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.idle,
    );
    expect(summaryFeed.requestCloseCalls, greaterThan(0));
    expect(other.state.value.sync.phase, ResourceSyncPhase.ready);
    expect(otherSummaryFeed.requestCloseCalls, 0);

    otherLease.release();
  });

  test(
    'close joins an admitted feed open before releasing its permit',
    () async {
      final openGate = StatisticsTestGate();
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
      );
      port.summaryOpenScripts.add(StatisticsOpenScript(gate: openGate));
      final budget = ResourceBudget();
      final repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      final lease = repository.acquireVisibleDemand();
      await openGate.entered.future.timeout(_guard);
      final historyFeed = await port.historyAt(1).timeout(_guard);
      var closeFinished = false;
      final closing = repository.close(deadline: DateTime.now().add(_guard));
      unawaited(
        closing.then<void>(
          (_) {
            closeFinished = true;
          },
          onError: (Object error, StackTrace stack) {
            closeFinished = true;
          },
        ),
      );
      // The other feed already reached its native close; the summary side is
      // still inside its admitted open, so the report cannot be complete.
      await historyFeed.closeStarted.future.timeout(_guard);
      expect(closeFinished, isFalse);
      expect(budget.used(ResourceKind.readModel), greaterThan(0));
      expect(port.summariesOpenCalls, 1);

      openGate.release.complete();
      final report = await closing.timeout(_guard);
      expect(report.complete, isTrue);
      expect(budget.usage, isEmpty);
      expect(
        port.summariesFeed.closeCalls,
        1,
        reason: 'The admitted open returned a handle that must still be closed',
      );
      expect(repository.state.value.snapshot, isNull);
      expect(repository.state.value.sync.phase, ResourceSyncPhase.closed);

      lease.release();
    },
  );

  test(
    'close reentered from the native open keeps and closes the returned handle',
    () async {
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
      );
      final budget = ResourceBudget();
      late StatisticsRepository repository;
      Future<CloseReport>? closing;
      Object? closeError;
      port.summaryOpenScripts.add(
        StatisticsOpenScript(
          onOpen: () {
            closing = repository.close(deadline: DateTime.now().add(_guard));
            unawaited(
              closing!.then<void>(
                (_) {},
                onError: (Object error, StackTrace stack) {
                  closeError = error;
                },
              ),
            );
          },
        ),
      );
      repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      final lease = repository.acquireVisibleDemand();
      await port.summariesAt(1).timeout(_guard);
      final report = await closing!.timeout(_guard);
      expect(closeError, isNull);
      expect(report.complete, isTrue);
      expect(port.summariesOpenCalls, 1);
      expect(port.summariesFeed.closeCalls, 1);
      expect(port.summariesFeed.closeStarted.isCompleted, isTrue);
      expect(budget.usage, isEmpty);
      expect(repository.state.value.snapshot, isNull);
      expect(repository.state.value.sync.phase, ResourceSyncPhase.closed);

      lease.release();
    },
  );

  test(
    'a timed-out close keeps its duty until the late open failure is joined',
    () async {
      final openGate = StatisticsTestGate();
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
      );
      port.summaryOpenScripts.add(
        StatisticsOpenScript(gate: openGate, fail: true),
      );
      final budget = ResourceBudget();
      final repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      final lease = repository.acquireVisibleDemand();
      await openGate.entered.future.timeout(_guard);
      final timedOut = await repository.close(deadline: DateTime.now());
      expect(timedOut.complete, isFalse);
      expect(timedOut.unresolved, isNotEmpty);
      expect(budget.used(ResourceKind.readModel), greaterThan(0));
      expect(port.summariesOpenCalls, 1);

      openGate.release.complete();
      final cleaned = await repository
          .retryCleanup(deadline: DateTime.now().add(_guard))
          .timeout(_guard);
      expect(cleaned.complete, isTrue);
      expect(cleaned.unresolved, isEmpty);
      expect(budget.usage, isEmpty);
      expect(port.summariesOpenCalls, 1);
      expect(repository.state.value.sync.phase, ResourceSyncPhase.closed);

      lease.release();
    },
  );

  test('a synchronous observer may close while connecting without losing registered work', () async {
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    Future<CloseReport>? closing;
    var closeFinished = false;
    final observation = repository.state.watch((state) {
      if (state.sync.phase != ResourceSyncPhase.connecting || closing != null) {
        return;
      }
      closing = repository.close(deadline: DateTime.now().add(_guard));
      unawaited(
        closing!.then<void>(
          (_) {
            closeFinished = true;
          },
          onError: (Object error, StackTrace stack) {
            closeFinished = true;
          },
        ),
      );
    });
    addTearDown(observation.cancel);

    final lease = repository.acquireVisibleDemand();
    final report = await closing!.timeout(_guard);
    expect(closeFinished, isTrue);
    expect(report.complete, isTrue);
    expect(budget.usage, isEmpty);
    expect(port.summariesOpenCalls, 1);
    expect(port.historyOpenCalls, 1);
    expect(port.summariesFeed.closeStarted.isCompleted, isTrue);
    expect(repository.state.value.snapshot, isNull);
    expect(repository.state.value.sync.phase, ResourceSyncPhase.closed);

    lease.release();
  });

  test('a synchronous observer may retry while connecting without a second attempt', () async {
    final summaries = _summaries(total: 1);
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    Future<void>? retrying;
    Object? retryError;
    var retryFinished = false;
    final observation = repository.state.watch((state) {
      if (state.sync.phase != ResourceSyncPhase.connecting ||
          retrying != null) {
        return;
      }
      retrying = repository.retrySync();
      unawaited(
        retrying!.then<void>(
          (_) {
            retryFinished = true;
          },
          onError: (Object error, StackTrace stack) {
            retryError = error;
            retryFinished = true;
          },
        ),
      );
    });
    addTearDown(observation.cancel);

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    await retrying!.timeout(_guard);

    expect(retryFinished, isTrue);
    expect(retryError, isNull);
    expect(port.summariesOpenCalls, 1);
    expect(port.historyOpenCalls, 1);
    expect(repository.state.value.snapshot, isNotNull);
    expect(repository.state.value.sync.phase, ResourceSyncPhase.ready);

    observation.cancel();
    lease.release();
  });

  test('an open that fails after the page hid still lets the latest demand start fresh', () async {
    final openGate = StatisticsTestGate();
    final summaries = _summaries(total: 1);
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
    );
    port.summaryOpenScripts.add(
      StatisticsOpenScript(gate: openGate, fail: true),
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final firstLease = repository.acquireVisibleDemand();
    await openGate.entered.future.timeout(_guard);
    firstLease.release();
    final reopenedLease = repository.acquireVisibleDemand();
    expect(port.summariesOpenCalls, 1);
    openGate.release.complete();

    final summaryFeed = await port.summariesAt(2).timeout(_guard);
    final historyFeed = await port.historyAt(2).timeout(_guard);
    expect(repository.state.value.snapshot, isNull);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);

    expect(repository.state.value.snapshot, isNotNull);
    expect(repository.state.value.snapshot!.revision, 1);
    expect(port.summariesOpenCalls, 2);

    reopenedLease.release();
  });

  test('an unresolved hide keeps the original feeds until an explicit retry retries them', () async {
    final summaries = _summaries(total: 1);
    final history = _history(total: 1);
    final nextSummaries = _summaries(total: 1, collectionRevision: 2);
    final nextHistory = _history(total: 1, collectionRevision: 2);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: summaries},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summariesFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summariesFeed, historyFeed);
    summariesFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: summaries.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summariesFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    final first = repository.state.value.snapshot!;

    // The native close of the summaries lane is not confirmed on hide.
    summariesFeed.outcome = _unconfirmedClose('statistics-summaries');
    lease.release();
    await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.idle,
    );

    final reopened = repository.acquireVisibleDemand();
    final failed = await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.failed,
    );
    expect(failed.snapshot, first);
    expect(failed.sync.error!.code, StudioFailureCode.busy);
    expect(
      port.summariesOpenCalls,
      1,
      reason: 'An unjoined owner is never covered by a replacement lane',
    );
    expect(port.historyOpenCalls, 1);
    expect(port.summariesFeed, same(summariesFeed));

    // A retry that still cannot confirm the original close keeps that owner.
    await expectLater(
      repository.retrySync().timeout(_guard),
      throwsA(_code(StudioFailureCode.busy)),
    );
    expect(
      summariesFeed.retryCloseCalls,
      1,
      reason: 'The retry must retry the original handle, not a new lane',
    );
    expect(port.summariesOpenCalls, 1);
    expect(repository.state.value.snapshot, first);
    expect(budget.used(ResourceKind.readModel), greaterThan(0));

    summariesFeed.outcome = const FeedCloseOutcome.clean();
    final retried = repository.retrySync();
    final reopenedSummaries = await port.summariesAt(2).timeout(_guard);
    final reopenedHistory = await port.historyAt(2).timeout(_guard);
    expect(summariesFeed.retryCloseCalls, 2);
    // The replacement exists only after the original owner was retried and
    // released by its own close report.
    expect(port.summariesOpenTraces, hasLength(1));
    expect(port.summariesOpenTraces.single.retryCloseCalls, 2);
    expect(port.summariesOpenTraces.single.closeCalls, 1);
    expect(port.summariesOpenTraces.single.requestCloseCalls, greaterThan(0));

    port.summaryScripts[_summaryRef2] = nextSummaries;
    port.historyScripts[_historyRef2] = nextHistory;
    await _listen(reopenedSummaries, reopenedHistory);
    reopenedSummaries.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 2,
        reference: _summaryRef2,
        collection: nextSummaries.collection,
      ),
    );
    reopenedHistory.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 2,
        reference: _historyRef2,
        collection: nextHistory.collection,
      ),
    );
    await reopenedSummaries.acknowledged(1).timeout(_guard);
    await reopenedHistory.acknowledged(1).timeout(_guard);
    await retried.timeout(_guard);
    expect(repository.state.value.snapshot!.revision, 2);

    reopened.release();
  });

  test(
    'a native summaries resync replaces only that lane after its real join',
    () async {
      final summaries = _summaries(total: 1);
      final history = _history(total: 1);
      final nextSummaries = _summaries(total: 1, collectionRevision: 2);
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
        summaryScripts: {_summaryRef: summaries},
        historyScripts: {_historyRef: history},
      );
      final budget = ResourceBudget();
      final repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      final lease = repository.acquireVisibleDemand();
      final summariesFeed = await port.summariesAt(1).timeout(_guard);
      final historyFeed = await port.historyAt(1).timeout(_guard);
      await _listen(summariesFeed, historyFeed);
      summariesFeed.emit(
        summariesBaseline(
          feedId: 'summaries',
          origin: _origin,
          revision: 1,
          reference: _summaryRef,
          collection: summaries.collection,
        ),
      );
      historyFeed.emit(
        historyBaseline(
          feedId: 'history',
          origin: _origin,
          revision: 1,
          reference: _historyRef,
          collection: history.collection,
        ),
      );
      await summariesFeed.acknowledged(1).timeout(_guard);
      await historyFeed.acknowledged(1).timeout(_guard);
      await repository.synchronize().timeout(_guard);
      final first = repository.state.value.snapshot!;

      // The retired lane cannot be replaced before its own native close joins.
      final closeReceipt = Completer<FeedCloseReport>();
      summariesFeed.closeReceipt = closeReceipt;
      summariesFeed.emit(
        summariesResyncRequired(feedId: 'summaries', origin: _origin),
      );
      await summariesFeed.closeStarted.future.timeout(_guard);
      expect(
        port.summariesOpenCalls,
        1,
        reason: 'The replacement lane waits for the original real join',
      );
      expect(summariesFeed.acknowledgements, [
        1,
      ], reason: 'A resync control frame is never confirmed as delivered data');
      expect(port.historyOpenCalls, 1);
      expect(historyFeed.requestCloseCalls, 0);
      expect(repository.state.value.snapshot, first);

      closeReceipt.complete(
        FeedCloseReport(
          feedId: 'summaries',
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
      final replacement = await port.summariesAt(2).timeout(_guard);
      await replacement.listened.future.timeout(_guard);
      expect(port.historyOpenCalls, 1);
      expect(historyFeed.requestCloseCalls, 0);
      expect(port.summariesOpenTraces.single.closeCalls, 1);
      expect(port.summariesOpenTraces.single.requestCloseCalls, greaterThan(0));
      expect(
        repository.state.value.snapshot,
        first,
        reason: 'One lane restart never publishes half a pair',
      );

      // The untouched history lane may advance while the summaries lane is
      // re-establishing; the last complete summaries material still stays.
      historyFeed.emit(
        historyChange(
          origin: _origin,
          deliverySequence: 2,
          revision: 2,
          baseRevision: 1,
          reference: _historyRef,
          collection: ProductCollectionRef(
            entry: 4,
            revision: 2,
            total: history.collection.total,
          ),
          baseCollectionRevision: 1,
        ),
      );
      await historyFeed.acknowledged(2).timeout(_guard);
      expect(historyFeed.acknowledgements, [1, 2]);
      expect(repository.state.value.snapshot, first);

      port.summaryScripts[_summaryRef2] = nextSummaries;
      replacement.emit(
        summariesBaseline(
          feedId: 'summaries',
          origin: _origin,
          revision: 2,
          reference: _summaryRef2,
          collection: nextSummaries.collection,
        ),
      );
      await replacement.acknowledged(1).timeout(_guard);
      final paired = await _waitFor(
        repository,
        (state) => state.snapshot?.revision == 2,
      );
      expect(paired.snapshot!.historyReference, _historyRef);
      expect(paired.snapshot!.summaries, hasLength(1));
      expect(paired.snapshot!.history, hasLength(1));

      lease.release();
    },
  );

  test(
    'a lane exhausts its bounded resubscriptions instead of opening forever',
    () async {
      final summaries = _summaries(total: 1);
      final history = _history(total: 1);
      final port = ScriptedStatisticsPort(
        origin: _origin,
        summariesFeedId: 'summaries',
        historyFeedId: 'history',
        summaryScripts: {_summaryRef: summaries},
        historyScripts: {_historyRef: history},
      );
      final budget = ResourceBudget();
      final repository = createStatisticsRepository(port: port, budget: budget);
      addTearDown(() => _expectClean(repository, budget));

      final lease = repository.acquireVisibleDemand();
      final summariesFeed = await port.summariesAt(1).timeout(_guard);
      final historyFeed = await port.historyAt(1).timeout(_guard);
      await _listen(summariesFeed, historyFeed);
      summariesFeed.emit(
        summariesBaseline(
          feedId: 'summaries',
          origin: _origin,
          revision: 1,
          reference: _summaryRef,
          collection: summaries.collection,
        ),
      );
      historyFeed.emit(
        historyBaseline(
          feedId: 'history',
          origin: _origin,
          revision: 1,
          reference: _historyRef,
          collection: history.collection,
        ),
      );
      await summariesFeed.acknowledged(1).timeout(_guard);
      await historyFeed.acknowledged(1).timeout(_guard);
      await repository.synchronize().timeout(_guard);
      final first = repository.state.value.snapshot!;

      // Three recoveries are allowed; each replacement followed the previous
      // lane's own native close.
      var lane = summariesFeed;
      for (var recovery = 1; recovery <= 3; recovery++) {
        lane.emit(summariesOwnerReplaced(feedId: 'summaries', origin: _origin));
        lane = await port.summariesAt(recovery + 1).timeout(_guard);
        await lane.listened.future.timeout(_guard);
        expect(port.summariesOpenCalls, recovery + 1);
        expect(port.historyOpenCalls, 1);
        expect(historyFeed.requestCloseCalls, 0);
        expect(
          port.summariesOpenTraces.last.closeCalls,
          greaterThanOrEqualTo(1),
        );
        expect(
          port.summariesOpenTraces.last.requestCloseCalls,
          greaterThanOrEqualTo(1),
        );
      }

      // The fourth replacement request is a typed terminal failure, not another
      // lane.
      lane.emit(summariesOwnerReplaced(feedId: 'summaries', origin: _origin));
      final failed = await _waitFor(
        repository,
        (state) => state.sync.phase == ResourceSyncPhase.failed,
      );
      expect(failed.snapshot, first);
      expect(failed.sync.error!.code, StudioFailureCode.unavailable);
      expect(failed.sync.error!.message, contains('exhausted'));
      expect(port.summariesOpenCalls, 4);
      expect(historyFeed.requestCloseCalls, greaterThan(0));

      final report = await repository
          .close(deadline: DateTime.now().add(_guard))
          .timeout(_guard);
      expect(report.complete, isTrue);
      expect(
        port.summariesOpenCalls,
        4,
        reason: 'Cleanup joins the failed lane instead of opening another one',
      );
      expect(budget.usage, isEmpty);

      lease.release();
    },
  );

  test('an identity is pinned by its origin and complete reference, never by its entry', () async {
    // One origin declares the same identity entry under two revisions. Reading
    // the older material again — in a fresh attempt whose reader holds no
    // identity cache — must return that material's own frozen identity.
    final first = _summaries(total: 1, account: 'alpha');
    final second = _summaries(
      total: 1,
      collectionRevision: 2,
      account: 'beta',
      identityRevision: 2,
    );
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: first, _summaryRef3: second},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(() => _expectClean(repository, budget));

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: first.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);
    expect(
      repository.state.value.snapshot!.summaries.single.identity.accountId,
      'alpha-0',
    );

    summaryFeed.emit(
      summariesChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _summaryRef3,
        collection: second.collection,
        baseCollectionRevision: 1,
      ),
    );
    historyFeed.emit(
      historyChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _historyRef,
        collection: const ProductCollectionRef(entry: 4, revision: 2, total: 1),
        baseCollectionRevision: 1,
      ),
    );
    await summaryFeed.acknowledged(2).timeout(_guard);
    await historyFeed.acknowledged(2).timeout(_guard);
    final upgraded = await _waitFor(
      repository,
      (state) => state.snapshot?.revision == 2,
    );
    expect(upgraded.snapshot!.summaries.single.identity.accountId, 'beta-0');

    // A new attempt reads the older pinned reference from the native boundary
    // again: the newer entry-1000 row must not answer it.
    lease.release();
    await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.idle,
    );
    final visible = repository.acquireVisibleDemand();
    final syncing = repository.synchronize();
    final nextSummary = await port.summariesAt(2).timeout(_guard);
    final nextHistory = await port.historyAt(2).timeout(_guard);
    await _listen(nextSummary, nextHistory);
    // Another material — a new complete material reference, never the first one
    // re-bound to a newer collection — pins the older identity reference again:
    // the same frozen value must come back even though a newer material declared
    // the same identity entry under revision 2.
    final rereadMaterial = _summaries(
      total: 1,
      account: 'alpha',
      collectionRevision: 3,
    );
    port.summaryScripts[_summaryRef2] = rereadMaterial;
    nextSummary.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 3,
        reference: _summaryRef2,
        collection: rereadMaterial.collection,
      ),
    );
    nextHistory.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 3,
        reference: _historyRef,
        collection: const ProductCollectionRef(entry: 4, revision: 3, total: 1),
      ),
    );
    await nextSummary.acknowledged(1).timeout(_guard);
    await nextHistory.acknowledged(1).timeout(_guard);
    await syncing.timeout(_guard);
    final reread = await _waitFor(
      repository,
      (state) => state.snapshot?.revision == 3,
    );
    expect(
      reread.snapshot!.summaries.single.identity.accountId,
      'alpha-0',
      reason:
          'The older pinned reference keeps its own frozen identity, not the '
          'newer revision that shares its entry',
    );
    expect(port.summaryIdentityReads, hasLength(3));

    visible.release();
  });

  test('a material that declares no identity for its row fails instead of borrowing one', () async {
    // The material declares entity entry 100 whose identity reference is
    // entry 1000, but declares no identity for it at all. Silently reusing any
    // other row's identity would publish a wrong frozen fact.
    final incomplete = SummariesMaterialScript(
      collection: const ProductCollectionRef(entry: 3, revision: 1, total: 1),
      entries: const [ProductEntityRef(entry: 100, revision: 1)],
      entities: {
        100: PerformanceSummaryRead(
          identity: const PerformanceSummaryIdentityRef(
            entry: 1000,
            revision: 1,
          ),
          counters: _counters(),
          effortBreakdowns: const TypedListRef(listId: 2000, total: 0),
        ),
      },
    );
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: incomplete},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(
      () => repository
          .close(deadline: DateTime.now().add(_guard))
          .timeout(_guard),
    );

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: incomplete.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    final failed = await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.failed,
    );
    expect(failed.sync.error, isNotNull);
    expect(failed.snapshot, isNull, reason: 'No partial material publishes');
    expect(
      summaryFeed.acknowledgements,
      isEmpty,
      reason: 'An unconfirmed material is never acknowledged',
    );

    lease.release();
  });

  test('one origin cannot redeclare a pinned identity with another frozen value', () async {
    final first = _summaries(total: 1, account: 'alpha');
    // Same origin, same complete identity reference (entry 1000, revision 1),
    // another frozen value: an immutable native declaration cannot be replaced
    // by a later material that happens to share its entry.
    final conflicting = _summaries(
      total: 1,
      collectionRevision: 2,
      account: 'gamma',
    );
    final history = _history(total: 1);
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryScripts: {_summaryRef: first, _summaryRef3: conflicting},
      historyScripts: {_historyRef: history},
    );
    final budget = ResourceBudget();
    final repository = createStatisticsRepository(port: port, budget: budget);
    addTearDown(
      () => repository
          .close(deadline: DateTime.now().add(_guard))
          .timeout(_guard),
    );

    final lease = repository.acquireVisibleDemand();
    final summaryFeed = await port.summariesAt(1).timeout(_guard);
    final historyFeed = await port.historyAt(1).timeout(_guard);
    await _listen(summaryFeed, historyFeed);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'summaries',
        origin: _origin,
        revision: 1,
        reference: _summaryRef,
        collection: first.collection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'history',
        origin: _origin,
        revision: 1,
        reference: _historyRef,
        collection: history.collection,
      ),
    );
    await summaryFeed.acknowledged(1).timeout(_guard);
    await historyFeed.acknowledged(1).timeout(_guard);
    await repository.synchronize().timeout(_guard);

    summaryFeed.emit(
      summariesChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _summaryRef3,
        collection: conflicting.collection,
        baseCollectionRevision: 1,
      ),
    );
    historyFeed.emit(
      historyChange(
        origin: _origin,
        deliverySequence: 2,
        revision: 2,
        baseRevision: 1,
        reference: _historyRef,
        collection: const ProductCollectionRef(entry: 4, revision: 2, total: 1),
        baseCollectionRevision: 1,
      ),
    );
    final failed = await _waitFor(
      repository,
      (state) => state.sync.phase == ResourceSyncPhase.failed,
    );
    expect(failed.sync.error, isNotNull);
    expect(failed.snapshot!.revision, 1);
    expect(
      failed.snapshot!.summaries.single.identity.accountId,
      'alpha-0',
      reason: 'The older declaration is never silently replaced',
    );
    expect(summaryFeed.acknowledgements, [
      1,
    ], reason: 'Only the original confirmed frame stays acknowledged');

    lease.release();
  });

  // Scripted-boundary verification, not a production proof: a complete material
  // always declares its own row identities, so the Repository never needs this
  // branch. The 25 cases above stay the production-level evidence; this one only
  // pins that the native double cannot answer another origin with this port's
  // direct script.
  test('a direct identity script answers only its own authority origin', () async {
    const summaryRef = PerformanceSummaryIdentityRef(entry: 10, revision: 1);
    const effortRef = PerformanceEffortIdentityRef(entry: 20, revision: 1);
    const sampleRef = PerformanceSampleIdentityRef(entry: 30, revision: 1);
    const summaryValue = PerformanceSummaryIdentityRead(
      accountId: ReadText.inline(text: 'account-a'),
      accountDisplayName: ReadText.inline(text: 'Alpha'),
      modelId: ReadText.inline(text: 'shared-model'),
    );
    const effortValue = PerformanceEffortIdentityRead(
      effort: ReadText.inline(text: 'high'),
    );
    const sampleValue = PerformanceSampleIdentityRead(
      accountId: ReadText.inline(text: 'account-a'),
      accountDisplayName: ReadText.inline(text: 'Alpha'),
      modelId: ReadText.inline(text: 'shared-model'),
      sentModel: null,
      reportedModel: null,
      modelMatchState: ModelMatchState.matched,
      effort: ReadText.inline(text: 'high'),
    );
    final port = ScriptedStatisticsPort(
      origin: _origin,
      summariesFeedId: 'summaries',
      historyFeedId: 'history',
      summaryIdentities: {summaryRef: summaryValue},
      effortIdentities: {effortRef: effortValue},
      sampleIdentities: {sampleRef: sampleValue},
    );

    // The port's own authority origin is answered by the direct script.
    await port.openSummaryIdentity(summaryRef, origin: _origin);
    await port.openEffortIdentity(effortRef, origin: _origin);
    await port.openSampleIdentity(sampleRef, origin: _origin);
    expect(port.summaryIdentityReads, hasLength(1));
    expect(port.effortIdentityReads, hasLength(1));
    expect(port.sampleIdentityReads, hasLength(1));

    // Another authority origin is never answered by this port's direct script:
    // the read fails before any value is produced, so no fake identity and no
    // extra scope exists afterwards.
    await expectLater(
      port.openSummaryIdentity(summaryRef, origin: _otherOrigin),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      port.openEffortIdentity(effortRef, origin: _otherOrigin),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      port.openSampleIdentity(sampleRef, origin: _otherOrigin),
      throwsA(isA<UnsupportedError>()),
    );
    expect(port.summaryIdentityReads, hasLength(1));
    expect(port.effortIdentityReads, hasLength(1));
    expect(port.sampleIdentityReads, hasLength(1));
    expect(
      port.summariesOpenCalls,
      0,
      reason: 'A rejected identity read opens no feed of another origin',
    );
    expect(port.historyOpenCalls, 0);
  });
}
