import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show Key, ValueKey;
import 'package:flutter/widgets.dart' show ScrollController;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../domain/models/timeline_presentation.dart';

const Object _unset = Object();

/// 公开给 view 的只读展示元数据。
///
/// 它**不含**任何已加载行/正文列表：唯一已加载消息集合在 [TimelineDisplayLease] 借出的
/// `InMemoryChatController.messages` 里，这里只描述模式、代次、连接、分页与新输出提示
/// （design/26 §26.8）。
class TimelineSessionViewState {
  const TimelineSessionViewState({
    required this.threadId,
    required this.generation,
    required this.mode,
    required this.connection,
    required this.connectionError,
    required this.olderCursor,
    required this.hasOlder,
    required this.isLoadingOlder,
    required this.olderError,
    required this.hasNewOutput,
    required this.isPreparingLive,
  });

  final String threadId;

  /// 展示代次；0 表示还没有建立展示（连接中或失败）。
  final int generation;
  final TimelineDisplayMode mode;

  /// 内容连接阶段；与 Thread 状态同步完全独立。
  final TimelineConnectionPhase connection;
  final Object? connectionError;

  /// 继续向前翻页的不透明边界；`null` 表示本代次没有更早边界。
  final String? olderCursor;
  final bool hasOlder;
  final bool isLoadingOlder;

  /// 分页失败保留内容并可显式重试；不为空即显示重试入口。
  final Object? olderError;

  /// History 下后台已有更新输出：只作为提示，不改冻结展示。
  final bool hasNewOutput;

  /// 正在建立新展示代次（显式回实时/发送前准备）。
  final bool isPreparingLive;

  TimelineSessionViewState copyWith({
    int? generation,
    TimelineDisplayMode? mode,
    TimelineConnectionPhase? connection,
    Object? connectionError = _unset,
    Object? olderCursor = _unset,
    bool? hasOlder,
    bool? isLoadingOlder,
    Object? olderError = _unset,
    bool? hasNewOutput,
    bool? isPreparingLive,
  }) => TimelineSessionViewState(
    threadId: threadId,
    generation: generation ?? this.generation,
    mode: mode ?? this.mode,
    connection: connection ?? this.connection,
    connectionError: identical(connectionError, _unset)
        ? this.connectionError
        : connectionError,
    olderCursor: identical(olderCursor, _unset)
        ? this.olderCursor
        : olderCursor as String?,
    hasOlder: hasOlder ?? this.hasOlder,
    isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
    olderError: identical(olderError, _unset) ? this.olderError : olderError,
    hasNewOutput: hasNewOutput ?? this.hasNewOutput,
    isPreparingLive: isPreparingLive ?? this.isPreparingLive,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineSessionViewState &&
          threadId == other.threadId &&
          generation == other.generation &&
          mode == other.mode &&
          connection == other.connection &&
          connectionError == other.connectionError &&
          olderCursor == other.olderCursor &&
          hasOlder == other.hasOlder &&
          isLoadingOlder == other.isLoadingOlder &&
          olderError == other.olderError &&
          hasNewOutput == other.hasNewOutput &&
          isPreparingLive == other.isPreparingLive;

  @override
  int get hashCode => Object.hash(
    threadId,
    generation,
    mode,
    connection,
    connectionError,
    olderCursor,
    hasOlder,
    isLoadingOlder,
    olderError,
    hasNewOutput,
    isPreparingLive,
  );
}

/// 一个展示代次借给 view 的 handle。
///
/// 每个代次拥有**新的** `InMemoryChatController`、`Chat` key 与
/// `ScrollController(keepScrollOffset: false)`。视图只在真实子树初始化时 [bind]、在真实
/// 子树 dispose 时 [unbind]；退役先停止发布与查询，等已挂载旧代次真正解绑后才销毁 controller
/// 并观察 stock operations stream 真正 done（design/26 §26.8）。
final class TimelineDisplayLease {
  TimelineDisplayLease({
    required this.threadId,
    required this.generation,
    required this.openQueries,
  }) : _controller = InMemoryChatController() {
    _presentation = TimelinePresentationController(
      _controller,
      generation: generation,
    );
  }

  /// 固定 Thread 身份与展示代次；两者都不随 tail 版本变化。
  final String threadId;
  final int generation;

  /// 每次 attempt 变化后按需重建查询 scope 的入口（由 owner 提供）。
  final StudioTimelineQueryScope? Function(int generation) openQueries;
  final InMemoryChatController _controller;
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  late final TimelinePresentationController _presentation;

