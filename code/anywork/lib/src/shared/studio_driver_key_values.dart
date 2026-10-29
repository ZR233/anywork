/// 驱动与验收脚本使用的键值字符串。
///
/// 本文件**只依赖 Dart**：宿主机侧 driver 脚本（`test_driver/*.dart`）在纯 Dart VM
/// 中编译，任何 `package:flutter` 依赖都会因为缺少 `dart:ui` 而编译失败。Flutter 侧
/// 的 `StudioDriverKeys` 从同一常量构造 `ValueKey`，因此键值只有这一份事实源；
/// driver 脚本需要新的键时，把字符串加进这里并在 `StudioDriverKeys` 中引用。
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
  static String modelEnabled(String accountId, String modelId) =>
      'account-model-enabled:${jsonEncode([accountId, modelId])}';
  static String modelDetails(String accountId, String modelId) =>
      'account-model-details:${jsonEncode([accountId, modelId])}';
  static String accountBillingKind(String accountId) =>
      'account-billing-kind:${jsonEncode(accountId)}';
  static String billingKindOption(BillingKind? kind) =>
      'account-billing-kind-${kind?.name ?? 'automatic'}';
  static const modelDetailDialog = 'model-detail-dialog';
  static const modelDetailClose = 'model-detail-close';
  static const modelDetailReload = 'model-detail-reload';
  static const modelDetailEvaluations = 'model-detail-evaluations';
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
  static const sidebarResize = 'sidebar-resize';
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
  static const timelineReturnLive = 'timeline-return-live';
  static const timelineNewOutput = 'timeline-new-output';
  static const timelineDetailDialog = 'timeline-detail-dialog';
  static const timelineDetailText = 'timeline-detail-text';
  static const timelineDetailCopy = 'timeline-detail-copy';
  static const timelineDetailClose = 'timeline-detail-close';
  static const timelineDetailRetry = 'timeline-detail-retry';
  static const timelineDetailTerminal = 'timeline-detail-terminal';
  static const timelineConnectionNotice = 'timeline-connection-notice';
  static const timelineRetryConnection = 'timeline-retry-connection';

  static String timelineRow(String id) => 'timeline-row-$id';
  static String timelineDetailOpen(String id, String field) =>
      'timeline-detail-open-$id-$field';

  /// 一个 typed 内容字段的稳定诊断 token（design/26 §26.9）。
  ///
  /// 展示层按钮 key 与 Driver 投影共用这一个入口：不按 `record.toString()`、类型名或两份
  /// switch 镜像生成身份。同类字段靠判别分支 + 逻辑索引区分，独立解码的同值字段得到同一
  /// token；问答的 header/question/answer/option 各自独立，不折叠成同一个 `user-input-N`。
  static String timelineDetailField(ThreadContentFieldView field) =>
      switch (field) {
        ThreadTextFieldView() => 'text',
        ThreadThinkingSummaryFieldView(:final chunkIndex) =>
          'thinking-summary-$chunkIndex',
        ThreadThinkingContentFieldView(:final chunkIndex) =>
          'thinking-content-$chunkIndex',
        ThreadToolArgumentsFieldView() => 'tool-arguments',
        ThreadToolResultFieldView() => 'tool-result',
        ThreadToolOutputArtifactsFieldView() => 'tool-artifacts',
        ThreadPlanDocumentFieldView() => 'plan-document',
        ThreadPlanFeedbackFieldView() => 'plan-feedback',
        ThreadRawPayloadFieldView(:final payloadIndex) =>
          'raw-payload-$payloadIndex',
        ThreadToolUserInputFieldView(:final questionIndex, :final part) =>
          'user-input-$questionIndex-${userInputPartToken(part)}',
      };

  /// 问答正文域的一段：与后端 `BridgeThreadUserInputFieldPart` 一一对应。
  static String userInputPartToken(ThreadUserInputFieldPartView part) =>
      switch (part) {
        ThreadUserInputHeaderFieldPartView() => 'header',
        ThreadUserInputQuestionFieldPartView() => 'question',
        ThreadUserInputAnswerFieldPartView(:final answerIndex) =>
          'answer-$answerIndex',
        ThreadUserInputOptionLabelFieldPartView(:final optionIndex) =>
          'option-label-$optionIndex',
        ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) =>
          'option-description-$optionIndex',
      };

  /// 统一“添加账号”入口的模板选择器与选项。
  ///
  /// ACP 与 Native 共用这一个入口：选项身份来自 typed 模板（Native 模板 id 或 ACP
  /// provider wire 值），不按显示名生成；`account-add` 仍是入口按钮的稳定键。
  static const accountTemplatePicker = 'account-template-picker';
  static String accountTemplateOption(String token) =>
      'account-template-option-$token';

  /// 模板选择器里**有界滚动列表**的稳定键：Driver 用官方滚动能力把目标选项真正
  /// 滚入视口后再拍摄/点击，不靠坐标或“元素存在”冒充可见。
  static const accountTemplateList = 'account-template-list';

  /// Native 账号 Base URL 输入控件本体：宽窄变化后要读真实文本验证草稿保留。
  static const accountBaseUrlInput = 'account-base-url-input';

  /// ACP 接入表单与认证状态的稳定键。
  ///
  /// 表单主操作沿用通用 `account-save`（同一“添加账号”入口的保存语义），取消沿用
  /// `account-cancel`；这里只登记 ACP 专有字段与按阶段的操作入口。
  static const acpAccountName = 'acp-account-name';
  static const acpAccountBack = 'acp-account-back';
  static const acpAccountRemove = 'acp-account-remove';

  static const acpAccountInstallOpen = 'acp-account-install-open';

  /// 官方服务条款入口；后端未提供 terms_url 时界面不渲染该键。
  static const acpAccountTermsOpen = 'acp-account-terms-open';
  static const acpAccountAuthState = 'acp-account-auth-state';

  /// 详情页里默认折叠的「连接信息」（官方 `ExpansionTile`）稳定键。
  static const acpAccountConnectionInfo = 'acp-account-connection-info';
  static const acpAccountCheck = 'acp-account-check';
  static const acpAccountLogin = 'acp-account-login';
  static const acpAccountLoginMethod = 'acp-account-login-method';
  static const acpAccountCancelAuth = 'acp-account-cancel-auth';
  static const acpAccountDone = 'acp-account-done';
  static String acpAccountRow(String accountId) => 'acp-account-row-$accountId';

  /// 列表行内的命令失败摘要（按目标接入），与详情页的通知同一 typed 来源。
  static String acpAccountNotice(String accountId) =>
      'acp-account-notice-$accountId';

  /// 详情页里默认折叠的通知技术详情（后端安全原文）。
  static const acpAccountNoticeDetail = 'acp-account-notice-detail';

  static String acpAccountDetail(String accountId) =>
      'acp-account-detail-$accountId';

  /// 认证状态区域的阶段 token：`unchecked`/`checking`/`required`/`authenticating`/
  /// `verifying`/`verified`/`cancelling`/`cancelled`/`failed`。
  static String acpAccountAuthPhase(String phase) =>
      'acp-account-auth-state-$phase';

  /// ACP 官方 server 准备面板的稳定键。
  ///
  /// 主操作沿用 `acp-install-prepare`：空闲时是“下载并准备”，可重试失败后是
  /// “重试准备”，Driver 只按当前 typed 阶段判断这一次点击的语义。
  static const acpInstallPanel = 'acp-install-panel';
  static const acpInstallPrepare = 'acp-install-prepare';
  static const acpInstallCancel = 'acp-install-cancel';
  static const acpInstallUsePrepared = 'acp-install-use-prepared';
  static const acpInstallStage = 'acp-install-stage';
  static const acpInstallProgress = 'acp-install-progress';
  static const acpInstallProgressText = 'acp-install-progress-text';
  static const acpInstallPercent = 'acp-install-percent';
  static const acpInstallSpeed = 'acp-install-speed';
  static const acpInstallRetryCount = 'acp-install-retry-count';
  static const acpInstallVersion = 'acp-install-version';
  static const acpInstallTarget = 'acp-install-target';
  static const acpInstallFailure = 'acp-install-failure';
  static const acpInstallReadyBadge = 'acp-install-ready';
  static const acpInstallReusedBadge = 'acp-install-reused';
}
