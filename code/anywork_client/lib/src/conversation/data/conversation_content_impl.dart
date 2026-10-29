import 'dart:async';

import '../../../models.dart';
import '../../../conversation_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart';
import '../../observation/latest_value.dart';
import '../domain/activity_content.dart';
import '../domain/content_lifecycle.dart';
import '../domain/content_state.dart';
import '../domain/conversation_repository.dart';
import 'activity_content_owner.dart';
import 'conversation_read_scope.dart';
import 'completion_budget.dart';
import 'input_turn_facts.dart';

/// Owns feed admission, delivery, ACK and actual retirement, but no history window.
final class ConversationContentImpl implements ConversationContent {
  ConversationContentImpl({
    required this.threadId,
    required ConversationTransport transport,
    required this.budget,
    required this.inputFacts,
    required this.onState,
    required this.onFailure,
    required this.onAttempt,
    int maxContentBytes = 64 * 1024 * 1024,
  }) : _transport = transport,
       _activity = ActivityContentOwner(maxContentBytes: maxContentBytes),
       _state = LatestValue(ChatIdle<bool>(threadId));
  @override
  final String threadId;
  final ConversationTransport _transport;
  final ResourceBudget budget;
  final InputFactRegistry inputFacts;
  final void Function(AttemptId, ThreadStreamFrame) onState;
  final void Function(AttemptId, Object, bool) onFailure;
  final void Function(AttemptId) onAttempt;
  final ActivityContentOwner _activity;
  final LatestValue<ChatUiState<bool>> _state;
  @override
  ValueObservation<ChatUiState<bool>> get state => _state;
  @override
  ValueObservation<CurrentActivity?> get currentActivity => _activity.source;
  final Map<AttemptId, _Attempt> _attempts = {};
  final Set<ConversationReadScope> _scopes = {};
  _Attempt? _current;
  _ConsumerLease? _consumer;
  Completer<void>? _consumerAvailable;
  ConversationCompletionCursor? _cursor;
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
  Observation attachConsumer(ConversationCompletionConsumer consumer) {
    if (_closed) throw StateError('Conversation is closed');
    if (_consumer != null)
      throw StateError('Completion consumer already attached');
    final lease = _ConsumerLease(this, consumer);
    _consumer = lease;
    final waiter = _consumerAvailable;
    _consumerAvailable = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    return lease;
  }