  /// 已覆盖范围的最早 canonical 键（`(ordinal, id)`）。
  ///
  /// 真实删除会让行消失，但**不**抹掉已经覆盖的范围边界；否则尾部更早身份的 `Add`
  /// 会被误当成已覆盖范围内的新身份插入，凭空制造分页前缀空洞（design/26 §26.7）。
  (int, String)? _floor;

  /// 已覆盖范围的最新 canonical 键；只随基线/前插/尾部插入单调外扩。
  (int, String)? _ceiling;

  /// 被有意忽略的更早身份及其 canonical 键（只存身份与位置，不存正文）。
  ///
  /// 保留位置是为了在后续页把这段范围纳入覆盖时，能核对“已知存在的身份”是否真的被这
  /// 一页交付：页快照可能线性化在尾部 `Add` 之前，游标一旦越过它就会永久缺消息。
  final Map<String, (int, String)> _excluded = {};
  static const int _excludedIdentities = 128;
  bool _excludedOverflow = false;

  final Completer<void> _released = Completer<void>();

  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  int? _appliedVersion;
  String? _olderCursor;
  bool _hasOlder = false;
  StudioTimelineQueryScope? _queries;
  bool _queriesSettled = false;
  bool _mounted = false;
  bool _retired = false;
  bool _disposed = false;

  /// Chat 子树的 key：新代次必须换 key，不能沿用旧列表 state。
  Key get chatKey => ValueKey('timeline-chat:$threadId:$generation');

  /// 唯一已加载消息集合由库持有；这里只借用同一个 controller。
  ChatController get controller => _controller;

  /// 只用于库、Scrollbar、被动观察与诊断；应用不写 pixels。
  ScrollController get scrollController => _scrollController;

  TimelineDisplayMode get mode => _mode;
  int? get appliedVersion => _appliedVersion;
  String? get olderCursor => _olderCursor;
  bool get hasOlder => _hasOlder;
  int get loadedCount => _presentation.length;
  Iterable<TimelineMessagePayload> get payloads => _presentation.payloads;
  TimelinePresentationItem? presentationFor(String itemId) =>
      _presentation.ownerOf(itemId);
  void addItemListener(TimelineItemListener listener) =>
      _presentation.addItemListener(listener);
  void removeItemListener(TimelineItemListener listener) =>
      _presentation.removeItemListener(listener);
  bool get isMounted => _mounted;
  bool get isRetired => _retired;
  bool get isReleased => _released.isCompleted;

  /// 本代次的查询 scope：attempt 变化后按需重建，仍绑定同一个展示代次。
  StudioTimelineQueryScope? get queries {
    final current = _queries;
    if (current != null && current.isActive) return current;
    if (_retired) return null;
    return _queries = openQueries(generation);
  }

  /// 该字段按需读取全文的入口；null 表示本代次没有加载该身份或字段。
  StudioTimelineDetailRef? detailRef(
    String itemId,
    ThreadContentFieldView field,
  ) => _presentation.payload(itemId)?.detailFor(field);

  /// 真实子树挂载。
  ///
  /// 退役不等于已释放：控制器尚存时发生的迟到真实挂载仍计入卸载等待，否则会在旧子树
  /// 还持有控制器时销毁它。已经释放的代次必须显式拒绝，不能静默把已销毁的控制器交给
  /// 子树（design/26 §26.8）。
  void bind() {
    if (_disposed) {
      throw StateError(
        'The timeline display generation was already released: '
        '$threadId#$generation',
      );
    }
    _mounted = true;
  }

  /// 本代次已加载身份的 typed 载荷；只读当前 Message，不复制正文。
  TimelineMessagePayload? payloadOf(String itemId) {
    return _presentation.payload(itemId);
  }

  /// 真实子树卸载：解绑并允许销毁。
  Future<void> unbind() {
    _mounted = false;
    _releaseIfReady();
    return _released.future;
  }

  /// 一次释放的 ACK；已释放时返回同一 future。
  Future<void> get released => _released.future;

  /// 退役：停止发布、拒绝新查询，然后等待真实卸载。
  Future<void> retire() {
    if (_retired) return _released.future;
    _retired = true;
    final scope = _queries;
    _queries = null;
    if (scope == null) {
      _queriesSettled = true;
    } else {
      // 先拒绝新工作与迟到发布，再等**已经受理**的真实查询退出；不丢 scope、不假装
      // 成功（design/26 §26.8）。
      scope.retire();
      unawaited(_settleQueries(scope));
    }
    _releaseIfReady();
    return _released.future;
  }

