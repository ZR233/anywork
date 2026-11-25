import 'dart:convert';

import 'package:anywork_client/models.dart';

import 'package:flutter/foundation.dart';

import 'studio_driver_key_values.dart';

abstract final class StudioDriverKeys {
  static const sessionSettings = ValueKey(
    StudioDriverKeyValues.sessionSettings,
  );
  static const defaultDelegationMode = ValueKey(
    StudioDriverKeyValues.defaultDelegationMode,
  );
  static const defaultDelegationPreference = ValueKey(
    StudioDriverKeyValues.defaultDelegationPreference,
  );
  static const draftDelegationMode = ValueKey(
    StudioDriverKeyValues.draftDelegationMode,
  );
  static const draftDelegationPreference = ValueKey(
    StudioDriverKeyValues.draftDelegationPreference,
  );
  static ValueKey<String> delegationModeOption(
    String scope,
    DelegationMode? mode,
  ) => ValueKey(StudioDriverKeyValues.delegationModeOption(scope, mode));
  static ValueKey<String> delegationPreferenceOption(
    String scope,
    DelegationPreference? preference,
  ) => ValueKey(
    StudioDriverKeyValues.delegationPreferenceOption(scope, preference),
  );
  static ValueKey<String> agentModel(String threadId) =>
      ValueKey(StudioDriverKeyValues.agentModel(threadId));
  static const shell = ValueKey<String>(StudioDriverKeyValues.shell);
  static const startPage = ValueKey<String>(StudioDriverKeyValues.startPage);
  static const threadPreparation = ValueKey<String>(
    StudioDriverKeyValues.threadPreparation,
  );
  static const threadPreparationDetails = ValueKey<String>(
    StudioDriverKeyValues.threadPreparationDetails,
  );

  /// 已选中但尚未打开的会话占位；首屏恢复的选择不自动打开会话（§6.1）。
  static const unopenedThread = ValueKey<String>('studio-unopened-thread');

  /// 未打开会话的显式打开入口（与具体 thread id 无关，便于驱动/测试定位）。
  static const openSelectedThread = ValueKey<String>(
    'studio-open-selected-thread',
  );
  static ValueKey<String> openThread(String id) =>
      ValueKey<String>('studio-open-thread-$id');
  static const sidebar = ValueKey<String>('studio-sidebar');
  static const sidebarResize = ValueKey<String>(
    StudioDriverKeyValues.sidebarResize,
  );
  static const timeline = ValueKey<String>(
    StudioDriverKeyValues.timelineScrollable,
  );
  static ValueKey<String> timelineRow(String id) =>
      ValueKey<String>(StudioDriverKeyValues.timelineRow(id));

  /// 分页与回到实时的稳定操作入口。
  static const timelineLoadingOlder = ValueKey<String>(
    StudioDriverKeyValues.timelineLoadingOlder,
  );
  static const timelineRetryOlder = ValueKey<String>(
    StudioDriverKeyValues.timelineRetryOlder,
  );
  static const timelineReturnLatest = ValueKey<String>(
    StudioDriverKeyValues.timelineReturnLatest,
  );

