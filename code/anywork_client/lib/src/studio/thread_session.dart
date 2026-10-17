import 'dart:async';

import '../../models.dart';
import '../../studio_ports.dart';
import '../../transport_ports.dart'
    show ChatDirection, ChatHandle, ChatTransport;
import '../chat/chat_channel.dart';
import '../chat/chat_models.dart';
import '../contracts/stamps.dart';
import '../lifecycle/resource_budget.dart';
import '../observation/latest_value.dart';
import '../observation/read_model.dart';
import 'stores/domain_sync.dart';
import 'stores/thread_directory_store.dart';
import 'thread_session_state.dart';
import 'thread_stream_gate.dart';

enum HistoryOperationOutcome {
  pending,
  awaitingObservation,
  observed,
  noChange,
  retired,
  failed,
  localCompletion,
}

/// Bounded operation diagnostics retain the server disposition after settling.
final class StudioHistoryOperation {
  const StudioHistoryOperation({
    required this.token,
    required this.attempt,
    required this.direction,
    required this.outcome,
    this.receipt,
    this.error,
  });

  final int token;
  final AttemptId? attempt;
  final TimelineDirection direction;
  final HistoryOperationOutcome outcome;
  final StudioChatReceipt? receipt;
  final String? error;
}

/// Identity of one focus intent within one view attempt. Item IDs alone cannot
/// distinguish a late A reply from a newer A -> B -> A intent.
final class StudioViewFocusRequest {
  StudioViewFocusRequest._(this.itemId, this.attempt);

  final String? itemId;
  final AttemptId? attempt;
}

/// One body request belongs to one content binding, including its late completion.
final class StudioItemBodyRequest {
  StudioItemBodyRequest._(this.itemId, this.attempt);
  final String itemId;
  final AttemptId attempt;
}

/// The application-owned runtime observer and unique content reducer for a Thread.
/// Providers attach only to [source]; [start], [retire] and [close] are explicit.
final class StudioThreadSession extends ReadModel<ThreadSessionState> {
  StudioThreadSession(
    this.threadId, {
    required this.transport,
    required this.directory,
    required this.budget,
  }) : super(ThreadSessionState(threadId: threadId)) {
    chat = ChatChannel(
      threadId: threadId,
      transport: _StudioChatTransport(transport),
      reducer: _SessionChatReducer(this),
      budget: budget,
    );
    _chatObservation = chat.state.watch(_onChatState);
  }

  final String threadId;
  final StudioTransport transport;
  final ThreadDirectoryStore directory;
  final ResourceBudget budget;
  late final ChatChannel<StudioChatSnapshot, StudioChatFrame, StudioChatReceipt>
  chat;
  late final Observation _chatObservation;
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
  final _ViewFocusTarget _viewFocus = _ViewFocusTarget();
  final Map<String, StudioItemBodyRequest> _itemBodyRequests = {};
  int _operationSequence = 0;
  _WindowOperation? _windowOperation;
  final historyOperation = LatestValue<StudioHistoryOperation?>(null);

  bool get isActive => _active;
  bool get isClosed => _closed;
  String? get confirmedViewFocus => _viewFocus.itemId;
  bool get viewFocusPending => _viewFocus.request != null;

