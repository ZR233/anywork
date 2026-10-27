import 'dart:async';

import '../../models.dart';
import '../../studio_ports.dart';
import '../chat/timeline_channel.dart';
import '../contracts/stamps.dart';
import '../lifecycle/resource_budget.dart';
import '../observation/read_model.dart';
import 'stores/domain_sync.dart';
import 'stores/thread_directory_store.dart';
import 'thread_session_state.dart';
import 'thread_stream_gate.dart';

final class StudioThreadSession extends ReadModel<ThreadSessionState> {
  StudioThreadSession(
    this.threadId, {
    required this.transport,
    required this.directory,
    required this.budget,
  }) : super(ThreadSessionState(threadId: threadId)) {
    timeline = StudioTimelineChannel(
      threadId: threadId,
      transport: transport,
      budget: budget,
    );
  }

  final String threadId;
  final StudioTransport transport;
  final ThreadDirectoryStore directory;
  final ResourceBudget budget;

  /// 该会话的唯一内容连接：有界基线、连续补丁与按代次查询 scope。
  ///
  /// 它不携带 Thread 状态，也不拥有已加载消息集合；正文由内容泵交付给当前展示 lease
  /// （design/26 §26.8）。
  late final StudioTimelineChannel timeline;
  final Map<int, _RuntimeBinding> _runtimeBindings = {};
  _RuntimeBinding? _runtime;
  _RuntimeResync? _runtimeResync;
  Timer? _runtimeRetry;
  int _runtimeSequence = 0;
  int _runtimeRetries = 0;
  int _lifecycleVersion = 0;
  bool _active = false;
  bool _closed = false;
  Future<CloseReport>? _closing;

  bool get isActive => _active;
  bool get isClosed => _closed;

  void start() {
    if (_closed) throw StateError('Thread session is closed');
    if (_active) return;
    _active = true;
    final version = ++_lifecycleVersion;
    _runtimeRetries = 0;
    _subscribe();
    if (_closed || !_active || version != _lifecycleVersion) return;
    // 内容需求与状态观察独立：会话显示期间始终存在一条有界内容连接。
    timeline.start();
  }

  void applySnapshot(ThreadWorkspace snapshot) {
    if (_closed || snapshot.thread.id != threadId) return;
    StudioThread? identity;
    for (final thread in [
      ...directory.state.window.threads,
      ...directory.state.overlayThreads,
    ]) {
      if (thread.id == threadId) {
        identity = thread;
        break;
      }
    }
    final next = applyThreadSnapshotState(
      state,
      snapshot,
      directoryThread: identity,
    );
    if (next != state) state = next;
  }

  void applyNotification(ThreadNotificationFrame frame) {
    if (_closed) return;
    final next = applyThreadNotificationState(state, frame);
    if (next != state) state = next;
  }

  /// Replaces only the runtime observation and waits for that binding's first
  /// owner baseline. Query revisions cannot repair a subscription watermark.
  Future<ThreadWorkspace> resyncRuntime() {
    if (_closed || !_active) {
      return Future.error(ThreadStateResyncCancelled(threadId));
    }
    final pending = _runtimeResync;
    if (pending != null) return pending.result.future;
    final resync = _RuntimeResync(++_lifecycleVersion);
    _runtimeResync = resync;
    _runtimeRetry?.cancel();
    _runtimeRetry = null;
    _runtime = null;
    unawaited(_resyncRuntime(resync));
    return resync.result.future;
  }

  Future<void> _resyncRuntime(_RuntimeResync resync) async {
    try {
      final retired = List.of(_runtimeBindings.values);
      final cancellations = [
        for (final binding in retired) _cancelRuntime(binding),
      ];
      markResync(null);
      await Future.wait(cancellations);
      if (_closed || !_active || resync.version != _lifecycleVersion) {
        throw ThreadStateResyncCancelled(threadId);
      }
      for (final binding in retired) {
        if (binding.cleanupError case final error?) {
          markResync(error, failed: true);
          throw error;
        }
      }
      _subscribe(firstSnapshot: resync.result);
      await resync.result.future;
    } catch (error, stackTrace) {
      if (!resync.result.isCompleted) {
        resync.result.completeError(error, stackTrace);
      }
    } finally {
      if (identical(_runtimeResync, resync)) _runtimeResync = null;
      resync.joined.complete();
    }
  }

  void _cancelRuntimeResync() {
    final resync = _runtimeResync;
    if (resync != null && !resync.result.isCompleted) {
      resync.result.completeError(ThreadStateResyncCancelled(threadId));
    }
  }

