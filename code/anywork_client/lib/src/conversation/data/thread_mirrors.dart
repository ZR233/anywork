import 'dart:async';

import '../../../operations_ports.dart';
import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/authoring_values.dart';
import '../domain/facet_state.dart';
import '../domain/execution_values.dart';
import '../domain/thread_frames.dart';
import '../domain/thread_identity.dart';
import 'conversation_mirror.dart';
import 'facet_cursor.dart';

/// The one Dart canonical writer for the five facets of a concrete Session.
/// Feed/query ownership is supervised by the Session, not by these value mirrors.
final class ThreadMirrors {
  ThreadMirrors({required this.threadId, required ResourceBudget budget, required OperationRecorder operations,
    required ResourcePermit permit})
      : _operations = operations,
        _permit = permit,
        _execution = ConversationMirror(const ThreadExecutionState(sync: _idle), budget: budget, owner: 'execution:$threadId'),
        _metrics = ConversationMirror(const ThreadMetricsState(sync: _idle), budget: budget, owner: 'metrics:$threadId'),
        _context = ConversationMirror(const ThreadContextState(sync: _idle), budget: budget, owner: 'context:$threadId'),
        _configuration = ConversationMirror(const ThreadConfigurationState(sync: _idle), budget: budget, owner: 'configuration:$threadId'),
        _authoring = ConversationMirror(const ThreadAuthoringState(sync: _idle), budget: budget, owner: 'authoring:$threadId');

  static const _idle = FacetSyncState(phase: FacetSyncPhase.idle);
  static const _ready = FacetSyncState(phase: FacetSyncPhase.ready);
  final String threadId;
  final OperationRecorder _operations;
  final ResourcePermit _permit;
  final ConversationMirror<ThreadExecutionState> _execution;
  final ConversationMirror<ThreadMetricsState> _metrics;
  final ConversationMirror<ThreadContextState> _context;
  final ConversationMirror<ThreadConfigurationState> _configuration;
  final ConversationMirror<ThreadAuthoringState> _authoring;
  final Map<ThreadFacet, FacetCursor> _cursors = {};
  bool _closed = false;

  ReadonlyLatestValue<ThreadExecutionState> get execution => _execution.readonly;
  ReadonlyLatestValue<ThreadMetricsState> get metrics => _metrics.readonly;
  ReadonlyLatestValue<ThreadContextState> get context => _context.readonly;
  ReadonlyLatestValue<ThreadConfigurationState> get configuration => _configuration.readonly;
  ReadonlyLatestValue<ThreadAuthoringState> get authoring => _authoring.readonly;

  void beginAttempt(ThreadFacet facet, ThreadObservationMode mode) {
    _ensureOpen();
    _cursors[facet] = FacetCursor(facet, mode);
    synchronize(facet, const FacetSyncState(phase: FacetSyncPhase.connecting));
  }

  ThreadFeedIdentity? identity(ThreadFacet facet) => _cursors[facet]?.identity;
  void checkBaseline(ThreadFacet facet, int sequence, ThreadFeedIdentity identity, ThreadFacetStamp stamp) =>
      _cursor(facet).validateBaseline(sequence, identity, stamp);
  void checkChange(ThreadFacet facet, int sequence, ThreadFacetStamp stamp, {int? baseRevision}) =>
      _cursor(facet).validateChange(sequence, stamp, baseRevision: baseRevision);

  FacetCursor _cursor(ThreadFacet facet) {
    _ensureOpen();
    final cursor = _cursors[facet];
    if (cursor == null) throw _protocol('No attempt was admitted for this facet.');
    return cursor;
  }