  void _detach(_ConsumerLease lease) {
    if (!identical(_consumer, lease)) return;
    _consumer = null;
    _cursor = null;
    final current = _current;
    if (current != null) _retire(current);
    if (_demand && !_closed) _open();
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
  ConversationQueryScope openScope({
    required String timelineEpoch,
    required int generation,
  }) {
    if (_closed) throw StateError('Conversation is closed');
    _scopes.removeWhere((scope) => scope.isSettled);
    final scope = ConversationReadScope(
      threadId: threadId,
      timelineEpoch: timelineEpoch,
      generation: generation,
      transport: _transport,
      budget: budget,
    );
    _scopes.add(scope);
    return scope;
  }

  bool _live(_Attempt a) =>
      !_closed && _demand && !a.retired && identical(_current, a);
  void _open() {
    if (_closed || !_demand || _current != null) return;
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
    final a = _Attempt(id, permit, _demandVersion);
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
        resumeAfter: _cursor,
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
    if (frame.event is ConversationFailureEvent) {
      _failAttempt(a, (frame.event as ConversationFailureEvent).failure);
      return;
    }
    if (frame.event is ConversationClosedEvent) {
      _failAttempt(a, const ConversationStreamEnded());
      return;
    }
    if (frame.deliverySequence != a.received + 1 ||
        a.ledger.length >= (a.acking ? 3 : 2)) {
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
    final event = frame.event;
    Future<void> work;
    if (event is ConversationStateEvent) {
      work = Future<void>.sync(() {
        onState(a.id, event.frame);
      });
    } else if (event is ConversationActivityContentEvent) {
      final precedingCompletion = a.completionSerial;
      work = a.activitySerial.then((_) async {
        if (event.frame is ActivityCommit) await precedingCompletion;
        await _process(a, event);
      });
      a.activitySerial = work;
      if (event.frame is ActivityCommit) a.completionSerial = work;
    } else {
      work = a.completionSerial.then((_) => _process(a, event));
      a.completionSerial = work;
    }
    a.pending.add(work);
    unawaited(
      work.then(
        (_) {
          a.pending.remove(work);
          if (!_live(a)) return;
          a.ledger[frame.deliverySequence] = true;
          _flushAck(a);
        },
        onError: (Object error, StackTrace stack) {
          a.pending.remove(work);
          if (_live(a)) _failAttempt(a, error);
        },
      ),
    );
  }

  Future<void> _process(_Attempt a, ConversationEvent event) async {
    if (!_live(a)) return;
    switch (event) {
      case ConversationBaselineEvent(:final baseline):
        if (_cursor != null)
          throw const ConversationContinuityError(
            'unexpected baseline during resume',
          );
        await _deliver(a, ConversationBaselineFrame(baseline));
      case ConversationUpdateEvent(:final update):
        await _deliver(a, _toFrame(update));
      case ConversationActivityContentEvent(:final frame, :final completed):
        if (frame is! ActivityCommit) {
          if (completed != null)
            throw const ConversationContinuityError(
              'completion on non-commit activity',
            );
          _activity.accept(frame);
        } else {
          final prepared = _activity.prepareCommit(frame);
          if (completed != null) await _deliver(a, _toFrame(completed));
          if (!_live(a)) return;
          _activity.publish(prepared);
        }
      case ConversationStateEvent() ||
          ConversationFailureEvent() ||
          ConversationClosedEvent():
        throw const ConversationContinuityError('unexpected event');
    }
    if (_live(a) && _state.value is! ChatReady<bool>)
      _state.publish(ChatReady<bool>(threadId, true));
    _retries = 0;
  }

  ConversationContentFrame _toFrame(ConversationUpdate update) =>
      switch (update) {
        ConversationBatch() => ConversationCompletedBatchFrame(update),
        ConversationReset(:final baseline) => ConversationResetFrame(baseline),
      };
  Future<void> _deliver(_Attempt a, ConversationContentFrame frame) async {
    final ConversationCompletionCursor next;
    switch (frame) {
      case ConversationBaselineFrame(:final baseline):
        _validateBaseline(a, baseline);
        next = baseline.completedCursor;
      case ConversationResetFrame(:final baseline):
        _validateBaseline(a, baseline);
        if (_cursor != null && _cursor!.timelineEpoch == baseline.timelineEpoch)
          throw const ConversationContinuityError('reset did not change epoch');
        next = baseline.completedCursor;
      case ConversationCompletedBatchFrame(:final batch):
        final old = _cursor;
        if (old == null ||
            batch.subscriptionId != a.feed!.subscriptionId ||
            batch.timelineEpoch != old.timelineEpoch ||
            batch.fromSeq != old.appendSeq ||
            batch.throughSeq < batch.fromSeq)
          throw const ConversationContinuityError('batch cursor mismatch');
        _validateItems(
          batch.items,
          minExclusive: batch.fromSeq,
          maxInclusive: batch.throughSeq,
        );
        if (batch.items.isEmpty ||
            batch.items.last.header.appendSeq != batch.throughSeq)
          throw const ConversationContinuityError('batch through mismatch');
        next = ConversationCompletionCursor(
          timelineEpoch: batch.timelineEpoch,
          appendSeq: batch.throughSeq,
        );
    }
    while (_consumer == null && _live(a)) {
      final available = _consumerAvailable ??= Completer<void>();
      await Future.any([available.future, a.stopped.future]);
    }
    if (!_live(a)) return;
    final lease = _consumer!;
    await Future<void>.sync(() => lease.consumer.accept(frame));
    if (!_live(a) || !identical(_consumer, lease) || lease.isCancelled) return;
    _cursor = next;
    final items = switch (frame) {
      ConversationBaselineFrame(:final baseline) => baseline.items,
      ConversationResetFrame(:final baseline) => baseline.items,
      ConversationCompletedBatchFrame(:final batch) => batch.items,
    };
    for (final item in items) {
      final descriptor = item.descriptor;
      if (descriptor is! ConversationTurnDescriptor ||
          descriptor.inputId == null ||
          !inputFacts.isWatching(descriptor.inputId!))
        continue;
      final status = switch (descriptor.outcome) {
        ConversationTurnCompleted(:final value) => value.status,
        ConversationTurnFailed(:final value) => value.status,
        ConversationTurnCancelled(:final value) => value.status,
        ConversationTurnBudgetLimited(:final value) => value.status,
      };
      inputFacts.publish(
        InputTurnFact(
          threadId: threadId,
          inputId: descriptor.inputId!,
          itemId: item.id,
          turnId: item.header.turnId,
          status: status,
          saved: null,
        ),
      );
    }
  }

  void _validateBaseline(_Attempt a, ConversationBaseline baseline) {
    if (baseline.subscriptionId != a.feed!.subscriptionId ||
        baseline.timelineEpoch != baseline.completedCursor.timelineEpoch ||
        baseline.timelineEpoch.isEmpty ||
        baseline.completedCursor.appendSeq < 0 ||
        baseline.hasOlder != (baseline.before != null))
      throw const ConversationContinuityError('baseline identity mismatch');
    _validateItems(
      baseline.items,
      maxInclusive: baseline.completedCursor.appendSeq,
    );
  }

  void _validateItems(
    List<ConversationItem> items, {
    int minExclusive = -1,
    required int maxInclusive,
  }) {
    validateCompletionBudget(items);
    var last = minExclusive;
    final ids = <String>{};
    for (final item in items) {
      final h = item.header;
      if (h.threadId != threadId ||
          h.id.isEmpty ||
          h.appendSeq <= last ||
          h.appendSeq > maxInclusive ||
          !ids.add(h.id))
        throw const ConversationContinuityError(
          'completion item identity or order mismatch',
        );
      final fields = <ThreadContentFieldView>{};
      for (final field in item.fields) {
        if (!fields.add(field.field) ||
            field.totalBytes < 0 ||
            field.previewBytes > field.totalBytes) {
          throw const ConversationContinuityError('invalid completed field');
        }
      }
      last = h.appendSeq;
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
    _activity.cancelStaging();
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
    try {
      await a.subscription?.cancel();
    } catch (e) {
      error ??= e;
    }
    try {
      await a.feed?.close();
    } catch (e) {
      error ??= e;
    }
    await Future.wait(
      List.of(
        a.pending,
      ).map((f) => f.then<void>((_) {}, onError: (Object _, StackTrace __) {})),
    );
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
      _join(deadline: deadline),
      for (final scope in _scopes)
        if (!scope.isActive) scope.close(deadline: deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}

final class _Attempt {
  _Attempt(this.id, this.permit, this.demandVersion);
  final AttemptId id;
  final ResourcePermit permit;
  final int demandVersion;
  ConversationFeed? feed;
  // The attempt owns this subscription until _cleanup joins cancel.
  // ignore: cancel_subscriptions
  StreamSubscription<ConversationFrame>? subscription;
  Future<void>? task;
  final Completer<void> stopped = Completer<void>();
  final Map<int, bool> ledger = {};
  final Set<Future<void>> pending = {};
  Future<void> activitySerial = Future.value();
  Future<void> completionSerial = Future.value();
  int received = 0;
  int acked = 0;
  bool acking = false;
  bool retired = false;
  Object? error;
  Object? failure;
  bool cleanupFinished = false;
}

final class _ConsumerLease implements Observation {
  _ConsumerLease(this.owner, this.consumer);
  final ConversationContentImpl owner;
  final ConversationCompletionConsumer consumer;
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
