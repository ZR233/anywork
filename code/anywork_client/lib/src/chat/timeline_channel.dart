import 'dart:async';

import '../../models.dart';
import '../../transport_ports.dart';
import '../contracts/stamps.dart';
import '../lifecycle/resource_budget.dart';
import '../observation/latest_value.dart';
import '../studio/timeline_contract.dart';
import 'chat_models.dart';

/// 一次内容尝试已被新的展示代次/重连取代。
final class StaleTimelineAttempt implements Exception {
  const StaleTimelineAttempt();

  @override
  String toString() => 'The timeline content attempt has been retired';
}

/// 尾部连接不再发布进度；错误绝不伪装成正常结束。
final class TimelineStreamEnded implements Exception {
  const TimelineStreamEnded();

  @override
  String toString() => 'The timeline content stream ended';
}

/// 已交付版本无法用本批次连续表达：显式重同步，不在本地拼接。
final class TimelineContinuityError implements Exception {
  const TimelineContinuityError(this.reason);

  final String reason;

  @override
  String toString() => 'Timeline continuity error: $reason';
}

/// 一个展示代次持有的 scope 已退役：拒绝新工作与迟到发布。
final class StaleTimelineScope implements Exception {
  const StaleTimelineScope();

  @override
  String toString() => 'The timeline query scope has been retired';
}

final class RetryPolicy {
  const RetryPolicy({
    this.delays = const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 400),
      Duration(seconds: 1),
    ],
  });

  final List<Duration> delays;
}

/// 页请求允许的条目范围（design/26 §26.2：默认 32，显式 1..100）。
const int timelinePageDefaultLimit = 32;
const int timelinePageMaxLimit = 100;

/// 详情块允许的字节范围：默认 64 KiB，最小 4 字节，最大 256 KiB。
const int timelineDetailMaxBytes = 256 * 1024;
const int timelineDetailMinBytes = 4;

const StudioFailure _pageArgumentFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Timeline page limit must be within 1..100',
  retryable: false,
  correlationId: 'client-timeline-page-argument',
);

const StudioFailure _detailArgumentFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Timeline detail block size must be within 4..262144 bytes',
  retryable: false,
  correlationId: 'client-timeline-detail-argument',
);

/// 一条内容连接的唯一所有者：attempt、demand、预算许可、单泵与 unresolved close。
///
/// 这里没有窗口控制面：page/detail 是有类型返回值的查询（见 [StudioTimelineQueryScope]），
/// 不通过“等待下一个窗口版本确认操作完成”收束。观察 [state] 从不改变 demand；新 attempt
/// 也绝不把补丁折算到另一个 attempt 的已交付基线（design/26 §26.8）。
final class StudioTimelineChannel {
  StudioTimelineChannel({
    required this.threadId,
    required TimelineTransport transport,
    ResourceBudget? budget,
    this.retryPolicy = const RetryPolicy(),
  }) : _transport = transport,
       budget = budget ?? ResourceBudget(),
       state = LatestValue<ChatUiState<StudioTimelineFrame>>(
         ChatIdle<StudioTimelineFrame>(threadId),
       );

  final String threadId;
  final TimelineTransport _transport;
  final ResourceBudget budget;
  final RetryPolicy retryPolicy;
  final LatestValue<ChatUiState<StudioTimelineFrame>> state;

  final Map<AttemptId, _TimelineAttempt> _attempts = {};
  _TimelineAttempt? _current;
  Timer? _retryTimer;
  Observation? _capacityObservation;
  int _sequence = 0;
  int _scopeSequence = 0;
  int _demandVersion = 0;
  int _retries = 0;
  bool _demand = false;
  bool _closed = false;
  StudioTimelineFrame? _lastFrame;
  Future<CloseReport>? _closeFuture;

  bool get hasDemand => _demand;
  bool get isClosed => _closed;
  AttemptId? get currentAttemptId => _current?.id;
  int get ownedAttemptCount => _attempts.length;

  void start() => setDemand(true);

  void setDemand(bool value) {
    if (_closed) {
      if (value) throw StateError('The timeline channel is closed');
      return;
    }
    if (_demand == value) return;
    _demand = value;
    _demandVersion++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancelCapacityObservation();
    final current = _current;
    if (current != null) _retire(current);
    if (!value) {
      _lastFrame = null;
      state.publish(ChatIdle<StudioTimelineFrame>(threadId));
      return;
    }
    _retries = 0;
    _open();
  }