  /// The exact reliable delta is handed to D1's index/identity owner before ACK.
  /// A latest observer is not a reliable handoff and is deliberately not used.
  Future<int> applyExecution(ThreadExecutionData frame, {
    required FutureOr<void> Function(ThreadFacetStamp stamp, InteractionDelta? delta) handoff,
  }) async {
    final cursor = _cursor(ThreadFacet.execution);
    final ThreadFacetStamp stamp;
    final ThreadExecutionBaseline value;
    InteractionDelta? delta;
    switch (frame.event) {
      case ThreadExecutionBaselineEvent(identity: final identity, stamp: final source, value: final baseline):
        _checkIndex(baseline.interactions);
        cursor.baseline(frame.deliverySequence, identity, source);
        stamp = source;
        value = baseline;
      case ThreadExecutionChangeEvent(stamp: final source, :final baseRevision, value: final change):
        final previous = _execution.value.value;
        if (previous == null) throw _protocol('An execution change has no baseline.');
        delta = change.interactions;
        if (delta != null) _checkDelta(previous.interactions, delta);
        cursor.change(frame.deliverySequence, source, baseRevision: baseRevision);
        stamp = source;
        value = previous.copyWith(
          status: change.status ?? previous.status,
          activeTurn: change.turns == null ? previous.activeTurn : change.turns!.activeTurn,
          recentTerminalTurn: change.turns == null ? previous.recentTerminalTurn : change.turns!.recentTerminalTurn,
          interactions: delta?.index ?? previous.interactions,
          activity: switch (change.activity) {
            UnchangedActivity() => previous.activity,
            ReplacedActivity(:final value) => value,
          },
          storage: switch (change.storage) {
            UnchangedStorage() => previous.storage,
            ReplacedStorage(:final value) => value,
          },
        );
    }
    _execution.publish(ThreadExecutionState(stamp: stamp, sync: _ready, value: value));
    await handoff(stamp, delta);
    return frame.deliverySequence;
  }

  int applyMetrics(ThreadMetricsData frame) {
    final cursor = _cursor(ThreadFacet.metrics);
    switch (frame.event) {
      case ThreadMetricsBaselineEvent(:final identity, :final stamp, :final value):
        cursor.baseline(frame.deliverySequence, identity, stamp);
        _metrics.publish(ThreadMetricsState(stamp: stamp, sync: _ready, value: value));
      case ThreadMetricsReplaceEvent(:final stamp, :final value):
        cursor.change(frame.deliverySequence, stamp);
        _metrics.publish(ThreadMetricsState(stamp: stamp, sync: _ready, value: value));
    }
    return frame.deliverySequence;
  }

  int applyContext(ThreadContextData frame) {
    final cursor = _cursor(ThreadFacet.context);
    switch (frame.event) {
      case ThreadContextBaselineEvent(:final identity, :final stamp, :final value):
        cursor.baseline(frame.deliverySequence, identity, stamp);
        _context.publish(ThreadContextState(stamp: stamp, sync: _ready, value: value));
      case ThreadContextReplaceEvent(:final stamp, :final value):
        cursor.change(frame.deliverySequence, stamp);
        _context.publish(ThreadContextState(stamp: stamp, sync: _ready, value: value));
    }
    return frame.deliverySequence;
  }

  int applyConfiguration(ThreadConfigurationData frame) {
    final cursor = _cursor(ThreadFacet.configuration);
    switch (frame.event) {
      case ThreadConfigurationBaselineEvent(:final identity, :final stamp, :final value):
        cursor.baseline(frame.deliverySequence, identity, stamp);
        _configuration.publish(ThreadConfigurationState(stamp: stamp, sync: _ready, value: value));
      case ThreadConfigurationReplaceEvent(:final stamp, :final value):
        cursor.change(frame.deliverySequence, stamp);
        _configuration.publish(ThreadConfigurationState(stamp: stamp, sync: _ready, value: value));
    }
    final source = _configuration.value;
    final epoch = source.stamp!.runtimeEpoch;
    final value = source.value!;
    if (value.modeBindingRevision case final revision?) {
      _operations.observe(ResourceStamp(resourceKey: 'thread-mode:$threadId', ownerEpoch: epoch, revision: revision));
    }
    if (value.modelRoute case final route?) {
      _operations.observe(ResourceStamp(resourceKey: 'thread-route:$threadId', ownerEpoch: epoch, revision: route.revision));
    }
    return frame.deliverySequence;
  }