  void start() {
    if (_closed) throw StateError('Thread session is closed');
    if (_active) return;
    _active = true;
    _lifecycleVersion++;
    _runtimeRetries = 0;
    _subscribe();
    if (state.hasSnapshot) chat.start();
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
    if (_active) chat.start();
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

  void _onChatState(ChatUiState<StudioChatSnapshot> next) {
    if (_closed || !_active) return;
    switch (next) {
      case ChatOpening<StudioChatSnapshot>():
        _retireItemBodyRequests();
        _finishHistoryOp(_windowOperation, HistoryOperationOutcome.retired);
        _viewFocus.itemId = null;
        _viewFocus.request = null;
        state = state.copyWith(
          hasChatWindow: false,
          chatVersion: null,
          chatViewId: '$threadId:${chat.currentAttemptId?.value}',
        );
        _restoreReadingWindow();
      case ChatReconnecting<StudioChatSnapshot>() ||
          ChatFailed<StudioChatSnapshot>():
        // The content channel owns its error. Thread runtime synchronization
        // changes only through its own state stream, never through ChatView.
        _retireItemBodyRequests();
        _finishHistoryOp(_windowOperation, HistoryOperationOutcome.retired);
      case ChatReady<StudioChatSnapshot>():
        _completeHistoryOpIfObserved();
      case ChatIdle<StudioChatSnapshot>() || ChatClosed<StudioChatSnapshot>():
        _retireItemBodyRequests();
        _finishHistoryOp(_windowOperation, HistoryOperationOutcome.retired);
    }
  }

  StudioChatSnapshot _applyChatFrame(
    StudioChatFrame frame, {
    bool first = false,
  }) {
    final current = first
        ? state.copyWith(hasChatWindow: false, chatVersion: null)
        : state;
    final result = applyChatFrameState(current, frame);
    switch (result.outcome) {
      case ChatFrameOutcome.applied:
        state = result.state;
        _itemBodyRequests.removeWhere(
          (id, _) => !state.history.previewedItemIds.contains(id),
        );
        _completeHistoryOpIfObserved();
      case ChatFrameOutcome.irrelevant:
        if (first) throw ChatProtocolError(result.reason.name);
      case ChatFrameOutcome.resync:
        throw ChatProtocolError(result.reason.name);
    }
    final reset = frame is StudioChatReset ? frame.snapshot : null;
    return StudioChatSnapshot(
      focusedItemId: reset?.focusedItemId ?? _viewFocus.itemId,
      version: state.chatVersion!,
      items: List.unmodifiable([
        for (final item in state.items)
          StudioChatItem(
            item,
            saved: item.saved,
            lifecycle: item.executionTerminal
                ? StudioChatLifecycle.terminal
                : StudioChatLifecycle.streaming,
          ),
      ]),
      hasOlder: state.history.hasOlder,
      hasNewer: state.history.hasNewer,
      canExtendLatest: state.history.canExtendLatest,
    );
  }

  Future<StudioChatWindow?> chatView() async {
    if (_closed || !_active || !state.hasSnapshot) return null;
    chat.start();
    await chat.ready;
    final attempt = chat.currentAttemptId;
    if (attempt == null) throw const StaleChatAttempt();
    return _SessionChatFacade(this, attempt);
  }

  void releaseHistory() {
    final next = releaseThreadHistoryState(state)
        .copyWith(hasChatWindow: false, chatVersion: null, chatViewId: null);
    if (next != state) state = next;
  }

  void jumpToLatest() {
    final next = jumpTimelineToLatestState(state);
    if (next != state) state = next;
  }

  StudioViewFocusRequest? requestViewFocus(
    String? itemId, {
    bool force = false,
  }) {
    final pending = _viewFocus.request;
    if (!force) {
      if (_viewFocus.itemId == itemId && pending == null) return null;
      if (pending != null && pending.itemId == itemId) return null;
    }
    // A different explicit focus supersedes the old window operation, including
    // a restoration whose receipt arrived before its content frame.
    _finishHistoryOp(_windowOperation, HistoryOperationOutcome.retired);
    final request = StudioViewFocusRequest._(itemId, chat.currentAttemptId);
    _viewFocus.request = request;
    return request;
  }

  bool isViewFocusCurrent(StudioViewFocusRequest request) =>
      !_closed &&
      _active &&
      request.attempt == chat.currentAttemptId &&
      identical(_viewFocus.request, request);

  void settleViewFocus(
    StudioViewFocusRequest request, {
    required bool succeeded,
  }) {
    if (!isViewFocusCurrent(request)) return;
    _viewFocus.request = null;
    if (succeeded) _viewFocus.itemId = request.itemId;
  }

  void _restoreReadingWindow() {
    final anchor = state.history.anchor;
    if (anchor == null ||
        anchor.readingIntent != TimelineReadingIntent.browseHistory)
      return;
    final request = requestViewFocus(anchor.itemId);
    if (request == null) return;
    final token = beginHistoryOp(TimelineDirection.older);
    if (token == null) {
      settleViewFocus(request, succeeded: false);
      return;
    }
    // control registers ownership, its permit and its join before waiting for
    // initial. Retire/close therefore also owns a restore awaiting first Reset.
    unawaited(
      chat
          .control((handle) => handle.focus(anchor.itemId))
          .then<void>(
            (receipt) {
              if (!isViewFocusCurrent(request)) return;
              settleViewFocus(request, succeeded: true);
              observeHistoryOp(token, receipt);
            },
            onError: (Object error, StackTrace stack) {
              if (!isViewFocusCurrent(request)) return;
              settleViewFocus(request, succeeded: false);
              failHistoryOp(token, error.toString());
            },
          ),
    );
  }

  void setTimelineAnchor(TimelineAnchor anchor) {
    final next = setTimelineAnchorState(state, anchor);
    if (next != state) state = next;
  }

  StudioItemBodyRequest? beginItemBodyLoad(String itemId) {
    final attempt = chat.currentAttemptId;
    final acceptsBodies = switch (chat.state.value) {
      ChatOpening<StudioChatSnapshot>() ||
      ChatReady<StudioChatSnapshot>() => true,
      _ => false,
    };
    if (_closed ||
        !_active ||
        !acceptsBodies ||
        attempt == null ||
        _itemBodyRequests.containsKey(itemId)) {
      return null;
    }
    final request = StudioItemBodyRequest._(itemId, attempt);
    _itemBodyRequests[itemId] = request;
    final next = beginItemBodyLoadState(state, itemId);
    if (next != state) state = next;
    return request;
  }

  bool isItemBodyRequestCurrent(StudioItemBodyRequest request) =>
      !_closed &&
      _active &&
      request.attempt == chat.currentAttemptId &&
      identical(_itemBodyRequests[request.itemId], request);

  void markItemBodyPending(StudioItemBodyRequest request) {
    if (!isItemBodyRequestCurrent(request)) return;
    _itemBodyRequests.remove(request.itemId);
    final next = markItemBodyPendingState(state, request.itemId);
    if (next != state) state = next;
  }

  void failItemBodyLoad(StudioItemBodyRequest request, String message) {
    if (!isItemBodyRequestCurrent(request)) return;
    _itemBodyRequests.remove(request.itemId);
    final next = failItemBodyLoadState(state, request.itemId, message);
    if (next != state) state = next;
  }

  void _retireItemBodyRequests() {
    _itemBodyRequests.clear();
    state = state.copyWith(
      history: state.history.copyWith(
        loadingItemIds: const {},
        pendingItemBodyIds: const {},
        unavailableItemIds: const {},
        itemBodyErrors: const {},
      ),
    );
  }

  void setHistoryLoading(TimelineDirection direction) {
    final history = state.history;
    state = state.copyWith(
      history: direction == TimelineDirection.older
          ? history.copyWith(
              isLoading: true,
              direction: direction,
              errorMessage: null,
            )
          : history.copyWith(
              isLoading: true,
              direction: direction,
              newerError: null,
            ),
    );
  }

  void setHistoryError(TimelineDirection direction, String message) {
    state = state.copyWith(
      history: direction == TimelineDirection.older
          ? state.history.copyWith(isLoading: false, errorMessage: message)
          : state.history.copyWith(isLoading: false, newerError: message),
    );
  }

  int? beginHistoryOp(TimelineDirection direction) {
    if (_closed || !_active || state.history.isLoading) return null;
    final token = ++_operationSequence;
    _windowOperation = _WindowOperation(
      token: token,
      attempt: chat.currentAttemptId,
      direction: direction,
    );
    _publishHistoryOperation(
      _windowOperation!,
      HistoryOperationOutcome.pending,
    );
    setHistoryLoading(direction);
    return token;
  }

  void observeHistoryOp(int token, StudioChatReceipt receipt) {
    final operation = _windowOperation;
    if (operation == null || operation.token != token) return;
    if (operation.attempt != chat.currentAttemptId) {
      _finishHistoryOp(operation, HistoryOperationOutcome.retired);
      return;
    }
    // disposition is authoritative. Equal versions prove only observation.
    operation.disposition = receipt.disposition;
    operation.targetVersion = receipt.version;
    operation.receipt = receipt;
    if (receipt.disposition == StudioChatDisposition.noChange) {
      // NoChange is an explicit control result. Its shared session version may
      // include publications outside this view that the content pump skips.
      _finishHistoryOp(operation, HistoryOperationOutcome.noChange);
      return;
    }
    _publishHistoryOperation(
      operation,
      HistoryOperationOutcome.awaitingObservation,
    );
    _completeHistoryOpIfObserved();
  }

  void finishHistoryLoad() => _finishHistoryOp(
    _windowOperation,
    HistoryOperationOutcome.localCompletion,
  );

  void failHistoryOp(int token, String message) {
    final operation = _windowOperation;
    if (operation == null || operation.token != token) return;
    _windowOperation = null;
    _publishHistoryOperation(
      operation,
      HistoryOperationOutcome.failed,
      error: message,
    );
    setHistoryError(operation.direction, message);
  }

  void _completeHistoryOpIfObserved() {
    final operation = _windowOperation;
    if (operation == null) return;
    if (operation.attempt != chat.currentAttemptId) {
      _finishHistoryOp(operation, HistoryOperationOutcome.retired);
      return;
    }
    final target = operation.targetVersion;
    final delivered = state.chatVersion;
    if (target != null && delivered != null && delivered >= target) {
      _finishHistoryOp(operation, HistoryOperationOutcome.observed);
    }
  }

  void _finishHistoryOp(
    _WindowOperation? operation, [
    HistoryOperationOutcome outcome = HistoryOperationOutcome.retired,
  ]) {
    if (operation == null || !identical(_windowOperation, operation)) return;
    _windowOperation = null;
    _publishHistoryOperation(operation, outcome);
    if (state.history.isLoading) {
      state = state.copyWith(history: state.history.copyWith(isLoading: false));
    }
  }

  void _publishHistoryOperation(
    _WindowOperation operation,
    HistoryOperationOutcome outcome, {
    String? error,
  }) {
    historyOperation.publish(
      StudioHistoryOperation(
        token: operation.token,
        attempt: operation.attempt,
        direction: operation.direction,
        outcome: outcome,
        receipt: operation.receipt,
        error: error,
      ),
    );
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
    if (state.hasSnapshot) chat.retry();
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
    _retireItemBodyRequests();
    _lifecycleVersion++;
    _cancelRuntimeResync();
    _runtimeRetry?.cancel();
    _runtimeRetry = null;
    final current = _runtime;
    _runtime = null;
    if (current != null) unawaited(_cancelRuntime(current));
    chat.setDemand(false);
    _finishHistoryOp(_windowOperation);
    releaseHistory();
    final reports = await Future.wait([
      chat.joinRetired(deadline: deadline),
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
    final content = await chat.close(deadline: deadline);
    _chatObservation.cancel();
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
      chat.retryCleanup(),
      _joinRuntime(deadline),
    ]);
    return CloseReport(
      unresolved: [for (final report in reports) ...report.unresolved],
    );
  }
}

final class _SessionChatReducer
    implements ChatReducer<StudioChatSnapshot, StudioChatFrame> {
  const _SessionChatReducer(this.owner);
  final StudioThreadSession owner;

  @override
  StudioChatSnapshot reset(StudioChatSnapshot snapshot) =>
      owner._applyChatFrame(StudioChatReset(snapshot), first: true);
  @override
  StudioChatSnapshot apply(StudioChatSnapshot current, StudioChatFrame frame) =>
      owner._applyChatFrame(frame);
  @override
  int version(StudioChatSnapshot snapshot) => snapshot.version;
}

final class _StudioChatTransport
    implements
        ChatTransport<StudioChatSnapshot, StudioChatFrame, StudioChatReceipt> {
  const _StudioChatTransport(this.transport);
  final StudioTransport transport;

  @override
  Future<ChatHandle<StudioChatSnapshot, StudioChatFrame, StudioChatReceipt>>
  open(String threadId) async {
    final source = transport;
    if (source is! ChatWindowReader) {
      throw StateError('ChatWindowReader is required for chat content');
    }
    return _StudioChatHandle(
      await (source as ChatWindowReader).openChatWindow(threadId),
    );
  }
}

final class _StudioChatHandle
    implements
        ChatHandle<StudioChatSnapshot, StudioChatFrame, StudioChatReceipt> {
  const _StudioChatHandle(this.window);
  final StudioChatWindow window;

  @override
  Future<StudioChatSnapshot> initial() => window.initial();
  @override
  Future<StudioChatFrame?> next() => window.next();
  @override
  Future<StudioChatReceipt> load(ChatDirection direction) => window.load(
    direction == ChatDirection.older
        ? TimelineDirection.older
        : TimelineDirection.newer,
  );
  @override
  Future<StudioChatReceipt> extendLatest() => window.extendLatest();
  @override
  Future<StudioChatReceipt> focus(String? itemId) => window.focus(itemId);
  @override
  Future<StudioChatReceipt> expand(String itemId) => window.expandItem(itemId);
  @override
  void requestClose() => window.requestClose();
  @override
  Future<void> close() => window.close();
}

final class _SessionChatFacade implements StudioChatWindow {
  const _SessionChatFacade(this.owner, this.attempt);
  final StudioThreadSession owner;
  final AttemptId attempt;