  static const timelineConnectionNotice = ValueKey<String>(
    StudioDriverKeyValues.timelineConnectionNotice,
  );
  static const timelineRetryConnection = ValueKey<String>(
    StudioDriverKeyValues.timelineRetryConnection,
  );
  static ValueKey<String> timelineContentOpen(String id, String key) =>
      ValueKey<String>(StudioDriverKeyValues.timelineContentOpen(id, key));
  static ValueKey<String> timelineContentWindow(String id, String key) =>
      ValueKey<String>(StudioDriverKeyValues.timelineContentWindow(id, key));
  static ValueKey<String> timelineContentCopyWindow(String id, String key) =>
      ValueKey<String>(
        StudioDriverKeyValues.timelineContentCopyWindow(id, key),
      );
  static ValueKey<String> timelineContentNextWindow(String id, String key) =>
      ValueKey<String>(
        StudioDriverKeyValues.timelineContentNextWindow(id, key),
      );
  static ValueKey<String> parentAgentLabel(String id) =>
      ValueKey<String>('timeline-parent-agent-label-$id');
  static const workspaceFooterScroll = ValueKey<String>(
    'workspace-footer-scrollable',
  );
  static const newSession = ValueKey<String>(StudioDriverKeyValues.newSession);
  static const nonProjectSessionsArea = ValueKey<String>(
    StudioDriverKeyValues.nonProjectSessionsArea,
  );
  static const standalonePreparationFailure = ValueKey<String>(
    StudioDriverKeyValues.standalonePreparationFailure,
  );
  static const standalonePreparationFailureMessage = ValueKey<String>(
    StudioDriverKeyValues.standalonePreparationFailureMessage,
  );
  static const standalonePreparationRetry = ValueKey<String>(
    StudioDriverKeyValues.standalonePreparationRetry,
  );
  static const openProject = ValueKey<String>('sidebar-open-project');
  static const settingsOpen = ValueKey<String>('settings-open');
  static const sidebarUpdateNow = ValueKey<String>(
    StudioDriverKeyValues.sidebarUpdateNow,
  );
  static const settingsPage = ValueKey<String>('settings-page');
  static const settingsBack = ValueKey<String>(
    StudioDriverKeyValues.settingsBack,
  );
  static const sessionMode = ValueKey<String>(
    StudioDriverKeyValues.sessionMode,
  );

  /// 触发器自身的展示文案。驱动脚本按此键读取文案，避免把菜单浮层里的行文本误当成
  /// 触发器值（浮层挂在触发器作用域下）。
  static const sessionModeLabel = ValueKey<String>(
    StudioDriverKeyValues.sessionModeLabel,
  );
  static const sessionWorkspaceMode = ValueKey<String>(
    'session-workspace-mode-selector',
  );
  static const startPageSelectors = ValueKey<String>(
    StudioDriverKeyValues.startPageSelectors,
  );
  static const model = ValueKey<String>('model-selector');
  static const reasoningEffort = ValueKey<String>(
    StudioDriverKeyValues.reasoningEffort,
  );
  static const reasoningEffortLabel = ValueKey<String>(
    StudioDriverKeyValues.reasoningEffortLabel,
  );
  static const accountUsageCheck = ValueKey<String>('account-usage-check');
  static const skillsDiscover = ValueKey<String>('skills-discover');
  static const mcpRefresh = ValueKey<String>('mcp-refresh');
  static const mcpResetAll = ValueKey<String>('mcp-reset-all');
  static const lspRefresh = ValueKey<String>('lsp-refresh');
  static const lspProbe = ValueKey<String>('lsp-probe');
  static const lspResetWorkspace = ValueKey<String>('lsp-reset-workspace');
  static const sshAddServer = ValueKey<String>('ssh-add-server');
  static const sshServerDialog = ValueKey<String>('ssh-server-dialog');
  static const sshServerAliasInput = ValueKey<String>('ssh-server-alias-input');
  static const sshServerHostInput = ValueKey<String>('ssh-server-host-input');
  static const sshServerUsernameInput = ValueKey<String>(
    'ssh-server-username-input',
  );
  static const sshServerPortInput = ValueKey<String>('ssh-server-port-input');
  static const sshServerIdentityInput = ValueKey<String>(
    'ssh-server-identity-input',
  );
  static const sshServerPasswordInput = ValueKey<String>(
    'ssh-server-password-input',
  );
  static const sshServerPasswordClear = ValueKey<String>(
    'ssh-server-password-clear',
  );
  static const sshServerValidationError = ValueKey<String>(
    'ssh-server-validation-error',
  );
  static const sshServerSave = ValueKey<String>('ssh-server-save');
  static const sshPasswordPromptDialog = ValueKey<String>(
    'ssh-password-prompt-dialog',
  );
  static const sshPasswordPromptInput = ValueKey<String>(
    'ssh-password-prompt-input',
  );
  static const sshPasswordPromptRemember = ValueKey<String>(
    'ssh-password-prompt-remember',
  );
  static const sshPasswordPromptSubmit = ValueKey<String>(
    'ssh-password-prompt-submit',
  );
  static const sshDeleteConfirm = ValueKey<String>('ssh-delete-confirm');
  static const addProjectContinue = ValueKey<String>('add-project-continue');
  static const addProjectNewConnection = ValueKey<String>(
    'add-project-new-connection',
  );
  static const sshDirectoryDialog = ValueKey<String>('ssh-directory-dialog');
  static const sshDirectoryList = ValueKey<String>('ssh-directory-list');
  static const sshOpenCurrentDirectory = ValueKey<String>(
    'ssh-open-current-directory',
  );
  static const sshDirectoryPathInput = ValueKey<String>(
    'ssh-directory-path-input',
  );
  static const sshDirectoryGo = ValueKey<String>('ssh-directory-go');
  static const sshDirectoryError = ValueKey<String>('ssh-directory-error');
  static const sshDirectoryEmpty = ValueKey<String>('ssh-directory-empty');
  static const sshDirectoryUp = ValueKey<String>('ssh-directory-up');
  static const composerInput = ValueKey<String>('composer-input');
  static const composerSubmit = ValueKey<String>('composer-submit');
  static const composerStop = ValueKey<String>('composer-stop');
  static const composerPending = ValueKey<String>('composer-pending');
  static const composerError = ValueKey<String>('composer-error');