  Future<void> _settleQueries(StudioTimelineQueryScope scope) async {
    try {
      await scope.close();
    } finally {
      _queriesSettled = true;
      _releaseIfReady();
    }
  }

  void _releaseIfReady() {
    if (_disposed || !_retired || _mounted || !_queriesSettled) return;
    _disposed = true;
    // 先挂 done 观察者再关闭流：stock operations stream 的 done 是可等待的释放 ACK。
    _controller.operationsStream.listen(
      (_) {},
      onDone: () {
        if (!_released.isCompleted) _released.complete();
      },
    );
    _presentation.dispose();
    _controller.dispose();
    _scrollController.dispose();
  }

  // ---- owner 内部：基线/差量应用 ----------------------------------------

  void adoptBaseline(StudioTimelineBaseline baseline) {
    _presentation.reset();
    _excluded.clear();
    _excludedOverflow = false;
    final ordered = [...baseline.items]
      ..sort(
        (left, right) => _compareCanonical(
          (left.item.ordinal, left.id),
          (right.item.ordinal, right.id),
        ),
      );
    for (final item in ordered) {
      _presentation.add(TimelineMessagePayload.fromItem(item));
    }
    _appliedVersion = baseline.version;
    _olderCursor = baseline.before;
    _hasOlder = baseline.hasOlder;
    _floor = ordered.isEmpty
        ? null
        : (ordered.first.item.ordinal, ordered.first.id);
    _ceiling = ordered.isEmpty
        ? null
        : (ordered.last.item.ordinal, ordered.last.id);
  }

  /// 应用一帧连续补丁；返回 false 表示本代次无法证明连续，需要显式新基线。
  ///
  /// History 下已展示内容/结构/saved 全部冻结：不写 Message、不改版本水位。
  bool applyPatch(StudioTimelinePatch patch) {
    if (_mode == TimelineDisplayMode.history) return true;
    if (_appliedVersion != patch.from) return false;
    for (final change in patch.changes) {
      final applied = switch (change) {
        StudioTimelineAdd(:final item) => _applyAdded(item),
        StudioTimelineUpdateItem() => _applyUpdated(change),
        StudioTimelineRemove(:final itemId) => _applyRemoved(itemId),
      };
      if (!applied) return false;
    }
    _appliedVersion = patch.to;
    return true;
  }

  /// 一条权威整条预览落进本代次：已加载身份原位收敛，新身份按 canonical 顺序插入。
  ///
  /// `Add` 不保证该身份从未被页查询加载，也不保证随后会补发 `UpdateItem`，因此不能把
  /// 已加载身份直接跳过。更早且未被本代次覆盖的新身份不插入（避免在分页前缀里造洞）、
  /// 也不另存待回放正文；它们由后续页查询取当时的权威值。
  bool _applyAdded(StudioTimelineItem incoming) {
    final payload = _presentation.payload(incoming.id);
    if (payload != null) {
      final next = payload.applyAdd(incoming);
      if (next == null) return false;
      if (!identical(next, payload)) _presentation.replace(incoming.id, next);
      return true;
    }
    final key = (incoming.item.ordinal, incoming.id);
    final floor = _floor;
    if (floor != null && _compareCanonical(key, floor) < 0) {
      _rememberExcluded(incoming.id, key);
      return true;
    }
    _excluded.remove(incoming.id);
    _presentation.add(TimelineMessagePayload.fromItem(incoming));
    final ceiling = _ceiling;
    if (ceiling == null || _compareCanonical(key, ceiling) > 0) _ceiling = key;
    return true;
  }

  bool _applyUpdated(StudioTimelineUpdateItem change) {
    final current = _presentation.payload(change.itemId);
    if (current != null) {
      final next = current.applyUpdate(change);
      if (next == null) return false;
      _presentation.replace(change.itemId, next);
      return true;
    }
    // 未知身份：只有能证明它属于被有意忽略的更早范围时才能安静跳过。
    final shell = change.itemShell;
    final floor = _floor;
    if (shell != null) {
      if (shell.id != change.itemId) return false;
      final key = (shell.ordinal, shell.id);
      if (floor != null && _compareCanonical(key, floor) < 0) {
        _rememberExcluded(change.itemId, key);
        return true;
      }
      // 已覆盖范围内的空洞：本代次漏了一条事实，必须显式重同步。
      return false;
    }
    return _excluded.containsKey(change.itemId);
  }

