import 'dart:async';

import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/conversation_timeline.dart';
import '../domain/timeline_models.dart';
import 'connection_owner.dart';
import 'conversation_mirror.dart';
import 'timeline_item_admission.dart';
import 'timeline_port.dart';
import 'timeline_query_scope.dart';
import 'timeline_lifecycle_read.dart';

/// A single ordered body path. Latest state contains connection metadata only.
final class ConversationTimelineOwner implements ConversationTimeline {
  ConversationTimelineOwner({required this.threadId, required TimelineTransport port,
    required this.budget, required this.nextAttempt}) : _port = port,
    _state = ConversationMirror(TimelineConnectionState(threadId: threadId,
      phase: TimelineConnectionPhase.idle), budget: budget, owner: 'timeline:$threadId');

  final String threadId;
  final TimelineTransport _port;
  final ResourceBudget budget;
  final AttemptId Function() nextAttempt;
  final ConversationMirror<TimelineConnectionState> _state;
  final Set<TimelineAttempt> _attempts = {};
  final Set<TimelineConsumerOwner> _consumers = {};
  TimelineAttempt? _current;
  AttemptId? _lastAttemptId;
  TimelineConsumerOwner? _consumer;
  Completer<void> _consumerChanged = Completer<void>();
  Timer? _retryTimer;
  Observation? _capacity;
  ResourcePermit? _capacityPermit;
  bool _demand = false;
  bool _sealed = false;
  bool _disposed = false;
  int _generation = 0;
  int _retries = 0;
  static const _delays = [Duration(milliseconds: 100), Duration(milliseconds: 400), Duration(seconds: 1)];

  @override
  ReadonlyLatestValue<TimelineConnectionState> get state => _state.readonly;
  @override
  late final TimelineLifecycleRead lifecycle = ConversationTimelineLifecycle(
    threadId: threadId, count: () => _attempts.length,
    snapshot: () => (activeAttemptId: _demand ? (_current?.owner.attemptId ?? _lastAttemptId) : null,
      attempts: [for (final attempt in _attempts) _readLifecycle(attempt)]));

  TimelineAttemptLifecycleSnapshot _readLifecycle(TimelineAttempt attempt) {
    final join = attempt.join;
    return (attemptId: attempt.owner.attemptId, retired: attempt.retired,
      join: join?.future, joined: () => join?.isCompleted ?? false, report: attempt.owner.report);
  }
  bool isCurrent(TimelineAttempt attempt) => !_sealed && _demand &&
      identical(_current, attempt) && !attempt.owner.isClosing;

  void setDemand(bool demand) {
    if (_sealed) { if (demand) throw conversationCancelled; return; }
    if (_demand == demand) return;
    _demand = demand;
    _generation++;
    _retries = 0;
    _stopRetry();
    final previous = _current;
    _current = null;
    if (previous != null) _retire(previous);
    if (demand) { _open(); } else {
      _state.publish(_state.value.copyWith(phase: TimelineConnectionPhase.idle, attemptId: null));
    }
  }

  @override
  void refresh() {
    if (_sealed) throw conversationCancelled;
    if (!_demand) return;
    _generation++;
    _retries = 0;
    _stopRetry();
    final previous = _current;
    _current = null;
    if (previous != null) _retire(previous);
    _open();
  }

  @override
  Future<StudioTimelineBaselineFrame> get ready {
    final attempt = _current;
    if (_sealed || attempt == null || !isCurrent(attempt)) {
      return Future.error(_state.value.error ?? conversationCancelled);
    }
    return attempt.ready.future;
  }

  @override
  TimelineConsumerLease attachConsumer(TimelineFrameConsumer consume) {
    if (_sealed) throw conversationCancelled;
    if (_consumer != null && !_consumer!.isClosed) {
      throw const StudioFailure(code: StudioFailureCode.conflict,
        message: 'This Timeline already has a body consumer.', retryable: false,
        correlationId: 'timeline-consumer-conflict');
    }
    final ResourcePermit permit;
    try { permit = budget.acquire(ResourceKind.observer, owner: 'timeline-consumer:$threadId'); }
    on ResourceBudgetExceeded catch (error) { throw error.failure; }
    final lease = TimelineConsumerOwner(this, consume, permit);
    _consumers.add(lease);
    _consumer = lease;
    _wakeConsumer();
    if (_demand && _current?.handoffStarted == true) {
      refresh();
    } else if (_demand && _current == null) {
      _open();
    }
    return lease;
  }

