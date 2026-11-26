import 'package:anywork_client/models.dart' as feed;

import 'live_status_state.dart';

/// 前端实时状态栏单一状态机：将后端快照、待处理交互与线程存储状态仲裁为唯一的 [LiveStatusState]。
abstract final class LiveStatusMachine {
  static LiveStatusView project(
    String threadId,
    feed.LiveStatusSnapshot snapshot, {
    required DateTime receivedAt,
    feed.PendingInteraction? interaction,
    bool isChildThread = false,
    feed.ThreadStorageStateView? storageState,
  }) {
    final state = _resolveState(
      threadId,
      snapshot,
      interaction: interaction,
      isChildThread: isChildThread,
      storageState: storageState,
    );
    return LiveStatusView(
      threadId: threadId,
      state: state,
      primaryActivity: _deriveDiagnosticActivity(threadId, state),
      revision: snapshot.revision,
    );
  }

  static LiveStatusState _resolveState(
    String threadId,
    feed.LiveStatusSnapshot snapshot, {
    required feed.PendingInteraction? interaction,
    required bool isChildThread,
    required feed.ThreadStorageStateView? storageState,
  }) {
    // 1. 根线程交互栏负责直接响应人工审批/输入，状态栏退避为隐藏态，不重复渲染交互详情。
    if (!isChildThread &&
        (interaction != null || snapshot.suppressedByInteraction)) {
      return const LiveStatusHidden(suppressed: true);
    }

    // 2. 子线程在右栏只读展示当前待处理交互详情。
    if (isChildThread && interaction != null) {
      return LiveStatusChildInteractionState(
        interactionId: interaction.id,
        payload: interaction.payload,
      );
    }

    // 3. 停止中锁存最高优先级（来自快照相位或显式停止关注项）。
    if (snapshot.phase is feed.LiveStatusStopping ||
        snapshot.attentions.any((item) => item.kind == 'stopping')) {
      final startedAtMs = switch (snapshot.phase) {
        feed.LiveStatusStopping(:final startedAtMs) => startedAtMs,
        _ => null,
      };
      return LiveStatusStoppingState(startedAtMs: startedAtMs);
    }

    // 4. 模型重连、5. 压缩、6. 文本流输出、7. 思考与工作容器严格互斥。
    switch (snapshot.phase) {
      case feed.LiveStatusReconnecting(
        :final attemptId,
        :final message,
        :final retryAfterMs,
        :final attempt,
        :final maxAttempts,
      ):
        return LiveStatusReconnectingState(
          attemptId: attemptId,
          message: message,
          retryAfterMs: retryAfterMs,
          attempt: attempt,
          maxAttempts: maxAttempts,
        );
      case feed.LiveStatusCompacting(:final manual, :final startedAtMs):
        return LiveStatusCompactingState(
          manual: manual,
          startedAtMs: startedAtMs,
        );
      case feed.LiveStatusStreamingText(
        :final attemptId,
        :final itemId,
        :final text,
        :final startedAtMs,
      ):
        return LiveStatusStreamingState(
          attemptId: attemptId,
          itemId: itemId,
          text: text,
          startedAtMs: startedAtMs,
        );
      case feed.LiveStatusWorking(
        :final items,
        :final reasoningPreview,
        :final startedAtMs,
      ):
        return LiveStatusWorkingState(
          threadId: threadId,
          items: [
            for (final item in items)
              LiveWorkMember(
                id: item.id,
                callId: item.callId,
                kind: item.kind,
                toolName: item.toolName,
                status: item.status,
                summary: item.summary,
                startedAtMs: item.startedAtMs,
                finishedAtMs: item.finishedAtMs,
              ),
          ],
          reasoningPreview: reasoningPreview,
          startedAtMs: startedAtMs,
        );
      case feed.LiveStatusStopping():
      case feed.LiveStatusIdle():
        break;
    }

    // 8. 非运行主阶段下按 storage > disconnected > error > approval 仲裁单行告警。
    final alert = _resolveAlert(snapshot.attentions, storageState);
    if (alert != null) {
      return alert;
    }

    // 9. 默认隐藏态。
    return const LiveStatusHidden(suppressed: false);
  }