  bool _applyRemoved(String itemId) {
    // 真实删除清掉该身份的忽略证据，但**不**抹掉已经覆盖的范围下界。
    _excluded.remove(itemId);
    _presentation.remove(itemId);
    return true;
  }

  /// 前插一页更早消息；重叠身份不重复插入，返回实际前插条数。
  ///
  /// 返回 null 表示这页与已覆盖范围无法证明连续（例如页游标之后又发布过更早身份）：
  /// 调用方必须显式重同步，不能把更早身份插进已覆盖范围造成空洞。
  int? prependOlder(StudioTimelinePage page) {
    final floor = _floor;
    final accepted = <(StudioTimelineItem, (int, String))>[];
    for (final item in page.items) {
      final key = (item.item.ordinal, item.id);
      if (floor != null && _compareCanonical(key, floor) >= 0) {
        // 已加载的重叠身份直接去重；未加载却在已覆盖范围内说明页前缀与本代次不连续。
        if (_presentation.contains(item.id)) continue;
        return null;
      }
      if (_presentation.contains(item.id)) continue;
      accepted.add((item, key));
    }
    accepted.sort((left, right) => _compareCanonical(left.$2, right.$2));
    // 这一页会把 [新下界, 旧下界) 纳入覆盖：区间里已知存在、但页快照没有交付的身份
    // 会被游标永久越过。已知证据不完整时（有界元数据已淘汰）同样不能声称完整。
    if (floor != null && accepted.isNotEmpty) {
      if (_excludedOverflow) return null;
      final newFloor = accepted.first.$2;
      final delivered = {for (final item in page.items) item.id};
      for (final entry in _excluded.entries) {
        final key = entry.value;
        if (_compareCanonical(key, floor) >= 0) continue;
        if (_compareCanonical(key, newFloor) < 0) continue;
        if (delivered.contains(entry.key)) continue;
        return null;
      }
    }
    for (final entry in accepted) {
      _presentation.add(TimelineMessagePayload.fromItem(entry.$1));
      _excluded.remove(entry.$1.id);
    }
    if (accepted.isNotEmpty) _floor = accepted.first.$2;
    _olderCursor = page.before;
    _hasOlder = page.hasOlder;
    return accepted.length;
  }

  /// 记住“更早范围里已知存在但本代次不展示”的身份与位置；退出有界容量后不再声称完整。
  void _rememberExcluded(String itemId, (int, String) key) {
    if (_excluded.length >= _excludedIdentities &&
        !_excluded.containsKey(itemId)) {
      _excluded.remove(_excluded.keys.first);
      _excludedOverflow = true;
    }
    _excluded[itemId] = key;
  }

  void enterHistory() => _mode = TimelineDisplayMode.history;
}

/// canonical 顺序：严格 `(ordinal, id)`，与分页 keyset 同一顺序。
int _compareCanonical((int, String) left, (int, String) right) {
  final byOrder = left.$1.compareTo(right.$1);
  return byOrder != 0 ? byOrder : left.$2.compareTo(right.$2);
}

/// 当前选中会话的展示 owner。
///
/// 每个 AppGraph 一个。它只拥有当前 Thread 的展示 lease 与展示元数据；已加载消息只存在于
/// lease 的 stock controller 里，不镜像 SDK 的有界尾部，也不保留 rows/ids/versions 快照。
final class TimelineSessionOwner {
  TimelineSessionOwner({required AnyworkClient client}) : _client = client {
    final watched = client.selection.source.watchLatest(_selectionChanged);
    _selectionObservation = watched.observation;
    _sessionObservation = client
        .watchActiveSession((_) => _selectionChanged(client.selection.state))
        .observation;
    _selectionChanged(watched.value);
  }

  final AnyworkClient _client;
  final LatestValue<TimelineSessionViewState?> source = LatestValue(null);
  Observation? _selectionObservation;
  Observation? _sessionObservation;
  Observation? _timelineObservation;
  StudioThreadSession? _observedSession;
  String? _observedThread;

  TimelineDisplayLease? _current;
  final Set<TimelineDisplayLease> _retiring = {};
  _PendingSwitch? _pendingSwitch;
  Future<void>? _olderInFlight;
  int _generation = 0;
  bool _closed = false;
  Future<CloseReport>? _closing;

