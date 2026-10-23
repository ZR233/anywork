import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/execution_values.dart';
import '../domain/facet_state.dart';
import '../domain/thread_frames.dart';
import '../domain/thread_identity.dart';
import 'conversation_observation_port.dart';
import 'connection_owner.dart';
import 'facet_feed.dart';
import 'thread_mirrors.dart';

final class ConversationSessionFeeds {
  ConversationSessionFeeds({required String threadId, required ConversationObservationPort port,
    required ResourceBudget budget, required AttemptId Function() nextAttempt,
    required this.mirrors, required this.onExecution, required this.onIncarnation,
    required this.onExecutionUnavailable, required this.onSourceIdentity,
    required this.onExecutionAttempt, required this.onExecutionBaseline,
    required this.onExecutionFailure, required this.checkExecutionSource}) {
    _executionFeed = _feed<ThreadExecutionFrame>(threadId, ThreadFacet.execution, budget, nextAttempt,
        (mode) => port.openThreadExecution(threadId, mode: mode), _execution,
      (frame) => frame is ThreadExecutionData);
    _feeds = {
      ThreadFacet.execution: _executionFeed,
      ThreadFacet.metrics: _feed<ThreadMetricsFrame>(threadId, ThreadFacet.metrics, budget, nextAttempt,
        (mode) => port.openThreadMetrics(threadId, mode: mode), _metrics,
        (frame) => frame is ThreadMetricsData),
      ThreadFacet.context: _feed<ThreadContextFrame>(threadId, ThreadFacet.context, budget, nextAttempt,
        (mode) => port.openThreadContext(threadId, mode: mode), _context,
        (frame) => frame is ThreadContextData),
      ThreadFacet.configuration: _feed<ThreadConfigurationFrame>(threadId, ThreadFacet.configuration, budget, nextAttempt,
        (mode) => port.openThreadConfiguration(threadId, mode: mode), _configuration,
        (frame) => frame is ThreadConfigurationData),
      ThreadFacet.authoring: _feed<ThreadAuthoringFrame>(threadId, ThreadFacet.authoring, budget, nextAttempt,
        (mode) => port.openThreadAuthoring(threadId, mode: mode), _authoring,
        (frame) => frame is ThreadAuthoringData),
    };
  }
  final ThreadMirrors mirrors;
  final void Function(ThreadFacetStamp, InteractionIndexHeader, InteractionDelta?) onExecution;
  final void Function(ThreadFacetStamp previous) onIncarnation;
  final void Function() onExecutionUnavailable;
  final void Function(AttemptId, CreatedInputExecutionBinding?) onExecutionAttempt;
  final void Function(AttemptId, ThreadFacetStamp) onExecutionBaseline;
  final void Function(StudioFailure) onExecutionFailure;
  final void Function(ThreadFacetStamp) checkExecutionSource;
  final ThreadFacetStamp? Function(ThreadFacetStamp, {required bool baseline, required bool commit}) onSourceIdentity;
  late final Map<ThreadFacet, ConversationFacetControl> _feeds;
  late final ConversationFacetFeed<ThreadExecutionFrame> _executionFeed;
  AttemptId? _executionBaselineAttempt;
  AttemptId? get executionAttemptId => _feeds[ThreadFacet.execution]!.activeAttemptId;
  bool get executionHasBaseline => executionAttemptId != null && executionAttemptId == _executionBaselineAttempt;

  ConversationFacetFeed<F> _feed<F>(String threadId, ThreadFacet facet, ResourceBudget budget,
    AttemptId Function() nextAttempt, Future<FeedConnection<F>> Function(ThreadObservationMode) open,
    Future<int?> Function(F, bool Function()) consume, bool Function(F) isData) => ConversationFacetFeed(label: '${facet.name}:$threadId', facet: facet,
      budget: budget, nextAttempt: nextAttempt, open: open,
      onAttempt: facet == ThreadFacet.execution ? (attempt) {
        _executionBaselineAttempt = null;
        onExecutionAttempt(attempt, null);
      } : null,
      begin: (mode) {
        if (facet == ThreadFacet.execution) onExecutionUnavailable();
        mirrors.beginAttempt(facet, mode);
      }, isData: isData, consume: consume,
      synchronize: (sync) {
        if (facet == ThreadFacet.execution) {
          _executionBaselineAttempt = null;
          onExecutionFailure(sync.error ?? (sync.phase == FacetSyncPhase.reconnecting
              ? const StudioFailure(code: StudioFailureCode.superseded,
                  message: 'The original execution attempt was replaced.', retryable: false,
                  correlationId: 'submission-execution-replaced')
              : conversationCancelled));
          onExecutionUnavailable();
        }
        mirrors.synchronize(facet, sync);
      }, feedId: () => mirrors.identity(facet)?.feedId);

