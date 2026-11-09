import 'dart:async';

import '../../../conversation_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart';
import '../domain/content_lifecycle.dart';
import '../domain/conversation_errors.dart';

/// Owns the independent state stream: admission, reduction handoff, ACK and
/// retirement. State never flows through content consumption, and content
/// events never enter here; the session remains the sole state writer.
final class ConversationStateOwner {
  ConversationStateOwner({
    required this.threadId,
    required ConversationTransport transport,
    required this.onState,
    required this.onFailure,
    required this.onAttempt,
  }) : _transport = transport;

  final String threadId;
  final ConversationTransport _transport;
  final void Function(AttemptId, ThreadStreamFrame) onState;
  final void Function(AttemptId, Object, bool) onFailure;
  final void Function(AttemptId) onAttempt;
  final Map<AttemptId, _StateAttempt> _attempts = {};
  _StateAttempt? _current;
  int _nextAttempt = 0;
  bool _demand = false;
  bool _closed = false;
  int _demandVersion = 0;
  int _retries = 0;
  Timer? _retryTimer;
  Future<CloseReport>? _closing;

  bool get hasDemand => _demand;
  bool get isClosed => _closed;
  AttemptId? get currentAttemptId => _current?.id;
  int get ownedAttemptCount => _attempts.length;

  void setDemand(bool value) {
    if (_closed && value) {
      throw StateError('Conversation state owner is closed');
    }
    if (_demand == value) return;
    _demand = value;
    _demandVersion++;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!value) {
      final current = _current;
      if (current != null) _retire(current);
    } else {
      _retries = 0;
      _open();
    }
  }

  void refresh() {
    _demandVersion++;
    _retries = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    final current = _current;
    if (current != null) _retire(current);
    if (_demand && !_closed) _open();
  }

  bool _live(_StateAttempt a) =>
      !_closed && _demand && !a.retired && identical(_current, a);

  void _open() {
    if (_closed || !_demand || _current != null) return;
    final id = AttemptId(++_nextAttempt);
    final a = _StateAttempt(id, _demandVersion);
    _attempts[id] = a;
    _current = a;
    final done = Completer<void>();
    a.task = done.future;
    done.complete(Future<void>.sync(() => _run(a)));
  }

  Future<void> _run(_StateAttempt a) async {
    try {
      if (!_live(a)) return;
      onAttempt(a.id);
      if (!_live(a)) return;
      final feed = await _transport.openConversationStateFeed(threadId);
      a.feed = feed;
      if (!_live(a)) return;
      if (feed.threadId != threadId || feed.subscriptionId.isEmpty) {
        throw const ConversationContinuityError('state feed identity mismatch');
      }
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
      if (a.failure != null &&
          a.retryable &&
          !_closed &&
          _demand &&
          a.demandVersion == _demandVersion &&
          _current == null &&
          !_attempts.containsKey(a.id)) {
        _scheduleRetry();
      }
    }
  }

  void _receive(_StateAttempt a, ConversationFrame frame) {
    if (!_live(a)) return;
    final feed = a.feed!;
    if (frame.threadId != threadId ||
        frame.subscriptionId != feed.subscriptionId) {
      _failAttempt(
        a,
        const ConversationContinuityError('state frame identity mismatch'),
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
          'state delivery sequence or credit exceeded',
        ),
      );
      return;
    }
    a.received = frame.deliverySequence;
    a.ledger[frame.deliverySequence] = false;
    final work = _enqueue(a, () async {
      if (!_live(a)) return;
      switch (frame.event) {
        case ConversationStateEvent(:final frame):
          if (frame case ThreadSnapshotFrame(
            :final completedHistoryVersion,
            :final schemaVersion,
          )) {
            if (completedHistoryVersion != 1) {
              throw ProtocolVersionMismatch(received: completedHistoryVersion);
            }
            if (schemaVersion != threadSchemaVersion) {
              throw ProtocolVersionMismatch(
                received: schemaVersion,
                supported: threadSchemaVersion,
                field: 'threadSchemaVersion',
              );
            }
          }
          onState(a.id, frame);
        case ConversationChatEvent() ||
            ConversationActivityEvent() ||
            ConversationFailureEvent() ||
            ConversationClosedEvent():
          // Content belongs to the content feed only; the state feed must not
          // become a second content admission path.
          throw const ConversationContinuityError(
            'content event on state feed',
          );
      }
      if (!_live(a)) return;
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

  /// The sole admission queue for state reduction. Its ACK never enters the
  /// content consumption queue and vice versa.
  Future<void> _enqueue(_StateAttempt a, Future<void> Function() operation) {
    final work = a.serial.then((_) => operation());
    // One failed operation must not leave unobserved errors on the queue tail.
    a.serial = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    a.pending.add(work);
    unawaited(a.serial.then((_) => a.pending.remove(work)));
    return work;
  }

  void _flushAck(_StateAttempt a) {
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

  void _failAttempt(_StateAttempt a, Object error) {
    if (!_live(a)) return;
    a.failure = error;
    final versionMismatch = error is ProtocolVersionMismatch;
    final exhausted =
        versionMismatch || _retries >= const RetryPolicy().delays.length;
    a.retryable = !versionMismatch;
    onFailure(a.id, error, exhausted);
    if (!_live(a)) return;
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

  void _retire(_StateAttempt a) {
    if (a.retired) return;
    a.retired = true;
    if (identical(_current, a)) _current = null;
    try {
      a.feed?.requestClose();
    } catch (error) {
      a.error = error;
    }
    if (!a.stopped.isCompleted) a.stopped.complete();
  }

  Future<void> _cleanup(_StateAttempt a) async {
    a.cleanupFinished = false;
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
    if (error != null) {
      a.error = error;
      a.cleanupFinished = true;
      return;
    }
    a.cleanupFinished = true;
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
            // Only this wait expires; the attempt retains its task.
          }
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (final a in selected)
          if (_attempts.containsKey(a.id))
            UnresolvedResource(
              owner: 'conversation-state:$threadId',
              attemptId: a.id,
              reason: a.error ?? StateError('state feed still retiring'),
            ),
      ],
    );
  }

  Future<CloseReport> joinRetired({DateTime? deadline}) =>
      _join(deadline: deadline, retiredOnly: true);

  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    _demand = false;
    _demandVersion++;
    _retryTimer?.cancel();
    for (final a in List.of(_attempts.values)) {
      _retire(a);
    }
    return _join(deadline: deadline);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    for (final a in List.of(_attempts.values)) {
      if (a.cleanupFinished && a.error != null && a.feed != null) {
        a.error = null;
        a.task = _cleanup(a);
      }
    }
    return _join(deadline: deadline, retiredOnly: !_closed);
  }
}

final class _StateAttempt {
  _StateAttempt(this.id, this.demandVersion);
  final AttemptId id;
  final int demandVersion;
  ConversationStateFeed? feed;
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
  bool retryable = true;
  int received = 0;
  int acked = 0;
  bool acking = false;
  bool retired = false;
  Object? error;
  Object? failure;
  bool cleanupFinished = false;
}
