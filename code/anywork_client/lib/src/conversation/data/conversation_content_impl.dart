import 'dart:async';
import 'dart:developer' as developer;

import '../../../models.dart';
import '../../../conversation_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';
import '../domain/content_lifecycle.dart';
import '../domain/content_state.dart';
import '../domain/conversation_repository.dart';
import 'conversation_read_scope.dart';

/// Owns feed admission, delivery, ACK and actual retirement, but no history window.
final class ConversationContentImpl implements ConversationContent {
  ConversationContentImpl({
    required this.threadId,
    required ConversationTransport transport,
    required this.budget,
    required this.onState,
    required this.onFailure,
    required this.onAttempt,
    this.scope = const MainChatScope(),
    this.initialDemand,
  }) : _transport = transport,
       _state = LatestValue(ChatIdle<bool>(threadId));
  @override
  final String threadId;
  final ConversationTransport _transport;
  final ResourceBudget budget;
  final void Function(AttemptId, ThreadStreamFrame) onState;
  final void Function(AttemptId, Object, bool) onFailure;
  final void Function(AttemptId) onAttempt;
  final ChatScope scope;
  final ReadDemand? initialDemand;
  final LatestValue<CurrentProjection?> _projection = LatestValue(null);
  final LatestValue<ChatUiState<bool>> _state;
  @override
  ValueObservation<ChatUiState<bool>> get state => _state;
  @override
  ValueObservation<CurrentProjection?> get current => _projection;
  final Map<AttemptId, _Attempt> _attempts = {};
  final Set<ConversationReadScope> _scopes = {};
  _Attempt? _current;
  _ConsumerLease? _consumer;
  Completer<void>? _consumerAvailable;
  int _nextAttempt = 0;
  bool _demand = false;
  bool _closed = false;
  int _demandVersion = 0;
  int _retries = 0;
  Timer? _retryTimer;
  Future<CloseReport>? _closing;
  Observation? _availability;
  @override
  bool get hasDemand => _demand;
  @override
  bool get isClosed => _closed;
  @override
  AttemptId? get currentAttemptId => _current?.id;
  @override
  int get ownedAttemptCount => _attempts.length;

  @override
  Future<void> get ready async {
    final value = _state.value;
    if (value is ChatReady<bool>) return;
    if (value is ChatFailed<bool>) throw value.error;
    final next = await _state.waitFor(
      (value) =>
          value is ChatReady<bool> ||
          value is ChatFailed<bool> ||
          value is ChatClosed<bool>,
    );
    if (next is ChatFailed<bool>) throw next.error;
    if (next is ChatClosed<bool>) throw const ConversationStreamEnded();
  }

  @override
  Observation attachConsumer(
    ConversationBatchConsumer consumer, {
    required ReadDemand demand,
  }) {
    if (_closed) throw StateError('Conversation is closed');
    if (_consumer != null)
      throw StateError('Completion consumer already attached');
    final lease = _ConsumerLease(this, consumer, demand);
    _consumer = lease;
    final waiter = _consumerAvailable;
    _consumerAvailable = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    if (_demand && _current == null) _open();
    return lease;
  }

  void _detach(_ConsumerLease lease) {
    if (!identical(_consumer, lease)) return;
    _consumer = null;
    _demandVersion++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _availability?.cancel();
    _availability = null;
    final current = _current;
    if (current != null) _retire(current);
    if (!_closed && _consumer == null && _current == null) {
      _state.publish(ChatIdle<bool>(threadId));
    }
  }

