import 'dart:async';
import 'dart:convert';

import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';
import '../domain/content_state.dart';
import '../domain/content_lifecycle.dart';
import '../domain/conversation_repository.dart';
import '../domain/page_coverage.dart';
import 'item_reducer.dart';
import 'input_turn_facts.dart';
import '../../../conversation_ports.dart';

part 'page_coverage.dart';

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
/// 这里没有窗口控制面：page/detail 是有类型返回值的查询（见 [ConversationQueryScopeImpl]），
/// 不通过“等待下一个窗口版本确认操作完成”收束。观察 [state] 从不改变 demand；新 attempt
/// 也绝不把补丁折算到另一个 attempt 的已交付基线（design/26 §26.8）。
final class ConversationContentImpl implements ConversationContent {
  ConversationContentImpl({
    required this.threadId,
    required ConversationTransport transport,
    ResourceBudget? budget,
    this.retryPolicy = const RetryPolicy(),
    required this.onState,
    required this.onFailure,
    required this.onAttempt,
    required this.inputFacts,
  }) : _transport = transport,
       budget = budget ?? ResourceBudget(),
       _state = LatestValue<ChatUiState<ConversationContentFrame>>(
         ChatIdle<ConversationContentFrame>(threadId),
       );

  final String threadId;
  final ConversationTransport _transport;
  final ResourceBudget budget;
  final RetryPolicy retryPolicy;
  final LatestValue<ChatUiState<ConversationContentFrame>> _state;
  @override
  ValueObservation<ChatUiState<ConversationContentFrame>> get state => _state;
  final void Function(AttemptId attemptId, ThreadStreamFrame frame) onState;
  final void Function(AttemptId attemptId, Object error, bool exhausted)
  onFailure;
  final void Function(AttemptId attemptId) onAttempt;
  final InputFactRegistry inputFacts;
  final Object _coverageIssuer = Object();

  InputTurnFact? _inputFact(ConversationItem item, String inputId) {
    final descriptor = item.descriptor;
    if (descriptor is! ConversationTurnDescriptor ||
        descriptor.value.inputId != inputId)
      return null;
    return InputTurnFact(
      threadId: threadId,
      inputId: inputId,
      itemId: item.id,
      turnId: item.header.turnId,
      status: descriptor.value.state.status,
      saved: item.saved,
    );
  }

  void seedInputFacts(String inputId, void Function(InputTurnFact) onFact) {
    final attempt = _current;
    if (attempt == null || !_isCurrent(attempt)) return;
    for (final item in List.of(attempt.items.values)) {
      if (!_isCurrent(attempt)) return;
      final fact = _inputFact(item, inputId);
      if (fact != null) onFact(fact);
    }
  }

  void _publishInputFacts(
    _TimelineAttempt attempt,
    Iterable<ConversationItem> items,
  ) {
    for (final item in items) {
      if (!_isCurrent(attempt)) return;
      final descriptor = item.descriptor;
      if (descriptor is! ConversationTurnDescriptor) continue;
      final inputId = descriptor.value.inputId;
      if (inputId == null || !inputFacts.isWatching(inputId)) continue;
      inputFacts.publish(_inputFact(item, inputId)!);
    }
  }

  @override
  ConversationItem mergeItem(
    ConversationItem current,
    ConversationItem incoming,
  ) => mergeConversationItem(current, incoming);
  @override
  ConversationItem reduceItem(
    ConversationItem current,
    ConversationUpdateItem update,
  ) => reduceConversationItem(current, update);

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
  ConversationContentFrame? _lastFrame;
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
      _state.publish(ChatIdle<ConversationContentFrame>(threadId));
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
  ConversationContentFrame? get lastDeliveredFrame => _lastFrame;

  /// 等待当前 attempt 的成功基线（或它的 typed 失败）。
  Future<ConversationBaselineFrame> get ready async {
    final attempt = _current;
    if (attempt == null || !_isCurrent(attempt)) {
      final currentState = state.value;
      if (currentState is ChatFailed<ConversationContentFrame>) {
        throw currentState.error;
      }
      throw const StaleConversationAttempt();
    }
    final result = await state.waitFor(
      (value) =>
          !_isCurrent(attempt) ||
          value is ChatReady<ConversationContentFrame> ||
          value is ChatReconnecting<ConversationContentFrame> ||
          value is ChatFailed<ConversationContentFrame>,
    );
    if (!_isCurrent(attempt)) throw const StaleConversationAttempt();
    if (result is ChatReady<ConversationContentFrame>) {
      final frame = result.snapshot;
      if (frame is ConversationBaselineFrame) return frame;
      throw const StaleConversationAttempt();
    }
    if (result is ChatReconnecting<ConversationContentFrame>)
      throw result.error;
    if (result is ChatFailed<ConversationContentFrame>) throw result.error;
    throw const StaleConversationAttempt();
  }

