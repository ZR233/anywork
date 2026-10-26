import 'dart:async';
import 'dart:collection';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart' show FeedConnection;
import 'package:anywork_client/statistics_ports.dart';

import 'profile_native_pin.dart' show profileIdentity, profileStamp;
import 'scripted_feed.dart';

/// Barrier that lets one behavior test release a specific native operation
/// without timers. The product owner still joins the original Future.
final class StatisticsTestGate {
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<void> wait() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
}

/// One scripted `openPerformance*` result: optional barrier, optional failure.
final class StatisticsOpenScript {
  const StatisticsOpenScript({this.gate, this.fail = false, this.onOpen});

  final StatisticsTestGate? gate;
  final bool fail;

  /// Runs synchronously inside the native open, before the barrier, so a test
  /// can reenter close or retry from the opening callback itself.
  final void Function()? onOpen;
}

/// Close bookkeeping of the lane a replacement open followed. It is recorded at
/// the moment the replacement is opened, so a leaked or unjoined owner is
/// visible instead of being papered over by a later successful close.
final class StatisticsOpenTrace {
  const StatisticsOpenTrace({
    required this.closeCalls,
    required this.retryCloseCalls,
    required this.requestCloseCalls,
  });

  final int closeCalls;
  final int retryCloseCalls;
  final int requestCloseCalls;
}

/// Declares one deferred native text field together with its exact chunk source
/// so the declared byte length and the scripted chunks cannot disagree.
///
/// The scripted text is ASCII: UTF-8 byte offsets equal code-unit offsets, which
/// keeps the scripted native boundary readable while the production reader still
/// validates byte counts, continuity and the final `nextOffset`.
final class StatisticsTestText {
  const StatisticsTestText(this.fieldId, this.text, {this.chunkBytes});

  final int fieldId;
  final String text;

  /// Per-chunk bound; smaller than the requested `maxBytes` proves that the
  /// reader joins several real chunks instead of assuming one reply.
  final int? chunkBytes;

  ReadText get read =>
      ReadText.deferred(fieldId: fieldId, utf8Bytes: text.length);
}

/// Immutable native material of one summaries read scope.
final class SummariesMaterialScript {
  SummariesMaterialScript({
    required this.collection,
    required Iterable<ProductEntityRef> entries,
    required Map<int, PerformanceSummaryRead> entities,
    Map<int, List<PerformanceEffortRead>> efforts = const {},
    Map<int, PerformanceSummaryIdentityRead> identities = const {},
    Map<int, PerformanceEffortIdentityRead> effortIdentities = const {},
    Iterable<StatisticsTestText> deferredTexts = const [],
    this.entriesGate,
    this.entityGate,
  }) : entries = List<ProductEntityRef>.unmodifiable(entries),
       entities = Map<int, PerformanceSummaryRead>.unmodifiable(entities),
       efforts = Map<int, List<PerformanceEffortRead>>.unmodifiable({
         for (final entry in efforts.entries)
           entry.key: List<PerformanceEffortRead>.unmodifiable(entry.value),
       }),
       identities = Map<int, PerformanceSummaryIdentityRead>.unmodifiable(
         identities,
       ),
       effortIdentities = Map<int, PerformanceEffortIdentityRead>.unmodifiable(
         effortIdentities,
       ),
       texts = Map<int, StatisticsTestText>.unmodifiable({
         for (final text in deferredTexts) text.fieldId: text,
       });

  final ProductCollectionRef collection;
  final List<ProductEntityRef> entries;
  final Map<int, PerformanceSummaryRead> entities;
  final Map<int, List<PerformanceEffortRead>> efforts;
  final Map<int, PerformanceSummaryIdentityRead> identities;
  final Map<int, PerformanceEffortIdentityRead> effortIdentities;
  final Map<int, StatisticsTestText> texts;
  final StatisticsTestGate? entriesGate;
  final StatisticsTestGate? entityGate;
}