  void detach(TimelineConsumerOwner consumer) {
    if (identical(_consumer, consumer)) _consumer = null;
    _wakeConsumer();
  }

  void consumerSettled(TimelineConsumerOwner consumer) {
    if (consumer.isClosed && !consumer.pending) _consumers.remove(consumer);
  }

  void _wakeConsumer() {
    final signal = _consumerChanged;
    _consumerChanged = Completer<void>();
    if (!signal.isCompleted) signal.complete();
  }

  @override
  StudioTimelineQueryScope? openScope({required int generation}) {
    if (_sealed) throw conversationCancelled;
    final attempt = _current;
    if (attempt == null || !isCurrent(attempt)) return null;
    final TimelineQueryScopeOwner scope;
    try { scope = TimelineQueryScopeOwner(this, attempt, generation); }
    on ResourceBudgetExceeded catch (error) { throw error.failure; }
    attempt.scopes.add(scope);
    return scope;
  }

  void _open() {
    if (_sealed || !_demand || _current != null) return;
    final openingAttempt = nextAttempt();
    _lastAttemptId = openingAttempt;
    final ConversationConnectionOwner<StudioTimelineConnection> owner;
    try {
      owner = ConversationConnectionOwner(label: 'timeline:$threadId', attemptId: openingAttempt,
        budget: budget, kind: ResourceKind.chatHandle, requestClose: (c) => c.requestClose(),
        close: (c) => c.close(), retryClose: (c) => c.retryClose());
    } catch (error) {
      _state.publish(_state.value.copyWith(phase: TimelineConnectionPhase.failed,
        error: conversationFailure(error)));
      if (error is ResourceBudgetExceeded && _capacity == null) {
        try {
          _capacityPermit = budget.acquire(ResourceKind.observer, owner: 'timeline-capacity:$threadId');
          _capacity = budget.watchAvailability(ResourceKind.chatHandle, () { _stopCapacity(); _open(); });
        } catch (_) { /* the overload is already explicit; refresh can retry */ }
      }
      return;
    }
    final attempt = TimelineAttempt(owner, _generation);
    _attempts.add(attempt);
    _current = attempt;
    owner.start(() => _port.openTimeline(threadId));
    _state.publish(_state.value.copyWith(phase: TimelineConnectionPhase.opening,
      attemptId: owner.attemptId, error: null, retryExhausted: false));
    owner.supervise(() => _run(attempt)).ignore();
  }

