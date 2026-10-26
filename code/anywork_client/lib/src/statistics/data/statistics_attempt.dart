import 'dart:async';

import '../../../resources_ports.dart';
import '../domain/statistics_state.dart';
import '../domain/statistics_values.dart';
import 'statistics_frames.dart';
import 'statistics_material.dart';
import 'statistics_materializer.dart';
import 'statistics_port.dart';
import 'statistics_read_fields.dart';
import 'statistics_reader.dart';

/// Bounded automatic lane resubscriptions inside one attempt. It counts native
/// resync/owner-replacement recoveries; it is not a timer or a retry policy.
const _maximumLaneResyncs = 3;

/// One concrete visible attempt. Both statistics feeds and every fixed read
/// scope belong to this attempt's own [ResourceLifetime], so a new attempt never
/// stacks a second feed on unresolved resources.
///
/// A frame is captured before any await: its identity, stamp, continuous
/// projection prefix and original collection are validated first, then the
/// material is read to completion. A single side confirms its own feed after its
/// own complete material exists, so one side never waits for the other's
/// delivery window. Only a pair from the same authority origin and business
/// revision becomes a published snapshot; otherwise the last complete snapshot
/// stays visible and nothing is published from one side.
final class StatisticsAttempt {
  StatisticsAttempt({
    required this.budget,
    required this.port,
    required this.owner,
    required this.lastGood,
    required this.publish,
    required this.onFailure,
  }) : lifetime = ResourceLifetime(budget) {
    materializer = StatisticsMaterializer(StatisticsReader(port, lifetime));
    unawaited(
      _paired.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  final ResourceBudget budget;
  final StatisticsPort port;
  final String owner;

  /// The repository's current complete snapshot; never a per-side buffer.
  final StatisticsSnapshot? Function() lastGood;
  final void Function(StatisticsSnapshot snapshot) publish;
  final void Function(StudioFailure failure) onFailure;

  final ResourceLifetime lifetime;
  late final StatisticsMaterializer materializer;

  ProductFeedOwner<PerformanceSummariesFrame>? _summariesFeed;
  ProductFeedOwner<PerformanceHistoryFrame>? _historyFeed;

  /// Each lane opens concrete feeds in generations. A retired lane's late
  /// frames only report their own delivery identity; they never publish
  /// material, bind an identity or acknowledge into the replacement lane.
  int _summariesGeneration = 0;
  int _historyGeneration = 0;
  Future<void>? _summariesRestart;
  Future<void>? _historyRestart;
  int _summariesResyncs = 0;
  int _historyResyncs = 0;

  ProductProjectionStamp? _summariesStamp;
  ProductCollectionRef? _summariesCollection;
  StatisticsSummariesMaterial? _summaries;
  PinnedReadOwner<PerformanceSummariesReadConnection>? _summariesRead;
  ({ProductReadOrigin origin, PerformanceSummariesReadRef reference})?
  _summariesReadTarget;

  ProductProjectionStamp? _historyStamp;
  ProductCollectionRef? _historyCollection;
  StatisticsHistoryMaterial? _history;
  PinnedReadOwner<PerformanceHistoryReadConnection>? _historyRead;
  ({ProductReadOrigin origin, PerformanceHistoryReadRef reference})?
  _historyReadTarget;

  final Completer<void> _paired = Completer<void>();
  StudioFailure? _failure;
  bool _retired = false;
  Future<CloseReport>? _retirement;

  /// Completes on the first paired publication of this attempt, or with the
  /// typed failure/replacement that ended it.
  Future<void> get paired => _paired.future;
  bool get retired => _retired;
  StudioFailure? get failure => _failure;

  /// Opens both feeds. Identities are bound by their own first frames, before
  /// any material read is admitted.
  void start() {
    lifetime.admit();
    _summariesFeed = _openSummaries(++_summariesGeneration);
    try {
      _historyFeed = _openHistory(++_historyGeneration);
    } catch (_) {
      _summariesFeed!.requestClose();
      unawaited(_summariesFeed!.cleanup(retry: false));
      rethrow;
    }
  }

  ProductFeedOwner<PerformanceSummariesFrame> _openSummaries(int generation) =>
      ProductFeedOwner(
        lifetime: lifetime,
        owner: '$owner:summaries:$generation',
        open: port.openPerformanceSummaries,
        sequence: (frame) =>
            frame is PerformanceSummariesData ? frame.deliverySequence : null,
        apply: (frame) => _applySummaries(generation, frame),
        failed: (failure) {
          if (generation != _summariesGeneration) return;
          fail(failure);
        },
      );

  ProductFeedOwner<PerformanceHistoryFrame> _openHistory(int generation) =>
      ProductFeedOwner(
        lifetime: lifetime,
        owner: '$owner:history:$generation',
        open: port.openPerformanceHistory,
        sequence: (frame) =>
            frame is PerformanceHistoryData ? frame.deliverySequence : null,
        apply: (frame) => _applyHistory(generation, frame),
        failed: (failure) {
          if (generation != _historyGeneration) return;
          fail(failure);
        },
      );

  /// Retires the original attempt. Cleanup is started here but never awaited
  /// from a resource's own consumer; the repository joins it separately.
  void requestRetire() {
    if (_retired) return;
    _retired = true;
    if (!_paired.isCompleted) _paired.completeError(statisticsSuperseded);
    _summariesFeed?.requestClose();
    _historyFeed?.requestClose();
    supervise();
  }

  /// Starts (once) the real join of every registered feed and read scope.
  void supervise() {
    if (_retirement != null) return;
    final done = Completer<CloseReport>();
    _retirement = done.future;
    unawaited(
      Future<CloseReport>.sync(() => lifetime.close()).then(
        (report) {
          if (!done.isCompleted) done.complete(report);
        },
        onError: (Object error, StackTrace stack) {
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          if (!done.isCompleted) done.complete(lifetime.snapshotReport());
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<CloseReport> get retirement {
    supervise();
    return _retirement!;
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) {
    requestRetire();
    return lifetime.close(deadline: deadline, retry: retry);
  }

  /// A retained attempt is reusable only after every lane it really opened has
  /// released; a lane that never opened owns nothing. The attempt's close report
  /// stays the authoritative gate for registered-but-unnamed resources.
  bool get clean {
    final summaries = _summariesFeed;
    final history = _historyFeed;
    return (summaries == null || summaries.released) &&
        (history == null || history.released);
  }

  void fail(StudioFailure failure) {
    if (_retired || lifetime.sealed) return;
    _failure ??= failure;
    if (!_paired.isCompleted) _paired.completeError(_failure!);
    onFailure(_failure!);
    requestRetire();
  }

  Future<int?> _applySummaries(
    int generation,
    PerformanceSummariesFrame frame,
  ) async {
    final delivery = frame is PerformanceSummariesData
        ? frame.deliverySequence
        : null;
    // A retired lane or an older generation keeps its own delivery identity and
    // never writes the replacement lane's state. Its own feed is already
    // closing, so this value is not acknowledged.
    if (_retired || lifetime.sealed || generation != _summariesGeneration)
      return delivery;
    try {
      switch (frame) {
        case PerformanceSummariesData(:final event):
          final material = await _consumeSummaries(event);
          if (_retired || lifetime.sealed || generation != _summariesGeneration)
            return delivery;
          _summaries = material;
          _pair();
        case PerformanceSummariesResyncRequired(:final identity):
          _summariesControl(identity);
          _resyncSummariesLane();
        case PerformanceSummariesFeedFailure(:final identity, :final error):
          _summariesControl(identity);
          fail(error);
        case PerformanceSummariesClosed(:final identity, :final reason):
          _summariesControl(identity);
          if (reason == ProductFeedCloseReason.ownerReplaced) {
            _resyncSummariesLane();
          } else {
            fail(_closedFailure(reason, 'summaries'));
          }
      }
      return delivery;
    } catch (error) {
      if (!_retired && !lifetime.sealed) fail(statisticsFailure(error));
      return delivery;
    }
  }

  Future<int?> _applyHistory(
    int generation,
    PerformanceHistoryFrame frame,
  ) async {
    final delivery = frame is PerformanceHistoryData
        ? frame.deliverySequence
        : null;
    if (_retired || lifetime.sealed || generation != _historyGeneration)
      return delivery;
    try {
      switch (frame) {
        case PerformanceHistoryData(:final event):
          final material = await _consumeHistory(event);
          if (_retired || lifetime.sealed || generation != _historyGeneration)
            return delivery;
          _history = material;
          _pair();
        case PerformanceHistoryResyncRequired(:final identity):
          _historyControl(identity);
          _resyncHistoryLane();
        case PerformanceHistoryFeedFailure(:final identity, :final error):
          _historyControl(identity);
          fail(error);
        case PerformanceHistoryClosed(:final identity, :final reason):
          _historyControl(identity);
          if (reason == ProductFeedCloseReason.ownerReplaced) {
            _resyncHistoryLane();
          } else {
            fail(_closedFailure(reason, 'history'));
          }
      }
      return delivery;
    } catch (error) {
      if (!_retired && !lifetime.sealed) fail(statisticsFailure(error));
      return delivery;
    }
  }

  void _summariesControl(ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.performanceSummaries)
      throw statisticsProtocol(
        'A statistics control frame belongs to another source.',
      );
    final stamp = _summariesStamp;
    if (stamp != null &&
        (identity.ownerEpoch != stamp.ownerEpoch ||
            identity.incarnation != stamp.incarnation))
      throw statisticsProtocol(
        'A statistics control frame changed its source identity.',
      );
    _summariesFeed!.bindIdentity(identity);
  }

  void _historyControl(ProductFeedIdentity identity) {
    if (identity.resource != ProductResource.performanceHistory)
      throw statisticsProtocol(
        'A statistics control frame belongs to another source.',
      );
    final stamp = _historyStamp;
    if (stamp != null &&
        (identity.ownerEpoch != stamp.ownerEpoch ||
            identity.incarnation != stamp.incarnation))
      throw statisticsProtocol(
        'A statistics control frame changed its source identity.',
      );
    _historyFeed!.bindIdentity(identity);
  }

  Future<StatisticsSummariesMaterial> _consumeSummaries(
    PerformanceSummariesEvent event,
  ) async {
    final ProductProjectionStamp stamp;
    final PerformanceSummariesHeader header;
    final ProductCollectionRef collection;
    switch (event) {
      case PerformanceSummariesBaselineEvent(
        :final identity,
        stamp: final baselineStamp,
        :final value,
      ):
        if (_summariesStamp != null)
          throw statisticsProtocol(
            'A statistics baseline repeated its original projection.',
          );
        if (identity.resource != ProductResource.performanceSummaries ||
            identity.ownerEpoch != baselineStamp.ownerEpoch ||
            identity.incarnation != baselineStamp.incarnation)
          throw statisticsProtocol(
            'A statistics baseline has another source identity.',
          );
        _summariesFeed!.bindIdentity(identity);
        stamp = baselineStamp;
        header = value.header;
        collection = _collection(value.collection, value.header.revision);
      case PerformanceSummariesChangeEvent(
        stamp: final changeStamp,
        :final baseRevision,
        :final value,
      ):
        final previous = _summariesStamp;
        if (previous == null ||
            changeStamp.origin != previous.origin ||
            baseRevision != previous.revision ||
            changeStamp.revision <= baseRevision)
          throw statisticsProtocol(
            'A statistics projection has a revision gap.',
          );
        if (value.baseCollectionRevision != _summariesCollection?.revision)
          throw statisticsProtocol(
            'A statistics collection has a revision gap.',
          );
        stamp = changeStamp;
        header = value.header;
        collection = _collection(value.collection, value.header.revision);
    }
    _summariesStamp = stamp;
    _summariesCollection = collection;
    return _materializeSummaries(stamp.origin, header, collection);
  }

  Future<StatisticsHistoryMaterial> _consumeHistory(
    PerformanceHistoryEvent event,
  ) async {
    final ProductProjectionStamp stamp;
    final PerformanceHistoryHeader header;
    final ProductCollectionRef collection;
    switch (event) {
      case PerformanceHistoryBaselineEvent(
        :final identity,
        stamp: final baselineStamp,
        :final value,
      ):
        if (_historyStamp != null)
          throw statisticsProtocol(
            'A statistics baseline repeated its original projection.',
          );
        if (identity.resource != ProductResource.performanceHistory ||
            identity.ownerEpoch != baselineStamp.ownerEpoch ||
            identity.incarnation != baselineStamp.incarnation)
          throw statisticsProtocol(
            'A statistics baseline has another source identity.',
          );
        _historyFeed!.bindIdentity(identity);
        stamp = baselineStamp;
        header = value.header;
        collection = _collection(value.collection, value.header.revision);
      case PerformanceHistoryChangeEvent(
        stamp: final changeStamp,
        :final baseRevision,
        :final value,
      ):
        final previous = _historyStamp;
        if (previous == null ||
            changeStamp.origin != previous.origin ||
            baseRevision != previous.revision ||
            changeStamp.revision <= baseRevision)
          throw statisticsProtocol(
            'A statistics projection has a revision gap.',
          );
        if (value.baseCollectionRevision != _historyCollection?.revision)
          throw statisticsProtocol(
            'A statistics collection has a revision gap.',
          );
        stamp = changeStamp;
        header = value.header;
        collection = _collection(value.collection, value.header.revision);
    }
    _historyStamp = stamp;
    _historyCollection = collection;
    return _materializeHistory(stamp.origin, header, collection);
  }

  /// The captured collection is part of the projection: without it the frame is
  /// not a complete material and must not be confirmed.
  ProductCollectionRef _collection(
    ProductCollectionRef? collection,
    int headerRevision,
  ) {
    if (collection == null || collection.total < 0 || headerRevision < 0)
      throw statisticsProtocol(
        'A statistics frame carries no complete material collection.',
      );
    return collection;
  }

  Future<StatisticsSummariesMaterial> _materializeSummaries(
    ProductReadOrigin origin,
    PerformanceSummariesHeader header,
    ProductCollectionRef collection,
  ) async {
    final existing = _summaries;
    if (existing != null &&
        existing.origin == origin &&
        existing.reference == header.reference) {
      if (existing.values.length != collection.total)
        throw statisticsProtocol(
          'A summary material changed its length without a new reference.',
        );
      return StatisticsSummariesMaterial(
        origin: origin,
        reference: header.reference,
        collection: collection,
        header: header,
        values: existing.values,
        rows: existing.rows,
      );
    }
    final last = lastGood();
    if (last != null &&
        last.origin == origin &&
        last.summariesReference == header.reference) {
      if (last.summaries.length != collection.total)
        throw statisticsProtocol(
          'A summary material changed its length without a new reference.',
        );
      return StatisticsSummariesMaterial(
        origin: origin,
        reference: header.reference,
        collection: collection,
        header: header,
        values: last.summaries,
        rows: null,
      );
    }
    return _summariesPin(origin, header.reference).use(
      (scope) => materializer.summaries(
        scope: scope,
        origin: origin,
        header: header,
        collection: collection,
        previous: existing != null && existing.origin == origin
            ? existing
            : null,
      ),
    );
  }

  Future<StatisticsHistoryMaterial> _materializeHistory(
    ProductReadOrigin origin,
    PerformanceHistoryHeader header,
    ProductCollectionRef collection,
  ) async {
    final existing = _history;
    if (existing != null &&
        existing.origin == origin &&
        existing.reference == header.reference) {
      if (existing.values.length != collection.total)
        throw statisticsProtocol(
          'A history material changed its length without a new reference.',
        );
      return StatisticsHistoryMaterial(
        origin: origin,
        reference: header.reference,
        collection: collection,
        header: header,
        values: existing.values,
        rows: existing.rows,
      );
    }
    final last = lastGood();
    if (last != null &&
        last.origin == origin &&
        last.historyReference == header.reference) {
      if (last.history.length != collection.total)
        throw statisticsProtocol(
          'A history material changed its length without a new reference.',
        );
      return StatisticsHistoryMaterial(
        origin: origin,
        reference: header.reference,
        collection: collection,
        header: header,
        values: last.history,
        rows: null,
      );
    }
    return _historyPin(origin, header.reference).use(
      (scope) => materializer.history(
        scope: scope,
        origin: origin,
        header: header,
        collection: collection,
        previous: existing != null && existing.origin == origin
            ? existing
            : null,
      ),
    );
  }

  PinnedReadOwner<PerformanceSummariesReadConnection> _summariesPin(
    ProductReadOrigin origin,
    PerformanceSummariesReadRef reference,
  ) {
    lifetime.admit();
    final target = (origin: origin, reference: reference);
    final current = _summariesRead;
    if (current != null && _summariesReadTarget == target && current.accepting)
      return current;
    current?.retire();
    _summariesReadTarget = target;
    return _summariesRead = PinnedReadOwner<PerformanceSummariesReadConnection>(
      lifetime: lifetime,
      owner: '$owner:summaries-read',
      open: () => port.openPerformanceSummariesRead(reference, origin: origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
  }

  PinnedReadOwner<PerformanceHistoryReadConnection> _historyPin(
    ProductReadOrigin origin,
    PerformanceHistoryReadRef reference,
  ) {
    lifetime.admit();
    final target = (origin: origin, reference: reference);
    final current = _historyRead;
    if (current != null && _historyReadTarget == target && current.accepting)
      return current;
    current?.retire();
    _historyReadTarget = target;
    return _historyRead = PinnedReadOwner<PerformanceHistoryReadConnection>(
      lifetime: lifetime,
      owner: '$owner:history-read',
      open: () => port.openPerformanceHistoryRead(reference, origin: origin),
      request: (scope) => scope.requestClose(),
      closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
  }

  /// Publishes only a compatible pair. Delivery sequences, projection stamps
  /// and read reference revisions stay independent facts of each feed.
  void _pair() {
    if (_retired || lifetime.sealed) return;
    final summaries = _summaries;
    final history = _history;
    if (summaries == null || history == null) return;
    if (summaries.origin != history.origin) return;
    final left = summaries.header;
    final right = history.header;
    if (left.revision != right.revision) return;
    if (left.updatedAt != right.updatedAt ||
        left.statisticsPending != right.statisticsPending ||
        left.statisticsGap != right.statisticsGap ||
        left.readFailed != right.readFailed) {
      fail(
        statisticsProtocol(
          'The statistics feeds disagree on one published revision.',
        ),
      );
      return;
    }
    final previous = lastGood();
    if (previous != null &&
        previous.origin == summaries.origin &&
        previous.revision > left.revision) {
      fail(statisticsProtocol('The statistics publication moved backwards.'));
      return;
    }
    final snapshot = StatisticsSnapshot(
      origin: summaries.origin,
      revision: left.revision,
      updatedAt: left.updatedAt,
      statisticsPending: left.statisticsPending,
      statisticsGap: left.statisticsGap,
      readFailed: left.readFailed,
      summariesReference: summaries.reference,
      historyReference: history.reference,
      summaries: summaries.values,
      history: history.values,
    );
    // The repository drops an unchanged snapshot and keeps only the ready
    // transition, so a reused material never looks like a new publication.
    publish(snapshot);
    // A compatible pair proves both lanes caught up; bounded resubscription
    // counters start again only when neither lane is mid-restart.
    if (_summariesRestart == null && _historyRestart == null) {
      _summariesResyncs = 0;
      _historyResyncs = 0;
    }
    if (!_paired.isCompleted) _paired.complete();
  }

  /// Native active resync (`ResyncRequired`, owner replacement) is a normal
  /// path, not an attempt failure: only the affected lane is retired and really
  /// joined, then reopened inside this same attempt. The other lane, the lanes'
  /// own delivery windows and the last complete snapshot stay untouched.
  void _resyncSummariesLane() {
    if (_retired || lifetime.sealed) return;
    if (_summariesRestart != null) return;
    final feed = _summariesFeed;
    if (feed == null || _summariesResyncs >= _maximumLaneResyncs) {
      fail(statisticsResyncExhausted('summaries'));
      return;
    }
    _summariesResyncs++;
    final done = Completer<void>();
    _summariesRestart = done.future;
    // Invalidate the retiring generation before it is joined: any late frame of
    // that lane reports only its own delivery identity from now on.
    _summariesGeneration++;
    // The replacement lane starts from its own baseline, never from the retired
    // lane's projection prefix.
    _summariesStamp = null;
    _summariesCollection = null;
    feed.requestClose();
    unawaited(
      Future<void>.sync(
        () => lifetime.run('$owner:summaries-resync', () async {
          await feed.cleanup(retry: false);
          if (lifetime.sealed || _retired) return;
          if (!feed.released)
            throw statisticsUnresolvedCleanup(
              'The original summaries feed has unresolved cleanup.',
            );
          _summariesFeed = _openSummaries(++_summariesGeneration);
        }),
      ).then(
        (_) {
          _summariesRestart = null;
          if (!done.isCompleted) done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _summariesRestart = null;
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          if (!lifetime.sealed && !_retired) fail(statisticsFailure(error));
          if (!done.isCompleted) done.completeError(statisticsFailure(error));
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  void _resyncHistoryLane() {
    if (_retired || lifetime.sealed) return;
    if (_historyRestart != null) return;
    final feed = _historyFeed;
    if (feed == null || _historyResyncs >= _maximumLaneResyncs) {
      fail(statisticsResyncExhausted('history'));
      return;
    }
    _historyResyncs++;
    final done = Completer<void>();
    _historyRestart = done.future;
    _historyGeneration++;
    _historyStamp = null;
    _historyCollection = null;
    feed.requestClose();
    unawaited(
      Future<void>.sync(
        () => lifetime.run('$owner:history-resync', () async {
          await feed.cleanup(retry: false);
          if (lifetime.sealed || _retired) return;
          if (!feed.released)
            throw statisticsUnresolvedCleanup(
              'The original history feed has unresolved cleanup.',
            );
          _historyFeed = _openHistory(++_historyGeneration);
        }),
      ).then(
        (_) {
          _historyRestart = null;
          if (!done.isCompleted) done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _historyRestart = null;
          lifetime.lastCause = error;
          lifetime.lastStack = stack;
          if (!lifetime.sealed && !_retired) fail(statisticsFailure(error));
          if (!done.isCompleted) done.completeError(statisticsFailure(error));
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  StudioFailure _closedFailure(ProductFeedCloseReason reason, String side) =>
      StudioFailure(
        code: reason == ProductFeedCloseReason.runtimeStopped
            ? StudioFailureCode.runtimeStopped
            : StudioFailureCode.unavailable,
        message: reason == ProductFeedCloseReason.ownerReplaced
            ? 'The statistics $side source was replaced.'
            : 'The statistics $side feed closed.',
        retryable: true,
        correlationId: 'statistics',
      );
}