  static LiveStatusAlertState? _resolveAlert(
    List<feed.LiveAttention> attentions,
    feed.ThreadStorageStateView? storageState,
  ) {
    if (storageState != null && _needsStorageAlert(storageState)) {
      final severity = LiveStorageSeverity.fromStorage(storageState);
      return switch (severity) {
        LiveStorageSeverity.resumeReady => LiveStatusAlertState(
          kind: LiveAlertKind.storageReady,
          storage: storageState,
        ),
        LiveStorageSeverity.fault => LiveStatusAlertState(
          kind: LiveAlertKind.storageFault,
          detail: _nonEmpty(storageState.lastError),
          storage: storageState,
        ),
        LiveStorageSeverity.pressure ||
        LiveStorageSeverity.resumeRequired ||
        LiveStorageSeverity.paused => LiveStatusAlertState(
          kind: LiveAlertKind.storageWarning,
          detail: _nonEmpty(storageState.lastError),
          storage: storageState,
        ),
      };
    }

    for (final item in attentions) {
      if (item.kind == 'disconnected') {
        return LiveStatusAlertState(
          kind: LiveAlertKind.disconnected,
          detail: _nonEmpty(item.summary),
        );
      }
    }

    for (final item in attentions) {
      if (item.kind != 'approval' && item.kind != 'stopping') {
        return LiveStatusAlertState(
          kind: LiveAlertKind.error,
          detail: _nonEmpty(item.summary),
        );
      }
    }

    for (final item in attentions) {
      if (item.kind == 'approval') {
        return LiveStatusAlertState(
          kind: LiveAlertKind.approval,
          detail: _nonEmpty(item.summary),
        );
      }
    }

    return null;
  }

  static bool _needsStorageAlert(feed.ThreadStorageStateView storage) =>
      storage.hasFault ||
      storage.pressurePaused ||
      storage.resumeRequired ||
      storage.execution == feed.ThreadStorageExecution.paused;

  static String? _nonEmpty(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static feed.ConversationActivityView? _deriveDiagnosticActivity(
    String threadId,
    LiveStatusState state,
  ) {
    feed.ConversationActivityView activity(
      feed.ConversationActivityKind kind, {
      String? id,
      String? summary,
      String? thinkingSummary,
      String? errorMessage,
      feed.ThreadStorageStateView? storage,
      int activeToolCount = 0,
    }) => feed.ConversationActivityView(
      identity: id ?? '$threadId:${kind.name}',
      kind: kind,
      summary: summary,
      thinkingSummary: thinkingSummary,
      errorMessage: errorMessage,
      storage: storage,
      activeToolCount: activeToolCount,
    );

    return switch (state) {
      LiveStatusWorkingState(:final items, :final reasoningPreview) => activity(
        items.isEmpty
            ? feed.ConversationActivityKind.thinking
            : feed.ConversationActivityKind.runningTool,
        id: 'live-work:$threadId',
        thinkingSummary: reasoningPreview,
        activeToolCount: items.where((item) => item.isActive).length,
      ),
      LiveStatusStreamingState(:final itemId) => activity(
        feed.ConversationActivityKind.responding,
        id: itemId,
      ),
      LiveStatusCompactingState() => activity(
        feed.ConversationActivityKind.compacting,
      ),
      LiveStatusStoppingState() => activity(
        feed.ConversationActivityKind.stopping,
      ),
      LiveStatusAlertState(kind: LiveAlertKind.approval, :final detail) =>
        activity(
          feed.ConversationActivityKind.awaitingApproval,
          summary: detail,
        ),
      LiveStatusAlertState(
        kind: LiveAlertKind.storageReady ||
            LiveAlertKind.storageWarning ||
            LiveAlertKind.storageFault,
        :final detail,
        :final storage,
      ) =>
        activity(
          feed.ConversationActivityKind.storageBlocked,
          errorMessage: detail,
          storage: storage,
        ),
      LiveStatusHidden() ||
      LiveStatusReconnectingState() ||
      LiveStatusAlertState() ||
      LiveStatusChildInteractionState() => null,
    };
  }
}