/// Immutable native material of one history read scope.
final class HistoryMaterialScript {
  HistoryMaterialScript({
    required this.collection,
    required Iterable<ProductEntityRef> entries,
    required Map<int, PerformanceSampleRead> entities,
    Map<int, PerformanceSampleIdentityRead> identities = const {},
    Iterable<StatisticsTestText> deferredTexts = const [],
    this.entriesGate,
    this.entityGate,
  }) : entries = List<ProductEntityRef>.unmodifiable(entries),
       entities = Map<int, PerformanceSampleRead>.unmodifiable(entities),
       identities = Map<int, PerformanceSampleIdentityRead>.unmodifiable(
         identities,
       ),
       texts = Map<int, StatisticsTestText>.unmodifiable({
         for (final text in deferredTexts) text.fieldId: text,
       });

  final ProductCollectionRef collection;
  final List<ProductEntityRef> entries;
  final Map<int, PerformanceSampleRead> entities;
  final Map<int, PerformanceSampleIdentityRead> identities;
  final Map<int, StatisticsTestText> texts;
  final StatisticsTestGate? entriesGate;
  final StatisticsTestGate? entityGate;
}

/// Native index page for one captured collection, computed from the declared
/// entries so a script can only break continuity on purpose.
({List<T> items, int? nextOffset}) statisticsTestPage<T>(
  List<T> values,
  int offset,
  int limit,
  int total,
) {
  final start = offset < 0
      ? 0
      : (offset > values.length ? values.length : offset);
  final capped = start + limit > values.length ? values.length : start + limit;
  final items = values.sublist(start, capped);
  final end = start + items.length;
  return (items: items, nextOffset: end == total ? null : end);
}

/// Scripted native read lifetime: replies, call receipts and close rights only.
abstract base class ScriptedStatisticsRead {
  ScriptedStatisticsRead(this.id, this.texts);

  final String id;
  final Map<int, StatisticsTestText> texts;
  final closeRequested = Completer<void>();
  final closeStarted = Completer<void>();
  final textReads = <({int fieldId, int offset})>[];
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  bool closed = false;
  FeedCloseOutcome outcome = const FeedCloseOutcome.clean();

  void requestClose() {
    requestCloseCalls++;
    if (!closeRequested.isCompleted) closeRequested.complete();
  }

  Future<FeedCloseReport> close() {
    closeCalls++;
    return _finish();
  }

  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    return _finish();
  }

  Future<FeedCloseReport> _finish() async {
    if (!closeStarted.isCompleted) closeStarted.complete();
    requestClose();
    closed = true;
    return FeedCloseReport(feedId: id, outcome: outcome);
  }

  Future<TextChunk> readText(
    int fieldId, {
    int offset = 0,
    int maxBytes = 65536,
  }) async {
    textReads.add((fieldId: fieldId, offset: offset));
    final script = texts[fieldId];
    if (script == null) {
      throw UnsupportedError('No scripted statistics text field $fieldId');
    }
    final start = offset > script.text.length ? script.text.length : offset;
    final bound = script.chunkBytes ?? maxBytes;
    final limit = bound > maxBytes ? maxBytes : bound;
    final end = start + limit > script.text.length
        ? script.text.length
        : start + limit;
    return TextChunk(
      fieldId: fieldId,
      offset: start,
      text: script.text.substring(start, end),
      nextOffset: end == script.text.length ? null : end,
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted statistics native capability: ${invocation.memberName}',
  );
}

