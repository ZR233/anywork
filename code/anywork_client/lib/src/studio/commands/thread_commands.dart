import '../../../conversation.dart';
import '../../../drafts_ports.dart';

import 'dart:async';
import 'dart:developer' show log;

import '../../../models.dart';
import '../../../studio_ports.dart';
import '../../../accounts_ports.dart' show SettingsWriteOwner;
import '../../../anywork_client.dart'
    show
        ReadModel,
        OperationHandle,
        OperationState,
        Observation,
        ResourceKind,
        ResourcePermit,
        ValueObservation;
import '../anywork_client.dart';
import '../agent_directory_queries.dart';
import '../stores/domain_sync.dart';
import '../stores/project_store.dart';
import '../bridge/product_topic_registry.dart' show BridgeTopicLease;
import '../../commands/mutation_board.dart' show OperationPhase;
import 'command_lane.dart';

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

/// Identity 观察在操作失败阶段的处置策略。
enum _ObservationFailurePolicy {
  /// 任何失败阶段立即取消观察（默认：一次性本地命令观察）。
  cancelOnFailure,

  /// 只有 observed、明确 rejected 或 owner 关闭才取消；unknown 与带回执的
  /// syncFailed 保留原 binding，等待后续同 ID 接受或 canonical 帧观察完成。
  /// continuation 的原身份接续依赖它在 unknown 期间不丢 canonical 观察。
  retainUntilSettled,
}

