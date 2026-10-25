import 'dart:async';
import 'dart:collection';

import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/statistics_ports.dart';

/// Barrier that lets a behavior test release a specific operation without sleeps.
final class StatisticsTestGate {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  Future<void> wait() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }
}

final class StatisticsPublicationFixture {
  StatisticsPublicationFixture({
    required this.identity,
    required Iterable<StatisticsSummaryPageItem> summaries,
    required Iterable<StatisticsSample> history,
    Map<int, Iterable<StatisticsEffortSummary>> efforts = const {},
    this.summaryGate,
    this.historyGate,
    this.effortGate,
    this.acknowledgementGate,
    this.failHistoryOffset,
  }) : summaries = List.unmodifiable(summaries),
       history = List.unmodifiable(history),
       efforts = Map.unmodifiable({
         for (final entry in efforts.entries)
           entry.key: List<StatisticsEffortSummary>.unmodifiable(entry.value),
       });

  final StatisticsFeedIdentity identity;
  final List<StatisticsSummaryPageItem> summaries;
  final List<StatisticsSample> history;
  final Map<int, List<StatisticsEffortSummary>> efforts;
  final StatisticsTestGate? summaryGate;
  final StatisticsTestGate? historyGate;
  final StatisticsTestGate? effortGate;
  final StatisticsTestGate? acknowledgementGate;
  final int? failHistoryOffset;
}

final class StatisticsConnectionPlan {
  StatisticsConnectionPlan({
    required this.initial,
    this.openGate,
    this.failOpen = false,
    this.onOpen,
    this.closeFailures = 0,
    this.closeAfterBaseline = false,
  });

  final StatisticsPublicationFixture initial;
  final StatisticsTestGate? openGate;
  final bool failOpen;
  final void Function()? onOpen;
  final bool closeAfterBaseline;
  int closeFailures;
}

final class ControlledStatisticsFeedPort implements StatisticsFeedPort {
  ControlledStatisticsFeedPort(Iterable<StatisticsConnectionPlan> plans)
    : _plans = Queue.of(plans);

  final Queue<StatisticsConnectionPlan> _plans;
  final List<ControlledStatisticsConnection> connections = [];
  final Map<int, Completer<void>> _openWaiters = {};
  final Map<int, Completer<ControlledStatisticsConnection>> _connectionWaiters =
      {};
  int openCalls = 0;

  @override
  Future<StatisticsFeedConnection> open() async {
    final ordinal = ++openCalls;
    _openWaiters.remove(ordinal)?.complete();
    if (_plans.isEmpty) {
      throw StateError('No statistics connection plan for open #$ordinal');
    }
    final plan = _plans.removeFirst();
    plan.onOpen?.call();
    final gate = plan.openGate;
    if (gate != null) await gate.wait();
    if (plan.failOpen) {
      throw StateError('Injected statistics open failure');
    }
    final connection = ControlledStatisticsConnection(plan);
    connections.add(connection);
    for (final entry in _connectionWaiters.entries.toList()) {
      if (entry.key <= connections.length) {
        entry.value.complete(connections[entry.key - 1]);
        _connectionWaiters.remove(entry.key);
      }
    }
    return connection;
  }

  Future<void> waitForOpenCall(int ordinal) {
    if (openCalls >= ordinal) return Future<void>.value();
    return (_openWaiters[ordinal] ??= Completer<void>()).future;
  }

  Future<ControlledStatisticsConnection> waitForConnection(int ordinal) {
    if (connections.length >= ordinal) {
      return Future.value(connections[ordinal - 1]);
    }
    return (_connectionWaiters[ordinal] ??=
            Completer<ControlledStatisticsConnection>())
        .future;
  }
}

final class ControlledStatisticsConnection implements StatisticsFeedConnection {
  ControlledStatisticsConnection(StatisticsConnectionPlan plan) : _plan = plan {
    _enqueue(plan.initial);
    if (plan.closeAfterBaseline) _finishUnexpectedly();
  }

  final StatisticsConnectionPlan _plan;
  final StreamController<StatisticsFeedEvent> _events =
      StreamController<StatisticsFeedEvent>();
  final Map<int, StatisticsPublicationFixture> _unacknowledged = {};
  final Set<ControlledStatisticsScope> _scopes = {};
  final List<int> acknowledgedSequences = [];
  final List<int> summaryOffsets = [];
  final List<int> historyOffsets = [];
  final List<(int, int)> effortReads = [];
  final Completer<void> closed = Completer<void>();
  bool closeRequested = false;
  bool _baselineEmitted = false;
  int closeCalls = 0;
  int scopeOpenCalls = 0;

  bool get isClosed => closed.isCompleted;

  void allowCloseToSucceed() => _plan.closeFailures = 0;

  void emit(StatisticsPublicationFixture publication) {
    if (closeRequested) {
      throw StateError('Cannot publish on a closing test feed');
    }
    _enqueue(publication);
  }

  void finishUnexpectedly() => _finishUnexpectedly();

  void _finishUnexpectedly() {
    if (_events.isClosed) return;
    _events.add(const StatisticsFeedClosed());
    unawaited(_events.close());
  }