final class ScriptedSummariesRead extends ScriptedStatisticsRead
    implements PerformanceSummariesReadConnection {
  ScriptedSummariesRead(this.ordinal, this.script)
    : super('statistics-summaries-read-$ordinal', script.texts);

  final int ordinal;
  final SummariesMaterialScript script;
  final entriesOffsets = <int>[];
  final entityReads = <ProductEntityRef>[];
  final effortPages = <({int listId, int offset})>[];
  int headerCalls = 0;

  @override
  Future<PerformanceSummariesReadHeader> header() async {
    headerCalls++;
    return PerformanceSummariesReadHeader(
      summaries: TypedListRef(
        listId: script.collection.entry,
        total: script.collection.total,
      ),
    );
  }

  @override
  Future<PerformanceSummariesEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    entriesOffsets.add(offset);
    await script.entriesGate?.wait();
    final page = statisticsTestPage(
      script.entries,
      offset,
      limit,
      script.collection.total,
    );
    return PerformanceSummariesEntryPage(
      collection: script.collection,
      offset: offset,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  }

  @override
  Future<PerformanceSummariesEntityRead> entity(
    ProductEntityRef reference,
  ) async {
    entityReads.add(reference);
    await script.entityGate?.wait();
    final value = script.entities[reference.entry];
    if (value == null) {
      throw UnsupportedError('No scripted summary entity ${reference.entry}');
    }
    return PerformanceSummariesEntityRead(reference: reference, value: value);
  }

  @override
  Future<PerformanceEffortReadPage> effortBreakdowns(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    effortPages.add((listId: listId, offset: offset));
    final values = script.efforts[listId];
    if (values == null) {
      throw UnsupportedError('No scripted effort list $listId');
    }
    final page = statisticsTestPage(values, offset, limit, values.length);
    return PerformanceEffortReadPage(
      listId: listId,
      offset: offset,
      total: values.length,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      readText(fieldId, offset: offset, maxBytes: maxBytes);

  @override
  Future<ProductEntityRef?> lookupSummary(
    String accountId,
    String modelId,
  ) async => throw UnsupportedError('Unscripted summary lookup');

  @override
  Future<PerformanceSummaryReadPage> summaries(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async => throw UnsupportedError('Unscripted summary list $listId');
}

final class ScriptedHistoryRead extends ScriptedStatisticsRead
    implements PerformanceHistoryReadConnection {
  ScriptedHistoryRead(this.ordinal, this.script)
    : super('statistics-history-read-$ordinal', script.texts);

  final int ordinal;
  final HistoryMaterialScript script;
  final entriesOffsets = <int>[];
  final entityReads = <ProductEntityRef>[];
  int headerCalls = 0;

  @override
  Future<PerformanceHistoryReadHeader> header() async {
    headerCalls++;
    return PerformanceHistoryReadHeader(
      samples: TypedListRef(
        listId: script.collection.entry,
        total: script.collection.total,
      ),
    );
  }

  @override
  Future<PerformanceHistoryEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    entriesOffsets.add(offset);
    await script.entriesGate?.wait();
    final page = statisticsTestPage(
      script.entries,
      offset,
      limit,
      script.collection.total,
    );
    return PerformanceHistoryEntryPage(
      collection: script.collection,
      offset: offset,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  }

  @override
  Future<PerformanceHistoryEntityRead> entity(
    ProductEntityRef reference,
  ) async {
    entityReads.add(reference);
    await script.entityGate?.wait();
    final value = script.entities[reference.entry];
    if (value == null) {
      throw UnsupportedError('No scripted sample entity ${reference.entry}');
    }
    return PerformanceHistoryEntityRead(reference: reference, value: value);
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      readText(fieldId, offset: offset, maxBytes: maxBytes);

  @override
  Future<PerformanceSampleReadPage> samples(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async => throw UnsupportedError('Unscripted sample list $listId');
}

final class ScriptedSummaryIdentityRead extends ScriptedStatisticsRead
    implements PerformanceSummaryIdentityReadConnection {
  ScriptedSummaryIdentityRead(
    this.ordinal,
    this.value,
    Map<int, StatisticsTestText> texts,
  ) : super('statistics-summary-identity-$ordinal', texts);

  final int ordinal;
  final PerformanceSummaryIdentityRead value;
  int headerCalls = 0;

  @override
  Future<PerformanceSummaryIdentityRead> header() async {
    headerCalls++;
    return value;
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      readText(fieldId, offset: offset, maxBytes: maxBytes);
}

final class ScriptedEffortIdentityRead extends ScriptedStatisticsRead
    implements PerformanceEffortIdentityReadConnection {
  ScriptedEffortIdentityRead(
    this.ordinal,
    this.value,
    Map<int, StatisticsTestText> texts,
  ) : super('statistics-effort-identity-$ordinal', texts);

  final int ordinal;
  final PerformanceEffortIdentityRead value;
  int headerCalls = 0;

  @override
  Future<PerformanceEffortIdentityRead> header() async {
    headerCalls++;
    return value;
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      readText(fieldId, offset: offset, maxBytes: maxBytes);
}

final class ScriptedSampleIdentityRead extends ScriptedStatisticsRead
    implements PerformanceSampleIdentityReadConnection {
  ScriptedSampleIdentityRead(
    this.ordinal,
    this.value,
    Map<int, StatisticsTestText> texts,
  ) : super('statistics-sample-identity-$ordinal', texts);

  final int ordinal;
  final PerformanceSampleIdentityRead value;
  int headerCalls = 0;

  @override
  Future<PerformanceSampleIdentityRead> header() async {
    headerCalls++;
    return value;
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      readText(fieldId, offset: offset, maxBytes: maxBytes);
}

/// Scripted statistics transport: it records and answers the native feeds and
/// read scopes declared by a test. It never merges, caches or reconnects; those
/// are the Repository responsibilities under test.
final class ScriptedStatisticsPort implements StatisticsPort {
  ScriptedStatisticsPort({
    required this.origin,
    required this.summariesFeedId,
    required this.historyFeedId,
    Map<PerformanceSummariesReadRef, SummariesMaterialScript> summaryScripts =
        const {},
    Map<PerformanceHistoryReadRef, HistoryMaterialScript> historyScripts =
        const {},
    Map<PerformanceSummaryIdentityRef, PerformanceSummaryIdentityRead>
        summaryIdentities =
        const {},
    Map<PerformanceEffortIdentityRef, PerformanceEffortIdentityRead>
        effortIdentities =
        const {},
    Map<PerformanceSampleIdentityRef, PerformanceSampleIdentityRead>
        sampleIdentities =
        const {},
    Iterable<StatisticsTestText> identityTexts = const [],
  }) : summaryScripts =
           Map<PerformanceSummariesReadRef, SummariesMaterialScript>.of(
             summaryScripts,
           ),
       historyScripts =
           Map<PerformanceHistoryReadRef, HistoryMaterialScript>.of(
             historyScripts,
           ),
       summaryIdentities =
           Map<
             PerformanceSummaryIdentityRef,
             PerformanceSummaryIdentityRead
           >.of(summaryIdentities),
       effortIdentities =
           Map<PerformanceEffortIdentityRef, PerformanceEffortIdentityRead>.of(
             effortIdentities,
           ),
       sampleIdentities =
           Map<PerformanceSampleIdentityRef, PerformanceSampleIdentityRead>.of(
             sampleIdentities,
           ),
       identityTexts = Map<int, StatisticsTestText>.of({
         for (final text in identityTexts) text.fieldId: text,
       });

  final ProductReadOrigin origin;
  final String summariesFeedId;
  final String historyFeedId;
  final Map<PerformanceSummariesReadRef, SummariesMaterialScript>
  summaryScripts;
  final Map<PerformanceHistoryReadRef, HistoryMaterialScript> historyScripts;
  final Map<PerformanceSummaryIdentityRef, PerformanceSummaryIdentityRead>
  summaryIdentities;
  final Map<PerformanceEffortIdentityRef, PerformanceEffortIdentityRead>
  effortIdentities;
  final Map<PerformanceSampleIdentityRef, PerformanceSampleIdentityRead>
  sampleIdentities;
  final Map<int, StatisticsTestText> identityTexts;

  /// Native identity answers a material declares for its own rows, indexed by
  /// the authority origin and the complete typed reference that same material
  /// declared in its entities. A later material never rebinds an older one: an
  /// equal re-declaration is idempotent and a disagreeing one is an explicit
  /// script conflict, so one origin's pinned reference can never be answered by
  /// another origin's or another revision's row that happens to share its entry.
  final _summaryIdentitiesByOrigin =
      <
        ProductReadOrigin,
        Map<PerformanceSummaryIdentityRef, PerformanceSummaryIdentityRead>
      >{};
  final _effortIdentitiesByOrigin =
      <
        ProductReadOrigin,
        Map<PerformanceEffortIdentityRef, PerformanceEffortIdentityRead>
      >{};
  final _sampleIdentitiesByOrigin =
      <
        ProductReadOrigin,
        Map<PerformanceSampleIdentityRef, PerformanceSampleIdentityRead>
      >{};

  final summaryOpenScripts = Queue<StatisticsOpenScript>();
  final historyOpenScripts = Queue<StatisticsOpenScript>();
  final summariesReads = <ScriptedSummariesRead>[];
  final historyReads = <ScriptedHistoryRead>[];
  final summaryIdentityReads = <ScriptedSummaryIdentityRead>[];
  final effortIdentityReads = <ScriptedEffortIdentityRead>[];
  final sampleIdentityReads = <ScriptedSampleIdentityRead>[];
  final summaryReadOpens =
      <({ProductReadOrigin origin, PerformanceSummariesReadRef reference})>[];
  final historyReadOpens =
      <({ProductReadOrigin origin, PerformanceHistoryReadRef reference})>[];
  final summariesOpenTraces = <StatisticsOpenTrace>[];
  final historyOpenTraces = <StatisticsOpenTrace>[];
  int summariesOpenCalls = 0;
  int historyOpenCalls = 0;

  final _summariesFeeds = <ScriptedFeed<PerformanceSummariesFrame>>[];
  final _historyFeeds = <ScriptedFeed<PerformanceHistoryFrame>>[];
  final _summariesOpened = <int, ScriptedFeed<PerformanceSummariesFrame>>{};
  final _historyOpened = <int, ScriptedFeed<PerformanceHistoryFrame>>{};
  final _summariesWaiters =
      <int, Completer<ScriptedFeed<PerformanceSummariesFrame>>>{};
  final _historyWaiters =
      <int, Completer<ScriptedFeed<PerformanceHistoryFrame>>>{};

  ScriptedFeed<PerformanceSummariesFrame> get summariesFeed =>
      _summariesFeeds.last;
  ScriptedFeed<PerformanceHistoryFrame> get historyFeed => _historyFeeds.last;

  Future<ScriptedFeed<PerformanceSummariesFrame>> summariesAt(int ordinal) {
    final opened = _summariesOpened[ordinal];
    if (opened != null) return Future.value(opened);
    return (_summariesWaiters[ordinal] ??=
            Completer<ScriptedFeed<PerformanceSummariesFrame>>())
        .future;
  }

  Future<ScriptedFeed<PerformanceHistoryFrame>> historyAt(int ordinal) {
    final opened = _historyOpened[ordinal];
    if (opened != null) return Future.value(opened);
    return (_historyWaiters[ordinal] ??=
            Completer<ScriptedFeed<PerformanceHistoryFrame>>())
        .future;
  }

  @override
  Future<FeedConnection<PerformanceSummariesFrame>>
  openPerformanceSummaries() async {
    final ordinal = ++summariesOpenCalls;
    if (_summariesFeeds.isNotEmpty) {
      final previous = _summariesFeeds.last;
      summariesOpenTraces.add(
        StatisticsOpenTrace(
          closeCalls: previous.closeCalls,
          retryCloseCalls: previous.retryCloseCalls,
          requestCloseCalls: previous.requestCloseCalls,
        ),
      );
    }
    final script = summaryOpenScripts.isEmpty
        ? const StatisticsOpenScript()
        : summaryOpenScripts.removeFirst();
    script.onOpen?.call();
    final gate = script.gate;
    if (gate != null) await gate.wait();
    if (script.fail) {
      throw StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'The scripted summaries feed is unavailable.',
        retryable: true,
        correlationId: summariesFeedId,
      );
    }
    final feed = ScriptedFeed<PerformanceSummariesFrame>(
      feedId: summariesFeedId,
      sequenceOf: (frame) =>
          frame is PerformanceSummariesData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! PerformanceSummariesData,
    );
    _summariesFeeds.add(feed);
    _summariesOpened[ordinal] = feed;
    _summariesWaiters.remove(ordinal)?.complete(feed);
    return feed;
  }

  @override
  Future<FeedConnection<PerformanceHistoryFrame>>
  openPerformanceHistory() async {
    final ordinal = ++historyOpenCalls;
    if (_historyFeeds.isNotEmpty) {
      final previous = _historyFeeds.last;
      historyOpenTraces.add(
        StatisticsOpenTrace(
          closeCalls: previous.closeCalls,
          retryCloseCalls: previous.retryCloseCalls,
          requestCloseCalls: previous.requestCloseCalls,
        ),
      );
    }
    final script = historyOpenScripts.isEmpty
        ? const StatisticsOpenScript()
        : historyOpenScripts.removeFirst();
    script.onOpen?.call();
    final gate = script.gate;
    if (gate != null) await gate.wait();
    if (script.fail) {
      throw StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'The scripted history feed is unavailable.',
        retryable: true,
        correlationId: historyFeedId,
      );
    }
    final feed = ScriptedFeed<PerformanceHistoryFrame>(
      feedId: historyFeedId,
      sequenceOf: (frame) =>
          frame is PerformanceHistoryData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! PerformanceHistoryData,
    );
    _historyFeeds.add(feed);
    _historyOpened[ordinal] = feed;
    _historyWaiters.remove(ordinal)?.complete(feed);
    return feed;
  }

  @override
  Future<PerformanceSummariesReadConnection> openPerformanceSummariesRead(
    PerformanceSummariesReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    summaryReadOpens.add((origin: origin, reference: reference));
    final script = summaryScripts[reference];
    if (script == null) {
      throw UnsupportedError('No scripted summaries material for $reference');
    }
    // The material owns the identities of its own rows; declaring them before
    // the scope exists keeps a missing or conflicting declaration an explicit
    // open failure instead of a later silent substitution.
    _declareSummaries(origin, script);
    final read = ScriptedSummariesRead(summariesReads.length + 1, script);
    summariesReads.add(read);
    return read;
  }

  @override
  Future<PerformanceHistoryReadConnection> openPerformanceHistoryRead(
    PerformanceHistoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    historyReadOpens.add((origin: origin, reference: reference));
    final script = historyScripts[reference];
    if (script == null) {
      throw UnsupportedError('No scripted history material for $reference');
    }
    _declareHistory(origin, script);
    final read = ScriptedHistoryRead(historyReads.length + 1, script);
    historyReads.add(read);
    return read;
  }

  @override
  Future<PerformanceSummaryIdentityReadConnection> openSummaryIdentity(
    PerformanceSummaryIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final value = _resolveIdentity(
      _summaryIdentitiesByOrigin[origin],
      summaryIdentities,
      reference,
      origin,
      'summary',
    );
    final read = ScriptedSummaryIdentityRead(
      summaryIdentityReads.length + 1,
      value,
      identityTexts,
    );
    summaryIdentityReads.add(read);
    return read;
  }

  @override
  Future<PerformanceEffortIdentityReadConnection> openEffortIdentity(
    PerformanceEffortIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final value = _resolveIdentity(
      _effortIdentitiesByOrigin[origin],
      effortIdentities,
      reference,
      origin,
      'effort',
    );
    final read = ScriptedEffortIdentityRead(
      effortIdentityReads.length + 1,
      value,
      identityTexts,
    );
    effortIdentityReads.add(read);
    return read;
  }

  @override
  Future<PerformanceSampleIdentityReadConnection> openSampleIdentity(
    PerformanceSampleIdentityRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final value = _resolveIdentity(
      _sampleIdentitiesByOrigin[origin],
      sampleIdentities,
      reference,
      origin,
      'sample',
    );
    final read = ScriptedSampleIdentityRead(
      sampleIdentityReads.length + 1,
      value,
      identityTexts,
    );
    sampleIdentityReads.add(read);
    return read;
  }

  /// Declares the identities of one summaries material under its own authority
  /// origin, using exactly the typed references that material's entities and
  /// effort rows declare.
  void _declareSummaries(
    ProductReadOrigin origin,
    SummariesMaterialScript script,
  ) {
    final summaries = _summaryIdentitiesByOrigin.putIfAbsent(origin, () => {});
    final efforts = _effortIdentitiesByOrigin.putIfAbsent(origin, () => {});
    for (final row in script.entities.values) {
      _declareIdentity(
        summaries,
        row.identity,
        script.identities[row.identity.entry],
        'summary',
        origin,
      );
    }
    for (final page in script.efforts.values) {
      for (final row in page) {
        _declareIdentity(
          efforts,
          row.identity,
          script.effortIdentities[row.identity.entry],
          'effort',
          origin,
        );
      }
    }
  }

  /// Declares the identities of one history material under its own authority
  /// origin, using exactly the typed reference each sample declares.
  void _declareHistory(ProductReadOrigin origin, HistoryMaterialScript script) {
    final samples = _sampleIdentitiesByOrigin.putIfAbsent(origin, () => {});
    for (final row in script.entities.values) {
      _declareIdentity(
        samples,
        row.identity,
        script.identities[row.identity.entry],
        'sample',
        origin,
      );
    }
  }

  /// Binds one declared identity to its complete reference. The same reference
  /// may be declared again with the same value; another value is a script
  /// conflict rather than a silent replacement of the older declaration.
  void _declareIdentity<TReference extends Object, TValue extends Object>(
    Map<TReference, TValue> declared,
    TReference reference,
    TValue? value,
    String side,
    ProductReadOrigin origin,
  ) {
    if (value == null) {
      throw UnsupportedError(
        'The scripted $side material of ${origin.ownerEpoch}'
        '/${origin.incarnation} declares no identity for $reference',
      );
    }
    final existing = declared[reference];
    if (existing == null) {
      declared[reference] = value;
      return;
    }
    if (existing != value) {
      throw UnsupportedError(
        'The scripted $side identity of ${origin.ownerEpoch}'
        '/${origin.incarnation} was redeclared with another value for '
        '$reference',
      );
    }
  }

  /// Answers one pinned identity read from the same origin and the complete
  /// reference. A direct script stays supported, but it is a declaration of this
  /// port's own authority origin: it is never a substitute for another origin's
  /// read. Another origin is answered only by the material it declared itself. A
  /// direct script that disagrees with the owning material is a conflict, and a
  /// reference no source declared is an explicit failure.
  TValue _resolveIdentity<TReference extends Object, TValue extends Object>(
    Map<TReference, TValue>? fromMaterial,
    Map<TReference, TValue> scripted,
    TReference reference,
    ProductReadOrigin requestOrigin,
    String side,
  ) {
    final material = fromMaterial?[reference];
    // A direct script answers for the port's own origin only. Any other origin
    // must be answered by material that origin declared for the same full
    // reference, so a foreign origin can never receive another origin's value.
    final direct = requestOrigin == origin ? scripted[reference] : null;
    if (material != null && direct != null && material != direct) {
      throw UnsupportedError(
        'The scripted $side identity for $reference disagrees with its material',
      );
    }
    final value = material ?? direct;
    if (value == null) {
      throw UnsupportedError(
        'No scripted $side identity for $reference in '
        '${requestOrigin.ownerEpoch}/${requestOrigin.incarnation}',
      );
    }
    return value;
  }
}

PerformanceSummariesFrame summariesBaseline({
  required String feedId,
  required ProductReadOrigin origin,
  required int revision,
  required PerformanceSummariesReadRef reference,
  required ProductCollectionRef collection,
  int deliverySequence = 1,
  int updatedAt = 1769904000,
  bool statisticsPending = false,
  bool statisticsGap = false,
  bool readFailed = false,
}) => PerformanceSummariesFrame.data(
  deliverySequence: deliverySequence,
  event: PerformanceSummariesEvent.baseline(
    identity: profileIdentity(
      feedId,
      origin,
      ProductResource.performanceSummaries,
    ),
    stamp: profileStamp(origin, revision),
    value: PerformanceSummariesBaseline(
      header: PerformanceSummariesHeader(
        revision: revision,
        updatedAt: updatedAt,
        statisticsPending: statisticsPending,
        statisticsGap: statisticsGap,
        readFailed: readFailed,
        reference: reference,
      ),
      collection: collection,
    ),
  ),
);

PerformanceSummariesFrame summariesChange({
  required ProductReadOrigin origin,
  required int deliverySequence,
  required int revision,
  required int baseRevision,
  required PerformanceSummariesReadRef reference,
  required ProductCollectionRef collection,
  required int baseCollectionRevision,
  int updatedAt = 1769904000,
  bool statisticsPending = false,
  bool statisticsGap = false,
  bool readFailed = false,
}) => PerformanceSummariesFrame.data(
  deliverySequence: deliverySequence,
  event: PerformanceSummariesEvent.change(
    stamp: profileStamp(origin, revision),
    baseRevision: baseRevision,
    value: PerformanceSummariesChange(
      header: PerformanceSummariesHeader(
        revision: revision,
        updatedAt: updatedAt,
        statisticsPending: statisticsPending,
        statisticsGap: statisticsGap,
        readFailed: readFailed,
        reference: reference,
      ),
      baseCollectionRevision: baseCollectionRevision,
      collection: collection,
      upserted: const <ProductEntityRef>[],
      removedEntries: const <int>[],
    ),
  ),
);

/// Native `ResyncRequired` control frame for one summaries lane generation.
PerformanceSummariesFrame summariesResyncRequired({
  required String feedId,
  required ProductReadOrigin origin,
  ProductResyncReason reason = ProductResyncReason.sourceLagged,
}) => PerformanceSummariesFrame.resyncRequired(
  identity: profileIdentity(
    feedId,
    origin,
    ProductResource.performanceSummaries,
  ),
  reason: reason,
);

/// Native owner replacement: the same lane needs a new subscription.
PerformanceSummariesFrame summariesOwnerReplaced({
  required String feedId,
  required ProductReadOrigin origin,
}) => PerformanceSummariesFrame.closed(
  identity: profileIdentity(
    feedId,
    origin,
    ProductResource.performanceSummaries,
  ),
  reason: ProductFeedCloseReason.ownerReplaced,
);

/// Native typed failure of one summaries lane.
PerformanceSummariesFrame summariesFeedFailure({
  required String feedId,
  required ProductReadOrigin origin,
  required StudioFailure error,
}) => PerformanceSummariesFrame.failure(
  identity: profileIdentity(
    feedId,
    origin,
    ProductResource.performanceSummaries,
  ),
  error: error,
);

PerformanceHistoryFrame historyBaseline({
  required String feedId,
  required ProductReadOrigin origin,
  required int revision,
  required PerformanceHistoryReadRef reference,
  required ProductCollectionRef collection,
  int deliverySequence = 1,
  int updatedAt = 1769904000,
  bool statisticsPending = false,
  bool statisticsGap = false,
  bool readFailed = false,
}) => PerformanceHistoryFrame.data(
  deliverySequence: deliverySequence,
  event: PerformanceHistoryEvent.baseline(
    identity: profileIdentity(
      feedId,
      origin,
      ProductResource.performanceHistory,
    ),
    stamp: profileStamp(origin, revision),
    value: PerformanceHistoryBaseline(
      header: PerformanceHistoryHeader(
        revision: revision,
        updatedAt: updatedAt,
        statisticsPending: statisticsPending,
        statisticsGap: statisticsGap,
        readFailed: readFailed,
        reference: reference,
      ),
      collection: collection,
    ),
  ),
);

PerformanceHistoryFrame historyChange({
  required ProductReadOrigin origin,
  required int deliverySequence,
  required int revision,
  required int baseRevision,
  required PerformanceHistoryReadRef reference,
  required ProductCollectionRef collection,
  required int baseCollectionRevision,
  int updatedAt = 1769904000,
  bool statisticsPending = false,
  bool statisticsGap = false,
  bool readFailed = false,
}) => PerformanceHistoryFrame.data(
  deliverySequence: deliverySequence,
  event: PerformanceHistoryEvent.change(
    stamp: profileStamp(origin, revision),
    baseRevision: baseRevision,
    value: PerformanceHistoryChange(
      header: PerformanceHistoryHeader(
        revision: revision,
        updatedAt: updatedAt,
        statisticsPending: statisticsPending,
        statisticsGap: statisticsGap,
        readFailed: readFailed,
        reference: reference,
      ),
      baseCollectionRevision: baseCollectionRevision,
      collection: collection,
      upserted: const <ProductEntityRef>[],
      removedEntries: const <int>[],
    ),
  ),
);