  /// 显式重建内容连接：新订阅、新基线、新 attempt。旧 attempt 由自身收束路径关闭。
  void refresh() {
    if (_closed || !_demand) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancelCapacityObservation();
    _demandVersion++;
    _retries = 0;
    final current = _current;
    if (current != null) _retire(current);
    _open();
  }

  /// 当前 attempt 交付过的最后一帧；供展示 owner 在挂载时判断是否需要显式重建。
  StudioTimelineFrame? get lastDeliveredFrame => _lastFrame;

  /// 等待当前 attempt 的成功基线（或它的 typed 失败）。
  Future<StudioTimelineBaselineFrame> get ready async {
    final attempt = _current;
    if (attempt == null || !_isCurrent(attempt)) {
      final currentState = state.value;
      if (currentState is ChatFailed<StudioTimelineFrame>) {
        throw currentState.error;
      }
      throw const StaleTimelineAttempt();
    }
    final result = await state.waitFor(
      (value) =>
          !_isCurrent(attempt) ||
          value is ChatReady<StudioTimelineFrame> ||
          value is ChatReconnecting<StudioTimelineFrame> ||
          value is ChatFailed<StudioTimelineFrame>,
    );
    if (!_isCurrent(attempt)) throw const StaleTimelineAttempt();
    if (result is ChatReady<StudioTimelineFrame>) {
      final frame = result.snapshot;
      if (frame is StudioTimelineBaselineFrame) return frame;
      throw const StaleTimelineAttempt();
    }
    if (result is ChatReconnecting<StudioTimelineFrame>) throw result.error;
    if (result is ChatFailed<StudioTimelineFrame>) throw result.error;
    throw const StaleTimelineAttempt();
  }

  /// 为当前 attempt 开一个展示代次的查询 scope；没有活动 attempt 时返回 null。
  ///
  /// [generation] 由展示 owner 给出，只用于诊断与预算归属，不参与业务判定。
  StudioTimelineQueryScope? openScope({required int generation}) {
    if (_closed) return null;
    final attempt = _current;
    if (attempt == null || !_isCurrent(attempt)) return null;
    final scope = StudioTimelineQueryScope._(
      channel: this,
      attempt: attempt,
      generation: generation,
      sequence: ++_scopeSequence,
    );
    attempt.scopes.add(scope);
    return scope;
  }

