import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../bridge/studio_bridge.dart';
import '../bridge/thread_stream_gate.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import 'chat_view_metrics.dart';
import 'domain_sync.dart';
import 'thread_directory_store.dart';
import 'thread_session_state.dart';

part 'thread_session_store.g.dart';

/// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
///
/// keepAlive 保留 last-known canonical runtime 状态；订阅寿命用 onCancel/onResume/onDispose。
/// 聊天正文按显示需求消费（design/25 §25.4）：无观察者时关闭权威 ChatView 并清正文镜像，
/// 恢复观察后重开窗口、重获最新有界 Reset——Rust 执行、可靠事实保存不依赖 Dart 是否观察。
@Riverpod(keepAlive: true)
class ThreadSessionStore extends _$ThreadSessionStore {
  BridgeThreadAttachment? _attachment;
  var _closed = false;

  /// 当前内容绑定：一个绑定独占一个 native 窗口与它的内容泵。
  ///
  /// 绑定身份（`generation`）用于拒收迟到回调：旧绑定只清理自己的句柄，泵只把帧写进
  /// 仍是当前的绑定；换代/关闭后的迟到帧一律丢弃。
  _ChatBinding? _binding;
  Future<_ChatBinding?>? _bindingOpening;
  int _bindingGeneration = 0;
  int _resyncAttempts = 0;
  int _windowOperationSeq = 0;
  _WindowOperation? _windowOperation;
  Completer<void>? _subscriptionReleaseHold;

  @override
  ThreadSessionState build(String threadId) {
    _closed = false;
    final bridge = ref.watch(studioBridgeProvider);
    ref.onCancel(() {
      unawaited(_releaseSubscription(clearHistory: true));
      _closeBinding();
    });
    ref.onResume(() {
      if (_closed || _attachment != null) return;
      scheduleMicrotask(() {
        if (_closed || !ref.mounted || _attachment != null) return;
        clearStreamEpoch();
        _attach(bridge);
        unawaited(_openChatBinding());
      });
    });
    ref.onDispose(() {
      _closed = true;
      unawaited(_releaseSubscription(clearHistory: false));
      _closeBinding();
    });
    scheduleMicrotask(() {
      if (_closed || !ref.mounted) return;
      _attach(bridge);
    });
    return ThreadSessionState(threadId: threadId);
  }

  void applySnapshot(ThreadWorkspace snapshot) {
    // design/18 §18.11.1：会话快照的身份事实先经目录窗口单行合并（会话
    // 自身事实为准、updatedAt 单调、不推进目录水位），workspace 再从
    // 合并后的行读取——否则不推进目录水位的 mode 变更会永远停留在旧值。
    ref
        .read(threadDirectoryStoreProvider.notifier)
        .replaceIdentity(snapshot.thread);
    final directory = _directoryThread(snapshot.thread.id);
    final next = applyThreadSnapshotState(
      state,
      snapshot,
      directoryThread: directory,
    );
    if (next == state) return;
    state = next;
  }

  void applyNotification(ThreadNotificationFrame frame) {
    final next = applyThreadNotificationState(state, frame);
    if (next == state) return;
    state = next;
  }

  /// 唯一 chat 写入路径：内容泵把权威帧交给唯一 reducer。
  ///
  /// `binding` 是帧所属的绑定：已关闭/已换代的绑定迟到帧直接丢弃。
  void _applyFrame(_ChatBinding binding, StudioChatFrame frame) {
    if (!ref.mounted || binding.closed || !identical(binding, _binding)) {
      return;
    }
    final result = applyChatFrameState(state, frame);
    switch (result.outcome) {
      case ChatFrameOutcome.applied:
        ChatViewMetrics.framesApplied += 1;
        state = result.state;
        _completeHistoryOpIfObserved();
      case ChatFrameOutcome.irrelevant:
        return;
      case ChatFrameOutcome.resync:
        ChatViewMetrics.framesResync += 1;
        unawaited(_resyncBinding(binding));
    }
  }

  void releaseHistory() {
    final next = releaseThreadHistoryState(state);
    if (next == state) return;
    ChatViewMetrics.historyClears += 1;
    state = next;
  }

