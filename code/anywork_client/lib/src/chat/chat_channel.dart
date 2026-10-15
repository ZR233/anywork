import 'dart:async';

import '../../transport_ports.dart';
import '../contracts/stamps.dart';
import '../lifecycle/resource_budget.dart';
import '../observation/latest_value.dart';
import 'chat_models.dart';

final class StaleChatAttempt implements Exception {
  const StaleChatAttempt();

  @override
  String toString() => 'The ChatView attempt has been retired';
}

final class ChatStreamEnded implements Exception {
  const ChatStreamEnded();

  @override
  String toString() => 'The ChatView content stream ended';
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

/// Owns one logical ChatView demand, including every late and retiring handle.
///
/// Observing [state] never changes demand. A new attempt never reduces a Patch
/// against [ChatUiState.snapshot] retained from another attempt.
final class ChatChannel<S, F, R> {
  ChatChannel({
    required this.threadId,
    required ChatTransport<S, F, R> transport,
    required ChatReducer<S, F> reducer,
    ResourceBudget? budget,
    this.retryPolicy = const RetryPolicy(),
  }) : _transport = transport,
       _reducer = reducer,
       budget = budget ?? ResourceBudget(),
       state = LatestValue<ChatUiState<S>>(ChatIdle<S>(threadId));

  final String threadId;
  final ChatTransport<S, F, R> _transport;
  final ChatReducer<S, F> _reducer;
  final ResourceBudget budget;
  final RetryPolicy retryPolicy;
  final LatestValue<ChatUiState<S>> state;
  final Map<AttemptId, _BindingAttempt<S, F, R>> _attempts = {};
  _BindingAttempt<S, F, R>? _current;
  Timer? _retryTimer;
  Observation? _capacityObservation;
  int _sequence = 0;
  int _controlSequence = 0;
  int _demandVersion = 0;
  int _retries = 0;
  bool _demand = false;
  bool _closed = false;
  S? _lastGood;
  Future<CloseReport>? _closeFuture;

  bool get hasDemand => _demand;
  AttemptId? get currentAttemptId => _current?.id;
  int get ownedAttemptCount => _attempts.length;

  void start() => setDemand(true);

  void setDemand(bool value) {
    if (_closed) {
      if (value) throw StateError('The Chat channel is closed');
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
      _lastGood = null;
      state.publish(ChatIdle<S>(threadId));
      return;
    }
    _retries = 0;
    _open();
  }

  void retry() {
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

  Future<S> get ready async {
    final attempt = _current;
    if (attempt == null || !_isCurrent(attempt)) {
      final currentState = state.value;
      if (currentState is ChatFailed<S>) throw currentState.error;
      throw const StaleChatAttempt();
    }
    final result = await state.waitFor(
      (value) =>
          !_isCurrent(attempt) ||
          value is ChatReady<S> ||
          value is ChatReconnecting<S> ||
          value is ChatFailed<S>,
    );
    if (!_isCurrent(attempt)) throw const StaleChatAttempt();
    if (result is ChatReady<S>) return result.snapshot;
    if (result is ChatReconnecting<S>) throw result.error;
    if (result is ChatFailed<S>) throw result.error;
    throw const StaleChatAttempt();
  }

  /// Captures a stable attempt before waiting and rejects a late control reply.
  Future<R> control(Future<R> Function(ChatHandle<S, F, R> handle) command) {
    final attempt = _current;
    if (attempt == null) return Future.error(const StaleChatAttempt());
    final ResourcePermit permit;
    try {
      permit = budget.acquire(
        ResourceKind.pendingOperation,
        owner:
            'chat-control:$threadId:${attempt.id.value}:${++_controlSequence}',
      );
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final task = _runControl(attempt, command, permit);
    late final Future<void> joined;
    joined = task
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            // The returned command Future carries the failure to its caller.
          },
        )
        .whenComplete(() {
          attempt.controls.remove(joined);
        });
    attempt.controls.add(joined);
    return task;
  }

  Future<R> _runControl(
    _BindingAttempt<S, F, R> attempt,
    Future<R> Function(ChatHandle<S, F, R>) command,
    ResourcePermit permit,
  ) async {
    try {
      await ready;
      if (!_isCurrent(attempt)) throw const StaleChatAttempt();
      final handle = attempt.handle;
      if (handle == null) throw const StaleChatAttempt();
      final receipt = await command(handle);
      if (!_isCurrent(attempt)) throw const StaleChatAttempt();
      return receipt;
    } finally {
      permit.release();
    }
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
      state.publish(ChatFailed<S>(threadId, lastGood: _lastGood, error: error));
      return;
    }
    _cancelCapacityObservation();
    // Ownership and the permit exist before transport.open's first await.
    final attempt = _BindingAttempt<S, F, R>(
      id: id,
      demandVersion: _demandVersion,
      permit: permit,
    );
    _current = attempt;
    _attempts[id] = attempt;
    state.publish(ChatOpening<S>(threadId, lastGood: _lastGood));
    attempt.task = _run(attempt);
  }

  void _cancelCapacityObservation() {
    _capacityObservation?.cancel();
    _capacityObservation = null;
  }

  bool _isCurrent(_BindingAttempt<S, F, R> attempt) =>
      !_closed &&
      _demand &&
      !attempt.retired &&
      identical(_current, attempt) &&
      attempt.demandVersion == _demandVersion;