  /// 为当前 attempt 开一个展示代次的查询 scope；没有活动 attempt 时返回 null。
  ///
  /// [generation] 由展示 owner 给出，只用于诊断与预算归属，不参与业务判定。
  ConversationQueryScope? openScope({
    required int generation,
    ConversationPageCoverage? coverage,
  }) {
    if (_closed) return null;
    final attempt = _current;
    if (attempt == null || !_isCurrent(attempt)) return null;
    final _PageCoverage? qualified;
    if (coverage == null) {
      qualified = null;
    } else {
      if (coverage is! _PageCoverage || !_ownsCoverage(attempt, coverage)) {
        throw const ConversationContinuityError('invalid page coverage');
      }
      qualified = coverage;
    }
    final scope = ConversationQueryScopeImpl._(
      channel: this,
      attempt: attempt,
      generation: generation,
      sequence: ++_scopeSequence,
      coverage: qualified,
    );
    attempt.scopes.add(scope);
    return scope;
  }

  bool _ownsCoverage(_TimelineAttempt attempt, _PageCoverage coverage) =>
      identical(coverage.issuer, _coverageIssuer) &&
      coverage.threadId == threadId &&
      coverage.attemptId == attempt.id &&
      coverage.subscriptionId == attempt.subscriptionId &&
      coverage.epoch == attempt.historyEpoch;

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
      _state.publish(
        ChatFailed<ConversationContentFrame>(
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
    // Reentrant publication can close immediately: its join must already exist.
    final completion = Completer<void>();
    attempt.task = completion.future;
    _current = attempt;
    _attempts[id] = attempt;
    completion.complete(Future<void>.sync(() => _run(attempt)));
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
      if (!_isCurrent(attempt)) return;
      _state.publish(
        ChatOpening<ConversationContentFrame>(threadId, lastGood: _lastFrame),
      );
      if (_isCurrent(attempt)) onAttempt(attempt.id);
      if (!_isCurrent(attempt)) return;
      final connection = await _transport.openConversationFeed(threadId);
      attempt.connection = connection;
      if (!_isCurrent(attempt)) return;
      if (connection.threadId != threadId ||
          connection.subscriptionId.isEmpty) {
        throw const ConversationContinuityError('feed identity mismatch');
      }
      attempt.subscriptionId = connection.subscriptionId;
      // A single ordered consumer, bounded by the native two-credit window.
      // No async listen callback or application-side event queue.
      await for (final envelope in connection.events) {
        if (!_isCurrent(attempt)) return;
        if (envelope.threadId != threadId ||
            envelope.subscriptionId != connection.subscriptionId) {
          throw const ConversationContinuityError('frame identity mismatch');
        }
        final event = envelope.event;
        if (event is ConversationFailureEvent) throw event.failure;
        if (event is ConversationClosedEvent)
          throw const ConversationStreamEnded();
        if (envelope.deliverySequence != attempt.deliverySequence + 1) {
          throw const ConversationContinuityError(
            'delivery sequence is not continuous',
          );
        }
        switch (event) {
          case ConversationStateEvent(:final frame):
            onState(attempt.id, frame);
          case ConversationBaselineEvent(:final baseline):
            if (attempt.version != null) {
              throw const ConversationContinuityError(
                'duplicate initial baseline',
              );
            }
            final frame = _adoptBaseline(attempt, baseline);
            if (!_isCurrent(attempt)) return;
            attempt.permit.mark(ResourcePhase.active);
            _lastFrame = frame;
            _state.publish(
              ChatReady<ConversationContentFrame>(threadId, frame),
            );
          case ConversationUpdateEvent(:final update):
            final frame = _reduce(attempt, update);
            if (!_isCurrent(attempt)) return;
            _lastFrame = frame;
            _state.publish(
              ChatReady<ConversationContentFrame>(threadId, frame),
            );
            _retries = 0;
          case ConversationFailureEvent() || ConversationClosedEvent():
            throw const ConversationStreamEnded();
        }
        // Synchronous publication above has completed before ACK. A listener
        // can revoke demand reentrantly; retirement never waits on this ACK.
        if (!_isCurrent(attempt)) return;
        // Retirement revokes delivery, not native ownership. An in-flight ACK
        // cannot hold close hostage; _cleanup still joins the actual feed and
        // every accepted query before releasing its permit.
        final revocation = Completer<void>();
        attempt.ackRevocation = revocation;
        try {
          await Future.any<void>([
            connection.acknowledge(envelope.deliverySequence),
            revocation.future,
          ]);
        } finally {
          // Complete the per-delivery signal even on success: a single signal
          // kept for the entire attempt would accumulate one listener per ACK.
          if (!revocation.isCompleted) revocation.complete();
          attempt.ackRevocation = null;
        }
        if (!_isCurrent(attempt)) return;
        attempt.deliverySequence = envelope.deliverySequence;
      }
      if (_isCurrent(attempt)) throw const ConversationStreamEnded();
    } catch (error) {
      if (_isCurrent(attempt)) {
        failure = error;
        final canRetry = _retries < retryPolicy.delays.length;
        onFailure(attempt.id, error, !canRetry);
        if (!_isCurrent(attempt)) return;
        _state.publish(
          canRetry
              ? ChatReconnecting<ConversationContentFrame>(
                  threadId,
                  lastGood: _lastFrame,
                  error: error,
                )
              : ChatFailed<ConversationContentFrame>(
                  threadId,
                  lastGood: _lastFrame,
                  error: error,
                ),
        );
      }
    } finally {
      if (identical(_current, attempt)) _current = null;
      attempt.retired = true;
      attempt.items.clear();
      attempt.proofs.clear();
      final cleaned = await (attempt.retirementCleanup ?? _cleanup(attempt));
      if (failure != null &&
          !_closed &&
          _demand &&
          attempt.demandVersion == _demandVersion &&
          _current == null) {
        if (cleaned) {
          _scheduleRetry(attempt.demandVersion);
        } else {
          _state.publish(
            ChatFailed<ConversationContentFrame>(
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
  ConversationBaselineFrame _adoptBaseline(
    _TimelineAttempt attempt,
    ConversationBaseline baseline, {
    ConversationResyncReason? resyncReason,
  }) {
    if (baseline.version < 0 ||
        (attempt.version != null && baseline.version < attempt.version!) ||
        baseline.hasOlder != (baseline.before != null)) {
      throw const ConversationContinuityError(
        'baseline version or cursor is invalid',
      );
    }
    final known = attempt.subscriptionId;
    if (known != null && known != baseline.subscriptionId) {
      throw const ConversationContinuityError(
        'baseline changed subscription identity',
      );
    }
    validateConversationItems(baseline.items, threadId: threadId, maxItems: 32);
    baseline = ConversationBaseline(
      subscriptionId: baseline.subscriptionId,
      version: baseline.version,
      items: List.unmodifiable(baseline.items.map(immutableConversationItem)),
      before: baseline.before,
      hasOlder: baseline.hasOlder,
    );
    attempt.adopt(baseline);
    attempt.historyEpoch++;
    attempt.proofs.clear();
    final membership = Object();
    for (final item in baseline.items) {
      attempt.proofs.item(
        item,
        attempt.changeSequence,
        deliveredMembership: membership,
        deliveredBaselineVersion: baseline.version,
      );
    }
    attempt.items
      ..clear()
      ..addAll(
        boundConversationTail(
          baseline.items,
          maxBytes: 8 * 1024 * 1024 - attempt.proofs.retainedBytes,
        ),
      );
    if (inputFacts.hasObservers) {
      _publishInputFacts(attempt, attempt.items.values.toList(growable: false));
    }
    return ConversationBaselineFrame(
      baseline,
      pageCoverage: _PageCoverage(
        issuer: _coverageIssuer,
        threadId: threadId,
        attemptId: attempt.id,
        subscriptionId: baseline.subscriptionId,
        epoch: attempt.historyEpoch,
        baselineVersion: baseline.version,
        membership: membership,
        lower: baseline.items.isEmpty ? null : _pageKey(baseline.items.first),
        upper: baseline.items.isEmpty ? null : _pageKey(baseline.items.last),
        before: baseline.before,
        hasOlder: baseline.hasOlder,
      ),
      resyncReason: resyncReason,
    );
  }

  /// 把 transport 的一帧更新折算为交付帧；无法证明连续就显式失败（不是猜删除）。
  ConversationContentFrame _reduce(
    _TimelineAttempt attempt,
    ConversationUpdate update,
  ) {
    if (update is ConversationPatch) {
      validateConversationPatchBudget(update);
      update = immutableConversationPatch(update);
    }
    switch (update) {
      case ConversationResync(
        :final subscriptionId,
        :final reason,
        :final baseline,
      ):
        if (attempt.subscriptionId != null &&
            attempt.subscriptionId != subscriptionId) {
          throw const ConversationContinuityError(
            'resync changed subscription identity',
          );
        }
        return _adoptBaseline(attempt, baseline, resyncReason: reason);
      case ConversationPatch(
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
          throw const ConversationContinuityError(
            'patch does not continue the delivered version',
          );
        }
        if (to <= from) {
          throw const ConversationContinuityError('patch did not advance');
        }
        // Validate the entire batch against a local candidate. No partial commit
        // of revision/header/descriptor/fields or version can escape on failure.
        final candidate = Map<String, ConversationItem>.of(attempt.items);
        for (final change in changes) {
          switch (change) {
            case ConversationAdd(:final item):
              validateConversationItems([item], threadId: threadId);
              final known = candidate[item.id];
              candidate[item.id] = known == null
                  ? immutableConversationItem(item)
                  : mergeConversationItem(known, item);
            case ConversationUpdateItem(:final itemId):
              final known = candidate[itemId];
              if (known != null) {
                candidate[itemId] = reduceConversationItem(known, change);
              } else if (change.revision < change.expectedRevision) {
                throw const ConversationContinuityError('revision regressed');
              }
            case ConversationRemove(:final itemId):
              candidate.remove(itemId);
          }
        }
        final proofs = attempt.proofs.copy();
        var sequence = attempt.changeSequence;
        for (final change in changes) {
          proofs.change(change, ++sequence);
        }
        attempt.items
          ..clear()
          ..addAll(
            boundConversationTail(
              candidate.values,
              maxBytes: 8 * 1024 * 1024 - proofs.retainedBytes,
            ),
          );
        attempt.proofs = proofs;
        attempt.changeSequence = sequence;
        attempt.version = to;
        // The complete candidate has committed; inspect reduced items, never
        // replay raw field deltas in drafts. Capture even a changed Turn that
        // was evicted by this same batch's bounded-tail admission.
        if (inputFacts.hasObservers) {
          final changedIds = <String>{
            for (final change in changes)
              switch (change) {
                ConversationAdd(:final item) => item.id,
                ConversationUpdateItem(:final itemId) ||
                ConversationRemove(:final itemId) => itemId,
              },
          };
          _publishInputFacts(attempt, [
            for (final id in changedIds)
              if (candidate[id] case final item?) item,
          ]);
        }
        return ConversationPatchFrame(update);
    }
  }

  void _retire(_TimelineAttempt attempt) {
    attempt.retired = true;
    final ackRevocation = attempt.ackRevocation;
    if (ackRevocation != null && !ackRevocation.isCompleted)
      ackRevocation.complete();
    attempt.items.clear();
    attempt.proofs.clear();
    if (identical(_current, attempt)) _current = null;
    attempt.permit.mark(ResourcePhase.retiring);
    attempt.retireScopes();
    _requestClose(attempt);
    if (attempt.connection != null) {
      final cleanup = attempt.retirementCleanup ??= _cleanup(attempt);
      unawaited(cleanup.then<void>((_) {}));
    }
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
    final scopeJoins = <ConversationQueryScopeImpl, Future<CloseReport>>{
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
    _state.publish(ChatClosed<ConversationContentFrame>(threadId));
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
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    for (final attempt in List.of(_attempts.values)) {
      if (deadline != null && !deadline.isAfter(DateTime.now())) break;
      final cleaning = attempt.cleaning;
      Future<void>? joining;
      if (cleaning != null) {
        joining = cleaning.then<void>((_) {});
      } else if (attempt.cleanupError != null && attempt.connection != null) {
        joining = _cleanup(attempt).then<void>((_) {});
      } else if (attempt.retired) {
        joining = attempt.task;
      }
      if (joining == null) continue;
      if (deadline == null) {
        await joining;
      } else {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        try {
          await joining.timeout(remaining);
        } on TimeoutException {
          // This is only a bounded join. Original work and permits stay owned.
          break;
        }
      }
    }
    return _report();
  }

  /// join 已退役的 attempt，但不永久关闭这条逻辑连接。
  @override
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
          reason: attempt.cleanupError ?? const StaleConversationAttempt(),
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
final class ConversationQueryScopeImpl implements ConversationQueryScope {
  ConversationQueryScopeImpl._({
    required ConversationContentImpl channel,
    required _TimelineAttempt attempt,
    required this.generation,
    required int sequence,
    required _PageCoverage? coverage,
  }) : _channel = channel,
       _attempt = attempt,
       _label = '$sequence',
       _coverage = coverage;

  final ConversationContentImpl _channel;
  final _TimelineAttempt _attempt;
  final String _label;
  _PageCoverage? _coverage;
  @override
  ConversationPageCoverage? get pageCoverage => _coverage;

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
  Future<ConversationPage> page({String? before, int? limit}) {
    final resolved = limit ?? conversationPageDefaultLimit;
    if (resolved < 1 || resolved > conversationPageMaxLimit) {
      return Future.error(_pageArgumentFailure);
    }
    final ticket = _coverage;
    if (ticket != null &&
        (!_channel._ownsCoverage(_attempt, ticket) ||
            !ticket.hasOlder ||
            before != ticket.before)) {
      return Future.error(
        const ConversationContinuityError('invalid page cursor coverage'),
      );
    }
    return _run('page', (connection) async {
      final result = await connection.page(before: before, limit: resolved);
      if (result.items.length > resolved) {
        throw const ConversationContinuityError(
          'page exceeded requested limit',
        );
      }
      return result;
    }, coverage: ticket);
  }

  /// 读取一段字段正文；后续块由调用方在 scope 仍活动时继续请求。
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) {
    final maxBytes = query.maxBytes;
    if (maxBytes != null &&
        (maxBytes < conversationDetailMinBytes ||
            maxBytes > conversationDetailMaxBytes)) {
      return Future.error(_detailArgumentFailure);
    }
    return _run('detail', (connection) async {
      final result = await connection.readDetail(itemId: itemId, query: query);
      if (result.itemId != itemId ||
          result.field != query.field ||
          result.revision != query.revision ||
          utf8.encode(result.text).length > (query.maxBytes ?? 65536) ||
          utf8.encode(result.text).length > result.totalBytes ||
          result.continuation != null &&
              result.continuation == query.continuation) {
        throw const ConversationContinuityError(
          'detail identity, length or continuation mismatch',
        );
      }
      return result;
    });
  }

  Future<T> _run<T>(
    String kind,
    Future<T> Function(ConversationFeed connection) query, {
    _PageCoverage? coverage,
  }) {
    if (!isActive) return Future.error(const StaleConversationScope());
    final connection = _attempt.connection;
    if (connection == null)
      return Future.error(const StaleConversationAttempt());
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
    final completion = Completer<T>();
    final task = completion.future;
    late final Future<void> joined;
    joined = task
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            // 调用方持有这次查询的错误；join 路径只等它真正结束。
          },
        )
        .whenComplete(() {
          _accepted.remove(joined);
        });
    _accepted.add(joined);
    // Transport callbacks may synchronously close this scope. Its exact join
    // responsibility must already be visible, including synchronous failures.
    completion.complete(
      Future<T>.sync(() => _execute(connection, query, permit, coverage)),
    );
    return task;
  }

  Future<T> _execute<T>(
    ConversationFeed connection,
    Future<T> Function(ConversationFeed connection) query,
    ResourcePermit permit,
    _PageCoverage? coverage,
  ) async {
    final readSequence = _attempt.changeSequence;
    final readEpoch = _attempt.historyEpoch;
    try {
      final result = await query(connection);
      // 迟到的回包不写新一代展示：scope 或 attempt 已退役即拒绝发布。
      if (!isActive) throw const StaleConversationScope();
      if (result is ConversationPage) {
        if (result.hasOlder != (result.before != null)) {
          throw const ConversationContinuityError(
            'page cursor does not match hasOlder',
          );
        }
        validateConversationItems(result.items, threadId: threadId);
        if (_attempt.historyEpoch != readEpoch ||
            _attempt.proofs.lostSequence > readSequence ||
            _attempt.changeSequence - readSequence > 100) {
          throw const ConversationContinuityError(
            'page continuity requires resync',
          );
        }
        final candidate = {for (final item in result.items) item.id: item};
        if (coverage != null) {
          if (!identical(_coverage, coverage) ||
              !_channel._ownsCoverage(_attempt, coverage)) {
            throw const ConversationContinuityError(
              'page coverage was superseded',
            );
          }
          _validateCoveragePage(coverage, result, readSequence);
        }
        for (final change in _attempt.proofs.entries.values) {
          if (change.sequence <= readSequence && coverage == null) continue;
          if (change.removed) {
            candidate.remove(change.id);
            continue;
          }
          if (change.sequence <= readSequence) continue;
          final current = _attempt.items[change.id];
          var previous = candidate[change.id];
          if (change.lastRemoval > readSequence) {
            candidate.remove(change.id);
            previous = null;
          }
          if (current == null) {
            // No second history mirror or body replay log is retained to guess.
            throw const ConversationContinuityError(
              'page changed outside bounded tail',
            );
          }
          if (previous != null) {
            candidate[current.id] = mergeConversationItem(previous, current);
          } else if (_concurrentItemInPage(current, result, coverage)) {
            candidate[current.id] = current;
          }
        }
        // Even a non-overlapping concurrent frame can improve a same-revision
        // preview; reconcile overlap without retaining this historical page.
        for (final entry in candidate.entries.toList()) {
          final current = _attempt.items[entry.key];
          if (current != null)
            candidate[entry.key] = mergeConversationItem(entry.value, current);
        }
        final merged = candidate.values.toList()
          ..sort(compareConversationItems);
        validateConversationItems(merged, threadId: threadId);
        if (coverage != null) {
          // No await or callback between validation and this atomic commit.
          final proofs = _attempt.proofs.copy();
          final membership = Object();
          proofs.transferMembership(coverage.membership, membership);
          for (final item in merged) {
            proofs.item(
              item,
              proofs.entries[item.id]?.sequence ?? 0,
              deliveredMembership: membership,
              deliveredBaselineVersion: coverage.baselineVersion,
            );
          }
          final tail = boundConversationTail(
            _attempt.items.values,
            maxBytes: 8 * 1024 * 1024 - proofs.retainedBytes,
          );
          _attempt.proofs = proofs;
          _attempt.items
            ..clear()
            ..addAll(tail);
          _coverage = coverage.advance(
            result,
            membership: membership,
            reconciled: merged,
          );
        }
        return ConversationPage(
          items: List.unmodifiable(merged.map(immutableConversationItem)),
          before: result.before,
          hasOlder: result.hasOlder,
        ) as T;
      }
      if (result is ConversationDetailChunk) {
        if (result.totalBytes < 0 || result.revision < 0) {
          throw const ConversationContinuityError('invalid detail lengths');
        }
      }
      return result;
    } catch (_) {
      // 查询失败也遵守同一退役边界：scope 已退役时不让迟到失败进入新代次；
      // 活跃 scope 的原始 typed 错误原样传播。
      if (!isActive) throw const StaleConversationScope();
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
      'ConversationQueryScopeImpl(${_channel.threadId}#$generation:$_label)';
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
  ConversationFeed? connection;
  Future<void>? task;
  Completer<void>? ackRevocation;
  bool retired = false;
  bool closeRequested = false;
  Object? cleanupError;
  Future<bool>? cleaning;
  Future<bool>? retirementCleanup;
  String? subscriptionId;
  int? version;

  /// 有界连续性副本：只记身份与内容版本，不持有正文。
  final Map<String, ConversationItem> items = {};
  int deliverySequence = 0;
  int historyEpoch = 0;
  int changeSequence = 0;
  _PageProofs proofs = _PageProofs();
  final Set<ConversationQueryScopeImpl> scopes = {};

  void adopt(ConversationBaseline baseline) {
    subscriptionId = baseline.subscriptionId;
    version = baseline.version;
    items
      ..clear()
      ..addAll(boundConversationTail(baseline.items));
  }

  /// 退役所有已开 scope：只拒绝新工作与迟到发布，集合留给真实 join 逐个移除。
  void retireScopes() {
    for (final scope in scopes) {
      scope.retire();
    }
  }
}