  Future<void> _run(TimelineAttempt attempt) async {
    StudioFailure? failure;
    var consumerFailed = false;
    _TimelineProcessingStage? processingStage;
    try {
      final connection = await attempt.owner.opened;
      if (!isCurrent(attempt)) return;
      final iterator = StreamIterator(connection.events);
      attempt.owner.onRequestClose(iterator.cancel);
      while (await iterator.moveNext()) {
        if (!isCurrent(attempt)) return;
        final wire = iterator.current;
        switch (wire) {
          case StudioTimelineFeedData(:final deliverySequence, :final event):
            final admitted = _admit(attempt, deliverySequence, event);
            processingStage = _TimelineProcessingStage.apply;
            final frame = _commit(attempt, admitted);
            final subscription = admitted.subscriptionId;
            _state.publish(TimelineConnectionState(threadId: threadId,
              phase: TimelineConnectionPhase.ready, attemptId: attempt.owner.attemptId,
              lastStamp: ViewStamp(threadId: threadId, viewId: subscription,
                viewEpoch: subscription, version: attempt.version!)));
            processingStage = null;
            if (!isCurrent(attempt)) return;
            TimelineConsumerOwner? lease;
            while (isCurrent(attempt)) {
              lease = _consumer;
              if (lease != null && !lease.isClosed) break;
              await _consumerChanged.future;
            }
            if (!isCurrent(attempt) || lease == null || lease.isClosed) return;
            // This marker invalidates a queued handoff when the consumer is
            // replaced; it is not proof that its callback has actually entered.
            attempt.handoffStarted = true;
            var consumerEntered = false;
            try {
              await lease.deliver(frame, canDeliver: () => isCurrent(attempt), onEnter: () {
                consumerEntered = true;
                processingStage = _TimelineProcessingStage.consumer;
              });
            } catch (error, stack) {
              if (!consumerEntered && (lease.isClosed || !isCurrent(attempt))) return;
              consumerFailed = consumerEntered;
              Error.throwWithStackTrace(error, stack);
            }
            processingStage = null;
            // The ACK belongs to this actual consumer and this actual handle.
            if (!isCurrent(attempt) || lease.isClosed || !identical(_consumer, lease)) return;
            processingStage = _TimelineProcessingStage.ack;
            await connection.ackThrough(deliverySequence);
            processingStage = null;
          case StudioTimelineFeedFailure(:final error): throw error;
          case StudioTimelineFeedClosed():
            throw const StudioFailure(code: StudioFailureCode.unavailable,
              message: 'The Timeline feed ended.', retryable: true, correlationId: 'timeline-feed-ended');
        }
      }
      if (isCurrent(attempt)) throw const StudioFailure(code: StudioFailureCode.unavailable,
        message: 'The Timeline feed ended without a terminal frame.', retryable: true,
        correlationId: 'timeline-feed-eof');
    } catch (error, stack) {
      attempt.owner.lastCause = error;
      attempt.owner.lastStack = stack;
      final enteredStage = processingStage;
      if (enteredStage != null) {
        attempt.owner.recordProcessingFailure('timeline:${enteredStage.name}', error, stack);
      }
      if (isCurrent(attempt)) {
        failure = conversationFailure(error);
        try {
          _state.publish(_state.value.copyWith(phase: TimelineConnectionPhase.failed,
            error: failure, retryExhausted: consumerFailed || _retries >= _delays.length));
        } catch (notificationError, notificationStack) {
          // Preserve the source error before the failed notification.
          if (enteredStage == null) {
            attempt.owner.recordProcessingFailure('timeline:failure', error, stack);
          }
          attempt.owner.recordProcessingFailure('timeline:failureNotification', notificationError, notificationStack);
        }
      }
    } finally {
      try {
        if (!attempt.ready.isCompleted) attempt.ready.completeError(failure ?? conversationCancelled);
        if (identical(_current, attempt)) {
          _current = null;
          if (failure == null && !_sealed && _demand) {
            _state.publish(_state.value.copyWith(phase: TimelineConnectionPhase.idle, attemptId: null));
          }
        }
      } catch (error, stack) {
        attempt.owner.recordProcessingFailure('timeline:retirementNotification', error, stack);
      } finally {
        _retire(attempt);
        if (failure != null && !consumerFailed && failure.retryable) {
          final generation = attempt.generation;
          // Never await this attempt's close inside its own supervised stream task.
          scheduleMicrotask(() async {
            final report = await attempt.owner.close();
            if (report.complete && !_sealed && _demand && generation == _generation &&
                _current == null && _retries < _delays.length) {
              _retryTimer = Timer(_delays[_retries++], () { _retryTimer = null; _open(); });
            }
          });
        }
      }
    }
  }