  /// 中断与清理态的主按钮，以及类型化阻塞说明。
  static const composerContinue = ValueKey<String>(
    StudioDriverKeyValues.composerContinue,
  );
  static const composerStopping = ValueKey<String>(
    StudioDriverKeyValues.composerStopping,
  );
  static const composerContinuing = ValueKey<String>(
    StudioDriverKeyValues.composerContinuing,
  );
  static const composerBlocker = ValueKey<String>(
    StudioDriverKeyValues.composerBlocker,
  );

  /// 子会话详情的只读说明；它取代原来的子会话停止入口。
  static const agentReadOnlyPanel = ValueKey<String>(
    StudioDriverKeyValues.agentReadOnlyPanel,
  );

  /// 智能体列表行内的独立停止入口与等待调度说明。
  static ValueKey<String> agentStop(String threadId) =>
      ValueKey(StudioDriverKeyValues.agentStop(threadId));
  static ValueKey<String> agentStopNote(String threadId) =>
      ValueKey(StudioDriverKeyValues.agentStopNote(threadId));

  /// 主会话里的子任务待决交互卡片。
  static ValueKey<String> childInteractionCard(String interactionId) =>
      ValueKey(StudioDriverKeyValues.childInteractionCard(interactionId));

  static const attachmentEntry = ValueKey<String>('composer-attachment-entry');
  static const attachmentLocal = ValueKey<String>('composer-attachment-local');
  static const attachmentUrl = ValueKey<String>('composer-attachment-url');
  static const attachmentUrlDialog = ValueKey<String>('attachment-url-dialog');
  static const attachmentUrlInput = ValueKey<String>('attachment-url-input');
  static const attachmentUrlSubmit = ValueKey<String>('attachment-url-submit');
  static const attachmentDraftRail = ValueKey<String>('attachment-draft-rail');
  static const agentSwitcher = ValueKey<String>('agent-switcher');
  static const sessionCost = ValueKey<String>('session-cost');
  static const sessionOpenWorkspaceMenu = ValueKey<String>(
    'session-open-workspace-menu',
  );
  static const sessionOpenWorkspaceVsCode = ValueKey<String>(
    'session-open-workspace-vscode',
  );
  static const sessionOpenWorkspaceZed = ValueKey<String>(
    'session-open-workspace-zed',
  );
  static const sessionOpenWorkspaceTerminal = ValueKey<String>(
    'session-open-workspace-terminal',
  );
  static const threadThroughput = ValueKey<String>('thread-throughput');
  static const statisticsSummary = ValueKey<String>('statistics-summary');
  static const statisticsHistory = ValueKey<String>('statistics-history');
  static const statisticsRefresh = ValueKey<String>('statistics-refresh');
  static const statisticsPreviousPage = ValueKey<String>(
    'statistics-previous-page',
  );
  static const statisticsNextPage = ValueKey<String>('statistics-next-page');
  static const statisticsPageNumber = ValueKey<String>(
    'statistics-page-number',
  );
  static const statisticsFilter = ValueKey<String>('statistics-filter');
  static const statisticsEffortFilter = ValueKey<String>(
    'statistics-effort-filter',
  );
  static const statisticsServiceTierFilter = ValueKey<String>(
    'statistics-service-tier-filter',
  );
  static const statisticsMismatchOnly = ValueKey<String>(
    'statistics-mismatch-only',
  );