  void jumpToLatest() {
    final next = jumpTimelineToLatestState(state);
    if (next == state) return;
    state = next;
  }

  /// 写入阅读锚点（浏览历史意图标记脱离底部）。
  void setTimelineAnchor(TimelineAnchor anchor) {
    final next = setTimelineAnchorState(state, anchor);
    if (next == state) return;
    state = next;
  }

  void beginItemBodyLoad(String itemId) {
    final next = beginItemBodyLoadState(state, itemId);
    if (next == state) return;
    state = next;
  }

  void markItemBodyPending(String itemId) {
    final next = markItemBodyPendingState(state, itemId);
    if (next == state) return;
    state = next;
  }

  void failItemBodyLoad(String itemId, String message) {
    final next = failItemBodyLoadState(state, itemId, message);
    if (next == state) return;
    state = next;
  }

  /// 确保该会话的权威内容窗口已打开并持续消费，返回窗口句柄供控制操作使用。
  ///
  /// 绑定生命周期与 store 的订阅寿命一致：打开后内容泵立即采纳首帧（Reset）并持续接收
  /// `next`；普通翻页、换焦点、追新、正文展开都操作同一窗口，内容由唯一出口交付。
  /// 未建立权威快照前不打开；打开结果被换代/关闭取代时立即关闭。
  Future<StudioChatWindow?> chatView() async {
    final binding = await _openChatBinding();
    return binding?.window;
  }

  /// 打开（或复用）当前内容绑定；泵任务由绑定自己持有。
  Future<_ChatBinding?> _openChatBinding() {
    if (_closed || !ref.mounted || !state.hasSnapshot) {
      return Future<void>.value().then((_) => null);
    }
    final existing = _binding;
    if (existing != null && !existing.closed) {
      return Future.value(existing);
    }
    return _bindingOpening ??= () async {
      final generation = ++_bindingGeneration;
      ChatViewMetrics.bindingOpens += 1;
      try {
        final source = ref.read(studioBridgeDataSourceProvider);
        if (source is! ChatWindowReader) {
          markResync(
            StateError('ChatWindowReader is required for chat content'),
            failed: true,
          );
          return null;
        }
        final reader = source as ChatWindowReader;
        final window = await reader.openChatWindow(threadId);
        if (!ref.mounted ||
            _closed ||
            !state.hasSnapshot ||
            generation != _bindingGeneration) {
          await window.close();
          return null;
        }
        final binding = _ChatBinding(generation, window);
        _binding = binding;
        final initial = await window.initial();
        if (binding.closed || !identical(binding, _binding)) {
          await window.close();
          return null;
        }
        _applyFrame(binding, StudioChatReset(initial));
        if (identical(binding, _binding)) {
          _resyncAttempts = 0;
        }
        unawaited(_pumpFrames(binding));
        return binding;
      } catch (error) {
        if (generation == _bindingGeneration && ref.mounted && !_closed) {
          markResync(error, failed: true);
        }
        return null;
      } finally {
        _bindingOpening = null;
      }
    }();
  }

  /// 内容泵：一个绑定同时至多一个未完成的 `next`；reduce 完上一帧后再取下一帧。
  Future<void> _pumpFrames(_ChatBinding binding) async {
    while (!binding.closed) {
      final StudioChatFrame? frame;
      try {
        frame = await binding.window.next();
      } catch (_) {
        // 传输故障：废弃当前绑定并重开，保留最后有效内容等下一次权威 Reset。
        await _resyncBinding(binding);
        return;
      }
      if (binding.closed) return;
      if (frame == null) {
        binding.closed = true;
        return;
      }
      _applyFrame(binding, frame);
      if (!identical(binding, _binding)) return;
    }
  }