  /// Admission reads the original attempt but only mutates a bounded candidate.
  /// No owner identity, ready completion, publication or consumer is touched.
  _TimelineAdmission _admit(TimelineAttempt attempt, int deliverySequence, StudioTimelineFeedEvent event) {
    if (deliverySequence != attempt.nextDelivery || deliverySequence < 1) {
      throw _protocol('Timeline delivery is not continuous.');
    }
    switch (event) {
      case StudioTimelineFeedBaseline(:final baseline):
        if (attempt.baselineSeen) throw _protocol('A second baseline requires an explicit resync.');
        return _admitBaseline(attempt, baseline);
      case StudioTimelineFeedUpdate(:final update):
        if (!attempt.baselineSeen) throw _protocol('The first Timeline Data is not a baseline.');
        switch (update) {
          case StudioTimelineResync(:final subscriptionId, :final reason, :final baseline):
            if (subscriptionId != attempt.subscriptionId) throw _protocol('Timeline resync changed identity.');
            return _admitBaseline(attempt, baseline, reason: reason);
          case StudioTimelinePatch(:final subscriptionId, :final from, :final to, :final changes):
            if (subscriptionId != attempt.subscriptionId || from != attempt.version || to <= from) {
              throw _protocol('The Timeline patch does not continue the original view.');
            }
            final members = Map<String, TimelineMemberIdentity>.of(attempt.members);
            for (final change in changes) {
              switch (change) {
                case StudioTimelineAdd(:final item):
                  final identity = admitTimelineItem(threadId, item, previous: members[item.id]);
                  _remember(members, item.id, identity);
                case StudioTimelineUpdateItem():
                  final identity = admitTimelineItemUpdate(threadId, change, members[change.itemId]);
                  _remember(members, change.itemId, identity);
                case StudioTimelineRemove(:final itemId):
                  // A real Remove is self-contained even outside this bounded map.
                  members.remove(itemId);
              }
            }
            return (frame: StudioTimelinePatchFrame(update), subscriptionId: subscriptionId,
              version: to, members: members);
        }
    }
  }

  _TimelineAdmission _admitBaseline(TimelineAttempt attempt, StudioTimelineBaseline baseline,
      {StudioTimelineResyncReason? reason}) {
    if (baseline.subscriptionId.isEmpty || baseline.version < 0 || baseline.items.length > 100 ||
        (attempt.subscriptionId != null && baseline.subscriptionId != attempt.subscriptionId)) {
      throw _protocol('The Timeline baseline identity is invalid.');
    }
    final members = <String, TimelineMemberIdentity>{};
    for (final item in baseline.items) {
      if (members.containsKey(item.id)) throw _protocol('The Timeline baseline repeats an item identity.');
      final identity = admitTimelineItem(threadId, item, previous: attempt.members[item.id]);
      members[item.id] = identity;
    }
    return (frame: StudioTimelineBaselineFrame(baseline, resyncReason: reason),
      subscriptionId: baseline.subscriptionId, version: baseline.version, members: members);
  }

  void _remember(Map<String, TimelineMemberIdentity> members, String id, TimelineMemberIdentity identity) {
    if (!members.containsKey(id) && members.length >= 100) members.remove(members.keys.first);
    members[id] = identity;
  }

  StudioTimelineFrame _commit(TimelineAttempt attempt, _TimelineAdmission admitted) {
    attempt.owner.expectFeedId(admitted.subscriptionId);
    attempt.subscriptionId = admitted.subscriptionId;
    attempt.version = admitted.version;
    attempt.members = admitted.members;
    attempt.baselineSeen = true;
    attempt.nextDelivery++;
    final frame = admitted.frame;
    if (frame is StudioTimelineBaselineFrame && !attempt.ready.isCompleted) attempt.ready.complete(frame);
    return frame;
  }

  void _retire(TimelineAttempt attempt) {
    if (!attempt.ready.isCompleted) attempt.ready.completeError(conversationCancelled);
    attempt.retired = true;
    _joinAttempt(attempt).ignore();
    for (final scope in List.of(attempt.scopes)) { scope.retire(); }
    _wakeConsumer();
  }