  /// 顶层汇总身份 (accountId, 配置 modelId)；effort 是组内细分，不进入顶层 key。
  static ValueKey<String> statisticsSummaryRow(
    String accountId,
    String modelId,
  ) => ValueKey<String>(
    'statistics-summary-row:${jsonEncode(<Object?>[accountId, modelId])}',
  );

  /// 组内请求组合；未记录档位保留既有 key，已记录档位加入复合身份。
  static ValueKey<String> statisticsSummaryEffortRow(
    String accountId,
    String modelId,
    String? effort, {
    String? requestedServiceTier,
  }) => ValueKey<String>(
    'statistics-summary-effort-row:${jsonEncode(<Object?>[accountId, modelId, effort, ?requestedServiceTier])}',
  );

  static ValueKey<String> statisticsHistoryCall(String callKey) =>
      ValueKey<String>('statistics-history-call:$callKey');
  static const accountEdit = ValueKey<String>('account-edit');
  static const accountSave = ValueKey<String>('account-save');
  static const accountAdd = ValueKey<String>('account-add');
  static const accountModelAdd = ValueKey<String>('account-model-add');
  static const accountCancel = ValueKey<String>('account-cancel');

  static const toolApprove = ValueKey<String>('tool-approve');
  static const toolDeny = ValueKey<String>('tool-deny');
  static const userInputSubmit = ValueKey<String>('user-input-submit');
  static const planSummary = ValueKey<String>('plan-summary');
  static const statusPlanEntry = ValueKey<String>('status-plan-entry');
  static const planDetails = ValueKey<String>('plan-details');
  static const planDetailsScroll = ValueKey<String>('plan-details-scroll');
  static const planFeedbackInput = ValueKey<String>('plan-feedback-input');
  static const planSubmitRevision = ValueKey<String>('plan-submit-revision');
  static const planApprove = ValueKey<String>('plan-approve');
  static const planFeedbackError = ValueKey<String>('plan-feedback-error');
  static const planDetailsStatus = ValueKey<String>('plan-details-status');
  static const planDetailsMarkdown = ValueKey<String>('plan-details-markdown');
  static const rightSidebar = ValueKey<String>(
    StudioDriverKeyValues.rightSidebar,
  );
  static const rightSidebarResizeHandle = ValueKey<String>(
    StudioDriverKeyValues.rightSidebarResizeHandle,
  );
  static const rightSidebarExpandMode = ValueKey<String>(
    StudioDriverKeyValues.rightSidebarExpandMode,
  );
  static const rightSidebarCollapse = ValueKey<String>(
    StudioDriverKeyValues.rightSidebarCollapse,
  );
  static const rightSidebarToggle = ValueKey<String>(
    StudioDriverKeyValues.rightSidebarToggle,
  );
  static const rightSidebarOverlayScrim = ValueKey<String>(
    StudioDriverKeyValues.rightSidebarOverlayScrim,
  );
  static const rightSidebarFileClose = ValueKey<String>(
    StudioDriverKeyValues.rightSidebarFileClose,
  );
  static ValueKey<String> rightSidebarTab(String kind) =>
      ValueKey<String>(StudioDriverKeyValues.rightSidebarTab(kind));
  static ValueKey<String> timelinePlanReceipt(String id) =>
      ValueKey<String>('timeline-plan-receipt-$id');
  static const userInputFirstOption = ValueKey<String>(
    'user-input-first-option',
  );
  static const userInputFirstText = ValueKey<String>('user-input-first-text');
  static const fallbackUserInput = ValueKey<String>('fallback-user-input');
  static const fallbackUserInputSubmit = ValueKey<String>(
    'fallback-user-input-submit',
  );

  static ValueKey<String> settingsTab(String id) =>
      ValueKey<String>('settings-tab-$id');