  /// 当前展示 lease 的借用 handle；不是该 Thread 或无展示时为 null。
  TimelineDisplayLease? lease(String threadId) {
    final current = _current;
    return !_closed && current != null && current.threadId == threadId
        ? current
        : null;
  }

  StudioThreadSession? _sessionOf(String threadId) =>
      _client.existingSession(threadId);

  void _selectionChanged(SelectionStoreState selection) {
    if (_closed) return;
    final threadId = selection.needsOpen ? null : selection.selectedThreadId;
    final active = _client.activeSession;
    final session = active?.threadId == threadId ? active : null;
    if (_observedThread == threadId &&
        identical(_observedSession, session) &&
        _timelineObservation != null) {
      return;
    }
    _detachTimeline();
    final previous = _current;
    _current = null;
    _observedThread = threadId;
    // 展示准备属于被切换掉的那次展示：选择一变就以 typed 取消收束旧等待，
    // 不能留下永久 pending（design/26 §26.8）。
    final pending = _pendingSwitch;
    _pendingSwitch = null;
    if (pending != null && !pending.result.isCompleted) {
      pending.cancel();
    }
    _olderInFlight = null;
    if (previous != null) unawaited(_retire(previous));
    if (threadId == null) {
      source.publish(null);
      return;
    }
    source.publish(
      TimelineSessionViewState(
        threadId: threadId,
        generation: 0,
        mode: TimelineDisplayMode.live,
        connection: TimelineConnectionPhase.idle,
        connectionError: null,
        olderCursor: null,
        hasOlder: false,
        isLoadingOlder: false,
        olderError: null,
        hasNewOutput: false,
        isPreparingLive: false,
      ),
    );
    if (session == null) {
      final failure = _client.resourceFailure.value;
      if (failure?.owner == 'session:$threadId') {
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: failure!.reason,
        );
      }
      return;
    }
    final watched = session.timeline.state.watchLatest(
      (state) => _onTimelineState(threadId, state),
    );
    _timelineObservation = watched.observation;
    _observedSession = session;
    _onTimelineState(threadId, watched.value);
  }

  void _detachTimeline() {
    _timelineObservation?.cancel();
    _timelineObservation = null;
    _observedSession = null;
  }

  // ---- 内容帧 → 展示代次 ------------------------------------------------