  void _check() {
    if (owner.chat.currentAttemptId != attempt) throw const StaleChatAttempt();
  }

  Future<StudioChatReceipt> _control(
    Future<StudioChatReceipt> Function(
      ChatHandle<StudioChatSnapshot, StudioChatFrame, StudioChatReceipt>,
    )
    action,
  ) {
    _check();
    return owner.chat.control(action);
  }

  @override
  Future<StudioChatSnapshot> initial() {
    _check();
    return owner.chat.ready;
  }

  @override
  Future<StudioChatFrame?> next() => Future.error(
    StateError('The Client owns the unique ChatView content pump'),
  );
  @override
  Future<StudioChatReceipt> load(TimelineDirection direction) => _control(
    (view) => view.load(
      direction == TimelineDirection.older
          ? ChatDirection.older
          : ChatDirection.newer,
    ),
  );
  @override
  Future<StudioChatReceipt> extendLatest() =>
      _control((view) => view.extendLatest());
  @override
  Future<StudioChatReceipt> focus(String? itemId) =>
      _control((view) => view.focus(itemId));
  @override
  Future<StudioChatReceipt> expandItem(String itemId) =>
      _control((view) => view.expand(itemId));
  @override
  void requestClose() {
    _check();
    owner.chat.setDemand(false);
  }

  @override
  Future<void> close() async {
    requestClose();
    await owner.chat.joinRetired();
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

final class _ViewFocusTarget {
  String? itemId;
  StudioViewFocusRequest? request;
}

final class _WindowOperation {
  _WindowOperation({
    required this.token,
    required this.attempt,
    required this.direction,
  });
  final int token;
  final AttemptId? attempt;
  final TimelineDirection direction;
  int? targetVersion;
  StudioChatDisposition? disposition;
  StudioChatReceipt? receipt;
}
