import 'package:anywork_client/conversation.dart'
    show ContinuationReason, InteractionKind, StudioFailureReason;
import 'package:anywork_client/drafts.dart' show AttachmentModality;
import 'package:anywork_client/models.dart' show ModelModality;
import 'package:anywork_client/modes.dart' show ThreadModeId;
import 'package:anywork_client/workspace.dart' show ThreadStatus;
import 'package:flutter/material.dart';

import '../features/conversation/state/composer_primary_action.dart';
import '../ui/formatters/throughput_format.dart';
import 'app_localizations.dart';

extension StudioLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  String compileModeLabel(ThreadModeId mode) {
    if (mode == ThreadModeId.simple) return l10n.compileModeSimple;
    if (mode == ThreadModeId.task) return l10n.compileModeTask;
    return mode.id;
  }

  /// Maps a canonical workflow state id to its localized display label.
  ///
  /// Only the built-in Task workflow phases are localized; an unknown or
  /// future state id is returned unchanged so canonical identity is never
  /// hidden behind a wrong translation.
  String workflowStateLabel(String stateId) {
    return switch (stateId.trim()) {
      'planning' => l10n.workflowStatePlanning,
      'editing_documents' => l10n.workflowStateEditingDocuments,
      'working' => l10n.workflowStateWorking,
      'integrating' => l10n.workflowStateIntegrating,
      'reviewing' => l10n.workflowStateReviewing,
      'completed' => l10n.workflowStateCompleted,
      'stopped' => l10n.workflowStateStopped,
      _ => stateId,
    };
  }

  /// Maps a canonical built-in thread mode id to its localized display label.
  ///
  /// Custom or unknown modes are returned unchanged.
  String workflowModeLabel(String modeId) {
    return switch (modeId.trim()) {
      'mode.simple' => l10n.workflowModeSimple,
      'mode.task' => l10n.workflowModeTask,
      _ => modeId,
    };
  }

  /// 吞吐量标签：数值由领域层提供，单位按 locale 追加（如“词元/秒”）。
  String tokenThroughputLabel(double? tokensPerSecond) {
    final value = formatTokenThroughputValue(tokensPerSecond);
    return value == null
        ? l10n.statusThroughputUnavailable
        : l10n.statusThroughputValue(value);
  }

  /// Maps a canonical account protocol (vendor adapter) to its display label.
  ///
  /// 身份来自 canonical `protocol` 值，不按模板 ID、显示名或地址推断。
  String protocolKindLabel(String protocol) {
    return switch (protocol) {
      'open_ai' => l10n.accountProtocolOpenAi,
      'deep_seek' => l10n.accountProtocolDeepSeek,
      'zhipu' => l10n.accountProtocolZhipu,
      'mi_mo' => l10n.accountProtocolMiMo,
      'xai' => l10n.accountProtocolXai,
      'open_ai_compatible' => l10n.accountProtocolCustom,
      _ => protocol,
    };
  }

  /// Maps a canonical wire API to its localized display label.
  String modelWireApiLabel(String protocol) {
    return switch (protocol) {
      'responses' => l10n.modelProtocolResponses,
      'chat_completions' => l10n.modelProtocolChatCompletions,
      _ => protocol,
    };
  }

  /// Maps a canonical connection mode to its localized display label.
  String modelConnectionLabel(String mode) {
    return switch (mode) {
      'web_socket' => l10n.modelConnectionWebSocket,
      'http' => l10n.modelConnectionHttp,
      _ => mode,
    };
  }

  String interactionKindLabel(InteractionKind kind) {
    return switch (kind) {
      InteractionKind.toolApproval => l10n.statusInteractionToolApproval,
      InteractionKind.userInput => l10n.statusInteractionUserInput,
    };
  }

  /// Maps a model modality to its localized display name.
  String modalityLabel(ModelModality modality) {
    return switch (modality) {
      ModelModality.text => l10n.modalityText,
      ModelModality.image => l10n.modalityImage,
      ModelModality.audio => l10n.modalityAudio,
      ModelModality.video => l10n.modalityVideo,
      ModelModality.file => l10n.modalityFile,
    };
  }

  /// Maps an attachment modality to its localized display name.
  String attachmentModalityLabel(AttachmentModality modality) {
    return switch (modality) {
      AttachmentModality.image => l10n.modalityImage,
      AttachmentModality.video => l10n.modalityVideo,
      AttachmentModality.file => l10n.modalityFile,
    };
  }

  /// Maps a protocol role key to its localized display name.
  ///
  /// Fixed roles translate to the current locale; an empty role falls back to a
  /// generic label; unknown extension roles are returned unchanged so custom
  /// identities are never hidden or rewritten.
  String roleLabel(String role) {
    return switch (role.trim()) {
      'explorer' => l10n.roleExplorer,
      'planner' => l10n.rolePlanner,
      'executor' => l10n.roleExecutor,
      'worktree_executor' => l10n.roleWorktreeExecutor,
      'reviewer' => l10n.roleReviewer,
      '' => l10n.roleEmpty,
      _ => role,
    };
  }

  /// Maps a fixed agent role key to its localized responsibility summary.
  ///
  /// System Agent cards and route rows share this single mapping so the same
  /// role always renders the same description in the active locale; unknown
  /// roles fall back to the generic summary instead of leaking runtime
  /// metadata, while user profiles never reach this mapping.
  String roleDescription(String role) {
    return switch (role.trim()) {
      'explorer' => l10n.settingsRoleExplorerDescription,
      'planner' => l10n.settingsRolePlannerDescription,
      'executor' => l10n.settingsRoleExecutorDescription,
      'worktree_executor' => l10n.settingsRoleWorktreeExecutorDescription,
      'reviewer' => l10n.settingsRoleReviewerDescription,
      _ => l10n.settingsRoleFallbackDescription,
    };
  }

  /// Maps a thread lifecycle status to its localized display label.
  ///
  /// The header agent switcher and the status bar share this single mapping so
  /// the same canonical status always renders the same localized text.
  String threadStatusLabel(ThreadStatus status) {
    return switch (status) {
      ThreadStatus.idle => l10n.threadStatusIdle,
      ThreadStatus.queued => l10n.agentDetailStatusQueued,
      ThreadStatus.running => l10n.agentDetailStatusRunning,
      ThreadStatus.waitingTool => l10n.statusTurnWaitingForApproval,
      ThreadStatus.waitingInteraction => l10n.statusTurnWaitingForUserInput,
      ThreadStatus.cancelling => l10n.threadStatusCancelling,
      ThreadStatus.closing => l10n.agentDetailStatusClosing,
      ThreadStatus.closed => l10n.threadStatusClosed,
      ThreadStatus.faulted => l10n.agentDetailStatusErrored,
    };
  }

  /// Maps a canonical tool status to its localized status-pill label.
  ///
  /// Unknown statuses are returned unchanged so extension or future values are
  /// never hidden behind a wrong translation.
  String toolStatusLabel(String status) {
    return switch (status.trim()) {
      'queued' => l10n.agentDetailStatusQueued,
      'running' ||
      'streaming' ||
      'approved' ||
      'started' => l10n.agentDetailStatusRunning,
      'awaitingApproval' => l10n.toolStatusAwaitingApproval,
      'succeeded' => l10n.agentDetailStatusCompleted,
      'failed' => l10n.toolStatusFailed,
      'denied' => l10n.toolStatusDenied,
      'cancelled' => l10n.toolStatusCancelled,
      'cancelling' => l10n.toolStatusCancelling,
      'interrupted' => l10n.agentDetailStatusInterrupted,
      'budgetLimited' => l10n.timelineReasoningBudgetLimited,
      _ => status,
    };
  }

  /// 主输入区被阻塞的类型化原因。
  ///
  /// 保存、模型与工作区阻塞由 canonical 事实判定；后端明确拒绝时用
  /// [StudioFailureReason] 的 typed 文案，缺失原因才退到中性说明，不把原始错误
  /// 文本当成原因分类。
  String composerBlockerLabel(ComposerBlocker blocker) {
    return switch (blocker) {
      ComposerStorageBlocker() => l10n.composerBlockedStorage,
      ComposerModelBlocker() => l10n.composerBlockedModel,
      ComposerWorkspaceBlocker() => l10n.composerBlockedWorkspace,
      ComposerFailureBlocker(:final reason) => composerFailureReasonLabel(
        reason,
      ),
    };
  }

  /// 后端 typed 失败原因的用户说明。
  String composerFailureReasonLabel(StudioFailureReason? reason) {
    return switch (reason) {
      StudioFailureReason.childThreadRequiresParentScheduling =>
        l10n.composerFailureChildRequiresParentScheduling,
      StudioFailureReason.continuationUnavailable =>
        l10n.composerFailureContinuationUnavailable,
      StudioFailureReason.continuationClaimed =>
        l10n.composerFailureContinuationClaimed,
      StudioFailureReason.staleContinuation =>
        l10n.composerFailureStaleContinuation,
      StudioFailureReason.staleExecution => l10n.composerFailureStaleExecution,
      StudioFailureReason.noExecution => l10n.composerNoExecution,
      StudioFailureReason.continuationAccepted =>
        l10n.composerContinuationAccepted,
      StudioFailureReason.executionInProgress =>
        l10n.composerFailureExecutionInProgress,
      StudioFailureReason.interactionNotHosted =>
        l10n.composerFailureInteractionNotHosted,
      StudioFailureReason.staleInteraction =>
        l10n.composerFailureStaleInteraction,
      // 归档会话只读：使用专用的继续/提交阻塞说明，不复用侧栏的归档标签。
      StudioFailureReason.threadArchived => l10n.composerBlockedArchived,
      null => l10n.composerBlockerUnknown,
    };
  }

  /// 继续点记录的已知中断原因；`null` 用中性说明，绝不回填「用户停止」。
  String composerContinuationReasonLabel(ContinuationReason? reason) {
    return switch (reason) {
      ContinuationReason.userStop => l10n.composerContinueReasonUserStop,
      ContinuationReason.hostShutdown =>
        l10n.composerContinueReasonHostShutdown,
      ContinuationReason.processInterrupted =>
        l10n.composerContinueReasonProcessInterrupted,
      ContinuationReason.stepLimit => l10n.composerContinueReasonStepLimit,
      ContinuationReason.executionFailed =>
        l10n.composerContinueReasonExecutionFailed,
      null => l10n.composerContinueReasonUnknown,
    };
  }

  /// Maps a canonical todo item status to its localized status-pill label.
  String todoStatusLabel(String status) {
    return switch (status.trim()) {
      'completed' => l10n.timelineTodoCompleted,
      'inProgress' => l10n.timelineTodoInProgress,
      'pending' => l10n.timelineTodoPending,
      _ => status,
    };
  }

  /// Maps a canonical account status to its localized display label.
  ///
  /// `ready` only describes configured credentials, not verified connectivity.
  /// `ready` and `missingCredential` are the only canonical statuses today;
  /// any other value is returned unchanged so unknown or future statuses are
  /// never mislabeled as a configuration state.
  String accountStatusLabel(String status) {
    return switch (status.trim()) {
      'ready' => l10n.settingsConfigured,
      'missingCredential' => l10n.settingsAccountMissingCredential,
      _ => status,
    };
  }

  /// Maps a canonical SSH connection state to its localized display label.
  String sshConnectionStateLabel(String state) {
    return switch (state.trim()) {
      'ready' => l10n.settingsSshReady,
      'disconnected' => l10n.settingsSshStateDisconnected,
      'connecting' => l10n.settingsSshStateConnecting,
      'waitingForInput' => l10n.settingsSshStateWaitingForInput,
      'reconnecting' => l10n.settingsSshStateReconnecting,
      'failed' => l10n.settingsSshStateFailed,
      _ => state,
    };
  }

  /// Maps a canonical worktree lease state to its localized display label.
  String worktreeStateLabel(String state) {
    return switch (state.trim()) {
      'prepared' => l10n.settingsWorktreeStatePrepared,
      'active' => l10n.settingsWorktreeStateActive,
      'preserved' => l10n.settingsWorktreeStatePreserved,
      'cleanupRequested' => l10n.settingsWorktreeStateCleanupRequested,
      'cleaned' => l10n.settingsWorktreeStateCleaned,
      _ => state,
    };
  }
}