  static const botsAdd = ValueKey<String>('bots-add');
  static const botsBack = ValueKey<String>('bots-back');
  static const botsChatBack = ValueKey<String>('bots-chat-back');
  static const botsFilter = ValueKey<String>('bots-filter');
  static const botsPlatformTools = ValueKey<String>('bots-platform-tools');
  static const botsOpenFeishu = ValueKey<String>('bots-open-feishu');
  static const botsOpenVerificationBrowser = ValueKey<String>(
    'bots-open-verification-browser',
  );
  static const botsOpenChat = ValueKey<String>('bots-open-chat');
  static const botsOpenChatBrowser = ValueKey<String>('bots-open-chat-browser');
  static const botsName = ValueKey<String>('bots-name');
  static const botsRiskAck = ValueKey<String>('bots-risk-ack');
  static const botsEdit = ValueKey<String>('bots-edit');
  static const botsEnabled = ValueKey<String>('bots-enabled');
  static const botsRetry = ValueKey<String>('bots-retry');
  static const botsCancelRegistration = ValueKey<String>(
    'bots-registration-cancel',
  );
  static const botsRegistrationStatus = ValueKey<String>(
    'bots-registration-status',
  );
  static const botsConfirmNewThread = ValueKey<String>(
    'bots-confirm-new-thread',
  );
  static const botsRefreshConversations = ValueKey<String>(
    'bots-refresh-conversations',
  );
  static const botsNextConversations = ValueKey<String>(
    'bots-next-conversations',
  );
  static const botsRefreshMessages = ValueKey<String>('bots-refresh-messages');
  static const botsNextMessages = ValueKey<String>('bots-next-messages');
  static ValueKey<String> botsApproveUser(String id) =>
      ValueKey<String>('bots-approve-user-$id');
  static ValueKey<String> botsClearPairing(String id) =>
      ValueKey<String>('bots-clear-pairing-$id');
  static ValueKey<String> botsDiagnostic(String id) =>
      ValueKey<String>('bots-diagnostic-$id');
  static ValueKey<String> botsConversation(String id) =>
      ValueKey<String>('bots-conversation-$id');
  static ValueKey<String> botsConversationActions(String id) =>
      ValueKey<String>('bots-conversation-actions-$id');
  static const botsScan = ValueKey<String>('bots-scan');
  static const botsManual = ValueKey<String>('bots-manual');
  static const botsSave = ValueKey<String>('bots-save');
  static const botsAppId = ValueKey<String>('bots-app-id');
  static const botsSecret = ValueKey<String>('bots-secret');
  static const botsSend = ValueKey<String>('bots-send');
  static const botsSendInput = ValueKey<String>('bots-send-input');
  static const botsOpenConsole = ValueKey<String>('bots-open-console');
  static const botsOpenConsoleManual = ValueKey<String>(
    'bots-open-console-manual',
  );
  static ValueKey<String> botsRow(String id) =>
      ValueKey<String>('bots-row-$id');
  static ValueKey<String> botsPending(String id) =>
      ValueKey<String>('bots-pending-$id');

  static ValueKey<String> sshTest(String id) =>
      ValueKey<String>('ssh-test-$id');

  static ValueKey<String> sshReconnect(String id) =>
      ValueKey<String>('ssh-reconnect-$id');

  static ValueKey<String> sshReady(String id) =>
      ValueKey<String>('ssh-ready-$id');

  static ValueKey<String> sshOpen(String id) =>
      ValueKey<String>('ssh-open-$id');

  static ValueKey<String> sshEdit(String id) =>
      ValueKey<String>('ssh-edit-$id');

  static ValueKey<String> sshDelete(String id) =>
      ValueKey<String>('ssh-delete-$id');

  static ValueKey<String> addProjectConnectionRow(String alias) =>
      ValueKey<String>('add-project-connection-$alias');

  static ValueKey<String> addProjectConnectionEdit(String alias) =>
      ValueKey<String>('add-project-connection-edit-$alias');

  static ValueKey<String> addProjectConnectionDelete(String alias) =>
      ValueKey<String>('add-project-connection-delete-$alias');

  static ValueKey<String> sshDirectoryCurrent(String path) =>
      ValueKey<String>('ssh-directory-current-$path');

  static ValueKey<String> sshDirectoryEntry(String path) =>
      ValueKey<String>('ssh-directory-entry-$path');

  static ValueKey<String> projectRow(String id) =>
      ValueKey<String>('project-row-$id');

  static ValueKey<String> projectExpand(String id) =>
      ValueKey<String>('project-expand-$id');