  void _subscribe({Completer<ThreadWorkspace>? firstSnapshot}) {
    if (_closed || !_active || _runtime != null) {
      if (firstSnapshot != null && !firstSnapshot.isCompleted) {
        firstSnapshot.completeError(ThreadStateResyncCancelled(threadId));
      }
      return;
    }
    final ResourcePermit permit;
    try {
      permit = budget.acquire(
        ResourceKind.observer,
        owner: 'runtime:$threadId:${_runtimeSequence + 1}',
        phase: ResourcePhase.opening,
      );
    } catch (error) {
      markResync(error, failed: true);
      if (firstSnapshot != null && !firstSnapshot.isCompleted) {
        firstSnapshot.completeError(error);
      }
      return;
    }
    final binding = _RuntimeBinding(
      ++_runtimeSequence,
      permit,
      firstSnapshot: firstSnapshot,
    );
    _runtime = binding;
    _runtimeBindings[binding.id] = binding;
    clearStreamEpoch();
    try {
      if (!_isRuntimeCurrent(binding)) return;
      binding.subscription = transport
          .subscribeThread(threadId)
          .listen(
            (frame) => _onRuntimeFrame(binding, frame),
            onError: (Object error, StackTrace stack) =>
                _onRuntimeFailure(binding, error),
            onDone: () => _onRuntimeFailure(
              binding,
              StateError('Thread state stream ended'),
            ),
            // Cancellation belongs to this binding. Auto-cancel would let the
            // Stream initiate cleanup outside the owner's explicit join path.
            cancelOnError: false,
          );
      if (!binding.retired) permit.mark(ResourcePhase.active);
    } catch (error) {
      _onRuntimeFailure(binding, error);
    } finally {
      binding.installed.complete();
    }
  }

  bool _isRuntimeCurrent(_RuntimeBinding binding) =>
      !_closed && _active && !binding.retired && identical(_runtime, binding);

  void _onRuntimeFrame(_RuntimeBinding binding, ThreadStreamFrame frame) {
    if (!_isRuntimeCurrent(binding)) return;
    final id = switch (frame) {
      ThreadSnapshotFrame(:final workspace) => workspace.thread.id,
      ThreadNotificationFrame(:final threadId) => threadId,
      ThreadResyncRequiredFrame(:final threadId) => threadId,
    };
    if (id != threadId) return;
    switch (frame) {
      case ThreadSnapshotFrame(:final workspace):
        applySnapshot(workspace);
        final firstSnapshot = binding.firstSnapshot;
        if (_isRuntimeCurrent(binding) &&
            firstSnapshot != null &&
            !firstSnapshot.isCompleted) {
          firstSnapshot.complete(workspace);
        }
      case ThreadResyncRequiredFrame(:final dropped, :final epoch):
        _onRuntimeFailure(
          binding,
          ThreadStateLagged(threadId: threadId, dropped: dropped, epoch: epoch),
        );
      case ThreadNotificationFrame():
        switch (classifyThreadFrame(state.watermark, frame)) {
          case ThreadFrameDecision.drop:
            return;
          case ThreadFrameDecision.resync:
            _onRuntimeFailure(
              binding,
              ThreadStateContinuityError(
                threadId: threadId,
                expected: state.watermark,
                epoch: frame.epoch,
                baseRevision: frame.baseRevision,
                revision: frame.revision,
              ),
            );
          case ThreadFrameDecision.apply:
            applyNotification(frame);
            // A delivered incremental owner fact proves this stream made
            // progress. Baselines alone do not: snapshot/EOF or snapshot/lagged
            // loops still exhaust the bounded consecutive-failure policy.
            _runtimeRetries = 0;
        }
    }
  }

  void _onRuntimeFailure(_RuntimeBinding binding, Object error) {
    if (!_isRuntimeCurrent(binding)) return;
    _runtime = null;
    binding.retired = true;
    final firstSnapshot = binding.firstSnapshot;
    if (firstSnapshot != null && !firstSnapshot.isCompleted) {
      firstSnapshot.completeError(error);
    }
    final version = _lifecycleVersion;
    final exhausted = _runtimeRetries >= const RetryPolicy().delays.length;
    markResync(error, failed: exhausted);
    unawaited(_recoverRuntime(binding, version, exhausted));
  }

  Future<void> _recoverRuntime(
    _RuntimeBinding binding,
    int version,
    bool exhausted,
  ) async {
    await _cancelRuntime(binding);
    if (_closed || !_active || version != _lifecycleVersion) return;
    if (binding.cleanupError case final error?) {
      markResync(error, failed: true);
      return;
    }
    if (exhausted) return;
    final delay = const RetryPolicy().delays[_runtimeRetries++];
    _runtimeRetry?.cancel();
    _runtimeRetry = Timer(delay, () {
      _runtimeRetry = null;
      if (version == _lifecycleVersion) _subscribe();
    });
  }

