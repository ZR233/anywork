import 'dart:async';

import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/facet_state.dart';
import '../domain/thread_identity.dart';
import 'connection_owner.dart';

/// Typed feed lifecycle only; the Session remains the sole facet reducer.
abstract interface class ConversationFacetControl {
  AttemptId? get activeAttemptId;
  void setDemand(bool demand, ThreadObservationMode mode);
  Future<void> retry();
  void Function() fenceProjection();
  void seal();
  Future<CloseReport> close({DateTime? deadline, bool retry = false});
}

final class ConversationFacetFeed<F> implements ConversationFacetControl {
  ConversationFacetFeed({required this.label, required this.facet,
    required this.budget, required this.nextAttempt, required this.open,
    required this.begin, required this.isData, required this.consume,
    required this.synchronize, required this.feedId, this.onAttempt});
  final String label;
  final ThreadFacet facet;
  final ResourceBudget budget;
  final AttemptId Function() nextAttempt;
  final Future<FeedConnection<F>> Function(ThreadObservationMode) open;
  final void Function(ThreadObservationMode) begin;
  final bool Function(F) isData;
  final Future<int?> Function(F, bool Function()) consume;
  final void Function(FacetSyncState) synchronize;
  final String? Function() feedId;
  final void Function(AttemptId)? onAttempt;
  final Set<ConversationConnectionOwner<FeedConnection<F>>> _owned = {};
  ConversationConnectionOwner<FeedConnection<F>>? _active;
  ThreadObservationMode? _mode;
  Object? _sourceKey;
  Future<FeedConnection<F>> Function()? _sourceOpen;
  void Function(AttemptId)? _sourceAttempt;
  Timer? _retryTimer;
  bool _demand = false;
  bool _sealed = false;
  int _generation = 0;
  int _retries = 0;
  static const _delays = [Duration(milliseconds: 100), Duration(milliseconds: 400), Duration(seconds: 1)];

  @override
  AttemptId? get activeAttemptId => _active?.isClosing == false ? _active!.attemptId : null;

  void setDemand(bool demand, ThreadObservationMode mode, {Object? sourceKey,
      Future<FeedConnection<F>> Function()? openSource, void Function(AttemptId)? sourceAttempt}) {
    if (_sealed) { if (demand) throw conversationCancelled; return; }
    if ((sourceKey == null) != (openSource == null)) throw const StudioFailure(
      code: StudioFailureCode.protocol, message: 'A bound feed source requires its exact opener.',
      retryable: false, correlationId: 'thread-feed-source');
    if (_demand == demand && (!demand || (_mode == mode && identical(_sourceKey, sourceKey)))) return;
    _demand = demand;
    _mode = mode;
    _sourceKey = demand ? sourceKey : null;
    _sourceOpen = demand ? openSource : null;
    _sourceAttempt = demand ? sourceAttempt : null;
    final generation = ++_generation;
    _retries = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    final previous = _active;
    _active = null;
    if (previous != null) _retire(previous);
    if (_sealed || generation != _generation) return;
    if (demand) { _start(); } else { synchronize(const FacetSyncState(phase: FacetSyncPhase.idle)); }
  }

  Future<void> retry() async {
    if (_sealed) throw conversationCancelled;
    if (!_demand) return;
    final generation = ++_generation;
    _retries = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    final previous = _active;
    _active = null;
    if (previous != null) _retire(previous);
    if (_sealed || generation != _generation) return;
    _start();
  }

  bool _current(ConversationConnectionOwner<FeedConnection<F>> owner, int generation) =>
      !_sealed && _demand && generation == _generation && identical(_active, owner) && !owner.isClosing;

  @override
  void Function() fenceProjection() {
    if (_sealed) return () {};
    final previous = _active;
    _active = null;
    final generation = ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retries = 0;
    // Only internal admission changes above: all siblings can be fenced before
    // any native cancellation or publication can synchronously reenter.
    return () {
      try {
        if (_sealed || generation != _generation) return;
      synchronize(FacetSyncState(phase: _demand ? FacetSyncPhase.reconnecting : FacetSyncPhase.idle));
      } catch (error, stack) {
        previous?.recordProcessingFailure('thread:${facet.name}:projectionNotification', error, stack);
        rethrow;
      } finally {
        if (previous != null) _retire(previous);
      scheduleMicrotask(() { if (!_sealed && generation == _generation) _start(); });
      }
    };
  }

