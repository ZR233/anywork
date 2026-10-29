import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart'
    show Key, Listenable, ValueKey, ValueListenable, ValueNotifier;
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';
import 'package:flutter/widgets.dart' show ScrollController;
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../domain/models/timeline_commands.dart';
import '../../features/conversation/timeline/state/timeline_entry.dart';
import '../../features/conversation/timeline/state/timeline_image_resources.dart';
import '../../features/conversation/timeline/state/timeline_view_state.dart';
import '../../features/conversation/timeline/state/timeline_ui_controllers.dart';
import '../../features/conversation/timeline/view_models/timeline_message_controller.dart';

export '../../features/conversation/timeline/state/timeline_view_state.dart';

const Object _unset = Object();

/// 一个展示代次借给 view 的 handle。
///
/// 每个代次拥有**新的** `InMemoryChatController`、`Chat` key 与
/// `ScrollController(keepScrollOffset: false)`。视图只在真实子树初始化时 [bind]、在真实
/// 子树 dispose 时 [unbind]；退役先停止发布与查询，等已挂载旧代次真正解绑后才销毁 controller
/// 并观察 stock operations stream 真正 done（design/26 §26.8）。
final class TimelineDisplayLease implements TimelineUiControllers {
  TimelineDisplayLease({
    required this.threadId,
    required this.generation,
    required this.content,
  }) : _controller = InMemoryChatController(),
       imageResources = TimelineImageResources(threadId: threadId) {
    _presentation = TimelineMessageController(
      _controller,
      generation: generation,
      imageResources: imageResources,
    );
  }

  /// 固定 Thread 身份与展示代次；两者都不随 tail 版本变化。
  final String threadId;
  final int generation;
  final ConversationContent content;
  final TimelineImageResources imageResources;