  void _open() {
    if (_closed || !_demand || _current != null) return;
    final id = AttemptId(++_sequence);
    final ResourcePermit permit;
    try {
      permit = budget.acquire(
        ResourceKind.chatHandle,
        owner: '$threadId:${id.value}',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded catch (error) {
      _capacityObservation ??= budget.watchAvailability(
        ResourceKind.chatHandle,
        () {
          _cancelCapacityObservation();
          _open();
        },
      );
      state.publish(
        ChatFailed<StudioTimelineFrame>(
          threadId,
          lastGood: _lastFrame,
          error: error,
        ),
      );
      return;
    }
    _cancelCapacityObservation();
    // 所有权与许可在 transport.open 的首次 await 之前成立。
    final attempt = _TimelineAttempt(
      id: id,
      demandVersion: _demandVersion,
      permit: permit,
    );
    _current = attempt;
    _attempts[id] = attempt;
    state.publish(
      ChatOpening<StudioTimelineFrame>(threadId, lastGood: _lastFrame),
    );
    attempt.task = _run(attempt);
  }

  void _cancelCapacityObservation() {
    _capacityObservation?.cancel();
    _capacityObservation = null;
  }

  bool _isCurrent(_TimelineAttempt attempt) =>
      !_closed &&
      _demand &&
      !attempt.retired &&
      identical(_current, attempt) &&
      attempt.demandVersion == _demandVersion;

  bool _isAttemptLive(_TimelineAttempt attempt) =>
      !_closed && _demand && !attempt.retired && identical(_current, attempt);

  Future<void> _run(_TimelineAttempt attempt) async {
    Object? failure;
    try {
      final connection = await _transport.openTimeline(threadId);
      // 迟到的 open 仍归属本 attempt：句柄立即由它收束。
      attempt.connection = connection;
      if (!_isCurrent(attempt)) return;
      final baseline = await connection.initial();
      if (!_isCurrent(attempt)) return;
      final first = _adoptBaseline(attempt, baseline);
      attempt.permit.mark(ResourcePhase.active);
      _lastFrame = first;
      state.publish(ChatReady<StudioTimelineFrame>(threadId, first));
      while (_isCurrent(attempt)) {
        // 同一时刻只有一个 next，且 reduce 完才取下一帧。
        final update = await connection.next();
        if (!_isCurrent(attempt)) return;
        if (update == null) throw const TimelineStreamEnded();
        final frame = _reduce(attempt, update);
        _lastFrame = frame;
        state.publish(ChatReady<StudioTimelineFrame>(threadId, frame));
      }
    } catch (error) {
      if (_isCurrent(attempt)) {
        failure = error;
        final canRetry = _retries < retryPolicy.delays.length;
        state.publish(
          canRetry
              ? ChatReconnecting<StudioTimelineFrame>(
                  threadId,
                  lastGood: _lastFrame,
                  error: error,
                )
              : ChatFailed<StudioTimelineFrame>(
                  threadId,
                  lastGood: _lastFrame,
                  error: error,
                ),
        );
      }
    } finally {
      if (identical(_current, attempt)) _current = null;
      attempt.retired = true;
      final cleaned = await _cleanup(attempt);
      if (failure != null &&
          !_closed &&
          _demand &&
          attempt.demandVersion == _demandVersion &&
          _current == null) {
        if (cleaned) {
          _scheduleRetry(attempt.demandVersion);
        } else {
          state.publish(
            ChatFailed<StudioTimelineFrame>(
              threadId,
              lastGood: _lastFrame,
              error: attempt.cleanupError!,
            ),
          );
        }
      }
    }
  }

  /// 新基线只属于它自己的 attempt/订阅；旧 attempt 的已交付版本不被继承。
  StudioTimelineBaselineFrame _adoptBaseline(
    _TimelineAttempt attempt,
    StudioTimelineBaseline baseline, {
    StudioTimelineResyncReason? resyncReason,
  }) {
    final known = attempt.subscriptionId;
    if (known != null && known != baseline.subscriptionId) {
      throw const TimelineContinuityError(
        'baseline changed subscription identity',
      );
    }
    attempt.adopt(baseline);
    return StudioTimelineBaselineFrame(baseline, resyncReason: resyncReason);
  }

  /// 把 transport 的一帧更新折算为交付帧；无法证明连续就显式失败（不是猜删除）。
  StudioTimelineFrame _reduce(
    _TimelineAttempt attempt,
    StudioTimelineUpdate update,
  ) {
    switch (update) {
      case StudioTimelineResync(
        :final subscriptionId,
        :final reason,
        :final baseline,
      ):
        if (attempt.subscriptionId != null &&
            attempt.subscriptionId != subscriptionId) {
          throw const TimelineContinuityError(
            'resync changed subscription identity',
          );
        }
        return _adoptBaseline(attempt, baseline, resyncReason: reason);
      case StudioTimelinePatch(
        :final subscriptionId,
        :final from,
        :final to,
        :final changes,
      ):
        final delivered = attempt.version;
        if (attempt.subscriptionId == null ||
            subscriptionId != attempt.subscriptionId ||
            delivered == null ||
            from != delivered) {
          throw const TimelineContinuityError(
            'patch does not continue the delivered version',
          );
        }
        if (to <= from) {
          throw const TimelineContinuityError('patch did not advance');
        }
        for (final change in changes) {
          switch (change) {
            case StudioTimelineAdd(:final item):
              final known = attempt.identities[item.id];
              if (known != null && item.revision < known) {
                throw const TimelineContinuityError(
                  'added identity regressed its revision',
                );
              }
              attempt.remember(item.id, item.revision);
            case StudioTimelineUpdateItem(
              :final itemId,
              :final expectedRevision,
              :final revision,
            ):
              final known = attempt.identities[itemId];
              if (known != null && known != expectedRevision) {
                throw const TimelineContinuityError(
                  'item update does not continue the known revision',
                );
              }
              // revision 是内容版本，不允许倒退；同 revision 的更新是合法的权威事实
              // （例如不伪增 revision 的预览补齐、保存确认或元数据推进）。这里只保有界
              // 连续性校验，不重做 producer 准入，也不为验证正文再建 body mirror。
              if (revision < expectedRevision) {
                throw const TimelineContinuityError(
                  'item update regressed its revision',
                );
              }
              attempt.remember(itemId, revision);
            case StudioTimelineRemove(:final itemId):
              // 真实删除按身份自包含：即使身份已不在连续性副本里也必须交付，
              // 因为消费者可能已通过页查询加载过它。
              attempt.identities.remove(itemId);
          }
        }
        attempt.version = to;
        return StudioTimelinePatchFrame(update);
    }
  }

  void _retire(_TimelineAttempt attempt) {
    attempt.retired = true;
    if (identical(_current, attempt)) _current = null;
    attempt.permit.mark(ResourcePhase.retiring);
    attempt.retireScopes();
    _requestClose(attempt);
  }

  void _requestClose(_TimelineAttempt attempt) {
    final connection = attempt.connection;
    if (connection == null || attempt.closeRequested) return;
    attempt.closeRequested = true;
    try {
      connection.requestClose();
    } catch (error) {
      // 仍然执行 join；request 失败在 join 成功时清除。
      attempt.cleanupError = error;
    }
  }

  Future<bool> _cleanup(_TimelineAttempt attempt) {
    if (attempt.permit.isReleased) return Future.value(true);
    final cleaning = attempt.cleaning;
    if (cleaning != null) return cleaning;
    final task = _joinCleanup(attempt);
    attempt.cleaning = task;
    return task.whenComplete(() {
      attempt.cleaning = null;
    });
  }

  Future<bool> _joinCleanup(_TimelineAttempt attempt) async {
    attempt.permit.mark(ResourcePhase.retiring);
    _requestClose(attempt);
    Object? failure;
    final connection = attempt.connection;
    // 原生 close 与已受理查询并行收束：任何一侧挂起都不能挡住另一侧的 join。
    final closeTask = connection == null
        ? Future<void>.value()
        : Future<void>.sync(connection.close);
    final scopeJoins = <StudioTimelineQueryScope, Future<CloseReport>>{
      for (final scope in List.of(attempt.scopes)) scope: scope.close(),
    };
    try {
      await closeTask;
    } catch (error) {
      failure = error;
    }
    // 已受理的页/详情查询由各自 scope 的真实 future 收束：CloseReport 是唯一的 join
    // 凭据，不能忽略它（忽略报告等于允许在查询仍持许可时宣告 clean）。
    for (final entry in scopeJoins.entries) {
      final CloseReport report;
      try {
        report = await entry.value;
      } catch (error) {
        failure ??= error;
        continue;
      }
      if (report.unresolved.isEmpty) {
        attempt.scopes.remove(entry.key);
      } else {
        failure ??= report.unresolved.first.reason;
      }
    }
    if (failure != null || attempt.scopes.isNotEmpty) {
      attempt.cleanupError = failure ?? attempt.cleanupError;
      attempt.permit.mark(ResourcePhase.unresolved);
      return false;
    }
    attempt.cleanupError = null;
    attempt.permit.release();
    _attempts.remove(attempt.id);
    return true;
  }

  void _scheduleRetry(int demandVersion) {
    if (_closed ||
        !_demand ||
        demandVersion != _demandVersion ||
        _current != null ||
        _retries >= retryPolicy.delays.length) {
      return;
    }
    final delay = retryPolicy.delays[_retries++];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (demandVersion == _demandVersion) _open();
    });
  }

