import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'studio_driver_key_values.dart';

abstract final class StudioDriverKeys {
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
  static const timelineReturnLive = ValueKey<String>(
    StudioDriverKeyValues.timelineReturnLive,
  );
  static const timelineNewOutput = ValueKey<String>(
    StudioDriverKeyValues.timelineNewOutput,
  );

  /// 全文查看器：只在用户显式打开后存在，按 canonical item + typed field 打开。
  static const timelineDetailDialog = ValueKey<String>(
    StudioDriverKeyValues.timelineDetailDialog,
  );
  static const timelineDetailText = ValueKey<String>(
    StudioDriverKeyValues.timelineDetailText,
  );
  static const timelineDetailCopy = ValueKey<String>(
    StudioDriverKeyValues.timelineDetailCopy,
  );
  static const timelineDetailClose = ValueKey<String>(
    StudioDriverKeyValues.timelineDetailClose,
  );
  static const timelineDetailRetry = ValueKey<String>(
    StudioDriverKeyValues.timelineDetailRetry,
  );
  static const timelineDetailTerminal = ValueKey<String>(
    StudioDriverKeyValues.timelineDetailTerminal,
  );
  static const timelineConnectionNotice = ValueKey<String>(
    StudioDriverKeyValues.timelineConnectionNotice,
  );
  static const timelineRetryConnection = ValueKey<String>(
    StudioDriverKeyValues.timelineRetryConnection,
  );
  static ValueKey<String> timelineDetailOpen(String id, String field) =>
      ValueKey<String>(StudioDriverKeyValues.timelineDetailOpen(id, field));
  static ValueKey<String> parentAgentLabel(String id) =>
      ValueKey<String>('timeline-parent-agent-label-$id');
  static const workspaceFooterScroll = ValueKey<String>(
    'workspace-footer-scrollable',
  );
  static const newSession = ValueKey<String>(StudioDriverKeyValues.newSession);
  static const openProject = ValueKey<String>('sidebar-open-project');
  static const projectPathDialog = ValueKey<String>('project-path-dialog');
  static const projectPathInput = ValueKey<String>('project-path-input');
  static const projectPathSubmit = ValueKey<String>('project-path-submit');
  static const settingsOpen = ValueKey<String>('settings-open');
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
  static const mcpResetAllConfirm = ValueKey<String>('mcp-reset-all-confirm');
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
  static const addProjectSourceLocal = ValueKey<String>(
    'add-project-source-local',
  );
  static const addProjectSourceRemote = ValueKey<String>(
    'add-project-source-remote',
  );
  static const addProjectContinue = ValueKey<String>('add-project-continue');
  static const addProjectNewConnection = ValueKey<String>(
    'add-project-new-connection',
  );
  static const addProjectConnect = ValueKey<String>('add-project-connect');
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
  static const statisticsFilter = ValueKey<String>('statistics-filter');
  static const statisticsEffortFilter = ValueKey<String>(
    'statistics-effort-filter',
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

  /// 组内 effort 细分行；`null` 与显式 `none` 由元组编码区分。
  static ValueKey<String> statisticsSummaryEffortRow(
    String accountId,
    String modelId,
    String? effort,
  ) => ValueKey<String>(
    'statistics-summary-effort-row:${jsonEncode(<Object?>[accountId, modelId, effort])}',
  );

  static ValueKey<String> statisticsHistoryRow(
    String accountId,
    String modelId,
    String? effort,
    int sampleIndex,
  ) => ValueKey<String>(
    'statistics-history-row:${jsonEncode(<Object?>[accountId, modelId, effort, sampleIndex])}',
  );
  static const accountEditor = ValueKey<String>('account-editor');
  static const accountEdit = ValueKey<String>('account-edit');
  static const accountSave = ValueKey<String>('account-save');
  static const accountPricing = ValueKey<String>('account-pricing');
  static const accountEditorScroll = ValueKey<String>('account-editor-scroll');
  static const accountAdd = ValueKey<String>('account-add');
  static const accountTemplate = ValueKey<String>('account-template');
  static const accountBaseUrl = ValueKey<String>('account-base-url');
  static const accountApiKey = ValueKey<String>('account-api-key');
  static const accountModelAdd = ValueKey<String>('account-model-add');
  static ValueKey<String> accountManualModelDelete(
    String accountId,
    String modelId,
  ) => ValueKey<String>('settings.account.$accountId.model.$modelId.delete');
  static const accountManualModelDeleteConfirm = ValueKey<String>(
    'settings.account.model.delete.confirm',
  );
  static ValueKey<String> customModelId(int index) =>
      ValueKey<String>('account-model-$index-id');
  static ValueKey<String> customModelAdvanced(int index) =>
      ValueKey<String>('account-model-$index-advanced');
  static ValueKey<String> customModelDisplayName(int index) =>
      ValueKey<String>('account-model-$index-display-name');
  static const accountCancel = ValueKey<String>('account-cancel');
  static const toolApprove = ValueKey<String>('tool-approve');
  static const toolDeny = ValueKey<String>('tool-deny');
  static const userInputSubmit = ValueKey<String>('user-input-submit');
  static const planSummary = ValueKey<String>('plan-summary');
  static const statusPlanEntry = ValueKey<String>('status-plan-entry');
  static const planDetails = ValueKey<String>('plan-details');
  static const planDetailsScroll = ValueKey<String>('plan-details-scroll');
  static const planDetailsClose = ValueKey<String>('plan-details-close');
  static const planResizeHandle = ValueKey<String>('plan-resize-handle');
  static const planFeedbackInput = ValueKey<String>('plan-feedback-input');
  static const planSubmitRevision = ValueKey<String>('plan-submit-revision');
  static const planApprove = ValueKey<String>('plan-approve');
  static const planFeedbackError = ValueKey<String>('plan-feedback-error');
  static const planDetailsReadingMode = ValueKey<String>(
    'plan-details-reading-mode',
  );
  static const planDetailsStatus = ValueKey<String>('plan-details-status');
  static const planDetailsTitle = ValueKey<String>('plan-details-title');
  static const planDetailsMarkdown = ValueKey<String>('plan-details-markdown');
  static ValueKey<String> timelinePlanReceipt(String id) =>
      ValueKey<String>('timeline-plan-receipt-$id');
  static ValueKey<String> timelinePlanReceiptReply(String id) =>
      ValueKey<String>('timeline-plan-receipt-reply-$id');
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
  static const botsStartTime = ValueKey<String>('bots-start-time');
  static const botsEndTime = ValueKey<String>('bots-end-time');
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
  static const botsProject = ValueKey<String>('bots-project');
  static const botsAppId = ValueKey<String>('bots-app-id');
  static const botsSecret = ValueKey<String>('bots-secret');
  static const botsSend = ValueKey<String>('bots-send');
  static const botsSendInput = ValueKey<String>('bots-send-input');
  static const botsOpenConsole = ValueKey<String>('bots-open-console');
  static const botsOpenConsoleManual = ValueKey<String>(
    'bots-open-console-manual',
  );
  static const botsFactConfig = ValueKey<String>('bots-fact-config');
  static const botsFactConnection = ValueKey<String>('bots-fact-connection');
  static const botsFactAuth = ValueKey<String>('bots-fact-auth');
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

  static ValueKey<String> threadRow(String id) =>
      ValueKey<String>('thread-row-$id');

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

  /// 输入框上方的固定活动条与其展开详情。
  static const ValueKey<String> conversationActivity = ValueKey<String>(
    'conversation-activity',
  );
  static const ValueKey<String> conversationActivityDetails = ValueKey<String>(
    'conversation-activity-details',
  );

  static ValueKey<String> timelineRolledBack(String id) =>
      ValueKey<String>('timeline-rolled-back-$id');

  static ValueKey<String> timelineBlock(String id) =>
      ValueKey<String>('timeline-block-$id');

  static ValueKey<String> timelineSkillActivation(String id) =>
      ValueKey<String>('timeline-skill-activation-$id');

  /// 页面只返回预览的超大条目：按 identity 回源完整正文的入口。
  static ValueKey<String> timelineItemBodyNotice(String id) =>
      ValueKey<String>('timeline-item-body-notice-$id');
  static ValueKey<String> timelineItemBodyLoad(String id) =>
      ValueKey<String>('timeline-item-body-load-$id');
  static ValueKey<String> timelineItemBodyRetry(String id) =>
      ValueKey<String>('timeline-item-body-retry-$id');

  /// 持久化队列压力诊断块（状态/history/calls 水位、字节、年龄、压力、错误）。
  static const persistenceQueueDiagnostics = ValueKey<String>(
    'persistence-queue-diagnostics',
  );
  static const persistenceQueueRefresh = ValueKey<String>(
    'persistence-queue-refresh',
  );

  static ValueKey<String> statusActiveSkill(String name) =>
      ValueKey<String>('status-active-skill-$name');

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

  static ValueKey<String> historyAttachment(String id) =>
      ValueKey<String>('history-attachment-$id');

  static ValueKey<String> timelineActivitySummary(String id) =>
      ValueKey<String>('timeline-activity-summary-$id');

  /// 只读问答回执的折叠头部：点击即展开/收起，折叠与展开状态下都指向同一条目身份。
  static ValueKey<String> timelineUserInput(String id) =>
      ValueKey<String>('timeline-user-input-$id');

  /// 问答回执的展开内容；是否存在该键即代表当前是否展开。
  static ValueKey<String> timelineUserInputDetails(String id) =>
      ValueKey<String>('timeline-user-input-details-$id');

  /// 回执里一题的标题与问题正文；序号是原问题顺序，不是文本身份。
  static ValueKey<String> timelineUserInputQuestion(String id, int index) =>
      ValueKey<String>('timeline-user-input-question-$id-$index');

  /// 回执里一题的答案正文。
  static ValueKey<String> timelineUserInputAnswer(String id, int index) =>
      ValueKey<String>('timeline-user-input-answer-$id-$index');

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
  /// 的 toggle/thumbnail/dialog key 必须叠加调用身份。Driver 与 Widget 均使用该公式，
  /// 保证两侧选中的是同一条目。调用 id 取工具 callId（缺失时实现回退 toolCallId）；
  /// 同一调用结果内重复引用同一资源时实现会追加 `#<序号>`。
  static String toolImageEntryId(String callId, String attachmentId) =>
      '$callId:$attachmentId';

  static ValueKey<String> viewImageToggle(String id) =>
      ValueKey<String>('view-image-toggle-$id');

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

  static ValueKey<String> toolImageGallery(String groupId) =>
      ValueKey<String>('tool-image-gallery-$groupId');

  /// 展示工具图片卡片：卡片本身、成功加载的图片与失败重试入口。
  ///
  /// `entryId` 沿用 [toolImageEntryId] 的 owning 调用 + 附件身份公式，因此同一资源被
  /// 不同调用展示时仍各自拥有独立的卡片身份。
  static ValueKey<String> imageCard(String entryId) =>
      ValueKey<String>('image-card-$entryId');

  static ValueKey<String> imageCardImage(String entryId) =>
      ValueKey<String>('image-card-image-$entryId');

  static ValueKey<String> imageCardRetry(String entryId) =>
      ValueKey<String>('image-card-retry-$entryId');

  static ValueKey<String> markdownImageSource(String url) =>
      ValueKey<String>('markdown-image-source-$url');

  static ValueKey<String> markdownImageThumbnail(String url) =>
      ValueKey<String>('markdown-image-thumbnail-$url');

  static ValueKey<String> markdownImageDialog(String url) =>
      ValueKey<String>('markdown-image-dialog-$url');

  static ValueKey<String> reasoningEffortOption(String effort) =>
      ValueKey<String>(StudioDriverKeyValues.reasoningEffortOption(effort));

  static ValueKey<String> mcpResetServer(String serverId) =>
      ValueKey<String>('mcp-reset-$serverId');

  static ValueKey<String> mcpServerRow(String serverId) =>
      ValueKey<String>('mcp-server-$serverId');

  static ValueKey<String> mcpServerError(String serverId) =>
      ValueKey<String>('mcp-server-error-$serverId');

  static ValueKey<String> lspRepairServer(String serverId) =>
      ValueKey<String>('lsp-repair-$serverId');

  static ValueKey<String> lspResetServer(String serverId) =>
      ValueKey<String>('lsp-reset-$serverId');

  static ValueKey<String> lspActivity() =>
      const ValueKey<String>('lsp-activity');

  static ValueKey<String> lspActivityDetail() =>
      const ValueKey<String>('lsp-activity-detail');

  static ValueKey<String> lspActivityOverflow() =>
      const ValueKey<String>('lsp-activity-overflow');

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

  static ValueKey<String> accountRow(String id) =>
      ValueKey<String>('account-row-$id');

  static ValueKey<String> accountConnectionMode(String accountId) =>
      ValueKey<String>('account-$accountId-connection-mode');

  static ValueKey<String> accountConnectionModeOption(
    String accountId,
    String mode,
  ) => ValueKey<String>('account-$accountId-connection-mode-$mode');

  static ValueKey<String> accountModelConnectionMode(
    String accountId,
    String model,
  ) => ValueKey<String>('account-$accountId-model-$model-connection-mode');

  static ValueKey<String> accountModelConnectionModeOption(
    String accountId,
    String model,
    String mode,
  ) =>
      ValueKey<String>('account-$accountId-model-$model-connection-mode-$mode');

  static ValueKey<String> accountModelAutoCompactInput(
    String accountId,
    String model,
  ) => ValueKey<String>('account-$accountId-model-$model-auto-compact-input');

  static ValueKey<String> accountModelAutoCompactReset(
    String accountId,
    String model,
  ) => ValueKey<String>('account-$accountId-model-$model-auto-compact-reset');
}
