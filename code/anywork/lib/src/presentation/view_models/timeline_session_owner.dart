import 'dart:async';

import 'package:anywork_client/studio_client.dart';

/// Immutable list structure plus a read-only query for its bounded row mirror.
/// Text and saved/body updates notify their row; they do not publish another
/// list structure. View identity is independent from the history-window epoch.
final class TimelineSessionWindow {
  factory TimelineSessionWindow({
    required String threadId,
    required List<TimelineRow> rows,
    required StudioTurnView? turn,
    required ThreadHistoryWindow history,
    required bool isLoadingOlder,
    required bool isLoadingNewer,
    String? viewId,
  }) {
    final query = _TimelineRowsStore('timeline-static:$threadId')
      ..replace(rows, history);
    return TimelineSessionWindow._(
      threadId: threadId,
      rowQuery: query,
      orderedIds: query.orderedIds,
      turn: turn,
      history: _pageHistory(history),
      isLoadingOlder: isLoadingOlder,
      isLoadingNewer: isLoadingNewer,
      viewId: viewId,
    );
  }

  const TimelineSessionWindow._({
    required this.threadId,
    required this.rowQuery,
    required this.orderedIds,
    required this.turn,
    required this.history,
    required this.isLoadingOlder,
    required this.isLoadingNewer,
    this.viewId,
  });

  final String threadId;
  final String? viewId;
  final TimelineRowsQuery rowQuery;
  final List<String> orderedIds;

  /// Synchronous viewport/diagnostic query. The list observer never watches it.
  List<TimelineRow> get rows => rowQuery.rows;
  final StudioTurnView? turn;
  final ThreadHistoryWindow history;
  final bool isLoadingOlder;
  final bool isLoadingNewer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineSessionWindow &&
          threadId == other.threadId &&
          viewId == other.viewId &&
          _sameIds(orderedIds, other.orderedIds) &&
          turn == other.turn &&
          history == other.history &&
          isLoadingOlder == other.isLoadingOlder &&
          isLoadingNewer == other.isLoadingNewer;

  @override
  int get hashCode => Object.hash(
    threadId,
    viewId,
    Object.hashAll(orderedIds),
    turn,
    history,
    isLoadingOlder,
    isLoadingNewer,
  );
}