  int applyAuthoring(ThreadAuthoringData frame) {
    final cursor = _cursor(ThreadFacet.authoring);
    switch (frame.event) {
      case ThreadAuthoringBaselineEvent(:final identity, :final stamp, :final value):
        cursor.baseline(frame.deliverySequence, identity, stamp);
        _authoring.publish(ThreadAuthoringState(stamp: stamp, sync: _ready, value: value));
      case ThreadAuthoringChangeEvent(:final stamp, :final baseRevision, value: final change):
        final previous = _authoring.value.value;
        if (previous == null) throw _protocol('An authoring change has no baseline.');
        cursor.change(frame.deliverySequence, stamp, baseRevision: baseRevision);
        final value = previous.copyWith(
          todo: switch (change.todo) { UnchangedTodo() => previous.todo, ReplacedTodo(:final value) => value },
          plan: switch (change.plan) { UnchangedPlan() => previous.plan, ReplacedPlan(:final value) => value },
          workflow: switch (change.workflow) { UnchangedWorkflow() => previous.workflow, ReplacedWorkflow(:final value) => value },
        );
        _authoring.publish(ThreadAuthoringState(stamp: stamp, sync: _ready, value: value));
    }
    return frame.deliverySequence;
  }

  void checkControl(ThreadFacet facet, ThreadFeedIdentity identity) => _cursor(facet).control(identity);

  /// Connection failures preserve the original value and stamp, never healthy defaults.
  void synchronize(ThreadFacet facet, FacetSyncState sync) {
    _ensureOpen();
    switch (facet) {
      case ThreadFacet.execution: _execution.publish(_execution.value.copyWith(sync: sync));
      case ThreadFacet.metrics: _metrics.publish(_metrics.value.copyWith(sync: sync));
      case ThreadFacet.context: _context.publish(_context.value.copyWith(sync: sync));
      case ThreadFacet.configuration: _configuration.publish(_configuration.value.copyWith(sync: sync));
      case ThreadFacet.authoring: _authoring.publish(_authoring.value.copyWith(sync: sync));
    }
  }

  void _checkIndex(InteractionIndexHeader index) {
    if (index.total < 0 || index.pending < 0 || index.pending > index.total ||
        index.reference.entry < 0 || index.reference.revision < 0) {
      throw _protocol('The interaction index header is invalid.');
    }
  }

  void _checkDelta(InteractionIndexHeader previous, InteractionDelta delta) {
    _checkIndex(delta.index);
    if (delta.baseIndexRevision != previous.reference.revision ||
        delta.index.reference.entry != previous.reference.entry ||
        delta.index.reference.revision <= previous.reference.revision ||
        delta.upserted.length + delta.removedEntries.length + delta.terminalFacts.length > 100) {
      throw _protocol('The interaction index delta is not continuous.');
    }
    final upserted = <int>{};
    final removed = <int>{};
    final terminals = <int>{};
    for (final brief in delta.upserted) {
      if (brief.revision != brief.reference.revision || !upserted.add(brief.reference.entry)) {
        throw _protocol('The interaction upsert has an inconsistent identity.');
      }
    }
    for (final entry in delta.removedEntries) {
      if (entry < 0 || !removed.add(entry) || upserted.contains(entry)) {
        throw _protocol('The interaction removal has an inconsistent identity.');
      }
    }
    for (final brief in delta.terminalFacts) {
      if (brief.status == InteractionStatus.pending ||
          brief.revision != brief.reference.revision ||
          !terminals.add(brief.reference.entry) || upserted.contains(brief.reference.entry)) {
        throw _protocol('The terminal interaction fact is not an exact terminal identity.');
      }
    }
    // A removal may also have a terminal fact, but removal alone proves nothing.
  }

  /// Only the Session may call this after all native/query/consumer owners joined.
  void dispose() {
    if (_closed) return;
    _closed = true;
    const closed = FacetSyncState(phase: FacetSyncPhase.closed);
    _execution.publish(_execution.value.copyWith(sync: closed));
    _metrics.publish(_metrics.value.copyWith(sync: closed));
    _context.publish(_context.value.copyWith(sync: closed));
    _configuration.publish(_configuration.value.copyWith(sync: closed));
    _authoring.publish(_authoring.value.copyWith(sync: closed));
    _execution.close();
    _metrics.close();
    _context.close();
    _configuration.close();
    _authoring.close();
    _permit.release();
  }

  void _ensureOpen() {
    if (_closed) throw const StudioFailure(code: StudioFailureCode.cancelled,
      message: 'The conversation Session is closed.', retryable: false,
      correlationId: 'conversation-session-closed');
  }

  StudioFailure _protocol(String message) => StudioFailure(code: StudioFailureCode.protocol,
      message: message, retryable: false, correlationId: 'conversation-mirror-protocol');
}