  void setDemand(bool value) {
    if (_closed && value) throw StateError('Conversation is closed');
    if (_demand == value) return;
    _demand = value;
    _demandVersion++;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!value) {
      _availability?.cancel();
      _availability = null;
      final current = _current;
      if (current != null) _retire(current);
      _state.publish(ChatIdle<bool>(threadId));
    } else {
      _retries = 0;
      _open();
    }
  }

  @override
  void refresh() {
    _demandVersion++;
    _retries = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    final current = _current;
    if (current != null) _retire(current);
    if (_demand && !_closed) _open();
  }

  @override
  ConversationQueryScope openScope({required int generation}) {
    if (_closed) throw StateError('Conversation is closed');
    final attempt = _current;
    final lease = _consumer;
    if (attempt == null ||
        attempt.feed == null ||
        lease == null ||
        !_live(attempt)) {
      throw const StaleConversationScope();
    }
    _scopes.removeWhere((scope) => scope.isSettled);
    late final ConversationReadScope scope;
    scope = ConversationReadScope(
      threadId: threadId,
      generation: generation,
      reader: attempt.feed!.reader,
      budget: budget,
      isEligible: () => _eligible(attempt, lease),
      applyOlder: (batch) => _enqueue(attempt, () async {
        if (!scope.isActive || !_eligible(attempt, lease)) {
          throw const StaleConversationScope();
        }
        await _deliver(attempt, lease, batch, queryScope: scope);
        if (!scope.isActive || !_eligible(attempt, lease)) {
          throw const StaleConversationScope();
        }
      }),
    );
    _scopes.add(scope);
    attempt.scopes.add(scope);
    return scope;
  }

  bool _live(_Attempt a) =>
      !_closed && _demand && !a.retired && identical(_current, a);
  bool _eligible(_Attempt a, _ConsumerLease lease) =>
      _live(a) && identical(_consumer, lease) && !lease.isCancelled;

  void _open() {
    if (_closed || !_demand || _current != null || _consumer == null) return;
    final id = AttemptId(++_nextAttempt);
    final ResourcePermit permit;
    try {
      permit = budget.acquire(
        ResourceKind.chatHandle,
        owner: '$threadId:${id.value}',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded catch (error) {
      _availability ??= budget.watchAvailability(ResourceKind.chatHandle, () {
        _availability?.cancel();
        _availability = null;
        _open();
      });
      _state.publish(ChatFailed<bool>(threadId, error: error));
      return;
    }
    final a = _Attempt(id, permit, _demandVersion, _consumer!);
    _attempts[id] = a;
    _current = a;
    final done = Completer<void>();
    a.task = done.future;
    done.complete(Future<void>.sync(() => _run(a)));
  }

  Future<void> _run(_Attempt a) async {
    try {
      _state.publish(ChatOpening<bool>(threadId));
      if (!_live(a)) return;
      onAttempt(a.id);
      if (!_live(a)) return;
      final feed = await _transport.openConversationFeed(
        threadId,
        scope: scope,
        demand: initialDemand ?? a.consumer.demand,
      );
      a.feed = feed;
      if (!_live(a)) return;
      if (feed.threadId != threadId || feed.subscriptionId.isEmpty)
        throw const ConversationContinuityError('feed identity mismatch');
      a.permit.mark(ResourcePhase.active);
      a.subscription = feed.events.listen(
        (frame) => _receive(a, frame),
        onError: (Object error, StackTrace stack) => _failAttempt(a, error),
        onDone: () => _failAttempt(a, const ConversationStreamEnded()),
      );
      await a.stopped.future;
    } catch (error) {
      if (_live(a)) {
        _failAttempt(a, error);
      }
    } finally {
      if (identical(_current, a)) _current = null;
      a.retired = true;
      await _cleanup(a);
      if (a.error != null &&
          !_closed &&
          _demand &&
          a.demandVersion == _demandVersion &&
          _current == null) {
        _state.publish(ChatFailed<bool>(threadId, error: a.error!));
      }
      if (a.failure != null &&
          !_closed &&
          _demand &&
          a.demandVersion == _demandVersion &&
          _current == null &&
          a.permit.isReleased) {
        _scheduleRetry();
      }
    }
  }

  void _receive(_Attempt a, ConversationFrame frame) {
    if (!_live(a)) return;
    final feed = a.feed!;
    if (frame.threadId != threadId ||
        frame.subscriptionId != feed.subscriptionId) {
      _failAttempt(
        a,
        const ConversationContinuityError('frame identity mismatch'),
      );
      return;
    }
    // Terminal frames reuse the last data sequence (including zero). They are
    // qualification barriers, not duplicate data and never consume/return credit.
    if (frame.event is ConversationFailureEvent ||
        frame.event is ConversationClosedEvent) {
      if (a.terminal) return;
      a.terminal = true;
      _failAttempt(a, switch (frame.event) {
        ConversationFailureEvent(:final failure) => failure,
        _ => const ConversationStreamEnded(),
      });
      return;
    }
    if (a.terminal) return;
    if (frame.deliverySequence != a.received + 1 ||
        a.ledger.length >= (a.acking ? 2 : 1)) {
      _failAttempt(
        a,
        const ConversationContinuityError(
          'delivery sequence or credit exceeded',
        ),
      );
      return;
    }
    a.received = frame.deliverySequence;
    a.ledger[frame.deliverySequence] = false;
    final work = _enqueue(a, () async {
      if (!_eligible(a, a.consumer)) return;
      switch (frame.event) {
        case ConversationStateEvent(:final frame):
          onState(a.id, frame);
        case ConversationChatEvent(:final batch):
          await _deliver(a, a.consumer, batch);
        case ConversationFailureEvent() || ConversationClosedEvent():
          throw const ConversationContinuityError('unexpected terminal');
      }
      if (!_eligible(a, a.consumer)) return;
      a.ledger[frame.deliverySequence] = true;
      _flushAck(a);
    });
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (_live(a)) _failAttempt(a, error);
        },
      ),
    );
  }

  /// The sole admission queue for State, streamed Chat and query Chat. Query IO
  /// starts before entering this queue, so a consumer await never blocks reads.
  Future<void> _enqueue(_Attempt a, Future<void> Function() operation) {
    final queued = Stopwatch()..start();
    final work = a.serial.then((_) {
      developer.Timeline.instantSync(
        'conversation.admission',
        arguments: {
          'threadId': threadId,
          'subscriptionId': a.feed?.subscriptionId ?? '',
          'queueWaitMicros': queued.elapsedMicroseconds,
        },
      );
      return operation();
    });
    // One failed operation must not leave unobserved errors on the queue tail.
    a.serial = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    a.pending.add(work);
    unawaited(a.serial.then((_) => a.pending.remove(work)));
    return work;
  }

  Future<void> _deliver(
    _Attempt a,
    _ConsumerLease lease,
    ChatBatch batch, {
    ConversationReadScope? queryScope,
  }) async {
    bool eligible() => _eligible(a, lease) && (queryScope?.isActive ?? true);
    if (!eligible()) return;
    await lease.consumer.applyBatch(batch);
    // Never consult a new selection/consumer after component acceptance.
    if (!eligible()) return;
    if (scope is MainChatScope && batch.current != null) {
      _projection.publish(batch.current);
    }
    if (!eligible()) return;
    if (batch.placement == ChatPlacement.set) {
      _retries = 0;
      _state.publish(ChatReady<bool>(threadId, true));
    }
  }

  void _flushAck(_Attempt a) {
    if (a.acking || !_live(a)) return;
    a.acking = true;
    final completion = Completer<void>();
    final task = completion.future;
    a.pending.add(task);
    completion.complete(
      Future<void>.sync(() async {
        while (_live(a) && a.ledger[a.acked + 1] == true) {
          final next = a.acked + 1;
          await a.feed!.acknowledge(next);
          if (!_live(a)) return;
          a.ledger.remove(next);
          a.acked = next;
        }
      }),
    );
    unawaited(
      task.then(
        (_) {
          a.pending.remove(task);
          a.acking = false;
          if (_live(a) && a.ledger[a.acked + 1] == true) _flushAck(a);
        },
        onError: (Object error, StackTrace stack) {
          a.pending.remove(task);
          a.acking = false;
          if (_live(a)) _failAttempt(a, error);
        },
      ),
    );
  }

  void _failAttempt(_Attempt a, Object error) {
    if (!_live(a)) return;
    a.failure = error;
    final exhausted = _retries >= const RetryPolicy().delays.length;
    onFailure(a.id, error, exhausted);
    if (!_live(a)) return;
    _state.publish(
      exhausted
          ? ChatFailed<bool>(threadId, error: error)
          : ChatReconnecting<bool>(threadId, error: error),
    );
    _retire(a);
  }

  void _scheduleRetry() {
    final delays = const RetryPolicy().delays;
    if (_retries >= delays.length) return;
    final version = _demandVersion;
    _retryTimer = Timer(delays[_retries++], () {
      _retryTimer = null;
      if (!_closed && _demand && version == _demandVersion) _open();
    });
  }

  void _retire(_Attempt a) {
    if (a.retired) return;
    a.retired = true;
    if (identical(_current, a)) _current = null;
    a.permit.mark(ResourcePhase.retiring);
    for (final scope in a.scopes) {
      scope.retire();
    }
    try {
      a.feed?.requestClose();
    } catch (error) {
      a.error = error;
    }
    final waiter = _consumerAvailable;
    _consumerAvailable = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    if (!a.stopped.isCompleted) a.stopped.complete();
  }

  Future<void> _cleanup(_Attempt a) async {
    a.cleanupFinished = false;
    a.permit.mark(ResourcePhase.retiring);
    Object? error;
    try {
      a.feed?.requestClose();
    } catch (e) {
      error = e;
    }
    if (!a.feedClosed) {
      try {
        await a.feed?.close();
        a.feedClosed = true;
      } catch (e) {
        error ??= e;
      }
    }
    final subscription = a.subscription;
    if (subscription != null) {
      final cancel = a.subscriptionCancel ??= Future<void>.sync(
        subscription.cancel,
      );
      try {
        await cancel;
      } catch (e) {
        error ??= e;
      }
    }
    await Future.wait(
      List.of(
        a.pending,
      ).map((f) => f.then<void>((_) {}, onError: (Object _, StackTrace __) {})),
    );
    for (final scope in a.scopes) {
      final report = await scope.close();
      if (!report.complete) error ??= report;
    }
    if (error != null) {
      a.error = error;
      a.cleanupFinished = true;
      a.permit.mark(ResourcePhase.unresolved);
      return;
    }
    a.cleanupFinished = true;
    a.permit.release();
    _attempts.remove(a.id);
  }

  Future<CloseReport> _join({
    DateTime? deadline,
    bool retiredOnly = false,
  }) async {
    final selected = [
      for (final a in _attempts.values)
        if (!retiredOnly || a.retired) a,
    ];
    final pending = [
      for (final a in selected)
        if (a.task != null) a.task!,
    ];
    if (pending.isNotEmpty) {
      if (deadline == null) {
        await Future.wait(pending);
      } else {
        final remaining = deadline.difference(DateTime.now());
        if (remaining > Duration.zero) {
          try {
            await Future.wait(pending).timeout(remaining);
          } on TimeoutException {
            // Only this wait expires; the attempt retains its task and permit.
          }
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (final a in selected)
          if (!a.permit.isReleased)
            UnresolvedResource(
              owner: 'conversation:$threadId',
              attemptId: a.id,
              reason: a.error ?? StateError('feed still retiring'),
            ),
      ],
    );
  }

  @override
  Future<CloseReport> joinRetired({DateTime? deadline}) =>
      _join(deadline: deadline, retiredOnly: true);
  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);
  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _demand = false;
    _demandVersion++;
    _retryTimer?.cancel();
    _availability?.cancel();
    _consumer?.cancel();
    for (final a in List.of(_attempts.values)) {
      _retire(a);
    }
    for (final scope in _scopes) {
      scope.retire();
    }
    _state.publish(ChatClosed<bool>(threadId));
    final reports = await Future.wait([
      _join(deadline: deadline),
      for (final scope in _scopes) scope.close(deadline: deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    for (final a in List.of(_attempts.values)) {
      if (a.cleanupFinished && a.error != null && a.feed != null) {
        a.error = null;
        a.task = _cleanup(a);
      }
    }
    final reports = await Future.wait([
      _join(deadline: deadline, retiredOnly: !_closed),
      for (final scope in _scopes)
        if (!scope.isActive) scope.close(deadline: deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}

final class _Attempt {
  _Attempt(this.id, this.permit, this.demandVersion, this.consumer);
  final AttemptId id;
  final ResourcePermit permit;
  final int demandVersion;
  final _ConsumerLease consumer;
  final Set<ConversationReadScope> scopes = {};
  ConversationFeed? feed;
  // The attempt owns this subscription until _cleanup joins cancel.
  // ignore: cancel_subscriptions
  StreamSubscription<ConversationFrame>? subscription;
  Future<void>? subscriptionCancel;
  bool feedClosed = false;
  Future<void>? task;
  final Completer<void> stopped = Completer<void>();
  final Map<int, bool> ledger = {};
  final Set<Future<void>> pending = {};
  Future<void> serial = Future.value();
  bool terminal = false;
  int received = 0;
  int acked = 0;
  bool acking = false;
  bool retired = false;
  Object? error;
  Object? failure;
  bool cleanupFinished = false;
}

final class _ConsumerLease implements Observation {
  _ConsumerLease(this.owner, this.consumer, this.demand);
  final ConversationContentImpl owner;
  final ConversationBatchConsumer consumer;
  final ReadDemand demand;
  @override
  bool isCancelled = false;
  @override
  bool get isPaused => false;
  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    owner._detach(this);
  }

  @override
  void pause() =>
      throw UnsupportedError('Completion consumer cannot be paused');
  @override
  void resume() {}
}