  Future<void> _cancelRuntime(_RuntimeBinding binding) {
    final firstSnapshot = binding.firstSnapshot;
    if (firstSnapshot != null && !firstSnapshot.isCompleted) {
      firstSnapshot.completeError(ThreadStateResyncCancelled(threadId));
    }
    final closing = binding.closing;
    if (closing != null) return closing;
    binding.retired = true;
    binding.permit.mark(ResourcePhase.retiring);
    return binding.closing = () async {
      // A synchronous stream callback can retire while listen is installing.
      await binding.installed.future;
      try {
        await binding.subscription?.cancel();
        binding.cleanupError = null;
        binding.permit.release();
        _runtimeBindings.remove(binding.id);
      } catch (error) {
        binding.cleanupError = error;
        binding.permit.mark(ResourcePhase.unresolved);
      }
    }();
  }

  void markResync(Object? error, {bool failed = false}) {
    final sync = DomainSyncStatus(
      phase: failed ? DomainSyncPhase.failed : DomainSyncPhase.reconnecting,
      errorMessage: error?.toString(),
    );
    if (sync != state.sync) state = state.copyWith(sync: sync);
  }

  void clearStreamEpoch() {
    if (state.streamEpoch != null) state = state.copyWith(streamEpoch: null);
  }

  void retry() {
    if (_closed || !_active) return;
    _lifecycleVersion++;
    _cancelRuntimeResync();
    _runtimeRetries = 0;
    _runtimeRetry?.cancel();
    _runtimeRetry = null;
    final current = _runtime;
    _runtime = null;
    if (current == null) {
      _subscribe();
    } else {
      current.retired = true;
      unawaited(_retryRuntime(current, _lifecycleVersion));
    }
    timeline.refresh();
  }

  Future<void> _retryRuntime(_RuntimeBinding binding, int version) async {
    await _cancelRuntime(binding);
    if (binding.cleanupError case final error?) {
      markResync(error, failed: true);
      return;
    }
    if (!_closed && _active && version == _lifecycleVersion) _subscribe();
  }

  Future<CloseReport> retire({DateTime? deadline}) async {
    _active = false;
    _lifecycleVersion++;
    _cancelRuntimeResync();
    _runtimeRetry?.cancel();
    _runtimeRetry = null;
    final current = _runtime;
    _runtime = null;
    if (current != null) unawaited(_cancelRuntime(current));
    timeline.setDemand(false);
    final reports = await Future.wait([
      timeline.joinRetired(deadline: deadline),
      _joinRuntime(deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }

  Future<CloseReport> _joinRuntime(DateTime? deadline) async {
    final resync = _runtimeResync;
    final retired = [
      for (final binding in _runtimeBindings.values)
        if (binding.retired) binding,
    ];
    final tasks = [
      if (resync != null) resync.joined.future,
      for (final binding in retired)
        if (binding.closing case final closing?) closing,
    ];
    if (deadline == null) {
      await Future.wait(tasks);
    } else {
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        try {
          await Future.wait(tasks).timeout(remaining);
        } on TimeoutException {
          // The original subscription and permit remain owned in the map.
        }
      }
    }
    return CloseReport(
      unresolved: [
        if (resync != null && !resync.joined.isCompleted)
          UnresolvedResource(
            owner: 'runtime-resync:$threadId',
            attemptId: AttemptId(resync.version),
            reason: StateError('Runtime resync join pending'),
          ),
        for (final binding in retired)
          if (_runtimeBindings.containsKey(binding.id))
            UnresolvedResource(
              owner: 'runtime:$threadId',
              attemptId: AttemptId(binding.id),
              reason:
                  binding.cleanupError ??
                  StateError('Runtime cancellation pending'),
            ),
      ],
    );
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      _closing ??= _close(deadline);

  Future<CloseReport> _close(DateTime? deadline) async {
    _closed = true;
    final retired = await retire(deadline: deadline);
    final content = await timeline.close(deadline: deadline);
    final unresolved = {
      for (final entry in [...retired.unresolved, ...content.unresolved])
        '${entry.owner}:${entry.attemptId.value}': entry,
    };
    return CloseReport(unresolved: unresolved.values);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    for (final binding in List.of(_runtimeBindings.values)) {
      if (binding.cleanupError != null) {
        binding.closing = null;
        unawaited(_cancelRuntime(binding));
      }
    }
    final reports = await Future.wait([
      timeline.retryCleanup(),
      _joinRuntime(deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}

final class _RuntimeBinding {
  _RuntimeBinding(this.id, this.permit, {this.firstSnapshot});
  final int id;
  final ResourcePermit permit;
  final Completer<ThreadWorkspace>? firstSnapshot;
  final Completer<void> installed = Completer();
  // _cancelRuntime joins this binding's cancel and retains failures in the owner map.
  // ignore: cancel_subscriptions
  StreamSubscription<ThreadStreamFrame>? subscription;
  Future<void>? closing;
  bool retired = false;
  Object? cleanupError;
}

final class _RuntimeResync {
  _RuntimeResync(this.version);

  final int version;
  final Completer<ThreadWorkspace> result = Completer();
  final Completer<void> joined = Completer();
}
