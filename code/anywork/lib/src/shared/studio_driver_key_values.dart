/// 测试与验收使用的键值字符串。
///
/// 本文件**只依赖 Dart**：纯 Dart 宿主脚本不能导入 `package:flutter`（缺少 `dart:ui`）。
/// Flutter 侧的 `StudioDriverKeys` 从同一常量构造 `ValueKey`，因此键值只有这一份事实源；
/// 需要新的键时，把字符串加进这里并在 `StudioDriverKeys` 中引用。
library;

import 'dart:convert';

import 'package:anywork_client/models.dart';

abstract final class StudioDriverKeyValues {
  static const sessionSettings = 'delegation-session-settings';
  static const defaultDelegationMode = 'delegation-default-mode';
  static const defaultDelegationPreference = 'delegation-default-preference';
  static const draftDelegationMode = 'delegation-draft-mode';
  static const draftDelegationPreference = 'delegation-draft-preference';
  static String delegationModeOption(String scope, DelegationMode? mode) =>
      'delegation-$scope-mode-${mode?.name ?? 'inherit'}';
  static String delegationPreferenceOption(
    String scope,
    DelegationPreference? preference,
  ) => 'delegation-$scope-preference-${preference?.name ?? 'inherit'}';
  static String agentModel(String threadId) => 'agent-model-$threadId';
  static String agentStop(String threadId) => 'agent-stop-$threadId';
  static String agentStopNote(String threadId) => 'agent-stop-note-$threadId';
  static String childInteractionCard(String interactionId) =>
      'child-interaction-card-$interactionId';
  static const shell = 'studio-shell';
  static const startPage = 'studio-start-page';
  static const threadPreparation = 'thread-preparation';
  static const threadPreparationDetails = 'thread-preparation-details';
  static String threadPreparationStage(ThreadPreparationStage stage) =>
      'thread-preparation-${stage.name}';
  static const newSession = 'sidebar-new-session';
  static const nonProjectSessionsArea = 'sidebar-non-project-sessions';
  static const sidebarUpdateNow = 'sidebar-update-now';
  static const standalonePreparationFailure = 'standalone-preparation-failure';
  static const standalonePreparationFailureMessage =
      'standalone-preparation-failure-message';
  static const standalonePreparationRetry = 'standalone-preparation-retry';
  static String projectNewSession(String workspaceId) =>
      'project-new-session-$workspaceId';
  static String threadRow(String id) => 'thread-row-$id';
  static String deleteThread(String id) => 'thread-delete-$id';
  static String deleteThreadDialog(String id) => 'thread-delete-dialog-$id';
  static String deleteThreadConfirm(String id) => 'thread-delete-confirm-$id';
  static const sidebarResize = 'sidebar-resize';
  static const rightSidebar = 'conversation-right-sidebar';
  static const rightSidebarResizeHandle = 'conversation-right-sidebar-resize';
  static const rightSidebarExpandMode =
      'conversation-right-sidebar-expand-mode';
  static const rightSidebarCollapse = 'conversation-right-sidebar-collapse';
  static const rightSidebarToggle = 'conversation-right-sidebar-toggle';
  static const rightSidebarOverlayScrim = 'conversation-right-sidebar-scrim';
  static const rightSidebarFileClose = 'conversation-right-sidebar-file-close';
  static String rightSidebarTab(String kind) =>
      'conversation-right-sidebar-tab-$kind';
  static const settingsBack = 'settings-back';
  static const sessionMode = 'session-mode-selector';
  static const sessionModeLabel = 'session-mode-label';
  static const startPageSelectors = 'start-page-selectors';
  static const reasoningEffort = 'reasoning-effort-selector';
  static const reasoningEffortLabel = 'reasoning-effort-label';

  /// 主输入区在中断、清理与阻塞态下的稳定入口。
  static const composerContinue = 'composer-continue';
  static const composerStopping = 'composer-stopping';
  static const composerContinuing = 'composer-continuing';
  static const composerBlocker = 'composer-blocker';

  /// 子会话详情的只读说明（没有任何输入、停止、答题或审批控件）。
  static const agentReadOnlyPanel = 'agent-readonly-panel';

  static String sessionModeOption(String mode) => 'session-mode-$mode';

  static String reasoningEffortOption(String effort) =>
      'reasoning-effort-$effort';

  /// Timeline 的稳定操作与详情入口（canonical item + typed field 寻址）。
  static const timelineScrollable = 'timeline-scrollable';
  static const timelineLoadingOlder = 'timeline-loading-older';
  static const timelineRetryOlder = 'timeline-retry-older';
  static const timelineReturnLatest = 'timeline-return-latest';
  static const timelineConnectionNotice = 'timeline-connection-notice';
  static const timelineRetryConnection = 'timeline-retry-connection';

  static String timelineRow(String id) => 'timeline-row-$id';
  static String timelineContentOpen(String id, String key) =>
      'timeline-content-open:${jsonEncode([id, key])}';
  static String timelineContentWindow(String id, String key) =>
      'timeline-content-window:${jsonEncode([id, key])}';
  static String timelineContentCopyWindow(String id, String key) =>
      'timeline-content-copy-window:${jsonEncode([id, key])}';
  static String timelineContentNextWindow(String id, String key) =>
      'timeline-content-next-window:${jsonEncode([id, key])}';
}