  final InMemoryChatController _controller;
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );

  late final TimelineMessageController _presentation;

  (int, String)? _floor;
  final Completer<void> _released = Completer<void>();
  final ValueNotifier<bool> retirement = ValueNotifier(false);

  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  int? _appliedVersion;
  String? _olderCursor;
  bool _hasOlder = false;
  ConversationPageCoverage? _pageCoverage;
  ConversationQueryScope? _queries;
  final Set<ConversationQueryScope> _ownedQueries = {};
  Object? queryCleanupError;
  bool _queriesSettled = false;
  bool _mounted = false;
  bool _retired = false;
  bool _disposed = false;

  /// Chat 子树的 key：新代次必须换 key，不能沿用旧列表 state。
  @override
  Key get chatKey => ValueKey('timeline-chat:$threadId:$generation');

  /// 唯一已加载消息集合由库持有；这里只借用同一个 controller。
  @override
  ChatController get controller => _controller;

  /// 只用于库、Scrollbar、被动观察与诊断；应用不写 pixels。
  @override
  ScrollController get scrollController => _scrollController;

  TimelineDisplayMode get mode => _mode;
  int? get appliedVersion => _appliedVersion;
  String? get olderCursor => _olderCursor;
  bool get hasOlder => _hasOlder;
  int get loadedCount => _presentation.length;
  int get activeStreamCount => _presentation.activeStreamCount;
  Iterable<ConversationItem> get items => _presentation.items;
  TimelineEntry? presentationFor(String itemId) =>
      _presentation.ownerOf(itemId);
  Listenable? memberObservation(String itemId) =>
      _presentation.memberObservation(itemId);
  @override
  ValueListenable<StreamState>? streamFor(String itemId) =>
      _presentation.streamFor(itemId);
  bool get isMounted => _mounted;
  @override
  bool get isRetired => _retired;
  bool get isReleased => _released.isCompleted;

  /// 只借用本代次已取得的分页资格；旧 History 不从当前 tail 重建资格。
  ConversationQueryScope? get queries {
    if (_retired || _pageCoverage == null) return null;
    final current = _queries;
    if (current != null && current.isActive) return current;
    _queries = null;
    if (current != null) unawaited(_settleQueries(current));
    final next = content.openScope(
      generation: generation,
      coverage: _pageCoverage,
    );
    if (next != null) _ownedQueries.add(next);
    return _queries = next;
  }

  ConversationQueryScope? openDetailQueries() {
    if (_retired) return null;
    final scope = content.openScope(generation: generation);
    if (scope != null) _ownedQueries.add(scope);
    return scope;
  }

  Future<void> closeDetailQueries(ConversationQueryScope scope) async {
    await _settleQueries(scope);
    if (_ownedQueries.contains(scope)) {
      throw StateError(
        'The detail query scope has not closed: $queryCleanupError',
      );
    }
  }

  /// 该字段按需读取全文的入口；null 表示本代次没有加载该身份或字段。
  ConversationDetailRef? detailRef(
    String itemId,
    ThreadContentFieldView field,
  ) => _presentation.item(itemId)?.detailFor(field);

  /// 真实子树挂载。
  ///
  /// 退役不等于已释放：控制器尚存时发生的迟到真实挂载仍计入卸载等待，否则会在旧子树
  /// 还持有控制器时销毁它。已经释放的代次必须显式拒绝，不能静默把已销毁的控制器交给
  /// 子树（design/26 §26.8）。
  @override
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
  ConversationItem? itemOf(String itemId) {
    return _presentation.item(itemId);
  }

  /// 真实子树卸载：解绑并允许销毁。
  @override
  Future<void> unbind() {
    _mounted = false;
    _releaseIfReady();
    return _released.future;
  }

  /// 一次释放的 ACK；已释放时返回同一 future。
  Future<void> get released => _released.future;

  /// 退役：停止发布、拒绝新查询，然后等待真实卸载。
  Future<void> retire() {
    if (_retired) {
      for (final scope in _ownedQueries.toList()) {
        unawaited(_settleQueries(scope));
      }
      return _released.future;
    }
    _retired = true;
    imageResources.retire();
    retirement.value = true;
    _queries = null;
    if (_ownedQueries.isEmpty) {
      _queriesSettled = true;
    } else {
      // 先拒绝新工作与迟到发布，再等**已经受理**的真实查询退出；不丢 scope、不假装
      // 成功（design/26 §26.8）。
      for (final scope in _ownedQueries.toList()) {
        scope.retire();
        unawaited(_settleQueries(scope));
      }
    }
    _releaseIfReady();
    return _released.future;
  }

  Future<void> _settleQueries(ConversationQueryScope scope) async {
    scope.retire();
    try {
      final report = await scope.close();
      if (report.complete) {
        _ownedQueries.remove(scope);
        if (_ownedQueries.isEmpty) queryCleanupError = null;
      } else {
        queryCleanupError = report;
      }
    } catch (error) {
      queryCleanupError = error;
    }
    _queriesSettled = _ownedQueries.isEmpty;
    _releaseIfReady();
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
    imageResources.release();
    retirement.dispose();
    _controller.dispose();
    _scrollController.dispose();
  }

  // ---- owner 内部：基线/差量应用 ----------------------------------------

  void adoptBaseline(
    ConversationBaseline baseline, {
    ConversationPageCoverage? pageCoverage,
  }) {
    final ordered = [...baseline.items]..sort(compareItems);
    _presentation.prepend(ordered);
    _appliedVersion = baseline.version;
    _olderCursor = baseline.before;
    _hasOlder = baseline.hasOlder;
    _pageCoverage = pageCoverage;
    _floor = ordered.isEmpty
        ? null
        : (ordered.first.header.ordinal, ordered.first.id);
  }

  bool applyPatch(ConversationPatch patch) {
    if (_mode == TimelineDisplayMode.history) return true;
    // Subscription/field/revision validation belongs to the SDK. The display
    // only checks whether it has consumed the immediately preceding frame.
    if (_appliedVersion != patch.from) return false;
    try {
      // Frame-local preparation only: no row is published until the SDK has
      // reconciled every affected historical value through its same reducer.
      final prepared = <String, ConversationItem?>{};
      ConversationItem? currentFor(String id) =>
          prepared.containsKey(id) ? prepared[id] : _presentation.item(id);
      for (final change in patch.changes) {
        switch (change) {
          case ConversationAdd(:final item):
            final current = currentFor(item.id);
            if (current != null) {
              prepared[item.id] = content.mergeItem(current, item);
            } else if (_floor == null ||
                _compareCanonical((item.header.ordinal, item.id), _floor!) >=
                    0) {
              prepared[item.id] = item;
            }
          case ConversationUpdateItem(:final itemId):
            final current = currentFor(itemId);
            if (current != null) {
              prepared[itemId] = content.reduceItem(current, change);
            }
          case ConversationRemove(:final itemId):
            prepared[itemId] = null;
        }
      }
      for (final entry in prepared.entries) {
        final item = entry.value;
        if (item == null) {
          _presentation.remove(entry.key);
        } else if (_presentation.item(entry.key) == null) {
          _presentation.add(item);
        } else {
          _presentation.replace(entry.key, item);
        }
      }
      _appliedVersion = patch.to;
      return true;
    } on Object {
      return false;
    }
  }

  int prependOlder(ConversationPage page) {
    final accepted = <ConversationItem>[];
    for (final item in page.items) {
      if (_presentation.item(item.id) != null) continue;
      accepted.add(item);
      final key = (item.header.ordinal, item.id);
      if (_floor == null || _compareCanonical(key, _floor!) < 0) _floor = key;
    }
    _presentation.prepend(accepted);
    _olderCursor = page.before;
    _hasOlder = page.hasOlder;
    return accepted.length;
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
  TimelineSessionOwner({required this._client});

  final AnyworkClient _client;
  final LatestValue<TimelineSessionViewState?> source = LatestValue(null);
  Observation? _timelineObservation;
  ConversationSession? _observedSession;
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

  ConversationSession? _sessionOf(String threadId) =>
      _client.conversations.existingSession(threadId);

  /// Navigation may explicitly detach presentation while retaining selection
  /// (for example, settings). This does not change business subscription demand.
  void select(String? threadId, {ResourceBudgetExceeded? admissionFailure}) {
    if (_closed) return;
    final session = threadId == null || admissionFailure != null
        ? null
        : _client.conversations.existingSession(threadId);
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
        connection: admissionFailure == null
            ? TimelineConnectionPhase.idle
            : TimelineConnectionPhase.failed,
        connectionError: admissionFailure,
        olderCursor: null,
        hasOlder: false,
        isLoadingOlder: false,
        olderError: null,
        hasNewOutput: false,
        isPreparingLive: false,
      ),
    );
    if (session == null) return;
    final watched = session.content.state.watchLatest(
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
    ChatUiState<ConversationContentFrame> state,
  ) {
    if (_closed || _observedThread != threadId) return;
    switch (state) {
      case ChatIdle<ConversationContentFrame>():
        _publishState(connection: TimelineConnectionPhase.idle);
      case ChatOpening<ConversationContentFrame>():
        _publishState(
          connection: TimelineConnectionPhase.opening,
          connectionError: null,
        );
      case ChatReady<ConversationContentFrame>(:final snapshot):
        _publishState(
          connection: TimelineConnectionPhase.ready,
          connectionError: null,
        );
        _applyFrame(threadId, snapshot);
      case ChatReconnecting<ConversationContentFrame>(:final error):
        _publishState(
          connection: TimelineConnectionPhase.reconnecting,
          connectionError: error,
        );
      case ChatFailed<ConversationContentFrame>(:final error):
        _publishState(
          connection: TimelineConnectionPhase.failed,
          connectionError: error,
        );
        _failPendingSwitch(error);
      case ChatClosed<ConversationContentFrame>():
        _publishState(connection: TimelineConnectionPhase.closed);
        _failPendingSwitch(
          StateError('The timeline content connection was closed'),
        );
    }
  }

  void _applyFrame(String threadId, ConversationContentFrame frame) {
    switch (frame) {
      case ConversationBaselineFrame(:final baseline, :final pageCoverage):
        final pending = _pendingSwitch;
        if (pending != null && pending.threadId == threadId) {
          _pendingSwitch = null;
          _startGeneration(threadId, baseline, pageCoverage: pageCoverage);
          _publishNewGeneration(isPreparingLive: false);
          if (!pending.result.isCompleted) pending.result.complete();
          return;
        }
        final current = _current;
        if (current == null) {
          _startGeneration(threadId, baseline, pageCoverage: pageCoverage);
          _publishNewGeneration();
          return;
        }
        if (current.mode == TimelineDisplayMode.live) {
          // 同连接重同步/重连基线：Live 采用同一种新代次语义，
          // 不把旧基线拼成应用侧第二套恢复算法。
          _startGeneration(threadId, baseline, pageCoverage: pageCoverage);
          _publishNewGeneration();
          return;
        }
        // History：只更新连接与提示，不替换冻结展示。
        _publishState(hasNewOutput: true);
      case ConversationPatchFrame(:final patch):
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
    ConversationPatch patch,
  ) {
    for (final change in patch.changes) {
      switch (change) {
        case ConversationAdd():
        case ConversationRemove():
          return true;
        case ConversationUpdateItem(
          :final itemId,
          :final expectedRevision,
          :final revision,
          :final lifecycle,
          :final header,
          :final descriptor,
          :final fields,
        ):
          final current = lease.itemOf(itemId);
          if (current == null) return true;
          if (revision != expectedRevision) return true;
          if (descriptor != null &&
              !identical(descriptor, current.descriptor)) {
            return true;
          }
          if (lifecycle == ConversationLifecycle.terminal &&
              !current.terminal) {
            return true;
          }
          if (header != null &&
              (header.turnId != current.header.turnId ||
                  header.updatedAt != current.header.updatedAt)) {
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
    _sessionOf(threadId)?.content.refresh();
  }

  void _startGeneration(
    String threadId,
    ConversationBaseline baseline, {
    required ConversationPageCoverage pageCoverage,
  }) {
    final previous = _current;
    final lease = TimelineDisplayLease(
      threadId: threadId,
      generation: ++_generation,
      content: _sessionOf(threadId)!.content,
    );
    lease.adoptBaseline(baseline, pageCoverage: pageCoverage);
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

  Future<void> retire() {
    final current = _current;
    select(null);
    return current?.released ?? Future.value();
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
      connectionError: identical(connectionError, _unset)
          ? current.connectionError
          : connectionError,
      olderCursor: identical(olderCursor, _unset)
          ? (lease == null ? current.olderCursor : lease.olderCursor)
          : olderCursor as String?,
      hasOlder: hasOlder ?? lease?.hasOlder ?? current.hasOlder,
      isLoadingOlder: isLoadingOlder ?? current.isLoadingOlder,
      olderError: identical(olderError, _unset)
          ? current.olderError
          : olderError,
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
    _requireExecutionOpen(threadId);
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
    session.content.refresh();
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

  void _requireExecutionOpen(String threadId) {
    final directory = _client.threadDirectory.state;
    final thread = [
      ...directory.window.threads,
      ...directory.overlayThreads,
    ].where((thread) => thread.id == threadId).firstOrNull;
    if (thread?.status.blocksNewExecution == true ||
        _sessionOf(threadId)
                ?.state
                .workspace
                ?.thread
                .status
                .blocksNewExecution ==
            true) {
      throw const StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message: 'Finally closed Threads are read-only',
        retryable: false,
        correlationId: 'app-timeline-thread-closed',
        detailsJson: '{"reason":"threadClosed"}',
      );
    }
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
    final session = _observedSession;
    final attemptId = current.content.currentAttemptId;
    final before = current.olderCursor;
    _publishState(isLoadingOlder: true, olderError: null);
    ConversationQueryScope? scope;
    try {
      scope = current.queries;
      if (scope == null) {
        throw StudioFailure(
          code: StudioFailureCode.unavailable,
          message: current._pageCoverage == null
              ? 'The timeline has no page coverage. Return to live to reload.'
              : 'The timeline content connection is not ready',
          retryable: true,
          correlationId: 'timeline-owner-no-scope',
        );
      }
      final page = await scope.page(before: before);
      final still = lease(threadId);
      if (!identical(still, current) || still?.generation != generation) return;
      if (!scope.isActive ||
          current.isRetired ||
          !identical(current._queries, scope)) {
        return;
      }
      if (page.hasOlder && (page.before == null || page.before == before)) {
        throw const StudioFailure(
          code: StudioFailureCode.protocol,
          message: 'The history page did not advance its cursor',
          retryable: true,
          correlationId: 'timeline-page-no-progress',
        );
      }
      final pageCoverage = scope.pageCoverage;
      if (pageCoverage == null) {
        throw const ConversationContinuityError(
          'The page scope has no display coverage',
        );
      }
      current._pageCoverage = pageCoverage;
      current.prependOlder(page);
      _publishState(isLoadingOlder: false, olderError: null);
    } catch (error) {
      final still = lease(threadId);
      if (!identical(still, current) || still?.generation != generation) return;
      if (current.isRetired ||
          error is StaleConversationScope ||
          error is StaleConversationAttempt ||
          (scope != null && !scope.isActive)) {
        _publishState(isLoadingOlder: false);
        return;
      }
      if (error is ConversationContinuityError) {
        // Record the original display's failure before refresh retires scopes.
        _publishState(
          isLoadingOlder: false,
          olderError: const StudioFailure(
            code: StudioFailureCode.protocol,
            message: 'The history page is no longer continuous. Return to live to reload.',
            retryable: true,
            correlationId: 'timeline-page-continuity',
          ),
        );
        // Publication may navigate synchronously; never refresh a new A or B.
        if (identical(lease(threadId), current) &&
            !current.isRetired &&
            _observedThread == threadId &&
            source.value?.threadId == threadId &&
            identical(_observedSession, session) &&
            identical(session?.content, current.content) &&
            current.content.currentAttemptId == attemptId &&
            (scope == null || scope.isActive)) {
          current.content.refresh();
        }
        return;
      }
      // 失败保留内容并暴露可重试错误；错误/取消/EOF 都必须收束 loading。
      _publishState(isLoadingOlder: false, olderError: error);
    } finally {
      if (identical(lease(threadId), current) &&
          source.value?.isLoadingOlder == true) {
        _publishState(isLoadingOlder: false);
      }
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
                'The timeline generation has not been released: ${lease.queryCleanupError ?? "waiting for subtree detach"}',
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