class ThreadCommands extends ReadModel<ThreadCommandBoard>
    implements DraftSubmissionCommands {
  ThreadCommands(this._client, {int Function()? nowMs})
    : _nowMs = nowMs ?? _wallClockMs,
      super(const ThreadCommandBoard());
  final AnyworkClient _client;

  /// 命令登记时间来源；界面用自己的墙钟比较，因此这里使用 Unix 毫秒。
  final int Function() _nowMs;
  final CommandLane _lane = CommandLane();
  final CommandLane _stopLane = CommandLane();
  final Set<Observation> _operationObservations = {};
  final Map<String, _ContinuationIntent> _continuationIntents = {};

  /// 同一 `(threadId, executionId)` 的停止登记：至多一个在途 + 至多一个排队重试。
  final Map<String, _StopFlight> _stopFlights = {};
  bool _closed = false;
  Future<void>? _closing;

  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing;
    _closed = true;
    _lane.seal();
    _stopLane.seal();
    return _closing = Future.wait<void>([_lane.join(), _stopLane.join()])
        .then((_) {
          for (final observation in List.of(_operationObservations)) {
            observation.cancel();
          }
          _operationObservations.clear();
        });
  }

  void _ensureOpen() {
    if (_closed || _client.isClosed)
      throw StateError('Thread commands are closed');
  }

  Future<T> _track<T>(Future<T> Function() action) {
    _ensureOpen();
    return _lane.run(action);
  }

  Future<void> compactThread(String threadId) {
    _ensureOpen();
    final key = 'compact:$threadId';
    if (state.commands[key]?.phase == CommandPhase.pending) {
      return Future<void>.error(StateError('Context compaction is pending'));
    }
    _begin(key, label: threadId);
    return _lane.enqueue(() async {
      try {
        _throwIfExecutionClosed(threadId);
        final issue = _executionBlockerForThread(threadId);
        if (issue != null) throw issue.blockedFailure();
        final storage = _client.conversations.sessionState(threadId)?.storage;
        if (storage?.blocksContinuation == true) {
          throw threadStorageContinuationFailure(storage!);
        }
        await _api.compactThread(threadId);
        _clear(key);
      } catch (error) {
        _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<void> setThreadModelRoute({
    String? threadId,
    required String accountId,
    required String modelId,
    String? effort,
  }) {
    _ensureOpen();
    final targetThreadId = threadId ?? _client.selection.state.selectedThreadId;
    if (targetThreadId == null) return Future<void>.value();
    final owner = _client.settingsWrites.captureOwner();
    final operation = _client.mutations.begin(
      target: 'thread-route:$targetThreadId',
      observationOwner: owner,
    );
    _client.settings.beginCommand(
      'thread-route:$targetThreadId',
      CommandTarget(accountId: accountId, modelId: modelId, effort: effort),
    );
    _watchObservation(operation, () {
      if (_client.settingsWrites.isCurrentOwner(owner)) {
        _client.settings.clearCommand('thread-route:$targetThreadId');
      }
    });
    return _track(
      () => _client.settingsWrites.enqueue(
        () => _applyThreadModelRoute(
          operation: operation,
          owner: owner,
          threadId: targetThreadId,
          accountId: accountId,
          modelId: modelId,
          effort: effort,
        ),
      ),
    );
  }

  Future<void> setThreadMode(ThreadModeId mode, {required String threadId}) {
    _ensureOpen();
    // 调用方传入渲染时冻结的目标，不重新读取全局选择。
    final key = 'mode:$threadId';
    final operation = _client.mutations.begin(target: key);
    _begin(key, label: mode.id);
    _watchObservation(operation, () => _clear(key));
    return _lane.enqueue(() async {
      final thread = _directoryThread(threadId);
      final runtime = _client.conversations.session(threadId).state.runtime;
      final recoveryIssue = _accessBlockerForThread(threadId);
      if (recoveryIssue != null) {
        final failure = recoveryIssue.blockedFailure();
        operation.reject(failure);
        if (_isLatest(operation)) _fail(key, threadId, failure);
        throw failure;
      }
      if (thread == null ||
          !thread.isRoot ||
          thread.status != ThreadStatusView.idle ||
          (runtime?.hasActiveWorkflow ?? false)) {
        operation.reject(StateError('Thread mode change is unavailable'));
        if (_isLatest(operation)) _clear(key);
        return;
      }
      try {
        final response = await _api.setThreadMode(
          operationId: operation.id,
          threadId: threadId,
          mode: mode,
        );
        operation.accept(response.receipt.toCommitReceipt());
      } catch (error) {
        _failOperation(operation, error);
        if (_isLatest(operation)) _fail(key, threadId, error);
        rethrow;
      }
      // 命令后不显式重读：mode 由目录增量交付、mode 默认 route 由 Thread 有序流
      // 交付（design/25 §25.5）。补偿式重读会让同一事实多出第二条合并路径，并让
      // 「帧没到」这种缺陷在验收里不可见。
    });
  }

  /// 草稿仍属于后续 route 层。这里只接受已经组装好的输入，不写 composer canonical。
  ///
  /// Client-side validation, Recovery, storage, or lane rejection before the
  /// transport method is invoked throws [SubmissionNotSent] with the original
  /// typed error. Errors after invocation propagate unchanged so callers can
  /// preserve unknown-outcome protection.
  Future<SubmitPromptReceipt> submitComposer(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) async {
    var transportInvoked = false;
    try {
      _ensureOpen();
      return await _lane.enqueue(() async {
        _throwIfExecutionClosed(threadId);
        if (input.text.trim().isEmpty && input.attachmentDraftIds.isEmpty) {
          throw ArgumentError('Prompt cannot be empty');
        }
        final issue = _executionBlockerForThread(threadId);
        if (issue != null) throw issue.blockedFailure();
        final storage = _client.conversations.sessionState(threadId)?.storage;
        if (storage?.blocksContinuation == true) {
          throw threadStorageContinuationFailure(storage!);
        }
        final key = 'submit:$threadId';
        _begin(key, label: threadId);
        try {
          transportInvoked = true;
          final receipt = await _api.submitPrompt(
            threadId,
            input,
            expectedModelRouteRevision: expectedModelRouteRevision,
          );
          _clear(key);
          return receipt;
        } catch (error) {
          _fail(key, threadId, error);
          rethrow;
        }
      });
    } catch (error) {
      if (!transportInvoked) throw SubmissionNotSent(error);
      rethrow;
    }
  }

  /// 解析当前会话的 pending interaction。
  ///
  /// 响应只确认命令；canonical interaction 帧仅由 Thread 有序流写入，
  /// 不在本地删除或改写 interaction（design/25 §25.5）。
  Future<void> resolveActiveInteraction(
    String threadId,
    String interactionId,
    InteractionResolutionCommand resolution,
  ) {
    _ensureOpen();
    _throwIfExecutionClosed(threadId);
    final recoveryIssue = _executionBlockerForThread(threadId);
    if (recoveryIssue != null) {
      return Future<void>.error(recoveryIssue.blockedFailure());
    }
    final storage = _client.conversations.sessionState(threadId)?.storage;
    if (storage?.blocksContinuation == true) {
      return Future<void>.error(threadStorageContinuationFailure(storage!));
    }
    final key = 'interaction:$threadId';
    final operation = _client.mutations.begin(target: key);
    final displayed = _client.conversations
        .session(threadId)
        .state
        .interactions
        .where((item) => item.id == interactionId)
        .firstOrNull;
    final turnId = displayed?.turnId;
    final displayedRevision = displayed?.revision ?? 0;
    _begin(key, label: interactionId);
    try {
      _watchIdentity(
        operation,
        threadId,
        (state) =>
            state.hasSnapshot &&
            !state.interactions.any((item) => item.id == interactionId),
        () => _clear(key),
      );
    } catch (error) {
      operation.reject(error);
      if (_isLatest(operation)) _fail(key, interactionId, error);
      rethrow;
    }
    return _lane.enqueue(() async {
      final queuedRecoveryIssue = _executionBlockerForThread(threadId);
      if (_isExecutionClosed(threadId)) {
        final failure = _closedReadOnlyFailure;
        _rejectQueuedOperation(operation, key, interactionId, failure);
        throw failure;
      }
      if (queuedRecoveryIssue != null) {
        final failure = queuedRecoveryIssue.blockedFailure();
        _rejectQueuedOperation(operation, key, interactionId, failure);
        throw failure;
      }
      final queuedStorage = _client.conversations
          .sessionState(threadId)
          ?.storage;
      if (queuedStorage?.blocksContinuation == true) {
        final failure = threadStorageContinuationFailure(queuedStorage!);
        _rejectQueuedOperation(operation, key, interactionId, failure);
        throw failure;
      }
      final active =
          [..._client.conversations.session(threadId).state.interactions]..sort(
            (left, right) =>
                interactionPriority(left.kind)
                    .compareTo(interactionPriority(right.kind)),
          );
      if (turnId == null ||
          active.firstOrNull?.id != interactionId ||
          active.firstOrNull?.turnId != turnId) {
        final conflict = const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The displayed interaction is no longer current',
          retryable: false,
          correlationId: 'client-interaction-conflict',
        );
        operation.reject(conflict);
        if (_isLatest(operation)) _fail(key, interactionId, conflict);
        throw conflict;
      }
      try {
        final response = await _api.respondInteraction(
          threadId,
          interactionId,
          displayedRevision,
          resolution,
          operationId: operation.id,
        );
        if (response.interaction.id != interactionId ||
            response.interaction.threadId != threadId ||
            response.interaction.turnId != turnId ||
            !response.receipt.requiresIdentityObservation) {
          throw StateError(
            'Interaction receipt did not match the stable target',
          );
        }
        operation.accept(response.receipt.toCommitReceipt());
      } catch (error) {
        _failOperation(operation, error);
        if (_isLatest(operation)) _fail(key, interactionId, error);
        rethrow;
      }
    });
  }

  /// Creates a new root thread through the single progress/terminal transport.
  ///
  /// A Client rejection before transport invocation throws
  /// [SubmissionNotSent]. A backend-emitted [NewThreadStartFailed] remains its
  /// original definite terminal event; stream errors or EOF after invocation
  /// remain unwrapped and do not prove rejection.
  Future<StartNewThreadResult?> submitNewThread({
    required String workspaceId,
    required StudioPromptInput input,
    required ThreadModeId mode,
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
    required void Function(ThreadPreparationProgress) onProgress,
  }) async {
    var transportInvoked = false;
    try {
      _ensureOpen();
      final navigation = _client.selection.beginNavigation();
      final selection = _client.selection.state;
      return await _lane.enqueue(() async {
        if (input.text.trim().isEmpty && input.attachmentDraftIds.isEmpty) {
          return null;
        }
        final project = (_client.project.state.projects?.values ?? const [])
            .where((candidate) => candidate.id == workspaceId)
            .firstOrNull;
        if (project?.isStandalone == true &&
            ThreadWorkspaceMode.fromId(workspaceMode ?? 'local').isWorktree) {
          throw StateError('Standalone workspaces only support local mode');
        }
        final key = 'new-thread:$workspaceId';
        _begin(key, label: workspaceId);
        try {
          final issue = _executionBlockerForProject(workspaceId);
          if (issue != null) throw issue.blockedFailure();
          transportInvoked = true;
          await for (final event in _api.startNewThread(
            workspaceId,
            input,
            mode,
            route: route,
            delegationMode: delegationMode,
            delegationPreference: delegationPreference,
            workspaceMode: workspaceMode,
          )) {
            switch (event) {
              case NewThreadStartProgress(:final progress):
                if (progress.workspaceId != workspaceId ||
                    progress.inputId != input.inputId) {
                  throw StateError(
                    'New Thread preparation identity did not match',
                  );
                }
                onProgress(progress);
              case NewThreadStartFailed():
                throw event;
              case NewThreadStartSucceeded(:final result):
                if (result.thread.workspaceId != workspaceId ||
                    result.receipt.threadId != result.thread.id ||
                    result.receipt.inputId != input.inputId) {
                  throw StateError(
                    'New Thread submission receipt did not match',
                  );
                }
                if (!_client.isClosed &&
                    _client.selection.isCurrentNavigation(navigation) &&
                    identical(_client.selection.state, selection)) {
                  // 目录条目由 owner 的目录增量交付（commit_directory 已在命令内发布）；
                  // 命令成功后不重读聚合状态（design/25 §25.5）。
                  _client.selection.selectThread(
                    workspaceId: workspaceId,
                    threadId: result.thread.id,
                  );
                }
                _clear(key);
                return result;
            }
          }
          throw StateError(
            'New Thread creation ended without a terminal outcome',
          );
        } catch (error) {
          _fail(key, workspaceId, error);
          rethrow;
        }
      });
    } catch (error) {
      if (!transportInvoked) throw SubmissionNotSent(error);
      rethrow;
    }
  }

  /// 主会话自己的精确停止。
  ///
  /// 目标是该会话规范运行时里的执行身份，而不是 `activeTurn`：准备、等待保存、等待准入
  /// 与清理期同样可寻址。调用瞬间冻结 ThreadId + 执行编号 + OperationId，切换选中会话
  /// 不会把命令重定向到别的会话。
  ///
  /// [expectedExecutionId] 是调用方渲染时捕获的执行编号：传入时它就是唯一目标，命令边界
  /// 不再从 canonical 重新选择，也不会在本地降级成「没有可停止执行」——若该执行已被替换，
  /// 由服务端返回 typed `staleExecution`，命令抛该失败。未传时仍取 canonical 当前执行。
  ///
  /// 返回值明确回答「这次点击是否真的发出了停止请求」：规范里已无当前执行时返回
  /// [StopNoExecution]，调用方不应进入进行中状态。
  Future<ThreadStopOutcome> stop(
    String threadId, {
    String? expectedExecutionId,
  }) {
    _ensureOpen();
    final frozen = expectedExecutionId;
    if (frozen != null) {
      return _stopExecution(
        threadId: threadId,
        executionId: frozen,
        requireCurrentCanonical: false,
      );
    }
    final execution = _client.conversations
        .session(threadId)
        .state
        .runtime
        ?.execution;
    if (execution == null) {
      return Future<ThreadStopOutcome>.value(
        StopNoExecution(threadId: threadId),
      );
    }
    return _stopExecution(threadId: threadId, executionId: execution.id);
  }

  /// 智能体列表某一行的精确停止。
  ///
  /// 目标来自 AgentDirectory 该行发布的执行身份与停止资格：不要求先选择或打开该会话，
  /// 不改变当前选择，不创建输入草稿，也不建立完整内容订阅。
  ///
  /// [expectedExecutionId] 是界面渲染该行时捕获的执行编号：传入时以它为唯一目标，仍要求
  /// 该行具备停止资格（`canStop`），但不再要求 canonical 仍发布这个执行——过时由服务端
  /// 以 typed `staleExecution` 拒绝，而不是本地改写或静默停止别的执行。
  ///
  /// 行不具备停止资格时返回 [StopNotQualified] 且不发出请求；有资格但没有发布的执行
  /// 时同样按无资格处理，不据活动摘要假造目标。
  Future<ThreadStopOutcome> stopAgent(
    String threadId, {
    String? expectedExecutionId,
  }) {
    _ensureOpen();
    final agent = _agentEntry(threadId);
    final frozen = expectedExecutionId;
    if (frozen != null) {
      if (agent == null || !agent.canStop) {
        return Future<ThreadStopOutcome>.value(
          StopNotQualified(threadId: threadId),
        );
      }
      return _stopExecution(
        threadId: threadId,
        executionId: frozen,
        fromDirectory: true,
        requireCurrentCanonical: false,
      );
    }
    final execution = agent?.execution;
    if (agent == null || !agent.canStop || execution == null) {
      return Future<ThreadStopOutcome>.value(
        StopNotQualified(threadId: threadId),
      );
    }
    return _stopExecution(
      threadId: threadId,
      executionId: execution.id,
      fromDirectory: true,
    );
  }

  Future<ThreadStopOutcome> _stopExecution({
    required String threadId,
    required String executionId,
    bool fromDirectory = false,
    bool requireCurrentCanonical = true,
  }) {
    // At most one in-flight attempt plus at most one queued retry per
    // (thread, execution): repeated clicks and timeout retries never accumulate
    // queued requests, yet an explicit retry still gets its turn once the
    // current attempt settles.
    final target = '$threadId:$executionId';
    final existing = _stopFlights[target];
    if (existing == null) {
      final entry = _StopFlight(
        threadId: threadId,
        executionId: executionId,
        fromDirectory: fromDirectory,
        requireCurrentCanonical: requireCurrentCanonical,
      );
      _stopFlights[target] = entry;
      return _runStopFlight(target, entry);
    }
    final queued = existing.queued;
    if (queued != null) return queued;
    // The caller learns that this click is queued, not sent: the interface
    // shows "request in flight" and keeps repeated submissions disabled.
    final registration = Completer<ThreadStopOutcome>()
      ..complete(StopQueued(threadId: threadId, executionId: executionId));
    existing.queued = registration.future;
    return existing.queued!;
  }

  /// 发起一次真实尝试，并在结算时把排队的唯一重试交给 lane。
  Future<ThreadStopOutcome> _runStopFlight(String target, _StopFlight entry) {
    final flight = _dispatchStop(
      threadId: entry.threadId,
      executionId: entry.executionId,
      fromDirectory: entry.fromDirectory,
      requireCurrentCanonical: entry.requireCurrentCanonical,
    );
    entry.inFlight = flight;
    unawaited(
      flight
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() => _settleStopFlight(target, entry)),
    );
    return flight;
  }

  void _settleStopFlight(String target, _StopFlight entry) {
    final queued = entry.queued;
    if (queued == null) {
      _stopFlights.removeWhere(
        (name, pending) => name == target && identical(pending, entry),
      );
      return;
    }
    entry.queued = null;
    try {
      // The queued retry owns its own settle handler, so this future is only
      // observed through that handler.
      unawaited(_runStopFlight(target, entry));
    } catch (error) {
      _fail('stop:${entry.threadId}', entry.threadId, error);
      _stopFlights.removeWhere(
        (name, pending) => name == target && identical(pending, entry),
      );
    }
  }

  Future<ThreadStopOutcome> _dispatchStop({
    required String threadId,
    required String executionId,
    required bool fromDirectory,
    required bool requireCurrentCanonical,
  }) {
    final key = 'stop:$threadId';
    final operation = _client.mutations.begin(target: key);
    _begin(key, label: executionId);
    try {
      if (fromDirectory) {
        _watchPredicate(
          operation,
          _client.project.source,
          (state) => _directoryExecutionEnded(state, threadId, executionId),
          () => _clear(key),
        );
      } else {
        _watchPredicate(
          operation,
          _client.conversations.session(threadId).source,
          (state) =>
              state.hasSnapshot && state.runtime?.execution?.id != executionId,
          () => _clear(key),
        );
      }
    } catch (error) {
      operation.reject(error);
      if (_isLatest(operation)) _fail(key, threadId, error);
      rethrow;
    }
    return _stopLane.enqueue<ThreadStopOutcome>(() async {
      // Without a caller-frozen identity the captured one must still be canonical:
      // a stop may not degrade into "stop whatever runs now". With a frozen
      // identity the server owns that comparison and answers typed staleExecution.
      final current = requireCurrentCanonical
          ? (fromDirectory
                ? _agentEntry(threadId)?.execution
                : _client.conversations
                      .session(threadId)
                      .state
                      .runtime
                      ?.execution)
          : null;
      if (requireCurrentCanonical &&
          (current == null || current.id != executionId)) {
        final stale = StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The observed execution is no longer current',
          retryable: false,
          correlationId: 'client-stop-stale-execution',
          reason: StudioFailureReason.staleExecution,
        );
        _failOperation(operation, stale);
        if (_isLatest(operation)) _fail(key, threadId, stale);
        throw stale;
      }
      try {
        final response = await _api.stopThread(
          threadId,
          executionId,
          operationId: operation.id,
        );
        if (response.threadId != threadId ||
            response.executionId != executionId ||
            !response.receipt.requiresIdentityObservation) {
          throw StateError('Stop receipt did not match the stable target');
        }
        operation.accept(response.receipt.toCommitReceipt());
        // The acceptance receipt is a fact the interface must be able to read
        // after it rebuilds; the canonical convergence is still pending.
        _markAccepted(key);
        return StopRequested(
          threadId: threadId,
          executionId: executionId,
          operationId: operation.id,
          receipt: response.receipt,
        );
      } catch (error) {
        _failOperation(operation, error);
        if (_isLatest(operation)) _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  /// 无新内容继续主会话。
  ///
  /// 只为主会话提供：子会话的执行由主智能体调度，用户界面没有直达入口。同一
  /// (会话, 继续点) 意图只允许一个 OperationId；结果未知时按原操作回查，不换编号重发。
  ///
  /// [continuation] 必须来自规范运行时投影（`ThreadRuntimeView.continuation`）：
  /// 已认领的点（`claimed`）表示继续已被受理或仍在准备，不再发送新请求；客户端不
  /// 本地生成继续点身份，也不从轮次终态推断能否继续。
  Future<ContinueThreadCommandReply> continueThread(
    String threadId,
    ContinuationView continuation, {
    required int expectedModelRouteRevision,
  }) {
    _ensureOpen();
    if (_isChildThread(threadId)) {
      return Future<ContinueThreadCommandReply>.error(
        _childRequiresParentScheduling(threadId),
      );
    }
    final accessIssue = _accessBlockerForThread(threadId);
    if (accessIssue != null) {
      return Future<ContinueThreadCommandReply>.error(
        accessIssue.blockedFailure(),
      );
    }
    final continuationId = continuation.id;
    final intentKey = '$threadId:$continuationId';
    final existing = _continuationIntents[intentKey];
    if (existing?.inFlight case final inFlight?) return inFlight;
    if (existing != null) {
      // A previous explicit intent already owns a frozen identity: read the
      // original operation instead of dispatching a second one. The shared
      // join is registered before any synchronously reentrant lane work, so
      // every reentrant click for this intent observes the same future.
      final completion = Completer<ContinueThreadCommandReply>();
      late final Future<ContinueThreadCommandReply> reconciling;
      reconciling = completion.future.whenComplete(() {
        if (identical(existing.inFlight, reconciling)) {
          existing.inFlight = null;
        }
      });
      existing.inFlight = reconciling;
      unawaited(
        _reconcileExistingIntent(existing)
            .then(completion.complete, onError: completion.completeError),
      );
      return reconciling;
    }
    _throwIfExecutionClosed(threadId);
    final recoveryIssue = _executionBlockerForThread(threadId);
    if (recoveryIssue != null) {
      return Future<ContinueThreadCommandReply>.error(
        recoveryIssue.blockedFailure(),
      );
    }
    final storage = _client.conversations.sessionState(threadId)?.storage;
    if (storage?.blocksContinuation == true) {
      return Future<ContinueThreadCommandReply>.error(
        threadStorageContinuationFailure(storage!),
      );
    }
    if (continuation.claimed) {
      // The canonical projection already says this intent was claimed: another
      // acceptance (or an unresolvable earlier one) owns it, so nothing is sent.
      final claimed = StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The continuation point is already claimed',
        retryable: false,
        correlationId: 'client-continuation-claimed',
        reason: StudioFailureReason.continuationClaimed,
      );
      _fail('continue:$threadId', threadId, claimed);
      return Future<ContinueThreadCommandReply>.error(claimed);
    }
    final key = 'continue:$threadId';
    // The intent and its shared join exist before any synchronously reentrant
    // publication: a reentrant click during begin/board publication joins
    // this future instead of allocating a second operation for the intent.
    final intent = _ContinuationIntent(
      threadId: threadId,
      continuationId: continuationId,
      expectedModelRouteRevision: expectedModelRouteRevision,
    );
    final completion = Completer<ContinueThreadCommandReply>();
    late final Future<ContinueThreadCommandReply> tracked;
    tracked = completion.future.whenComplete(() {
      if (identical(intent.inFlight, tracked)) intent.inFlight = null;
    });
    _continuationIntents[intentKey] = intent;
    intent.inFlight = tracked;
    try {
      final operation = _client.mutations.begin(target: key);
      intent.operation = operation;
      _begin(key, label: continuationId);
      _watchPredicate(
        operation,
        _client.conversations.session(threadId).source,
        (state) =>
            state.hasSnapshot &&
            (state.runtime?.execution != null ||
                (state.activeTurn?.state.isBusy ?? false)),
        () => _clear(key),
        policy: _ObservationFailurePolicy.retainUntilSettled,
      );
    } catch (error) {
      // Never invoked and never observed: this is a definite local rejection,
      // so the frozen identity is released for a fresh explicit click. Every
      // synchronous setup step shares this path: a budget-exceeded begin or a
      // board registration failure must not leave the intent's shared join
      // dangling in the map for later clicks to await forever.
      final handle = intent.operation;
      if (handle != null) handle.reject(error);
      if (identical(_continuationIntents[intentKey], intent)) {
        _continuationIntents.remove(intentKey);
      }
      if (handle != null && _isLatest(handle)) _fail(key, threadId, error);
      completion.completeError(error);
      return tracked;
    }
    final task = _sendContinuation(intent, resend: false);
    unawaited(
      task.then(completion.complete, onError: completion.completeError),
    );
    return tracked;
  }

  /// 首次发送与已查明 NotFound 的原身份再发共用同一发送 helper。
  ///
  /// 冻结的 thread/continuation/route CAS 与原 OperationId 原样透传。[resend]
  /// 为 true 时，发送前的本地 guard 失败只把 typed 错误交回调用方：不删除
  /// 意图、不 reject 原操作、不分配新 ID，原 unknown 身份与观察责任保持不变。
  Future<ContinueThreadCommandReply> _sendContinuation(
    _ContinuationIntent intent, {
    required bool resend,
  }) {
    final operation = intent.operation!;
    final key = 'continue:${intent.threadId}';
    final intentKey = '${intent.threadId}:${intent.continuationId}';
    var transportInvoked = false;
    return _lane.enqueue(() async {
      try {
        if (resend) {
          _ensureOpen();
          _throwIfAccessBlockedForThread(intent.threadId);
          // The reconcile read and this dispatch are separate steps: state
          // may have changed in between. A determined rejection must never
          // reach the transport again under this identity.
          final state = operation.state.value;
          if (state.failurePhase == OperationPhase.rejected) {
            throw StateError(
              'The continuation identity reached a terminal disposition',
            );
          }
        }
        _throwIfExecutionClosed(intent.threadId);
        final recoveryIssue = _executionBlockerForThread(intent.threadId);
        if (recoveryIssue != null) throw recoveryIssue.blockedFailure();
        final storage = _client.conversations
            .sessionState(intent.threadId)
            ?.storage;
        if (storage?.blocksContinuation == true) {
          throw threadStorageContinuationFailure(storage!);
        }
        transportInvoked = true;
        final reply = await _api.continueThread(
          intent.threadId,
          intent.continuationId,
          expectedModelRouteRevision: intent.expectedModelRouteRevision,
          operationId: operation.id,
        );
        if (reply.threadId != intent.threadId ||
            !reply.receipt.requiresIdentityObservation) {
          throw StateError('Continue receipt did not match the stable target');
        }
        try {
          operation.accept(reply.receipt.toCommitReceipt());
        } finally {
          // Synchronous observation may clear this command or admit a newer
          // intent. A recorded receipt survives later synchronization failure.
          if (_isLatest(operation) && operation.state.value.receipt != null) {
            _markAccepted(key);
          }
        }
        return reply;
      } catch (error) {
        if (transportInvoked) {
          _failOperation(operation, error);
        } else if (!resend) {
          // The allocated ID was never sent and must not be reconciled as an
          // unknown operation after a local lane-time rejection.
          operation.reject(error);
          if (identical(_continuationIntents[intentKey], intent)) {
            _continuationIntents.remove(intentKey);
          }
        }
        // A resend blocked before dispatch keeps the original unknown identity
        // and its observation responsibility; nothing is rejected or replaced.
        if (!resend && _isLatest(operation)) {
          _fail(key, intent.threadId, error);
        }
        rethrow;
      }
    });
  }

  /// 按原操作身份回查一次继续操作；查询不激活执行、不解除后来发生的停止。
  Future<ContinuationOperationView> readContinuationOperation(
    String threadId,
    String operationId,
  ) {
    _ensureOpen();
    return _lane.run(() {
      _throwIfAccessBlockedForThread(threadId);
      return _api.readContinuationOperation(threadId, operationId);
    });
  }

  /// 该会话当前继续点的规范投影；未打开或没有未完成工作时为空。
  ///
  /// 只读访问器：不激活会话、不新建操作，也不在本地推断继续资格。
  ContinuationView? continuation(String threadId) => _client.conversations
      .existingSession(threadId)
      ?.state
      .runtime
      ?.continuation;

  /// 读取主会话可见的子任务待决交互只读投影。
  ///
  /// 普通只读查询：返回值不写入事件所属的领域镜像，也不作为 UI 刷新来源；
  /// 待决集合事实由 `ChildInteractions` 主题的基线与事件交付。列举本身不激活
  /// 任何子会话，也不建立其完整内容订阅。
  Future<List<ChildInteractionSummary>> readChildInteractions(
    String hostThreadId,
  ) {
    _ensureOpen();
    final recoveryIssue = _accessBlockerForThread(hostThreadId);
    if (recoveryIssue != null) {
      return Future<List<ChildInteractionSummary>>.error(
        recoveryIssue.blockedFailure(),
      );
    }
    return _lane.run(() => _api.readChildInteractions(hostThreadId));
  }

  /// 主会话代表子任务提交交互决议。
  ///
  /// 宿主身份固定为主会话，原交互身份与版本原样透传；决议结果落在原交互所属的子会话。
  /// 子会话侧没有等价入口，这里也拒绝把子会话当作宿主。
  /// 合法回执受理后返回本次真实操作；调用方观察其状态，不以回调成功推断决议已生效。
  Future<OperationHandle> resolveChildInteraction(
    String hostThreadId,
    ChildInteractionSummary summary,
    InteractionResolutionCommand resolution,
  ) {
    _ensureOpen();
    _throwIfExecutionClosed(hostThreadId);
    _throwIfExecutionClosed(summary.childThreadId);
    final recoveryIssue = _executionBlockerForThread(hostThreadId);
    if (recoveryIssue != null) {
      return Future<OperationHandle>.error(recoveryIssue.blockedFailure());
    }
    final storage = _client.conversations.sessionState(hostThreadId)?.storage;
    if (storage?.blocksContinuation == true) {
      return Future<OperationHandle>.error(
        threadStorageContinuationFailure(storage!),
      );
    }
    if (summary.childThreadId == hostThreadId ||
        summary.interaction.threadId != summary.childThreadId ||
        _isChildThread(hostThreadId)) {
      final failure = StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A child decision is submitted through the main session that hosts it',
        retryable: false,
        correlationId: 'client-child-interaction-host',
        reason: StudioFailureReason.interactionNotHosted,
      );
      return Future<OperationHandle>.error(failure);
    }
    final childRecoveryIssue = _executionBlockerForThread(
      summary.childThreadId,
    );
    if (childRecoveryIssue != null) {
      return Future<OperationHandle>.error(childRecoveryIssue.blockedFailure());
    }
    final childStorage = _client.conversations
        .sessionState(summary.childThreadId)
        ?.storage;
    if (childStorage?.blocksContinuation == true) {
      return Future<OperationHandle>.error(
        threadStorageContinuationFailure(childStorage!),
      );
    }
    final key = 'interaction:$hostThreadId';
    final operation = _client.mutations.begin(target: key);
    _begin(key, label: summary.interactionId);
    // 在途决议自己保留该宿主的主题份额：离开页面只 detach 展示，不撤销本次
    // 操作的事实观察；观察结算或失败时随 binding 一并回收。
    BridgeTopicLease decisionLease;
    try {
      decisionLease = _client.channels.acquireChildInteractions(hostThreadId);
    } catch (error) {
      operation.reject(error);
      if (_isLatest(operation)) _fail(key, summary.interactionId, error);
      return Future<OperationHandle>.error(error);
    }
    try {
      _watchPredicate(
        operation,
        _client.childInteractions(hostThreadId).source,
        (observation) =>
            observation.canonical.loaded &&
            (observation.canonical.value?.confirmsDecision(
                  childThreadId: summary.childThreadId,
                  interactionId: summary.interactionId,
                  revision: summary.revision,
                ) ??
                false),
        () => _clear(key),
        topicLease: decisionLease,
      );
    } catch (error) {
      // A failed registration never owned the binding; the lease share must
      // not outlive this attempt. Release is idempotent for a cancelled binding.
      unawaited(decisionLease.release().catchError((Object _) {}));
      operation.reject(error);
      if (_isLatest(operation)) _fail(key, summary.interactionId, error);
      return Future<OperationHandle>.error(error);
    }
    return _lane.enqueue(() async {
      final hostRecoveryIssue = _executionBlockerForThread(hostThreadId);
      if (_isExecutionClosed(hostThreadId) ||
          _isExecutionClosed(summary.childThreadId)) {
        _rejectQueuedOperation(
          operation,
          key,
          summary.interactionId,
          _closedReadOnlyFailure,
        );
        throw _closedReadOnlyFailure;
      }
      if (hostRecoveryIssue != null) {
        final failure = hostRecoveryIssue.blockedFailure();
        _rejectQueuedOperation(operation, key, summary.interactionId, failure);
        throw failure;
      }
      final hostStorage = _client.conversations
          .sessionState(hostThreadId)
          ?.storage;
      if (hostStorage?.blocksContinuation == true) {
        final failure = threadStorageContinuationFailure(hostStorage!);
        _rejectQueuedOperation(operation, key, summary.interactionId, failure);
        throw failure;
      }
      final childRecoveryIssue = _executionBlockerForThread(
        summary.childThreadId,
      );
      if (childRecoveryIssue != null) {
        final failure = childRecoveryIssue.blockedFailure();
        _rejectQueuedOperation(operation, key, summary.interactionId, failure);
        throw failure;
      }
      final childStorage = _client.conversations
          .existingSession(summary.childThreadId)
          ?.state
          .storage;
      if (childStorage?.blocksContinuation == true) {
        final failure = threadStorageContinuationFailure(childStorage!);
        _rejectQueuedOperation(operation, key, summary.interactionId, failure);
        throw failure;
      }
      try {
        final response = await _api.respondInteraction(
          hostThreadId,
          summary.interactionId,
          summary.revision,
          resolution,
          operationId: operation.id,
        );
        if (response.interaction.id != summary.interactionId ||
            response.interaction.threadId != summary.childThreadId ||
            !response.receipt.requiresIdentityObservation) {
          throw StateError(
            'Child interaction receipt did not match the stable target',
          );
        }
        try {
          operation.accept(response.receipt.toCommitReceipt());
        } finally {
          // Acceptance can synchronously observe this command or admit a newer
          // intent. Keep a recorded receipt even if later synchronization fails,
          // but never recreate a cleared command or mark the newer intent.
          if (_isLatest(operation) && operation.state.value.receipt != null) {
            _markAccepted(key);
          }
        }
        return operation;
      } catch (error) {
        _failOperation(operation, error);
        if (_isLatest(operation)) _fail(key, summary.interactionId, error);
        rethrow;
      }
    });
  }

  Future<StudioThread?> renameThread(String threadId, String title) {
    _ensureOpen();
    final key = 'rename:$threadId';
    final operation = _client.mutations.begin(target: key);
    _begin(key, label: title);
    _watchObservation(operation, () => _clear(key));
    return _lane.enqueue(() async {
      final thread = _directoryThread(threadId);
      final recoveryIssue = _accessBlockerForThread(threadId);
      if (recoveryIssue != null) {
        final failure = recoveryIssue.blockedFailure();
        _failOperation(operation, failure);
        if (_isLatest(operation)) _fail(key, threadId, failure);
        throw failure;
      }
      if (thread == null || !thread.isRoot) {
        operation.reject(StateError('Thread rename is unavailable'));
        if (_isLatest(operation)) _clear(key);
        return null;
      }
      try {
        final response = await _api.renameThread(
          threadId,
          title,
          operationId: operation.id,
        );
        operation.accept(response.receipt.toCommitReceipt());
        // 目录增量已在命令内发布（commit_directory），不重读聚合状态。
        return response.thread;
      } catch (error) {
        _failOperation(operation, error);
        if (_isLatest(operation)) _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<void> archiveThread(String threadId) {
    _ensureOpen();
    if (AgentDirectoryQueries.rootThreadId(
          threadId: _client.selection.state.selectedThreadId,
          agents: _client.project.state.agents?.values ?? const [],
          threads: [
            ..._client.threadDirectory.state.window.threads,
            ..._client.threadDirectory.state.overlayThreads,
          ],
        ) ==
        threadId) {
      _client.selection.beginNavigation();
    }
    final key = 'archive:$threadId';
    final operation = _client.mutations.begin(target: key);
    _begin(key, label: threadId);
    _watchObservation(operation, () => _clear(key));
    return _lane.enqueue(() async {
      final thread = _directoryThread(threadId);
      final recoveryIssue = _accessBlockerForThread(threadId);
      if (recoveryIssue != null) {
        final failure = recoveryIssue.blockedFailure();
        _failOperation(operation, failure);
        if (_isLatest(operation)) _fail(key, threadId, failure);
        throw failure;
      }
      if (thread == null || !thread.isRoot) {
        operation.reject(StateError('Thread archive is unavailable'));
        if (_isLatest(operation)) _clear(key);
        return;
      }
      try {
        final response = await _api.archiveThread(
          threadId,
          operationId: operation.id,
        );
        operation.accept(response.receipt.toCommitReceipt());
        final result = response.result;
        if (!_client.isClosed) {
          for (final id in result.removedThreadIds) {
            if (_client.selection.state.selectedThreadId == id) {
              _client.conversations.setVisibleThread(null);
            }
          }
          final selected = _client.selection.state.selectedThreadId;
          if (selected != null && result.removedThreadIds.contains(selected)) {
            _client.selection.replaceRemovedThread(result.nextRoot?.id);
          }
        }
      } catch (error) {
        _failOperation(operation, error);
        if (_isLatest(operation)) _fail(key, threadId, error);
        rethrow;
      }
    });
  }

  Future<void> _applyThreadModelRoute({
    required OperationHandle operation,
    required SettingsWriteOwner owner,
    required String threadId,
    required String accountId,
    required String modelId,
    String? effort,
  }) async {
    final key = 'thread-route:$threadId';
    final target = CommandTarget(
      accountId: accountId,
      modelId: modelId,
      effort: effort,
    );
    final settings = _client.settings;
    var issued = false;
    Object? requestFailure;
    try {
      _client.settingsWrites.requireOwner(owner);
      _throwIfAccessBlockedForThread(threadId);
      if (!_client.settings.state.configLoaded) {
        final refreshed = await _client.settingsCommands.refreshCanonical(
          owner: owner,
        );
        _client.settingsWrites.requireOwner(owner);
        if (refreshed == null || !_client.settings.state.configLoaded) {
          throw StateError('Settings are not available yet.');
        }
      }
      final response = await retryRevisionConflict(() async {
        _client.settingsWrites.requireOwner(owner);
        _throwIfAccessBlockedForThread(threadId);
        var attemptIssued = false;
        try {
          return await _requestThreadModelRoute(
            operationId: operation.id,
            owner: owner,
            onIssue: () {
              attemptIssued = true;
              issued = true;
              requestFailure = null;
            },
            threadId: threadId,
            accountId: accountId,
            modelId: modelId,
            effort: effort,
          );
        } catch (error) {
          if (attemptIssued) requestFailure = error;
          rethrow;
        }
      }, refresh: () => _refreshRouteOwners(threadId, owner));
      operation.accept(response.receipt.toCommitReceipt());
      _client.settingsWrites.requireOwner(owner);
      if (!!_client.isClosed) return;
      _client.acceptSettingsSnapshot(response.settings, owner: owner);
      _client.settingsWrites.requireOwner(owner);
      if (_isLatest(operation)) {
        _rememberWarning(threadId, response.warning);
      }
    } catch (error) {
      if (!issued) {
        operation.reject(error);
      } else {
        // Refresh or local admission failures cannot replace the outcome of
        // the last request that actually crossed the transport boundary.
        _failOperation(operation, requestFailure ?? error);
      }
      if (!_client.isClosed &&
          _client.settingsWrites.isCurrentOwner(owner) &&
          _isLatest(operation)) {
        settings.failCommand(
          key,
          typedCommandFailure(error, correlationId: 'client-thread-route'),
          target: target,
        );
      }
      rethrow;
    }
  }

  /// 两次 revision 都在尝试前从各自 owner 读取。响应 runtime 不进入 store。
  Future<ThreadModelRouteCommandReply> _requestThreadModelRoute({
    required OperationId operationId,
    required SettingsWriteOwner owner,
    required void Function() onIssue,
    required String threadId,
    required String accountId,
    required String modelId,
    String? effort,
  }) async {
    _client.settingsWrites.requireOwner(owner);
    _throwIfAccessBlockedForThread(threadId);
    final session = _client.conversations.session(threadId).state;
    final route = session.runtime?.modelRoute;
    final target = _findModel(accountId, modelId);
    if (!session.hasSnapshot || route == null || target == null) {
      throw StateError('Selected thread model route is unavailable.');
    }
    _client.settingsWrites.requireOwner(owner);
    _throwIfAccessBlockedForThread(threadId);
    onIssue();
    return _api.setThreadModelRoute(
      operationId: operationId,
      threadId: threadId,
      expectedModelRouteRevision: route.revision,
      expectedSettingsRevision:
          _client.settingsWrites.stamp?.revision ??
          _client.settings.state.settingsRevision,
      accountId: accountId,
      modelId: modelId,
      effort: effort ?? target.reasoningEfforts.firstOrNull,
    );
  }

  Future<bool> _refreshRouteOwners(
    String threadId,
    SettingsWriteOwner owner,
  ) async {
    _client.settingsWrites.requireOwner(owner);
    _throwIfAccessBlockedForThread(threadId);
    final settings = await _client.settingsCommands.refreshCanonical(
      owner: owner,
    );
    _client.settingsWrites.requireOwner(owner);
    _throwIfAccessBlockedForThread(threadId);
    if (settings == null || !!_client.isClosed) return false;
    try {
      await _client.conversations.session(threadId).resyncRuntime();
    } catch (_) {
      _client.settingsWrites.requireOwner(owner);
      // Only a fresh owner baseline permits another CAS attempt. Observation
      // failure or retired demand preserves the original known conflict.
      return false;
    }
    _client.settingsWrites.requireOwner(owner);
    _throwIfAccessBlockedForThread(threadId);
    return !_client.isClosed;
  }

  AccountModelView? _findModel(String accountId, String modelId) {
    final accounts = _client.modelAccounts;
    for (final account in accounts) {
      if (account.id != accountId) continue;
      for (final candidate in account.models) {
        if (candidate.modelId == modelId) return candidate;
      }
    }
    return null;
  }

  StudioThread? _directoryThread(String threadId) {
    final directory = _client.threadDirectory.state;
    for (final thread in directory.window.threads) {
      if (thread.id == threadId) return thread;
    }
    for (final thread in directory.overlayThreads) {
      if (thread.id == threadId) return thread;
    }
    return null;
  }

  /// 智能体目录里该成员行的唯一事实；未装载时为空，不据旧摘要假造成员。
  StudioAgentView? _agentEntry(String threadId) {
    final agents = _client.project.state.agents?.values;
    if (agents == null) return null;
    for (final agent in agents) {
      if (agent.threadId == threadId) return agent;
    }
    return null;
  }

  /// 子会话身份来自规范目录成员关系与 Thread 父子链接，不从界面选择推导。
  bool _isChildThread(String threadId) {
    final thread = _directoryThread(threadId);
    if (thread != null && !thread.isRoot) return true;
    return _agentEntry(threadId)?.parentPath != null;
  }

  StudioFailure _childRequiresParentScheduling(String threadId) =>
      StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message:
            'A child agent is continued and instructed by the main session',
        retryable: false,
        correlationId: 'client-child-requires-parent-scheduling',
        reason: StudioFailureReason.childThreadRequiresParentScheduling,
      );

  /// 目录级停止观察：只在同一成员行确认目标执行已结束或被安全替代时成立。
  ///
  /// 缺页、未装载或行内没有执行都不能被读成「停止完成」——那只是没有可证明的目标执行。
  bool _directoryExecutionEnded(
    ProjectStoreState state,
    String threadId,
    String executionId,
  ) {
    final agents = state.agents?.values;
    if (agents == null) return false;
    for (final agent in agents) {
      if (agent.threadId != threadId) continue;
      return agent.execution?.id != executionId;
    }
    return false;
  }

  /// 已存在意图按原身份回查一次；仅回查本身的 NotFound 才允许原身份再发。
  ///
  /// 已受理就沿用原回执；NotFound 证明该身份从未被受理，此时在串行 lane 内
  /// 复核准入后以冻结输入与**同一 OperationId** 再发，不换编号、不递归公共
  /// continueThread；其它回查错误原样上抛，保留未知结果，不盲目重发。
  Future<ContinueThreadCommandReply> _reconcileExistingIntent(
    _ContinuationIntent intent,
  ) async {
    final operation = intent.operation;
    if (operation == null) {
      throw StateError('A continuation intent has no operation identity');
    }
    final ContinuationOperationView view;
    // A determined rejection proves this intent reached a terminal local
    // disposition. Re-sending it after a NotFound would admit a second attempt
    // under the frozen identity and only then reject the handle after the
    // transport accepted it: fail closed instead. A held receipt is different:
    // the original acceptance keeps its observation duty and later guards
    // still return their typed failures through the normal resend path.
    void throwIfDefinitelyDisposed() {
      final state = operation.state.value;
      if (state.failurePhase == OperationPhase.rejected) {
        throw state.error ??
            StateError('The continuation intent was already rejected');
      }
    }

    try {
      // 只读回查走并行跟踪的 run：它不排在 mutation 串行队列里，后续再发的
      // enqueue 不会在持有同串行 lane 的闭包内等待自己。
      view = await _lane.run(() {
        _throwIfAccessBlockedForThread(intent.threadId);
        return _api.readContinuationOperation(
          intent.threadId,
          operation.id.value,
        );
      });
    } on StudioFailure catch (error, stackTrace) {
      if (error.code != StudioFailureCode.notFound) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      // The backend proves this identity was never admitted: resend the frozen
      // input under the SAME operation id after the serial lane re-checks
      // admission. The intent, its unknown protection and its observation
      // responsibility stay with the original identity.
      // The read itself may have raced a reentrant disposition change, so the
      // frozen identity is re-checked before any dispatch decision.
      throwIfDefinitelyDisposed();
      return _sendContinuation(intent, resend: true);
    }
    if (view.threadId != intent.threadId ||
        view.operationId != operation.id.value) {
      throw StateError('Continuation read did not match the frozen identity');
    }
    // Use the original handle directly: a missing or already-rejected identity
    // is an incompatible state that must fail closed instead of re-beginning.
    operation.accept(view.receipt.toCommitReceipt());
    switch (view.state) {
      case ConsumedContinuation():
        // A consumed control input is a canonical fact about the new Turn: the
        // effect happened even though the original receipt was lost.
        if (operation.state.value.receipt != null) {
          if (!operation.state.value.effective) operation.markEffective();
          if (!operation.state.value.observed) operation.markObserved();
        }
      case DiscardedContinuation():
        // A discarded control input never runs; it must not stay pending.
        operation.reject(
          StudioFailure(
            code: StudioFailureCode.conflict,
            message: 'The continuation intent was discarded',
            retryable: false,
            correlationId: 'client-continuation-discarded',
            reason: StudioFailureReason.continuationUnavailable,
          ),
        );
      case PendingContinuation():
        // Still admitted and unconsumed: the identity observer registered at
        // dispatch settles it when the canonical Turn appears.
        break;
    }
    if (_client.mutations.latest('continue:${intent.threadId}')?.id ==
        operation.id) {
      _clear('continue:${intent.threadId}');
    }
    return ContinueThreadCommandReply(
      threadId: view.threadId,
      inputId: view.inputId,
      continuationId: view.continuationId,
      cursor: view.acceptedSequence,
      receipt: view.receipt,
    );
  }

  String? _workspaceIdForThread(String threadId) {
    final directoryProjectId = _directoryThread(threadId)?.workspaceId;
    if (directoryProjectId != null) return directoryProjectId;
    final workspaceProjectId = _client.conversations
        .existingSession(threadId)
        ?.state
        .workspace
        ?.thread
        .workspaceId;
    if (workspaceProjectId != null) return workspaceProjectId;
    final selection = _client.selection.state;
    return selection.selectedThreadId == threadId
        ? selection.selectedProjectId
        : null;
  }

  StudioRecoveryIssue? _accessBlockerForThread(String threadId) =>
      recoveryIssueBlockingAccess(
        _client.recovery.state.value?.values ?? const [],
        workspaceId: _workspaceIdForThread(threadId),
        threadId: threadId,
      );

  StudioRecoveryIssue? _executionBlockerForThread(String threadId) =>
      recoveryIssueBlockingExecution(
        _client.recovery.state.value?.values ?? const [],
        workspaceId: _workspaceIdForThread(threadId),
        threadId: threadId,
      );

  StudioRecoveryIssue? _executionBlockerForProject(String workspaceId) =>
      recoveryIssueBlockingExecution(
        _client.recovery.state.value?.values ?? const [],
        workspaceId: workspaceId,
      );

  void _throwIfAccessBlockedForThread(String threadId) {
    final issue = _accessBlockerForThread(threadId);
    if (issue != null) throw issue.blockedFailure();
  }

  static const _closedReadOnlyFailure = StudioFailure(
    code: StudioFailureCode.permissionDenied,
    message: 'Finally closed Threads are read-only',
    retryable: false,
    correlationId: 'client-thread-closed',
    detailsJson: '{"reason":"threadClosed"}',
  );

  void _throwIfExecutionClosed(String threadId) {
    if (_isExecutionClosed(threadId)) {
      throw _closedReadOnlyFailure;
    }
  }

  // A read-only gate must not admit a cold child owner. Missing local facts
  // remain unknown; the backend still authoritatively rejects retired targets.
  bool _isExecutionClosed(String threadId) =>
      _directoryThread(threadId)?.status.blocksNewExecution == true ||
      _client.conversations
              .sessionState(threadId)
              ?.workspace
              ?.thread
              .status
              .blocksNewExecution ==
          true ||
      switch (_agentEntry(threadId)?.state) {
        ClosingStudioAgent() || ClosedStudioAgent() => true,
        _ => false,
      };

  void _rememberWarning(String threadId, String? warning) {
    final warnings = {...state.warnings};
    if (warning == null) {
      warnings.remove(threadId);
    } else {
      warnings[threadId] = warning;
    }
    if (_stringMapsEqual(warnings, state.warnings)) return;
    state = state.copyWith(warnings: warnings);
  }

  void _begin(String key, {required String label}) {
    _put(
      CommandStatus(
        key: key,
        phase: CommandPhase.pending,
        target: CommandTarget(label: label),
        startedAtMs: _nowMs(),
      ),
    );
  }

  void _clear(String key) {
    if (!state.commands.containsKey(key)) return;
    state = state.copyWith(commands: {...state.commands}..remove(key));
  }

  void _fail(String key, String id, Object error) {
    final existing = state.commands[key];
    _put(
      CommandStatus(
        key: key,
        phase: CommandPhase.failed,
        target: existing?.target ?? CommandTarget(label: id),
        error: typedCommandFailure(error, correlationId: 'client-thread'),
        // An already received acceptance receipt stays a fact even when the
        // following observation fails.
        accepted: existing?.accepted ?? false,
        startedAtMs: existing?.startedAtMs ?? _nowMs(),
      ),
    );
  }

  /// 记录「已收到受理回执」；已结算或已清除的命令不再重建该条状态。
  void _markAccepted(String key) {
    final existing = state.commands[key];
    if (existing == null || existing.accepted) return;
    _put(existing.withAccepted());
  }

  void _put(CommandStatus status) {
    final commands = {...state.commands, status.key: status};
    if (commandMapsEqual(commands, state.commands)) return;
    state = state.copyWith(commands: commands);
  }

  StudioTransport get _api => _client.transport;

  bool _isLatest(OperationHandle operation) =>
      _client.mutations.latest(operation.state.value.target)?.id ==
      operation.id;

  void _watchObservation(
    OperationHandle operation,
    void Function() onObserved,
  ) {
    late final Observation observation;
    void merge(OperationState value) {
      if (value.observed && !_client.isClosed && _isLatest(operation))
        onObserved();
      if (value.observed || value.failurePhase != null) {
        observation.cancel();
        _operationObservations.remove(observation);
      }
    }

    final watched = operation.state.watchLatest(merge);
    observation = watched.observation;
    _operationObservations.add(observation);
    merge(watched.value);
  }

  void _watchIdentity(
    OperationHandle operation,
    String threadId,
    bool Function(ThreadSessionState) predicate,
    void Function() onObserved,
  ) {
    _watchPredicate<ThreadSessionState>(
      operation,
      _client.conversations.session(threadId).source,
      predicate,
      onObserved,
    );
  }

  /// 注册一次有预算的 identity 观察。
  ///
  /// [source] 是该操作真正的 canonical 镜像：主会话停止与继续看 Thread 状态，
  /// 成员行停止看智能体目录，子任务交互看主会话的工作区投影。注册与当前值读取
  /// 是同一同步事务，帧先到和回执先到都不漏确认。
  void _watchPredicate<S>(
    OperationHandle operation,
    ValueObservation<S> source,
    bool Function(S) predicate,
    void Function() onObserved, {
    _ObservationFailurePolicy policy =
        _ObservationFailurePolicy.cancelOnFailure,
    BridgeTopicLease? topicLease,
  }) {
    final permit = _client.budget.acquire(
      ResourceKind.observer,
      owner: 'command:${operation.id.value}',
    );
    final binding = _IdentityOperationObservation(permit, topicLease);
    var confirmed = false;
    void completeIfAccepted() {
      final current = operation.state.value;
      if (binding.isCancelled ||
          !confirmed ||
          current.observed ||
          current.receipt?.requiresIdentityObservation != true)
        return;
      if (!current.effective) operation.markEffective();
      operation.markObserved();
    }

    void mergeOwner(S next) {
      if (binding.isCancelled) return;
      if (predicate(next)) confirmed = true;
      completeIfAccepted();
    }

    void mergeOperation(OperationState next) {
      if (next.observed && !_client.isClosed && _isLatest(operation))
        onObserved();
      final settled = switch (policy) {
        _ObservationFailurePolicy.cancelOnFailure =>
          next.observed || next.failurePhase != null,
        _ObservationFailurePolicy.retainUntilSettled =>
          next.observed || next.failurePhase == OperationPhase.rejected,
      };
      if (settled) {
        binding.cancel();
        _operationObservations.remove(binding);
      } else {
        completeIfAccepted();
      }
    }

    try {
      // Registration and the current value are one synchronous transaction.
      // A matching frame before the receipt is remembered by this binding;
      // the receipt still supplies its own authoritative disposition.
      final owner = source.watchLatest(mergeOwner);
      binding.owner = owner.observation;
      final receipt = operation.state.watchLatest(mergeOperation);
      binding.operation = receipt.observation;
      _operationObservations.add(binding);
      mergeOwner(owner.value);
      mergeOperation(receipt.value);
    } catch (_) {
      binding.cancel();
      _operationObservations.remove(binding);
      rethrow;
    }
  }

  void _failOperation(OperationHandle operation, Object error) {
    if (operation.state.value.receipt != null) {
      operation.syncFailed(error);
    } else if (error is StudioFailure &&
        (switch (error.code) {
          StudioFailureCode.invalidArgument ||
          StudioFailureCode.notFound ||
          StudioFailureCode.busy ||
          StudioFailureCode.conflict ||
          StudioFailureCode.staleRevision ||
          StudioFailureCode.permissionDenied ||
          StudioFailureCode.overloaded => true,
          _ => false,
        })) {
      operation.reject(error);
    } else {
      operation.unknownOutcome(error);
    }
  }

  void _rejectQueuedOperation(
    OperationHandle operation,
    String key,
    String label,
    Object error,
  ) {
    operation.reject(error);
    if (_isLatest(operation)) _fail(key, label, error);
  }
}

class ThreadCommandBoard {
  const ThreadCommandBoard({
    this.commands = const {},
    this.warnings = const {},
  });

  final Map<String, CommandStatus> commands;
  final Map<String, String> warnings;

  ThreadCommandBoard copyWith({
    Map<String, CommandStatus>? commands,
    Map<String, String>? warnings,
  }) {
    return ThreadCommandBoard(
      commands: commands ?? this.commands,
      warnings: warnings ?? this.warnings,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(other, this) ||
      other is ThreadCommandBoard &&
          commandMapsEqual(commands, other.commands) &&
          _stringMapsEqual(warnings, other.warnings);

  @override
  int get hashCode =>
      Object.hash(commandMapHash(commands), _stringMapHash(warnings));
}

bool _stringMapsEqual(Map<String, String> left, Map<String, String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

int _stringMapHash(Map<String, String> values) => Object.hashAll(
  values.entries.map((entry) => Object.hash(entry.key, entry.value)),
);

/// 一个 `(threadId, executionId)` 的停止登记。
///
/// 结构上只有两段：当前在途尝试，以及至多一个排队的重试。任何时刻都不会出现第三个
/// 请求，因此重复点击与超时重试都不会累积排队请求或 pending permit。
final class _StopFlight {
  _StopFlight({
    required this.threadId,
    required this.executionId,
    required this.fromDirectory,
    required this.requireCurrentCanonical,
  });

  final String threadId;
  final String executionId;
  final bool fromDirectory;
  final bool requireCurrentCanonical;

  /// 当前在途尝试的 future；结算后由排队重试取代或整条登记被清除。
  Future<ThreadStopOutcome>? inFlight;

  /// 唯一排队重试的返回结果（立即完成，语义为「已排队、尚未发出」）。
  Future<ThreadStopOutcome>? queued;
}

/// 一个 (会话, 继续点) 意图的一次性冻结身份与唯一在途结果。
///
/// Thread、continuation 身份、route CAS 与 OperationId 在首次创建时冻结；
/// 回执丢失或页面离开后，这个身份仍然可用：再次显式点击先按它回查原操作，
/// 仅当回查证明 NotFound 时才以同一身份再发冻结输入，不换编号，也不会同时
/// 存在两个操作。
final class _ContinuationIntent {
  _ContinuationIntent({
    required this.threadId,
    required this.continuationId,
    required this.expectedModelRouteRevision,
  });

  final String threadId;
  final String continuationId;
  final int expectedModelRouteRevision;

  /// 分配一次；任何后续路径不得重新 begin 或替换该身份。
  OperationHandle? operation;

  /// 当前在途结果；同一意图的所有调用共享同一个 future。
  Future<ContinueThreadCommandReply>? inFlight;
}

/// An identity predicate and its operation retention form one bounded observer.
final class _IdentityOperationObservation implements Observation {
  _IdentityOperationObservation(this.permit, [this.topicLease]);
  final ResourcePermit permit;

  /// 本次观察保留的主题份额；观察结算、失败或关闭时一并释放。
  /// 释放失败由订阅登记表保留原句柄与许可，这里只记录诊断。
  final BridgeTopicLease? topicLease;
  Observation? owner;
  Observation? operation;
  @override
  bool isCancelled = false;
  @override
  bool get isPaused => owner?.isPaused ?? false;
  @override
  void pause() {
    owner?.pause();
  }

  @override
  void resume() {
    owner?.resume();
  }

  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    owner?.cancel();
    operation?.cancel();
    permit.release();
    final lease = topicLease;
    if (lease != null) {
      unawaited(
        lease.release().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            log(
              'command_topic_lease_release_failed topic=${lease.topic} '
              'error=$error',
              stackTrace: stack,
            );
          },
        ),
      );
    }
  }
}
