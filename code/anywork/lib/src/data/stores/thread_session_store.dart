import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/studio_models.dart';
import '../bridge/studio_bridge.dart';
import '../bridge/thread_stream_gate.dart';
import '../frb/studio_api.dart';
import '../repositories/studio_api_provider.dart';
import 'chat_view_events.dart';
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

  /// 连续内容泵失败次数；**首帧真正落地**时清零（见 [_notePumpFailure]），用于有界退避。
  int _pumpFailures = 0;
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
  /// `binding` 是帧所属的绑定：已关闭/已换代的绑定迟到帧直接丢弃。每次决定都留下带身份
  /// 与原因的事件（design/25 §25.10），使「哪一帧、哪个绑定、哪条校验」可被事后定位。
  void _applyFrame(_ChatBinding binding, StudioChatFrame frame) {
    final identity = _bindingIdentity(binding);
    if (!ref.mounted || binding.closed || !identical(binding, _binding)) {
      ChatViewEvents.record(
        ChatViewEventKind.frameRejected,
        identity: identity,
        details: {
          'reason': !ref.mounted
              ? 'storeDisposed'
              : binding.closed
              ? 'bindingClosed'
              : 'bindingSuperseded',
          'frame': frame.kind,
        },
      );
      return;
    }
    final result = applyChatFrameState(state, frame);
    switch (result.outcome) {
      case ChatFrameOutcome.applied:
        ChatViewMetrics.framesApplied += 1;
        // 首帧（或任何一帧）真正落地才证明这条绑定可用：退避计数在此清零。
        _pumpFailures = 0;
        ChatViewEvents.record(
          frame is StudioChatReset
              ? ChatViewEventKind.frameReset
              : ChatViewEventKind.framePatch,
          identity: identity,
          details: {'from': state.chatVersion, 'to': result.state.chatVersion},
        );
        state = result.state;
        _completeHistoryOpIfObserved();
      case ChatFrameOutcome.irrelevant:
        ChatViewEvents.record(
          ChatViewEventKind.frameRejected,
          identity: identity,
          details: {'reason': result.reason.name, 'frame': frame.kind},
        );
        return;
      case ChatFrameOutcome.resync:
        ChatViewMetrics.framesResync += 1;
        ChatViewEvents.record(
          ChatViewEventKind.frameResync,
          identity: identity,
          details: {
            'reason': result.reason.name,
            'frame': frame.kind,
            'current': state.chatVersion,
          },
        );
        unawaited(_resyncBinding(binding));
    }
  }

  Map<String, String> _bindingIdentity(_ChatBinding binding) => {
    'thread': _currentThreadId,
    'binding': '${binding.generation}',
  };

  /// 观测记录用的当前 thread 身份。
  ///
  /// dispose 之后 Riverpod 不再允许读 `state`：那时只保留空身份，绝不为了记一条诊断事件
  /// 让清理路径抛错。
  String get _currentThreadId {
    try {
      return state.threadId;
    } catch (_) {
      return '';
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
    // 跳回最新会聚焦权威窗口的 Latest：确认焦点回到「跟随最新」。
    _viewFocus.itemId = null;
  }

  /// 后端已确认的窗口焦点与在途目标（design/25 §25.6）。
  ///
  /// 与 UI 的阅读锚点严格分开：锚点表达「读者看到哪里」，焦点表达「后端窗口围绕哪一条」。
  /// 普通窗口内滚动只改变锚点，只有真正的意图切换才允许改焦点——否则每次换顶行都会让后端
  /// 换窗口并发一次内容 Reset，把滚动变成整窗重载。
  final _ViewFocusTarget _viewFocus = _ViewFocusTarget();

  /// 当前已确认的窗口焦点（`null` 表示 Latest）：供命令层与测试读取。
  String? get confirmedViewFocus => _viewFocus.itemId;

  /// 是否存在仍在途的焦点请求。用于「同一目标不重复发起，但失败后可以重试」。
  bool get viewFocusPending => _viewFocus.pending;

  /// 需要为 [itemId] 发起 native focus 时返回 true；已确认或已在途的同一目标不再是新请求。
  ///
  /// 去重只依据「后端已确认焦点」与「同一目标的在途请求」，不依据刚写下的 UI 锚点：失败后
  /// 同一个目标必须能重试，否则一次失败会被本地意图永久压住。[itemId] 为 null 表示 Latest。
  bool requestViewFocus(String? itemId) {
    if (_viewFocus.itemId == itemId && !_viewFocus.pending) return false;
    if (_viewFocus.pending && _viewFocus.inFlight == itemId) return false;
    _viewFocus.pending = true;
    _viewFocus.inFlight = itemId;
    return true;
  }

  /// 标记一次焦点请求的结果：成功即成为已确认焦点，失败只清在途，允许下一次重试。
  void settleViewFocus(String? itemId, {required bool succeeded}) {
    if (_viewFocus.inFlight == itemId) {
      _viewFocus.pending = false;
      _viewFocus.inFlight = null;
    }
    if (succeeded) _viewFocus.itemId = itemId;
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
      ChatViewEvents.record(
        ChatViewEventKind.bindingOpening,
        identity: {'thread': _currentThreadId, 'binding': '$generation'},
      );
      try {
        final source = ref.read(studioBridgeDataSourceProvider);
        if (source is! ChatWindowReader) {
          ChatViewEvents.record(
            ChatViewEventKind.bindingClosed,
            identity: {'thread': _currentThreadId, 'binding': '$generation'},
            details: {'reason': 'chatWindowReaderMissing', 'everOpened': false},
          );
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
          ChatViewEvents.record(
            ChatViewEventKind.bindingClosed,
            identity: {'thread': _currentThreadId, 'binding': '$generation'},
            details: {
              'reason': !ref.mounted
                  ? 'storeDisposed'
                  : _closed
                  ? 'closed'
                  : !state.hasSnapshot
                  ? 'snapshotLost'
                  : 'supersededWhileOpening',
              'everOpened': false,
            },
          );
          return null;
        }
        final binding = _ChatBinding(generation, window);
        // 候选安装：首帧验证成功之前不进入 `_binding`。否则并发调用会把一个「有句柄、
        // 没有泵」的实例当成 ready binding 复用（design/25 §25.4）。
        final initial = await window.initial();
        if (!_bindingCandidateUsable(binding)) {
          await window.close();
          ChatViewEvents.record(
            ChatViewEventKind.bindingClosed,
            identity: {'thread': _currentThreadId, 'binding': '$generation'},
            details: {
              'reason': binding.closed
                  ? 'closedDuringInitial'
                  : 'supersededDuringInitial',
              'everOpened': false,
            },
          );
          return null;
        }
        _binding = binding;
        _applyFrame(binding, StudioChatReset(initial));
        ChatViewEvents.record(
          ChatViewEventKind.bindingOpened,
          identity: {'thread': _currentThreadId, 'binding': '$generation'},
          details: {
            'version': initial.version,
            'items': initial.items.length,
            'hasOlder': initial.hasOlder,
            'hasNewer': initial.hasNewer,
            'canExtendLatest': initial.canExtendLatest,
            'focused': initial.focusedItemId,
          },
        );
        unawaited(_pumpFrames(binding));
        return binding;
      } catch (error) {
        // 打开失败不在这里自动重开：重开由显示需求或下一次显式操作触发。否则「打开一直
        // 失败」会变成紧循环——自动重试必须在无法推进时停下来，而不是无限重放。
        ChatViewEvents.record(
          ChatViewEventKind.bindingClosed,
          identity: {'thread': _currentThreadId, 'binding': '$generation'},
          details: {
            'reason': 'openFailed',
            'error': '$error',
            'attempt': _notePumpFailure(),
          },
        );
        if (generation == _bindingGeneration && ref.mounted && !_closed) {
          markResync(error, failed: true);
        }
        return null;
      } finally {
        _bindingOpening = null;
      }
    }();
  }

  /// 候选绑定是否仍然可以安装为 ready binding。
  bool _bindingCandidateUsable(_ChatBinding candidate) {
    return ref.mounted &&
        !_closed &&
        !candidate.closed &&
        state.hasSnapshot &&
        candidate.generation == _bindingGeneration &&
        _binding == null;
  }

  /// 记录一次内容泵失败并返回累计次数（用于有界退避）。
  ///
  /// 计数只在**首帧真正落地**时清零：打开成功即清零会让「initial 每次成功、第一条增量
  /// 每次失败」的重开循环永远进不了有效退避，退化成紧循环。
  int _notePumpFailure() {
    _pumpFailures += 1;
    return _pumpFailures;
  }

  /// 连续失败后的有界退避；第一次失败不等待，避免正常重连被无谓延迟。
  Future<void> _retryDelayIfNeeded() async {
    final attempt = _pumpFailures;
    if (attempt <= 1) return;
    await Future<void>.delayed(
      Duration(milliseconds: 50 * (attempt - 1).clamp(1, 10)),
    );
  }

  /// 内容泵：一个绑定同时至多一个未完成的 `next`；reduce 完上一帧后再取下一帧。
  Future<void> _pumpFrames(_ChatBinding binding) async {
    while (!binding.closed) {
      final StudioChatFrame? frame;
      try {
        frame = await binding.window.next();
      } catch (error) {
        // 传输故障：废弃当前绑定并重开，保留最后有效内容等下一次权威 Reset。
        await _failBinding(binding, reason: 'pumpError', error: '$error');
        return;
      }
      if (binding.closed) return;
      if (frame == null) {
        // 出口结束（EOF）：与传输故障同样废弃绑定并收束内容同步状态，不能只把句柄标记关闭。
        await _failBinding(binding, reason: 'pumpEnded');
        return;
      }
      _applyFrame(binding, frame);
      if (!identical(binding, _binding)) return;
    }
  }

  /// 废弃一个绑定（泵故障、EOF 或重同步）并按退避重开同一会话的有界窗口。
  ///
  /// 恢复只重建受影响资源的观察，不重启业务 owner；期间保留最后有效内容，
  /// 不把数据不可用渲染为空列表（design/25 §25.9）。
  Future<void> _failBinding(
    _ChatBinding binding, {
    required String reason,
    String? error,
  }) async {
    final wasCurrent = identical(binding, _binding);
    if (wasCurrent) {
      _closeBinding();
    } else {
      binding.closed = true;
    }
    final attempt = _notePumpFailure();
    ChatViewEvents.record(
      ChatViewEventKind.bindingClosed,
      identity: _bindingIdentity(binding),
      details: {'reason': reason, 'attempt': attempt, 'error': error},
    );
    await _retryDelayIfNeeded();
    if (_closed || !ref.mounted) return;
    unawaited(_openChatBinding());
  }

  /// 连续性缺口或传输故障：废弃当前绑定，稍作退避后重开同一会话的有界窗口。
  Future<void> _resyncBinding(_ChatBinding binding) async {
    if (!identical(binding, _binding)) return;
    await _failBinding(binding, reason: 'resync');
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
    _finishHistoryOp(_windowOperation, 'localCompletion');
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
    ChatViewEvents.record(
      ChatViewEventKind.operationBegun,
      identity: {'thread': _currentThreadId, 'operation': '$token'},
      details: {
        'direction': direction.name,
        'binding': '$_bindingGeneration',
        'version': state.chatVersion,
      },
    );
    setHistoryLoading(direction);
    return token;
  }

  /// 回执已到：有内容变化时等对应帧进入 read model；版本已观察时立即结束本轮。
  void observeHistoryOp(int token, StudioChatReceipt receipt) {
    final op = _windowOperation;
    if (op == null || op.token != token) {
      ChatViewEvents.record(
        ChatViewEventKind.operationObserved,
        identity: {'thread': _currentThreadId, 'operation': '$token'},
        details: {
          'reason': op == null ? 'noPendingOperation' : 'tokenSuperseded',
          'receiptVersion': receipt.version,
        },
      );
      return;
    }
    if (op.generation != _bindingGeneration) {
      ChatViewEvents.record(
        ChatViewEventKind.operationObserved,
        identity: {'thread': _currentThreadId, 'operation': '$token'},
        details: {
          'reason': 'bindingChanged',
          'receiptVersion': receipt.version,
        },
      );
      _finishHistoryOp(op, 'bindingChanged');
      return;
    }
    final current = state.chatVersion;
    if (current != null && receipt.version <= current) {
      // 回执版本取自**窗口交付域**（runtime 以窗口快照版本填回执）：等于已交付版本表示
      // 这次操作没有产生本窗口可见的变化（真正的 NoChange），小于则表示对应内容帧已经
      // 先于回执到达。两者都不需要继续等一个不会到来的内容帧。
      final result = receipt.version == current
          ? 'noChange'
          : 'alreadyObserved';
      ChatViewEvents.record(
        ChatViewEventKind.operationObserved,
        identity: {'thread': _currentThreadId, 'operation': '$token'},
        details: {
          'reason': result,
          'receiptVersion': receipt.version,
          'currentVersion': current,
          'retained': receipt.retained,
        },
      );
      _finishHistoryOp(op, result);
      return;
    }
    ChatViewEvents.record(
      ChatViewEventKind.operationObserved,
      identity: {'thread': _currentThreadId, 'operation': '$token'},
      details: {
        'reason': 'awaitingContentVersion',
        'receiptVersion': receipt.version,
        'currentVersion': current,
        'retained': receipt.retained,
      },
    );
    _windowOperation = op.waitingFor(receipt.version);
    _completeHistoryOpIfObserved();
  }

  void failHistoryOp(int token, String message) {
    final op = _windowOperation;
    if (op == null || op.token != token) return;
    _windowOperation = null;
    ChatViewEvents.record(
      ChatViewEventKind.operationSettled,
      identity: {'thread': _currentThreadId, 'operation': '$token'},
      details: {'result': 'failed', 'error': message},
    );
    setHistoryError(op.direction, message);
  }

  void _completeHistoryOpIfObserved() {
    final op = _windowOperation;
    if (op == null || op.targetVersion == null) return;
    final current = state.chatVersion;
    if (current != null && current >= op.targetVersion!) {
      _finishHistoryOp(op, 'contentVersionObserved');
    }
  }

  void _finishHistoryOp(_WindowOperation? op, String reason) {
    if (op == null) return;
    if (!identical(_windowOperation, op) &&
        _windowOperation?.token != op.token) {
      return;
    }
    _windowOperation = null;
    ChatViewEvents.record(
      ChatViewEventKind.operationSettled,
      identity: {'thread': _currentThreadId, 'operation': '${op.token}'},
      details: {
        'result': reason,
        'direction': op.direction.name,
        'targetVersion': op.targetVersion,
        'currentVersion': state.chatVersion,
      },
    );
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

/// 后端窗口焦点事实：已确认的目标（`null` = Latest）加上至多一个在途请求。
///
/// UI 阅读锚点不属于这里；这里是「后端窗口现在围绕哪一条」的唯一事实源。
class _ViewFocusTarget {
  String? itemId;
  bool pending = false;
  String? inFlight;
}