  /// 第一个调用者确定共享期限，之后调用只加入同一结果。
  /// join 超时绝不放走原始 open/close 任务或许可。
  Future<CloseReport> close({DateTime? deadline}) =>
      _closeFuture ??= _close(deadline);

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _demand = false;
    _demandVersion++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancelCapacityObservation();
    for (final attempt in List.of(_attempts.values)) {
      _retire(attempt);
    }
    state.publish(ChatClosed<StudioTimelineFrame>(threadId));
    final tasks = <Future<void>>[
      for (final attempt in _attempts.values)
        if (attempt.task case final task?) task,
    ];
    if (deadline == null) {
      await Future.wait(tasks);
    } else {
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        try {
          await Future.wait(tasks).timeout(remaining);
        } on TimeoutException {
          // 未完成的观察仍留在 _attempts 并持有许可。
        }
      }
    }
    return _report();
  }

  /// 只重试原生收束，绝不重放业务写入或创建句柄。
  Future<CloseReport> retryCleanup() async {
    for (final attempt in List.of(_attempts.values)) {
      final cleaning = attempt.cleaning;
      if (cleaning != null) {
        await cleaning;
      } else if (attempt.cleanupError != null && attempt.connection != null) {
        await _cleanup(attempt);
      } else if (attempt.retired && attempt.connection != null) {
        final task = attempt.task;
        if (task != null) await task;
      }
    }
    return _report();
  }

  /// join 已退役的 attempt，但不永久关闭这条逻辑连接。
  Future<CloseReport> joinRetired({DateTime? deadline}) async {
    final retired = [
      for (final attempt in _attempts.values)
        if (attempt.retired) attempt,
    ];
    final tasks = <Future<void>>[
      for (final attempt in retired)
        if (attempt.task case final task?) task,
    ];
    if (deadline == null) {
      await Future.wait(tasks);
    } else {
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        try {
          await Future.wait(tasks).timeout(remaining);
        } on TimeoutException {
          // 这些任务在期限后仍由同一 attempt 持有。
        }
      }
    }
    return CloseReport(unresolved: _unresolved(retired));
  }

  List<UnresolvedResource> _unresolved(Iterable<_TimelineAttempt> attempts) => [
    for (final attempt in attempts)
      if (_attempts.containsKey(attempt.id))
        UnresolvedResource(
          owner: threadId,
          attemptId: attempt.id,
          reason: attempt.cleanupError ?? const StaleTimelineAttempt(),
        ),
  ];

  /// 只报告已退役或带收束失败的观察：健康的活动 attempt 不是 unresolved。
  CloseReport _report() => CloseReport(
    unresolved: _unresolved([
      for (final attempt in _attempts.values)
        if (attempt.retired || attempt.cleanupError != null) attempt,
    ]),
  );

  /// 每观察的连续性副本上限：只保留有限身份/版本，不另留事件日志（design/26 §26.7）。
  static const int continuityItems = 100;
}