  void _enqueue(StatisticsPublicationFixture publication) {
    final sequence = publication.identity.deliverySequence;
    if (_unacknowledged.containsKey(sequence)) {
      throw StateError('Duplicate test delivery sequence $sequence');
    }
    _unacknowledged[sequence] = publication;
    final event = _baselineEmitted
        ? StatisticsFeedData(publication.identity)
        : StatisticsFeedBaseline(publication.identity);
    _baselineEmitted = true;
    _events.add(event);
  }

  @override
  Stream<StatisticsFeedEvent> events() => _events.stream;

  @override
  Future<StatisticsReadScope> openScope(
    StatisticsFeedIdentity publication,
  ) async {
    final fixture = _unacknowledged[publication.deliverySequence];
    if (closeRequested ||
        fixture == null ||
        fixture.identity.ownerEpoch != publication.ownerEpoch ||
        fixture.identity.feedId != publication.feedId ||
        fixture.identity.publicationRevision !=
            publication.publicationRevision) {
      throw StateError(
        'Test scope identity did not refer to a pending delivery',
      );
    }
    scopeOpenCalls++;
    final scope = ControlledStatisticsScope(this, fixture);
    _scopes.add(scope);
    return scope;
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    final fixture = _unacknowledged[deliverySequence];
    if (deliverySequence <=
        (acknowledgedSequences.isEmpty ? 0 : acknowledgedSequences.last)) {
      return;
    }
    if (closeRequested || fixture == null) {
      throw StateError('Test ACK did not refer to an open delivery');
    }
    final gate = fixture.acknowledgementGate;
    if (gate != null) await gate.wait();
    if (deliverySequence != acknowledgedSequences.length + 1) {
      throw StateError('Test ACK was not a contiguous prefix');
    }
    acknowledgedSequences.add(deliverySequence);
    _unacknowledged.remove(deliverySequence);
  }

  @override
  void requestClose() {
    if (closeRequested) return;
    closeRequested = true;
    _finishUnexpectedly();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (_plan.closeFailures > 0) {
      _plan.closeFailures--;
      throw StateError('Injected statistics close failure');
    }
    while (_scopes.isNotEmpty) {
      await _scopes.first.closed.future;
    }
    if (!closed.isCompleted) closed.complete();
  }
}

final class ControlledStatisticsScope implements StatisticsReadScope {
  ControlledStatisticsScope(this._connection, this._publication)
    : scopeId = 'test-scope-${++_nextScopeId}';

  static int _nextScopeId = 0;
  final ControlledStatisticsConnection _connection;
  final StatisticsPublicationFixture _publication;
  final Completer<void> closed = Completer<void>();
  bool _closeRequested = false;

  @override
  String get ownerEpoch => _publication.identity.ownerEpoch;
  @override
  String get feedId => _publication.identity.feedId;
  @override
  final String scopeId;
  @override
  int get publicationRevision => _publication.identity.publicationRevision;

  @override
  Future<StatisticsPage<StatisticsSummaryPageItem>> readSummaries(
    int offset,
    int limit,
  ) async {
    _ensureOpen();
    _connection.summaryOffsets.add(offset);
    final gate = _publication.summaryGate;
    if (gate != null) await gate.wait();
    return _page(
      _publication.summaries,
      offset,
      limit,
      materialRevision: _publication.identity.summariesRevision,
    );
  }

  @override
  Future<StatisticsPage<StatisticsSample>> readHistory(
    int offset,
    int limit,
  ) async {
    _ensureOpen();
    _connection.historyOffsets.add(offset);
    final gate = _publication.historyGate;
    if (gate != null) await gate.wait();
    if (_publication.failHistoryOffset == offset) {
      throw StateError('Injected statistics history page failure');
    }
    return _page(
      _publication.history,
      offset,
      limit,
      materialRevision: _publication.identity.historyRevision,
    );
  }

  @override
  Future<StatisticsPage<StatisticsEffortSummary>> readEfforts(
    int summaryIndex,
    int offset,
    int limit,
  ) async {
    _ensureOpen();
    _connection.effortReads.add((summaryIndex, offset));
    final gate = _publication.effortGate;
    if (gate != null) await gate.wait();
    final values = _publication.efforts[summaryIndex] ?? const [];
    return _page(
      values,
      offset,
      limit,
      materialRevision: _publication.identity.summariesRevision,
      summaryIndex: summaryIndex,
    );
  }

  StatisticsPage<T> _page<T>(
    List<T> values,
    int offset,
    int limit, {
    required int materialRevision,
    int? summaryIndex,
  }) {
    if (offset < 0 || limit < 1 || limit > 128 || offset > values.length) {
      throw RangeError('Invalid controlled statistics page request');
    }
    final end = (offset + limit).clamp(0, values.length).toInt();
    return StatisticsPage(
      ownerEpoch: ownerEpoch,
      feedId: feedId,
      scopeId: scopeId,
      publicationRevision: publicationRevision,
      materialRevision: materialRevision,
      offset: offset,
      totalCount: values.length,
      nextOffset: end < values.length ? end : null,
      sourceBytes: 0,
      summaryIndex: summaryIndex,
      items: values.sublist(offset, end),
    );
  }

  void _ensureOpen() {
    if (_closeRequested || _connection.closeRequested) {
      throw StateError('Controlled statistics scope is closing');
    }
  }

  @override
  Future<void> close() async {
    if (_closeRequested) return;
    _closeRequested = true;
    _connection._scopes.remove(this);
    if (!closed.isCompleted) closed.complete();
  }
}