  /// 连续性缺口或传输故障：废弃当前绑定，稍作退避后重开同一会话的有界窗口。
  ///
  /// 恢复只重建受影响资源的观察，不重启业务 owner；期间保留最后有效内容，
  /// 不把数据不可用渲染为空列表（design/25 §25.9）。
  Future<void> _resyncBinding(_ChatBinding binding) async {
    if (!identical(binding, _binding)) return;
    _closeBinding();
    final attempts = ++_resyncAttempts;
    if (attempts > 1) {
      await Future<void>.delayed(
        Duration(milliseconds: 50 * (attempts - 1).clamp(0, 10)),
      );
    }
    if (_closed || !ref.mounted) return;
    unawaited(_openChatBinding());
  }

  /// 关闭当前内容绑定：立即让绑定失效（迟到帧拒收），再可靠关闭 native 窗口。
  void _closeBinding() {
    final binding = _binding;
    final closedGeneration = _bindingGeneration;
    _binding = null;
    _bindingGeneration++;
    final op = _windowOperation;
    if (op != null && op.generation == closedGeneration) {
      _windowOperation = null;
    }
    if (binding == null) return;
    binding.closed = true;
    ChatViewMetrics.bindingCloses += 1;
    unawaited(binding.window.close());
    // Riverpod 禁止在 onCancel/onDispose 里读写 notifier state；收束后的投影更新延后到微任务。
    scheduleMicrotask(() => _afterBindingClosed(closedGeneration));
  }

  void _afterBindingClosed(int closedGeneration) {
    if (!ref.mounted || _closed || _binding != null) return;
    if (_bindingGeneration != closedGeneration + 1) return;
    var history = state.history;
    if (_windowOperation == null && history.isLoading) {
      history = history.copyWith(isLoading: false);
    }
    if (!state.hasChatWindow && history == state.history) return;
    state = state.copyWith(hasChatWindow: false, history: history);
  }

  void setHistoryLoading(TimelineDirection direction) {
    final history = state.history;
    final next = direction == TimelineDirection.older
        ? history.copyWith(
            isLoading: true,
            direction: direction,
            errorMessage: null,
          )
        : history.copyWith(
            isLoading: true,
            direction: direction,
            newerError: null,
          );
    if (next == history) return;
    state = state.copyWith(history: next);
  }

  void setHistoryError(TimelineDirection direction, String message) {
    final history = direction == TimelineDirection.older
        ? state.history.copyWith(isLoading: false, errorMessage: message)
        : state.history.copyWith(isLoading: false, newerError: message);
    if (history == state.history) return;
    state = state.copyWith(history: history);
  }

  /// 回执到达或代次已变时结束加载，不改另一方向的错误。
  void finishHistoryLoad() {
    _finishHistoryOp(_windowOperation);
  }

  /// 在第一个 await 之前占位：同一 view 同一方向只允许一项在途控制操作。
  int? beginHistoryOp(TimelineDirection direction) {
    if (!ref.mounted || _closed) return null;
    if (state.history.isLoading) return null;
    final token = ++_windowOperationSeq;
    _windowOperation = _WindowOperation(
      token: token,
      generation: _bindingGeneration,
      direction: direction,
    );
    setHistoryLoading(direction);
    return token;
  }

  /// 回执已到：有内容变化时等对应帧进入 read model；NoChange 立即结束本轮。
  void observeHistoryOp(int token, StudioChatReceipt receipt) {
    final op = _windowOperation;
    if (op == null || op.token != token) return;
    if (op.generation != _bindingGeneration) {
      _finishHistoryOp(op);
      return;
    }
    final current = state.chatVersion;
    if (current != null && receipt.version <= current) {
      _finishHistoryOp(op);
      return;
    }
    _windowOperation = op.waitingFor(receipt.version);
    _completeHistoryOpIfObserved();
  }

  void failHistoryOp(int token, String message) {
    final op = _windowOperation;
    if (op == null || op.token != token) return;
    _windowOperation = null;
    setHistoryError(op.direction, message);
  }

  void _completeHistoryOpIfObserved() {
    final op = _windowOperation;
    if (op == null || op.targetVersion == null) return;
    final current = state.chatVersion;
    if (current != null && current >= op.targetVersion!) {
      _finishHistoryOp(op);
    }
  }