  Future<CloseReport> _joinAttempt(TimelineAttempt attempt, {bool retry = false}) {
    final done = Completer<CloseReport>();
    attempt.join = done;
    attempt.owner.close(retry: retry).then((report) {
      if (report.complete) _attempts.remove(attempt);
      done.complete(report);
    }, onError: (Object error, StackTrace stack) {
      attempt.owner.recordProcessingFailure('timelineJoin', error, stack);
      done.complete(attempt.owner.report());
    });
    return done.future;
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    _demand = false;
    _generation++;
    _current = null;
    _stopRetry();
    for (final consumer in List.of(_consumers)) { consumer.requestClose(); }
    for (final attempt in List.of(_attempts)) { _retire(attempt); }
    _wakeConsumer();
    _state.publish(_state.value.copyWith(phase: TimelineConnectionPhase.closed));
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final attempts = List.of(_attempts);
    final consumers = List.of(_consumers);
    final joins = [for (final a in attempts) _joinAttempt(a, retry: retry)];
    final scopeTasks = [for (final a in attempts) for (final scope in List.of(a.scopes)) scope.close(deadline: deadline)];
    final consumerDone = Future.wait([for (final c in consumers) c.close()]);
    await observeConversationCompletion(consumerDone.then<void>((_) {}), deadline);
    await observeConversationCompletion(Future.wait(joins).then<void>((_) {}), deadline);
    final reports = [for (final a in attempts) a.owner.report()];
    final scopeReports = await Future.wait(scopeTasks);
    _attempts.removeWhere((a) => a.owner.released);
    final unresolved = [for (final report in [...reports, ...scopeReports]) ...report.unresolved];
    for (final consumer in _consumers) {
      if (consumer.pending) unresolved.add(UnresolvedResource(owner: 'timeline-consumer:$threadId',
        attemptId: consumer.attemptId, issues: [const FeedCloseIssue(diagnostic: StudioShutdownIssue(
          stage: 'timelineConsumer', code: 'handoffPending', message: 'The original consumer handoff is still in flight.',
          retryable: true, correlationId: 'timeline-consumer'), recovery: CleanupRecovery.awaitCompletion)]));
    }
    if (unresolved.isEmpty && !_disposed) { _disposed = true; _state.close(); }
    return CloseReport(unresolved: unresolved);
  }

  void _stopCapacity() { _capacity?.cancel(); _capacity = null; _capacityPermit?.release(); _capacityPermit = null; }
  void _stopRetry() { _retryTimer?.cancel(); _retryTimer = null; _stopCapacity(); }
  StudioFailure _protocol(String message) => StudioFailure(code: StudioFailureCode.protocol,
    message: message, retryable: false, correlationId: 'timeline-continuity');
}

enum _TimelineProcessingStage { apply, consumer, ack }

typedef _TimelineAdmission = ({
  StudioTimelineFrame frame,
  String subscriptionId,
  int version,
  Map<String, TimelineMemberIdentity> members,
});

final class TimelineAttempt {
  TimelineAttempt(this.owner, this.generation) { ready.future.ignore(); }
  final ConversationConnectionOwner<StudioTimelineConnection> owner;
  final int generation;
  final Completer<StudioTimelineBaselineFrame> ready = Completer();
  final Set<TimelineQueryScopeOwner> scopes = {};
  Map<String, TimelineMemberIdentity> members = {};
  String? subscriptionId;
  int? version;
  int nextDelivery = 1;
  bool baselineSeen = false;
  bool handoffStarted = false;
  bool retired = false;
  Completer<CloseReport>? join;
}

final class TimelineConsumerOwner implements TimelineConsumerLease {
  TimelineConsumerOwner(this.channel, this.consume, this.permit) : attemptId = channel.nextAttempt();
  final ConversationTimelineOwner channel;
  final TimelineFrameConsumer consume;
  final ResourcePermit permit;
  final AttemptId attemptId;
  final Set<Future<void>> _pending = {};
  bool _closed = false;
  @override
  bool get isClosed => _closed;
  bool get pending => _pending.isNotEmpty;
  Future<void> deliver(StudioTimelineFrame frame, {required bool Function() canDeliver,
      required void Function() onEnter}) {
    if (_closed) return Future.error(conversationCancelled);
    final done = Completer<void>();
    final preceding = List.of(_pending);
    _pending.add(done.future);
    final task = Future<void>.sync(() async {
      await Future.wait([for (final previous in preceding)
        previous.then<void>((_) {}, onError: (Object _, StackTrace _) {})]);
      if (_closed || !canDeliver()) throw conversationCancelled;
      onEnter();
      await consume(frame);
    });
    task.then((_) { _pending.remove(done.future); done.complete(); _settle(); },
      onError: (Object error, StackTrace stack) { _pending.remove(done.future); done.completeError(error, stack); _settle(); });
    return done.future;
  }
  @override
  void requestClose() { if (_closed) return; _closed = true; channel.detach(this); _settle(); }
  void _settle() { if (_closed && _pending.isEmpty) { permit.release(); channel.consumerSettled(this); } }
  @override
  Future<void> close() async {
    requestClose();
    await Future.wait([for (final pending in List.of(_pending))
      pending.then<void>((_) {}, onError: (Object _, StackTrace _) {})]);
    _settle();
  }
}