/// 一个展示代次的查询 scope：捕获连接 attempt，退役后拒绝新工作与迟到发布。
final class StudioTimelineQueryScope {
  StudioTimelineQueryScope._({
    required StudioTimelineChannel channel,
    required _TimelineAttempt attempt,
    required this.generation,
    required int sequence,
  }) : _channel = channel,
       _attempt = attempt,
       _label = '$sequence';

  final StudioTimelineChannel _channel;
  final _TimelineAttempt _attempt;
  final String _label;

  /// 展示代次身份（由展示 owner 给出，只用于诊断与预算归属）。
  final int generation;

  final Set<Future<void>> _accepted = {};
  int _querySequence = 0;
  bool _retired = false;

  AttemptId get attemptId => _attempt.id;
  String get threadId => _channel.threadId;
  int get pendingQueries => _accepted.length;
  bool get isActive => !_retired && _channel._isAttemptLive(_attempt);

  /// 读一页：无状态 keyset 页，不推进订阅基线。
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    final resolved = limit ?? timelinePageDefaultLimit;
    if (resolved < 1 || resolved > timelinePageMaxLimit) {
      return Future.error(_pageArgumentFailure);
    }
    return _run(
      'page',
      (connection) => connection.page(before: before, limit: resolved),
    );
  }

  /// 读取一段字段正文；后续块由调用方在 scope 仍活动时继续请求。
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    final maxBytes = query.maxBytes;
    if (maxBytes != null &&
        (maxBytes < timelineDetailMinBytes ||
            maxBytes > timelineDetailMaxBytes)) {
      return Future.error(_detailArgumentFailure);
    }
    return _run(
      'detail',
      (connection) => connection.readDetail(itemId: itemId, query: query),
    );
  }

  Future<T> _run<T>(
    String kind,
    Future<T> Function(StudioTimelineConnection connection) query,
  ) {
    if (!isActive) return Future.error(const StaleTimelineScope());
    final connection = _attempt.connection;
    if (connection == null) return Future.error(const StaleTimelineAttempt());
    final ResourcePermit permit;
    try {
      permit = _channel.budget.acquire(
        ResourceKind.pendingOperation,
        owner:
            'timeline-$kind:${_channel.threadId}:$generation:${++_querySequence}',
      );
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    // The external query may synchronously retire/close this scope. Admit its
    // real join before invoking transport, not after its first callback.
    final completion = Completer<void>();
    final joined = completion.future;
    _accepted.add(joined);
    final task = _execute(connection, query, permit);
    unawaited(
      task
          .then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {
              // 调用方持有这次查询的错误；join 路径只等它真正结束。
            },
          )
          .whenComplete(() {
            _accepted.remove(joined);
            completion.complete();
          }),
    );
    return task;
  }

  Future<T> _execute<T>(
    StudioTimelineConnection connection,
    Future<T> Function(StudioTimelineConnection connection) query,
    ResourcePermit permit,
  ) async {
    try {
      final result = await query(connection);
      // 迟到的回包不写新一代展示：scope 或 attempt 已退役即拒绝发布。
      if (!isActive) throw const StaleTimelineScope();
      return result;
    } catch (_) {
      if (!isActive) throw const StaleTimelineScope();
      rethrow;
    } finally {
      permit.release();
    }
  }

  /// 停止接受新查询并拒绝迟到发布；已受理查询由其自身 future 收束。
  void retire() {
    // scope 属于开它的 attempt：这里只拒绝新工作与迟到发布，**不**从“当前 attempt”
    // 顺手摘掉自己，也不清空集合——那会让 channel 的 join 看不到在途查询。
    _retired = true;
  }

  /// 等待已经受理的查询退出；提前放弃等待不放走仍在活动的许可。
  ///
  /// 每次调用都重新结算当前在途查询，不缓存旧 deadline 下的未完成报告：否则后续清理
  /// 永远读不到真实完成，也无法归还许可（design/26 §26.8）。
  Future<CloseReport> close({DateTime? deadline}) => _join(deadline);

  Future<CloseReport> _join(DateTime? deadline) async {
    if (!_retired) retire();
    final pending = List.of(_accepted);
    if (pending.isEmpty) {
      _deregister();
      return CloseReport();
    }
    if (deadline == null) {
      await Future.wait(pending);
      _deregister();
      return CloseReport();
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) return _pendingReport(pending.length);
    var timedOut = false;
    try {
      await Future.wait(pending).timeout(remaining);
    } on TimeoutException {
      timedOut = true;
    }
    if (!timedOut) {
      _deregister();
      return CloseReport();
    }
    return _pendingReport(_accepted.length);
  }

  /// 真实 join 干净后解除连接归属：已确认退出的 scope 不再积压到整条连接关闭，
  /// 仍在途或清理失败的 scope 继续保留归属与许可（design/26 §26.8）。
  void _deregister() => _attempt.scopes.remove(this);

  CloseReport _pendingReport(int pending) => CloseReport(
    unresolved: [
      for (var index = 0; index < pending; index++)
        UnresolvedResource(
          owner: 'timeline-query:${_channel.threadId}:$generation',
          attemptId: _attempt.id,
          reason: StateError(
            'A timeline query is still in flight after the deadline',
          ),
        ),
    ],
  );

  @override
  String toString() =>
      'StudioTimelineQueryScope(${_channel.threadId}#$generation:$_label)';
}