  void demand({required bool selected, required bool evidence, required ThreadObservationMode mode,
      required bool Function() isCurrent, required CreatedInputExecutionBinding? executionSource}) {
    for (final entry in _feeds.entries) {
      if (!isCurrent()) return;
      if (entry.key == ThreadFacet.execution) {
        _executionFeed.setDemand(selected || evidence,
          executionSource == null ? mode : ThreadObservationMode.live,
          sourceKey: executionSource?.source, openSource: executionSource?.source.openExecution,
          sourceAttempt: (attempt) {
            _executionBaselineAttempt = null;
            onExecutionAttempt(attempt, executionSource);
          });
      } else {
        entry.value.setDemand(selected, mode);
      }
    }
  }
  Future<void> retry(ThreadFacet facet) => _feeds[facet]!.retry();
  Future<CloseReport> retireUi({required bool retainExecution, DateTime? deadline, bool retry = false}) async {
    final reports = await Future.wait([
      for (final entry in _feeds.entries) if (entry.key != ThreadFacet.execution || !retainExecution)
        entry.value.close(deadline: deadline, retry: retry),
      if (retainExecution) _executionFeed.joinRetired(deadline: deadline, retry: retry),
    ]);
    return CloseReport(unresolved: [for (final report in reports) ...report.unresolved]);
  }
  void seal() { for (final feed in _feeds.values) { feed.seal(); } }
  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    seal();
    final reports = await Future.wait([for (final feed in _feeds.values) feed.close(deadline: deadline, retry: retry)]);
    return CloseReport(unresolved: [for (final report in reports) ...report.unresolved]);
  }

  bool _baseline(ThreadFacetStamp next, bool Function() onApply) {
    onSourceIdentity(next, baseline: true, commit: false);
    if (!onApply()) return false;
    final previous = onSourceIdentity(next, baseline: true, commit: true);
    if (previous != null && (previous.runtimeEpoch != next.runtimeEpoch || previous.incarnation != next.incarnation)) {
      final retirements = [for (final entry in _feeds.entries)
        if (entry.key != next.facet) entry.value.fenceProjection()];
      Object? failure;
      StackTrace? failureStack;
      for (final retire in retirements) {
        try { retire(); } catch (error, stack) { failure ??= error; failureStack ??= stack; }
      }
      try { onIncarnation(previous); } catch (error, stack) { failure ??= error; failureStack ??= stack; }
      if (failure case final error?) Error.throwWithStackTrace(error, failureStack!);
    }
    if (!onApply()) return false;
    onSourceIdentity(next, baseline: false, commit: true);
    return true;
  }
  Never _control(ThreadFacet facet, ThreadFeedIdentity identity, {StudioFailure? error,
    ThreadResyncReason? resync, ThreadFeedClosedReason? closed}) {
    mirrors.checkControl(facet, identity);
    if (error != null) throw error;
    if (resync != null || closed == ThreadFeedClosedReason.ownerReplaced) throw const StudioFailure(
      code: StudioFailureCode.superseded, message: 'The original Thread facet requires a new baseline.',
      retryable: true, correlationId: 'thread-facet-resync');
    throw StudioFailure(code: closed == ThreadFeedClosedReason.runtimeStopped
        ? StudioFailureCode.runtimeStopped : StudioFailureCode.cancelled,
      message: 'The original Thread facet closed.', retryable: false, correlationId: 'thread-facet-closed');
  }
  Future<int?> _execution(ThreadExecutionFrame frame, bool Function() onApply) async {
    switch (frame) {
      case ThreadExecutionData(:final event):
        final attempt = executionAttemptId;
        if (event case ThreadExecutionBaselineEvent(:final identity, :final stamp)) {
          mirrors.checkBaseline(ThreadFacet.execution, frame.deliverySequence, identity, stamp);
          checkExecutionSource(stamp);
          if (!_baseline(stamp, onApply)) return null;
        } else if (event case ThreadExecutionChangeEvent(:final stamp, :final baseRevision)) {
          mirrors.checkChange(ThreadFacet.execution, frame.deliverySequence, stamp, baseRevision: baseRevision);
          onSourceIdentity(stamp, baseline: false, commit: false);
          if (!onApply()) return null;
          onSourceIdentity(stamp, baseline: false, commit: true);
        }
        final sequence = await mirrors.applyExecution(frame,
          handoff: (stamp, delta) => onExecution(stamp, mirrors.execution.value.value!.interactions, delta));
        if (event is ThreadExecutionBaselineEvent && attempt != null &&
            executionAttemptId == attempt && onApply()) {
          _executionBaselineAttempt = attempt;
          onExecutionBaseline(attempt, event.stamp);
        }
        return sequence;
      case ThreadExecutionResyncRequired(:final identity, :final reason): return _control(ThreadFacet.execution, identity, resync: reason);
      case ThreadExecutionFailure(:final identity, :final error): return _control(ThreadFacet.execution, identity, error: error);
      case ThreadExecutionClosed(:final identity, :final reason): return _control(ThreadFacet.execution, identity, closed: reason);
    }
  }
  Future<int?> _metrics(ThreadMetricsFrame frame, bool Function() onApply) async {
    switch (frame) {
      case ThreadMetricsData(:final event):
        if (event case ThreadMetricsBaselineEvent(:final identity, :final stamp)) {
          mirrors.checkBaseline(ThreadFacet.metrics, frame.deliverySequence, identity, stamp);
          if (!_baseline(stamp, onApply)) return null;
        } else if (event case ThreadMetricsReplaceEvent(:final stamp)) {
          mirrors.checkChange(ThreadFacet.metrics, frame.deliverySequence, stamp);
          onSourceIdentity(stamp, baseline: false, commit: false);
          if (!onApply()) return null;
          onSourceIdentity(stamp, baseline: false, commit: true);
        }
        return mirrors.applyMetrics(frame);
      case ThreadMetricsResyncRequired(:final identity, :final reason): return _control(ThreadFacet.metrics, identity, resync: reason);
      case ThreadMetricsFailure(:final identity, :final error): return _control(ThreadFacet.metrics, identity, error: error);
      case ThreadMetricsClosed(:final identity, :final reason): return _control(ThreadFacet.metrics, identity, closed: reason);
    }
  }
  Future<int?> _context(ThreadContextFrame frame, bool Function() onApply) async {
    switch (frame) {
      case ThreadContextData(:final event):
        if (event case ThreadContextBaselineEvent(:final identity, :final stamp)) {
          mirrors.checkBaseline(ThreadFacet.context, frame.deliverySequence, identity, stamp);
          if (!_baseline(stamp, onApply)) return null;
        } else if (event case ThreadContextReplaceEvent(:final stamp)) {
          mirrors.checkChange(ThreadFacet.context, frame.deliverySequence, stamp);
          onSourceIdentity(stamp, baseline: false, commit: false);
          if (!onApply()) return null;
          onSourceIdentity(stamp, baseline: false, commit: true);
        }
        return mirrors.applyContext(frame);
      case ThreadContextResyncRequired(:final identity, :final reason): return _control(ThreadFacet.context, identity, resync: reason);
      case ThreadContextFailure(:final identity, :final error): return _control(ThreadFacet.context, identity, error: error);
      case ThreadContextClosed(:final identity, :final reason): return _control(ThreadFacet.context, identity, closed: reason);
    }
  }
  Future<int?> _configuration(ThreadConfigurationFrame frame, bool Function() onApply) async {
    switch (frame) {
      case ThreadConfigurationData(:final event):
        if (event case ThreadConfigurationBaselineEvent(:final identity, :final stamp)) {
          mirrors.checkBaseline(ThreadFacet.configuration, frame.deliverySequence, identity, stamp);
          if (!_baseline(stamp, onApply)) return null;
        } else if (event case ThreadConfigurationReplaceEvent(:final stamp)) {
          mirrors.checkChange(ThreadFacet.configuration, frame.deliverySequence, stamp);
          onSourceIdentity(stamp, baseline: false, commit: false);
          if (!onApply()) return null;
          onSourceIdentity(stamp, baseline: false, commit: true);
        }
        return mirrors.applyConfiguration(frame);
      case ThreadConfigurationResyncRequired(:final identity, :final reason): return _control(ThreadFacet.configuration, identity, resync: reason);
      case ThreadConfigurationFailure(:final identity, :final error): return _control(ThreadFacet.configuration, identity, error: error);
      case ThreadConfigurationClosed(:final identity, :final reason): return _control(ThreadFacet.configuration, identity, closed: reason);
    }
  }
  Future<int?> _authoring(ThreadAuthoringFrame frame, bool Function() onApply) async {
    switch (frame) {
      case ThreadAuthoringData(:final event):
        if (event case ThreadAuthoringBaselineEvent(:final identity, :final stamp)) {
          mirrors.checkBaseline(ThreadFacet.authoring, frame.deliverySequence, identity, stamp);
          if (!_baseline(stamp, onApply)) return null;
        } else if (event case ThreadAuthoringChangeEvent(:final stamp, :final baseRevision)) {
          mirrors.checkChange(ThreadFacet.authoring, frame.deliverySequence, stamp, baseRevision: baseRevision);
          onSourceIdentity(stamp, baseline: false, commit: false);
          if (!onApply()) return null;
          onSourceIdentity(stamp, baseline: false, commit: true);
        }
        return mirrors.applyAuthoring(frame);
      case ThreadAuthoringResyncRequired(:final identity, :final reason): return _control(ThreadFacet.authoring, identity, resync: reason);
      case ThreadAuthoringFailure(:final identity, :final error): return _control(ThreadFacet.authoring, identity, error: error);
      case ThreadAuthoringClosed(:final identity, :final reason): return _control(ThreadFacet.authoring, identity, closed: reason);
    }
  }
}
