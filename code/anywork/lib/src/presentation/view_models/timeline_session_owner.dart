import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import '../../domain/models/timeline_commands.dart';
import '../../domain/models/timeline_rows.dart';

/// 展示 owner 交给连接组件的窗口快照：行投影 + 窗口边界 + 正文状态。
///
/// 它不是第二份正文事实源：投影与行对象都属于应用侧的显示镜像，正文、状态与省略量仍由
/// canonical 窗口条目携带（design/25 §25.6）。
final class TimelineSessionWindow {
  const TimelineSessionWindow({
    required this.threadId,
    required this.rows,
    required this.orderedIds,
    required this.rowVersions,
    required this.turn,
    required this.history,
    required this.isLoadingOlder,
    required this.isLoadingNewer,
    this.viewId,
  });

  final String threadId;
  final String? viewId;
  final List<TimelineRow> rows;
  final List<String> orderedIds;

  /// 行的内容版本序列。展示窗口的相等性必须包含它：正文增量只改变行的渲染版本，
  /// 若只比较身份序列，窗口就不会重新交付，读者会停留在一份过期的正文上。
  final List<int> rowVersions;
  final StudioTurnView? turn;

  /// canonical 窗口交付的正文状态：预览、回源在途、待落盘、不可用与错误。
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
          _sameVersions(rowVersions, other.rowVersions) &&
          turn == other.turn &&
          history == other.history &&
          isLoadingOlder == other.isLoadingOlder &&
          isLoadingNewer == other.isLoadingNewer;

  @override
  int get hashCode => Object.hash(
    threadId,
    viewId,
    Object.hashAll(orderedIds),
    Object.hashAll(rowVersions),
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

bool _sameVersions(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
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
    // 切换 Thread 时显式关闭旧 lease：不留下上一会话的行投影或展示状态。
    _current?.retire();
    _current = null;
    if (source.value != null) source.publish(null);
    if (threadId == null) return;
    // A display observer never retries admission by constructing another
    // Client owner. Explicit retry publishes its result through resourceFailure.
    final session = _client.existingSession(threadId);
    if (session == null) return;

    late final _TimelineSessionLease lease;
    lease = _TimelineSessionLease((command) => _dispatch(threadId, command), (
      window,
    ) {
      if (!_closed && identical(_current, lease)) {
        source.publish(window);
      }
    }, threadId: threadId);
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

  /// 命令门面直接使用 Client 的 threadCommands；展示 owner 不持有第二份会话事实源。
  Future<void> _dispatch(String threadId, TimelineCommand command) {
    final commands = _client.threadCommands;
    return switch (command) {
      TimelineLoadOlder() => commands.loadOlderHistory(threadId),
      TimelineLoadNewer() => commands.loadNewerHistory(threadId),
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
  _TimelineSessionLease(this._dispatch, this._publish, {required this.threadId})
    : _projector = TimelineRowProjector();

  final String threadId;
  final Future<void> Function(TimelineCommand) _dispatch;
  final void Function(TimelineSessionWindow?) _publish;
  TimelineRowProjector? _projector;
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
        _publish(null);
      }
      return;
    }
    final history = state.history;
    if (_window != null && _window!.viewId != state.chatViewId) {
      _projector = TimelineRowProjector();
    }
    final rows = _projector!.project(state.items);
    final next = TimelineSessionWindow(
      threadId: threadId,
      viewId: state.chatViewId,
      rows: rows,
      orderedIds: [for (final row in rows) row.id],
      rowVersions: [for (final row in rows) row.renderVersion],
      turn: state.activeTurn,
      history: history,
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

  /// 窗口版本号：仅用于事件序号的去重，不作为内容事实源。
  int? get _chatVersion => _state?.chatVersion;

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
        final version = _chatVersion;
        if (version != null) {
          controller.addSync(TimelineWindowReset(threadId, version));
        }
      }
    };
    controller.onCancel = () => _observers.remove(observer);
    final version = _chatVersion;
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