bool _sameIds(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

ThreadHistoryWindow _pageHistory(ThreadHistoryWindow history) =>
    history.copyWith(
      previewedItemIds: const {},
      loadingItemIds: const {},
      itemBodyErrors: const {},
      pendingItemBodyIds: const {},
      unavailableItemIds: const {},
    );

/// Queries expose observation/cancellation without exposing a mirror writer.
abstract interface class TimelineRowsQuery {
  static TimelineRowsQuery snapshot(
    List<TimelineRow> rows, {
    ThreadHistoryWindow body = const ThreadHistoryWindow(),
    ResourceBudget? budget,
  }) =>
      _TimelineRowsStore('timeline-static', budget: budget)
        ..replace(rows, body);
  List<String> get orderedIds;
  List<TimelineRow> get rows;
  ThreadHistoryWindow get bodyHistory;
  TimelineRowQuery? row(String itemId);
}

final class TimelineRowSnapshot {
  const TimelineRowSnapshot({required this.row, required this.body});
  final TimelineRow row;

  /// Only the underlying item IDs belonging to this projected row are retained.
  final ThreadHistoryWindow body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRowSnapshot && row == other.row && body == other.body;

  @override
  int get hashCode => Object.hash(row, body);
}

final class TimelineRowQuery {
  TimelineRowQuery._(TimelineRowSnapshot value, this._budget, this._owner)
    : _source = LatestValue(value);
  final LatestValue<TimelineRowSnapshot?> _source;
  final ResourceBudget _budget;
  final String _owner;
  final Set<_TimelineRowObservation> _observations = {};
  bool _closed = false;
  TimelineRowSnapshot? get value => _source.value;
  LatestWatch<TimelineRowSnapshot?> watchLatest(
    void Function(TimelineRowSnapshot?) listener,
  ) {
    if (_closed) throw StateError('The Timeline row was evicted');
    final permit = _budget.acquire(ResourceKind.observer, owner: _owner);
    try {
      final watched = _source.watchLatest(listener);
      late final _TimelineRowObservation observation;
      observation = _TimelineRowObservation(
        watched.observation,
        permit,
        () => _observations.remove(observation),
      );
      _observations.add(observation);
      return LatestWatch(value: watched.value, observation: observation);
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  void _publish(TimelineRowSnapshot value) {
    if (_source.value != value) _source.publish(value);
  }

  void _retire() {
    if (_closed) return;
    _closed = true;
    _source.publish(null);
    for (final observation in _observations.toList()) {
      observation.cancel();
    }
    _source.close();
  }
}

final class _TimelineRowObservation implements Observation {
  _TimelineRowObservation(this._inner, this._permit, this._onCancel);
  final Observation _inner;
  final ResourcePermit _permit;
  final void Function() _onCancel;
  @override
  bool get isCancelled => _inner.isCancelled;
  @override
  bool get isPaused => _inner.isPaused;
  @override
  void pause() => _inner.pause();
  @override
  void resume() => _inner.resume();
  @override
  void cancel() {
    _inner.cancel();
    _permit.release();
    _onCancel();
  }
}

/// One store per selected lease. No row or observation survives eviction.
final class _TimelineRowsStore implements TimelineRowsQuery {
  _TimelineRowsStore(this._owner, {ResourceBudget? budget})
    : _budget = budget ?? ResourceBudget();
  final ResourceBudget _budget;
  final String _owner;
  final Map<String, TimelineRowQuery> _rowById = {};
  List<TimelineRow> _rows = const [];
  List<String> _orderedIds = const [];
  ThreadHistoryWindow _history = const ThreadHistoryWindow();

  @override
  List<TimelineRow> get rows => _rows;
  @override
  List<String> get orderedIds => _orderedIds;
  @override
  ThreadHistoryWindow get bodyHistory => _history;
  @override
  TimelineRowQuery? row(String itemId) => _rowById[itemId];

  void replace(List<TimelineRow> rows, ThreadHistoryWindow history) {
    final ids = [for (final row in rows) row.id];
    final retained = ids.toSet();
    final removed = _rowById.keys
        .where((id) => !retained.contains(id))
        .toList();
    final updates = <(TimelineRowQuery, TimelineRowSnapshot)>[];
    for (final row in rows) {
      final snapshot = TimelineRowSnapshot(
        row: row,
        body: _rowHistory(row, history),
      );
      final current = _rowById[row.id];
      if (current == null) {
        _rowById[row.id] = TimelineRowQuery._(
          snapshot,
          _budget,
          '$_owner:${row.id}',
        );
      } else if (current.value != snapshot) {
        updates.add((current, snapshot));
      }
    }
    _rows = List.unmodifiable(rows);
    _history = history;
    if (!_sameIds(_orderedIds, ids)) _orderedIds = List.unmodifiable(ids);
    for (final id in removed) {
      _rowById.remove(id)!._retire();
    }
    // All synchronous queries see the complete new window before row listeners
    // run. Each listener can therefore capture a consistent viewport snapshot.
    for (final (query, snapshot) in updates) {
      query._publish(snapshot);
    }
  }

  void clear() {
    final rows = _rowById.values.toList();
    _rowById.clear();
    _rows = const [];
    _orderedIds = const [];
    _history = const ThreadHistoryWindow();
    for (final row in rows) {
      row._retire();
    }
  }
}

ThreadHistoryWindow _rowHistory(TimelineRow row, ThreadHistoryWindow history) {
  final ids = <String>{
    if (row.part case final part?) part.id,
    for (final item in row.toolGroup?.items ?? const <TimelineToolGroupItem>[])
      item.id,
    for (final part in row.reasoningGroup?.parts ?? const <TimelineEntry>[])
      part.id,
  };
  return ThreadHistoryWindow(
    previewedItemIds: Set.unmodifiable(
      history.previewedItemIds.intersection(ids),
    ),
    loadingItemIds: Set.unmodifiable(history.loadingItemIds.intersection(ids)),
    itemBodyErrors: Map.unmodifiable({
      for (final entry in history.itemBodyErrors.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    }),
    pendingItemBodyIds: Set.unmodifiable(
      history.pendingItemBodyIds.intersection(ids),
    ),
    unavailableItemIds: Set.unmodifiable(
      history.unavailableItemIds.intersection(ids),
    ),
  );
}

/// One per AppGraph. Selection and Client sources drive this owner even when
/// there are no Riverpod/Widget observers (for example while Settings is open).
/// Only the current selected thread has a display lease and projection cache.
final class TimelineSessionOwner {
  TimelineSessionOwner({required AnyworkClient client}) : _client = client {
    final watched = client.selection.source.watchLatest(_selectionChanged);
    _selectionObservation = watched.observation;
    _selectionChanged(watched.value);
    _resourceObservation = client.resourceFailure.watch((_) {
      if (!_closed) _selectionChanged(client.selection.state);
    });
  }

  final AnyworkClient _client;
  final LatestValue<TimelineSessionWindow?> source = LatestValue(null);
  Observation? _selectionObservation;
  Observation? _resourceObservation;
  _TimelineSessionLease? _current;
  bool _closed = false;
  Future<CloseReport>? _closing;

  TimelineSession? session(String threadId) {
    final current = _current;
    return !_closed && current?.threadId == threadId ? current : null;
  }

  void _selectionChanged(SelectionStoreState selection) {
    if (_closed) return;
    final threadId = selection.needsOpen ? null : selection.selectedThreadId;
    if (_current?.threadId == threadId) return;
    _current?.retire();
    _current = null;
    if (source.value != null) source.publish(null);
    if (threadId == null) return;
    // A display observer never retries admission by constructing another
    // Client owner. Explicit retry publishes its result through resourceFailure.
    final session = _client.existingSession(threadId);
    if (session == null) return;

    late final _TimelineSessionLease lease;
    lease = _TimelineSessionLease(
      (command) => _dispatch(threadId, command),
      (window) {
        if (!_closed && identical(_current, lease)) {
          source.publish(window);
        }
      },
      threadId: threadId,
      budget: _client.budget,
    );
    _current = lease;
    final watched = session.source.watchLatest(lease.apply);
    if (_closed || !identical(_current, lease)) {
      watched.observation.cancel();
      lease.retire();
      return;
    }
    lease.attach(watched.observation);
    lease.apply(watched.value);
  }

  Future<void> _dispatch(String threadId, TimelineCommand command) {
    final commands = _client.threadCommands;
    return switch (command) {
      TimelineLoadOlder() => commands.loadOlderHistory(threadId),
      TimelineLoadNewer() => commands.loadNewerHistory(threadId),
      TimelineExtendLatest() => commands.extendLatestHistory(threadId),
      TimelineJumpToLatest() => commands.jumpToLatest(threadId),
      TimelineExpandBody(:final itemId) => commands.loadItemBody(
        threadId,
        itemId,
      ),
      TimelineVisibleBodies(:final itemIds) => commands.ensureItemBodies(
        threadId,
        itemIds,
      ),
      TimelineAnchorChanged(:final anchor, :final viewAction) =>
        commands.updateTimelineAnchor(threadId, anchor, viewAction: viewAction),
    };
  }

  /// This owner only owns synchronous observations/display leases. Native view
  /// joins and outstanding mutations remain owned by the Client. The graph's
  /// existing deadline is accepted without starting another cleanup timer.
  Future<CloseReport> close({DateTime? deadline}) {
    final existing = _closing;
    if (existing != null) return existing;
    _closed = true;
    _selectionObservation?.cancel();
    _selectionObservation = null;
    _resourceObservation?.cancel();
    _resourceObservation = null;
    _current?.retire();
    _current = null;
    source.close();
    return _closing = Future.value(CloseReport());
  }
}

/// A concrete TimelineSession. The lease owns only observation and projection;
/// retiring it cannot stop the Rust Session, Turn, or Client mutation owner.
final class _TimelineSessionLease implements TimelineSession {
  _TimelineSessionLease(
    this._dispatch,
    this._publish, {
    required this.threadId,
    required ResourceBudget budget,
  }) : _rows = _TimelineRowsStore('timeline:$threadId', budget: budget);

  final String threadId;
  final Future<void> Function(TimelineCommand) _dispatch;
  final void Function(TimelineSessionWindow?) _publish;
  TimelineRowProjector? _projector = TimelineRowProjector();
  final _TimelineRowsStore _rows;
  Observation? _observation;
  ThreadSessionState? _state;
  TimelineSessionWindow? _window;
  final Set<_TimelineEventObserver> _observers = {};
  bool _closed = false;

  void attach(Observation observation) {
    if (_closed) {
      observation.cancel();
      return;
    }
    _observation = observation;
  }

  void apply(ThreadSessionState state) {
    if (_closed || state.threadId != threadId) return;
    final previous = _state;
    _state = state;
    if (!state.hasChatWindow && state.items.isEmpty) {
      if (_window != null) {
        _window = null;
        _rows.clear();
        _publish(null);
      }
      return;
    }
    final history = state.history;
    if (_window != null && _window!.viewId != state.chatViewId) {
      _rows.clear();
      _projector = TimelineRowProjector();
    }
    _rows.replace(_projector!.project(state.items), history);
    final next = TimelineSessionWindow._(
      threadId: threadId,
      viewId: state.chatViewId,
      rowQuery: _rows,
      orderedIds: _rows.orderedIds,
      turn: state.activeTurn,
      history: _pageHistory(history),
      isLoadingOlder:
          history.isLoading && history.direction == TimelineDirection.older,
      isLoadingNewer:
          history.isLoading && history.direction == TimelineDirection.newer,
    );
    if (_window != next) {
      _window = next;
      _publish(next);
    }
    final version = state.chatVersion;
    if (version != null &&
        (previous?.chatViewId != state.chatViewId ||
            previous?.history.epoch != history.epoch ||
            previous?.chatVersion == null)) {
      _emit(TimelineWindowReset(threadId, version));
    } else if (version != null && previous?.chatVersion != version) {
      _emit(TimelineWindowPatch(threadId, previous!.chatVersion!, version));
    }
    if (previous?.activeTurn != state.activeTurn) {
      _emit(TimelineRuntimeChanged(threadId));
    }
    if (history.isLoading && previous?.history.isLoading != true) {
      _emit(TimelinePagingStarted(threadId, history.direction));
    } else if (!history.isLoading && previous?.history.isLoading == true) {
      final error = history.direction == TimelineDirection.older
          ? history.errorMessage
          : history.newerError;
      if (error != null) {
        _emit(TimelinePagingFailed(threadId, history.direction, error));
      } else if (version != null) {
        _emit(TimelinePagingCompleted(threadId, history.direction, version));
      }
    }
  }

  @override
  Stream<TimelineEvent> get events => Stream.multi((controller) {
    if (_closed) {
      controller.addSync(TimelineSessionClosed(threadId));
      controller.closeSync();
      return;
    }
    final observer = _TimelineEventObserver(controller);
    _observers.add(observer);
    controller.onPause = () => observer.paused = true;
    controller.onResume = () {
      observer.paused = false;
      if (observer.pending) {
        observer.pending = false;
        // These are display notifications, not another content stream. A
        // resumed observer rereads the current complete projection instead of
        // buffering an unbounded series of stale window-version notifications.
        final version = _state?.chatVersion;
        if (version != null) {
          controller.addSync(TimelineWindowReset(threadId, version));
        }
      }
    };
    controller.onCancel = () => _observers.remove(observer);
    final version = _state?.chatVersion;
    if (version != null) {
      controller.addSync(TimelineWindowReset(threadId, version));
    }
  }, isBroadcast: true);

  void _emit(TimelineEvent event) {
    if (_closed) return;
    for (final observer in List.of(_observers)) {
      if (observer.paused) {
        observer.pending = true;
      } else {
        observer.controller.addSync(event);
      }
    }
  }

  @override
  Future<void> dispatch(TimelineCommand command) {
    if (_closed) {
      return Future.error(StateError('The Timeline lease is closed'));
    }
    return _dispatch(command);
  }

  void retire() {
    if (_closed) return;
    _closed = true;
    _observation?.cancel();
    _observation = null;
    _projector = null;
    _rows.clear();
    _window = null;
    _state = null;
    for (final observer in List.of(_observers)) {
      observer.controller.addSync(TimelineSessionClosed(threadId));
      observer.controller.closeSync();
    }
    _observers.clear();
  }

  @override
  Future<void> close() {
    retire();
    return Future.value();
  }
}

final class _TimelineEventObserver {
  _TimelineEventObserver(this.controller);
  final MultiStreamController<TimelineEvent> controller;
  bool paused = false;
  bool pending = false;
}