  void _start() {
    if (_sealed || !_demand || _active != null) return;
    final mode = _mode!;
    final ConversationConnectionOwner<FeedConnection<F>> owner;
    try {
      owner = ConversationConnectionOwner(label: label, attemptId: nextAttempt(), budget: budget,
        kind: ResourceKind.observer, requestClose: (c) => c.requestClose(),
        close: (c) => c.close(), retryClose: (c) => c.retryClose());
    } catch (error) {
      synchronize(FacetSyncState(phase: FacetSyncPhase.failed, error: conversationFailure(error)));
      return;
    }
    _owned.add(owner);
    _active = owner;
    final generation = _generation;
    // A supplied source never falls back to the ordinary activating opener.
    final openAttempt = _sourceKey == null ? () => open(mode) : _sourceOpen!;
    final announceAttempt = _sourceAttempt ?? onAttempt;
    try {
      announceAttempt?.call(owner.attemptId);
      begin(mode);
      owner.start(openAttempt);
    } catch (error, stack) {
      owner.start(() => Future.error(error, stack));
    }
    owner.supervise(() => _run(owner, generation)).ignore();
  }

  Future<void> _run(ConversationConnectionOwner<FeedConnection<F>> owner, int generation) async {
    StudioFailure? failure;
    String? enteredStage;
    try {
      final connection = await owner.opened;
      if (!_current(owner, generation)) return;
      final iterator = StreamIterator(connection.events);
      owner.onRequestClose(iterator.cancel);
      while (await iterator.moveNext()) {
        if (!_current(owner, generation)) return;
        final frame = iterator.current;
        // Typed terminal/resync controls are not admitted Data applications.
        enteredStage = null;
        final sequence = await consume(frame, () {
          if (!_current(owner, generation)) return false;
          if (!isData(frame)) throw const StudioFailure(code: StudioFailureCode.protocol,
            message: 'A control frame cannot enter Data application.', retryable: false, correlationId: 'thread-feed-apply');
          enteredStage = 'thread:${facet.name}:apply';
          return true;
        });
        if (!_current(owner, generation)) return;
        if (feedId() case final id?) owner.expectFeedId(id);
        enteredStage = null;
        if (sequence != null) {
          enteredStage = 'thread:${facet.name}:ack';
          await connection.ackThrough(sequence);
          enteredStage = null;
        }
      }
      if (_current(owner, generation)) throw const StudioFailure(code: StudioFailureCode.unavailable,
        message: 'The Thread facet ended without its typed terminal control.', retryable: true,
        correlationId: 'thread-feed-eof');
    } catch (error, stack) {
      owner.lastCause = error;
      owner.lastStack = stack;
      if (enteredStage case final stage?) owner.recordProcessingFailure(stage, error, stack);
      if (_current(owner, generation)) {
        failure = conversationFailure(error);
        try {
        synchronize(FacetSyncState(phase: failure.retryable && _retries < _delays.length ? FacetSyncPhase.reconnecting : FacetSyncPhase.failed,
          error: failure, retryExhausted: _retries >= _delays.length));
        } catch (notificationError, notificationStack) {
          if (enteredStage == null) owner.recordProcessingFailure('thread:${facet.name}:failure', error, stack);
          owner.recordProcessingFailure('thread:${facet.name}:failureNotification', notificationError, notificationStack);
        }
      }
    } finally {
      if (identical(_active, owner)) _active = null;
      _retire(owner);
      if (failure != null && failure.retryable) {
        scheduleMicrotask(() async {
          final report = await owner.close();
          if (report.complete && !_sealed && _demand && generation == _generation &&
              _active == null && _retries < _delays.length) {
            _retryTimer = Timer(_delays[_retries++], () { _retryTimer = null; _start(); });
          }
        });
      }
    }
  }

  void _retire(ConversationConnectionOwner<FeedConnection<F>> owner) {
    owner.requestClose();
    owner.close().then((report) { if (report.complete) _owned.remove(owner); }).ignore();
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    _demand = false;
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _active = null;
    for (final owner in List.of(_owned)) { _retire(owner); }
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final reports = await Future.wait([for (final owner in List.of(_owned))
      owner.close(deadline: deadline, retry: retry)]);
    _owned.removeWhere((owner) => owner.released);
    return CloseReport(unresolved: [for (final report in reports) ...report.unresolved]);
  }

  /// Join retired UI attempts without sealing/cancelling the active execution
  /// source which is still borrowed by the original operation's evidence lease.
  Future<CloseReport> joinRetired({DateTime? deadline, bool retry = false}) async {
    final retired = [for (final owner in _owned) if (!identical(owner, _active) || owner.isClosing) owner];
    final reports = await Future.wait([for (final owner in retired)
      owner.close(deadline: deadline, retry: retry)]);
    _owned.removeWhere((owner) => owner.released);
    return CloseReport(unresolved: [for (final report in reports) ...report.unresolved]);
}
}