  static ValueKey<String> projectMenu(String id) =>
      ValueKey<String>('project-menu-$id');

  static ValueKey<String> projectNewSession(String id) =>
      ValueKey<String>(StudioDriverKeyValues.projectNewSession(id));

  static ValueKey<String> threadRow(String id) =>
      ValueKey<String>(StudioDriverKeyValues.threadRow(id));

  static ValueKey<String> pinThread(String id) =>
      ValueKey<String>('thread-pin-$id');

  static ValueKey<String> threadMenu(String id) =>
      ValueKey<String>('thread-menu-$id');

  static ValueKey<String> copyThreadWorkspace(String id) =>
      ValueKey<String>('thread-menu-copy-workspace-$id');

  static ValueKey<String> openThreadWorkspace(String id) =>
      ValueKey<String>('thread-menu-open-workspace-$id');

  static ValueKey<String> openThreadVsCode(String id) =>
      ValueKey<String>('thread-menu-open-vscode-$id');

  static ValueKey<String> openThreadZed(String id) =>
      ValueKey<String>('thread-menu-open-zed-$id');

  static ValueKey<String> openThreadTerminal(String id) =>
      ValueKey<String>('thread-menu-open-terminal-$id');

  static ValueKey<String> archiveThread(String id) =>
      ValueKey<String>('thread-archive-$id');

  static const archiveThreadConfirm = ValueKey<String>(
    'thread-archive-confirm',
  );

  static ValueKey<String> deleteThread(String id) =>
      ValueKey<String>(StudioDriverKeyValues.deleteThread(id));

  static ValueKey<String> deleteThreadDialog(String id) =>
      ValueKey<String>(StudioDriverKeyValues.deleteThreadDialog(id));

  static ValueKey<String> deleteThreadConfirm(String id) =>
      ValueKey<String>(StudioDriverKeyValues.deleteThreadConfirm(id));

  static ValueKey<String> renameThread(String id) =>
      ValueKey<String>('thread-rename-$id');

  static ValueKey<String> renameThreadDialog(String id) =>
      ValueKey<String>('thread-rename-dialog-$id');

  static ValueKey<String> renameThreadInput(String id) =>
      ValueKey<String>('thread-rename-input-$id');

  static ValueKey<String> renameThreadSave(String id) =>
      ValueKey<String>('thread-rename-save-$id');

  static ValueKey<String> retryRecoveryIssue(String id) =>
      ValueKey<String>('recovery-retry-$id');

  /// 输入框上方的固定活动条。
  static const ValueKey<String> conversationActivity = ValueKey<String>(
    'conversation-activity',
  );

  /// 持久化队列压力诊断块（状态/history/calls 水位、字节、年龄、压力、错误）。
  static const persistenceQueueDiagnostics = ValueKey<String>(
    'persistence-queue-diagnostics',
  );
  static const persistenceQueueRefresh = ValueKey<String>(
    'persistence-queue-refresh',
  );

  static ValueKey<String> statusActiveSkill(String name) =>
      ValueKey<String>('status-active-skill-$name');

  static const statusStartedItems = ValueKey<String>('status-started-items');

  static ValueKey<String> statusLspServer(String id) =>
      ValueKey<String>('status-lsp-server-$id');

  static ValueKey<String> sessionModeOption(String mode) =>
      ValueKey<String>(StudioDriverKeyValues.sessionModeOption(mode));

  static ValueKey<String> sessionWorkspaceModeOption(String mode) =>
      ValueKey<String>('session-workspace-mode-$mode');

  /// Sidebar session-row workspace-mode marker; present only for `worktree`.
  static ValueKey<String> threadWorkspaceMode(String id) =>
      ValueKey<String>('thread-workspace-mode-$id');

  static ValueKey<String> settingsRoleModel(String role) =>
      ValueKey<String>('settings-role-$role-model');

  static ValueKey<String> settingsRoleModelOption(
    String role,
    String accountId,
    String model,
  ) => ValueKey<String>(
    'settings-role-${jsonEncode(<String>[role, accountId, model])}',
  );

  static ValueKey<String> modelOption(String accountId, String model) =>
      ValueKey<String>('model-${jsonEncode(<String>[accountId, model])}');