final class _TimelineAttempt {
  _TimelineAttempt({
    required this.id,
    required this.demandVersion,
    required this.permit,
  });

  final AttemptId id;
  final int demandVersion;
  final ResourcePermit permit;
  StudioTimelineConnection? connection;
  Future<void>? task;
  bool retired = false;
  bool closeRequested = false;
  Object? cleanupError;
  Future<bool>? cleaning;
  String? subscriptionId;
  int? version;

  /// 有界连续性副本：只记身份与内容版本，不持有正文。
  final Map<String, int> identities = {};
  final Set<StudioTimelineQueryScope> scopes = {};

  void adopt(StudioTimelineBaseline baseline) {
    subscriptionId = baseline.subscriptionId;
    version = baseline.version;
    identities.clear();
    for (final item in baseline.items) {
      remember(item.id, item.revision);
    }
  }

  void remember(String itemId, int revision) {
    // 只保留最近登记的有限身份；退出副本不等于删除通知。
    if (identities.length >= StudioTimelineChannel.continuityItems &&
        !identities.containsKey(itemId)) {
      identities.remove(identities.keys.first);
    }
    identities[itemId] = revision;
  }

  /// 退役所有已开 scope：只拒绝新工作与迟到发布，集合留给真实 join 逐个移除。
  void retireScopes() {
    for (final scope in scopes) {
      scope.retire();
    }
  }
}
