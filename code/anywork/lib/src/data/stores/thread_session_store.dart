import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../bridge/studio_bridge.dart';
import '../bridge/thread_stream_gate.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import 'domain_sync.dart';
import 'thread_directory_store.dart';
import 'thread_session_state.dart';

part 'thread_session_store.g.dart';

/// 会话状态族。首个观察者经 Bridge 建流，最后一个观察者释放订阅。
///
/// keepAlive 保留 last-known canonical；订阅寿命用 onCancel/onResume/onDispose，
/// 不引入可见性 generation。
@Riverpod(keepAlive: true)
class ThreadSessionStore extends _$ThreadSessionStore {
  BridgeThreadAttachment? _attachment;
  var _closed = false;
  StudioChatWindow? _chatView;
  Future<StudioChatWindow?>? _chatViewOpening;

  @override
  ThreadSessionState build(String threadId) {
    _closed = false;
    final bridge = ref.watch(studioBridgeProvider);
    ref.onCancel(() {
      unawaited(_releaseSubscription(clearHistory: true));
    });
    ref.onResume(() {
      if (_closed || _attachment != null) return;
      clearStreamEpoch();
      _attach(bridge);
    });
    ref.onDispose(() {
      _closed = true;
      unawaited(_releaseSubscription(clearHistory: false));
      unawaited(_chatView?.close());
      _chatView = null;
    });
    scheduleMicrotask(() {
      if (_closed || !ref.mounted) return;
      _attach(bridge);
    });
    return ThreadSessionState(threadId: threadId);
  }

  void applySnapshot(ThreadWorkspace snapshot) {
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

  void applyTimelinePage(
    TimelinePage page,
    TimelineDirection direction, {
    bool replaceWindow = false,
    bool followBottom = false,
  }) {
    final next = applyTimelinePageState(
      state,
      page,
      direction,
      replaceWindow: replaceWindow,
      followBottom: followBottom,
    );
    if (next == state) return;
    state = next;
  }

  void applyChatSnapshot(
    StudioChatSnapshot snapshot, {
    ChatHistoryCompletion? historyCompletion,
  }) {
    final next = applyChatSnapshotState(
      state,
      snapshot,
      historyCompletion: historyCompletion,
    );
    if (next == state) return;
    state = next;
  }

  void releaseHistory() {
    final next = releaseThreadHistoryState(state);
    if (next == state) return;
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

  /// 惰性打开该会话的权威 ChatView 窗口句柄。
  ///
  /// 句柄生命周期与 store 实例一致：store 释放（invalidate/销毁）时关闭；
  /// 未建立权威快照前不打开；打开结果被换代/关闭取代时立即关闭。
  Future<StudioChatWindow?> chatView() {
    if (_closed || !ref.mounted || !state.hasSnapshot) {
      return Future<void>.value().then((_) => null);
    }
    final existing = _chatView;
    if (existing != null) return Future.value(existing);
    return _chatViewOpening ??= () async {
      try {
        final source = ref.read(studioBridgeDataSourceProvider);
        if (source is! ChatWindowReader) return null;
        final window = await (source as ChatWindowReader).openChatWindow(
          threadId,
        );
        if (!ref.mounted || _closed || !state.hasSnapshot) {
          await window.close();
          return null;
        }
        _chatView = window;
        return window;
      } catch (_) {
        return null;
      } finally {
        _chatViewOpening = null;
      }
    }();
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

  /// 页被拒绝或代次已变时结束加载，不改另一方向的错误。
  void finishHistoryLoad() {
    if (!state.history.isLoading) return;
    state = state.copyWith(history: state.history.copyWith(isLoading: false));
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
    await attachment?.release();
    if (!ref.mounted || !clearHistory) return;
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