  static ValueKey<String> modelCapabilityTags(String accountId, String model) =>
      ValueKey<String>(
        'model-${jsonEncode(<String>[accountId, model])}-capabilities',
      );

  static ValueKey<String> attachmentDraft(String id) =>
      ValueKey<String>('attachment-draft-$id');

  static ValueKey<String> attachmentRemove(String id) =>
      ValueKey<String>('attachment-remove-$id');

  static ValueKey<String> attachmentModality(String id) =>
      ValueKey<String>('attachment-modality-$id');

  /// 只读问答回执的折叠头部：点击即展开/收起，折叠与展开状态下都指向同一条目身份。
  static ValueKey<String> timelineUserInput(String id) =>
      ValueKey<String>('timeline-user-input-$id');

  /// Wait/sleep card, expanded details and secondary diagnostics.
  static ValueKey<String> waitingCard(String itemId) =>
      ValueKey<String>('wait-card:$itemId');
  static ValueKey<String> waitingDetails(String itemId) =>
      ValueKey<String>('wait-details:$itemId');
  static ValueKey<String> waitingDiagnostics(String itemId) =>
      ValueKey<String>('wait-diagnostics:$itemId');

  static ValueKey<String> viewImageTool(String callId) =>
      ValueKey<String>('view-image-tool-$callId');

  /// 工具图片条目的稳定唯一身份：owning 调用 id + 附件 id。
  ///
  /// 资源 id 内容寻址，同一工具组内不同调用读取同一图片会得到相同附件 id，因此条目
  /// 的 thumbnail/dialog key 必须叠加调用身份。测试与 Widget 均使用该公式，保证选中
  /// 的是同一条目。调用 id 取工具 callId（缺失时实现回退 toolCallId）；同一调用结果
  /// 内重复引用同一资源时实现会追加 `#<序号>`。
  static String toolImageEntryId(String callId, String attachmentId) =>
      '$callId:$attachmentId';

  static ValueKey<String> viewImageThumbnail(String id) =>
      ValueKey<String>('view-image-thumbnail-$id');

  static ValueKey<String> viewImageDialog(String id) =>
      ValueKey<String>('view-image-dialog-$id');

  static ValueKey<String> timelineImageDialog(String id) =>
      ValueKey<String>('timeline-image-dialog-$id');

  static ValueKey<String> timelineImageRetry(String id) =>
      ValueKey<String>('timeline-image-retry-$id');

  static const ValueKey<String> timelineImageClose = ValueKey<String>(
    'timeline-image-close',
  );

  static ValueKey<String> reasoningEffortOption(String effort) =>
      ValueKey<String>(StudioDriverKeyValues.reasoningEffortOption(effort));

  static ValueKey<String> mcpResetServer(String serverId) =>
      ValueKey<String>('mcp-reset-$serverId');

  static ValueKey<String> mcpServerRow(String serverId) =>
      ValueKey<String>('mcp-server-$serverId');

  static ValueKey<String> mcpServerError(String serverId) =>
      ValueKey<String>('mcp-server-error-$serverId');

  static ValueKey<String> lspResetServer(String serverId) =>
      ValueKey<String>('lsp-reset-$serverId');

  static ValueKey<String> compactContext() =>
      const ValueKey<String>('studio-compact-context');

  static ValueKey<String> contextUsage() =>
      const ValueKey<String>('context-usage');

  static ValueKey<String> contextUsageDetail() =>
      const ValueKey<String>('context-usage-detail');

  static ValueKey<String> settingsRoleEffort(String role) =>
      ValueKey<String>('settings-role-$role-effort');

  static ValueKey<String> settingsRoleEffortOption(
    String role,
    String effort,
  ) => ValueKey<String>('settings-role-$role-effort-$effort');

  static ValueKey<String> userInputOption(String questionId, int optionIndex) =>
      ValueKey<String>('user-input-option-$questionId-$optionIndex');

  static ValueKey<String> userInputText(String questionId) =>
      ValueKey<String>('user-input-text-$questionId');

  static ValueKey<String> agentRow(String id) =>
      ValueKey<String>('agent-thread-$id');

  static ValueKey<String> agentTaskSummary(String id) =>
      ValueKey<String>('agent-task-summary-$id');
}