  void _onTimelineState(
    String threadId,
    ChatUiState<StudioTimelineFrame> state,
  ) {
    if (_closed || _observedThread != threadId) return;
    switch (state) {
      case ChatIdle<StudioTimelineFrame>():
        _publishState(connection: TimelineConnectionPhase.idle);
      case ChatOpening<StudioTimelineFrame>():
        _publishState(
          connection: TimelineConnectionPhase.opening,
          connectionError: null,
        );
      case ChatReady<StudioTimelineFrame>(:final snapshot):
        _publishState(
          connection: TimelineConnectionPhase.ready,
          connectionError: null,
        );
        _applyFrame(threadId, snapshot);
      case ChatReconnecting<StudioTimelineFrame>(:final error):
        _publishState(
          connection: TimelineConnectionPhase.reconnecting,
          connectionError: error,
        );
      case ChatFailed<StudioTimelineFrame>(:final error):
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error,
        );
        _failPendingSwitch(error);
      case ChatClosed<StudioTimelineFrame>():
        _publishState(connection: TimelineConnectionPhase.closed);
        _failPendingSwitch(
          StateError('The timeline content connection was closed'),
        );
    }
  }

  void _applyFrame(String threadId, StudioTimelineFrame frame) {
    switch (frame) {
      case StudioTimelineBaselineFrame(:final baseline):
        final pending = _pendingSwitch;
        if (pending != null && pending.threadId == threadId) {
          _pendingSwitch = null;
          _startGeneration(threadId, baseline);
          _publishNewGeneration(isPreparingLive: false);
          if (!pending.result.isCompleted) pending.result.complete();
          return;
        }
        final current = _current;
        if (current == null) {
          _startGeneration(threadId, baseline);
          _publishNewGeneration();
          return;
        }
        if (current.mode == TimelineDisplayMode.live) {
          // 同连接重同步/重连基线：Live 采用同一种新代次语义，
          // 不把旧基线拼成应用侧第二套恢复算法。
          _startGeneration(threadId, baseline);
          _publishNewGeneration();
          return;
        }
        // History：只更新连接与提示，不替换冻结展示。
        _publishState(hasNewOutput: true);
      case StudioTimelinePatchFrame(:final patch):
        final current = _current;
        if (current == null) {
          _requestResync();
          return;
        }
        if (!current.applyPatch(patch)) {
          _requestResync();
          return;
        }
        final alreadyHinted = source.value?.hasNewOutput ?? false;
        _publishState(
          // History 只有真实内容或展示状态变化才提示；纯保存确认与空批次不制造
          // “有新输出”（design/26 §26.8）。
          hasNewOutput:
              alreadyHinted ||
              (current.mode == TimelineDisplayMode.history &&
                  _historyShowsNewContent(current, patch)),
        );
    }
  }

  /// History 下这一帧是否带来真实内容或展示状态变化。
  ///
  /// 只读已交付 Message 的 typed 事实，不另存正文副本：revision 前进、字段真实变化、
  /// 预览封顶后总长继续增长、执行终态推进或 Turn/更新时间变化都算新内容；同一 revision
  /// 下全部 `Unchanged` 且字段总长不变的帧只是保存/省略量等元数据，不算。
  bool _historyShowsNewContent(
    TimelineDisplayLease lease,
    StudioTimelinePatch patch,
  ) {
    for (final change in patch.changes) {
      switch (change) {
        case StudioTimelineAdd():
        case StudioTimelineRemove():
          return true;
        case StudioTimelineUpdateItem(
          :final itemId,
          :final expectedRevision,
          :final revision,
          :final lifecycle,
          :final itemShell,
          :final fields,
        ):
          final current = lease.payloadOf(itemId);
          if (current == null) return true;
          if (revision != expectedRevision) return true;
          if (lifecycle == StudioTimelineLifecycle.terminal &&
              !current.terminal) {
            return true;
          }
          if (itemShell != null &&
              (itemShell.turnId != current.item.turnId ||
                  itemShell.updatedAt != current.item.updatedAt)) {
            return true;
          }
          for (final update in fields) {
            if (update.change is! UnchangedThreadFieldChangeView) return true;
            final ref = current.detailFor(update.field);
            if (ref == null || ref.totalBytes != update.totalBytes) return true;
          }
      }
    }
    return false;
  }

  /// 消费者无法证明连续：显式刷新内容连接（新订阅/新基线），本地不补帧。
  void _requestResync() {
    final threadId = _observedThread;
    if (threadId == null) return;
    _sessionOf(threadId)?.timeline.refresh();
  }

  void _startGeneration(String threadId, StudioTimelineBaseline baseline) {
    final previous = _current;
    final lease = TimelineDisplayLease(
      threadId: threadId,
      generation: ++_generation,
      openQueries: (generation) =>
          _sessionOf(threadId)?.timeline.openScope(generation: generation),
    );
    lease.adoptBaseline(baseline);
    _current = lease;
    _olderInFlight = null;
    if (previous != null) unawaited(_retire(previous));
  }

  /// 新首帧成功的统一收尾：本代次从自己的空闲状态开始，绝不继承旧代次的 loading 或错误。
  ///
  /// 旧代次的迟到页回包被代次 guard 丢弃；如果这里不清零，展示会永久停留在 loading
  /// （design/26 §26.8「分页 loading、错误和在途归属属于展示代次」）。
  void _publishNewGeneration({
    bool hasNewOutput = false,
    bool? isPreparingLive,
  }) => _publishState(
    isLoadingOlder: false,
    olderError: null,
    hasNewOutput: hasNewOutput,
    isPreparingLive: isPreparingLive,
  );

  Future<void> _retire(TimelineDisplayLease lease) async {
    _retiring.add(lease);
    try {
      await lease.retire();
    } finally {
      _retiring.remove(lease);
    }
  }

  // ---- 发布 --------------------------------------------------------------

  void _publishState({
    TimelineDisplayMode? mode,
    TimelineConnectionPhase? connection,
    Object? connectionError = _unset,
    Object? olderError = _unset,
    Object? olderCursor = _unset,
    bool? hasOlder,
    bool? isLoadingOlder,
    bool? hasNewOutput,
    bool? isPreparingLive,
  }) {
    final current = source.value;
    if (current == null) return;
    final lease = _current;
    final next = current.copyWith(
      generation: lease?.generation ?? current.generation,
      mode: mode ?? lease?.mode ?? current.mode,
      connection: connection ?? current.connection,
      connectionError: connectionError,
      olderCursor: identical(olderCursor, _unset)
          ? (lease == null ? current.olderCursor : lease.olderCursor)
          : olderCursor,
      hasOlder: hasOlder ?? lease?.hasOlder ?? current.hasOlder,
      isLoadingOlder: isLoadingOlder ?? current.isLoadingOlder,
      olderError: olderError,
      hasNewOutput: hasNewOutput ?? current.hasNewOutput,
      isPreparingLive: isPreparingLive ?? current.isPreparingLive,
    );
    if (next == current) return;
    source.publish(next);
  }

  // ---- 界面意图 ----------------------------------------------------------

  Future<void> dispatch(String threadId, TimelineCommand command) {
    return switch (command) {
      TimelineEnterHistory() => _enterHistory(threadId),
      TimelineReturnLive() => returnToLive(threadId),
    };
  }

  Future<void> _enterHistory(String threadId) async {
    final current = lease(threadId);
    final view = source.value;
    if (current == null || view == null || view.threadId != threadId) return;
    if (view.mode == TimelineDisplayMode.history) return;
    current.enterHistory();
    _publishState(
      mode: TimelineDisplayMode.history,
      hasNewOutput: false,
      connectionError: _unset,
      olderError: _unset,
    );
  }

  /// 显式回到实时：刷新内容连接 attempt，从新订阅的一致最新首帧建立新代次。
  ///
  /// 新首帧成功前旧 History 一直保留；失败可见并可重试，future 以 typed 错误收束。
  Future<void> returnToLive(String threadId) =>
      _establishLiveGeneration(threadId);

  /// 发送前准备：只有当前展示仍属于该 Thread 时才建立新代次。
  ///
  /// 没有该 Thread 的当前展示时不抢占其他 Thread 的展示；命令仍使用草稿冻结的目标。
  /// 失败时抛出 typed 错误且**不改动**当前展示，草稿 owner 据此走已知未提交路径。
  /// 但**仅选择变化**不撤销已经冻结的发送：展示前置不再适用就收束它，由调用方继续提交
  /// 原冻结目标；真实准备失败与退出仍然抛出。
  Future<void> prepareSend(String threadId) async {
    if (_closed || lease(threadId) == null) return;
    try {
      await _establishLiveGeneration(threadId);
    } on TimelinePreparationCancelled {
      // 选择已切走：这次展示前置不再适用，但不改变已冻结的发送目标。
      return;
    }
  }

  Future<void> _establishLiveGeneration(String threadId) async {
    if (_closed) throw StateError('The timeline owner is closed');
    final session = _sessionOf(threadId);
    if (session == null || lease(threadId) == null) return;
    final existing = _pendingSwitch;
    if (existing != null) return existing.result.future;
    final pending = _PendingSwitch(threadId);
    _pendingSwitch = pending;
    _publishState(isPreparingLive: true, hasNewOutput: false);
    // 采用新订阅避免把「页请求返回前已交付的 tail」拼成应用侧第二套恢复算法。
    session.timeline.refresh();
    try {
      await pending.result.future;
    } finally {
      if (identical(_pendingSwitch, pending)) {
        _pendingSwitch = null;
        _publishState(isPreparingLive: false);
      }
    }
  }

  void _failPendingSwitch(Object error) {
    final pending = _pendingSwitch;
    if (pending == null || pending.result.isCompleted) return;
    pending.result.completeError(error);
  }

  /// 同一 Thread/展示代次的视口补齐与触底分页共用同一个在途 future。
  Future<void> loadOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation: generation, retry: false);

  /// Retry clears the previous error only after this request is admitted.
  Future<void> retryOlder(String threadId, {required int generation}) =>
      _requestOlder(threadId, generation: generation, retry: true);

  Future<void> _requestOlder(
    String threadId, {
    required int generation,
    required bool retry,
  }) {
    if (lease(threadId)?.generation != generation) return Future<void>.value();
    final existing = _olderInFlight;
    if (existing != null) return existing;
    final task = _loadOlder(threadId, retry: retry);
    late final Future<void> tracked;
    tracked = task.whenComplete(() {
      if (identical(_olderInFlight, tracked)) _olderInFlight = null;
    });
    _olderInFlight = tracked;
    return tracked;
  }

  Future<void> _loadOlder(String threadId, {required bool retry}) async {
    final current = lease(threadId);
    final view = source.value;
    if (current == null || view == null || view.threadId != threadId) return;
    if (!current.hasOlder ||
        view.isLoadingOlder ||
        (view.olderError != null && !retry) ||
        view.isPreparingLive ||
        view.connection != TimelineConnectionPhase.ready) {
      return;
    }
    final generation = current.generation;
    final before = current.olderCursor;
    _publishState(isLoadingOlder: true, olderError: null);
    StudioTimelineQueryScope? scope;
    try {
      scope = current.queries;
      if (scope == null) {
        throw const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'The timeline content connection is not ready',
          retryable: true,
          correlationId: 'timeline-owner-no-scope',
        );
      }
      final page = await scope.page(before: before);
      final still = lease(threadId);
      if (still == null || still.generation != generation) return;
      if (page.hasOlder && (page.before == null || page.before == before)) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'The history page did not advance its cursor',
          retryable: true,
          correlationId: 'timeline-page-no-progress',
        );
      }
      final inserted = still.prependOlder(page);
      if (inserted == null) {
        // 页前缀与本代次已覆盖范围无法证明连续：显式重建，不静默漏掉事实。
        _publishState(
          isLoadingOlder: false,
          olderError: const StudioFailure(
            code: StudioFailureCode.protocol,
            message:
                'The history page is not continuous with the current display',
            retryable: true,
            correlationId: 'timeline-page-not-continuous',
          ),
        );
        _requestResync();
        return;
      }
      _publishState(isLoadingOlder: false, olderError: null);
    } catch (error) {
      final still = lease(threadId);
      if (still == null || still.generation != generation) return;
      if (scope != null && !scope.isActive) {
        _publishState(isLoadingOlder: false);
        return;
      }
      // 失败保留内容并暴露可重试错误；错误/取消/EOF 都必须收束 loading。
      _publishState(isLoadingOlder: false, olderError: error);
    }
  }

  // ---- 关闭 --------------------------------------------------------------

  /// 关闭：先同步发布「无展示」促使现存视图卸载，再等待真实释放。
  ///
  /// 重复关闭返回同一个 future；树仍借用 controller 时不会提前 ACK。
  Future<CloseReport> close({DateTime? deadline}) {
    final existing = _closing;
    if (existing != null) return existing;
    _closed = true;
    _selectionObservation?.cancel();
    _selectionObservation = null;
    _sessionObservation?.cancel();
    _sessionObservation = null;
    _detachTimeline();
    final pending = _pendingSwitch;
    _pendingSwitch = null;
    if (pending != null && !pending.result.isCompleted) {
      pending.result.completeError(
        StateError('The timeline owner closed during send preparation'),
      );
    }
    final leases = <TimelineDisplayLease>{..._retiring, ?_current};
    _current = null;
    // 同步发布无展示：现存子树据此卸载，其 unbind 才能允许销毁 controller。
    if (source.value != null) source.publish(null);
    for (final lease in leases) {
      unawaited(lease.retire());
    }
    return _closing = _join(leases, deadline);
  }

  Future<CloseReport> _join(
    Set<TimelineDisplayLease> leases,
    DateTime? deadline,
  ) async {
    if (leases.isEmpty) return CloseReport();
    final futures = [for (final lease in leases) lease.released];
    if (deadline == null) {
      await Future.wait(futures);
      return CloseReport();
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining > Duration.zero) {
      try {
        await Future.wait(futures).timeout(remaining);
      } on TimeoutException {
        // 未释放的代次仍被真实子树借用：保留 controller、scroll 与 lease。
      }
    }
    return CloseReport(
      unresolved: [
        for (final lease in leases)
          if (!lease.isReleased)
            UnresolvedResource(
              owner: 'timeline-display:${lease.threadId}',
              attemptId: AttemptId(lease.generation),
              reason: StateError(
                'The mounted timeline generation has not been released',
              ),
            ),
      ],
    );
  }
}

final class _PendingSwitch {
  _PendingSwitch(this.threadId);
  final String threadId;
  final Completer<void> result = Completer<void>();

  /// 选择变化让这次展示前置不再适用：typed 取消，不是失败也不是成功。
  void cancel() {
    if (!result.isCompleted) {
      result.completeError(TimelinePreparationCancelled(threadId));
    }
  }
}

/// 展示准备因为在途选择变化而不再适用。
///
/// 它只表示“这次展示前置被放弃”，**不**表示发送失败：已冻结的发送目标仍然有效
/// （design/26 §26.8）。
final class TimelinePreparationCancelled implements Exception {
  const TimelinePreparationCancelled(this.threadId);
  final String threadId;

  @override
  String toString() =>
      'Timeline preparation for thread $threadId was cancelled by a selection change';
}