  void _finishHistoryOp(_WindowOperation? op) {
    if (op == null) return;
    if (!identical(_windowOperation, op) &&
        _windowOperation?.token != op.token) {
      return;
    }
    _windowOperation = null;
    if (!state.history.isLoading) return;
    state = state.copyWith(history: state.history.copyWith(isLoading: false));
  }

  /// 测试用：挂起旧订阅释放，验证迟到清理不能清空新窗口。
  @visibleForTesting
  void holdNextSubscriptionRelease() {
    _subscriptionReleaseHold = Completer<void>();
  }

  /// 测试用：放行被挂起的旧订阅释放。
  @visibleForTesting
  void releaseHeldSubscription() {
    final hold = _subscriptionReleaseHold;
    _subscriptionReleaseHold = null;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  /// 局部重同步：保留 workspace / 窗口，只暴露传输错误。
  void markResync(Object? error, {bool failed = false}) {
    final sync = DomainSyncStatus(
      phase: failed ? DomainSyncPhase.failed : DomainSyncPhase.reconnecting,
      errorMessage: error?.toString(),
    );
    if (sync == state.sync) return;
    state = state.copyWith(sync: sync);
  }

  void clearStreamEpoch() {
    if (state.streamEpoch == null) return;
    state = state.copyWith(streamEpoch: null);
  }

  void retry() {
    final attachment = _attachment;
    if (attachment == null) return;
    clearStreamEpoch();
    unawaited(attachment.resubscribe());
  }

  void _attach(StudioBridge bridge) {
    if (_attachment != null || _closed) return;
    _attachment = bridge.attachThread(
      threadId,
      readWatermark: () => state.watermark,
      onSubscriptionStarting: clearStreamEpoch,
      onFrame: _onFrame,
      onClosed: (error) => markResync(error, failed: error != null),
    );
  }

  void _onFrame(ThreadStreamFrame frame) {
    if (!ref.mounted) return;
    switch (classifyThreadFrame(state.watermark, frame)) {
      case ThreadFrameDecision.drop:
        return;
      case ThreadFrameDecision.resync:
        markResync(null);
        unawaited(_attachment?.resubscribe());
        return;
      case ThreadFrameDecision.apply:
        switch (frame) {
          case ThreadSnapshotFrame(:final workspace):
            applySnapshot(workspace);
          case ThreadNotificationFrame():
            applyNotification(frame);
          case ThreadResyncRequiredFrame():
            markResync(null);
            unawaited(_attachment?.resubscribe());
        }
    }
  }

  Future<void> _releaseSubscription({required bool clearHistory}) async {
    final attachment = _attachment;
    _attachment = null;
    final hold = _subscriptionReleaseHold;
    if (hold != null) {
      await hold.future;
    }
    await attachment?.release();
    if (!clearHistory || !ref.mounted) return;
    if (_attachment != null || _binding != null) return;
    releaseHistory();
  }

  StudioThread? _directoryThread(String id) {
    // 仅在 Thread 快照落地时读取一次目录条目，不是目录增量订阅。
    // 目录元数据属于 ThreadDirectoryStore；本族只消费 Thread 有序流，
    // 不回绑 workspace.thread，也不因目录移除就地清空 workspace。
    // keepAlive 不会随目录项消失自动释放，移除须调用 releaseThreadSession。
    final window = ref.read(threadDirectoryStoreProvider).window;
    for (final thread in window.threads) {
      if (thread.id == id) return thread;
    }
    return null;
  }
}

/// 一次内容窗口绑定：native 窗口 + 它的内容泵的身份。
class _ChatBinding {
  _ChatBinding(this.generation, this.window);

  final int generation;
  final StudioChatWindow window;
  var closed = false;
}

class _WindowOperation {
  _WindowOperation({
    required this.token,
    required this.generation,
    required this.direction,
    this.targetVersion,
  });

  final int token;
  final int generation;
  final TimelineDirection direction;
  final int? targetVersion;

  _WindowOperation waitingFor(int version) {
    return _WindowOperation(
      token: token,
      generation: generation,
      direction: direction,
      targetVersion: version,
    );
  }
}