  Future<void> _run(_BindingAttempt<S, F, R> attempt) async {
    Object? failure;
    try {
      final handle = await _transport.open(threadId);
      // Adoption belongs to this attempt even if the open completed late.
      attempt.handle = handle;
      if (!_isCurrent(attempt)) return;
      final initial = await handle.initial();
      if (!_isCurrent(attempt)) return;
      var snapshot = _reducer.reset(initial);
      attempt.permit.mark(ResourcePhase.active);
      _lastGood = snapshot;
      state.publish(ChatReady<S>(threadId, snapshot));
      while (_isCurrent(attempt)) {
        // There is exactly one outstanding next, and reduce precedes the next.
        final frame = await handle.next();
        if (!_isCurrent(attempt)) return;
        if (frame == null) throw const ChatStreamEnded();
        snapshot = _reducer.apply(snapshot, frame);
        _lastGood = snapshot;
        state.publish(ChatReady<S>(threadId, snapshot));
      }
    } catch (error) {
      if (_isCurrent(attempt)) {
        failure = error;
        final canRetry = _retries < retryPolicy.delays.length;
        state.publish(
          canRetry
              ? ChatReconnecting<S>(threadId, lastGood: _lastGood, error: error)
              : ChatFailed<S>(threadId, lastGood: _lastGood, error: error),
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
            ChatFailed<S>(
              threadId,
              lastGood: _lastGood,
              error: attempt.cleanupError!,
            ),
          );
        }
      }
    }
  }

  void _retire(_BindingAttempt<S, F, R> attempt) {
    attempt.retired = true;
    if (identical(_current, attempt)) _current = null;
    attempt.permit.mark(ResourcePhase.retiring);
    _requestClose(attempt);
  }

  void _requestClose(_BindingAttempt<S, F, R> attempt) {
    final handle = attempt.handle;
    if (handle == null || attempt.closeRequested) return;
    attempt.closeRequested = true;
    try {
      handle.requestClose();
    } catch (error) {
      // The joining close still runs. A request failure is retained if join fails.
      attempt.cleanupError = error;
    }
  }

  Future<bool> _cleanup(_BindingAttempt<S, F, R> attempt) {
    if (attempt.permit.isReleased) return Future.value(true);
    final cleaning = attempt.cleaning;
    if (cleaning != null) return cleaning;
    final task = _joinCleanup(attempt);
    attempt.cleaning = task;
    return task.whenComplete(() {
      attempt.cleaning = null;
    });
  }

  Future<bool> _joinCleanup(_BindingAttempt<S, F, R> attempt) async {
    attempt.permit.mark(ResourcePhase.retiring);
    _requestClose(attempt);
    final handle = attempt.handle;
    try {
      await Future.wait<void>([
        if (handle != null) Future<void>.sync(handle.close),
        ...attempt.controls,
      ]);
      attempt.cleanupError = null;
      attempt.permit.release();
      _attempts.remove(attempt.id);
      return true;
    } catch (error) {
      attempt.cleanupError = error;
      attempt.permit.mark(ResourcePhase.unresolved);
      return false;
    }
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

  /// The first caller chooses the shared deadline; later calls join its result.
  /// Timing out the join never abandons the original open/close task or permit.
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
    state.publish(ChatClosed<S>(threadId));
    final tasks = [
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
          // Every unfinished task remains in _attempts and retains its permit.
        }
      }
    }
    return _report();
  }

  /// Retries only native cleanup, never business writes or handle creation.
  Future<CloseReport> retryCleanup() async {
    for (final attempt in List.of(_attempts.values)) {
      final cleaning = attempt.cleaning;
      if (cleaning != null) {
        await cleaning;
      } else if (attempt.cleanupError != null && attempt.handle != null) {
        await _cleanup(attempt);
      } else if (attempt.retired && attempt.handle != null) {
        final task = attempt.task;
        if (task != null) await task;
      }
    }
    return _report();
  }

  /// Joins retired attempts without permanently closing this logical channel.
  Future<CloseReport> joinRetired({DateTime? deadline}) async {
    final retired = [
      for (final attempt in _attempts.values)
        if (attempt.retired) attempt,
    ];
    final tasks = [
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
          // These tasks remain owned by the same attempts after the deadline.
        }
      }
    }
    return CloseReport(
      unresolved: [
        for (final attempt in retired)
          if (_attempts.containsKey(attempt.id))
            UnresolvedResource(
              owner: threadId,
              attemptId: attempt.id,
              reason: attempt.cleanupError ?? const StaleChatAttempt(),
            ),
      ],
    );
  }

  CloseReport _report() => CloseReport(
    unresolved: [
      for (final attempt in _attempts.values)
        if (attempt.retired || attempt.cleanupError != null)
          UnresolvedResource(
            owner: threadId,
            attemptId: attempt.id,
            reason: attempt.cleanupError ?? const StaleChatAttempt(),
          ),
    ],
  );
}

final class _BindingAttempt<S, F, R> {
  _BindingAttempt({
    required this.id,
    required this.demandVersion,
    required this.permit,
  });

  final AttemptId id;
  final int demandVersion;
  final ResourcePermit permit;
  ChatHandle<S, F, R>? handle;
  Future<void>? task;
  bool retired = false;
  bool closeRequested = false;
  Object? cleanupError;
  Future<bool>? cleaning;
  final Set<Future<void>> controls = {};
}
