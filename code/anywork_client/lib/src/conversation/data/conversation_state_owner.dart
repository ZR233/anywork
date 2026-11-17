import 'dart:async';
import 'dart:math';

import '../../../lifecycle.dart' show ClientCloseBudget, ClientResourceId;
import '../../../conversation_ports.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart';
import '../../../models.dart';
import '../../studio/thread_frames.dart';
import '../domain/content_lifecycle.dart';
import '../domain/conversation_errors.dart';

/// Owns the sole Current State observation. There is no delivery ACK or replay.
final class ConversationStateOwner {
  ConversationStateOwner({
    required this.threadId,
    required CurrentTransport transport,
    required this.onState,
    required this.onFailure,
    required this.onAttempt,
    required this.demand,
  }) : _transport = transport;

  final String threadId;
  final CurrentTransport _transport;
  final ReadDemand demand;
  final void Function(AttemptId, ThreadStreamFrame) onState;
  final void Function(AttemptId, Object, bool) onFailure;
  final void Function(AttemptId) onAttempt;
  final Map<AttemptId, _StateAttempt> _attempts = {};
  final String _resourceScopeId = _newResourceScopeId();
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
    if (_closed && value)
      throw StateError('Conversation state owner is closed');
    if (_demand == value) return;
    _demand = value;
    _demandVersion++;
    _retryTimer?.cancel();
    _retryTimer = null;
    final current = _current;
    if (current != null) _retire(current);
    if (value) {
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

  bool _live(_StateAttempt attempt) =>
      !_closed && _demand && !attempt.retired && identical(_current, attempt);

  void _open() {
    if (_closed || !_demand || _current != null) return;
    final id = AttemptId(++_nextAttempt);
    final attempt = _StateAttempt(
      id,
      _demandVersion,
      ClientResourceId(_resourceScopeId, id.value),
    );
    _attempts[id] = attempt;
    _current = attempt;
    final done = Completer<void>();
    attempt.task = done.future;
    done.complete(Future<void>.sync(() => _run(attempt)));
  }

  Future<void> _run(_StateAttempt attempt) async {
    try {
      if (!_live(attempt)) return;
      onAttempt(attempt.id);
      if (!_live(attempt)) return;
      final reader = await _transport.openCurrentReader(
        threadId,
        currentProtocolVersion: currentProtocolVersion,
        demand: demand,
      );
      attempt.reader = reader;
      if (!_live(attempt)) return;
      _validateIdentity(reader);
      final initial = reader.initialView;
      if (initial.revision.ownerId != reader.metadata.currentOwnerId) {
        throw const ConversationContinuityError(
          'current baseline owner mismatch',
        );
      }
      _acceptReset(attempt, initial.revision);
      _admit(attempt, initial.state);
      final watch = await reader.watch(after: initial.revision, demand: demand);
      attempt.watch = watch;
      if (!_live(attempt)) return;
      attempt.subscription = watch.frames.listen(
        (frame) => _receive(attempt, frame),
        onError: (Object error, StackTrace stack) =>
            _failAttempt(attempt, error),
        onDone: () => _failAttempt(attempt, const ConversationStreamEnded()),
      );
      await attempt.stopped.future;
    } catch (error) {
      if (_live(attempt)) _failAttempt(attempt, error);
    } finally {
      if (identical(_current, attempt)) _current = null;
      attempt.retired = true;
      if (!attempt.stopped.isCompleted) attempt.stopped.complete();
      await _cleanup(attempt);
      if (attempt.failure != null &&
          attempt.retryable &&
          !_closed &&
          _demand &&
          attempt.demandVersion == _demandVersion &&
          _current == null &&
          !_attempts.containsKey(attempt.id)) {
        _scheduleRetry();
      }
    }
  }

  void _validateIdentity(CurrentReader reader) {
    if (reader.threadId != threadId ||
        reader.metadata.currentProtocolVersion != currentProtocolVersion ||
        reader.metadata.readerId.isEmpty ||
        reader.metadata.currentOwnerId.isEmpty) {
      throw const ConversationContinuityError(
        'current reader identity mismatch',
      );
    }
  }

  void _receive(_StateAttempt attempt, CurrentFrame frame) {
    if (!_live(attempt)) return;
    switch (frame) {
      case ResetCurrentFrame(:final view):
        _acceptReset(attempt, view.revision);
        _admit(attempt, view.state);
        return;
      case NotificationCurrentFrame(:final revision, :final notification):
        _validateContinuousRevision(attempt, revision);
        attempt.revision = revision;
        _admit(attempt, notification);
        return;
      case ProjectionCurrentFrame(:final revision):
        _validateContinuousRevision(attempt, revision);
        attempt.revision = revision;
        return;
    }
  }

  void _acceptReset(_StateAttempt attempt, CurrentRevision revision) {
    if (revision.ownerId.isEmpty) {
      throw const ConversationContinuityError('current reset has no owner');
    }
    attempt.ownerId = revision.ownerId;
    attempt.revision = revision;
  }

  void _validateContinuousRevision(
    _StateAttempt attempt,
    CurrentRevision revision,
  ) {
    final previous = attempt.revision;
    if (attempt.ownerId == null ||
        revision.ownerId != attempt.ownerId ||
        (previous != null &&
            previous.ownerId == attempt.ownerId &&
            revision.revision < previous.revision)) {
      throw const ConversationContinuityError(
        'current owner changed without Reset or revision moved backwards',
      );
    }
  }

  void _admit(_StateAttempt attempt, ThreadStreamFrame? frame) {
    if (frame == null || !_live(attempt)) return;
    final work = _enqueue(attempt, () async {
      if (!_live(attempt)) return;
      if (frame case ThreadSnapshotFrame(:final schemaVersion)) {
        if (schemaVersion != threadSchemaVersion) {
          throw ProtocolVersionMismatch(
            received: schemaVersion,
            supported: threadSchemaVersion,
            field: 'threadSchemaVersion',
          );
        }
      }
      onState(attempt.id, frame);
    });
    unawaited(
      work.then(
        (_) {
          if (_live(attempt)) _retries = 0;
        },
        onError: (Object error, StackTrace _) {
          if (_live(attempt)) _failAttempt(attempt, error);
        },
      ),
    );
  }

  Future<void> _enqueue(
    _StateAttempt attempt,
    Future<void> Function() operation,
  ) {
    final work = attempt.serial.then((_) => operation());
    attempt.serial = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    attempt.pending.add(work);
    unawaited(attempt.serial.then((_) => attempt.pending.remove(work)));
    return work;
  }

  void _failAttempt(_StateAttempt attempt, Object error) {
    if (!_live(attempt)) return;
    attempt.failure = error;
    final versionMismatch = error is ProtocolVersionMismatch;
    final exhausted =
        versionMismatch || _retries >= const RetryPolicy().delays.length;
    attempt.retryable = !versionMismatch;
    onFailure(attempt.id, error, exhausted);
    if (!_live(attempt)) return;
    _retire(attempt);
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

  void _retire(_StateAttempt attempt) {
    if (attempt.retired) return;
    attempt.retired = true;
    if (identical(_current, attempt)) _current = null;
    try {
      attempt.watch?.requestClose();
      attempt.reader?.requestClose();
    } catch (error) {
      attempt.error = error;
    }
    if (!attempt.stopped.isCompleted) attempt.stopped.complete();
  }

  Future<void> _cleanup(_StateAttempt attempt) async {
    Object? error;
    try {
      attempt.watch?.requestClose();
      attempt.reader?.requestClose();
    } catch (exception) {
      error = exception;
    }
    if (!attempt.watchClosed && attempt.watch != null) {
      try {
        await attempt.watch!.close();
        attempt.watchClosed = true;
      } catch (exception) {
        error ??= exception;
      }
    }
    if (!attempt.readerClosed && attempt.reader != null) {
      try {
        await attempt.reader!.close();
        attempt.readerClosed = true;
      } catch (exception) {
        error ??= exception;
      }
    }
    final subscription = attempt.subscription;
    if (subscription != null) {
      final cancel = attempt.subscriptionCancel ??= Future<void>.sync(
        subscription.cancel,
      );
      try {
        await cancel;
      } catch (exception) {
        error ??= exception;
      }
    }
    await Future.wait(
      List.of(attempt.pending).map(
        (future) =>
            future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
      ),
    );
    attempt.cleanupFinished = true;
    if (error != null) {
      attempt.error = error;
      return;
    }
    _attempts.remove(attempt.id);
  }

  Future<CloseReport> _join({
    ClientCloseBudget? budget,
    bool retiredOnly = false,
  }) async {
    final selected = [
      for (final attempt in _attempts.values)
        if (!retiredOnly || attempt.retired) attempt,
    ];
    final pending = [
      for (final attempt in selected)
        if (attempt.task != null) attempt.task!,
    ];
    if (pending.isNotEmpty) {
      if (budget == null) {
        await Future.wait(pending);
      } else {
        final remaining = budget.remaining;
        if (remaining > Duration.zero) {
          try {
            await Future.wait(pending).timeout(remaining);
          } on TimeoutException {
            // The attempt retains its task and cleanup obligation.
          }
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (final attempt in selected)
          if (_attempts.containsKey(attempt.id))
            UnresolvedResource(
              resourceId: attempt.resourceId,
              owner: 'current-state:$threadId',
              attemptId: attempt.id,
              reason:
                  attempt.error ?? StateError('current reader still retiring'),
            ),
      ],
    );
  }

  Future<CloseReport> joinRetired({ClientCloseBudget? budget}) =>
      _join(budget: budget, retiredOnly: true);

  Future<CloseReport> close({ClientCloseBudget? budget}) =>
      _closing ??= _close(budget);

  Future<CloseReport> _close(ClientCloseBudget? budget) async {
    _closed = true;
    _demand = false;
    _demandVersion++;
    _retryTimer?.cancel();
    for (final attempt in List.of(_attempts.values)) {
      _retire(attempt);
    }
    return _join(budget: budget);
  }

  Future<CloseReport> retryCleanup({ClientCloseBudget? budget}) async {
    for (final attempt in List.of(_attempts.values)) {
      if (attempt.cleanupFinished &&
          attempt.error != null &&
          (attempt.reader != null || attempt.watch != null)) {
        attempt.error = null;
        attempt.task = _cleanup(attempt);
      }
    }
    return _join(budget: budget, retiredOnly: !_closed);
  }
}

final class _StateAttempt {
  _StateAttempt(this.id, this.demandVersion, this.resourceId);
  final AttemptId id;
  final ClientResourceId resourceId;
  final int demandVersion;
  CurrentReader? reader;
  CurrentWatch? watch;
  // ignore: cancel_subscriptions
  StreamSubscription<CurrentFrame>? subscription;
  Future<void>? subscriptionCancel;
  bool readerClosed = false;
  bool watchClosed = false;
  Future<void>? task;
  final Completer<void> stopped = Completer<void>();
  final Set<Future<void>> pending = {};
  Future<void> serial = Future.value();
  bool retryable = true;
  bool retired = false;
  Object? error;
  Object? failure;
  String? ownerId;
  CurrentRevision? revision;
  bool cleanupFinished = false;
}

String _newResourceScopeId() {
  final random = Random.secure();
  final nonce = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'current-state-$nonce';
}
