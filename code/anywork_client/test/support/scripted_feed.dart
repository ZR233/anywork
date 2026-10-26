import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

/// Scripted native boundary, not a Repository/reducer. Data credit, listener
/// claim and cleanup receipts are explicit so public owner tests can control
/// the actual await boundaries without timers or a second canonical mirror.
final class ScriptedFeed<T> implements FeedConnection<T> {
  ScriptedFeed({
    required this.feedId,
    required this.sequenceOf,
    required this.isTerminal,
  });

  final String feedId;
  final int? Function(T) sequenceOf;
  final bool Function(T) isTerminal;
  final listened = Completer<void>();
  final cancellationStarted = Completer<void>();
  final closeStarted = Completer<void>();
  final acknowledgements = <int>[];
  final _ackWaiters = <int, Completer<void>>{};
  Completer<void>? cancellationReceipt;
  Completer<void>? ackReceipt;

  /// Completes when the first acknowledgement actually entered the native call,
  /// before that call's own receipt resolves. This is the real handshake for
  /// holding an in-flight acknowledgement; no timer guesses when it is reached.
  final acknowledgementEntered = Completer<int>();
  Completer<FeedCloseReport>? closeReceipt;
  FeedCloseOutcome outcome = const FeedCloseOutcome.clean();
  int closeCalls = 0;
  int retryCloseCalls = 0;
  int requestCloseCalls = 0;
  int _sent = 0;
  int _acknowledged = 0;
  final _outstanding = <int>{};
  bool _claimed = false;
  bool _closing = false;
  bool _terminal = false;
  bool _sinkClosing = false;

  late final _controller = StreamController<T>(
    sync: true,
    onListen: () => listened.complete(),
    onCancel: () async {
      if (!cancellationStarted.isCompleted) cancellationStarted.complete();
      await cancellationReceipt?.future;
    },
  );
  late final Stream<T> _events = _ClaimedFeedStream(this);

  @override
  Stream<T> get events => _events;

  void emit(T frame) {
    if (_closing || _terminal) throw _failure(StudioFailureCode.cancelled);
    if (!_claimed) throw StateError('Wait for actual listen before emitting');
    final sequence = sequenceOf(frame);
    if (sequence != null) {
      if (sequence <= _sent)
        throw ArgumentError('Delivery sequence must advance');
      if (_outstanding.length == 2)
        throw _failure(StudioFailureCode.overloaded);
      _sent = sequence;
      _outstanding.add(sequence);
    }
    _terminal = isTerminal(frame);
    _controller.add(frame);
  }

  Future<void> acknowledged(int prefix) {
    if (_acknowledged >= prefix) return Future.value();
    return _ackWaiters.putIfAbsent(prefix, Completer<void>.new).future;
  }

  @override
  Future<void> ackThrough(int deliverySequence) async {
    if (deliverySequence < _acknowledged || deliverySequence > _sent) {
      throw _failure(StudioFailureCode.invalidArgument);
    }
    if (!acknowledgementEntered.isCompleted) {
      acknowledgementEntered.complete(deliverySequence);
    }
    await ackReceipt?.future;
    _acknowledged = deliverySequence;
    _outstanding.removeWhere((sequence) => sequence <= deliverySequence);
    acknowledgements.add(deliverySequence);
    for (final entry in _ackWaiters.entries.toList()) {
      if (entry.key <= deliverySequence) {
        _ackWaiters.remove(entry.key);
        entry.value.complete();
      }
    }
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    _closing = true;
    if (_claimed && !_sinkClosing) {
      _sinkClosing = true;
      // Native join and Dart stream cancellation have separate real receipts.
      // The public owner must join both rather than treating one as the other.
      unawaited(_controller.close());
    }
  }

  @override
  Future<FeedCloseReport> close() {
    closeCalls++;
    return _close();
  }

  @override
  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    return _close();
  }

  Future<FeedCloseReport> _close() {
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    return closeReceipt?.future ??
        Future.value(FeedCloseReport(feedId: feedId, outcome: outcome));
  }

  StudioFailure _failure(StudioFailureCode code) => StudioFailure(
    code: code,
    message: 'Scripted feed admission rejected',
    retryable: false,
    correlationId: feedId,
  );
}

final class _ClaimedFeedStream<T> extends Stream<T> {
  _ClaimedFeedStream(this.owner);
  final ScriptedFeed<T> owner;

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // Getter access never claims, and closing Cancelled wins over Conflict.
    final rejection = owner._closing
        ? StudioFailureCode.cancelled
        : owner._claimed
        ? StudioFailureCode.conflict
        : null;
    if (rejection != null) {
      return Stream<T>.error(owner._failure(rejection)).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
    owner._claimed = true;
    return owner._controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
